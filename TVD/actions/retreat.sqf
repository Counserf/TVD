#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_BaseTriggers и т.д.)

/*
 * Выполняет отступление всей стороны, уничтожая юнитов вне базы и передавая технику врагу
 * Параметры:
 *   _side: сторона - сторона, которая отступает
 * Возвращает: текст - обновлённый лог потерь при отступлении
 */
TVD_retreatSide = {
    params ["_side"];
    private _trigger = TVD_BaseTriggers select (TVD_Sides find _side); // Триггер базы отступающей стороны
    if (isNull _trigger) exitWith {diag_log "TVD_retreatSide: Trigger is null"; parseText ""}; // Выход с пустым логом, если триггер отсутствует
    _trigger setTriggerActivation ["ANY", "PRESENT", true]; // Активация триггера для всех объектов
    
    private _retLossLog = parseText ""; // Лог потерь при отступлении
    private _enemySide = TVD_Sides select (1 - (TVD_Sides find _side)); // Противоположная сторона
    
    // Уничтожение юнитов вне зоны базы
    private _retreatUnits = allPlayers select {side group _x == _side && !(_x in list _trigger)};
    {
        [_x, _retLossLog] call TVD_retreatSoldier; // Индивидуальное отступление с обновлением лога
    } forEach _retreatUnits;
    
    // Передача техники врагу только если она вне базы
    private _lostVehicles = TVD_ValUnits select {!(_x in list _trigger) && (_x getVariable "TVD_UnitValue" select 0) == _side}; // Изменение: техника на базе не передаётся
    {
        _x setVariable ["TVD_CapOwner", _enemySide, true]; // Смена владельца техники
        _retLossLog = composeText [_retLossLog, parseText format ["%1, ", getText (configFile >> "CfgVehicles" >> typeOf _x >> "displayName")]]; // Добавление в лог
    } forEach _lostVehicles;
    
    // Передача всех зон врагу (кроме заблокированных)
    {if (!(_x select 2)) then {(_x select 0) setMarkerColor (_enemySide call TVD_sideToColor)}} forEach TVD_capZones;
    
    ["retreatLossList", _retLossLog, TVD_Sides find _side] call TVD_logEvent; // Логирование потерь
    _retLossLog // Возвращаем обновлённый лог
};

/*
 * Выполняет отступление одного солдата с уведомлением и удалением
 * Параметры:
 *   _unit: объект - юнит, который отступает
 *   _log: текст (опционально) - лог для добавления имени юнита (используется в retreatSide)
 * Возвращает: текст - обновлённый лог, если передан
 */
TVD_retreatSoldier = {
    params ["_unit", ["_log", nil]];
    if (isNull _unit) exitWith {diag_log "TVD/retreat.sqf: Unit is null"; if (!isNil "_log") then {_log} else {nil}}; // Выход с логом, если юнит отсутствует
    private _us = TVD_Sides find side group _unit; // Индекс стороны юнита
    if (_us == -1) exitWith {diag_log "TVD/retreat.sqf: Unit side not in TVD_Sides"; if (!isNil "_log") then {_log} else {nil}}; // Пропуск, если сторона не найдена
    private _unitName = name _unit; // Имя юнита для уведомлений и лога
    
    // Уведомление ближайших игроков в радиусе 50 метров
    [_unit, _unitName] call TVD_notifyRetreat; // Используем общую функцию уведомления
    
    // Уведомление самому игроку, если он жив
    if (isPlayer _unit) then {[_unit, "Вы отступили в тыл.", "dynamic"] call TVD_notifyPlayers};
    
    private _unitValue = _unit getVariable ["TVD_UnitValue", []]; // Данные юнита
    private _amount = if (_unitValue isNotEqualTo []) then {_unitValue select 1} else {TVD_SoldierCost}; // Ценность юнита: из TVD_UnitValue или по умолчанию
    _unit setVariable ["TVD_soldierRetreats", true, true]; // Установка флага отступления
    
    // Обновление очков и удаление юнита (только на сервере)
    if (isServer) then {
        TVD_SidesResScore set [_us, (TVD_SidesResScore select _us) + _amount]; // Добавление очков в резерв
        TVD_RetrCount set [_us, (TVD_RetrCount select _us) + 1]; // Увеличение счётчика отступлений
        ["TVD_RetreatUpdate", [_us, _amount]] call CBA_fnc_globalEvent; // Синхронизация через CBA-ивент
        
        _unit setDamage 1; // Уничтожение юнита
        [_unit] call TVD_safeDelete; // Используем общую функцию удаления
        
        // Формирование данных для лога
        private _passData = [_unitName, side group _unit, if (count _unitValue > 2) then {(_unitValue select 2) call TVD_unitRole} else {""}, _unit getVariable ["TVD_GroupID", ""]];
        if (!isNil "_log" && {_log isEqualType (parseText "")}) then {
            _log = composeText [_log, parseText format ["%1, ", _unitName]]; // Обновление переданного лога
        };
        ["retreatSoldier", _passData] call TVD_logEvent; // Логирование события
    };
    
    if (!isNil "_log") then {_log}; // Возвращаем обновлённый лог, если он передан
};

/*
 * Уведомляет о отступлении юнита
 * Параметры:
 *   _unit: объект - юнит, который отступает
 *   _unitName: строка - имя юнита
 */
TVD_notifyRetreat = {
    params ["_unit", "_unitName"];
    private _notifyUnits = (ASLToAGL getPosASL _unit nearEntities ["CAManBase", 50]) select {isPlayer _x};
    [_notifyUnits, format ["%1 отступил в тыл.", _unitName], "title"] call TVD_notifyPlayers;
};

/*
 * Безопасно удаляет объект с задержкой
 * Параметры:
 *   _object: объект - объект для удаления
 */
TVD_safeDelete = {
    params ["_object"];
    sleep 2;
    if (!isNull _object) then {deleteVehicle _object}; // Убрана проверка экипажа
};