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
        [_missionResults, _endCause] call TVD_logMission; // Запись итогов миссии в лог
    };
    
    private _winner = _missionResults select 0; // Победившая сторона из результатов
    private _textOut = [_endCause, _missionResults] call TVD_writeDebrief; // Текст дебрифинга
    
    // Формирование сообщения для завершения в зависимости от причины
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
            ["Миссия завершена администратором"] remoteExec ["hint", 0]; // Уведомление всем игрокам через hint
            sleep 2; // Задержка 2 секунды для отображения уведомления
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
                
                _textOut = composeText [_compText, _textOut]; // Объединение заголовка с текстом дебрифинга
                if (player != vehicle player) then {(vehicle player) addEventHandler ["HandleDamage", {false}]}; // Отключение урона для техники игрока
                player addEventHandler ["HandleDamage", {false}]; // Отключение урона для игрока
                
                if (_express) then {
                    [localize "STR_TVD_MissionResults", _textOut] spawn TVD_quickEnd; // Быстрое завершение с коротким дебрифингом
                } else {
                    [localize "STR_TVD_MissionEnd", _textOut, _isPlayerWin] spawn TVD_smoothEnd; // Плавное завершение с полным дебрифингом
                };
            }] remoteExec ["call", 0]; // Выполнение на всех клиентах
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
    while {diag_tickTime - _timer < 25} do { // Показ дебрифинга на 25 секунд
        _title hintC _text; // Отображение дебрифинга через hintC
        hintC_arr_EH = findDisplay 72 displayAddEventHandler ["unload", { // Обработчик закрытия подсказки
            0 = _this spawn {
                _this select 0 displayRemoveEventHandler ["unload", hintC_arr_EH];
                hintSilent ""; // Очистка экрана после закрытия
            };
        }];
        sleep 0.01; // Частое обновление для плавности отображения
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
    sleep 2; // Задержка перед затемнением
    titleText ["", "BLACK OUT", 5]; // Затемнение экрана на 5 секунд
    sleep 5; // Ожидание завершения затемнения
    
    private _timer = diag_tickTime; // Локальное время для отсчёта
    while {diag_tickTime - _timer < 25} do { // Показ дебрифинга на 25 секунд
        localize "STR_TVD_MissionResults" hintC _text; // Отображение результатов миссии
        hintC_arr_EH = findDisplay 72 displayAddEventHandler ["unload", { // Обработчик закрытия подсказки
            0 = _this spawn {
                _this select 0 displayRemoveEventHandler ["unload", hintC_arr_EH];
                hintSilent ""; // Очистка экрана после закрытия
            };
        }];
        sleep 0.01; // Частое обновление для плавности
    };
};

/*
 * Мониторит условия завершения миссии и предоставляет возможность продления
 * Параметры:
 *   _endCause: число - причина завершения миссии (2-4)
 *   _specificSide: сторона (опционально) - сторона для причин 2, 3, 4, по умолчанию sideLogic
 */
TVD_monitorEnd = {
    params ["_endCause", "_specificSide" = sideLogic];
    private _result = false; // Локальный флаг завершения мониторинга (замена em_result)
    private _ttw = 60 min ((missionNamespace getVariable ["a3a_endMissionTime", 3600]) - time); // Время до конца от a3a
    private _actContinueAdded = -1; // Локальный ID действия продления (замена em_actContinueAdded)
    private _bonus = TVD_TimeExtendLimit; // Локальное количество доступных продлений (замена em_bonus)
    private _extended = false; // Локальный флаг продления (замена em_extended)

    // Формирование сообщения о причине завершения
    private _message = switch (_endCause) do {
        case 2: {localize "STR_TVD_HeavyLosses"}; // Тяжёлые потери
        case 3: {format [localize "STR_TVD_SideRetreated", _specificSide]}; // Отступление стороны
        case 4: {format [localize "STR_TVD_KeyTaskCompleted", _specificSide]}; // Выполнение ключевой задачи
        default {""}; // Пустое сообщение для неизвестной причины
    };
    
    // Определение, кому показывать уведомление
    private _showTo = if (_endCause == 2) then {TVD_Sides select (1 - (TVD_Sides find _specificSide))} else {TVD_Sides};
    if (_message != "") then {
        [_showTo, format ["%1<br/><br/>%2", _message, [_ttw, "MM:SS"] call BIS_fnc_secondsToString], "dynamic"] call TVD_notifyPlayers; // Уведомление о завершении
    };
    
    private _startTime = diag_tickTime; // Начало отсчёта времени
    // Асинхронный цикл мониторинга с локальными переменными
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        _args params ["_startTime", "_endCause", "_specificSide", "_result", "_ttw", "_actContinueAdded", "_bonus", "_extended"];
        
        private _waitTime = 0 max (_ttw - (diag_tickTime - _startTime)); // Оставшееся время
        if (_waitTime <= 1) exitWith { // Завершение при истечении времени
            _result = true;
            [_handle] call CBA_fnc_removePerFrameHandler; // Остановка обработчика
        };
        
        // Клиентская часть: обновление интерфейса и действия командира
        if (!isDedicated) then {
            hint format [localize "STR_TVD_EndWarning", [_waitTime, "MM:SS"] call BIS_fnc_secondsToString, _bonus]; // Показ таймера игрокам
            if (_extended) then {
                _extended = false; // Сброс флага продления
                [localize "STR_TVD_MissionExtended", "dynamic"] call TVD_notifyPlayers; // Уведомление о продлении
            };
            
            private _unitValue = player getVariable ["TVD_UnitValue", []];
            if (count _unitValue > 2 && {_unitValue select 2 in ["sideLeader", "execSideLeader"]} && _waitTime < 60 && _actContinueAdded != -2) then {
                titleText [localize "STR_TVD_EndExtendPrompt", "PLAIN DOWN"]; // Подсказка командиру о продлении
                if (_actContinueAdded == -1) then {
                    _actContinueAdded = player addAction ["<t color='#ffffff'>" + localize "STR_TVD_ExtendMission" + "</t>", { // Действие продления
                        _args params ["", "", "", "", "_ttw", "_actContinueAdded", "_bonus", "_extended"];
                        _ttw = _ttw + 300; // Увеличение времени на 5 минут
                        missionNamespace setVariable ["a3a_endMissionTime", (missionNamespace getVariable ["a3a_endMissionTime", 3600]) + 300, true]; // Обновление глобального времени миссии
                        player removeAction _actContinueAdded; // Удаление действия после использования
                        _actContinueAdded = -1; // Сброс ID действия
                        _bonus = _bonus - 1; // Уменьшение количества продлений
                        _extended = true; // Установка флага продления
                    }, nil, 0, false, true, "", "_actContinueAdded != -2"];
                };
            };
        };
        
        // Серверная часть: отключение продления при исчерпании лимита
        if (isServer && _bonus <= 0) then {
            _actContinueAdded = -2; // Отключение возможности продления
        };
    }, 1, [_startTime, _endCause, _specificSide, _result, _ttw, _actContinueAdded, _bonus, _extended]] call CBA_fnc_addPerFrameHandler;
    
    waitUntil {sleep 1; _result}; // Ожидание завершения мониторинга с локальным флагом
};