#include "\x\cba\addons\main\script_macros.hpp" // Подключение макросов CBA для использования асинхронных функций и утилит
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_ZoneGain и другие параметры)

// Локальная переменная для хранения причины завершения миссии
private "_endCause";

// Клиентская часть: запуск действий игрока
if (!isDedicated) then {
    [] spawn TVD_addClientActions; // Асинхронный запуск функции добавления действий (отступление, резерв и т.д.) на клиенте
};

// Серверная часть: основной цикл и логика миссии
if (isServer) then {
    // Получение параметров миссии из аргументов вызова скрипта (если переданы), с fallback на значения из config.sqf
    private _sides = _this param [0, TVD_Sides]; // Стороны конфликта (bluefor, opfor)
    private _capZonesCount = _this param [1, TVD_CapZonesCount]; // Количество зон захвата
    private _retreatPossible = _this param [2, TVD_RetreatPossible]; // Разрешение отступления для сторон
    private _zoneGain = _this param [3, TVD_ZoneGain]; // Очки за контроль одной зоны
    private _retreatRatio = _this param [4, TVD_RetreatRatio]; // Порог потерь для отступления
    
    // Проверка корректности переданных сторон, с логированием ошибки, если они отсутствуют
    if (isNil "_sides") then { 
        _sides = TVD_Sides; 
        diag_log "TVD/main.sqf: TVD_Sides is nil, using default"; // Логирование использования значений по умолчанию
    };
    
    // Запуск инициализации миссии с переданными или дефолтными параметрами
    private _initResult = [_sides, _capZonesCount, _retreatPossible, _zoneGain, _retreatRatio] call TVD_init;
    if (isNil "_initResult") then { diag_log "TVD/main.sqf: TVD_init failed"; }; // Логирование сбоя инициализации
    
    // Установка переменной timeToEnd, если она не определена (индикатор завершения миссии: -1 = не завершена)
    if (isNil "timeToEnd") then { 
        timeToEnd = -1; 
        publicVariable "timeToEnd"; // Синхронизация с клиентами
    };

    // Обработчик действий администратора через событие CBA (вызывается из admin_menu.sqf)
    ["TVD_Admin_Action", {
        params ["_action", ["_winner", sideUnknown], ["_noReplay", false]]; // Параметры: действие, победитель, флаг без реплея
        
        diag_log format ["TVD/main.sqf: Admin action triggered - Action: %1, Winner: %2, NoReplay: %3", _action, _winner, _noReplay]; // Логирование действия админа
        
        switch (_action) do {
            case "Техническое завершение": {
                timeToEnd = 0; // Код завершения 0 для админского вмешательства
                publicVariable "timeToEnd"; // Синхронизация с клиентами
                [0, false, _winner, false] call TVD_endMission; // Плавное завершение с дебрифингом и реплеем
            };
            case "Техническое завершение без реплея": {
                timeToEnd = 0; // Код завершения 0 для админского вмешательства
                publicVariable "timeToEnd"; // Синхронизация с клиентами
                [0, true, _winner, true] call TVD_endMission; // Быстрое завершение без реплея
            };
            case "Убить всех ботов": {
                [] call TVD_killAllAI; // Уничтожение всех AI-юнитов без уведомления игроков
            };
        };
    }] call CBA_fnc_addEventHandler;

    // Ожидание окончания заморозки миссии (переменная a3a_var_started становится true)
    [CBA_fnc_waitUntilAndExecute, {(missionNamespace getVariable ["a3a_var_started", false])}, {
        sleep (missionNamespace getVariable ["TVD_StartupDelay", 10]); // Задержка перед запуском циклов (по умолчанию 10 секунд)

        // Периодическое логирование состояния миссии каждые 5 минут
        [CBA_fnc_addPerFrameHandler, {
            if (isNil "TVD_PlayerCountInit" || isNil "TVD_PlayerCountNow") exitWith {}; // Пропуск, если данные о игроках не инициализированы
            private _stats = [] call TVD_updateScore; // Обновление текущих очков сторон
            if (!isNil "_stats") then { ["scheduled", _stats] call TVD_logEvent; }; // Логирование состояния с проверкой на nil
        }, 300] call CBA_fnc_addPerFrameHandler; // 300 секунд = 5 минут

        // Проверка задач каждые 10 секунд
        [CBA_fnc_addPerFrameHandler, {
            if (timeToEnd != -1 || count TVD_TaskObjectsList <= 2) exitWith {[_this select 1] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении миссии или отсутствии задач
            [] call TVD_updateTasks; // Обновление состояния задач
        }, 10] call CBA_fnc_addPerFrameHandler;

        // Запуск мониторинга тяжёлых потерь в отдельном потоке
        [] spawn TVD_monitorHeavyLosses;

        // Основной цикл проверки условий завершения миссии (каждые 3 секунды)
        [CBA_fnc_addPerFrameHandler, {
            params ["_args", "_handle"]; // Аргументы и идентификатор обработчика
            
            if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка цикла при завершении миссии
            
            // Установка времени миссии по умолчанию (1 час), если оно не задано
            if (isNil "a3a_endMissionTime") then {missionNamespace setVariable ["a3a_endMissionTime", 3600, true]};
            
            // Проверка условий завершения миссии
            switch (true) do {
                case ((a3a_endMissionTime - time) < 300): { // Осталось менее 5 минут
                    timeToEnd = 1; // Код завершения 1: истечение времени
                    publicVariable "timeToEnd"; // Синхронизация с клиентами
                    [1, false] call TVD_endMission; // Плавное завершение с дебрифингом
                };
                case (TVD_HeavyLosses != sideLogic): { // Тяжёлые потери одной из сторон
                    timeToEnd = 2; // Код завершения 2: тяжёлые потери
                    publicVariable "timeToEnd"; // Синхронизация с клиентами
                    [2, false, TVD_HeavyLosses] call TVD_endMission; // Завершение с указанием стороны
                };
                case (TVD_SideRetreat != sideLogic): { // Сторона отступила
                    timeToEnd = 3; // Код завершения 3: отступление
                    publicVariable "timeToEnd"; // Синхронизация с клиентами
                    [TVD_SideRetreat] call TVD_retreatSide; // Обработка отступления (передача техники, удаление юнитов)
                    sleep 5; // Задержка для завершения эффектов отступления
                    [3, false, TVD_SideRetreat] call TVD_endMission; // Завершение с дебрифингом
                };
                case (TVD_MissionComplete != sideLogic): { // Выполнена ключевая задача
                    timeToEnd = 4; // Код завершения 4: выполнение задачи
                    publicVariable "timeToEnd"; // Синхронизация с клиентами
                    [4, false, TVD_MissionComplete] call TVD_endMission; // Завершение с указанием стороны
                };
            };
        }, 3] call CBA_fnc_addPerFrameHandler; // Интервал проверки: 3 секунды
    }] call CBA_fnc_waitUntilAndExecute; // Запуск после окончания заморозки миссии
};

/*
 * Функция уничтожения всех AI-юнитов, не управляемых игроками
 * Выполняется только на сервере по команде администратора
 */
TVD_killAllAI = {
    if (!isServer) exitWith {}; // Проверка: выполняется только на сервере
    private _aiUnits = allUnits select {!isPlayer _x}; // Выборка всех юнитов, не являющихся игроками
    {
        _x setDamage 1; // Мгновенное уничтожение юнита
        ["killed", _x] call TVD_logEvent; // Логирование смерти AI в журнале миссии
    } forEach _aiUnits;
    diag_log format ["TVD/main.sqf: Admin killed %1 AI units", count _aiUnits]; // Логирование количества уничтоженных AI в RPT-файл
};