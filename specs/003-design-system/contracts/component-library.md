# План и контракт 003.4 — библиотека компонентов

**Дата**: 2026-11-01. **Требования**: [component-library.md](../component-library.md). Дополняет [presentation.md](presentation.md); действующие P01–P10, приватность, владельцы и recovery сохраняют приоритет. При разнице визуального образца и токена используется канонический токен.

## Размещение и поставка

Выбрана уже действующая Flutter Material 3 (`BrandTheme.useMaterial3=true`) с брендовой темой и Deck presentation widgets. Стандартные controls используют реальные Material реализации; общие коллекции и составные элементы реализованы в `lib/ui/deck_*`. Дизайн-атлас использует согласованные роли/токены и общий HTML renderer; отдельный Flutter entrypoint показывает production-компоненты, а не HTML-имитации. Сборка атласа и текущие проверки описаны в актуальном разделе [quickstart 003.4](../quickstart.md).

- Общая библиотека остаётся внутри root Flutter приложения: `lib/ui/`, токены — `lib/theme/`. Публичная точка импорта — существующий `lib/ui/deck_components.dart`; допускается разнести реализацию по файлам с экспортами из этой точки. Нового package/repository нет.
- C01 переиспользует BrandColors/BrandTypography/BrandSpacing/BrandGeometry и bundled assets. Точные текущие размеры/пороги 520/1060 и правила shell берутся из P01–P04 и brand_tokens; новый набор токенов не создаётся.
- Существующие DeckSurface, SectionHeader, Status, Notice, KeyValue, Actions, FormSection, DialogLayout, BoundedTextView и FocusLabel дорабатываются или составляются, а не дублируются под новыми именами. Предметные компоненты `lib/servers/`, `profiles/`, `automation/`, `settings/` остаются адаптерами данных и действий.
- Отдельный entrypoint каталога — `tool/component_catalog.dart`, примеры/реестр — `tool/component_catalog/`. Запуск из root: `flutter run -d windows -t tool/component_catalog.dart`. Это отдельный MaterialApp с существующей BrandTheme, без imports bootstrap/controllers/engine/windows transport, без инициализации locald или чтения настроек/секретов. Каталог не добавляется в навигацию клиента и его assets.
- UI-тесты библиотеки — `test/widget/components/`; общие fixtures — `test/support/component_cases.dart`; дизайн образцы и инструкция — `docs/design/components/README.md`. Каталог не требует production dependency. Используется SDK/lock/pinned tools основного plan 003; Flutter controls, flutter_test, существующие capture tools. Нет новых сетевых prerequisites, persistence schema, миграций и API versions. Windows bundle сохраняет прежний состав; новые используемые runtime assets должны попасть в существующий pubspec bundle с лицензией.

## Контракт входов и событий

Это внутрипроцессный UI-контракт v1 этапа 003.4, не wire protocol. Существующие публичные constructors сохраняют совместимость; неизбежное изменение обновляет все callers и тесты одной задачей. Точные Dart-имена новых типов можно выбрать при реализации, сохранив перечисленные значения и семантику.

| Семейства | Обязательный вход / событие |
| --- | --- |
| C02–C04, C13 | label, value/controller от owner, helper/error, enabled, pending, onChanged/onSubmit/onCancel; validators остаются у owner. Nullable callback не выглядит доступным действием. Пароль скрыт по умолчанию, copy отсутствует; показ только явно пользователем, доступный label меняется |
| C05–C08, C29 | loaded rows, уникальный стабильный row ID, columns (key, label, text/numeric/machine alignment, cell renderer, sort capability, порядок узких полей), selected IDs, sort descriptor, query/filters, collection state, permitted actions, paging metadata; callbacks лишь сообщают намерение |
| C09–C12, C18, C21, C30 | отображаемые значения, подпись, DeckTone, loading/quality/reason, provenance/time при наличии, допустимые действия. Компонент не выводит факт подключения или разрешение из цвета/наличия данных |
| C14–C17, C19 | selected/open state, title/target/body/actions, availability, onSelect/onClose/confirm. Модальные routes открывает существующий showMotionDialog и private-session механизм; общий layout не хранит consent |
| C20, C22–C28 | переданный snapshot: значения/единицы/series/timestamps/gaps, шаги и outcome, стороны diff, точный raw text, path nodes, дата/часовой пояс и ошибки; выбор/копирование/редактирование — только явные события owner |

Общие состояния каталога: default, hover, focus, pressed, selected, disabled, pending, error, empty, no-results, unavailable, stale, partial, unknown. У каждого C ID записываются применимые состояния и мотивированное N/A (например, у типографики нет submit/pending). Design ready означает только принятую визуальную карточку; code ready — assertions и работоспособные callbacks; adopted — production mapping и regression results. До проверок статусы pending, а не ready.

## Коллекции: сортировка, выбор и объём

- Компонент controlled: owner передаёт порядок, query, filters, selection, sort и paging. Событие сортировки передаёт column ID + asc/desc; цикл unsorted → asc → desc → unsorted. Меняются только строки, не цель и не права. Нет скрытого server/client sort или фильтрации; каталог демонстрирует локальный owner.
- Без provided sort capability заголовок не интерактивен. Null отображается «Нет данных», а не 0; конкретный порядок null и строк задаёт owner. В каталоге null последний в обоих направлениях, строки сравниваются по lower-case тексту, числа численно, равные значения сохраняют порядок fixture.
- Выбор controlled, по row ID, не по индексу. Default — без выбора; opt-in single или multi. Select-all относится только к отображаемой странице/порции, сообщает её ID и исключает недоступные строки; скрытые выбранные ID owner может сохранять с явным общим счётчиком C29. После удаления записи owner удаляет её ID из selection. Row action не вызывает row-select; повторный click checkbox инвертирует только этот ID.
- Узкая композиция при width≤520 показывает подписанные значения в исходном порядке колонок и все разрешённые действия. В остальных ширинах при недостатке места/200% текста тоже используется список: измерение доступного места и column minimum widths (default 120 logical px, override >0) определяет fit. Column values не отбрасываются; список серверов и экран не имеют horizontal scroll. Внутренний bounded raw text может иметь собственную прокрутку по P07.
- Paging по умолчанию отсутствует: компонент показывает переданную порцию с lazy row construction. Page и load-more — взаимоисключающие opt-in режимы; default pageSize=25, варианты 25/50/100 для локального каталога. Production owner явно передаёт поддерживаемые размеры/total/hasMore/current page; unknown total показывается как unknown, Next доступен только при hasMore, pending блокирует повтор загрузки. Смена query/filter/pageSize сообщает reset на первую страницу, но не выполняет I/O сама.
- Для проверки bounded layout каталог использует 0/1/1000 строк и lazy list без создания виджетов всех 1000 строк сразу. Это fixture размера, не новый backend limit. Сервисные лимиты/retention остаются прежними. У пустого результата поиска есть очистка, у empty dataset — разрешённое owner действие, у unavailable — объяснение без фиктивного retry.

## Формы, сообщения и безопасность

- Текстовые controllers и validator принадлежат feature owner; local reveal/menu/accordion state может жить внутри элемента и уничтожается с ним. UI rebuild не запускает запросы. Pending guard действует синхронно при первом submit до ожидания async result; повтор Enter/click не dispatch. Закрытие или потеря доступа не означают физическую отмену принятого задания.
- Focus order соответствует чтению. Диалог замыкает Tab, Escape/backdrop дают cancel, Enter вызывает только явно назначенный default submit при валидном/не pending состоянии; опасный confirm не default Enter. После закрытия focus возвращается к открывшему control либо заголовку текущего раздела, если control удалён. Меню: arrows/Home/End, Enter/Space выбор, Escape закрыть; tooltip не единственный источник обязательной причины/ошибки.
- Краткое уведомление используется только для локального несущественного результата (например copy), default 4 секунды, с close и семантическим announcement. Ошибки, unknown outcome, security/target context остаются постоянными C11/C12/C24. Автоматического retry нет. Copy только явное действие над разрешённым значением, использует существующий clipboard механизм; failure показывается текстом, пароль/credential никогда не копируется этим общим control.
- Loading с данными означает refreshing: snapshot сохраняется с меткой; initial loading без данных не рисует фиктивные строки. Partial/stale и provenance поступают от owner; неизвестное время не вычисляется из текущих часов.
- C22 сохраняет принятые ≤120 points и разрыв >15000 ms, существующие текстовую альтернативу и keyboard selection; новых polling/timers нет. C23 не превращает local close в cancel; unknown не terminal success. C24 показывает обязательные target/effects/scope/deadline вне сворачиваемых технических деталей и не решает, можно ли доверять/исполнять.
- C25 — read-only сравнение уже переданных пар полей/строк с пометками add/remove/change/conflict; не вычисляет merge и не пишет файл. C26 — plain multiline/read-only text с validation от owner, без syntax engine/exec. C27 — lazy дети, переданные owner; expand/select не читает filesystem. C28 получает даты и зоны явно (UTC default в каталоге), показывает время события и наблюдения с разными labels; picker возвращает значение и зону, schedule/DST validation остаётся у соответствующего owner, каталог проверяет invalid/empty ввод. Это не новый планировщик.

## Проверки, трассировка и применение

Реестр `docs/design/components/registry.json` создаётся T103: schemaVersion=1; components[{id, sourceScreenIds, variants, applicableStates, notApplicableReasons, designEvidence, implementationPaths, exampleIds, testPaths, designStatus, codeStatus, adoptionStatus}]; screens[{screenId, componentIds, kind:existing|concept, productionPaths, verificationEvidence}]. Evidence — repo-relative paths/идентификаторы проверок, до выполнения пустые; C IDs и screen IDs уникальны, все ссылки разрешаются. Полнота проверяется против 30 IDs этой спеки и 98 IDs screens.json, existing/concept — по исходным 35/63, не по догадке исполнителя. Не каждый общий элемент обязан встречаться в каждом экране.

Каждая T105–T134 закрывает соответствующий C ID только после карточки дизайна, работающего production элемента в каталоге, примера, assertions взаимодействия и применимых failure/boundary cases. Для C01 вместо взаимодействий проверяются точные токены/assets/contrast; для остальных N/A мотивируется. Общие cases: themes × frames × textScale, keyboard/semantics/reduced motion, long/missing content, совмещение состояний. Визуальные captures обеих тем всех применимых комбинаций записываются отдельно от assertions и просматриваются на overflow/обрезку/focus; прежние capture IDs не переписываются. Шрифты и данные синтетические/offline. Реальный manual Windows smoke не выдаётся за widget result.

Связь требований и задач:

| Требование / приёмка | Решение | Задачи |
| --- | --- | --- |
| FR-CL-01–03,08 / AC-CL-01,02,05 | Каталог, реестр, общие состояния, отдельная приёмка | T103–T134, T138–T140 |
| FR-CL-04,05 / AC-CL-03 | Controlled collection, адаптация, paging, стабильные ID | T109–T112, T133, T135, T138 |
| FR-CL-06,07 / AC-CL-04,06 | Owners, callbacks, focus/privacy, без I/O | T104–T134, T136–T140 |
| FR-CL-09,10 / SC-CL-02–04 | Mapping всех экранов, adoption существующих owners | T103, T135–T140 |

T135–T137 переводят только существующие production compositions; новые серверные возможности concepts не создаются. Для концепта допустим локальный пример/fixture с маркировкой, без runtime route. Common layout дубли удаляются только после подтверждения parity; feature-specific lifecycle не обобщается ради уменьшения строк. Обязательные gates: format/analyze/test для Flutter изменений, `lychee "specs/**/*.md"` для spec, существующие design-reference checks по quickstart, Windows build/smoke при изменении native release composition и независимое ревью по AGENTS.md. Фактические команды/exits/scope и оставшиеся ограничения пишутся в отдельный evidence раздел 003.4, а не заменяют историческую приёмку 003.1–003.3.
