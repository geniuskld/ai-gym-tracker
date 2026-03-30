# IronLog -- AI Gym Tracker

iOS-приложение для трекинга силовых тренировок с двусторонним обменом данными через JSON.

## Концепция

1. **Импорт плана** -- получаешь JSON от Claude (или другого ИИ), вставляешь в приложение -- готовые шаблоны тренировок с весами, повторами, техниками
2. **Тренировка** -- приложение ведёт по упражнениям: показывает prescribed вес/повторы, таймер отдыха, Dynamic Island, поддерживает drop-сеты, myo-reps и другие техники
3. **Экспорт логов** -- формируешь JSON с историей, отправляешь Claude для анализа прогресса и корректировки плана

## Стек

- Swift / SwiftUI / SwiftData (iOS 17+)
- MVVM + Services
- ActivityKit (Dynamic Island + Lock Screen Live Activity)
- WidgetKit (виджет-расширение для Live Activity)
- XcodeGen (генерация xcodeproj из project.yml)

## Возможности

### Импорт плана
- JSON через буфер обмена или файл
- Превью плана перед подтверждением
- Повторный импорт обновляет существующий план
- Поддержка нескольких планов

### Тренировка
- Пошаговый UI: одно упражнение на экране, свайп для навигации
- Prescribed вес/повторы/RIR из плана с автозаполнением
- Техники: straight, drop_set, myo_reps, rest_pause, superset
- TechniqueFlow -- stateless протокол для управления потоком сетов
- SetRoadmap -- визуальный список сетов (warmup/working/drop/mini)
- WeightStepper -- кнопки -5/-1/+1/+5 kg
- Таймер отдыха с вибрацией и уведомлениями
- Dynamic Island: вес + таймер во время сета, обратный отсчёт во время отдыха
- Lock Screen Live Activity
- Оценка упражнения (Heavy/OK/Easy) между упражнениями
- Perceived effort (1-3) при завершении тренировки
- Список упражнений (sheet с прогрессом)
- max_mini_sets для myo-reps (лимит мини-сетов)

### История и экспорт
- Хронологический список тренировок с планом и шаблоном
- Детали тренировки с полным логом
- Swipe-to-delete
- ShareLink экспорт в JSON
- Оценки упражнений и planName в экспорте

## JSON-схемы

- `schemas/workout-plan.schema.json` -- схема импорта плана (документирована для ИИ)
- `schemas/workout-log.schema.json` -- схема экспорта лога
- `schemas/sample-plan.json` -- пример плана с весами, warmup-сетами, myo-reps

## Структура

См. [ARCHITECTURE.md](docs/ARCHITECTURE.md)
