#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (используется для TVD_notifyPlayers)

/*
 * Механика обыска для юнитов в плену или без сознания (требуется ACE3)
 */
TVD_frisk = {
    waitUntil {sleep 5; missionNamespace getVariable ["a3a_var_started", false]}; // Ожидание окончания заморозки миссии

    // Проверка наличия ACE3, без которого механика обыска невозможна
    if (!isClass (configFile >> "CfgPatches" >> "ace_main")) exitWith {
        diag_log "TVD/frisk.sqf: ACE3 not detected, frisk functionality disabled"; // Логирование отсутствия ACE3
    };

    /*
     * Добавляет действие "Обыскать" к юниту
     * Параметры:
     *   _target: объект - юнит, который будет обыскан
     */
    TVD_addFriskAction = {
        params ["_target"];
        private _action = _target addAction ["<t color='#0353f5'>Обыскать</t>", { // Действие синего цвета
            params ["_target", "_caller"];
            _caller action ["Gear", _target]; // Открытие инвентаря цели для обыска
            
            private _notifyUnits = (_target nearEntities 5) select {isPlayer _x}; // Игроки в радиусе 5 метров от цели
            if (_notifyUnits isNotEqualTo []) then {
                [_notifyUnits, format ["%1 обыскивает %2", name _caller, name _target], "title"] call TVD_notifyPlayers; // Уведомление об обыске
            };
        }, [], -1, false, true, "", "(_this != _target) && (_this distance _target <= 3) && (_target getVariable ['ace_captives_ishandcuffed', false] || _target getVariable ['ACE_isUnconscious', false])"]; // Условие: рядом, в плену или без сознания
        
        // Удаление действия, если юнит выходит из состояния плена/бессознательности или умирает
        [{!(_this getVariable ["ace_captives_ishandcuffed", false]) && !(_this getVariable ["ACE_isUnconscious", false]) || !alive _this}, {
            params ["_target", "_action"];
            _target removeAction _action; // Удаление действия
            _target setVariable ["TVD_friskActionSent", false, true]; // Сброс флага отправки действия
        }, [_target, _action]] call CBA_fnc_waitUntilAndExecute;
    };

    // Глобальный обработчик события захвата юнита для добавления действия
    ["TVD_Captured", {[_this select 1] spawn TVD_addFriskAction}] call CBA_fnc_addEventHandler;

    // Серверная часть: добавление обработчиков событий ACE3 для всех игроков
    if (isServer) then {
        {if (isPlayer _x) then {_x setVariable ["TVD_friskActionSent", false]}} forEach allPlayers; // Инициализация флага для всех игроков
        
        {
            // Обработчик события "взятие в плен" (ACE3)
            [_x, "ace_captives_ishandcuffed", {
                params ["_unit", "_isHandcuffed"];
                if (_isHandcuffed && !(_unit getVariable ["TVD_friskActionSent", false])) then {
                    _unit setVariable ["TVD_friskActionSent", true]; // Установка флага отправки действия
                    TVD_Captured = _unit; // Установка глобальной переменной для события
                    publicVariable "TVD_Captured"; // Синхронизация события для клиентов
                    if (!isDedicated) then {[_unit] spawn TVD_addFriskAction}; // Локальный вызов на хосте
                };
            }] call CBA_fnc_addBISEventHandler;
            
            // Обработчик события "потеря сознания" (ACE3)
            [_x, "ACE_isUnconscious", {
                params ["_unit", "_isUnconscious"];
                if (_isUnconscious && !(_unit getVariable ["TVD_friskActionSent", false])) then {
                    _unit setVariable ["TVD_friskActionSent", true]; // Установка флага отправки действия
                    TVD_Captured = _unit; // Установка глобальной переменной для события
                    publicVariable "TVD_Captured"; // Синхронизация события для клиентов
                    if (!isDedicated) then {[_unit] spawn TVD_addFriskAction}; // Локальный вызов на хосте
                };
            }] call CBA_fnc_addBISEventHandler;
        } forEach allPlayers;
    };
};