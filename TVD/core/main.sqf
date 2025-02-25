#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для использования функций CBA
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_ZoneGain и т.д.)

// Локальные переменные для управления завершением
private "_endCause";

// Отключение лимитов WMT (если используется мод WMT)
wmt_hl_disable = true;

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
    
    // Запуск инициализации миссии с параметрами
    [_sides, _capZonesCount, _retreatPossible, _zoneGain, _retreatRatio] call TVD_init;

    // Ожидание окончания заморозки миссии (a3a_var_started)
    [CBA_fnc_waitUntilAndExecute, {(missionNamespace getVariable ["a3a_var_started", false])}, {
        sleep 10; // Задержка перед началом циклов для стабилизации миссии

        // Периодическое логирование состояния миссии (каждые 5 минут)
        [CBA_fnc_addPerFrameHandler, {
            if (isNil "TVD_PlayerCountInit" || isNil "TVD_PlayerCountNow") exitWith {}; // Ждём данные о игроках
            private _stats = [] call TVD_updateScore; // Обновление текущих очков
            ["scheduled", _stats] call TVD_logEvent; // Логирование состояния
        }, 300] call CBA_fnc_addPerFrameHandler; // 300 секунд = 5 минут

        // Проверка задач каждые 10 секунд
        [CBA_fnc_addPerFrameHandler, {
            if (timeToEnd != -1 || count TVD_TaskObjectsList <= 2) exitWith {[_this select 1] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении
            [] call TVD_updateTasks; // Обновление состояния задач
        }, 10] call CBA_fnc_addPerFrameHandler;

        // Запуск мониторинга тяжёлых потерь
        [] spawn TVD_monitorHeavyLosses;

        // Основной цикл проверки условий завершения миссии
        [CBA_fnc_addPerFrameHandler, {
            params ["", "_handle"];
            if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении
            
            switch (true) do {
                case (!isNil "WMT_Global_EndMission"): { // Админское завершение
                    timeToEnd = 0;
                    publicVariable "timeToEnd";
                    [0, true] call TVD_endMission; // Быстрое завершение
                };
                case ((missionNamespace getVariable ["WMT_Global_LeftTime", [3600]]) select 0 < 300): { // Истечение времени
                    timeToEnd = 1;
                    publicVariable "timeToEnd";
                    [1, false] call TVD_endMission; // Плавное завершение
                };
                case (TVD_HeavyLosses != sideLogic): { // Тяжёлые потери
                    timeToEnd = 2;
                    publicVariable "timeToEnd";
                    [2, false, TVD_HeavyLosses] call TVD_endMission; // Завершение с указанием стороны
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
        }, 3] call CBA_fnc_addPerFrameHandler; // Проверка каждые 3 секунды
    }] call CBA_fnc_waitUntilAndExecute;
};