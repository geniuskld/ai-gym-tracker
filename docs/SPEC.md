# IronLog -- Спецификация

## 1. Концепция

iOS-приложение для трекинга силовых тренировок + sync-сервер:
- **Импорт плана** -- Claude генерирует JSON-план, загружает на сервер. Приложение синхронизирует автоматически или импортирует вручную
- **Пошаговая тренировка** -- приложение ведет по упражнениям: prescribed вес/повторы, таймер отдыха, техники (drop-сеты, myo-reps, суперсеты, rest-pause)
- **Синхронизация логов** -- логи автоматически отправляются на сервер. Claude забирает их для анализа прогресса и корректировки плана

## 2. Scope

### Реализовано
- Импорт JSON-плана (буфер обмена / файл / sync с сервера), превью перед подтверждением
- Shared Base Contract: plan_type, plan_id, plan_version, plan_name, schema, created_at
- Schema identification: timestamp в плане + структурная валидация в приложении
- Повторный импорт обновляет существующий план
- Выбор плана (по умолчанию -- последний использованный, авто-выбор если один)
- Несовместимые планы показываются как "not supported" с timestamps схем
- Один план на plan_id (при обновлении заменяет предыдущий)
- Выбор шаблона -> Active Workout
- Пошаговый UI: одно упражнение на экране
- Ввод: вес (кнопки -5/-1/+1/+5 kg), повторы, RIR
- Автозаполнение веса: из плана (per-set) -> из прошлой тренировки -> вручную
- Warmup-сеты с отдельным prescribed весом
- Заметки к упражнению из плана (notes)
- Техники: straight, drop_set, myo_reps (с лимитом мини-сетов), rest_pause, superset
- TechniqueFlow -- stateless протокол для управления потоком сетов
- SetRoadmap -- визуальный список всех сетов с тремя состояниями
- Таймер отдыха с вибрацией и push-уведомлением
- Dynamic Island: вес + таймер при выполнении, обратный отсчет при отдыхе
- Lock Screen Live Activity
- Оценка упражнения (Heavy/OK/Easy) между упражнениями
- Perceived effort (1-3) при завершении тренировки
- История тренировок с planName, swipe-to-delete, ShareLink JSON-экспорт
- Sync-сервер: FastAPI + MongoDB + Docker
- JWT auth (регистрация, вход, sliding 90-day expiry)
- Plan sync: авто-проверка + баннер обновления + ручная кнопка
- Log sync: fire-and-forget upload после тренировки, delete при удалении
- Настройки: server URL, аккаунт, test connection
- Иконка приложения (золотой бицепс с синими мозговыми извилинами)
- JSON-схемы с документацией для AI

### Вне текущего scope
- PR-трекинг, графики прогресса
- HealthKit, Apple Watch
- Редактор плана в UI
- Кардио-блок
- Русская локализация UI
- Периодизация (авто-переключение rep-схемы по неделям)

## 3. Функциональные требования

### 3.1. Импорт плана
- FR-IMP-01: Импорт JSON через буфер обмена или файл
- FR-IMP-02: Валидация JSON с понятными ошибками
- FR-IMP-03: Превью плана перед подтверждением импорта
- FR-IMP-04: Поддержка нескольких импортированных планов
- FR-IMP-05: Повторный импорт с тем же plan_id обновляет существующий (один план на plan_id)
- FR-IMP-06: Bundled sample-plan.json для первого запуска
- FR-IMP-07: Если план не декодируется (неизвестный формат) -- сообщение "обнови приложение"
- FR-IMP-08: Структурная валидация при импорте: plan_type, body_part, technique, наличие templates/groups/exercises/sets
- FR-IMP-09: Legacy matching: при пустом planId совпадение по planName

### 3.2. Синхронизация
- FR-SYN-01: Регистрация и вход по email + пароль
- FR-SYN-02: JWT хранится в Keychain, auto-refresh при активности (< 30 дней до expiry)
- FR-SYN-03: При запуске: GET /plan -> сравнение plan_version -> баннер обновления
- FR-SYN-04: Баннер "New plan vN available" если план проходит структурную валидацию
- FR-SYN-05: Баннер "Update app" если план не декодируется (DecodingError)
- FR-SYN-06: Ручная кнопка "Sync Plan" в списке планов
- FR-SYN-07: Fire-and-forget upload лога после завершения тренировки
- FR-SYN-08: Fire-and-forget delete лога при swipe-to-delete
- FR-SYN-09: Настройки: server URL, аккаунт (логин/регистрация/выход), test connection
- FR-SYN-10: 401 -> очистка токена, показ "Not logged in"

### 3.3. Тренировка
- FR-WRK-00: Выбор плана: saved -> last used (из истории) -> первый доступный. Один план -- авто-выбор
- FR-WRK-01: Выбор шаблона -> одно упражнение на экране, свайп-навигация
- FR-WRK-02: Ввод веса (кнопки -5/-1/+1/+5), повторов. Вес предзаполняется: из prescribed per-set -> из прошлой тренировки -> вручную
- FR-WRK-03: Таймер отдыха по упражнению. Вибрация + push-уведомление + Dynamic Island
- FR-WRK-04: Суперсеты: чередование A1/A2, таймер после пары
- FR-WRK-05: Drop-сеты: рабочий + drop с авто-расчетом веса (% снижение)
- FR-WRK-06: Myo-reps: активация + мини-сеты с лимитом (max_mini_sets), кнопка "Finish exercise"
- FR-WRK-07: Rest-pause: основной сет + продолжения с коротким отдыхом
- FR-WRK-08: Warmup-сеты с отдельным prescribed весом
- FR-WRK-09: SetRoadmap: визуальный список сетов (active/pending/completed)
- FR-WRK-10: Оценка упражнения (Heavy/OK/Easy) между упражнениями
- FR-WRK-11: Perceived effort (1-3) при завершении
- FR-WRK-12: Заметки к упражнению из плана (notes)
- FR-WRK-13: Resume незавершенной тренировки при возврате в приложение

### 3.4. Dynamic Island + Live Activity
- FR-DI-01: Performing: иконка гантели + вес (зеленый)
- FR-DI-02: Resting: иконка таймера + обратный отсчет (синий)
- FR-DI-03: Overtime: "GO!" (желтый)
- FR-DI-04: Expanded: название упражнения, вес/следующий сет, прогресс-бар
- FR-DI-05: Lock Screen: название + вес/следующий сет + таймер

### 3.5. История и прогресс
- FR-HIS-01: Хронологический список тренировок с planName и templateName
- FR-HIS-02: Детальный просмотр тренировки
- FR-HIS-03: Swipe-to-delete (с удалением на сервере)
- FR-HIS-04: ShareLink экспорт в JSON

### 3.6. Экспорт
- FR-EXP-01: Экспорт логов в JSON по схеме workout-log.schema.json
- FR-EXP-02: Включает exerciseRating, planName, planType, planId, perceived_effort
- FR-EXP-03: Share Sheet (ShareLink)

### 3.7. Сервер
- FR-SRV-01: POST /register, POST /login -> JWT
- FR-SRV-02: GET /plans -- список планов (последняя версия каждого plan_id)
- FR-SRV-03: GET /plan -- последний план по type+id
- FR-SRV-04: PUT /plan -- загрузка с полной цепочкой валидации (base -> type -> version)
- FR-SRV-05: GET /plan/versions -- история версий
- FR-SRV-06: POST /log -- upsert логов по workout ID
- FR-SRV-07: GET /log -- запрос логов (since, template_id, type, limit)
- FR-SRV-08: DELETE /log/{id} -- удаление лога
- FR-SRV-09: GET /schema -- описание схемы (public)
- FR-SRV-10: Валидация plan_type, 422 для неизвестных типов

## 4. Нефункциональные требования
- NFR-01: Offline-first: полная функциональность без интернета, sync при наличии
- NFR-02: Нативный iOS (Swift/SwiftUI), iOS 17+, SwiftData
- NFR-03: Минимальный UI, большие тап-зоны, минимум навигации
- NFR-04: Данные хранятся локально (SwiftData), копия на сервере (MongoDB)
- NFR-05: JSON-экспорт до 1MB на 6 месяцев
- NFR-06: Время запуска < 1 секунда
- NFR-07: Dark mode поддерживается автоматически (system theme)
- NFR-08: Фоновая устойчивость: Date-based таймеры работают корректно после background/foreground
- NFR-09: JWT sliding expiry (90 дней), auto-refresh при активности
- NFR-10: Sync-ошибки не блокируют UI (fire-and-forget)

## 5. Ключевое ограничение
- Никакого ручного создания планов в UI -- только импорт JSON или sync с сервера
- Приложение = исполнитель плана + логгер
- Анализ прогресса и корректировка плана -- на стороне AI через сервер

## 6. Schema & Compatibility
- Каждый план несет поле `schema` -- timestamp идентификатор схемы (e.g. `"2026-04-09T22:00:00Z"`)
- Серверная JSON-схема содержит `x-schema-id` с тем же timestamp
- Приложение хранит `PlanSchema.id` -- timestamp своей поддерживаемой схемы
- **Валидация структурная**: приложение проверяет plan_type, body_part, technique, наличие templates/groups/exercises/sets
- Загруженные планы не проходящие валидацию -> "not supported" + timestamps обеих схем
- Ответ сервера не декодируется -> баннер "Update app"
- PlanType -- enum на обеих сторонах (Python Enum, Swift enum), сейчас: `strength`

## 7. JSON-схемы
- `schemas/workout-plan.schema.json` -- полностью документирована, каждое поле с описанием и примерами. Содержит `x-schema-id` timestamp
- `schemas/workout-log.schema.json` -- схема экспорта с exerciseRating, planName, planType, planId
- `schemas/sample-plan.json` -- рабочий пример с Shared Base Contract, warmup, working, drop, myo_reps, superset
