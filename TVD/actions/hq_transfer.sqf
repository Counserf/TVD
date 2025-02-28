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
            [_leader, _side] call TVD_assignNewCommander; // Используем общую функцию для назначения
            break;
        };
    } forEach (allGroups select {side _x == _side});

    // Исправление средней проблемы: если нет подходящего лидера группы, ищем любого живого игрока на стороне
    if (!_found) then {
        private _fallback = allPlayers findIf {side group _x == _side && alive _x && isPlayer _x};
        if (_fallback != -1) then {
            private _newLeader = allPlayers select _fallback;
            [_newLeader, _side] call TVD_assignNewCommander; // Используем общую функцию для назначения
        } else {
            [_side, "КС убит. Некому принять командование.", "dynamic"] call TVD_notifySide; // Сообщение стороне
            diag_log "TVD/hq_transfer.sqf: No eligible commander found";
        };
    };
};

/*
 * Назначает нового командира стороне
 * Параметры:
 *   _newLeader: объект - новый командир
 *   _side: сторона - сторона, которой передаётся командование
 */
TVD_assignNewCommander = {
    params ["_newLeader", "_side"];
    private _unitValue = _newLeader getVariable ["TVD_UnitValue", []];
    if (_unitValue isNotEqualTo []) then { _unitValue set [2, "execSideLeader"]; } // Обновляем роль, если уже есть TVD_UnitValue
    else { _unitValue = [_side, 50, "execSideLeader"]; }; // Создаём новое значение, если его нет
    _newLeader setVariable ["TVD_UnitValue", _unitValue, true]; // Назначение исполняющим обязанности
    [_newLeader, "mpkilled", ["TVD_hqTransfer", ["slTransfer", _newLeader]]] remoteExec ["call", 2]; // Добавление обработчика смерти новому командиру
    [_newLeader, "Вы приняли командование.", "dynamic"] call TVD_notifyPlayers; // Уведомление новому командиру
    [[side group _newLeader, format ["КС убит. %1 принял командование.", name _newLeader]], "TaskAssigned"] call TVD_notifySide; // Уведомление стороне
    diag_log format ["TVD/hq_transfer.sqf: New commander assigned: %1", name _newLeader];
};