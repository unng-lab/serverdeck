# Research: адаптивный дизайн ServerDeck

**Дата**: 2026-10-25. **Пакет**: [003 — Дизайн и доступность](spec.md).

Документ фиксирует решения Phase 0 для визуального внедрения в существующий Flutter-клиент. Исследование кода и SDK не является приёмкой реализации. Фактические проверки приложения и независимое ревью фиксируются отдельно после изменений.

## R01 — Среда и зависимости

**Decision**: использовать закреплённый Flutter 3.47.7 / bundled Dart 3.13.5, framework revision `abaf9c523780a608bd46686fd5e53740a07077f8`. Первая runtime-платформа остаётся Windows; phone обозначает узкую композицию того же клиента, а не новую заявленную поддержку Android/iOS. Изменение не требует нового UI-пакета, backend, внешнего сервиса, загрузки шрифтов или миграции хранилища.

**Rationale**: [pubspec.yaml](../../pubspec.yaml) уже содержит Flutter, локализацию, существующие protocol/windows-пакеты и bundled brand assets. [foundation-sdk.ps1](../../tools/foundation-sdk.ps1) проверяет эту точную SDK identity. Read-only вызов `H:/flutter/flutter/bin/flutter.bat --version --machine` 25.10.2026 фактически вернул перечисленные версии и revision. Это проверка identity SDK, а не успешный анализ, сборка или прогон тестов приложения.

**Alternatives considered**: обновление SDK и сторонняя библиотека навигации/дизайна увеличивают scope и не нужны для токенов, responsive layout и доступных widgets. Новые платформенные обещания требуют собственной приёмки и сюда не добавляются.

## R02 — Иерархия источников

**Decision**: требования продукта и полномочий соответствующего пакета имеют приоритет; точные визуальные значения берутся из [брендбука 1.1](../../docs/brandbook/README.md) и [исходных токенов](../../docs/brandbook/tokens/serverdeck.tokens.json); композиции — из [стабильного атласа](../../docs/design/README.md), [DESIGN.md](../../docs/design/DESIGN.md), [screens.json](../../docs/design/screens.json) и [автономного HTML](../../docs/design/ServerDeck-design.html). Отличающаяся демонстрационная кнопка или цифра не переопределяет контракт приложения.

**Rationale**: атлас явно использует вымышленные данные и отдельно помечает наличие сценария, дизайн и техническую приёмку. `output/design-all-pages-2026-10-25` остаётся исходным экспортом и вспомогательной историей; package links используют стабильный `docs/design/`.

**Alternatives considered**: импорт HTML как рабочего клиента, копирование demo data, объявление всего атласа реализованным или изменение API ради картинки нарушают границы 001 и достоверность наблюдений.

## R03 — Граница 35 существующих сценариев

**Decision**: применять визуальную систему к 35 записям `implemented: true` из реестра на дату инвентаризации: `01`, `02`, `03`, `04`, `05`, `06`, `07`, `08`, `09`, `10`, `12`, `13`, `16`, `17`, `18`, `19`, `22`, `23`, `27`, `28`, `29`, `30`, `31`, `32`, `33`, `34`, `35`, `36`, `37`, `38`, `39`, `40`, `84`, `85`, `94`. Это сценарии и состояния существующих widgets, а не 35 обязательных новых routes. Остальные 63 записи остаются концептами своих профильных пакетов.

**Rationale**: текущее приложение уже предоставляет readiness, локальные профили, trust/connection, системные наблюдения, ограниченный журнал, рецепт/план/задание, Ansible-профили, MCP grants/delegations и настройки. Изменение композиции не требует реализации 63 будущих возможностей.

**Alternatives considered**: флаг `implemented` как доказательство parity отклонён. Например, поиск/сводки fleet относятся к 008; pause/расширенные фильтры журнала — к 009; текущий глобальный раздел заданий — заглушка; создание профиля сохраняет без подключения. Эти отличия не закрываются декоративными кнопками. В 003 сохраняются доступные команды и честные состояния отсутствующей возможности.

## R04 — Владение компонентами и жизненным циклом

**Decision**: [app.dart](../../lib/app.dart) сохраняет composition root и связи bootstrap/settings/profile snapshots. [FoundationShell](../../lib/shell/foundation_shell.dart) отвечает за выбранный основной раздел, адаптивную навигацию и рамку страницы. Palette/typography/widget themes принадлежат [brand_theme.dart](../../lib/theme/brand_theme.dart), assets — [brand_assets.dart](../../lib/theme/brand_assets.dart), reduced motion — [motion.dart](../../lib/theme/motion.dart). Общие presentation widgets получают значения/статусы/callbacks и не выполняют Local API, SSH или доступ к БД.

Владельцы существующих сценариев сохраняются:

| Группа | Владелец реализации |
| --- | --- |
| 01–03 | `lib/shell/readiness_view.dart`, `lib/shell/error_view.dart` |
| 04–05 | `lib/profiles/profile_list.dart` |
| 07–09, 12–13 | `lib/profiles/profile_form.dart`, `profile_delete.dart`, `credential_input.dart`, `mutation_status.dart` |
| 06, 10, 22–23, 40 | `lib/servers/server_panel.dart`, `server_controller.dart`, `metrics_history.dart` |
| 16–19, 27–30, 32–39, 94 | `lib/software/software_panel.dart`, `lib/automation/automation_panel.dart`, `automation_controller.dart` |
| 31 | `lib/profiles/recovery_view.dart`, `startup_recovery.dart` |
| 84–85 | `lib/settings/settings_view.dart`, `settings_form.dart`, `settings_controller.dart` |

**Rationale**: controllers уже реализуют subscriptions, request identity, cancellation, timers, revision checks и disposal. Resize и theme меняют только presentation: не создают второй controller, не повторяют запрос, не пересоздают secret draft и не заменяют его значениями из snapshot. При потере readiness действующая очистка private state остаётся обязательной. Lifecycle behavior остаётся у существующего owner; адаптивные ветви не перемещают его в заново создаваемые rail/sidebar/phone widgets.

**Alternatives considered**: новый глобальный store, перестройка service ownership, непосредственный UI→SSH канал и перенос controllers в generic widgets не нужны для 003. Принудительное сохранение всех скрытых панелей в `IndexedStack` без проверки readiness/disposal также не принимается как универсальное решение.

## R05 — Точная визуальная система

**Decision**: сохранить все непрозрачные цветовые роли токенов обеих тем; не генерировать палитру из seed. Noto Sans 400/600 и Noto Sans Mono 400 входят в bundle. Роли текста: page title 24/32/600; body 14/20/400; table/log 13/20/400; button/table header 13/20/600; caption 12/16/400. Кнопки не наследуют caption 12/16 как общую label style. Control/card/dialog radius — 8/12/16; spacing — 4/8/12/16/24/32/48; icon — 20; focus — 2 с gap 2.

**Rationale**: [типографическая страница](../../docs/brandbook/layouts/09-typography.svg) явно различает button и caption. Существующий `BrandColors` уже сохраняет точные палитры, но default Material widget shapes и все `label*` styles требуют явного role mapping. Цвет controls берётся из `control`, декоративных границ — из `border`. Минимальная интерактивная область 44×44 не уменьшается до визуального `size.control=36`.

**Alternatives considered**: локальные произвольные hex/радиусы и defaults Material не дают воспроизводимого соответствия бренду. Понижение opacity для disabled вместо токенов исключено. Состояния disabled/error/focus/selected/hover имеют видимую композицию; фокус и выбранность не исчезают при ошибке. Цвет статуса всегда сопровождается текстом и символом.

## R06 — Зафиксированная адаптивная рамка

**Decision**: layout определяется доступной логической шириной shell после системных insets, без зависимости от названия устройства.

| Ширина | Основная навигация | Геометрия |
| --- | --- | --- |
| `>1060` | Постоянный sidebar 210 px с логотипом, иконками и подписями | Padding content 24 px |
| `521–1060` | Rail 72 px с иконками; полное имя доступно в tooltip и semantics | Padding content 24 px |
| `<=520` | Нижняя панель пяти разделов; полные подписи; растущий `Wrap` по R07 | Padding content 16 px |

Topbar имеет 56 px при контрольных 100%/200%; в ней компактный текст не крупнее body 14/20, бренд/контекст и существующее действие истории. Page title 24/32 располагается ниже в content с собственной растущей высотой. Длинные profile name/address и сообщения находятся в переносимом контексте content, а не в фиксированной строке topbar. Width 520 относится к phone, 521 к rail, 1060 к rail, 1061 к sidebar.

**Rationale**: эти пределы конкретизируют предложения атласа и позволяют проверить переходы. Fixed topbar не вмещает page title 24/32 при 200% (64 px line height), поэтому заголовок не помещается в неё. В rail targets не меньше 44×44; подписи не обрезаются внутри 72 px и не заменяют доступное имя icon-only controls. Desktop sidebar при больших строках растёт по вертикали и прокручивается.

**Alternatives considered**: прежняя комбинация sidebar 256 / appbar 72 / drawer `<=800` расходится с выбранной композицией. Fixed page-title topbar и подавление text scaling скрывают содержимое. Drawer не требуется как обязательная дополнительная phone-навигация, поскольку все пять действий доступны снизу.

## R07 — Phone при 200%: доступный нижний Wrap

**Decision**: использовать собственный presentation widget нижней навигации вместо фиксированного Material `NavigationBar`. Пять пунктов идут в неизменном порядке «Серверы», «ПО», «Журналы», «Задания», «Настройки». Каждый содержит icon 20, vertical gap 4 и caption 12/16 с актуальным `TextScaler`. Item имеет horizontal padding 4 с каждой стороны, vertical padding 8; min width/height 44. Панель имеет horizontal padding 4, vertical padding 8; `Wrap.spacing=4`, `runSpacing=4`.

Ширина пункта вычисляется через `TextPainter` для полной подписи с текущими locale/direction/font/textScaler: `max(44, ceil(max(normalWidth, selectedWidth)) + 8)`, ограниченная доступной шириной панели. Измеряются normal и selected styles, чтобы смена выбранного раздела не меняла размещение. Если пункту требуется вся ширина, текст переносится. Нет `ellipsis`, ограничения `maxLines`, `FittedBox`, подавления scaling или фиксированной высоты панели. Пункты переносятся целиком; высота панели равна фактической высоте рядов.

Панель размещается в `Scaffold.bottomNavigationBar` и `SafeArea`, занимает собственное место и не перекрывает body. Body остаётся в `Expanded` с вертикальной прокруткой; page actions и длинные notices переносятся. При открытой экранной клавиатуре нижняя навигация скрывается по `MediaQuery.viewInsets.bottom > 0`; выбранный раздел/черновик сохраняются, после закрытия клавиатуры панель возвращается. Modal forms/dialogs получают доступную высоту над keyboard и прокрутку полей/действий; одновременное изменение размера не подтверждает и не закрывает форму.

**Rationale**: исходник закреплённого SDK `packages/flutter/lib/src/material/navigation_bar.dart` прямо указывает, что `MediaQuery.textScaler` не увеличивает размер стандартного `NavigationBar`. Пять фиксированных ячеек с fixed height нельзя считать доказательством читаемых полных подписей при 200%.

Аналитический расчёт advance widths из bundled `NotoSans-Regular.ttf` (таблицы `cmap`, `hmtx`, `head`, без зависимости от внешних шрифтов) дал padded widths при 100% `[61,44,63,58,72]`, сумма с gap/padding 330 px; при 200% `[113,45,117,108,136]`, сумма 543 px. При 360/390 px нормальные подписи помещаются в один ряд, увеличенные — ориентировочно в два ряда 3+2, с высотой около 164 px плюс SafeArea. Это расчёт без shaping/kerning и selected face, а не результат Flutter layout test. Контракт опирается на runtime `TextPainter`, рост и перенос, а приёмка — на фактический widget render обеих тем и четырёх размеров при 100%/200%.

**Alternatives considered**: один fixed row на 360 px обрезает увеличенные подписи; icon-only phone navigation скрывает обязательные видимые названия; уменьшение шрифта отменяет пользовательское scaling; нижняя overlay-панель закрывает содержимое; permanent bottom navigation при клавиатуре занимает высоту, необходимую форме.

## R08 — Честная проекция данных и защищённых действий

**Decision**: UI показывает только значения/возможности существующих controllers. Локальный контекст shell показывает выбранный профиль и состояние locald; SSH connection badge разрешён только при передаче реальной connection projection выбранного сервера. Если такой projection отсутствует, shell не утверждает ни подключение, ни недоступность. Текущее безусловное «Не подключён» рядом с выбранным профилем не сохраняется как новая семантика дизайна.

Quality (`unknown`, `stale`, `denied`, `unsupported`, `incomplete`), время/источник наблюдения, пропуски журнала и unknown outcome не скрываются декоративным success. Empty successful result отличается от неполученных данных. Инструменты показывают только доступные команды; ожидание того же запроса блокирует его повтор, но независимая shell navigation остаётся доступной. Создание/просмотр/resizing widgets не подключает сервер и не подтверждает trust/approval/apply. Точное явное действие «Подключиться и открыть рецепты» сохраняет свой существующий connection effect.

**Rationale**: существующие `ServerPanel` и `AutomationPanel` выполняют действия через Trusted API client; их права, trust revision, idempotency, expiry, cancellation и reconciliation уже имеют собственных владельцев. Presentation не меняет срок, retry payload, immutable plan inputs или область MCP grant. Credentials остаются в текущем credential input lifecycle и не попадают в status, history, screenshot fixtures или diagnostic details.

**Alternatives considered**: atlas examples как runtime fallback, synthetic availability count, ноль вместо отсутствующей метрики, автоматический повтор unknown mutation и автоматический connect при открытии страницы нарушают существующие требования.

Global Logs/Jobs получают точное объяснение отсутствия общего списка и наличия existing nested журнала/заданий в контексте сервера при нужном доступе/доверии. Локальное действие «К серверам» помогает открыть этот контекст без нового API или автоподключения; blanket «Выполнение заданий пока недоступно» не сохраняется как ложное описание уже существующих jobs. Это уточнение presentation/navigation, не новая агрегация или выдача полномочий.

## R09 — Доступность графика и длинных данных

**Decision**: у существующего [MetricsHistory](../../lib/servers/metrics_history.dart) сохранить максимум 120 точек и пропуски как отсутствие данных. Дополнить график раскрываемыми текстовыми значениями тех же ограниченных samples: UTC timestamp, CPU, RAM, root disk; null/invalid value — явный пропуск, не 0. Series используют `accent`, `chart2`, `chart3`, разные подписи и текстовую альтернативу. Формат доступен keyboard/screen reader и не требует hover. UI не добавляет polling/retention/агрегацию от себя. Приоритет FR-004-LOCAL-02/03/05 раскрыт в P08: общий graph block300/270px на1100/800, три plot25px одной строкой, actions слева/graphs справа по нижней линии и errors выше. Базовые patterns относятся к актуальным данным; stale задаёт dash6-4 всем curve/legend strokes, сохраняя series symbols/names/color roles и явный quality text.

**Rationale**: текущий graph имеет только общий semantics label и диапазон времени; это не текстовые значения FR-125. Текущие primary/secondary цвета совпадают, хотя третья роль `chart3` уже существует. Источник даёт достаточно данных для bounded alternative без нового API.

**Alternatives considered**: один generic accessibility label, tooltip-only values и копирование sparkline из макета не закрывают требование. Новые диапазоны истории и графики других ещё отсутствующих модулей остаются в профильных пакетах.

## R10 — Проверки и граница доказательств

**Decision**: после спецификации запускать `lychee "specs/**/*.md"`, после Flutter изменений — `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`; далее независимый review/fix loop по [AGENTS.md](../../AGENTS.md). Проверки HTML не заменяют эти gates. На момент этого исследования перечисленные обязательные проверки изменения приложения не выполнялись.

Сохранить regression coverage существующих [theme tests](../../test/theme/brand_theme_test.dart), [shell tests](../../test/widget/foundation_shell_test.dart), [profile list tests](../../test/widget/profile_list_test.dart), [accessibility forms tests](../../test/widget/accessibility_test.dart) и [reduced-motion tests](../../test/widget/reduced_motion_test.dart). Добавить измеримые сценарии выбранных breakpoint boundaries, phone labels/targets при 200%, смены темы/размера без потери draft/filter/controller identity, keyboard focus/selection, честного shell context и graph text values. Для remote observations использовать synthetic controllers/fixtures; оформление не требует соединения с пользовательским сервером.

**Rationale**: существующий dirty worktree включает несвязанные изменения и незавершённые сценарии других пакетов; их прежние результаты не доказывают 003 и не должны быть затёрты. В документах сохраняется различие «исследовано», «запланировано», «реализовано» и «проверено»; независимое ревью пакета предшествует handoff в реализацию.

**Alternatives considered**: объявить готовность по screenshots/старым task checkmarks или запустить реальный инфраструктурный сценарий ради косметического изменения не даёт корректной scope-bound приёмки.

## R11 — Ограниченный preflight root analyzer

**Decision**: перед Flutter-реализацией добавить в root `pubspec.yaml` только `dev_dependencies.analyzer: 13.3.0` и выполнить закреплённым SDK `flutter pub get --offline`, сохранив полученный root lock. Production dependencies/runtime не расширяются; код существующего `tools/unit-coverage-zero.dart` не меняется. Его существующие вызовы с `--packages=packages/serverdeck_protocol/.dart_tool/package_config.json` остаются действующими.

**Rationale**: baseline root `flutter analyze` фактически завершился с13issues: root/tools helper напрямую импортирует analyzer, которого не было в root dev dependencies. Параллельная проверка root установила analyzer13.3.0 в protocol lock/cache и успешный isolated helper smoke с explicit package context. Это локальный dependency-context дефект preflight, не UI failure и не успешный root analyze. После dev dependency нужны новый root analyze и smoke `dart --packages=packages/serverdeck_protocol/.dart_tool/package_config.json tools/unit-coverage-zero.dart --references lib/theme/brand_theme.dart`; предыдущий результат не засчитывается как выполненная приёмка003.

**Alternatives considered**: исключить helper через `analysis_options.yaml` рассмотрено и отклонено — оно уменьшает полноту root analysis без необходимости. Перенос helper, изменение его корректных protocol package calls, новый production dependency или незакреплённая версия analyzer не нужны. Реализация preflight выполняется только после полного Tasks и review пакета.

## R12 — Offline fallback для отсутствующих glyphs

**Decision**: сохранить исходные Noto Sans400/600 и Mono400, добавить полный неизменённый Noto Sans SC variable как fallback для отсутствующих символов. Одинаковая chain используется явными BrandTypography roles, обеими темами и fixture font loader. Font, отдельная OFL и [source metadata](../../assets/brand/fonts/NotoSansSC-SOURCE.json) входят в bundle. Runtime загрузки из сети и новые production dependencies не нужны.

**Evidence/rationale**: deferred CJK例 в06/22/23 действительно отсутствовал в cmap всех трёх исходных faces; исходная actual raster проверка отличалась от корректного glyph на1004пикселя. Полный upstream font17772300bytes, SHA256 `a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`, pinned Google Fonts commit `e7db6ca603fd4862010383ff17ffd6cc4ffac1c0`; OFL SHA256 `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9`. Variable wght100–900/default100 проверен фактическими body400/button600/log400 pixels против explicit-axis reference400/600 и против tofu; веса400/600 дают разные изображения. Metadata/лицензия/FontManifest и сохранность исходных assets также проверены. Это конкретное glyph/fallback evidence, не обещание покрытия всего Unicode.

**Alternatives considered**: заменить例 латиницей означало бы убрать обязательный stress case. Только find.text не доказывает отрисовку. System-only fallback дал бы разные результаты в Windows и isolated test engine. Fixture-only subset скрыл бы проблему произвольного пользовательского текста. Полный неизменённый upstream asset сохраняет понятные provenance/license и добавляет17.8MB к поставке; исходные брендовые typography/palette/tokens не меняются.

## R13 — Provenance результата и сохранённый draft редактора

**Decision**: automation UI сохраняет один bounded outcome конкретного durable callback отдельно от последующих read errors. Existing Panel-owned presentation helper наблюдает own completion и current owner context, без изменения controller/API/identity/polling. Route-owned editor submission валидирует metadata существующим protocol validator и ожидает собственный owner result. Ошибка сохраняет controllers; existing request actions доступны внутри modal. Definitive CAS восстанавливается только через explicit existing read, показ exact revision/digest, отдельное принятие новой expected head и новый explicit save с прежним текстом draft. Контекст проверяется перед действиями и после await; новая authorization authority не вводится.

**Evidence/rationale**: completed supplemental preflight2 обнаружил смешение old pending label с новой read error и потерю draft при semantic-invalid name. Actual regression отдельно воспроизвела эти sequence/metadata failures. Независимый scoped field-error probe нашёл8/8ellipsis truncations в обеих темах наphone200% иdesktop100%, хотя поля были раскрыты и0save callbacks. Открытый retained editor также должен давать выполнимый recovery path без вынужденной потери draft. T093–T097 закрепляют исправления; scoped reds не являются успешным полным gate.

**Alternatives considered**: сочетание current error+pendingLabel не устанавливает provenance записи. Автоматически очищать pending, читать новую основу или повторять изменённый payload нарушало бы existing lifecycle. Закрытие формы на dispatch уничтожает draft до ответа. Новый controller/native interface не нужен: существующие result/error/pending, retryPending/dismissPending/selectProfile/saveProfile достаточны; технический UI state остаётся ephemeral и bounded. Full adaptive/capture/mandatory/fresh-review gates остаются обязательными.

## R14 — Общий JSON editor ожидает собственный результат

**Decision**: применить P04/P06 к existing JSON dialogs grant/delegation/plan parameters и read dialogs version/compare. Route-owned shared presentation flow ожидает собственный borrowed callback, сохраняет JSON и связанную service validation error; live Panel использует этот же flow. Read/durable kind передаётся явно из existing AutomationUiPhase. Своё retained request отличается от unrelated pending; повтор/отказ от запроса остаётся у owner, никакой новой mutation identity или автоматического resend нет.

**Evidence/rationale**: supplemental preflight3 подтвердил, что lifetimeSeconds:0 проходит JSON/type слой, service возвращает VALIDATION, но _jsonEditor уже закрыл route и disposed input. Private pending closure доступна только для exact retry/dismiss, не для редактирования draft. Profile-specific T094/T097 не закрывают общий контракт. Select-version/compare являются reads, поэтому blanket pending lock или write-success semantics к ним неприменимы.

**Boundaries**: ошибки сохраняют текст до explicit close/P10 retirement; pending fields непрозрачны и не редактируются. Own successful callback может закрыть ещё действующий dialog, включая обновление DTO собственным readback; stale context не разрешает новую операцию. Не добавляются grant UI, новый CAS/rebase, API/schema/validator/dependency/timer/cache или изменение authority. Existing shared flow сначала можно извлечь с прежним поведением для meaningful runtime red; такой red не заменяет native proof. Затем current production flow и caller wiring проверяются вместе с delayed VALIDATION, duplicate/late/current-context, read-with-unrelated-write, retry/dismiss и own-success completion.
