#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для использования функций CBA
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_ZoneGain и т.д.)

// Локальные переменные для управления завершением
private "_endCause";

// Клиентская часть: запуск клиентских действий
if (!isDedicated) then {
    [] spawn TVD_addClientActions; // Инициализация действий игрока (отступление, отправка в резерв и т.д.)
};

// Серверная часть: основной цикл миссии
if (isServer) then {
    // Инициализация параметров миссии (переопределяют config.sqf, если указаны)
    private _sides = _this param [0, TVD_Sides];
    private _capZonesCount = _this param [1, TVD_CapZonesCount];
    private _retreatPossible = _this param [2, TVD_RetreatPossible];
    private _zoneGain = _this param [3, TVD_ZoneGain];
    private _retreatRatio = _this param [4, TVD_RetreatRatio];
    
    // Проверка корректности входных параметров
    if (isNil "_sides") then { _sides = TVD_Sides; diag_log "TVD/main.sqf: TVD_Sides is nil, using default"; };
    
    // Запуск инициализации миссии с параметрами
    private _initResult = [_sides, _capZonesCount, _retreatPossible, _zoneGain, _retreatRatio] call TVD_init;
    if (isNil "_initResult") then { diag_log "TVD/main.sqf: TVD_init failed"; };
    
    // Инициализация timeToEnd, если не определена
    if (isNil "timeToEnd") then { timeToEnd = -1; publicVariable "timeToEnd"; };

    // Обработка действий администратора через CBA-событие
    ["TVD_Admin_Action", {
        params ["_action", ["_winner", sideUnknown], ["_noReplay", false]];
        
        diag_log format ["TVD/main.sqf: Admin action triggered - Action: %1, Winner: %2, NoReplay: %3", _action, _winner, _noReplay];
        
        switch (_action) do {
            case "Техническое завершение": {
                timeToEnd = 0; // Код 0 для админского завершения через интерфейс
                publicVariable "timeToEnd";
                [0, false, _winner, false] call TVD_endMission; // Плавное завершение с реплеем через TVD_endMission
            };
            case "Техническое завершение без реплея": {
                timeToEnd = 0; // Код 0 для админского завершения через интерфейс
                publicVariable "timeToEnd";
                [0, true, _winner, true] call TVD_endMission; // Завершение без реплея через TVD_endMission
            };
            case "Убить всех ботов": {
                [] call TVD_killAllAI; // Уничтожение всех AI-юнитов без уведомления игроков
            };
        };
    }] call CBA_fnc_addEventHandler;

    // Ожидание окончания заморозки миссии (a3a_var_started)
    [CBA_fnc_waitUntilAndExecute, {(missionNamespace getVariable ["a3a_var_started", false])}, {
        sleep (missionNamespace getVariable ["TVD_StartupDelay", 10]); // Задержка перед началом циклов для стабилизации миссии, конфигурируемо

        // Периодическое логирование состояния миссии (каждые 5 минут)
        [CBA_fnc_addPerFrameHandler, {
            if (isNil "TVD_PlayerCountInit" || isNil "TVD_PlayerCountNow") exitWith {}; // Ждём данные о игроках
            private _stats = [] call TVD_updateScore; // Обновление текущих очков
            if (!isNil "_stats") then { ["scheduled", _stats] call TVD_logEvent; }; // Логирование состояния, с проверкой
        }, 300] call CBA_fnc_addPerFrameHandler; // 300 секунд = 5 минут

        // Проверка задач каждые 10 секунд
        [CBA_fnc_addPerFrameHandler, {
            if (timeToEnd != -1 || count TVD_TaskObjectsList <= 2) exitWith {[_this select 1] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении
            [] call TVD_updateTasks; // Обновление состояния задач
        }, 10] call CBA_fnc_addPerFrameHandler;

        // Запуск мониторинга тяжёлых потерь
        [] spawn TVD_monitorHeavyLosses;

        // Основной цикл проверки условий завершения миссии (оптимизирован через waitUntil)
        [CBA_fnc_waitUntilAndExecute, {
            if (timeToEnd != -1) exitWith {true}; // Миссия завершена
            if (isNil "a3a_endMissionTime") then {missionNamespace setVariable ["a3a_endMissionTime", 3600, true]}; // Установка по умолчанию, если не задано
            
            switch (true) do {
                case ((a3a_endMissionTime - time) < 300): { // Истечение времени
                    timeToEnd = 1;
                    publicVariable "timeToEnd";
                    [1, false] call TVD_endMission; // Плавное завершение
                };
                case (TVD_HeavyLosses != sideLogic): { // Тяжёлые потери
                    timeToEnd = 2;
                    publicVariable "timeToEnd";
                    [2, false, TVD_HeavyLosses] call TVD_endMission; // Завершение с причиной
                };
                case (TVD_SideRetreat != sideLogic): { // Отступление стороны
                    timeToEnd = 3;
                    publicVariable "timeToEnd";
                    [TVD_SideRetreat] call TVD_retreatSide; // Обработка отступления
                    sleep 5; // Задержка для завершения эффектов
                    [3, false, TVD_SideRetreat] call TVD_endMission;
                };
                case (TVD_MissionComplete != sideLogic): { // Выполнение ключевой задачи
                    timeToEnd = 4;
                    publicVariable "timeToEnd";
                    [4, false, TVD_MissionComplete] call TVD_endMission;
                };
            };
            false // Продолжение цикла
        }, 3] call CBA_fnc_waitUntilAndExecute; // Проверка каждые 3 секунды
    }] call CBA_fnc_waitUntilAndExecute;
};

/*
 * Уничтожает всех ботов, не управляемых игроками
 */
TVD_killAllAI = {
    if (!isServer) exitWith {}; // Выполняется только на сервере
    private _aiUnits = allUnits select {!isPlayer _x}; // Выборка всех юнитов, не управляемых игроками
    {
        _x setDamage 1; // Уничтожение юнита
        ["killed", _x] call TVD_logEvent; // Логирование смерти бота
    } forEach _aiUnits;
    diag_log format ["TVD/main.sqf: Admin killed %1 AI units", count _aiUnits]; // Логирование действия в серверный лог
};