#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии

/*
 * Завершает миссию с уведомлением и дебрифингом
 * Параметры:
 *   _endCause: число - причина завершения миссии (0 - админ, 1 - время, 2 - тяжёлые потери, 3 - отступление, 4 - выполнение задачи)
 *   _express: логическое (опционально) - быстрое (true) или плавное (false) завершение, по умолчанию false
 *   _specificSide: сторона (опционально) - сторона для причин 2, 3, 4, по умолчанию sideLogic
 *   _noReplay: логическое (опционально) - завершение без реплея (true), по умолчанию false
 */
TVD_endMission = {
    params ["_endCause", "_express" = false, "_specificSide" = sideLogic, ["_noReplay", false]];
    
    // Проверка времени миссии через a3a_endMissionTime
    if (isNil "a3a_endMissionTime") then {missionNamespace setVariable ["a3a_endMissionTime", 3600, true]}; // 1 час по умолчанию, если не задано
    if (_endCause == -1 && {time > missionNamespace getVariable ["a3a_endMissionTime", 3600]}) then {_endCause = 1}; // Время вышло
    
    // Расчёт результатов миссии с учётом причины завершения
    private _missionResults = if (_endCause == 2 || _endCause == 3) then {
        [_endCause, TVD_Sides find _specificSide] call TVD_calculateWin
    } else {
        [_endCause] call TVD_calculateWin
    };
    
    // Логирование итогов на сервере
    if (isServer) then {
        [_missionResults, _endCause] call TVD_logMission;
    };
    
    private _winner = _missionResults select 0;
    private _textOut = [_endCause, _missionResults] call TVD_writeDebrief;
    
    // Формирование сообщения для завершения
    private _endMessage = switch (_endCause) do {
        case 0: {localize "STR_TVD_LogMissionEndAdmin"}; // Админ завершил миссию
        case 1: {localize "STR_TVD_TimeOut"};           // Время миссии истекло
        case 2: {format [localize "STR_TVD_HeavyLosses", TVD_HeavyLosses]}; // Тяжёлые потери
        case 3: {format [localize "STR_TVD_SideRetreated", TVD_SideRetreat]}; // Сторона отступила
        case 4: {format [localize "STR_TVD_KeyTaskCompleted", TVD_MissionComplete]}; // Ключевая задача выполнена
        default {"Mission ended"}; // Неизвестная причина
    };
    
    // Завершение миссии на сервере
    if (isServer) then {
        if (_noReplay) then {
            ["Миссия завершена администратором"] remoteExec ["hint", 0]; // Уведомление всем игрокам
            sleep 2; // Небольшая задержка для отображения уведомления
            [_endMessage] remoteExec ["endMission", 0]; // Прямое завершение без реплея через дефолтный Arma 3 механизм
        } else {
            [_endMessage, _winner] call a3a_fnc_endMission; // Завершение через a3a с возможностью реплея
            // Локальная обработка дебрифинга для клиентов (только если не _noReplay)
            [[_textOut, _winner, _express, _missionResults select 1], {
                params ["_textOut", "_winner", "_express", "_sup"];
                private _isPlayerWin = (playerSide in ([_winner] call BIS_fnc_friendlySides)) && (_winner != sideLogic); // Проверка победы стороны игрока
                private _tColor = if (_isPlayerWin) then {"#057f05"} else {"#7f0505"}; // Зелёный для победы, красный для поражения
                private _compText = if (_sup == 0) then { // Ничья
                    parseText format ["<t size='2.0' align='center' shadow='2'>%1</t><br/>", localize "STR_TVD_DebriefTie"]
                } else { // Победа или поражение
                    private _prefs = if (_isPlayerWin) then { // Массив степеней победы
                        [localize "STR_TVD_DebriefMinor", localize "STR_TVD_DebriefMajor", localize "STR_TVD_DebriefCrushing"]
                    } else { // Массив степеней поражения
                        [localize "STR_TVD_DebriefMinorLoss", localize "STR_TVD_DebriefMajorLoss", localize "STR_TVD_DebriefCrushingLoss"]
                    };
                    composeText [parseText format ["<t size='2.0' color='%1' align='center' shadow='2'>%2 %3</t><br/>", 
                        _tColor, 
                        _prefs select (_sup - 1), 
                        if (_isPlayerWin) then {localize "STR_TVD_DebriefVictory"} else {localize "STR_TVD_DebriefDefeat"}
                    ]]
                };
                
                _textOut = composeText [_compText, _textOut]; // Объединение заголовка с текстом
                if (player != vehicle player) then {(vehicle player) addEventHandler ["HandleDamage", {false}]}; // Отключение урона для техники игрока
                player addEventHandler ["HandleDamage", {false}]; // Отключение урона для игрока
                
                if (_express) then {
                    [localize "STR_TVD_MissionResults", _textOut] spawn TVD_quickEnd; // Быстрое завершение
                } else {
                    [localize "STR_TVD_MissionEnd", _textOut, _isPlayerWin] spawn TVD_smoothEnd; // Плавное завершение
                };
            }] remoteExec ["call", 0];
        };
    };
};

/*
 * Выполняет быстрое завершение миссии с показом дебрифинга на 25 секунд
 * Параметры:
 *   _title: строка - заголовок дебрифинга
 *   _text: текст - содержимое дебрифинга
 */
TVD_quickEnd = {
    params ["_title", "_text"];
    private _timer = diag_tickTime; // Локальное время для отсчёта
    while {diag_tickTime - _timer < 25} do { // Показ на 25 секунд
        _title hintC _text; // Отображение дебрифинга
        hintC_arr_EH = findDisplay 72 displayAddEventHandler ["unload", { // Обработчик закрытия подсказки
            0 = _this spawn {
                _this select 0 displayRemoveEventHandler ["unload", hintC_arr_EH];
                hintSilent ""; // Очистка экрана
            };
        }];
        sleep 0.01; // Частое обновление для плавности
    };
};

/*
 * Выполняет плавное завершение миссии с затемнением и дебрифингом
 * Параметры:
 *   _preMessage: строка - предварительное сообщение перед затемнением
 *   _text: текст - содержимое дебрифинга
 *   _isWin: логическое - победа стороны игрока
 */
TVD_smoothEnd = {
    params ["_preMessage", "_text", "_isWin"];
    ["<t size='1.5'>" + _preMessage + "</t>", "bis_fnc_dynamictext"] remoteExec ["spawn", 0]; // Уведомление о завершении всем игрокам
    sleep 2;
    titleText ["", "BLACK OUT", 5]; // Затемнение экрана на 5 секунд
    sleep 5;
    
    private _timer = diag_tickTime; // Локальное время для отсчёта
    while {diag_tickTime - _timer < 25} do { // Показ дебрифинга на 25 секунд
        localize "STR_TVD_MissionResults" hintC _text;
        hintC_arr_EH = findDisplay 72 displayAddEventHandler ["unload", { // Обработчик закрытия подсказки
            0 = _this spawn {
                _this select 0 displayRemoveEventHandler ["unload", hintC_arr_EH];
                hintSilent "";
            };
        }];
        sleep 0.01; // Частое обновление
    };
};

/*
 * Мониторит условия завершения миссии и предоставляет возможность продления
 * Параметры:
 *   _endCause: число - причина завершения миссии (2-4)
 *   _specificSide: сторона (опционально) - сторона для причин 2, 3, 4
 */
TVD_monitorEnd = {
    params ["_endCause", "_specificSide" = sideLogic];
    em_result = false; // Флаг завершения мониторинга
    em_ttw = 60 min ((missionNamespace getVariable ["a3a_endMissionTime", 3600]) - time); // Время до конца от a3a
    em_actContinueAdded = -1; // ID действия продления
    em_bonus = TVD_TimeExtendLimit; // Количество доступных продлений
    em_extended = false; // Флаг продления

    // Формирование сообщения о причине завершения
    private _message = switch (_endCause) do {
        case 2: {localize "STR_TVD_HeavyLosses"};
        case 3: {format [localize "STR_TVD_SideRetreated", _specificSide]};
        case 4: {format [localize "STR_TVD_KeyTaskCompleted", _specificSide]};
        default {""};
    };
    
    private _showTo = if (_endCause == 2) then {TVD_Sides select (1 - (TVD_Sides find _specificSide))} else {TVD_Sides}; // Кому показывать уведомление
    if (_message != "") then {
        [_showTo, format ["%1<br/><br/>%2", _message, [em_ttw, "MM:SS"] call BIS_fnc_secondsToString], "dynamic"] call TVD_notifyPlayers; // Уведомление о завершении
    };
    
    private _startTime = diag_tickTime; // Начало отсчёта времени
    // Асинхронный цикл мониторинга
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        _args params ["_startTime", "_endCause", "_specificSide"];
        
        private _waitTime = 0 max (em_ttw - (diag_tickTime - _startTime)); // Оставшееся время
        if (_waitTime <= 1) exitWith { // Завершение при истечении времени
            em_result = true;
            [_handle] call CBA_fnc_removePerFrameHandler;
        };
        
        // Клиентская часть: обновление интерфейса и действия командира
        if (!isDedicated) then {
            hint format [localize "STR_TVD_EndWarning", [_waitTime, "MM:SS"] call BIS_fnc_secondsToString, em_bonus]; // Показ таймера игрокам
            if (em_extended) then {
                em_extended = false;
                publicVariable "em_extended";
                [localize "STR_TVD_MissionExtended", "dynamic"] call TVD_notifyPlayers; // Уведомление о продлении
            };
            
            private _unitValue = player getVariable ["TVD_UnitValue", []];
            if (count _unitValue > 2 && {_unitValue select 2 in ["sideLeader", "execSideLeader"]} && _waitTime < 60 && em_actContinueAdded != -2) then {
                titleText [localize "STR_TVD_EndExtendPrompt", "PLAIN DOWN"]; // Подсказка командиру
                if (em_actContinueAdded == -1) then {
                    em_actContinueAdded = player addAction ["<t color='#ffffff'>" + localize "STR_TVD_ExtendMission" + "</t>", { // Действие продления
                        em_ttw = em_ttw + 300; // Увеличение времени на 5 минут
                        publicVariable "em_ttw";
                        missionNamespace setVariable ["a3a_endMissionTime", (missionNamespace getVariable ["a3a_endMissionTime", 3600]) + 300, true]; // Обновление времени миссии
                        player removeAction em_actContinueAdded;
                        em_actContinueAdded = -1;
                        publicVariable "em_actContinueAdded";
                        em_bonus = em_bonus - 1;
                        publicVariable "em_bonus";
                        em_extended = true;
                        publicVariable "em_extended";
                    }, nil, 0, false, true, "", "em_actContinueAdded != -2"];
                };
            };
        };
        
        // Серверная часть: отключение продления при исчерпании лимита
        if (isServer && em_bonus <= 0) then {
            em_actContinueAdded = -2;
            publicVariable "em_actContinueAdded";
        };
    }, 1, [_startTime, "_endCause", "_specificSide"]] call CBA_fnc_addPerFrameHandler;
    
    waitUntil {sleep 1; em_result}; // Ожидание завершения мониторинга
};