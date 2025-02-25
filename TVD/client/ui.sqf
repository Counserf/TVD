#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Отправляет уведомление игрокам с заданным текстом и типом отображения
 * Параметры:
 *   _targets: массив/число - игроки или 0 (все)
 *   _message: строка/массив - текст уведомления или [сторона, текст] для задач
 *   _type: строка (опционально) - тип уведомления ("title", "dynamic", "task", по умолчанию "title")
 */
TVD_notifyPlayers = {
    params ["_targets", "_message", "_type" = "title"];
    private _formatted = switch (_type) do {
        case "title": {format ["<t align='center'>%1</t>", _message]}; // Обычный заголовок
        case "dynamic": {[_message, 0, 0.7, 6, 0.2]}; // Динамический текст
        case "task": {_message}; // Уведомление о задаче
        default {_message}; // По умолчанию простой текст
    };
    
    // Выбор типа выполнения в зависимости от _type
    switch (_type) do {
        case "dynamic": {[_formatted, "bis_fnc_dynamictext", _targets] remoteExec ["spawn", _targets]}; // Динамический текст
        case "task": { // Уведомление о задаче с типом "TaskSucceeded" или "TaskFailed"
            [[_formatted], {
                params ["_msg"];
                private _type = if (playerSide == (_msg select 0)) then {"TaskSucceeded"} else {"TaskFailed"};
                [_type, [0, _msg select 1]] call BIS_fnc_showNotification; // Показ уведомления
            }] remoteExec ["call", _targets];
        };
        default {[[_formatted], {titleText [_this select 0, "PLAIN DOWN"]}] remoteExec ["call", _targets]}; // Заголовок по центру
    };
};

/*
 * Отправляет уведомление всем игрокам заданной стороны
 * Параметры:
 *   _side: сторона - сторона для уведомления (sideLogic для всех)
 *   _message: строка - текст уведомления
 *   _type: строка (опционально) - тип уведомления ("title", "dynamic", по умолчанию "title")
 */
TVD_notifySide = {
    params ["_side", "_message", "_type" = "title"];
    private _targets = if (_side == sideLogic) then {0} else {allPlayers select {side group _x == _side}}; // Фильтрация по стороне
    [_targets, _message, _type] call TVD_notifyPlayers; // Вызов общей функции уведомления
};