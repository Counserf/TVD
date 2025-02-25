#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии

// Инициализация очереди логов для асинхронной обработки (только на сервере)
if (isServer && isNil "TVD_LogQueue") then {
    TVD_LogQueue = [];
    
    // Асинхронный обработчик логов с интервалом 0.5 секунды
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        private _queue = _args select 0;
        
        if (_queue isEqualTo []) exitWith {}; // Пропуск, если очередь пуста
        
        private _entry = _queue deleteAt 0; // Извлечение первого события из очереди
        _entry params ["_type", "_data", "_extra"];
        
        [_type, _data, "_extra"] call TVD_logEvent; // Вызов логирования события
        
        if (_queue isEqualTo []) then {[_handle] call CBA_fnc_removePerFrameHandler}; // Удаление обработчика, если очередь пуста
    }, 0.5, [TVD_LogQueue]] call CBA_fnc_addPerFrameHandler;
};

/*
 * Логирует событие в миссии с временной меткой и соотношением сил
 * Параметры:
 *   _type: строка - тип события (например, "killed", "taskCompleted")
 *   _data: любой тип - данные события (юнит, сообщение и т.д.)
 *   _extra: любой тип (опционально) - дополнительный параметр (например, индекс стороны)
 */
TVD_logEvent = {
    params ["_type", "_data", ["_extra", nil]];
    private _timeStamp = parseText format ["<t size='0.7' shadow='2' color='#CCCCCC'>%1: </t>", [daytime * 3600] call BIS_fnc_secondsToString]; // Метка времени
    private _sColor = ["#ed4545", "#457aed", "#27b413", "#d16be5", "#ffffff"]; // Цвета сторон (east, west, resistance, civilian, neutral)
    private _plot = parseText ""; // Текст события для лога
    
    // Формирование текста события в зависимости от типа
    switch (_type) do {
        case "scheduled": { // Периодический отчёт о состоянии миссии
            private _si0 = TVD_Sides find west;
            private _si1 = TVD_Sides find east;
            _plot = composeText [
                parseText format ["<t size='0.7' shadow='2'>" + localize "STR_TVD_LogScheduled" + "</t>",
                    TVD_PlayerCountNow select _si0, TVD_PlayerCountNow select _si1,
                    (TVD_PlayerCountInit select _si0) - (TVD_PlayerCountNow select _si0),
                    (TVD_PlayerCountInit select _si1) - (TVD_PlayerCountNow select _si1),
                    {_x select 1 == TVD_Sides select 0} count TVD_capZones,
                    {_x select 1 == TVD_Sides select 1} count TVD_capZones,
                    TVD_TaskObjectsList select 0, TVD_TaskObjectsList select 1]
            ];
        };
        case "taskCompleted": { // Завершение задачи
            private _side = TVD_Sides select _extra;
            private _si = TVD_Sides find _side;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogTaskCompleted" + "</t>", _sColor select _si, _side, _data];
        };
        case "capVehicle": { // Захват техники
            private _si0 = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            private _si1 = TVD_Sides find _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogCapVehicle" + "</t>", _sColor select _si1, TVD_Sides select _extra, getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
        };
        case "sentToRes": { // Отправка техники в резерв
            private _si0 = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            private _si1 = TVD_Sides find _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogSentToRes" + "</t>", _sColor select _si1, TVD_Sides select _extra, getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
        };
        case "sentToResMan": { // Отправка пехотинца в резерв
            private _si1 = TVD_Sides find (_data select 1);
            private _si0 = TVD_Sides find (TVD_Sides select (1 - (TVD_Sides find (_data select 1))));
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogSentToResMan" + "</t>", 
                _sColor select _si0, TVD_Sides select (1 - (TVD_Sides find (_data select 1))),
                _sColor select _si1, _data select 0, _data select 2, _data select 3];
        };
        case "retreatSoldier": { // Отступление солдата
            private _si0 = TVD_Sides find (_data select 1);
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatSoldier" + "</t>", _sColor select _si0, _data select 0, _data select 2, _data select 3];
        };
        case "retreatScore": { // Корректировка очков при отступлении
            private _si0 = TVD_Sides find _data;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatScore" + "</t>", _sColor select _si0, _data, _extra];
        };
        case "retreatLossList": { // Потери при отступлении
            private _si0 = TVD_Sides find _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatLossList" + "</t>", _sColor select _si0, TVD_Sides select _extra, _data];
        };
        case "killed": { // Убийство юнита
            if (!(((_data getVariable ["TVD_UnitValue", [sideLogic, 0]]) select 0) in TVD_Sides) || 
                (_data getVariable ["TVD_soldierRetreats", false]) || 
                (_data getVariable ["TVD_soldierSentToRes", false])) exitWith {}; // Пропуск, если юнит не участвует или удалён
            if (count (_data getVariable ["TVD_UnitValue", []]) > 2 && {(_data getVariable "TVD_UnitValue" select 2) in ["soldier"]}) exitWith {}; // Пропуск обычных солдат
            
            private _si0 = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            if (_data isKindOf "CAManBase") then { // Для пехоты
                _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogKilledMan" + "</t>", 
                    _sColor select _si0, name _data, 
                    if (count (_data getVariable ["TVD_UnitValue", []]) > 2) then {(_data getVariable "TVD_UnitValue" select 2) call TVD_unitRole} else {""}, 
                    _data getVariable ["TVD_GroupID", ""]
                ];
            } else { // Для техники
                _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogKilledVehicle" + "<t color='#FFB23D'></t>", _sColor select _si0, getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
            };
        };
    };
    
    private _stats = [] call TVD_calculateWin; // Текущие результаты миссии
    private _si0 = TVD_Sides find west;
    private _si1 = TVD_Sides find east;
    private _sidesRatio = parseText format ["<t size='0.7' shadow='2'>(<t color='%1'>%2%</t>-<t color='%3'>%4%</t>) </t>", _sColor select _si0, _stats select 2, _sColor select _si1, _stats select 3];
    TVD_MissionLog pushBack composeText [_timeStamp, _sidesRatio, _plot]; // Добавление события в лог
};

/*
 * Логирует итоги миссии в файл и отправляет куратору
 * Параметры:
 *   _stats: массив - результаты миссии от TVD_calculateWin
 *   _outcome: число - причина завершения миссии (0-4)
 */
TVD_logMission = {
    params ["_stats", "_outcome" = ""];
    TVD_ExportLog = [];
    
    if (_outcome != "") then {
        _outcome = switch (_outcome) do {
            case 0: {localize "STR_TVD_LogMissionEndAdmin"};
            case 1: {localize "STR_TVD_LogMissionEndTime"};
            case 2: {format [localize "STR_TVD_HeavyLosses", TVD_HeavyLosses]};
            case 3: {format [localize "STR_TVD_SideRetreated", TVD_SideRetreat]};
            case 4: {format [localize "STR_TVD_KeyTaskCompleted", TVD_MissionComplete]};
        };
    };
    
    private _si0 = TVD_Sides find west;
    private _si1 = TVD_Sides find east;
    private _pushLine = { // Функция для записи строки в лог и массив экспорта
        params ["_text"];
        diag_log _text;
        TVD_ExportLog pushBack str _text;
    };
    
    [
        "//------------------------------------------------------------//",
        "TVD Mission Status Report:",
        format ["Mission date/time: %1", date],
        format ["missionStart: %1", missionStart],
        format ["winSide: %1; Supremacy: %2; Ratio: %3 - %4; Score: %5", _stats select 0, _stats select 1, _stats select 2, _stats select 3, _stats select 4],
        format ["Soldiers Dead: %1 - %2; Present: %3 - %4", (TVD_PlayerCountInit select _si0) - (TVD_PlayerCountNow select _si0) - (TVD_RetrCount select 0), (TVD_PlayerCountInit select _si1) - (TVD_PlayerCountNow select _si1) - (TVD_RetrCount select 1), TVD_PlayerCountNow select _si0, TVD_PlayerCountNow select _si1],
        format ["EndMission Reason: %1", _outcome],
        "Vars:",
        format ["TVD_Sides = %1", TVD_Sides],
        format ["TVD_InitScore = %1", TVD_InitScore],
        format ["TVD_ValUnits = %1", TVD_ValUnits],
        format ["TVD_capZones = %1", TVD_capZones],
        format ["TVD_SidesInfScore = %1", TVD_SidesInfScore],
        format ["TVD_SidesValScore = %1", TVD_SidesValScore],
        format ["TVD_SidesZonesScore = %1", TVD_SidesZonesScore],
        format ["TVD_SidesResScore = %1", TVD_SidesResScore],
        "Mission Log:"
    ] apply {[_x] call _pushLine};
    
    {[_x] call _pushLine} forEach TVD_MissionLog; // Добавление всех записей лога
    ["//------------------------------------------------------------//"] call _pushLine;
    
    if (!isNull TVD_Curator) then {
        TVD_ExportLog remoteExec ["TVD_logCurator", TVD_Curator]; // Отправка лога куратору
    } else {
        TVD_PendingLogs append TVD_ExportLog; // Сохранение в ожидающие логи, если куратора нет
    };
};

/*
 * Логирует отчёт для куратора на его клиенте
 * Параметры:
 *   _log: массив - строки лога для вывода
 */
TVD_logCurator = {
    diag_log parseText "TVD_ExportLog:"; // Заголовок лога куратора
    {diag_log parseText format ["%1", str _x]} forEach _this; // Вывод всех строк лога
};

/*
 * Формирует дебрифинг для показа игрокам
 * Параметры:
 *   _outcome: число - причина завершения миссии (0-4)
 *   _stats: массив - результаты миссии от TVD_calculateWin
 * Возвращает: текст - форматированный дебрифинг
 */
TVD_writeDebrief = {
    params ["_outcome", "_stats"];
    private _winner = if (_stats select 0 == sideLogic) then {"-"} else {str (_stats select 0)}; // Победитель или ничья
    private _sColor = ["#ed4545", "#457aed", "#27b413", "#d16be5", "#ffffff"]; // Цвета сторон
    private _si0 = TVD_Sides find west;
    private _si1 = TVD_Sides find east;
    
    // Текст причины завершения
    private _outcomeText = switch (_outcome) do {
        case 0: {parseText format ["<t size='1.0' color='#fbbd2c' align='center' shadow='2'>%1</t><br/>", localize "STR_TVD_LogMissionEndAdmin"]};
        case 1: {parseText format ["<t size='1.2' color='#fbbd2c' align='center' shadow='2'>%1</t><br/>", localize "STR_TVD_TimeOut"]};
        case 2: {parseText format ["<t size='1.0' color='#fbbd2c' align='center' shadow='2'>%1:<br/><t color='%2'>%3</t><br/>", localize "STR_TVD_HeavyLosses", _sColor select (TVD_Sides find TVD_HeavyLosses), TVD_HeavyLosses]};
        case 3: {parseText format ["<t size='1.1' color='#fbbd2c' align='center' shadow='2'>%1:<br/><t color='%2'>%3</t><br/>", localize "STR_TVD_SideRetreated", _sColor select (TVD_Sides find TVD_SideRetreat), TVD_SideRetreat]};
        case 4: {parseText format ["<t size='1.1' color='#fbbd2c' align='center' shadow='2'>%1:<br/><t color='%2'>%3</t><br/>", localize "STR_TVD_KeyTaskCompleted", _sColor select (TVD_Sides find TVD_MissionComplete), TVD_MissionComplete]};
    };
    
    // Список зон для дебрифинга
    private _zonesList = TVD_capZones apply {
        parseText format ["<t align='right' size='0.7' shadow='2' color='%1'>%2</t>", _sColor select (TVD_Sides find (_x select 1)), markerText (_x select 0)]
    };
    
    // Основной текст дебрифинга
    private _textOut = composeText [
        _outcomeText,
        parseText "<t size='1.0' align='center' shadow='2'>----------------------------------------------------------</t><br/>",
        parseText format ["<t size='1.2' align='center' shadow='2'>%1<br/></t>", localize "STR_TVD_DebriefResults"],
        parseText format ["<t size='0.9' underline='true' shadow='2'>%1</t><br/>", localize "STR_TVD_DebriefSideRatio"],
        parseText format ["<t align='center'> <t size='1.8' color='%1'>%2%</t>   <->   <t size='1.8' color='%3'>%4%</t></t><br/>", _sColor select _si0, _stats select 2, _sColor select _si1, _stats select 3],
        parseText format ["<t align='center' size='0.7'>" + localize "STR_TVD_DebriefWinnerSide" + "</t><br/>", _sColor select (TVD_Sides find (_stats select 0)), _winner],
        parseText format ["<t size='0.9' underline='true' shadow='2'>%1</t>", localize "STR_TVD_DebriefRemainingForces"],
        parseText format ["<t size='0.9' underline='true' shadow='2' align='right'>%1</t><br/>", localize "STR_TVD_DebriefCasualties"],
        parseText format ["<t color='%1'>%2</t>   <->   <t color='%3'>%4</t>", _sColor select _si0, TVD_PlayerCountNow select _si0, _sColor select _si1, TVD_PlayerCountNow select _si1],
        parseText format ["<t align='right'> <t color='%1'>%2</t>   <->   <t color='%3'>%4</t></t><br/>", _sColor select _si0, (TVD_PlayerCountInit select _si0) - (TVD_PlayerCountNow select _si0) - (TVD_RetrCount select 0), _sColor select _si1, (TVD_PlayerCountInit select _si1) - (TVD_PlayerCountNow select _si1) - (TVD_RetrCount select 1)],
        parseText " ",
        parseText format ["<t underline='true' shadow='2'>%1</t>", localize "STR_TVD_DebriefEventLog"],
        parseText format ["<t underline='true' shadow='2' align='right'>%1</t>", localize "STR_TVD_DebriefControlledZones"]
    ];
    
    // Объединение логов событий и списка зон
    private _logCount = count TVD_MissionLog;
    private _zoneCount = count _zonesList;
    if (_logCount >= _zoneCount) then {
        for "_i" from 0 to (_logCount - 1) do {
            private _zLine = if (_i < _zoneCount) then {_zonesList select _i} else {""};
            _textOut = composeText [_textOut, parseText "<br/>", TVD_MissionLog select _i, _zLine];
        };
    } else {
        for "_i" from 0 to (_zoneCount - 1) do {
            private _mlLine = if (_i < _logCount) then {TVD_MissionLog select _i} else {""};
            _textOut = composeText [_textOut, parseText "<br/>", _mlLine, _zonesList select _i];
        };
    };
    
    _textOut // Возвращаем готовый текст дебрифинга
};