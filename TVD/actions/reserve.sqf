#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_BaseTriggers и т.д.)

/*
 * Отправляет юнит (технику или пехотинца) в резерв с уведомлением и удалением
 * Параметры:
 *   _target: объект - юнит или техника для отправки
 *   _caller: объект - игрок, инициирующий действие
 */
TVD_sendToReserve = {
    params ["_target", "_caller"];
    if (isNull _target || isNull _caller) exitWith {diag_log "TVD_sendToReserve: Target or caller is null";}; // Выход, если цель или вызывающий отсутствуют
    private _us = [_target] call TVD_getSideIndexFromTrigger; // Используем общую функцию для определения индекса стороны
    if (_us == -1) exitWith {diag_log "TVD_sendToReserve: Invalid side index";}; // Выход при ошибке триггера
    private _unitName = if (_target isKindOf "CAManBase") then {name _target} else {getText (configFile >> "CfgVehicles" >> typeOf _target >> "displayName")}; // Имя юнита или техники
    private _isMan = _target isKindOf "CAManBase"; // Флаг: является ли юнит пехотинцем
    
    // Обработка пехотинца
    if (_isMan) then {
        _target setVariable ["TVD_soldierSentToRes", true, true]; // Установка флага отправки в резерв с публичной синхронизацией
        private _notifyUnits = [_target, _caller, _us, true] call TVD_getNotifyUnits; // Используем общую функцию для списка уведомлений
        [_notifyUnits, format ["Пленник (%1) отправлен в тыл стороны %2.", _unitName, TVD_Sides select _us], "title"] call TVD_notifyPlayers; // Уведомление об отправке
        if (isPlayer _target) then {[_target, "Вас отправили в тыловой лагерь военно-пленных.", "dynamic"] call TVD_notifyPlayers}; // Уведомление игроку, если он является целью
    } else {
        // Исправление средней проблемы: проверка на повторную отправку техники
        if (_target getVariable ["TVD_SentToRes", 0] == 1) exitWith {
            [_caller, "Техника уже отправляется в тыл.", "title"] call TVD_notifyPlayers;
        };
        _target setVariable ["TVD_SentToRes", 1, true]; // Установка флага начала отправки в резерв
        private _notifyUnits = [_target, _caller, _us, true] call TVD_getNotifyUnits; // Используем общую функцию для списка уведомлений
        [_notifyUnits, format ["%1 - начата отправка в тыл...", _unitName], "title"] call TVD_notifyPlayers; // Уведомление о начале отправки
        
        // Асинхронная обработка отправки техники с визуальными эффектами и таймером
        [_target, _unitName, _us] spawn {
            params ["_target", "_unitName", "_us"];
            private _startTime = diag_tickTime; // Начальное время для отсчёта 3-минутного периода
            private _trig = false; // Флаг активации дымовой завесы
            
            // Проверка состояния техники каждую секунду
            [CBA_fnc_addPerFrameHandler, {
                params ["_args", "_handle"];
                _args params ["_target", "_unitName", "_us", "_startTime", "_trig"];
                
                private _waitTime = diag_tickTime - _startTime; // Прошедшее время с начала отправки
                if (({alive _x} count crew _target > 0) || !alive _target) exitWith { // Прерывание, если экипаж жив или техника уничтожена
                    _target setVariable ["TVD_SentToRes", 0, true]; // Сброс флага отправки
                    private _notifyUnits = [_target, objNull, _us, true] call TVD_getNotifyUnits; // Используем общую функцию
                    [_notifyUnits, format ["%1 - отправка в тыл отменена.", _unitName], "title"] call TVD_notifyPlayers; // Уведомление об отмене
                    [_handle] call CBA_fnc_removePerFrameHandler; // Завершение обработчика
                };
                
                // Создание дымовой завесы через 2.5 минуты для визуального эффекта
                if (_waitTime > 150 && !_trig) then {
                    "SmokeShellRed" createVehicle getPosATL _target; // Красный дым на позиции техники
                    _trig = true; // Установка флага, чтобы дым не создавался повторно
                };
                
                // Завершение отправки через 3 минуты
                if (_waitTime > 180) exitWith {
                    private _originalUs = TVD_Sides find (_target getVariable "TVD_UnitValue" select 0); // Индекс изначальной стороны техники
                    private _amount = if (_us != _originalUs) then {(_target getVariable ["TVD_UnitValue", [nil, 0]] select 1) / 2} else {_target getVariable ["TVD_UnitValue", [nil, 0]] select 1}; // Очки за технику: 50% при захвате
                    
                    TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв (инициализация в init.sqf)
                    private _unitValue = _target getVariable ["TVD_UnitValue", []];
                    if (!(_unitValue isEqualTo [])) then {_target setVariable ["TVD_UnitValue", nil, true]}; // Очистка данных юнита, если они есть
                    private _index = TVD_ValUnits find _target;
                    if (_index != -1) then {TVD_ValUnits deleteAt _index}; // Удаление из списка ценных юнитов
                    ["TVD_ReserveUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация очков через CBA-ивент
                    
                    private _notifyUnits = [_target, objNull, _us, true] call TVD_getNotifyUnits; // Используем общую функцию
                    [_notifyUnits, format ["%1 - успешно отправлен в тыл.", _unitName], "title"] call TVD_notifyPlayers; // Уведомление об успешной отправке
                    
                    [_target] call TVD_safeDelete; // Используем общую функцию удаления без проверки экипажа
                    ["sentToRes", _target, _us] call TVD_logEvent; // Логирование события отправки
                    [_handle] call CBA_fnc_removePerFrameHandler; // Завершение обработчика
                };
            }, 1, [_target, _unitName, _us, _startTime, _trig]] call CBA_fnc_addPerFrameHandler; // Проверка каждую секунду
        };
    };
    
    // Обработка пехотинца на сервере
    if (isServer && _isMan) then {
        if (isNil "TVD_SidesResScore") then { TVD_SidesResScore = [0, 0]; }; // Инициализация TVD_SidesResScore, если она отсутствует
        private _unitValue = _target getVariable ["TVD_UnitValue", []];
        private _amount = if (!(_unitValue isEqualTo [])) then {_unitValue select 1} else {TVD_SoldierCost}; // Ценность юнита: из TVD_UnitValue или по умолчанию
        TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв
        ["TVD_ReserveUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация очков через CBA-ивент
        
        _target setDamage 1; // Уничтожение юнита
        [_target] call TVD_safeDelete; // Используем общую функцию удаления
        
        private _passData = [_unitName, side group _target, if (count _unitValue > 2) then {(_unitValue select 2) call TVD_unitRole} else {""}, _target getVariable ["TVD_GroupID", ""]]; // Данные для лога
        ["sentToResMan", _passData] call TVD_logEvent; // Логирование события отправки пехотинца
    };
};

// Синхронизация очков резерва через CBA-ивент (инициализация один раз на сервере)
if (isServer && isNil "TVD_ReserveUpdateEH") then {
    TVD_ReserveUpdateEH = ["TVD_ReserveUpdate", { // Обработчик события обновления резерва
        params ["_us", "_amount"];
        if (_us >= 0 && _us < count TVD_SidesResScore) then { // Проверка корректности индекса стороны
            TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Обновление очков резерва на всех клиентах
        };
    }] call CBA_fnc_addEventHandler;
};

/*
 * Получает список игроков для уведомлений
 * Параметры:
 *   _target: объект - цель уведомления
 *   _caller: объект (опционально) - инициатор действия
 *   _us: число (опционально) - индекс стороны
 *   _includeLeaders: логическое (опционально) - включать ли КС и КО
 */
TVD_getNotifyUnits = {
    params ["_target", ["_caller", objNull], ["_us", -1], ["_includeLeaders", false]];
    private _notifyUnits = (ASLToAGL getPosASL _target nearEntities ["CAManBase", 50]) select {isPlayer _x};
    if (!isNull _caller) then { _notifyUnits pushBackUnique _caller; };
    if (_includeLeaders && _us != -1) then {
        _notifyUnits append (allPlayers select {side group _x in ([TVD_Sides select _us] call BIS_fnc_friendlySides) && {(_x getVariable ["TVD_UnitValue", []]) param [2, ""] in ["sideLeader", "execSideLeader", "squadLeader"]}});
    };
    _notifyUnits pushBackUnique TVD_Curator;
    _notifyUnits
};

/*
 * Безопасно удаляет объект с задержкой
 * Параметры:
 *   _object: объект - объект для удаления
 */
TVD_safeDelete = {
    params ["_object"];
    sleep 2;
    if (!isNull _object) then {deleteVehicle _object}; // Убрана проверка экипажа по вашему требованию
};

/*
 * Возвращает индекс стороны по триггеру базы
 * Параметры:
 *   _target: объект - объект для проверки
 * Возвращает: число - индекс стороны (0 или 1) или -1 при ошибке
 */
TVD_getSideIndexFromTrigger = {
    params ["_target"];
    if (isNil "TVD_BaseTriggers") exitWith {diag_log "TVD: TVD_BaseTriggers not defined"; -1};
    if (!isNull (TVD_BaseTriggers select 0) && {_target in list (TVD_BaseTriggers select 0)}) then {0} else {1}
};