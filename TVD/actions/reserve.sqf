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
    private _us = if (!isNull (TVD_BaseTriggers select 0) && {_target in list (TVD_BaseTriggers select 0)}) then {0} else {1}; // Индекс стороны по базе
    private _unitName = if (_target isKindOf "CAManBase") then {name _target} else {getText (configFile >> "CfgVehicles" >> typeOf _target >> "displayName")}; // Имя юнита или техники
    private _isMan = _target isKindOf "CAManBase"; // Флаг: является ли юнит пехотинцем
    
    // Обработка пехотинца
    if (_isMan) then {
        _target setVariable ["TVD_soldierSentToRes", true, true]; // Установка флага отправки
        private _notifyUnits = (ASLToAGL getPosASL _target nearEntities ["CAManBase", 50]) select {isPlayer _x}; // Ближайшие игроки в радиусе 50 метров
        _notifyUnits pushBackUnique TVD_Curator; // Добавление куратора для уведомления
        [_notifyUnits, format ["Пленник (%1) отправлен в тыл стороны %2.", _unitName, TVD_Sides select _us], "title"] call TVD_notifyPlayers; // Уведомление об отправке
        if (isPlayer _target) then {[_target, "Вас отправили в тыловой лагерь военно-пленных.", "dynamic"] call TVD_notifyPlayers}; // Уведомление игроку, если он является целью
    } else {
        // Обработка техники
        _target setVariable ["TVD_SentToRes", 1, true]; // Установка флага отправки
        private _notifyUnits = (ASLToAGL getPosASL _target nearEntities ["CAManBase", 50]) select {isPlayer _x};
        [_notifyUnits, format ["%1 - начата отправка в тыл...", _unitName], "title"] call TVD_notifyPlayers; // Уведомление о начале отправки
        
        // Асинхронная обработка отправки техники
        [_target, _unitName, _us] spawn {
            params ["_target", "_unitName", "_us"];
            private _startTime = diag_tickTime; // Начальное время для отсчёта
            private _trig = false; // Флаг дымовой завесы
            
            [CBA_fnc_addPerFrameHandler, {
                params ["_args", "_handle"];
                _args params ["_target", "_unitName", "_us", "_startTime", "_trig"];
                
                private _waitTime = diag_tickTime - _startTime; // Прошедшее время
                if (({alive _x} count crew _target > 0) || !alive _target) exitWith { // Прерывание, если экипаж жив или техника уничтожена
                    _target setVariable ["TVD_SentToRes", 0, true]; // Сброс флага отправки
                    private _notifyUnits = (ASLToAGL getPosASL _target nearEntities ["CAManBase", 50]) select {isPlayer _x};
                    [_notifyUnits, format ["%1 - отправка в тыл отменена.", _unitName], "title"] call TVD_notifyPlayers; // Уведомление об отмене
                    [_handle] call CBA_fnc_removePerFrameHandler; // Завершение обработчика
                };
                
                // Создание дымовой завесы через 2.5 минуты
                if (_waitTime > 150 && !_trig) then {
                    "SmokeShellRed" createVehicle getPosATL _target; // Создание красного дыма для визуального эффекта
                    _trig = true;
                };
                
                // Завершение отправки через 3 минуты
                if (_waitTime > 180) exitWith {
                    private _originalUs = TVD_Sides find (_target getVariable "TVD_UnitValue" select 0); // Индекс изначальной стороны
                    private _amount = if (_us != _originalUs) then {(_target getVariable ["TVD_UnitValue", [nil, 0]] select 1) / 2} else {_target getVariable ["TVD_UnitValue", [nil, 0]] select 1}; // Очки за технику (50% при захвате)
                    
                    TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв
                    private _unitValue = _target getVariable ["TVD_UnitValue", []];
                    if (_unitValue isNotEqualTo []) then {_target setVariable ["TVD_UnitValue", nil, true]}; // Очистка данных
                    private _index = TVD_ValUnits find _target;
                    if (_index != -1) then {TVD_ValUnits deleteAt _index}; // Удаление из списка ценных юнитов
                    ["TVD_ReserveUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация через CBA-ивент
                    
                    private _notifyUnits = (ASLToAGL getPosASL _target nearEntities ["CAManBase", 50]) select {isPlayer _x};
                    [_notifyUnits, format ["%1 - успешно отправлен в тыл.", _unitName], "title"] call TVD_notifyPlayers; // Уведомление об успехе
                    
                    sleep 2; // Задержка перед удалением для визуального эффекта
                    if (!isNull _target) then {deleteVehicle _target}; // Удаление техники
                    ["sentToRes", _target, _us] call TVD_logEvent; // Логирование события
                    [_handle] call CBA_fnc_removePerFrameHandler; // Завершение обработчика
                };
            }, 1, [_target, _unitName, _us, _startTime, _trig]] call CBA_fnc_addPerFrameHandler; // Проверка каждую секунду
        };
    };
    
    // Обработка пехотинца на сервере
    if (isServer && _isMan) then {
        private _unitValue = _target getVariable ["TVD_UnitValue", []];
        private _amount = if (_unitValue isNotEqualTo []) then {_unitValue select 1} else {TVD_SoldierCost}; // Ценность юнита
        TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв
        ["TVD_ReserveUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация через CBA-ивент
        
        _target setDamage 1; // Уничтожение юнита
        [_target] spawn {sleep 2; if (!isNull (_this select 0)) then {deleteVehicle (_this select 0)}}; // Асинхронное удаление через 2 секунды
        
        private _passData = [_unitName, side group _target, if (count _unitValue > 2) then {(_unitValue select 2) call TVD_unitRole} else {""}, _target getVariable ["TVD_GroupID", ""]]; // Данные для лога
        ["sentToResMan", _passData] call TVD_logEvent; // Логирование события
    };
};

// Синхронизация очков резерва через CBA-ивент (инициализация один раз)
if (isServer && isNil "TVD_ReserveUpdateEH") then {
    TVD_ReserveUpdateEH = ["TVD_ReserveUpdate", { // Обработчик события обновления резерва
        params ["_us", "_amount"];
        if (_us >= 0 && _us < count TVD_SidesResScore) then { // Проверка корректности индекса
            TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Обновление очков резерва на всех клиентах
        };
    }] call CBA_fnc_addEventHandler;
};