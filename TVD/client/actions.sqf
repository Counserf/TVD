#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Добавляет клиентские действия игроку (отступление, отправка в резерв, командование)
 */
TVD_addClientActions = {
    waitUntil {sleep 5; !isNull player && missionNamespace getVariable ["a3a_var_started", false]}; // Ожидание готовности игрока и миссии
    if !(side group player in TVD_Sides) exitWith {diag_log "TVD/actions.sqf: Player side not in TVD_Sides";}; // Выход, если сторона не участвует в TVD
    
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
            private _us = if (_target in list (TVD_BaseTriggers select 0)) then {0} else {1}; // Индекс стороны по базе
            if (TVD_RetreatPossible param [_us, false]) then { // Проверка возможности отступления
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
        private _us = if (_target in list (TVD_BaseTriggers select 0)) then {0} else {1}; // Индекс стороны по базе
        if (TVD_RetreatPossible param [_us, false] && {isClass (configFile >> "CfgPatches" >> "ace_main") && {_target getVariable ["ace_captives_ishandcuffed", false]}}) then { // Проверка возможности и плена
            [[_target, _caller], "TVD_sendToReserve"] remoteExec ["call", 2]; // Вызов серверной функции отправки в резерв
        } else {
            [localize "STR_TVD_CannotSendCaptive", "title"] call TVD_notifyPlayers; // Уведомление об ошибке
        };
    }, nil, 0, false, true, "", format ["_this != _target && (_target distance _this <= 3) && {isClass (configFile >> 'CfgPatches' >> 'ace_main') && {_target getVariable ['ace_captives_ishandcuffed', false]}} && {_this in list %1}", _baseTrigger]];
    
    // Действие: отправка техники в резерв
    player addAction ["<t color='#ffffff'>" + localize "STR_TVD_SendVehicleToReserve" + "</t>", {
        params ["_target", "_caller"];
        private _us = if (_target in list (TVD_BaseTriggers select 0)) then {0} else {1}; // Индекс стороны по базе
        if (TVD_RetreatPossible param [_us, false] && !(_target getVariable ["TVD_SentToRes", 0] > 0)) then { // Проверка возможности и статуса отправки
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
            private _rand = 1 + floor random 5; // Случайный индекс для подтверждения
            private _actIndex = []; // Локальный массив действий
            for "_i" from 0 to 6 do {
                if (_i == _rand) then {
                    private _id = _caller addAction ["<t color='#ffffff'>" + localize "STR_TVD_RetreatConfirm" + "</t>", { // Подтверждение отступления
                        _caller setVariable ["TVD_retrAction", 0]; // Завершение действия
                        {_caller removeAction _x} forEach (_caller getVariable ["TVD_actIndex", []]); // Удаление всех действий
                        _caller setVariable ["TVD_actIndex", []]; // Очистка массива действий
                        TVD_SideRetreat = side _caller; // Установка отступившей стороны
                        publicVariableServer "TVD_SideRetreat"; // Уведомление сервера об отступлении
                    }, nil, 0, false, true, "", "timeToEnd == -1"];
                    _actIndex pushBack _id; // Добавление ID действия в массив
                } else {
                    private _id = _caller addAction ["<t color='#8BC8D6'>" + localize "STR_TVD_RetreatCancel" + "</t>", { // Отмена отступления
                        _caller setVariable ["TVD_retrAction", 1]; // Возврат в начальное состояние
                        {_caller removeAction _x} forEach (_caller getVariable ["TVD_actIndex", []]); // Удаление всех действий
                        _caller setVariable ["TVD_actIndex", []]; // Очистка массива действий
                    }, nil, 0, false, true, "", ""];
                    _actIndex pushBack _id; // Добавление ID действия в массив
                };
            };
            _caller setVariable ["TVD_actIndex", _actIndex]; // Сохранение массива действий
        }, nil, 0, false, true, "", "(_target getVariable ['TVD_retrAction', 1]) == 1 && timeToEnd == -1"]; // Условие для командиров
    };
};