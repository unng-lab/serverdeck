# Data model: представление существующего приложения

Дата: 2026-10-28. Модель дополняет [план](plan.md) и [визуальный контракт](contracts/full-application.md). Она описывает RAM-состояние Flutter UI и существующие DTO. Новые persistent entities, Local API, store, custom binding language и reference-протокол не вводятся.

## Владение и контекст

| Представление | Источник и поля | Инварианты |
| --- | --- | --- |
| Навигация | Текущий `DeckLocation`: раздел, view, server/record/job identity, caller | RAM UI; explicit target имеет приоритет над saved default. Отсутствующий/чужой target не заменяется другим профилем. |
| Рабочая область | Существующие owners и private epoch | Один lifecycle на client/server/private context; смена страницы не создаёт второго controller/subscription. |
| Draft формы | Существующие controllers и `TextEditingController` | Theme/resize сохраняют значение, selection и разрешённый context. Другая операция не присваивает прежний pending result. |
| Статус изменения | Waiting/pending/unknown/conflict/committed/readback и прежний request | Status view использует тот же owner и draft; explicit actions сохраняют прежние guards. Сам показ ничего не исполняет. |
| Наблюдение | Полученные target/source/observedAt/receivedAt/value/quality | Unknown, denied, unsupported, stale, incomplete и dropped не равны successful empty или нулю. |
| План/job/grant | Существующие immutable IDs/revisions/digests/expiry/scopes | Представление не создаёт согласие, не переносит его на другую цель и не меняет полномочия. |
| Сценарий widget test | Обычный Dart setup и fake внешние зависимости | Используется настоящий production widget/controller. Данные синтетические; нет отдельного JSON-корпуса, reader или схемы receipts. |

## Переходы контекста

Обычные theme/resize/tab/filter transitions сохраняют текущий допустимый UI state, не вызывая connect/write/approval. Навигация в ПО/Журналы/Задания передаёт фактический target прежнему owner. Callback проверяет актуальность своего client/target/generation; late result не заменяет чужой экран или draft.

Потеря readiness/авторизованной сессии имеет приоритет над сохранением приватного draft: цель, секретные editors и неподтверждённое согласие скрываются прежним production путём, поздние replies их не возвращают. Постоянные данные locald не удаляются.

## История метрик

`MetricHistoryProjection` использует полученные source-order snapshots, не более 120 точек. Только int 0–100 является процентной точкой. `null`, double, строка, отрицательное или превышающее 100 значение разрывает ряд; не округляется и не превращается в 0. Пропуски, равное/обратное время, stale и evicted history сохраняют прежний смысл владельца данных.

CPU/RAM/root disk различаются цветом, линией и marker. Один point показывается отдельно без выдуманной линии, ноль samples — пустотой. Полный график и mini charts берут один ряд; текстовая альтернатива показывает те же времена, значения, единицы и gaps, включая saved route без повторного сбора. Геометрия и role variants следуют каноническому контракту, не новой модели наблюдений.

## Редакторы и полный JSON

Полный JSON остаётся в route-owned controller. Typed controls — его представление, а не разрешение silently отфильтровать неизвестные/невалидные поля. До admission/save проверяется полный документ по существующему product codec; затем действуют прежние authority/target/revision/expiry guards.

Безопасные промежуточные поля остаются редактируемыми: enum Add→edit, values→default repair, select-all/delete числового значения. Unsafe nested shapes не вызывают cast/dropdown assertion; видна связанная ошибка, invalid submit даёт 0 dispatch. Не добавляются default TTL, dedup, coercion или последнее валидное значение вместо введённого.

Происхождение scalar kind — private RAM metadata editor: собственная structured правка сохраняет допустимый numeric intent; внешняя замена полного raw text пересчитывает его из переданного JSON. Caret-only изменение не является заменой source. Смена controller/private context и disposal сохраняют обычный retirement.

`GenericJsonDraftState` связывает текущий callback/result с той же операцией и route. Read success не объявляет результат unrelated pending write, explicit dismiss не уничтожает draft, late completion после close/retirement не меняет UI.

## Совместимость и проверка

Состав, версии и валидация product DTO остаются у 001/021 и профильных пакетов. Смена дизайна не требует миграции, нового API, provider или собственного wire/storage формата. UI values и copy показывают фактические данные прежнего owner; совпадение ключей JSON по смыслу не позволяет менять копируемый текст.

Обычные unit/widget tests проверяют эти переходы через существующие fake clients/delegates. Сырые значения, полные строки, состояние формы и число callbacks утверждаются непосредственно в тесте. Источники визуального дизайна — HTML/брендбук/PNG; отдельная инфраструктурная модель для сравнения не нужна.
