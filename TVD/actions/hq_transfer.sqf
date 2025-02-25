#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Передаёт командование стороне при смерти командира
 * Параметры:
 *   _type: строка - тип события ("slTransfer" для передачи командования)
 *   _unit: объект - убитый командир
 */
TVD_hqTransfer = {
    params ["_type", "_unit"];
    if (_type != "slTransfer" || isNull _unit) exitWith {}; // Выход, если не передача командования или юнит отсутствует
    
    private _side = (_unit getVariable ["TVD_UnitValue", [sideLogic, 0]]) select 0; // Сторона командира
    if !(_side in TVD_Sides) exitWith {}; // Выход, если сторона не участвует в игре
    
    private _found = false; // Флаг нахождения нового командира
    scopeName "hqSearch"; // Область для прерывания поиска
    
    // Поиск нового командира среди групп стороны
    {
        if (side _x == _side) then {
            {
                private _unitValue = _x getVariable ["TVD_UnitValue", []];
                if (_unitValue isNotEqualTo [] && side _x == _side && (_unitValue param [2, ""] == "squadLeader") && isPlayer _x) then { // Поиск командира отделения
                    _found = true;
                    _unitValue set [2, "execSideLeader"]; // Назначение исполняющим обязанности
                    _x setVariable ["TVD_UnitValue", _unitValue, true]; // Обновление данных юнита
                    
                    [_x, "mpkilled", ["TVD_hqTransfer", ["slTransfer", _x]]] remoteExec ["call", 2]; // Добавление обработчика смерти новому командиру
                    [_x, "Вы приняли командование.", "dynamic"] call TVD_notifyPlayers; // Уведомление новому командиру
                    [[side group _x, format ["КС убит. %1 принял командование.", name _x]], "TaskAssigned"] call TVD_notifySide; // Уведомление стороне
                    breakTo "hqSearch"; // Прерывание поиска
                };
            } forEach units _x;
        };
    } forEach allGroups;
    
    // Сообщение, если командир не найден
    if (!_found) then {
        [_side, "КС убит. Некому принять командование.", "dynamic"] call TVD_notifySide;
    };
};