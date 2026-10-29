# Контракт 003.4: точный дизайн существующего приложения

Дата: 2026-10-28. По последнему уточнению пользователя 003 сначала переносит точный дизайн уже реализованных базовых страниц и объединяет существующие функции в приложении. Текущая приёмка относится к 37 сценариям ниже, общему shell и всем поддержанным состояниям этих функций. Это 35 исторических origins плюс композиции11 host-key-changed и93 для существующего blocked plan. Для93 отсутствие protected-cause discriminator требует честного blocked-unspecified варианта FA07.1; новая классификация не объявляется существующей. Остальной61 экран сохраняется в программе98, но его функциональность и дизайн планируются и принимаются вместе в соответствующих существующих пакетах004–020. Новые сервисы, backend/provider implementation и функциональность будущих пакетов не являются задачами реализации003.

Актуальный scope задаёт [spec](../spec.md); общая трассировка находится в [screen-map](../screen-map.md). Этот документ заменяет для003.4 ограничения визуального переноса, rail72, общий topbar56 и способы принятия текущего Flutter как достаточного результата в [историческом presentation-контракте](presentation.md). Его защитные правила сохраняются. Прежние завершённые задачи и результаты остаются историей своего scope и не становятся новой визуальной приёмкой.

## FA01 — Канонический источник и состав экранов

Обязательный комплект: [HTML-атлас](../../../docs/design/ServerDeck-design.html), [реестр](../../../docs/design/screens.json), [DESIGN](../../../docs/design/DESIGN.md), [брендбук](../../../docs/brandbook/README.md), [точные токены](../../../docs/brandbook/tokens/serverdeck.tokens.json). Приоритет: продуктовые/защитные требования владельца → брендбук и точные роли → композиция атласа. Перенос дизайна не меняет существующие полномочия, API, trust, credentials, лимиты или результат операции.

| Артефакт | SHA256 исходной редакции003.4 |
| --- | --- |
| `docs/design/ServerDeck-design.html` | `7ceda8e4e79f736c48bd6ff24b572f75b5e05f2aa2e3d25dca95cbbecbe1b75d` |
| `docs/design/screens.json` | `8767675afc2dfb59e74fece2fdc3586ca31c795be7b29cf6b668ce238d702ed8` |
| `docs/brandbook/tokens/serverdeck.tokens.json` | `294b3fe4f7adcb1319f89fc4a2eb2872c8ba84a81cd05ccda610d9895da8a2d0` |

Реестр программы содержит ровно98 уникальных стабильных IDs и владельца каждой будущей пары «функция + дизайн». Текущий acceptance registry003 содержит37 сценариев, перечисленных FA06; исторический `implemented` не доказывает готовность и не исключает11/93. Смена состава текущего scope требует явного согласования, а не нового значения флага. Изменение источника фиксируется обычной историей версии и причиной; текущий Flutter не становится новым каноном.

Композиция HTML определяет области, поля, columns/tabs/actions и порядок элементов. Header actions, filters/search, rows, overflow, copy, chart/table и подтверждения сверяются в настоящих Flutter widgets. Каждое доступное действие вызывает прежний разрешённый callback и использует фактическую цель; будущая функция имеет своего владельца и честное объяснение недоступности. Читаемая [таблица действий](base-affordances.md) помогает этой сверке. Исполняемый manifest, машинный registry каждого instance и отдельный валидатор не нужны.
Публичные инструкции используют пути относительно корня репозитория. Первоначальный export `output/design-all-pages-2026-10-25/previews/{theme}/{desktop|compact|mobile|small}/{screenId}.png` — вспомогательная ignored provenance, не runtime dependency. Локальная provenance-запись может хранить фактическое расположение и SHA256 PNG; никакой абсолютный путь автора не требуется для сборки, тестов или работы приложения.

Для прямой сверки используются закреплённый HTML, брендбук и имеющиеся исходные PNG. При недоступности браузерного просмотра ограничения не обходятся; источник можно читать как документ и сравнивать по доступным изображениям. Computer Use и автоматизация рабочего стола не требуются и не применяются вопреки указанию пользователя. Отдельный source renderer не создаётся.

## FA02 — Production composition и граница данных

Точные роли/assets находятся в `lib/theme`; shared surfaces, controls, panels, tables/cards, status, charts, forms и menus — в `lib/ui`, с `deck_page.dart` и `deck_data_table.dart` рядом с существующим `deck_components.dart`. Общий chrome остаётся в `lib/shell/foundation_shell.dart`; `lib/shell/deck_navigation.dart` задаёт RAM `DeckLocation`/`DeckNavigationController`, `lib/shell/base_workspace.dart` размещает существующих owners с ключом client/server/privateEpoch. Feature widgets остаются в своих существующих модулях и используют нынешние controllers/typed projections/callbacks. Реестр98 — documentation/test metadata; production navigation содержит только текущие base views, без gallery будущих экранов. Это presentation integration, не новый владелец effects и не новые Local API/Isar DTO.

Допустима общая route с разными состояниями/panes;37 отдельных Navigator routes не требуются. Все37 композиции и существующие функции должны быть достижимы в обычном приложении. HTML/WebView атласа, screenshot background, debug gallery и test-only navigator не являются реализацией. Existing controller/panel lifecycle проверяется отдельно от простого isolated body render.

Реальные значения поступают от соответствующего owner; `value/rows` атласа используются только в design/test fixtures. Fixture передаёт синтетические данные настоящим production widgets/controllers через fake delegates/transports в unit/widget runner. Production runtime не загружает demonstration rows, canned service results, atlas handlers или fixture state switches. Отсутствие данных не становится нулём, вымышленной метрикой, чужим target или успешным результатом.

Композиционные области текущих страниц сохраняются: например summary, profile identity, observation area, actions, source/time и context. Когда конкретный future affordance/field требует ещё отсутствующей функции, его место и визуальная роль трассируются к владельцу будущего пакета; существующие данные и действия отображаются полноценно. Неактивный future control имеет явное объяснение доступности в этой версии, без ложного «сервер не поддерживается» и без demo callback. Он не считается реализацией функции. Такая запись не разрешает оставить всю базовую страницу generic unavailable и объявить перенос завершённым. Функциональный scope и дизайн будущего affordance закрываются вместе у владельца.

## FA03 — Конечный CSS cascade и геометрия

Размеры — logical px при DPR1, без OS title bar и atlas chrome. Применяется конечный CSS cascade закреплённого HTML, включая последующие responsive overrides; первая декларация sidebar184 не является действующим эталоном.

| Условие | Композиция при100% текста |
| --- | --- |
| width >1060 | Sidebar210 на всю высоту; topbar только над рабочей областью height56; content padding top26/horizontal28/bottom24 |
| 520 < width ≤1060 | Rail68; topbar56; content padding24; mark вместо sidebar logo; полные accessible labels и tooltips |
| width ≤520 | Sidebar/rail скрыты; topbar62, logo145×44 и icon targets44; content padding top22/horizontal16/bottom24; одна колонка; bottom navigation68 плюс safe area |
| width ≤760 | Двухколоночные detail panels становятся одной колонкой; profile identity/state/system/metrics/actions сохраняют порядок renderer |

Дополнительно проверяются границы520/521,760/761,1060/1061. На800×600 используется rail, на1100×760 sidebar. Desktop sidebar padding24/16/18, logo160×48. Workspace switch находится между logo и пятью main items; local-service/storage/operator context — снизу. Operator показывает фактический локальный контекст; фиктивная учётная запись OP не вводится. Наличие места для identity в дизайне не добавляет аккаунт или OIDC-функцию в003.

Пять main sections: Серверы → ПО → Журналы → Задания → Настройки. Selected item имеет canonical selected surface/accent indicator и `Semantics.selected`. Sidebar items min-height44; rail centred icons имеют tooltip по hover/focus/long press. Sidebar/rail прокручиваются при недостатке высоты. Topbar содержит breadcrumb и реальный locald status; SSH/observation не выдаются за local readiness. Phone использует logo/actions без desktop breadcrumb.

Page header сохраняет eyebrow/title/description/header actions, порядок и выравнивание renderer. Действия переносятся при недостатке места. Header не заменяется единственной строкой Material AppBar. Workspace selector, footer, filters, summary, panels и row/card compositions не исчезают ради уменьшения работы. Объяснения существующих security/prerequisites растут и не перекрывают controls.

Внутри каждого origin используются окончательные CSS rules/renderer: panel radius12, control8, dialog16; panel header/body padding, gaps, columns, table/card/key-value, timeline и chart shapes. Generic ExpansionTile/AlertDialog не считается переносом другой композиции только из-за одинакового текста. Страничные формы/планы сохраняют composition в production page/pane; реальные transient dialogs используют соответствующую context/consequences/controls composition. Выбор container не отменяет требование совпадения проверяемых regions.

Phone server/software/job lists используют cards/sections; whole-page/server-list horizontal overflow запрещён. Raw logs/value tables могут иметь отдельный labelled scroll с доступным context. Числа выровнены вправо; table rows не превращаются в отдельно скруглённые pills. Формы растут и прокручиваются над keyboard insets, сохраняя достижимость actions.

### Уточнение пользователя — 2026-10-29: header actions04

На экране04 «Первый запуск» две верхние кнопки «Добавить сервер» и «Настроить ИИ-доступ» должны располагаться в одну строку на широком экране, когда хватает места. Ограничение max-width300 из первоначального атласа для этого конкретного action region отменено явным уточнением пользователя. Действуют natural width двух controls, gap8 и прежний responsive header flow; при нехватке ширины сохраняется адаптивный перенос/phone layout. Остальные страницы не получают глобального изменения max-width. Нижняя пара welcome actions и callbacks не меняются. Сравнение04 учитывает это уточнение наряду с каноническими размерами, а не возвращает отвергнутую пользователем вертикальную desktop пару.

## FA04 — Типографика, цвета, иконки, controls

Все24 роли каждой темы берутся из tokens JSON, без seed palette и системных defaults. Проверяется фактическая композиция: text≥4.5:1, controls/focus/chart≥3:1. Disabled использует непрозрачные роли. Dark shadow отсутствует; light shadow `0 4 16 rgba(23,35,55,0.10)` применяется только к menus/dialogs.

| Роль | Семейство, размер/line height/weight |
| --- | --- |
| Page title | Noto Sans24/32/600 |
| Body | Noto Sans14/20/400 |
| Table data | Noto Sans13/20/400 |
| Logs, versions, commands | Noto Sans Mono13/20/400 |
| Button, table header | Noto Sans13/20/600 |
| Caption/metadata | Noto Sans12/16/400 |

Оригинальные Noto Sans regular/semibold и Noto Sans Mono поставляются побайтно с OFL. Существующий лицензированный bundled Unicode fallback используется для отсутствующих glyphs; системный font/network не является условием русского UI. Особые роли renderer, например large numeric value и section heading, сохраняют его CSS metrics, а не становятся общей caption/body.

Конфликты источников закрыты по приоритету: table-header12/18/400 HTML становится13/20/600; phone button14/20 становится13/20/600; caption/metadata11px не подменяет12/16. CSS disabled opacity .5 заменяется непрозрачными semantic roles; target<44 получает hit area≥44 без изменения видимой icon20. Эти явные поправки применяются в Flutter и учитываются при прямой сверке с исходными PNG. Они не разрешают замену канонической структуры новой компоновкой и не требуют отдельного reference manifest.

Иконки воспроизводят canonical SVG `paths` атласа: viewBox24×24, stroke1.5, round cap/join, fill none, штатный size20; отдельные размеры renderer сохраняются. Material icon с другим силуэтом не проходит по одному совпадению смысла. Logo/mark используют соответствующие dark/light assets, пропорции и охранное поле; не перерисовываются системным шрифтом. У icon-only control есть accessible name и tooltip.

Проверяются normal/hover/focus/selected/disabled/loading/error применимых controls. Приоритет disabled > error > focus > selected > hover; error сохраняет информацию focus/selection. Focus outline2/gap2 снаружи control; touch target≥44×44, desktop control visual36, phone control min44 по окончательному CSS. Pending показывает этап и блокирует второй dispatch; reduced motion оставляет static symbol/text. Motion120/180ms не изменяет исход операции.

## FA05 — Производный эталон200%

У HTML нет text-scale control, а CSS задаёт явные px font sizes. Поэтому200% — производная композиция по следующему алгоритму, а не готовый исходный PNG. Browser zoom, `transform:scale`, изменение только root font и увеличение PNG его не воспроизводят.

1. Зафиксировать viewport/DPR1/theme/source revision/screen/state/fixture и поправки FA04. Breakpoints используют неизменную available logical width.
2. Удвоить font size и абсолютную line height каждого текста; сохранить family/weight/letter spacing/значение. Relative line-height сохраняет multiplier. Не удваивать icons/strokes/padding/gaps/chart plot heights.
3. Обязательные label/value/error/context не имеют maxLines/ellipsis/scale-down/nowrap; длинное неделимое значение допускает перенос внутри слова. Block/row/control heights — min-height и растут по содержимому; header actions/filters/form actions переносятся. При200% source `.two-columns`, `.two-columns.equal`, `.form-grid` и `.stats-grid` используют одну колонку во всех frames. `.profile-card` использует одноколоночную перестройку source≤760 с порядком identity → state → system → три metrics → actions; три компактных metrics сохраняют свой порядок и three-column block, labels/values переносятся, plot heights не меняются. Это обязательные правила Flutter layout, без выбора нового breakpoint по усмотрению реализации; они учитываются при прямой сверке с дизайном.
4. Phone navigation при100%: пять columns, icon20/gap4, caption12/16, min item52, panel68 плюс safe area. При200% item width=`max(44,ceil(max(normalLabelWidth,selectedLabelWidth))+8)`, не больше ширины панели; items переносятся целиком в исходном порядке, spacing/runSpacing4, panel padding horizontal4/vertical6. Слишком длинная label занимает full-width item с переносом. Panel height определяется рядами; body получает оставшуюся высоту и vertical scroll.
5. Topbar56/62, controls/dialogs могут расти по своему тексту; navigation columns210/68, content margins и breakpoints не меняются. Page context включён в page scroll, а не отнимает фиксированные35% высоты. При keyboard inset>0 phone navigation временно скрыта без изменения section/draft.
6. Raw content имеет отдельную bounded scroll area с именем, keyboard focus и доступным context. Focused field/action reveal обычной прокруткой; errors/submit/next step и focus outline не обрезаются.

Правила реализуются в Flutter и проверяются обычными widget tests и прямым просмотром при 200% текста. Исходный100% PNG не растягивается; отдельный HTML adapter или производный набор файлов эталона не требуется. Неразрешённое различие исправляется в UI, а не обновлением baseline из текущего Flutter.

## FA06 — Текущие37 сценариев и обычная навигация

Registry включает раздел, production composition/owner, source reference, context и entry каждого origin. Приведённые transitions интегрируют существующие функции; не требуют нового fleet inventory, provider или backend. Context содержит workspace/private epoch, section, typed target/resource/profile/revision/plan/job/grant IDs, filter/sort/page, route-owned draft и return/scroll context. Display name не заменяет identity.

| ID | Production entry / context |
| --- | --- |
| 01-startup | Bootstrap → фактические starting/recovering/stopping; workspace/typed stage |
| 02-service-unavailable | Bootstrap → фактический locald failure/retry; workspace/reason |
| 03-storage-blocked | Owner → существующий protection/storage failure; workspace/reason |
| 04-empty-workspace | Серверы → успешно загруженный пустой каталог |
| 05-server-list | Серверы → настоящий каталог профилей |
| 06-server-overview | 05 → открыть конкретный профиль/сервер; matching target/revisions |
| 07-profile-create | 04/05 → Добавить сервер; route-owned draft |
| 08-profile-edit | 05 → Изменить выбранный профиль; captured revision/draft |
| 09-profile-delete | 05 → удалить выбранный профиль; captured identity/revision/confirmation |
| 10-host-trust | Явное подключение → первое доверие; exact host identity/fingerprint |
| 11-host-key-changed | Существующий SSH owner → changed key; прежняя и новая identity, чтение/запись заблокированы |
| 12-credential-input | 07/08 → существующий credential method/input; secret остаётся у формы |
| 13-mutation-conflict | Profile mutation → definitive conflict; original request/draft/revision |
| 16-install-catalog | ПО → существующий catalog; выбранный target требуется только существующим owner действием |
| 17-recipe-detail | 16 → выбранный recipe/version/digest |
| 18-install-preflight | 17 → Проверить готовность для явного server/recipe |
| 19-plan-approval | 17/18 → точный owner plan/target/digest/expiry |
| 22-server-logs | Журналы; 06 → Журнал; выбранный server/source |
| 23-log-record | 22 → открыть конкретную запись с captured target/source/two timestamps |
| 27-job-list | Задания → существующие jobs выбранного scope/target; без выдуманной global aggregation |
| 28-job-detail | 27 → выбранный job/plan/target |
| 29-job-unknown | Job owner → unknown outcome прежнего job/operation |
| 30-job-cancel | 28 → существующая cooperative cancel/stop-waiting semantics |
| 31-recent-operations | Задания → Последние локальные операции |
| 32-automation-profiles | Задания → Ansible-профили; 06 → Автоматизация |
| 33-profile-authoring | 32 → Новый профиль/редактирование; immutable basis/draft |
| 34-profile-revisions | 32 → Выбрать версию/сравнение выбранного profile |
| 35-plan-parameters | 17/34 → параметры exact version/target перед планом |
| 36-ai-grants | 04/05/84 ИИ-доступ; Задания → ИИ-доступ. Целевая section — Настройки, независимо от caller |
| 37-ai-grant-form | 36 → существующий grant editor в Настройках; target/scope/expiry/draft |
| 38-mcp-client-config | 36 → конфигурация конкретного grant в Настройках |
| 39-delegations | 34 → делегирование выбранной immutable version |
| 40-executor-binding | 06 → существующая подготовка исполнителя; host/key/inspection/expiry |
| 84-settings | Настройки → service-owned settings |
| 85-settings-form | 84 → Изменить настройки; captured revision/draft |
| 93-protected-effect-blocked | Только существующий валидный `AutomationPlanRecord.status=blocked` в текущем matching target/version context → композиция отказа плана. Причина защиты и идентичность эффекта могут быть неизвестны; точная проекция задана FA07.1 |
| 94-plan-invalidated | 19 owner → stale/expired/invalidated plan с original identity |

Пять main sections всегда доступны. ПО ведёт в существующий16 catalog, а не притворяется будущим14 inventory; Журналы и Задания используют действительный выбранный server/scope и при необходимости предлагают выбор существующего профиля. Выбор не подключает автоматически. Задания имеют entries32/31/36, также доступные без выбранного server там, где это разрешает нынешний owner. Возврат23→22 и modal return используют сохранённый безопасный context. Server overview открывает существующие recipes/automation/executor/logs через реальные entries; не требуется раскрыть гигантский ExpansionTile, чтобы найти эти функции.

State compositions выбираются реальным owner result, не production query-флагом.11 и93 имеют собственные primary bindings/captures: старые captures35 их автоматически не принимают.93 проверяет уже действующий protected-plan отказ, а не добавляет ещё отсутствующие операции других domain services. Неизвестный/недействительный target не заменяется чужим выбранным профилем. После readiness/authority/session invalidation private panes/dialogs/secret drafts/unconfirmed approvals скрываются; late reply их не возвращает. Durable history не удаляется.

Theme/resize/textScale сохраняют State/controller identity, draft, selection/filter и поддержанный pause/scroll context; не создают повторные subscriptions/connect/read/write/approval. Уход из UI не равен job cancellation. Исчезнувший chrome focus переходит на эквивалентный selected control без effect; обычное закрытие modal возвращает focus на launcher или безопасный control того же context.

## FA07 — Действия и честные результаты

### FA07.1 — 93: существующий blocked plan без выдуманной причины

Существующий wire record содержит `reasons[{code,field,stepId}]`; при `status=blocked`
его `effects` и `checks` пусты по инварианту протокола. `QUALIFICATION_REQUIRED`
исполнителя и преобразованный `RUNTIME_INCOMPATIBLE` не являются признаком NetBird
или конкретного защищённого эффекта. Ни текст сообщения, ни `field=packages`,
ни одинокий errorCode без валидного blocked plan не выбирают93 как доказанную
защитную блокировку.

Обычный вход93 — открыть полученный текущим owner валидный blocked plan из18/19/28.
План связан с тем же serverId, `AutomationRevisionKey` и текущими display stamps.
Если record отсутствует, остаётся ошибка исходной страницы; новый93 не создаётся.
Статус runnable не перенаправляется в93; invalidated/expired использует94.
Просмотр сохранённого blocked record явно помечается историческим и не объявляет
его сегодняшним результатом. Typed display projection в `automation_sections.dart`
является readonly RAM value и не меняет wire/storage/API/полномочия.

Для нынешнего обобщённого payload заголовок — **«План заблокирован»**, статус —
**«Исполнение не разрешено»**. Выводятся фактические код, поле и optional stepId
причины, исходная цель и время из record. Область эффекта сохраняет место и подпись
**«Сведения о конкретном защищённом эффекте не предоставлены»**. Нельзя писать
«Затрагивается NetBird», название пакета либо список неполученных effects/checks.
Независимый reference case называется `93-blocked-unspecified`: это композиция93
с изменёнными фактическими текстами/неизвестными значениями, не demo protected result.
Подробный protected-effect discriminator и новые domain effects остаются расширением
соответствующих006/016; их отсутствие не выдаётся за реализованную классификацию.

Affordances:

- «Просмотреть причины» открывает readonly реальные `reasons` этого же immutable
  record. Оно не перечитывает SSH и не запускает preflight/apply.
- Каноническое «Открыть запрещённый эффект» остаётся в композиции, но при нынешнем
  payload неактивно с объяснением **«Сервис не передал идентичность эффекта»**.
  Нельзя открывать desired step под видом доказанного эффекта. Если stepId есть,
  отдельное «Открыть исходный шаг» показывает matching `desired` step как запрос,
  с явным различием запроса и разрешённого эффекта.
- «Изменить исходный запрос» открывает прежний33/35 для exact plan.key и сохранённых
  inputs только при наличии matching source revision и действующих прав. Иначе
  отображается readonly причина отсутствия источника/прав; другой current profile
  автоматически не подставляется. Сохранение и создание нового плана — отдельные
  существующие действия пользователя; прежний blocked record не переписывается.
- «Закрыть план» возвращает в безопасный caller context той же цели, без approval,
  apply, повторной записи или реконструкции неизвестного эффекта.

T133/T136 проверяют валидный blocked с generic qualification/runtime reason,
пустыми effects/checks, отсутствующим stepId и matching/nonmatching source; также
runnable, error-only, expired и чужой target. Обязательные отрицательные assertions:
нет необоснованного NetBird/protected-cause текста, отсутствующая identity не даёт
активной кнопки, просмотр причины/шага ничего не исполняет, privacy retirement
скрывает весь record. Этот контракт закрывает только существующую проекцию blocked
plan и не утверждает готовность будущего service-specific protected-effect UI.

Каждое existing-function/state/local-view affordance имеет owner FR/AC, production callback/projection, input identity, prerequisites, pending/result/unknown/recovery branch, implementation task и unit/widget assertion. Виды: navigate/read/local-view/copy-export/write/wait. `wait` только отображает действительное ожидание owner transition («Дождаться запуска»), не создаёт фиктивного запроса. Local-view меняет настоящий поддержанный tab/filter/draft; copy/export даёт фактический разрешённый результат. Demo toast/state toggle не является binding.

Read, диагностика, просмотр плана, точное согласие и запуск — разные transitions. Перед write видимы существующие target/current/desired/effects/data loss/downtime/restart/check/recovery. Согласие связано с immutable identity/revision/digest/expiry; смена target/credentials/trust/revision отзывает его. Protected effects не включаются ради кнопки макета.

Pending блокирует повтор того же dispatch, сохраняя независимую navigation. Отмена ожидания не обещает server cancellation. Unknown outcome сохраняет прежнюю operation identity и показывает owner result check; automatic new write/retry/payload запрещены. Definitive conflict сохраняет draft и требует существующий явный recovery. Late completion проверяет current owner/context generation и не закрывает чужую форму. Пароли/ключи/tokens не попадают в route URL/general context/history/diagnostics/capture fixtures.

Локальные search/filter/selection05 работают только над уже загруженными ProfileView и известными connection projections: не требуют fleet API/polling, а ненаблюдённая связь остаётся unknown. Канонические структурированные поля33/35/37/39 оформляют существующие JSON/typed schemas и прежние validation/save/plan/grant/delegation callbacks; сохранение старого JSON-only интерфейса не выполняет перенос макета. Это presentation draft/codec, без расширения допустимых API данных или полномочий. Отсутствующие remote filters/pause/global aggregation/save-and-connect не изобретаются внутри003: их дизайн и функции трассируются к004–020 с явно обозначенными controls. Внешний OIDC является отдельным принятым направлением будущей синхронизации, не разрешением реализовать backend/provider или экран87 в этом этапе.

## FA08 — Поддержанные состояния и matrix

Каждый из37 сценариев имеет primary case и все поддержанные текущим owner states: normal/data, loading, successful empty, validation/conflict, denied, unavailable, unsupported, stale, dropped/incomplete, pending, unknown, trust/protection/readiness/privacy transitions там, где они существуют. Возможности HTML variants не доказывают существование runtime state/API. N/A требует точной причины из текущего контракта; существующая обязательная ветвь не закрывается N/A. Отдельно `future-owner` сохраняет невыполненную функцию будущего пакета, без притворного pass.

| Фактическое состояние | Проверяемое отображение |
| --- | --- |
| Loading | Точный источник/этап/running symbol; не successful empty |
| Successful empty | Успешно получен пустой результат реального scope/filter/time |
| Data | Значения/единицы и предусмотренные owner target/source/observedAt/receivedAt/quality |
| Denied / unsupported | Разные причины/next step; не zero/empty/success |
| Offline | Locald отдельно от выбранного SSH host; независимый local catalog остаётся доступен |
| Stale | Snapshot/time/source и отсутствие утверждения о текущем результате; gap не превращается в линию до now |
| Incomplete/dropped | Неизвестные поля/утраты явно отмечены; counts только из результата |
| Validation/conflict | Readable связанное объяснение, сохранённый draft, явное исправление/сверка |
| Pending/unknown | Разные состояния, exact previous identity, запрет дубликата записи, owner recovery |
| Trust/protection/privacy | Fail closed, причина и безопасный next step; invalidated private context скрыт |

Primary003 matrix:37 × {1100×760,800×600,390×800,360×800} × {light,dark} × {1.0,2.0} = **592 разных cases**. Для этих37 есть296 исходных100% PNG как provenance; проверки при100% учитывают поправки FA04, а при200% — также FA05. Каждый дополнительный поддержанный state checkpoint проходит те же16 комбинаций; focus/hover/disabled/keyboard/scroll cases дополняют matrix. Будущая совокупная программа98 требует1568 primary cases после реализации соответствующих пар «функция + дизайн» у владельцев; это не критерий завершения текущего003 и не повод принять остальные61 как implemented.

## FA09 — Прямая приёмка интерфейса

Сравнить обычные страницы приложения с каноническими HTML/PNG и брендбуком. Проверяются состав/порядок областей, alignment/grid, sidebar/rail/topbar/content/header/actions, panels/cards/tables/forms/charts и phone nav. Explicit CSS/token размеры и x/y/width/height имеют допуск≤1 logical px; font role/family/weight/line height точны. Переносы и baseline соответствуют правилам FA03–FA05; 200% не является растянутым screenshot.

Непрозрачные fills соответствуют RGB роли. Anti-alias края glyph/path учитываются при просмотре, но не скрывают неверный silhouette/stroke/layout или потерянный текст. Проверяются исходные SVG и logo assets. Отсутствующая обязательная область, неверный target/status, clipping или недоступное действие — дефект независимо от общего сходства фона.

Имена, версии и фактические состояния приложения могут отличаться от демонстрационных значений макета. Достоверность и полные значения проверяются непосредственно обычными unit/widget tests с fake внешними зависимостями; различия данных не оправдывают иную композицию, вымышленные значения или скрытые controls. Общий JSON-корпус, второй валидатор, язык bindings, schema bundle, receipt graph и source adapter не являются условиями приёмки.

Desktop/compact PNG может быть full-page: сравнивается верхний viewport и доступность оставшихся областей при прокрутке, без уменьшения всей страницы до frame. На phone проверяются navigation, последний action/context, keyboard inset и длинные детали. Focus, copy, inner scroll, real callbacks, pending/unknown и privacy проверяются обычными widget regressions на production tree.

Фиксируются фактически проверенные страницы/условия и найденные различия. Контрольные размеры, обе темы и 100%/200% сохраняются; создавать отдельный файл эталона для каждого сочетания не требуется. Старые passes, макеты и contact sheets не доказывают текущего результата. Непросмотренная ветвь остаётся непроверенной.
## FA10 — Показ и отдельные статусы готовности

Действует static/unit/widget stage из [AGENTS](../../../AGENTS.md). Tests используют production presentation/controllers и fake delegates/transports, без внешних эффектов. Обычные mandatory checks идут с очищенными capture variables и ожидаемым opt-in skip. Отдельные widget capture/golden runs имеют записанные invocation/scope и не разрешают native/FFI/Isar/DPAPI/real process/pipe/SSH/container/systemd/Ansible/integration qualification tests.

Поставка003 включает разрешённые пользователем сборку, установку и показ настоящего приложения с отдельными build/package/install evidence. Показ использует normal production navigation и фактические данные/действия, без атласа/gallery/test routes/fixture flags. Запись содержит source revision, installed version/package identity, actual client area/DPI/text scale/theme, открытые entries, наблюдаемые состояния и screenshot/video paths. Показываются пять разделов, новая композиция server list/overview, существующая форма, plan/job context и settings по фактической доступности данных. Ненаблюдённая ветвь честно отмечается; этот показ не является полной runtime/native квалификацией.

Раздельные статусы: visual-contract-ready (правила/источники/data boundaries определены, spec review clean), base-ui-implemented, unit-widget-verified, visually-verified (полный заявленный003 matrix), installed-shown. Завершение003 требует этих относящихся к текущему scope результатов и clean независимого review по правилам репозитория. Оно не означает whole-program-complete: остальные61 экран, их функциональные сервисы, ещё не выбранные providers/backend и соответствующая квалификация остаются у004–020 и других профильных владельцев. Исторические и новые отложенные проверки явно отмечаются not-run; не становятся pass от source-only или visual результата.
