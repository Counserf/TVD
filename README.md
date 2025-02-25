# TVD - Tactical Victory Determination

TVD (Tactical Victory Determination) — это скриптовый мод для Arma 3, который добавляет механику подсчёта очков, управления задачами, отступления и завершения миссии на основе действий игроков и заданных условий. Подходит для PvP и кооперативных сценариев с двумя сторонами, определяемыми через `mission_parameters.hpp` (`blueforSide` и `opforSide`).

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
   ├── description.ext
   ├── init.sqf
   ├── mission_parameters.hpp
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

### 2. Настройка `description.ext`
Убедитесь, что в `description.ext` подключены параметры миссии:
```
class A3A_MissionParams {
    #include "mission_parameters.hpp"
};
```

### 3. Настройка `mission_parameters.hpp`
Укажите стороны конфликта:
```
// Противоборствующие стороны ("WEST", "EAST", "INDEPENDENT")
blueforSide = "WEST";
opforSide = "EAST";
```
- Допустимы значения: `"WEST"`, `"EAST"`, `"INDEPENDENT"`.
- Союзники `INDEPENDENT` определяются в редакторе через настройки фракций.

### 4. Настройка `init.sqf`
Добавьте в `init.sqf` в корне миссии следующий код для запуска TVD:
```
// Проверка выполнения на сервере
if (isServer) then {  
    waitUntil {sleep 1; count allPlayers > 0}; // Ожидание игроков
    [] execVM "TVD\core\main.sqf"; // Запуск TVD
};

// Проверка выполнения на клиенте
if (hasInterface) then { 
    [] execVM "TVD\client\actions.sqf"; // Инициализация клиентских действий
};
```

### 5. Создание баз
В редакторе Arma 3 создайте два триггера для баз сторон:
- **trgBase_side0 (bluefor)**:
  - Переменная: `trgBase_side0`
  - Размер: 50x50 м
  - Активация: `ANYPLAYER`, `PRESENT`
- **trgBase_side1 (opfor)**:
  - Переменная: `trgBase_side1`
  - Размер: 50x50 м
  - Активация: `ANYPLAYER`, `PRESENT`

Эти триггеры определяют зоны для отступления и отправки юнитов в резерв.

### 6. Размещение юнитов
- Добавьте играбельных юнитов для `blueforSide` и `opforSide` рядом с их базами (`trgBase_side0` и `trgBase_side1`).
- Назначьте командиров (КС) с помощью переменной:
  ```
  this setVariable ["TVD_UnitValue", [west, 50, "sideLeader"], true]; // КС для blueforSide
  ```

---

## Конфигурация

Файл `TVD/config.sqf` содержит настройки миссии. Отредактируйте его под свои нужды. Подробные комментарии есть в самом файле:
- `TVD_CapZonesCount`: Количество зон захвата.
- `TVD_RetreatPossible`: Разрешение отступления.
- `TVD_ZoneGain`: Очки за зону.
- `TVD_RetreatRatio`: Порог потерь для отступления.
- `TVD_SoldierCost`: Очки за солдата.
- `TVD_TimeExtendPossible`: Возможность продления времени КС.
- `TVD_TimeExtendLimit`: Лимит продлений.
- `TVD_CriticalLossRatio`: Порог тяжёлых потерь.
- `a3a_endMissionTime`: Время миссии.

### Зоны захвата
Если `TVD_CapZonesCount > 0`, создайте маркеры в редакторе:
- `mZone_0`, `mZone_1`, и т.д. (соответственно количеству зон).
- Установите цвет маркера (`ColorBLUFOR`, `ColorOPFOR`) для начального владельца.

### Задачи
#### Через код в `init.sqf`
Добавьте задачи после инициализации TVD:
```
private _trigger = createTrigger ["EmptyDetector", [5000, 5000, 0], true];
_trigger setTriggerArea [50, 50, 0, false];
_trigger setTriggerActivation ["WEST", "PRESENT", true];
_trigger setVariable ["TVD_TaskObject", [west, 100, "Захватить зону", true, ["false", "false", "false", "false", "true"], true], true];
```

#### Через редактор
Создайте задачу с условием трёхкратного преимущества:
1. Добавьте триггер:
   - Тип: `EmptyDetector`
   - Позиция: `[5000, 5000, 0]`
   - Размер: 50x50 м
   - Активация: `WEST`, `PRESENT`, повторяемая
   - Условие: `this && (({side _x == east} count allPlayers) / ({side _x == west} count allPlayers) >= 3)`
   - Переменная: `trigAdvantageWest`
2. В поле инициализации:
   ```
   this setVariable ["TVD_TaskObject", [west, 100, "Удержать позицию против перевеса", true, ["false", "false", "false", "false", "true"], true], true];
   ```

---

## Основной функционал
- **Захват зон**: Контроль маркеров приносит очки.
- **Отступление**: Индивидуальное или по приказу КС при значительных потерях.
- **Техника**: Захват или отправка в резерв.
- **Тяжёлые потери**: Завершение миссии при критическом уроне.
- **Задачи**: Выполнение ключевых задач завершает миссию.
- **Логирование**: События и итоги сохраняются.
- **Уведомления**: Сообщения и дебрифинг.

---

## Пример базовой миссии
1. Создайте `TVD_Mission.Stratis`.
2. Скопируйте папку `TVD`.
3. Настройте `description.ext` и `mission_parameters.hpp`.
4. Добавьте код в `init.sqf`.
5. В редакторе:
   - Создайте триггеры `trgBase_side0` и `trgBase_side1`.
   - Добавьте юнитов для `blueforSide` и `opforSide`.
   - Настройте задачу.
6. Отредактируйте `TVD/config.sqf`.
7. Сохраните и запустите.

---

## Дополнительные возможности
- **Обыск (ACE3)**: В `ext/frisk.sqf`.
- **Маркировка ящиков**: В `ext/mark_box.sqf`:
  ```
  this setVariable ["TVD_markBox", [west, "Ящик с Javelin"], true];
  ```
- **Логирование**: Логи отправляются администратору.

---

## Отладка
- Используйте консоль для проверки переменных (`TVD_SidesInfScore`, `TVD_MissionLog`).
- Проверьте RPT-файл на ошибки.

---

## Лицензия
TVD распространяется под лицензией MIT. Используйте и модифицируйте свободно с указанием авторства.

Автор: Counserf  
GitHub: [https://github.com/Counserf/TVD](https://github.com/Counserf/TVD)