#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_RetreatRatio)

/*
 * Мониторит тяжёлые потери сторон и устанавливает флаги отступления или завершения
 */
TVD_monitorHeavyLosses = {
    if (isNil "TVD_hl_sidelimits") then {TVD_hl_sidelimits = [0, 0, 0]}; // Лимиты игроков для сторон (east, west, resistance)
    if (isNil "TVD_hl_ratio") then {TVD_hl_ratio = [0.2, 0.2, 0.2]}; // Порог потерь для завершения (20%)
    
    waitUntil {sleep 1.5; time > 60}; // Ожидание начала миссии (1 минута)
    waitUntil {sleep 2; missionNamespace getVariable ["a3a_var_started", false]}; // Ожидание окончания заморозки

    // Определение дружеской стороны для resistance
    private _resistanceFriendSide = switch (true) do {
        case (west in ([resistance] call BIS_fnc_friendlySides)): {west};
        case (east in ([resistance] call BIS_fnc_friendlySides)): {east};
        default {sideUnknown};
    };

    // Инициализация начального числа игроков
    TVD_PlayerCountInit = [
        {side _x == east && isPlayer _x} count allPlayers,
        {side _x == west && isPlayer _x} count allPlayers,
        {side _x == resistance && isPlayer _x} count allPlayers
    ];

    // Асинхронный мониторинг потерь
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        _args params ["_resistanceFriendSide"];
        
        if (timeToEnd != -1) exitWith {[_handle] call CBA_fnc_removePerFrameHandler}; // Остановка при завершении миссии
        
        // Текущее число игроков
        TVD_PlayerCountNow = [
            {side _x == east && isPlayer _x} count allPlayers,
            {side _x == west && isPlayer _x} count allPlayers,
            {side _x == resistance && isPlayer _x} count allPlayers
        ];

        // Проверка потерь для каждой стороны
        {
            private _playerratio = TVD_hl_ratio select _forEachIndex; // Порог для завершения
            if (_x in [east, west] || _resistanceFriendSide == sideUnknown) then {
                private _playersBegin = TVD_PlayerCountInit select _forEachIndex + (if (_x == _resistanceFriendSide) then {TVD_PlayerCountInit select 2} else {0}); // Начальное число с учётом resistance
                private _playersNow = TVD_PlayerCountNow select _forEachIndex + (if (_x == _resistanceFriendSide) then {TVD_PlayerCountNow select 2} else {0}); // Текущее число
                
                if (_playersBegin != 0) then {
                    private _ratio = _playersNow / _playersBegin; // Текущий процент выживания
                    if (_ratio < TVD_RetreatRatio && _forEachIndex < count TVD_SideCanRetreat && !(TVD_SideCanRetreat select _forEachIndex)) then { // Разрешение отступления
                        TVD_SideCanRetreat set [_forEachIndex, true];
                        publicVariable "TVD_SideCanRetreat";
                    };
                    if (_playerratio != 0 && _ratio < _playerratio) exitWith { // Завершение из-за тяжёлых потерь
                        TVD_HeavyLosses = _x;
                        publicVariable "TVD_HeavyLosses";
                        [_handle] call CBA_fnc_removePerFrameHandler;
                    };
                    if (_playersNow <= (TVD_hl_sidelimits select _forEachIndex)) exitWith { // Завершение из-за лимита
                        TVD_HeavyLosses = _x;
                        publicVariable "TVD_HeavyLosses";
                        [_handle] call CBA_fnc_removePerFrameHandler;
                    };
                };
            };
        } forEach [east, west, resistance];
    }, 10, [_resistanceFriendSide]] call CBA_fnc_addPerFrameHandler; // Проверка каждые 10 секунд
};