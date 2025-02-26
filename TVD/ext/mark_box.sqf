#include "\x\cba\addons\main\script_macros.hpp"
#include "..\config.sqf"

TVD_markBox = {
    if (isServer) then {
        private _markers = [];
        {
            private _markData = _x getVariable ["TVD_markBox", []];
            if (_markData isNotEqualTo []) then {
                private _marker = createMarker [str _x, position _x];
                _marker setMarkerColor "ColorOrange";
                _marker setMarkerText (_markData select 1);
                _marker setMarkerType "mil_dot";
                _markers pushBack [_marker, _markData select 0];
                
                [{time > 300}, {
                    deleteMarker (_this select 0);
                }, [_marker]] call CBA_fnc_waitUntilAndExecute;
            };
        } forEach vehicles;
        publicVariable "TVD_BoxMarkers";
        TVD_BoxMarkers = _markers;
    };

    if (!isDedicated) then {
        waitUntil {!isNil "TVD_BoxMarkers"};
        {
            _x params ["_marker", "_side"];
            if (side group player == _side) then {
                private _localMarker = createMarkerLocal [_marker, getMarkerPos _marker];
                _localMarker setMarkerColorLocal "ColorOrange";
                _localMarker setMarkerTextLocal (markerText _marker);
                _localMarker setMarkerTypeLocal "mil_dot";
            };
        } forEach TVD_BoxMarkers;
    };
};