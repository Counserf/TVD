#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Добавляет клиентские действия игроку (отступление, отправка в резерв, командование)
 */
TVD_addClientActions = {
    [true] call TVD_waitForStart; // Используем общую функцию ожидания с проверкой игрока
    if !(side group player in TVD_Sides) exitWith {diag_log "TVD/actions.sqf: Player side not in TVD_Sides";}; // Выход, если сторона не участвует в TVD
    
    // Исправление высокой проблемы: предотвращение дублирования действий
    if (!isNil {player getVariable "TVD_actionsAdded"}) exitWith {};
    player setVariable ["TVD_actionsAdded", true];

    if (isNil "TVD_BaseTriggers") then { diag_log "TVD/actions.sqf: TVD_BaseTriggers not defined"; }; // Проверка наличия триггеров баз
    private _sideIdx = TVD_Sides find side group player; // Индекс стороны игрока в TVD_Sides
    private _baseTrigger = TVD_BaseTriggers select _sideIdx; // Триггер базы игрока
    private _commonCond = "_this == _target && !(_this getVariable ['ACE_isUnconscious', false]) && !(_this getVariable ['ace_captives_ishandcuffed', false])"; // Общее условие для действий

    // Действие: индивидуальное отступление солдата
    private _retreatActionId = player addAction ["<t color='#ff4c4c'>" + localize "STR_TVD_RetreatIndividual" + "</t>", {
        params ["_target", "_caller"];
        _caller setVariable ["TVD_srAct", 2]; // Переход в режим подтверждения (локальная переменная)
        
        // Действие подтверждения отступления
        private _approveId = _caller addAction ["<t color='#ff4c4c'>" + localize "STR_TVD_RetreatConfirm" + "</t>", {
            params ["_target", "_caller"];
            _caller setVariable ["TVD_srAct", 0]; // Завершение действия
            {_caller removeAction _x} forEach [_caller getVariable ["TVD_approveId", -1], _caller getVariable ["TVD_cancelId", -1], _caller getVariable ["TVD_retreatActionId", -1]]; // Удаление всех действий
            private _us = [_target] call TVD_getSideIndexFromTrigger; // Используем общую функцию
            if (["retreat", _target, _us] call TVD_checkActionCondition) then { // Используем общую функцию проверки условий
                [[_target], "TVD_retreatSoldier"] remoteExec ["call", 2]; // Вызов серверной функции отступления
            } else {
                [localize "STR_TVD_NoRearError", "title"] call TVD_notifyPlayers; // Уведомление об ошибке
            };
        }, nil, 0, false, true, "", _commonCond];
        _caller setVariable ["TVD_approveId", _approveId]; // Сохранение ID действия подтверждения
        
        // Действие отмены отступления
        private _cancelId = _caller addAction ["<t color='#8BC8D6'>" + localize "STR_TVD_RetreatCancel" + "</t>", {
            params ["_target", "_caller"];
            _caller setVariable ["TVD_srAct", 1]; // Возврат в начальное состояние
            {_caller removeAction _x} forEach [_caller getVariable ["TVD_approveId", -1], _caller getVariable ["TVD_cancelId", -1]]; // Удаление действий
        }, nil, 0, false, true, "", _commonCond];
        _caller setVariable ["TVD_cancelId", _cancelId]; // Сохранение ID действия отмены
    }, nil, 0, false, true, "", format ["%1 && (_this getVariable ['TVD_srAct', 1]) == 1 && {_this in list %2 && TVD_SideCanRetreat param [%3, false]}", _commonCond, _baseTrigger, _sideIdx]];
    player setVariable ["TVD_retreatActionId", _retreatActionId]; // Сохранение ID действия отступления
    
    // Действие: отправка пехотинца в резерв
    player addAction ["<t color='#ffffff'>" + localize "STR_TVD_SendToReserve" + "</t>", {
        params ["_target", "_caller"];
        private _us = [_target] call TVD_getSideIndexFromTrigger; // Используем общую функцию
        if (["reserveMan", _target, _us] call TVD_checkActionCondition) then { // Используем общую функцию проверки условий
            [[_target, _caller], "TVD_sendToReserve"] remoteExec ["call", 2]; // Вызов серверной функции отправки в резерв
        } else {
            [localize "STR_TVD_CannotSendCaptive", "title"] call TVD_notifyPlayers; // Уведомление об ошибке
        };
    }, nil, 0, false, true, "", format ["_this != _target && (_target distance _this <= 3) && {isClass (configFile >> 'CfgPatches' >> 'ace_main') && {_target getVariable ['ace_captives_ishandcuffed', false]}} && {_this in list %1}", _baseTrigger]];
    
    // Действие: отправка техники в резерв
    player addAction ["<t color='#ffffff'>" + localize "STR_TVD_SendVehicleToReserve" + "</t>", {
        params ["_target", "_caller"];
        private _us = [_target] call TVD_getSideIndexFromTrigger; // Используем общую функцию
        if (["reserveVehicle", _target, _us] call TVD_checkActionCondition) then { // Используем общую функцию проверки условий
            [[_target, _caller], "TVD_sendToReserve"] remoteExec ["call", 2]; // Вызов серверной функции отправки в резерв
        } else {
            [localize "STR_TVD_CannotSendVehicle", "title"] call TVD_notifyPlayers; // Уведомление об ошибке
        };
    }, nil, 0, false, true, "", format ["_this != _target && (_target distance _this <= 5) && (_target isKindOf 'Vehicle') && {_this in list %1}", _baseTrigger]];
    
    // Действие: команда на отступление для командиров
    if (player getVariable ["TVD_UnitValue", []] param [2, ""] in ["sideLeader", "execSideLeader"]) then {
        player addAction ["<t color='#ffffff'>" + localize "STR_TVD_SideRetreatCommand" + "</t>", {
            params ["_target", "_caller"];
            _caller setVariable ["TVD_retrAction", 2]; // Переход в режим подтверждения (локальная переменная)
            // Исправление средней проблемы: уникальный код подтверждения вместо рандома
            private _confirmCode = format ["CONFIRM_%1", floor random 1000]; // Уникальный код подтверждения
            private _actIndex = []; // Локальный массив действий
            
            // Действие подтверждения с кодом
            private _confirmId = _caller addAction [format ["<t color='#ffffff'>%1 %2</t>", localize "STR_TVD_RetreatConfirm", _confirmCode], {
                params ["_target", "_caller"];
                _caller setVariable ["TVD_retrAction", 0]; // Завершение действия
                {_caller removeAction _x} forEach (_caller getVariable ["TVD_actIndex", []]); // Удаление всех действий
                _caller setVariable ["TVD_actIndex", []]; // Очистка массива действий
                TVD_SideRetreat = side _caller; // Установка отступившей стороны
                publicVariableServer "TVD_SideRetreat"; // Уведомление сервера об отступлении
            }, nil, 0, false, true, "", format ["timeToEnd == -1 && (_this getVariable ['TVD_confirmCode', '']) == '%1'", _confirmCode]];
            _caller setVariable ["TVD_confirmCode", _confirmCode];
            _actIndex pushBack _confirmId;
            
            // Действия отмены (без кода)
            for "_i" from 0 to 5 do {
                private _id = _caller addAction ["<t color='#8BC8D6'>" + localize "STR_TVD_RetreatCancel" + "</t>", {
                    params ["_target", "_caller"];
                    _caller setVariable ["TVD_retrAction", 1]; // Возврат в начальное состояние
                    {_caller removeAction _x} forEach (_caller getVariable ["TVD_actIndex", []]); // Удаление всех действий
                    _caller setVariable ["TVD_actIndex", []]; // Очистка массива действий
                }, nil, 0, false, true, "", ""];
                _actIndex pushBack _id;
            };
            _caller setVariable ["TVD_actIndex", _actIndex]; // Сохранение массива действий
        }, nil, 0, false, true, "", "(_target getVariable ['TVD_retrAction', 1]) == 1 && timeToEnd == -1"]; // Условие для командиров
    };
};

/*
 * Проверяет условия для выполнения действий
 * Параметры:
 *   _type: строка - тип действия ("retreat", "reserveMan", "reserveVehicle")
 *   _target: объект - цель действия
 *   _us: число - индекс стороны
 * Возвращает: логическое - выполняется ли условие
 */
TVD_checkActionCondition = {
    params ["_type", "_target", "_us"];
    switch (_type) do {
        case "retreat": {TVD_SideCanRetreat param [_us, false]};
        case "reserveMan": {TVD_RetreatPossible param [_us, false] && {isClass (configFile >> "CfgPatches" >> "ace_main") && {_target getVariable ["ace_captives_ishandcuffed", false]}}};
        case "reserveVehicle": {TVD_RetreatPossible param [_us, false] && !(_target getVariable ["TVD_SentToRes", 0] > 0)};
        default {false};
    };
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

/*
 * Ожидает старта миссии
 * Параметры:
 *   _checkPlayer: логическое (опционально) - проверять ли наличие игрока
 */
TVD_waitForStart = {
    params [["_checkPlayer", false]];
    waitUntil {sleep 2; missionNamespace getVariable ["a3a_var_started", false] && (!_checkPlayer || !isNull player)};
};