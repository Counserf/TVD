#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Создаёт локальные маркеры для ящиков на карте для игроков соответствующей стороны
 */
TVD_markBox = {
    {
        private _markData = _x getVariable ["TVD_markBox", []]; // Данные для маркировки [сторона, текст]
        if (_markData isNotEqualTo [] && side group player == _markData select 0) then { // Проверка принадлежности стороны
            private _marker = createMarkerLocal [str _x, position _x]; // Создание локального маркера
            _marker setMarkerColorLocal "ColorOrange"; // Установка оранжевого цвета
            _marker setMarkerTextLocal (_markData select 1); // Установка текста (например, "Ящик с Javelin")
            _marker setMarkerTypeLocal "mil_dot"; // Установка типа точки
            
            // Удаление маркера через 5 минут
            [{time > 300}, {deleteMarkerLocal (_this select 0)}, [_marker]] call CBA_fnc_waitUntilAndExecute;
        };
    } forEach vehicles; // Проход по всем транспортным средствам
};