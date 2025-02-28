#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии

// Определение идентификатора диалога администратора
#define TVD_ADMIN_DIALOG_IDD 9999

/*
 * Открывает диалог администратора для завершения миссии или уничтожения AI
 */
TVD_showAdminMenu = {
    if (!([player] call TVD_isAdmin)) exitWith {hint "Вы не администратор!";}; // Используем общую функцию проверки прав
    // Исправление средней проблемы: серверная проверка прав перед открытием
    ["TVD_AdminCheck", [player]] remoteExecCall ["CBA_fnc_serverEvent", 2];
    waitUntil {!isNil {player getVariable "TVD_adminApproved"}};
    if (player getVariable ["TVD_adminApproved"]) then {
        createDialog "TVD_Admin_EndMission"; // Открытие диалога только после подтверждения с сервера
    } else {
        hint "Вы не администратор! Доступ запрещён.";
    };
    player setVariable ["TVD_adminApproved", nil]; // Сброс флага
};

// Серверная проверка прав администратора
if (isServer && isNil "TVD_AdminCheckEH") then {
    TVD_AdminCheckEH = ["TVD_AdminCheck", {
        params ["_player"];
        _player setVariable ["TVD_adminApproved", serverCommandAvailable "#kick", true];
    }] call CBA_fnc_addEventHandler;
};

// Ожидание загрузки основного дисплея и добавление обработчика нажатия клавиш
waitUntil {!isNull (findDisplay 46)}; // Ожидание загрузки основного дисплея игры
if (isNil "TVD_AdminKeyHandler") then { // Проверка на повторное добавление обработчика
    TVD_AdminKeyHandler = (findDisplay 46) displayAddEventHandler ["KeyDown", {
        params ["_display", "_key", "_shift", "_ctrl", "_alt"];
        if (_key == 221 && _ctrl && !(_shift || _alt) && ([player] call TVD_isAdmin)) then { // 221 - код клавиши "]", используем TVD_isAdmin
            [] call TVD_showAdminMenu; // Вызов меню при нажатии Ctrl + ]
            true // Подтверждение обработки события
        } else {
            false // Продолжение обработки других событий
        };
    }];
};

/*
 * Завершает миссию технически с дебрифингом через a3a_fnc_endMission
 */
TVD_adminEndMissionTechnical = {
    ["Техническое завершение", sideUnknown, false] call TVD_executeAdminAction; // Используем общую функцию
};

/*
 * Завершает миссию без реплея через endMission
 */
TVD_adminEndMissionNoReplay = {
    ["Техническое завершение без реплея", sideUnknown, true] call TVD_executeAdminAction; // Используем общую функцию
};

/*
 * Уничтожает всех AI-юнитов без уведомления игроков
 */
TVD_adminKillAllAI = {
    ["Убить всех ботов", sideUnknown, false] call TVD_executeAdminAction; // Используем общую функцию
};

/*
 * Выполняет административное действие и закрывает диалог
 * Параметры:
 *   _action: строка - тип действия
 *   _winner: сторона - победитель (по умолчанию sideUnknown)
 *   _noReplay: логическое - завершение без реплея
 */
TVD_executeAdminAction = {
    params ["_action", "_winner", "_noReplay"];
    ["TVD_Admin_Action", [_action, _winner, _noReplay]] call CBA_fnc_globalEvent; // Отправка события серверу
    closeDialog 0; // Закрытие диалога после выбора
};

/*
 * Проверяет, является ли юнит администратором
 * Параметры:
 *   _unit: объект - проверяемый юнит
 * Возвращает: логическое - является ли юнит администратором
 */
TVD_isAdmin = {
    params ["_unit"];
    serverCommandAvailable "#kick" && isPlayer _unit
};

// Определение структуры диалога администратора
class TVD_Admin_EndMission {
    idd = TVD_ADMIN_DIALOG_IDD; // Идентификатор диалога
    movingEnable = false; // Запрет перемещения диалога
    enableSimulation = true; // Включение симуляции во время диалога
    onLoad = "uiNamespace setVariable ['TVD_Admin_EndMission_Display', _this select 0];"; // Сохранение дисплея в uiNamespace
    
    class controlsBackground {
        class Background: RscText { // Фон диалога
            idc = -1;
            x = 0.35 * safezoneW + safezoneX; // Позиция X с учётом безопасной зоны
            y = 0.35 * safezoneH + safezoneY; // Позиция Y с учётом безопасной зоны
            w = 0.3 * safezoneW; // Ширина диалога
            h = 0.28 * safezoneH; // Высота диалога (для трёх кнопок)
            colorBackground[] = {0, 0, 0, 0.8}; // Полупрозрачный чёрный фон
        };
    };
    
    class controls {
        class Title: RscText { // Заголовок диалога
            idc = -1;
            text = "Админское меню"; // Текст заголовка
            x = 0.35 * safezoneW + safezoneX;
            y = 0.35 * safezoneH + safezoneY;
            w = 0.3 * safezoneW;
            h = 0.04 * safezoneH;
            colorText[] = {1, 1, 1, 1}; // Белый цвет текста
            colorBackground[] = {0.1, 0.1, 0.1, 1}; // Тёмно-серый фон заголовка
        };
        
        class ButtonTechnical: RscButton { // Кнопка "Техническое завершение"
            idc = 1600;
            text = "Техническое завершение";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.40 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminEndMissionTechnical"; // Вызов функции при нажатии
        };
        
        class ButtonNoReplay: RscButton { // Кнопка "Завершение без реплея"
            idc = 1601;
            text = "Завершение без реплея";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.46 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminEndMissionNoReplay"; // Вызов функции при нажатии
        };
        
        class ButtonKillAI: RscButton { // Кнопка "Убить всех ботов"
            idc = 1602;
            text = "Убить всех ботов";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.52 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminKillAllAI"; // Вызов функции при нажатии
        };
    };
};