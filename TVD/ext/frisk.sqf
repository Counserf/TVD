#include "\x\cba\addons\main\script_macros.hpp"
#include "..\config.sqf"

TVD_frisk = {
    waitUntil {sleep 5; missionNamespace getVariable ["a3a_var_started", false]};

    TVD_addFriskAction = {
        params ["_target"];
        private _action = _target addAction ["<t color='#0353f5'>Обыскать</t>", {
            params ["_target", "_caller"];
            _caller action ["Gear", _target];
            
            private _notifyUnits = (_target nearEntities 5) select {isPlayer _x};
            if (_notifyUnits isNotEqualTo []) then {
                [_notifyUnits, format ["%1 обыскивает %2", name _caller, name _target], "title"] call TVD_notifyPlayers;
            };
        }, [], -1, false, true, "", "(_this != _target) && (_this distance _target <= 3) && (_target getVariable ['ace_captives_ishandcuffed', false] || _target getVariable ['ACE_isUnconscious', false])"];
        
        [{!(_this getVariable ["ace_captives_ishandcuffed", false]) && !(_this getVariable ["ACE_isUnconscious", false]) || !alive _this}, {
            params ["_target", "_action"];
            _target removeAction _action;
            _target setVariable ["TVD_friskActionSent", false, true];
        }, [_target, _action]] call CBA_fnc_waitUntilAndExecute;
    };

    ["TVD_Captured", {[_this select 1] spawn TVD_addFriskAction}] call CBA_fnc_addEventHandler;

    if (isServer) then {
        {if (isPlayer _x) then {_x setVariable ["TVD_friskActionSent", false]}} forEach allPlayers;
        
        {
            [_x, "ace_captives_ishandcuffed", {
                params ["_unit", "_isHandcuffed"];
                if (_isHandcuffed && !(_unit getVariable ["TVD_friskActionSent", false])) then {
                    _unit setVariable ["TVD_friskActionSent", true];
                    TVD_Captured = _unit;
                    publicVariable "TVD_Captured";
                    if (!isDedicated) then {[_unit] spawn TVD_addFriskAction};
                };
            }] call CBA_fnc_addBISEventHandler;
            
            [_x, "ACE_isUnconscious", {
                params ["_unit", "_isUnconscious"];
                if (_isUnconscious && !(_unit getVariable ["TVD_friskActionSent", false])) then {
                    _unit setVariable ["TVD_friskActionSent", true];
                    TVD_Captured = _unit;
                    publicVariable "TVD_Captured";
                    if (!isDedicated) then {[_unit] spawn TVD_addFriskAction};
                };
            }] call CBA_fnc_addBISEventHandler;
        } forEach allPlayers;
    };
};