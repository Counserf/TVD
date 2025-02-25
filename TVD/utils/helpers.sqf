#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides)

/*
 * Преобразует цвет маркера в сторону
 * Параметры:
 *   _color: строка - цвет маркера (например, "ColorBlufor")
 * Возвращает: сторона - соответствующая сторона (west, east, etc.)
 */
TVD_colorToSide = {
    params ["_color"];
    switch (toLower _color) do { // Исправлено на toLower для надёжности
        case "colorblufor": {west};
        case "colorwest": {west};
        case "coloropfor": {east};
        case "coloreast": {east};
        case "colorindependent": {resistance};
        case "colorguer": {resistance};
        case "colorcivilian": {civilian};
        case "colorciv": {civilian};
        default {sideLogic}; // По умолчанию нейтральная сторона
    };
};

/*
 * Преобразует сторону в цвет маркера
 * Параметры:
 *   _side: сторона - сторона (west, east, etc.)
 * Возвращает: строка - соответствующий цвет маркера
 */
TVD_sideToColor = {
    params ["_side"];
    switch (_side) do {
        case west: {"ColorBLUFOR"}; // Унифицировано с современными стандартами
        case east: {"ColorOPFOR"};
        case resistance: {"ColorIndependent"};
        case civilian: {"ColorCivilian"};
        default {"ColorBlack"}; // По умолчанию чёрный цвет
    };
};

/*
 * Преобразует сторону в числовой индекс
 * Параметры:
 *   _side: сторона - сторона (west, east, etc.)
 * Возвращает: число - индекс стороны (0-4)
 */
TVD_sideToIndex = {
    params ["_side"];
    switch (_side) do {
        case west: {1};
        case east: {0};
        case resistance: {2};
        case civilian: {3};
        case sideLogic: {4};
        default {-1}; // Неверная сторона
    };
};

/*
 * Преобразует роль юнита в текстовое описание
 * Параметры:
 *   _role: строка - роль юнита (например, "sideLeader")
 * Возвращает: строка - описание роли (например, "КС")
 */
TVD_unitRole = {
    params ["_role"];
    switch (_role) do {
        case "sideLeader": {"КС"}; // Командир стороны
        case "execSideLeader": {"исп.КС"}; // Исполняющий обязанности командира
        case "squadLeader": {"КО"}; // Командир отделения
        case "crewTank": {"Экипаж(Т)"}; // Экипаж танка
        case "crewAPC": {"Экипаж(БТР)"}; // Экипаж БТР
        case "pilot": {"Пилот"}; // Пилот
        case "sniper": {"Снайпер"}; // Снайпер
        case "vip": {"Спец-юнит"}; // Особый юнит
        case "soldier": {""}; // Обычный солдат
        default {""}; // Неизвестная роль
    };
};

/*
 * Добавляет очки стороне с опциональным логированием и уведомлением
 * Параметры:
 *   _side: сторона - сторона для добавления очков
 *   _score: число - количество очков
 *   _logIt: логическое (опционально) - логировать ли событие
 *   _message: строка (опционально) - сообщение для лога и уведомления
 *   _notify: логическое (опционально) - показывать ли уведомление
 */
TVD_addSideScore = {
    params ["_side", "_score", ["_logIt", false], ["_message", ""], ["_notify", false]];
    private _us = TVD_Sides find _side; // Индекс стороны
    
    waitUntil {sleep 1; !isNil "TVD_SidesResScore"}; // Ожидание инициализации резерва
    
    if (_us == -1) then { // Проверка корректности стороны
        [format ["ОШИБКА! Сторона %1 не верна. Допустимые стороны: %2", _side, TVD_Sides], "title"] call TVD_notifyPlayers;
    } else {
        TVD_InitScore set [1 - _us, (TVD_InitScore select (1 - _us)) + _score]; // Добавление очков противоположной стороне
        if (_logIt) then {[_side, _message, _notify] call TVD_completeTask}; // Завершение задачи с логированием
    };
};