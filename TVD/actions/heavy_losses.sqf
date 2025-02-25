#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии

/*
 * Мониторит тяжёлые потери сторон и устанавливает флаги отступления или завершения
 */
TVD_monitorHeavyLosses = {
    // Лимиты игроков для сторон (bluefor, opfor, резерв для совместимости)
    if (isNil "TVD_hl_sidelimits") then {TVD_hl_sidelimits = [0, 0, 0]};
    // Порог потерь для завершения (используется TVD_CriticalLossRatio из config.sqf)
    if (isNil "TVD_hl_ratio") then {TVD_hl_ratio = TVD_CriticalLossRatio};

    waitUntil {sleep 1.5; time > 60}; // Ожидание начала миссии (1 минута)
    waitUntil {sleep 2; missionNamespace getVariable ["a3a_var_started", false]}; // Ожидание окончания заморозки

    // Инициализация начального числа игроков с учётом союзников
    TVD_PlayerCountInit = [
        {(side _x in TVD_BlueforAllies) && isPlayer _x} count allPlayers, // Bluefor + союзники
        {(side _x in TVD_OpforAllies) && isPlayer _x} count allPlayers,   // Opfor + союзники
        0 // Резерв для совместимости, не используется
    ];

    // Асинхронный мониторинг потерь
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении миссии
        
        // Текущее число игроков с учётом союзников
        TVD_PlayerCountNow = [
            {(side _x in TVD_BlueforAllies) && isPlayer _x} count allPlayers,
            {(side _x in TVD_OpforAllies) && isPlayer _x} count allPlayers,
            0
        ];

        // Проверка потерь для каждой стороны
        {
            private _playerratio = TVD_hl_ratio select _forEachIndex; // Порог для завершения из TVD_CriticalLossRatio
            private _playersBegin = TVD_PlayerCountInit select _forEachIndex; // Начальное число игроков
            private _playersNow = TVD_PlayerCountNow select _forEachIndex; // Текущее число игроков
            
            if (_playersBegin != 0) then {
                private _ratio = _playersNow / _playersBegin; // Текущий процент выживания
                if (_ratio < TVD_RetreatRatio && _forEachIndex < count TVD_SideCanRetreat && !(TVD_SideCanRetreat select _forEachIndex)) then {
                    TVD_SideCanRetreat set [_forEachIndex, true]; // Разрешение отступления
                    publicVariable "TVD_SideCanRetreat";
                };
                if (_playerratio != 0 && _ratio < _playerratio) exitWith { // Завершение из-за тяжёлых потерь
                    TVD_HeavyLosses = TVD_Sides select _forEachIndex;
                    publicVariable "TVD_HeavyLosses";
                    [_handle] call CBA_fnc_removePerFrameHandler;
                };
                if (_playersNow <= (TVD_hl_sidelimits select _forEachIndex)) exitWith { // Завершение из-за лимита
                    TVD_HeavyLosses = TVD_Sides select _forEachIndex;
                    publicVariable "TVD_HeavyLosses";
                    [_handle] call CBA_fnc_removePerFrameHandler;
                };
            };
        } forEach [0, 1]; // Проверка только для bluefor и opfor
    }, 10] call CBA_fnc_addPerFrameHandler; // Проверка каждые 10 секунд
};