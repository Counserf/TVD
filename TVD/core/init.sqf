#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации TVD

// Локальные переменные для инициализации сторон и обработки данных
private ["_i", "_ownerSide", "_unitSide"];

// Чтение сторон из mission_parameters.hpp с поддержкой INDEPENDENT как самостоятельной стороны
private _blueforSideRaw = missionNamespace getVariable ["blueforSide", "WEST"]; // Сырое значение bluefor из параметров миссии
private _opforSideRaw = missionNamespace getVariable ["opforSide", "EAST"]; // Сырое значение opfor из параметров миссии

// Преобразование строковых значений сторон в типы side для использования в скриптах
private _blueforSide = _blueforSideRaw call BIS_fnc_sideType; // Преобразование bluefor в side (west, east, resistance)
private _opforSide = _opforSideRaw call BIS_fnc_sideType; // Преобразование opfor в side (west, east, resistance)

// Защита от некорректных или пустых значений сторон в mission_parameters.hpp
if (isNil "_blueforSide" || {!(_blueforSide in [west, east, resistance, civilian])}) then {
    diag_log format [localize "STR_TVD_Init_InvalidBlueforSide", _blueforSideRaw]; // Логирование ошибки bluefor и установка по умолчанию
    _blueforSide = west;
};
if (isNil "_opforSide" || {!(_opforSide in [west, east, resistance, civilian])}) then {
    diag_log format [localize "STR_TVD_Init_InvalidOpforSide", _opforSideRaw]; // Логирование ошибки opfor и установка по умолчанию
    _opforSide = east;
};

// Установка основных сторон конфликта
TVD_Sides = [_blueforSide, _opforSide]; // Массив сторон [blueforSide, opforSide]

// Определение союзников для каждой стороны с учётом BIS_fnc_friendlySides
TVD_BueforAllies = [TVD_Sides select 0]; // Основная сторона bluefor и её союзники
TVD_OpforAllies = [TVD_Sides select 1];   // Основная сторона opfor и её союзники
{
    if (_x in ([TVD_Sides select 0] call BIS_fnc_friendlySides) && _x != TVD_Sides select 0) then {
        TVD_BueforAllies pushBack _x; // Добавляем союзника к bluefor
    };
    if (_x in ([TVD_Sides select 1] call BIS_fnc_friendlySides) && _x != TVD_Sides select 1) then {
        TVD_OpforAllies pushBack _x; // Добавляем союзника к opfor
    };
} forEach [west, east, resistance]; // Проверка всех возможных сторон

// Логирование для отладки: вывод сторон и их союзников
diag_log format [localize "STR_TVD_Init_BlueforSide", TVD_Sides select 0, TVD_BueforAllies]; // Лог bluefor и союзников
diag_log format [localize "STR_TVD_Init_OpforSide", TVD_Sides select 1, TVD_OpforAllies]; // Лог opfor и союзников

// Переопределение параметров миссии из аргументов, если они переданы при вызове
if !(_this isEqualType []) then { 
    _this = []; 
    diag_log localize "STR_TVD_Init_InvalidArguments"; // Логирование ошибки аргументов
};
TVD_Sides = _this param [0, TVD_Sides]; // Основные стороны конфликта (blueforSide, opforSide)
TVD_CapZonesCount = _this param [1, TVD_CapZonesCount]; // Количество зон захвата
TVD_RetreatPossible = _this param [2, TVD_RetreatPossible]; // Разрешение отступления
TVD_ZoneGain = _this param [3, TVD_ZoneGain]; // Очки за зону
TVD_RetreatRatio = _this param [4, TVD_RetreatRatio]; // Порог отступления

// Инициализация глобальных переменных состояния миссии
TVD_capZones = [];                    // Список зон захвата [маркер, сторона, блокировка]
TVD_InitScore = [0, 0, 0];            // Начальные очки сторон (bluefor, opfor, neutral)
TVD_ValUnits = [];                    // Список ценных юнитов (техника, КС, КО)
TVD_TaskObjectsList = [0, 0];         // Счётчики задач для сторон (bluefor, opfor)
TVD_SoldierCost = TVD_SoldierCost;    // Стоимость солдата из config.sqf
TVD_RetrCount = [0, 0];               // Счётчик отступлений сторон (bluefor, opfor)
TVD_SidesInfScore = [0, 0];           // Очки за пехоту
TVD_SidesValScore = [0, 0];           // Очки за ценные юниты
TVD_SidesZonesScore = [0, 0];         // Очки за зоны
TVD_SidesResScore = [0, 0];           // Очки за резервы
timeToEnd = -1;                       // Время до конца миссии (-1 = не завершена)
TVD_HeavyLosses = sideLogic;          // Сторона с тяжёлыми потерями (по умолчанию нейтральная)
TVD_MissionComplete = sideLogic;      // Сторона, завершившая миссию (по умолчанию нейтральная)
TVD_SideCanRetreat = [false, false];  // Разрешение отступления для сторон (bluefor, opfor)
TVD_SideRetreat = sideLogic;          // Сторона, которая отступила
TVD_GroupList = [];                   // Список групп игроков [имя, сторона, юниты]
TVD_MissionLog = [];                  // Лог событий миссии
TVD_PlayableUnits = [];               // Список игровых юнитов
TVD_StaticWeapons = [];               // Список статичного оружия
TVD_BlueforPlayers = allPlayers select {side group _x in TVD_BueforAllies}; // Кэширование игроков bluefor
TVD_OpforPlayers = allPlayers select {side group _x in TVD_OpforAllies};   // Кэширование игроков opfor

// Инициализация куратора и накопления логов на сервере
if (isServer) then {
    if (isNil "TVD_PendingLogs") then { TVD_PendingLogs = []; }; // Создание массива для логов, если куратора нет

    // Функция для обновления куратора (администратора, получающего логи)
    TVD_updateCurator = {
        private _admins = allPlayers select {isPlayer _x && {serverCommandAvailable "#kick"}}; // Все текущие администраторы
        private _oldCurator = TVD_Curator;
        if (_admins isEqualTo []) then {
            TVD_Curator = objNull; // Нет администраторов
        } else {
            if (isNull TVD_Curator || !(TVD_Curator in _admins)) then { // Если куратор не админ
                TVD_Curator = _admins select 0; // Первый администратор становится куратором
                if (!isNull TVD_Curator && _oldCurator != TVD_Curator && !isNil "TVD_PendingLogs" && {count TVD_PendingLogs > 0}) then {
                    TVD_PendingLogs remoteExec ["TVD_logCurator", TVD_Curator]; // Отправка накопленных логов
                    TVD_PendingLogs = []; // Очистка после отправки
                };
            };
        };
        publicVariable "TVD_Curator"; // Синхронизация куратора
    };

    [] call TVD_updateCurator; // Изначальная установка куратора

    // Обработка подключения и отключения игроков для обновления куратора
    addMissionEventHandler ["PlayerConnected", {[] call TVD_updateCurator;}];
    addMissionEventHandler ["PlayerDisconnected", {
        params ["_id", "_uid", "_name", "_jip", "_owner"];
        if (_uid == getPlayerUID TVD_Curator) then { [] call TVD_updateCurator; }; // Обновление куратора при отключении текущего
    }];

    // Периодическая проверка администраторов (каждые 10 секунд)
    [CBA_fnc_addPerFrameHandler, {
        if (count allPlayers > 0) then { [] call TVD_updateCurator; }; // Если есть игроки, проверяем куратора
    }, 10] call CBA_fnc_addPerFrameHandler;
};

// Привязка базовых триггеров к основным сторонам (TVD_Sides)
if (!isNull trgBase_side0) then {trgBase_side0 setVariable ["TVD_BaseSide", TVD_Sides select 0, true]}; // База bluefor
if (!isNull trgBase_side1) then {trgBase_side1 setVariable ["TVD_BaseSide", TVD_Sides select 1, true]}; // База opfor

// Сбор статичного оружия на карте для последующего использования
TVD_StaticWeapons = vehicles select {_x isKindOf "StaticWeapon"};

// Ожидание начала миссии (асинхронное выполнение после старта)
[{(time > 0)}, {
    // Синхронизация ключевых переменных на сервере для мультиплеера
    if (isServer) then {
        publicVariable "TVD_Sides";           // Основные стороны (blueforSide, opforSide)
        publicVariable "TVD_BueforAllies";   // Союзники bluefor
        publicVariable "TVD_OpforAllies";     // Союзники opfor
        publicVariable "TVD_RetreatPossible"; // Разрешение отступления
        publicVariable "TVD_SideCanRetreat";  // Разрешение отступления для сторон
        publicVariable "timeToEnd";           // Время до конца миссии
        publicVariable "TVD_BlueforPlayers";  // Синхронизация кэшированных списков bluefor
        publicVariable "TVD_OpforPlayers";    // Синхронизация кэшированных списков opfor
    };
    
    // Присвоение идентификаторов группам и назначение ценности КС и КО
    private _groupMap = createHashMap; // Хэш-карта для хранения групп и их идентификаторов
    private _sideLeaders = [TVD_BlueforPlayers select 0, TVD_OpforPlayers select 0]; // Список КС для обеих сторон (первые слоты)
    {
        private _side = side _x; // Сторона игрока
        if (_side in (TVD_BueforAllies + TVD_OpforAllies)) then { // Проверка, принадлежит ли игрок к сторонам конфликта
            private _group = group _x; // Группа игрока
            private _groupStr = str _group splitString " "; // Разделение строки группы на части (например, "Alpha 1-1")
            private _prefix = switch (_groupStr select 1) do { // Префикс группы (A, B, C, D)
                case "Alpha": {"A"};
                case "Bravo": {"B"};
                case "Charlie": {"C"};
                case "Delta": {"D"};
                default {""};
            };
            private _grId = format ["%1%2:%3", _prefix, _groupStr select 2, (units _group find _x) + 1]; // Формат ID группы: A1:1
            _x setVariable ["TVD_GroupID", _grId, true]; // Установка ID группы для юнита
            _groupMap set [_group, _grId]; // Сохранение группы в хэш-карту
            
            // Назначение КС (первый слот стороны)
            if (_x == (_side call {if (_this in TVD_BueforAllies) then {TVD_BlueforPlayers select 0} else {TVD_OpforPlayers select 0}})) then {
                _x setVariable ["TVD_UnitValue", [_side, 50, "sideLeader"], true]; // КС получает 50 очков и роль "sideLeader"
            } else {
                // Назначение КО (командиров отделений) для лидеров групп, кроме КС
                if (_x == leader _group && !(_x in _sideLeaders)) then {
                    _x setVariable ["TVD_UnitValue", [_side, 25, "squadLeader"], true]; // КО получает 25 очков и роль "squadLeader"
                };
            };
        };
    } forEach allPlayers;

    // Ожидание окончания заморозки миссии (a3a_var_started)
    [CBA_fnc_waitUntilAndExecute, {(missionNamespace getVariable ["a3a_var_started", false])}, {
        // Формирование списка групп с учётом союзников
        private _allGroups = allGroups select {(count units _x > 0) && (side _x in (TVD_BueforAllies + TVD_OpforAllies))}; // Все активные группы сторон
        TVD_GroupList = _allGroups apply {[str _x, side _x, units _x]}; // Массив: [имя, сторона, юниты]
        {
            private _groupData = _x;
            {   
                _x setVariable ["TVD_Group", _groupData, true]; // Привязка юнита к группе
                if (_x == leader _x) then {_x setVariable ["TVD_GroupLeader", true, true]}; // Отметка лидера группы
            } forEach (_groupData select 2); // Применение к каждому юниту группы
        } forEach TVD_GroupList;

        // Логирование списка игровых юнитов на сервере
        if (isServer) then {
            TVD_PlayableUnits = allPlayers apply {str _x}; // Список всех игроков в виде строк
            ["init", format [localize "STR_TVD_Init_PlayableUnits", TVD_PlayableUnits joinString ", "]] call TVD_logEvent; // Логирование списка юнитов
            if (!isNull TVD_Curator) then {
                ["TVD_InitLog", TVD_PlayableUnits] call CBA_fnc_targetEvent; // Отправка лога куратору
            };
        };

        // Инициализация зон захвата на основе TVD_CapZonesCount
        if (TVD_CapZonesCount > 0) then {
            private _logics = allMissionObjects "Logic"; // Все логические объекты миссии
            for "_i" from 0 to (TVD_CapZonesCount - 1) do { // Цикл по количеству зон
                private _markerName = format ["mZone_%1", _i]; // Имя маркера зоны (mZone_0, mZone_1 и т.д.)
                private _lock = _logics findIf {_x getVariable ["Marker", "false"] == _markerName} != -1; // Проверка блокировки зоны
                TVD_capZones pushBack [_markerName, getMarkerColor _markerName call TVD_colorToSide, _lock]; // [имя маркера, сторона, блокировка]
            };
        };

        // Подсчёт начальных очков за зоны с учётом союзников
        {
            private _side = _x select 1; // Сторона, владеющая зоной
            private _index = if (_side in TVD_BueforAllies) then {0} else {if (_side in TVD_OpforAllies) then {1} else {2}}; // Индекс стороны
            TVD_InitScore set [_index, (TVD_InitScore select _index) + TVD_ZoneGain]; // Добавление очков за зону
        } forEach TVD_capZones;

        // Составление списка задач из объектов миссии
        private _allObjects = allMissionObjects ""; // Все объекты миссии
        TVD_TaskObjectsList = _allObjects select {
            private _taskData = _x getVariable ["TVD_TaskObject", nil]; // Данные задачи объекта
            if (!isNil "_taskData") then {
                if (count _taskData < 4) then {_taskData pushBack true}; // Добавление статуса задачи, если его нет
                if (count _taskData < 5) then {_taskData pushBack ["false", "false", "false", "false"]; _taskData pushBack false}; // Условия и флаг ключа
                _x setVariable ["TVD_TaskObject", _taskData, true]; // Обновление данных задачи
                _x setVariable ["TVD_TaskObjectStatus", "", true]; // Установка статуса задачи
                true
            } else {false};
        };

        // Подсчёт очков за юниты и технику без ручной настройки TVD_UnitValue
        private _allUnits = allUnits + vehicles; // Все юниты и техника на карте
        {
            private _side = side _x; // Сторона юнита по умолчанию
            private _wmtSide = _x getVariable ["WMT_Side", sideLogic]; // Проверка WMT_Side для техники/контейнеров
            if (_wmtSide != sideLogic) then {_side = _wmtSide}; // Переопределение стороны, если задано WMT_Side
            
            if (_side in (TVD_BueforAllies + TVD_OpforAllies) || _x in vehicles) then { // Проверка принадлежности к сторонам или технике
                private _unitValue = _x getVariable ["TVD_UnitValue", []]; // Существующие значения TVD_UnitValue (для КС/КО уже задано выше)
                private _isValuable = _unitValue isNotEqualTo []; // Проверка, является ли юнит ценным
                
                if (_isValuable) then { // Уже заданные КС, КО или техника
                    _unitSide = if (_unitValue select 0 in TVD_BueforAllies) then {0} else {if (_unitValue select 0 in TVD_OpforAllies) then {1} else {2}}; // Индекс стороны
                    TVD_InitScore set [_unitSide, (TVD_InitScore select _unitSide) + (_unitValue select 1)]; // Добавление начальных очков
                    TVD_ValUnits pushBack _x; // Добавление в список ценных юнитов
                    
                    if (_unitValue select 2 == "sideLeader" && (_unitValue select 0 in TVD_Sides)) then {
                        [_x, "mpkilled", ["TVD_hqTransfer", ["slTransfer", _x]]] remoteExec ["call", 2]; // Передача командования при смерти КС на сервере
                    };
                    [_x, "mpkilled", ["TVD_logEvent", ["killed", _x]]] remoteExec ["call", 2]; // Логирование смерти юнита на сервере
                } else {
                    if (_x in vehicles) then { // Техника определяется автоматически
                        private _vehicleSide = _side; // Сторона техники из редактора или WMT_Side
                        private _crew = crew _x; // Экипаж техники
                        if (_crew isNotEqualTo []) then {
                            _vehicleSide = side (_crew select 0); // Если есть экипаж, используем его сторону
                        };
                        if (_vehicleSide in TVD_BueforAllies || _vehicleSide in TVD_OpforAllies) then { // Проверка принадлежности к сторонам
                            private _isArmed = count (weapons _x) > 0; // Проверка наличия вооружения
                            private _value = switch (true) do { // Оценка ценности техники по типу и вооружению
                                case (_x isKindOf "Airplane" && _isArmed): {150}; // Вооружённые самолёты - 150 очков
                                case (_x isKindOf "Airplane"): {75};              // Невооружённые самолёты - 75 очков
                                case (_x isKindOf "Tank" && _isArmed): {100};     // Вооружённая гусеничная техника - 100 очков
                                case (_x isKindOf "Tank"): {40};                  // Невооружённая гусеничная техника - 40 очков
                                case (_x isKindOf "Helicopter" && _isArmed): {100}; // Вооружённые вертолёты - 100 очков
                                case (_x isKindOf "Helicopter"): {50};            // Невооружённые вертолёты - 50 очков
                                case (_x isKindOf "Car" && _isArmed): {60};       // Вооружённая колёсная техника - 60 очков
                                case (_x isKindOf "Car"): {30};                   // Невооружённая колёсная техника - 30 очков
                                case (_x isKindOf "Ship" && _isArmed): {50};      // Вооружённые лодки - 50 очков
                                case (_x isKindOf "Ship"): {20};                  // Невооружённые лодки - 20 очков
                                case (_x isKindOf "StaticWeapon"): {30};          // Статичное оружие - 30 очков
                                default {25};                                     // Прочая техника - 25 очков
                            };
                            _unitSide = if (_vehicleSide in TVD_BueforAllies) then {0} else {1}; // Индекс стороны (0 - bluefor, 1 - opfor)
                            _x setVariable ["TVD_UnitValue", [_vehicleSide, _value, "vehicle"], true]; // Автоматическое задание ценности техники
                            TVD_InitScore set [_unitSide, (TVD_InitScore select _unitSide) + _value]; // Добавление начальных очков за технику
                            TVD_ValUnits pushBack _x; // Добавление в список ценных юнитов
                            _x setVariable ["TVD_CapOwner", _vehicleSide, true]; // Начальный владелец техники
                            _x setVariable ["TVD_SentToRes", 0, true]; // Флаг отправки в резерв
                            _x addEventHandler ["GetIn", {[_this select 0, _this select 2] call TVD_captureVehicle}]; // Обработчик захвата техники
                            [_x, "mpkilled", ["TVD_logEvent", ["killed", _x]]] remoteExec ["call", 2]; // Логирование уничтожения техники на сервере
                        };
                    } else { // Обычные солдаты (не КС, не КО, не техника)
                        _unitSide = if (_side in TVD_BueforAllies) then {0} else {if (_side in TVD_OpforAllies) then {1} else {2}}; // Индекс стороны
                        TVD_InitScore set [_unitSide, (TVD_InitScore select _unitSide) + TVD_SoldierCost]; // Добавление очков за обычного солдата
                    };
                };
            };
        } forEach _allUnits;
        
        // Синхронизация списка ценных юнитов на сервере
        if (isServer) then {publicVariable "TVD_ValUnits"};

        // Подключение клиентского интерфейса администратора для не-dedicated серверов
        if (!isDedicated) then {
            call compile preprocessFileLineNumbers "TVD\client\admin_menu.sqf"; // Загрузка интерфейса администратора
        };
    }] call CBA_fnc_waitUntilAndExecute; // Ожидание окончания заморозки миссии
}] call CBA_fnc_waitUntilAndExecute; // Ожидание начала миссии