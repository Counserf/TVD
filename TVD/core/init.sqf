#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации TVD

// Локальные переменные для инициализации
private ["_i", "_ownerSide", "_unitSide"];

// Чтение сторон из mission_parameters.hpp с поддержкой INDEPENDENT
private _blueforSideRaw = missionNamespace getVariable ["blueforSide", "WEST"];
private _opforSideRaw = missionNamespace getVariable ["opforSide", "EAST"];

// Преобразование строк в типы сторон
private _blueforSide = _blueforSideRaw call BIS_fnc_sideType;
private _opforSide = _opforSideRaw call BIS_fnc_sideType;

// Защита от некорректных или пустых значений
if (isNil "_blueforSide" || {!(_blueforSide in [west, east, resistance, civilian])}) then {
    diag_log format ["TVD Warning: Invalid blueforSide '%1'. Defaulting to WEST.", _blueforSideRaw];
    _blueforSide = west;
};
if (isNil "_opforSide" || {!(_opforSide in [west, east, resistance, civilian])}) then {
    diag_log format ["TVD Warning: Invalid opforSide '%1'. Defaulting to EAST.", _opforSideRaw];
    _opforSide = east;
};

// Установка основных сторон (могут быть west, east или resistance)
TVD_Sides = [_blueforSide, _opforSide];

// Определение союзников для каждой стороны
TVD_BueforAllies = [TVD_Sides select 0]; // Основная сторона bluefor и её союзники
TVD_OpforAllies = [TVD_Sides select 1];    // Основная сторона opfor и её союзники

// Проверка всех сторон на союз с bluefor или opfor (оптимизировано)
{
    if (_x in ([TVD_Sides select 0] call BIS_fnc_friendlySides) && _x != TVD_Sides select 0) then {
        TVD_BueforAllies pushBack _x; // Добавляем союзника к bluefor
    };
    if (_x in ([TVD_Sides select 1] call BIS_fnc_friendlySides) && _x != TVD_Sides select 1) then {
        TVD_OpforAllies pushBack _x; // Добавляем союзника к opfor
    };
} forEach [west, east, resistance];

// Логирование для отладки
diag_log format ["TVD Init: Bluefor Side = %1, Allies = %2", TVD_Sides select 0, TVD_BueforAllies];
diag_log format ["TVD Init: Opfor Side = %1, Allies = %2", TVD_Sides select 1, TVD_OpforAllies];

// Переопределение параметров миссии из аргументов (если вызвано с параметрами)
if !(_this isEqualType []) then { _this = []; diag_log "TVD/init.sqf: Arguments invalid, using defaults"; };
TVD_Sides = _this param [0, TVD_Sides];           // Основные стороны конфликта (blueforSide, opforSide)
TVD_CapZonesCount = _this param [1, TVD_CapZonesCount]; // Количество зон захвата
TVD_RetreatPossible = _this param [2, TVD_RetreatPossible]; // Разрешение отступления
TVD_ZoneGain = _this param [3, TVD_ZoneGain];     // Очки за зону
TVD_RetreatRatio = _this param [4, TVD_RetreatRatio]; // Порог отступления

// Инициализация глобальных переменных состояния миссии
TVD_capZones = [];                    // Список зон захвата [маркер, сторона, блокировка]
TVD_InitScore = [0, 0, 0];            // Начальные очки сторон (bluefor, opfor, neutral)
TVD_ValUnits = [];                    // Список ценных юнитов (техника, командиры)
TVD_TaskObjectsList = [0, 0];         // Счётчики задач для сторон (bluefor, opfor)
TVD_SoldierCost = TVD_SoldierCost;    // Стоимость солдата из config.sqf
TVD_RetrCount = [0, 0];               // Счётчик отступлений сторон (bluefor, opfor)
TVD_SidesInfScore = [0, 0];           // Очки за пехоту
TVD_SidesValScore = [0, 0];           // Очки за ценные юниты
TVD_SidesZonesScore = [0, 0];         // Очки за зоны
TVD_SidesResScore = [0, 0];           // Очки за резервы
timeToEnd = -1;                       // Время до конца миссии (-1 = не завершена)
TVD_TimeExtendPossible = false;       // Возможность продления времени
TVD_HeavyLosses = sideLogic;          // Сторона с тяжёлыми потерями (по умолчанию нейтральная)
TVD_MissionComplete = sideLogic;      // Сторона, завершившая миссию (по умолчанию нейтральная)
TVD_SideCanRetreat = [false, false];  // Разрешение отступления для сторон (bluefor, opfor)
TVD_SideRetreat = sideLogic;          // Сторона, которая отступила
TVD_GroupList = [];                   // Список групп игроков [имя, сторона, юниты]
TVD_MissionLog = [];                  // Лог событий миссии
TVD_PlayableUnits = [];               // Список игровых юнитов
TVD_StaticWeapons = [];               // Список статичного оружия

// Инициализация куратора и накопления логов на сервере
if (isServer) then {
    // Создание массива для хранения логов до появления администратора
    if (isNil "TVD_PendingLogs") then { TVD_PendingLogs = []; };

    // Функция для обновления куратора
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

    // Изначальная установка куратора
    [] call TVD_updateCurator;

    // Обработка подключения игроков
    addMissionEventHandler ["PlayerConnected", {[] call TVD_updateCurator;}];

    // Обработка отключения игроков
    addMissionEventHandler ["PlayerDisconnected", {
        params ["_id", "_uid", "_name", "_jip", "_owner"];
        if (_uid == getPlayerUID TVD_Curator) then { [] call TVD_updateCurator; }; // Обновление куратора при отключении текущего
    }];

    // Периодическая проверка администраторов
    [CBA_fnc_addPerFrameHandler, {
        if (count allPlayers > 0) then { [] call TVD_updateCurator; }; // Если есть игроки, проверяем куратора
    }, 10] call CBA_fnc_addPerFrameHandler; // Каждые 10 секунд
};

// Привязка базовых триггеров к основным сторонам (TVD_Sides)
if (!isNull trgBase_side0) then {trgBase_side0 setVariable ["TVD_BaseSide", TVD_Sides select 0, true]}; // Bluefor
if (!isNull trgBase_side1) then {trgBase_side1 setVariable ["TVD_BaseSide", TVD_Sides select 1, true]}; // Opfor

// Сбор статичного оружия на карте
TVD_StaticWeapons = vehicles select {_x isKindOf "StaticWeapon"};

// Ожидание начала миссии (асинхронное выполнение после старта)
[{(time > 0)}, {
    // Синхронизация ключевых переменных на сервере
    if (isServer) then {
        publicVariable "TVD_Sides";           // Основные стороны (blueforSide, opforSide)
        publicVariable "TVD_BueforAllies";   // Союзники bluefor
        publicVariable "TVD_OpforAllies";     // Союзники opfor
        publicVariable "TVD_RetreatPossible"; // Разрешение отступления
        publicVariable "TVD_SideCanRetreat";  // Разрешение отступления для сторон
        publicVariable "timeToEnd";           // Время до конца миссии
    };
    
    // Присвоение идентификаторов группам с учётом всех участвующих сторон
    private _groupMap = createHashMap;
    {
        private _side = side _x;
        if (_side in (TVD_BueforAllies + TVD_OpforAllies)) then {
            private _group = group _x;
            private _groupStr = str _group splitString " ";
            private _prefix = switch (_groupStr select 1) do { // Префикс группы (A, B, C, D)
                case "Alpha": {"A"};
                case "Bravo": {"B"};
                case "Charlie": {"C"};
                case "Delta": {"D"};
                default {""};
            };
            private _grId = format ["%1%2:%3", _prefix, _groupStr select 2, (units _group find _x) + 1]; // Формат: A1:1
            _x setVariable ["TVD_GroupID", _grId, true];
            _groupMap set [_group, _grId];
        };
    } forEach allPlayers;

    // Ожидание окончания заморозки миссии
    [CBA_fnc_waitUntilAndExecute, {(missionNamespace getVariable ["a3a_var_started", false])}, {
        // Формирование списка групп с учётом союзников (упрощённый цикл)
        private _allGroups = allGroups select {(count units _x > 0) && (side _x in (TVD_BueforAllies + TVD_OpforAllies))};
        TVD_GroupList = _allGroups apply {[str _x, side _x, units _x]}; // Массив: [имя, сторона, юниты]
        {
            private _groupData = _x;
            {   
                _x setVariable ["TVD_Group", _groupData, true]; // Привязка юнита к группе
                if (_x == leader _x) then {_x setVariable ["TVD_GroupLeader", true, true]}; // Отметка лидера
            } forEach (_groupData select 2); // Используем units из _groupData
        } forEach TVD_GroupList;

        // Логирование списка игровых юнитов
        if (isServer) then {
            TVD_PlayableUnits = allPlayers apply {str _x};
            ["init", "TVD_PlayableUnits: " + (TVD_PlayableUnits joinString ", ")] call TVD_logEvent;
            if (!isNull TVD_Curator) then {
                ["TVD_InitLog", TVD_PlayableUnits] call CBA_fnc_targetEvent; // Отправка лога куратору
            };
        };

        // Инициализация зон захвата
        if (TVD_CapZonesCount > 0) then {
            private _logics = allMissionObjects "Logic";
            for "_i" from 0 to (TVD_CapZonesCount - 1) do {
                private _markerName = format ["mZone_%1", _i];
                private _lock = _logics findIf {_x getVariable ["Marker", "false"] == _markerName} != -1;
                TVD_capZones pushBack [_markerName, getMarkerColor _markerName call TVD_colorToSide, _lock]; // [имя маркера, сторона, блокировка]
            };
        };

        // Подсчёт начальных очков за зоны с учётом союзников
        {
            private _side = _x select 1;
            private _index = if (_side in TVD_BueforAllies) then {0} else {if (_side in TVD_OpforAllies) then {1} else {2}};
            TVD_InitScore set [_index, (TVD_InitScore select _index) + TVD_ZoneGain];
        } forEach TVD_capZones;

        // Составление списка задач
        private _allObjects = allMissionObjects "";
        TVD_TaskObjectsList = _allObjects select {
            private _taskData = _x getVariable ["TVD_TaskObject", nil];
            if (!isNil "_taskData") then {
                if (count _taskData < 4) then {_taskData pushBack true}; // Статус задачи
                if (count _taskData < 5) then {_taskData pushBack ["false", "false", "false", "false"]; _taskData pushBack false}; // Условия и флаг ключа
                _x setVariable ["TVD_TaskObject", _taskData, true];
                _x setVariable ["TVD_TaskObjectStatus", "", true];
                true
            } else {false};
        };

        // Подсчёт очков за юниты и технику с учётом союзников
        private _allUnits = allUnits + vehicles;
        {
            private _side = side _x;
            if (_side in (TVD_BueforAllies + TVD_OpforAllies) || _x in vehicles) then {
                private _unitValue = _x getVariable ["TVD_UnitValue", []];
                private _isValuable = _unitValue isNotEqualTo [];
                
                if (_isValuable) then {
                    _unitSide = if (_unitValue select 0 in TVD_BueforAllies) then {0} else {if (_unitValue select 0 in TVD_OpforAllies) then {1} else {2}};
                    TVD_InitScore set [_unitSide, (TVD_InitScore select _unitSide) + (_unitValue select 1)];
                    TVD_ValUnits pushBack _x;
                    
                    if (count _unitValue < 3) then {
                        _unitValue pushBack "squadLeader";
                        _x setVariable ["TVD_UnitValue", _unitValue, true];
                    };
                    
                    // Возможности КС только для TVD_Sides
                    if (_unitValue select 2 == "sideLeader" && (_unitValue select 0 in TVD_Sides)) then {
                        [_x, "mpkilled", ["TVD_hqTransfer", ["slTransfer", _x]]] remoteExec ["call", 2]; // Передача командования
                    };
                    [_x, "mpkilled", ["TVD_logEvent", ["killed", _x]]] remoteExec ["call", 2]; // Логирование смерти
                    
                    if (_x in vehicles) then {
                        _x setVariable ["TVD_CapOwner", _unitValue select 0, true];
                        _x setVariable ["TVD_SentToRes", 0, true];
                        _x addEventHandler ["GetIn", {[_this select 0, _this select 2] call TVD_captureVehicle}]; // Захват техники
                        if (_unitValue select 1 > 1) then {
                            [_x, "mpkilled", ["TVD_logEvent", ["killed", _x]]] remoteExec ["call", 2];
                        };
                    };
                } else {
                    _unitSide = if (_side in TVD_BueforAllies) then {0} else {if (_side in TVD_OpforAllies) then {1} else {2}};
                    TVD_InitScore set [_unitSide, (TVD_InitScore select _unitSide) + TVD_SoldierCost];
                };
            };
        } forEach _allUnits;
        
        if (isServer) then {publicVariable "TVD_ValUnits"};

        // Подключение клиентского интерфейса администратора
        if (!isDedicated) then {
            call compile preprocessFileLineNumbers "TVD\client\admin_menu.sqf"; // Загрузка интерфейса администратора
        };
    }] call CBA_fnc_waitUntilAndExecute;
}] call CBA_fnc_waitUntilAndExecute;