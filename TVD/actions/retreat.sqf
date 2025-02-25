#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_BaseTriggers и т.д.)

/*
 * Выполняет отступление всей стороны, уничтожая юнитов вне базы и передавая технику врагу
 * Параметры:
 *   _side: сторона - сторона, которая отступает
 */
TVD_retreatSide = {
    params ["_side"];
    private _trigger = TVD_BaseTriggers select (TVD_Sides find _side); // Триггер базы отступающей стороны
    if (isNull _trigger) exitWith {diag_log "TVD_retreatSide: Trigger is null";}; // Выход, если триггер отсутствует
    _trigger setTriggerActivation ["ANY", "PRESENT", true]; // Активация триггера для всех
    
    private _retLossLog = parseText ""; // Лог потерь при отступлении
    private _enemySide = TVD_Sides select (1 - (TVD_Sides find _side)); // Противоположная сторона
    
    // Уничтожение юнитов вне зоны базы
    private _retreatUnits = allPlayers select {side group _x == _side && !(_x in list _trigger)};
    {[_x, _retLossLog] call TVD_retreatSoldier} forEach _retreatUnits; // Индивидуальное отступление для каждого
    
    // Передача техники врагу
    private _lostVehicles = TVD_ValUnits select {!(_x in list _trigger) && (_x getVariable "TVD_UnitValue" select 0) == _side};
    {
        _x setVariable ["TVD_CapOwner", _enemySide, true]; // Смена владельца техники
        _retLossLog = composeText [_retLossLog, parseText format ["%1, ", getText (configFile >> "CfgVehicles" >> typeOf _x >> "displayName")]]; // Добавление в лог
    } forEach _lostVehicles;
    
    // Передача всех зон врагу
    {if (!(_x select 2)) then {(_x select 0) setMarkerColor (_enemySide call TVD_sideToColor)}} forEach TVD_capZones; // Обновление цвета зон
    
    ["retreatLossList", _retLossLog, TVD_Sides find _side] call TVD_logEvent; // Логирование потерь
};

/*
 * Выполняет отступление одного солдата с уведомлением и удалением
 * Параметры:
 *   _unit: объект - юнит, который отступает
 *   _log: текст (опционально) - лог для добавления имени юнита (используется в retreatSide)
 */
TVD_retreatSoldier = {
    params ["_unit", ["_log", nil]];
    if (isNull _unit) exitWith {}; // Выход, если юнит отсутствует
    private _us = TVD_Sides find side group _unit; // Индекс стороны юнита
    if (_us == -1) exitWith {}; // Пропуск, если сторона не найдена
    private _unitName = name _unit; // Имя юнита
    
    // Уведомление ближайших игроков
    private _notifyUnits = (ASLToAGL getPosASL _unit nearEntities ["CAManBase", 50]) select {isPlayer _x};
    [_notifyUnits, format ["%1 отступил в тыл.", _unitName], "title"] call TVD_notifyPlayers;
    
    // Уведомление самому игроку, если он жив
    if (isPlayer _unit) then {[_unit, "Вы отступили в тыл.", "dynamic"] call TVD_notifyPlayers};
    
    private _unitValue = _unit getVariable ["TVD_UnitValue", []]; // Данные юнита
    private _amount = if (_unitValue isNotEqualTo []) then {_unitValue select 1} else {TVD_SoldierCost}; // Ценность юнита
    _unit setVariable ["TVD_soldierRetreats", true, true]; // Установка флага отступления
    
    // Обновление очков и удаление юнита (только на сервере)
    if (isServer) then {
        TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв
        TVD_RetrCount set [_us, (TVD_RetrCount select _us) + 1]; // Увеличение счётчика отступлений
        ["TVD_RetreatUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация через CBA-ивент
        
        _unit setDamage 1; // Уничтожение юнита
        [_unit] spawn {sleep 2; if (!isNull (_this select 0)) then {deleteVehicle (_this select 0)}}; // Асинхронное удаление через 2 секунды
        
        // Формирование данных для лога
        private _passData = [_unitName, side group _unit, if (count _unitValue > 2) then {(_unitValue select 2) call TVD_unitRole} else {""}, _unit getVariable ["TVD_GroupID", ""]];
        if (!isNil "_log") then {_log = composeText [_log, parseText format ["%1, ", _unitName]]}; // Добавление в общий лог, если указан
        ["retreatSoldier", _passData] call TVD_logEvent; // Логирование события
    };
};