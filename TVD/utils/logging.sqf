#include "\x\cba\addons\main\script_macros.hpp" // Подключение макросов CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии TVD

// Инициализация очереди логов на сервере для асинхронной обработки
if (isServer && isNil "TVD_LogQueue") then {
    TVD_LogQueue = []; // Очередь для хранения событий логов
    
    // Асинхронный обработчик логов с интервалом 0.5 секунды
    [CBA_fnc_addPerFrameHandler, {
        params ["_args", "_handle"];
        private _queue = _args select 0;
        
        if (_queue isEqualTo []) exitWith {}; // Пропуск, если очередь пуста
        
        private _maxPerFrame = 10; // Лимит обработки: 10 событий за кадр
        for "_i" from 0 to (_maxPerFrame - 1) do {
            if (_queue isEqualTo []) exitWith {}; // Выход, если очередь опустела
            private _entry = _queue deleteAt 0; // Извлечение первого события
            _entry params ["_type", "_data", "_extra"];
            
            [_type, "_data", "_extra"] call TVD_logEvent; // Логирование события
        };
        
        // Мониторинг размера очереди для предотвращения перегрузки
        private _queueSize = count _queue;
        if (_queueSize > 50) then {
            diag_log format [localize "STR_TVD_Log_QueueWarning", _queueSize]; // Предупреждение о большом размере очереди
        };
        
        if (_queueSize == 0) then {[_handle] call CBA_fnc_removePerFrameHandler}; // Удаление обработчика, если очередь пуста
    }, 0.5, [TVD_LogQueue]] call CBA_fnc_addPerFrameHandler; // Интервал обработки — 0.5 секунды
};

/*
 * Функция TVD_logEvent
 * Логирует события в миссии с временной меткой и соотношением сил
 * Параметры:
 *   _type: строка - тип события (например, "killed", "taskCompleted")
 *   _data: любой тип - данные события (юнит, сообщение и т.д.)
 *   _extra: любой тип (опционально) - дополнительный параметр (например, индекс стороны)
 */
TVD_logEvent = {
    params ["_type", "_data", ["_extra", nil]];
    
    // Временная метка в формате текста
    private _timeStamp = parseText format ["<t size='0.7' shadow='2' color='#CCCCCC'>%1: </t>", [daytime * 3600] call BIS_fnc_secondsToString];
    
    // Цвета сторон для отображения в логе
    private _sColor = ["#ed4545", "#457aed", "#27b413", "#d16be5", "#ffffff"]; // east, west, resistance, civilian, neutral
    private _plot = parseText ""; // Текст события
    
    // Обработка события в зависимости от его типа
    switch (_type) do {
        case "scheduled": { // Периодический отчёт о состоянии миссии
            private _si0 = 0; // Индекс blueforSide
            private _si1 = 1; // Индекс opforSide
            _plot = composeText [
                parseText format ["<t size='0.7' shadow='2'>" + localize "STR_TVD_LogScheduled" + "</t>",
                    TVD_PlayerCountNow select _si0, TVD_PlayerCountNow select _si1, // Живые игроки
                    (TVD_PlayerCountInit select _si0) - (TVD_PlayerCountNow select _si0), // Потери bluefor
                    (TVD_PlayerCountInit select _si1) - (TVD_PlayerCountNow select _si1), // Потери opfor
                    {_x select 1 == TVD_Sides select _si0} count TVD_capZones, // Зоны bluefor
                    {_x select 1 == TVD_Sides select _si1} count TVD_capZones, // Зоны opfor
                    TVD_TaskObjectsList select _si0, TVD_TaskObjectsList select _si1] // Выполненные задачи
            ];
        };
        case "taskCompleted": { // Завершение задачи
            private _side = TVD_Sides select _extra;
            private _si = _extra; // Индекс стороны
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogTaskCompleted" + "</t>", _sColor select _si, _side, _data];
        };
        case "capVehicle": { // Захват техники
            private _originalSideIndex = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            private _capturingSideIndex = _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogCapVehicle" + "</t>", 
                _sColor select _capturingSideIndex, TVD_Sides select _capturingSideIndex, 
                getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
        };
        case "sentToRes": { // Отправка техники в резерв
            private _si0 = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            private _si1 = TVD_Sides find _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogSentToRes" + "</t>", 
                _sColor select _si1, TVD_Sides select _extra, 
                getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
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
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatSoldier" + "</t>", 
                _sColor select _si0, _data select 0, _data select 2, _data select 3];
        };
        case "retreatScore": { // Корректировка очков при отступлении
            private _si0 = TVD_Sides find _data;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatScore" + "</t>", 
                _sColor select _si0, _data, _extra];
        };
        case "retreatLossList": { // Потери при отступлении
            private _si0 = TVD_Sides find _extra;
            _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogRetreatLossList" + "</t>", 
                _sColor select _si0, TVD_Sides select _extra, _data];
        };
        case "killed": { // Убийство юнита
            if (!(((_data getVariable ["TVD_UnitValue", [sideLogic, 0]]) select 0) in TVD_Sides) || 
                (_data getVariable ["TVD_soldierRetreats", false]) || 
                (_data getVariable ["TVD_soldierSentToRes", false])) exitWith {}; // Пропуск, если юнит не участвует
            
            private _si0 = TVD_Sides find (_data getVariable "TVD_UnitValue" select 0);
            if (_data isKindOf "CAManBase") then { // Пехота
                _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogKilledMan" + "</t>", 
                    _sColor select _si0, name _data, 
                    if (count (_data getVariable ["TVD_UnitValue", []]) > 2) then {(_data getVariable "TVD_UnitValue" select 2) call TVD_unitRole} else {""}, 
                    _data getVariable ["TVD_GroupID", ""]
                ];
            } else { // Техника
                _plot = parseText format ["<t size='0.7' shadow='2'><t color='%1'>" + localize "STR_TVD_LogKilledVehicle" + "<t color='#FFB23D'></t>", 
                    _sColor select _si0, getText (configFile >> "CfgVehicles" >> typeOf _data >> "displayName")];
            };
        };
    };
    
    // Вычисление текущих результатов миссии
    private _stats = [] call TVD_calculateWin;
    if (!isNil "_stats") then { // Проверка на существование результатов
        private _si0 = 0; // blueforSide
        private _si1 = 1; // opforSide
        private _sidesRatio = parseText format ["<t size='0.7' shadow='2'>(<t color='%1'>%2%</t>-<t color='%3'>%4%</t>) </t>", 
            _sColor select _si0, _stats select 2, _sColor select _si1, _stats select 3];
        TVD_MissionLog pushBack composeText [_timeStamp, _sidesRatio, _plot]; // Добавление события в лог
    } else {
        diag_log "TVD_logging: _stats is nil in TVD_logEvent"; // Логирование ошибки
    };
};