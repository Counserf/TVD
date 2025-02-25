#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_TaskObjectsList и т.д.)

/*
 * Обновляет состояние задач в миссии, проверяя их выполнение
 * Параметры:
 *   _endIt: логическое (опционально) - окончательное завершение задач (true) или регулярная проверка (false, по умолчанию)
 * Возвращает: число - текущее количество задач в списке
 */
TVD_updateTasks = {
    params ["_endIt" = false];
    private ["_tasksCount", "_task", "_side", "_us", "_message", "_showMessageTo", "_amount"];
    
    _tasksCount = count TVD_TaskObjectsList; // Количество задач в списке
    if (_tasksCount <= 2) exitWith {2}; // Возвращаем 2, если остались только счётчики сторон
    
    // Проверка всех задач, начиная с индекса 2 (0 и 1 - счётчики сторон)
    for "_i" from 2 to (_tasksCount - 1) do {
        _task = TVD_TaskObjectsList select _i;
        // Пропускаем задачу, если она завершена или объект удалён
        if (isNull _task || isNil {_task getVariable "TVD_TaskObject"} || (_task getVariable "TVD_TaskObjectStatus") in ["fail", "success"]) then {
            _task setVariable ["TVD_TaskObject", nil, true]; // Очистка данных задачи
            _task setVariable ["TVD_TaskObjectStatus", "fail", true]; // Установка статуса "провал"
            TVD_TaskObjectsList deleteAt _i; // Удаление задачи из списка
            continue;
        };
        
        // Извлечение данных задачи
        _side = _task getVariable "TVD_TaskObject" select 0; // Сторона задачи
        _us = TVD_Sides find _side; // Индекс стороны
        _message = _task getVariable "TVD_TaskObject" select 2; // Сообщение о задаче
        _showMessageTo = _task getVariable "TVD_TaskObject" select 3; // Флаг показа уведомления
        private _conditions = _task getVariable "TVD_TaskObject" select 4; // Условия выполнения
        private _isKeyTask = _task getVariable "TVD_TaskObject" select 5; // Флаг ключевой задачи

        // Проверка выполнения задачи в зависимости от типа объекта
        switch (true) do {
            case (_task isKindOf "EmptyDetector"): { // Задача-триггер
                if (_endIt && timeToEnd >= 0) then {
                    private _cond = _conditions param [timeToEnd, "false"]; // Условие для текущей причины завершения
                    if (call compile _cond && _side != TVD_SideRetreat) then {
                        _task setTriggerStatements ["true", "", ""]; // Принудительная активация триггера
                        waitUntil {triggerActivated _task}; // Ожидание активации
                    };
                };
                if (triggerActivated _task) then {
                    [_task, _side, _us, _message, _showMessageTo, _isKeyTask] call TVD_completeTask; // Завершение задачи
                } else if (_endIt) then {
                    _task setVariable ["TVD_TaskObjectStatus", "fail", true]; // Установка статуса "провал"
                    _task setVariable ["TVD_TaskObject", nil, true];
                    TVD_TaskObjectsList deleteAt _i; // Удаление задачи
                };
            };
            case (_task isKindOf "Logic"): { // Задача-логический объект
                if (_endIt && timeToEnd >= 0) then {
                    private _cond = _conditions param [timeToEnd, "false"]; // Условие для текущей причины завершения
                    if (call compile _cond && _side != TVD_SideRetreat) then {
                        _task setVariable ["WMT_TaskEnd", true, true]; // Принудительное завершение
                    };
                };
                if (_task getVariable ["WMT_TaskEnd", false]) then {
                    [_task, _side, _us, _message, _showMessageTo, _isKeyTask] call TVD_completeTask; // Завершение задачи
                } else if (_endIt) then {
                    _task setVariable ["TVD_TaskObjectStatus", "fail", true]; // Установка статуса "провал"
                    _task setVariable ["TVD_TaskObject", nil, true];
                    TVD_TaskObjectsList deleteAt _i; // Удаление задачи
                };
            };
        };
        _tasksCount = count TVD_TaskObjectsList; // Обновление счётчика после возможного удаления
    };
    _tasksCount // Возвращаем текущее число задач
};

/*
 * Завершает задачу, обновляет счётчики и логирует событие
 * Параметры:
 *   _task: объект - объект задачи (триггер или логический объект)
 *   _side: сторона - сторона, выполнившая задачу
 *   _us: число - индекс стороны в TVD_Sides
 *   _message: строка - сообщение о задаче
 *   _showMessageTo: логическое - показывать ли уведомление игрокам
 *   _isKeyTask: логическое - является ли задача ключевой
 */
TVD_completeTask = {
    params ["_task", "_side", "_us", "_message", "_showMessageTo", "_isKeyTask"];
    
    if (isNull _task || _us == -1) exitWith {}; // Проверка на валидность задачи и стороны
    
    // Обновление счётчиков задач и очков
    TVD_TaskObjectsList set [_us, (TVD_TaskObjectsList select _us) + 1]; // Увеличение счётчика задач стороны
    private _amount = _task getVariable ["TVD_TaskObject", [0, 0]] select 1; // Очки за задачу
    TVD_InitScore set [1 - _us, (TVD_InitScore select (1 - _us)) + _amount]; // Добавление очков противоположной стороне
    
    // Проверка ключевой задачи
    if (_isKeyTask) then {TVD_MissionComplete = _side}; // Установка флага завершения миссии
    _task setVariable ["TVD_TaskObjectStatus", "success", true]; // Установка статуса "успех"
    _task setVariable ["TVD_TaskObject", nil, true]; // Очистка данных задачи
    TVD_TaskObjectsList deleteAt (TVD_TaskObjectsList find _task); // Удаление задачи из списка
    
    // Уведомление игроков, если требуется
    if (_showMessageTo) then {
        private _notifyTargets = allPlayers select {side group _x == _side || side group _x != _side}; // Фильтрация игроков обеих сторон
        if (_notifyTargets isNotEqualTo []) then {
            [[_side, _message], "task"] call TVD_notifyPlayers; // Уведомление с типом "task"
        };
    };
    
    // Логирование события на сервере
    if (isServer) then {
        ["taskCompleted", _message, _us] call TVD_logEvent; // Запись в лог миссии
    };
};