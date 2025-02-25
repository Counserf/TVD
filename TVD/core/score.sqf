#include "\x\cba\addons\main\script_macros.hpp" // Подключение CBA для асинхронных функций
#include "..\config.sqf" // Подключение конфигурации миссии (TVD_Sides, TVD_SoldierCost и т.д.)

/*
 * Обновляет текущие очки сторон в миссии
 * Параметры:
 *   _endOpt: число (опционально) - опция завершения (по умолчанию 0)
 *   _infUpdate: любое (опционально) - обновление пехоты (по умолчанию 0)
 *   _valUpdate: любое (опционально) - обновление ценных юнитов (по умолчанию 0)
 * Возвращает: массив - [_endOpt, _infUpdate, _valUpdate, инф_очки, ценные_очки, зоны_очки, резервы_очки]
 */
TVD_updateScore = {
    params ["_endOpt" = 0, "_infUpdate" = 0, "_valUpdate" = 0];

    // Подсчёт очков за обычных солдат (10 очков за каждого)
    TVD_SidesInfScore = [0, 0];
    private _infUnits = allPlayers select { // Фильтрация игроков без ценности и не в резерве
        private _side = side group _x;
        _side in TVD_Sides && 
        isNil {_x getVariable "TVD_UnitValue"} && 
        !(_x getVariable ["TVD_soldierSentToRes", false])
    };
    {
        private _us = TVD_Sides find side group _x; // Индекс стороны игрока
        if (_us == -1) then {continue}; // Пропуск, если сторона не найдена
        if (isClass (configFile >> "CfgPatches" >> "ace_main") && {_x getVariable ["ace_captives_ishandcuffed", false]}) then { // Проверка на плен (ACE3)
            private _veh = vehicle _x;
            private _onBase0 = !isNull trgBase_side0 && {_veh in list trgBase_side0}; // На базе west?
            private _onBase1 = !isNull trgBase_side1 && {_veh in list trgBase_side1}; // На базе east?
            if (_onBase0 || _onBase1) then {
                if ((_onBase0 && side group _x != trgBase_side0 getVariable ["TVD_BaseSide", sideLogic]) || 
                    (_onBase1 && side group _x != trgBase_side1 getVariable ["TVD_BaseSide", sideLogic])) then {
                    _us = 1 - _us; // Перенос очков на противоположную сторону, если на вражеской базе
                };
            };
        };
        TVD_SidesInfScore set [_us, (TVD_SidesInfScore select _us) + 10]; // Добавление 10 очков за солдата
    } forEach _infUnits;

    // Подсчёт очков за ценные юниты (техника, командиры)
    TVD_SidesValScore = [0, 0];
    private _validUnits = []; // Список для фильтрации живых юнитов
    {
        if (!alive _x || isNull _x) then { // Проверка на живых и существующих юнитов
            if (!isNil {_x getVariable "TVD_UnitValue"}) then {_x setVariable ["TVD_UnitValue", nil, true]}; // Очистка данных мёртвого юнита
            continue;
        };
        private _unitValue = _x getVariable ["TVD_UnitValue", []];
        if (_unitValue isEqualTo []) then {continue}; // Пропуск, если нет ценности
        private _us = TVD_Sides find (_unitValue select 0); // Индекс изначальной стороны
        if (_us == -1) then {continue}; // Пропуск, если сторона не найдена
        private _capOwner = _x getVariable ["TVD_CapOwner", ""]; // Владелец техники
        
        if (_capOwner != "") then { // Если юнит - техника
            if (_capOwner != _unitValue select 0) then { // Техника захвачена
                _us = TVD_Sides find _capOwner;
                if (_us != -1) then {TVD_SidesValScore set [_us, (TVD_SidesValScore select _us) + (_unitValue select 1) / 2]}; // 50% ценности за захват
            } else if (_us != -1) then { // Техника осталась у владельца
                TVD_SidesValScore set [_us, (TVD_SidesValScore select _us) + _unitValue select 1]; // Полная ценность
            };
        } else { // Если юнит - пехота
            if (isClass (configFile >> "CfgPatches" >> "ace_main") && {_x getVariable ["ace_captives_ishandcuffed", false]}) then { // Проверка на плен (ACE3)
                private _veh = vehicle _x;
                private _onBase0 = !isNull trgBase_side0 && {_veh in list trgBase_side0};
                private _onBase1 = !isNull trgBase_side1 && {_veh in list trgBase_side1};
                if (_onBase0 || _onBase1) then {
                    if ((_onBase0 && _unitValue select 0 != trgBase_side0 getVariable ["TVD_BaseSide", sideLogic]) || 
                        (_onBase1 && _unitValue select 0 != trgBase_side1 getVariable ["TVD_BaseSide", sideLogic])) then {
                        _us = 1 - _us; // Перенос очков, если на вражеской базе
                    };
                };
            };
            if (isPlayer _x && !(_x getVariable ["TVD_soldierSentToRes", false])) then { // Живой игрок, не в резерве
                TVD_SidesValScore set [_us, (TVD_SidesValScore select _us) + _unitValue select 1]; // Добавление полной ценности
            };
        };
        _validUnits pushBack _x; // Добавление в список живых юнитов
    } forEach TVD_ValUnits;

    // Обновление списка ценных юнитов только при изменении (только на сервере)
    if (isServer && TVD_ValUnits isNotEqualTo _validUnits) then {
        TVD_ValUnits = _validUnits;
        publicVariable "TVD_ValUnits"; // Синхронизация с клиентами
    };

    // Подсчёт очков за зоны
    TVD_SidesZonesScore = [0, 0];
    {
        private _marker = _x select 0;
        private _side = getMarkerColor _marker call TVD_colorToSide; // Текущий владелец зоны
        _x set [1, _side]; // Обновление владельца в списке
        if (_side in TVD_Sides) then {
            private _ownerSide = TVD_Sides find _side;
            TVD_SidesZonesScore set [_ownerSide, (TVD_SidesZonesScore select _ownerSide) + TVD_ZoneGain]; // Добавление очков за зону
        };
    } forEach TVD_capZones;

    // Возвращаем текущие результаты подсчёта
    [_endOpt, _infUpdate, _valUpdate, TVD_SidesInfScore, TVD_SidesValScore, TVD_SidesZonesScore, TVD_SidesResScore]
};

/*
 * Рассчитывает итоги миссии и определяет победителя
 * Параметры:
 *   _endOpt: число (опционально) - причина завершения миссии (по умолчанию -1)
 *   _retrOn: число (опционально) - индекс отступившей стороны (по умолчанию -1)
 * Возвращает: массив - [победитель, степень превосходства, % west, % east, [потери west, потери east]]
 */
TVD_calculateWin = {
    params ["_endOpt" = -1, "_retrOn" = -1];
    private _stats = [_endOpt] call TVD_updateScore; // Получение текущих очков
    private _scoreRatio = [0.0, 0.0]; // Соотношение потерь сторон
    private _sRegain = 0.0; // Компенсация при отступлении

    // Расчёт соотношения потерь для каждой стороны
    for "_i" from 0 to 1 do {
        if (TVD_InitScore select _i != 0) then {
            _scoreRatio set [1 - _i, round (((TVD_InitScore select _i) - ((TVD_SidesInfScore select _i) + (TVD_SidesValScore select _i) + (TVD_SidesZonesScore select _i) + (TVD_SidesResScore select _i))) / ((TVD_InitScore select 0) + (TVD_InitScore select 1) + (TVD_InitScore select 2)) * 1000) / 10];
        };
    };

    // Корректировка при отступлении
    if (_retrOn != -1 && _retrOn >= 0 && _retrOn < count TVD_Sides) then {
        _sRegain = ((0 max (_scoreRatio select (1 - _retrOn))) - (0 min (_scoreRatio select _retrOn))) / 2; // Компенсация половины разницы
        _scoreRatio set [1 - _retrOn, (_scoreRatio select (1 - _retrOn)) - _sRegain]; // Уменьшение потерь отступившей стороны
        ["retreatScore", TVD_Sides select _retrOn, _sRegain] call TVD_logEvent; // Логирование корректировки
    };

    // Определение победителя и степени превосходства
    private _ratioDiff = (_scoreRatio select 0) - (_scoreRatio select 1); // Разница в потерях
    private _winSide = if (_ratioDiff > 0) then {TVD_Sides select 0} else {TVD_Sides select 1}; // Победитель по разнице
    private _superiority = switch (true) do { // Степень превосходства
        case (abs _ratioDiff > 36): {3}; // Сокрушительная победа
        case (abs _ratioDiff > 12): {2}; // Уверенная победа
        case (abs _ratioDiff > 4):  {1}; // Преимущественная победа
        default                     {0; _winSide = sideLogic}; // Ничья
    };

    private _ratioBalance = 100.0 min (0.0 max (50.0 + _ratioDiff)); // Баланс соотношения (0-100%)
    [_winSide, _superiority, _ratioBalance, 100.0 - _ratioBalance, [_scoreRatio select 0, _scoreRatio select 1]] // Возвращаем результаты
};