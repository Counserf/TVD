#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Обрабатывает захват техники новым владельцем
 * Параметры:
 *   _vehicle: объект - техника, которую захватывают
 *   _unit: объект - юнит, выполняющий захват
 */
TVD_captureVehicle = {
    params ["_vehicle", "_unit"];
    if (isNull _vehicle || isNull _unit) exitWith {}; // Выход, если техника или юнит отсутствуют
    
    private _side = side _unit; // Сторона захватывающего юнита
    if (_side in TVD_Sides && _side != _vehicle getVariable ["TVD_CapOwner", sideLogic]) then { // Проверка: сторона в игре и не текущий владелец
        _vehicle setVariable ["TVD_CapOwner", _side, true]; // Установка нового владельца с публичной синхронизацией
        private _unitValue = _vehicle getVariable ["TVD_UnitValue", [nil, 0]] select 1; // Ценность техники
        if (_unitValue > 1) then { // Логирование, если ценность больше 1
            ["capVehicle", _vehicle, TVD_Sides find _side] call TVD_logEvent;
        };
    };
};