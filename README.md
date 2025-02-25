# TVD - Tactical Victory Determination

TVD (Tactical Victory Determination) — это скриптовый мод для Arma 3, который добавляет механику подсчёта очков, управления задачами, отступления и завершения миссии на основе действий игроков и заданных условий. Подходит для PvP и кооперативных сценариев с двумя сторонами (west и east).

Этот документ описывает процесс интеграции TVD в вашу миссию.

---

## Требования
- **Arma 3** (версия 2.0+ рекомендуется).
- **CBA_A3** (Community Base Addons) — для асинхронных функций и обработчиков событий.
- **ACE3** (опционально) — для механик плена и обыска.

---

## Установка

### 1. Подготовка структуры миссии
1. Создайте папку миссии в `Documents\Arma 3\missions`, например, `TVD_Mission.Stratis`.
2. Скопируйте папку `TVD` из репозитория в корень миссии. Итоговая структура:
   ```
   TVD_Mission.Stratis/
   ├── init.sqf
   ├── stringtable.xml
   └── TVD/
       ├── config.sqf
       ├── core/
       │   ├── init.sqf
       │   ├── main.sqf
       │   ├── score.sqf
       │   ├── tasks.sqf
       │   └── end.sqf
       ├── client/
       │   ├── actions.sqf
       │   └── ui.sqf
       ├── utils/
       │   ├── helpers.sqf
       │   └── logging.sqf
       ├── ext/
       │   ├── init.sqf
       │   ├── frisk.sqf
       │   └── mark_box.sqf
       └── actions/
           ├── retreat.sqf
           ├── reserve.sqf
           ├── capture.sqf
           ├── hq_transfer.sqf
           └── heavy_losses.sqf
   ```

### 2. Настройка `init.sqf`
Добавьте следующий код в `init.sqf` в корне миссии для инициализации TVD:

```
// Проверка выполнения на сервере
if (isServer) then {  
    private _sides = [west, east];              // Стороны конфликта (west - синие, east - красные)
    private _capZonesCount = 0;                 // Количество зон захвата (0 - без зон, 1+ - с маркерами mZone_0, mZone_1 и т.д.)
    private _retreatPossible = [true, true];    // Разрешение отступления для сторон (true - да, false - нет)
    private _zoneGain = 50;                     // Очки за контроль одной зоны
    private _retreatRatio = 0.3;                // Порог потерь для отступления (0.3 = 70% потерь)
    missionNamespace setVariable ["a3a_endMissionTime", 3600, true]; // Время миссии в секундах (3600 = 1 час)

    waitUntil {sleep 1; count allPlayers > 0}; // Ожидание игроков
    [_sides, _capZonesCount, _retreatPossible, _zoneGain, _retreatRatio] execVM "TVD\core\main.sqf"; // Запуск TVD
};

// Проверка выполнения на клиенте
if (hasInterface) then { 
    [] execVM "TVD\client\actions.sqf"; // Инициализация клиентских действий
};
```

### 3. Создание баз
В редакторе Arma 3 создайте два триггера для баз сторон:
- **trgBase_side0 (west)**:
  - Переменная: `trgBase_side0`
  - Размер: 50x50 м
  - Активация: `ANYPLAYER`, `PRESENT`
- **trgBase_side1 (east)**:
  - Переменная: `trgBase_side1`
  - Размер: 50x50 м
  - Активация: `ANYPLAYER`, `PRESENT`

Эти триггеры определяют зоны для отступления и отправки юнитов в резерв.

### 4. Размещение юнитов
- Добавьте играбельных юнитов для `west` и `east` рядом с их базами (`trgBase_side0` и `trgBase_side1`).
- При необходимости назначьте командиров с помощью переменной:
  ```
  this setVariable ["TVD_UnitValue", [west, 50, "sideLeader"], true]; // Командир west
  ```

---

## Конфигурация

Файл `TVD/config.sqf` содержит основные настройки мода. Измените их под нужды вашей миссии:

```
TVD_Sides = [west, east];           // Стороны конфликта
TVD_CapZonesCount = 0;              // Количество зон захвата
TVD_RetreatPossible = [true, true]; // Разрешение отступления
TVD_ZoneGain = 50;                  // Очки за зону
TVD_RetreatRatio = 0.3;             // Порог потерь для отступления (0.3 = 70%)
TVD_SoldierCost = 10;               // Очки за солдата
TVD_TimeExtendPossible = false;     // Возможность продления времени командиром
TVD_TimeExtendLimit = 2;            // Лимит продлений (по 5 минут)
TVD_CriticalLossRatio = [0.5, 0.5, 0.5]; // Порог тяжёлых потерь (50%)
```

### Зоны захвата
Если `TVD_CapZonesCount > 0`, создайте маркеры в редакторе:
- `mZone_0`, `mZone_1`, и т.д. (соответственно количеству зон).
- Установите цвет маркера (`ColorBLUFOR`, `ColorOPFOR`) для начального владельца.

### Задачи
Добавьте задачи через триггеры или логические объекты в `init.sqf` после инициализации TVD:

```
private _trigger = createTrigger ["EmptyDetector", [5000, 5000, 0], true];
_trigger setTriggerArea [50, 50, 0, false];
_trigger setTriggerActivation ["WEST", "PRESENT", true];
_trigger setVariable ["TVD_TaskObject", [west, 100, "Захватить зону", true, ["false", "false", "false", "false", "true"], true], true];
```

- `west` — сторона задачи.
- `100` — очки за выполнение.
- `"Захватить зону"` — описание.
- `true` — показывать уведомление.
- `["false", "false", "false", "false", "true"]` — условия завершения для разных причин (см. `tasks.sqf`).
- `true` — ключевая задача (завершает миссию).

---

## Основной функционал

- **Захват зон**: Контроль маркеров (`mZone_X`) приносит очки (`TVD_ZoneGain`).
- **Отступление**: 
  - Индивидуальное — через базу, добавляет очки в резерв.
  - Стороной — приказ командира завершает миссию при 70% потерь (`TVD_RetreatRatio`).
- **Техника**: Захват (`TVD_captureVehicle`) или отправка в резерв (`TVD_sendToReserve`).
- **Тяжёлые потери**: Миссия завершается при <50% игроков (`TVD_CriticalLossRatio`).
- **Задачи**: Выполнение ключевых задач завершает миссию.
- **Логирование**: События и итоги сохраняются для администратора.
- **Уведомления**: Сообщения игрокам и дебрифинг в конце.

---

## Пример базовой миссии

1. Создайте `TVD_Mission.Stratis`.
2. Скопируйте папку `TVD`.
3. В `init.sqf` добавьте код из шага 2.
4. В редакторе:
   - Создайте триггеры `trgBase_side0` и `trgBase_side1`.
   - Добавьте по 5 играбельных юнитов для west и east.
   - Создайте задачу (см. пример выше).
5. Сохраните и запустите миссию.

### Как это работает
- Игроки west и east сражаются за контроль.
- При 70% потерь можно отступить через базу.
- Выполнение задачи или истечение времени завершает миссию с дебрифингом.

---

## Дополнительные возможности

### Обыск (ACE3)
- Включено в `ext/frisk.sqf`.
- Позволяет обыскивать пленных или бессознательных юнитов.

### Маркировка ящиков
- Включено в `ext/mark_box.sqf`.
- Добавьте переменную к ящику:
  ```
  this setVariable ["TVD_markBox", [west, "Ящик с Javelin"], true];
  ```
- Маркер виден только стороне west в течение 5 минут.

### Логирование
- Логи сохраняются в `diag_log` и отправляются администратору (если он есть).

---

## Отладка
- Используйте консоль для проверки переменных (например, `TVD_SidesInfScore`, `TVD_MissionLog`).
- Включите CBA и проверьте наличие ошибок в RPT-файле.

---

## Лицензия
TVD распространяется под лицензией MIT. Используйте и модифицируйте свободно с указанием авторства.

Автор: Counserf  
GitHub: [https://github.com/Counserf/TVD](https://github.com/Counserf/TVD)