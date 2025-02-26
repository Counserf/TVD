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
    if (_type != "slTransfer" || isNull _unit) exitWith {diag_log "TVD/hq_transfer.sqf: Invalid type or unit";}; // Выход, если не передача командования или юнит отсутствует
    
    private _side = (_unit getVariable ["TVD_UnitValue", [sideLogic, 0]]) select 0; // Сторона командира
    if !(_side in TVD_Sides) exitWith {diag_log "TVD/hq_transfer.sqf: Side not in TVD_Sides";}; // Выход, если сторона не участвует в игре
    
    private _found = false; // Флаг нахождения нового командира
    
    // Оптимизированный поиск нового командира среди групп стороны
    {
        private _leader = leader _x;
        private _unitValue = _leader getVariable ["TVD_UnitValue", []];
        if (
            side _x == _side &&
            _unitValue isNotEqualTo [] &&
            (_unitValue param [2, ""] == "squadLeader") &&
            isPlayer _leader &&
            alive _leader
        ) then {
            _found = true;
            _unitValue set [2, "execSideLeader"]; // Назначение исполняющим обязанности
            _leader setVariable ["TVD_UnitValue", _unitValue, true]; // Обновление данных юнита
            
            [_leader, "mpkilled", ["TVD_hqTransfer", ["slTransfer", _leader]]] remoteExec ["call", 2]; // Добавление обработчика смерти новому командиру
            [_leader, "Вы приняли командование.", "dynamic"] call TVD_notifyPlayers; // Уведомление новому командиру
            [[side group _leader, format ["КС убит. %1 принял командование.", name _leader]], "TaskAssigned"] call TVD_notifySide; // Уведомление стороне
            break;
        };
    } forEach (allGroups select {side _x == _side});

    // Сообщение, если командир не найден
    if (!_found) then {
        [_side, "КС убит. Некому принять командование.", "dynamic"] call TVD_notifySide;
    };
};