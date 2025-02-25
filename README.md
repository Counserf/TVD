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

В процессе работы...
