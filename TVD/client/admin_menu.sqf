#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии

// Определение идентификатора диалога
#define TVD_ADMIN_DIALOG_IDD 9999

// Создание диалога администратора
TVD_showAdminMenu = {
    if (!serverCommandAvailable "#kick") exitWith {hint "Вы не администратор!";}; // Выход, если игрок не администратор
    createDialog "TVD_Admin_EndMission"; // Создание диалога
};

// Обработчик нажатия клавиш для вызова меню (Ctrl + ])
waitUntil {!isNull (findDisplay 46)}; // Ожидание загрузки основного дисплея
(findDisplay 46) displayAddEventHandler ["KeyDown", {
    params ["_display", "_key", "_shift", "_ctrl", "_alt"];
    if (_key == 221 && _ctrl && !(_shift || _alt) && serverCommandAvailable "#kick") then { // 221 - код клавиши "]"
        [] call TVD_showAdminMenu; // Вызов меню при нажатии Ctrl + ]
        true // Подтверждение обработки события
    } else {
        false // Продолжение обработки других событий
    };
}];

// Функции обработки выбора администратора
TVD_adminEndMissionTechnical = {
    ["TVD_Admin_Action", ["Техническое завершение", sideUnknown, false]] call CBA_fnc_globalEvent; // Отправка события серверу
    closeDialog 0; // Закрытие диалога
};

TVD_adminEndMissionNoReplay = {
    ["TVD_Admin_Action", ["Техническое завершение без реплея", sideUnknown, true]] call CBA_fnc_globalEvent; // Отправка события серверу
    closeDialog 0; // Закрытие диалога
};

TVD_adminKillAllAI = {
    ["TVD_Admin_Action", ["Убить всех ботов"]] call CBA_fnc_globalEvent; // Отправка события серверу для уничтожения ботов
    closeDialog 0; // Закрытие диалога
};

// Определение диалога
class TVD_Admin_EndMission {
    idd = TVD_ADMIN_DIALOG_IDD;
    movingEnable = false;
    enableSimulation = true;
    onLoad = "uiNamespace setVariable ['TVD_Admin_EndMission_Display', _this select 0];";
    
    class controlsBackground {
        class Background: RscText {
            idc = -1;
            x = 0.35 * safezoneW + safezoneX;
            y = 0.35 * safezoneH + safezoneY;
            w = 0.3 * safezoneW;
            h = 0.28 * safezoneH; // Уменьшено для трёх кнопок
            colorBackground[] = {0, 0, 0, 0.8};
        };
    };
    
    class controls {
        class Title: RscText {
            idc = -1;
            text = "Админское меню";
            x = 0.35 * safezoneW + safezoneX;
            y = 0.35 * safezoneH + safezoneY;
            w = 0.3 * safezoneW;
            h = 0.04 * safezoneH;
            colorText[] = {1, 1, 1, 1};
            colorBackground[] = {0.1, 0.1, 0.1, 1};
        };
        
        class ButtonTechnical: RscButton {
            idc = 1600;
            text = "Техническое завершение";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.40 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminEndMissionTechnical";
        };
        
        class ButtonNoReplay: RscButton {
            idc = 1601;
            text = "Завершение без реплея";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.46 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminEndMissionNoReplay";
        };
        
        class ButtonKillAI: RscButton {
            idc = 1602;
            text = "Убить всех ботов";
            x = 0.36 * safezoneW + safezoneX;
            y = 0.52 * safezoneH + safezoneY;
            w = 0.28 * safezoneW;
            h = 0.04 * safezoneH;
            action = "call TVD_adminKillAllAI";
        };
    };
};