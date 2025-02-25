#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Инициализирует механику обыска пленных или бессознательных юнитов
 */
TVD_frisk = {
    waitUntil {sleep 5; missionNamespace getVariable ["a3a_var_started", false]}; // Ожидание начала миссии

    /*
     * Добавляет действие "Обыскать" для заданного юнита
     * Параметры:
     *   _target: объект - юнит, которого можно обыскать
     */
    TVD_addFriskAction = {
        params ["_target"];
        private _action = _target addAction ["<t color='#0353f5'>Обыскать</t>", { // Действие "Обыскать" с синим цветом
            params ["_target", "_caller"];
            _caller action ["Gear", _target]; // Открытие инвентаря цели
            
            private _notifyUnits = (_target nearEntities 5) select {isPlayer _x}; // Ближайшие игроки в радиусе 5 метров
            if (_notifyUnits isNotEqualTo []) then {
                [_notifyUnits, format ["%1 обыскивает %2", name _caller, name _target], "title"] call TVD_notifyPlayers; // Уведомление об обыске
            };
        }, [], -1, false, true, "", "(_this != _target) && (_this distance _target <= 3) && (_target getVariable ['ace_captives_ishandcuffed', false] || _target getVariable ['ACE_isUnconscious', false])"]; // Условия: не сам, расстояние ≤ 3 м, плен или бессознательное состояние
        
        // Удаление действия при изменении состояния
        [{!(_this getVariable ["ace_captives_ishandcuffed", false]) && !(_this getVariable ["ACE_isUnconscious", false]) || !alive _this}, {
            params ["_target", "_action"];
            _target removeAction _action; // Удаление действия
            _target setVariable ["TVD_friskActionSent", false, true]; // Сброс флага
        }, [_target, _action]] call CBA_fnc_waitUntilAndExecute;
    };

    // Обработчик события захвата юнита
    ["TVD_Captured", {[_this select 1] spawn TVD_addFriskAction}] call CBA_fnc_addEventHandler;

    // Серверная часть: отслеживание пленных и бессознательных
    if (isServer) then {
        {if (isPlayer _x) then {_x setVariable ["TVD_friskActionSent", false]}} forEach allPlayers; // Инициализация флага для игроков
        
        // Асинхронная проверка каждые 3 секунды
        [CBA_fnc_addPerFrameHandler, {
            params ["", "_handle"];
            if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении миссии
            private _captives = allPlayers select { // Фильтрация пленных или бессознательных игроков
                (_x getVariable ["ace_captives_ishandcuffed", false] || _x getVariable ["ACE_isUnconscious", false]) && 
                !(_x getVariable ["TVD_friskActionSent", false])
            };
            {
                _x setVariable ["TVD_friskActionSent", true]; // Установка флага отправки действия
                TVD_Captured = _x;
                publicVariable "TVD_Captured"; // Синхронизация события
                if (!isDedicated) then {[_x] spawn TVD_addFriskAction}; // Выполнение на хосте
            } forEach _captives;
        }, 3] call CBA_fnc_addPerFrameHandler;
    };
};