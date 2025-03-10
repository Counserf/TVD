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
    [] call TVD_waitForStart; // Используем общую функцию ожидания старта миссии

    // Исправление: фиксируем состав сторон один раз после a3a_var_started
    if (isNil "TVD_BlueforPlayers" || isNil "TVD_OpforPlayers") then { diag_log "TVD/heavy_losses.sqf: Player lists not initialized"; };
    TVD_PlayerCountInit = [
        count TVD_BlueforPlayers, // Используем кэшированный список один раз
        count TVD_OpforPlayers,   // Используем кэшированный список один раз
        0 // Резерв для совместимости
    ];
    diag_log format ["TVD/heavy_losses.sqf: Initial player count fixed - Bluefor: %1, Opfor: %2", TVD_PlayerCountInit select 0, TVD_PlayerCountInit select 1];

    // Асинхронный мониторинг потерь
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении миссии
        
        // Текущее число игроков с учётом союзников
        TVD_PlayerCountNow = [
            count (TVD_BlueforPlayers select {alive _x}),
            count (TVD_OpforPlayers select {alive _x}),
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

/*
 * Ожидает старта миссии
 * Параметры:
 *   _checkPlayer: логическое (опционально) - проверять ли наличие игрока
 */
TVD_waitForStart = {
    params [["_checkPlayer", false]];
    waitUntil {sleep 2; missionNamespace getVariable ["a3a_var_started", false] && (!_checkPlayer || !isNull player)};
};