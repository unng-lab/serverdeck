# Этапы Spec Kit — 008

## Clarify — 2026-11-09

Вопросов задано:0. Критических неоднозначностей для формального уточнения нет.
Текущая проверка опирается на spec/plan/model/contracts и независимое ревью пакета.

| Категория | Покрытие |
|---|---|
| Scope / поведение | Clear: US-801–804, FR-801–812 |
| Модель / идентичность / lifecycle | Clear: data-model.md |
| UX / ошибки | Clear: AC-805–813, contracts/tools.md |
| Нефункциональные ограничения | Clear: bounds, auth/privacy, unit-only scope |
| Внешние зависимости / протокол | Clear: существующие003/007, внешний ИИ-клиент |
| Recovery / concurrency | Clear: revision, receipt24h, disconnect, atomic effects |
| Constraints / terminology / completion | Clear: plan, AC/SC, отсутствие placeholders |

requirements.md повторно оценён:16/16→16/16, изменения маркеров не требуются.
Custom checklist software.md сгенерирован:14 unchecked требований качества,
reviewer-owned. Extensions.yml отсутствует; before/after hooks неприменимы.

## Tasks

Сгенерировано27 задач: foundation7; US1=2, US2=7, US3=5, US4=3; final3.
Порядок и независимая приёмка находятся в tasks.md. Реализация пока не начата.

## Карта требований к задачам

| FR | Задачи | AC / SC |
|---|---|---|
| 801 | T008,T009,T013,T020 | AC-801–803; SC-802 |
| 802 | T008,T009,T010,T011 | AC-802/804 |
| 803 | T008,T009 | AC-803; SC-802 |
| 804 | T003,T007,T010,T024 | AC-805/813; SC-801/805 |
| 805 | T006,T010–T016,T020 | AC-805–807; SC-801/803 |
| 806 | T003,T004,T010,T011,T015,T016 | AC-808 |
| 807 | T004,T005,T007,T014,T026 | AC-808–811; SC-804 |
| 808 | T004,T005,T007,T010,T011,T017 | AC-809; SC-803 |
| 809 | T004,T006,T017–T021 | AC-810 |
| 810 | T015,T017–T021 | AC-810/811 |
| 811 | T022–T024 | AC-812/813; SC-805 |
| 812 | T004,T005,T007,T010,T014 | AC-807/808 |

## Analyze — 2026-11-09

Read-only анализ spec/plan/tasks после check-prerequisites -RequireSpec -RequireTasks
-IncludeTasks: замечаний0; requirements17(12FR+5SC),tasks27,coverage100%,ambiguities0,
duplications0,critical0,unmapped tasks0,constitution conflicts0. Карта выше и задачи
содержат полное соответствие. Следующий gate — независимый review пакета/checklist,
затем speckit-implement. Исправления в рамках Analyze не выполнялись.

## Pre-implementation review / setup

Независимый read-only reviewer /root/review_008_tasks: замечаний0, готов к реализации.
По его явному запросу применены [x] CHK001–014, требования одобрены (14/14).
В requirements.md16/16; implement gate PASS. Это не отметки реализации.
Проверены fake repository test/fixtures/domain_repository.dart, FeatureHarness,
общий gate/ReceiptBook и места composition. .gitignore покрывает generated build,
.dart_tool, local evidence и secrets; новых runtime dependencies нет.
T001/T002 выполнены: этапы/карта сохранены, seams проверены.
Baseline unit console suite: flutter test test/console test/mcp/console_router_test.dart
test/mcp/console_session_test.dart test/connections/console_transport_test.dart
test/connections/console_pty_test.dart — exit0,84 passed, лог
.local/software-008-console-baseline.log. Только fake/unit, не real SSH.

## Foundation T003–T007

Реализованы typed DTO/validation, SoftwareValue, две additive Isar schema,
индексированные repository queries/counts/retention/cascade и detached fake records.
ReceiptMethod расширен тремя metadata-методами, добавлена SOFTWARE_NOT_FOUND.
Build runner успешно сгенерировал records.g.dart. Новый runtime не добавлен.
Unit RED перед моделью: отсутствующие типы, exit1; после реализации10 software
unit tests passed. Обе ошибки транзакции проверены на fake snapshot repository.

Проверки текущего foundation:
- root dart format --output=none --set-exit-if-changed .: exit0,499 files,0 changed;
- flutter analyze: exit0,no issues;
- flutter test: exit0,877 passed;
- tools/check-test-boundaries.ps1: exit0,113 Dart files;
- git diff --check: exit0.
Логи .local/software-008-foundation-{format,analyze,full-test,unit}.log.
Это unit/static evidence; реальная Isar/SSH и запуск продукта не выполнялись.
Остальные задачи реализации открыты; карточки пока не подключены к UI/MCP.

## Review corrections and owner checkpoint

Foundation reviewer выявил2 P2: safeJSON lower bound через abs overflow и строки
публичной проекции без полной Unicode/NUL-проверки. T028/T029 добавлены без удаления
выполненной истории; исправлены direct lower/upper comparisons и обход всех строк
публичной проекции без нормализации literal-полей. Boundary tests включают int64
minimum, safe bounds/соседей и некорректные target/author/snapshot/CRUD summary.

Начат общий SoftwareOwner: локальный CRUD/atomic events, receipts, optimistic revision,
endpoint marker/conflict, profile quotas, bounded pages. Receipt HMAC использует
исходное typed spelling входа, даже если public name trim-нормализуется.
Owner red test до появления типа: exit1. Теперь8 owner unit cases passed:
CRUD/stale, save/delete replay после cascade, paging/filter/cursor revision,
смена endpoint, concurrent retry/точный payload, revoke/author, quota, failCommit.
T010–T012 остаются открытыми до полной проверки сценариев/ревью, UI/MCP ещё не подключены.

После исправлений и текущего owner:
- root dart format --output=none --set-exit-if-changed .: exit0,501 files,0 changed;
- flutter analyze: exit0,no issues;
- flutter test: exit0,887 passed;
- tools/check-test-boundaries.ps1: exit0,114 Dart files;
- git diff --check: exit0.
Логи .local/software-008-owner-{format,analyze,full-test,unit}.log.
Цель активна: остаются shell acceptance closeout, полная owner/MCP/UI/analysis
реализация, converge, окончательные checks и независимые review/fix loops.

## Полная реализация US1–US4

T008/T009: общий shell подтверждён текущими console owners/ConnectionOwner.bindConsole/
transport.startOwnedPty и unit cases console_access/console_replay/console_lifecycle.
Дополнительно software_mcp_test проверяет конфиг-команды как raw ввод, один видимый
engine, повтор без resend, синтетический discovery двух экземпляров, пустые неизвестные
поля и запрет чтения после revoke. Никакого нового executor/file API нет.

T010–T024: один SoftwareOwner подключён к FeatureRuntime, MCP router и вкладке ПО
через ProfileViewPanel/runtime_view. UI использует существующие общие компоненты;
есть CRUD/форма/conflict reread, фильтр текущей страницы, paging, old-target marker,
запрет shortcut, журнал/заметки, явное копирование анализа с injectable clipboard.
History имеет actor/time/снимок имени/сообщённый исход и сохраняется после delete.

T030: многостраничный MCP тест выявил ложные конфликты от auth-clock, который
продвигает global dataRevision. Курсор использует snapshotRevision существующего
profilesListRevision, продвигаемого атомарно software-эффектами и профильными
изменениями. Проверки grant по-прежнему выполняются до чтения/эффекта/ответа.
Большие карточки обходятся всеми страницами без дубликатов/усечения, полный
text+structured response <=1MiB. Новое поле/миграция не добавлены.

Registry contractVersion3 содержит27 working tools. SHA256 canonical original21
проверяется unit test; исходные определения неизменны. Обе registry идентичны.
Pinned MCP2025-11-25 official schema audit:2 offline unit checks passed.
Runtime/import audit: schema list содержит обе коллекции; Flutter analyze проверил
замыкание импортов; software код не содержит Process/Isar.open/SSHClient/SFTP/
HttpClient/File calls, shell принадлежит существующим owners. Installer/deps неизменны.

## Проверки текущей полной реализации

- root dart format --output=none --set-exit-if-changed .: exit0,506 files,0 changed;
- flutter analyze: exit0,no issues;
- flutter test: exit0,915 passed;
- software subset:48 passed (включая8 functional widget tests и2 analysis tests);
- tools/check-test-boundaries.ps1: exit0,117 Dart files;
- python -m unittest discover -s test/mcp -p official_schema_test.py: exit0,2 passed;
- git diff --check: exit0.
Логи .local/software-008-feature-{format,analyze,full-test,unit}.log.
Это unit/static evidence. Реальная Isar, SSH, запуск продукта, integration/layout
и release проверки не выполнялись и не являются gate этого пакета.

## Acceptance evidence map

| Критерий | Текущая реализация / unit evidence |
|---|---|
| AC-801 | console open/read маршруты, общий ConsoleOwner engine; software_mcp_test discovery |
| AC-802 | write ack без command exit; тот же operationSequence не увеличивает channel.writes; console_replay/lifecycle |
| AC-803 | команды чтения/изменения конфига передаются обычным shell-вводом; software_mcp_test |
| AC-804 | console access/revoke и owner commit/response revoke cases, защищённый вывод не выдаётся |
| AC-805 | software_mcp_test CRUD roundtrip пяти полей; software_view_test форма/отображение |
| AC-806 | owner stale/concurrent tests; UI conflict сохраняет draft, требует reread; duplicate names |
| AC-807 | локальные repository/save/delete без SSH; история delete сохраняется |
| AC-808 | две schema в existing store format2, source storage audit и fake schema/rollback/cascade tests; old-target UI tests |
| AC-809 | единая транзакция card/event/receipt/revisions, fake failAfterWrite/failCommit; owner tests |
| AC-810 | history.add assigns actor/time, UI показывает сообщённый исход; note tests |
| AC-811 | deleted-card indexed history; заметки после delete видны; raw terminal fields отсутствуют |
| AC-812 | pure softwareAnalysisPrompt и explicit copy widget callback, без запуска shell/ИИ |
| AC-813 | synthetic discovery нескольких экземпляров и обычный software.save с null/empty |

SC-801 покрыт AC-805; SC-802 — AC-801–803; SC-803 — AC-806/809;
SC-804 — durable schema contract/source + fake preservation/delete history
(это не real database durability test); SC-805 — AC-812/813.
Окончательное подтверждение остаётся за Converge и независимым review/fix loop.

Полный link check текущего пакета: exit0,380 total/160 unique/374OK/0 errors/
6 baseline exclusions/2 redirects, .local/software-008-feature-links.log.
T026 выполнен: обязательные unit/static/link gates и audits завершены.

Analyze повторён после snapshot-контракта:30 tasks,17 требований(12FR+5SC),
coverage100%,unmapped0,ambiguities0,contradictions0,constitution issues0.
T030 связан с FR-805/808 и проверкой большого MCP обхода; исправление не добавило
runtime/Isar fields. Это read-only assessment; нормативные правки выполнены отдельно
в рамках реализации подтверждённого pagination-дефекта, не командой Analyze.

## Независимое полное review и completion audit FR/AC/SC

/root/review_008_full_implementation завершил read-only review всего изменённого
кода, registry, storage/generated/fakes, UI/MCP composition и пакета: замечаний0,
готовность подтверждена. CHK001–014 повторно одобрены без изменения маркеров.
T027 выполнен: предыдущие подтверждённые defects закрыты fresh review, все
FR-801–812/AC-801–813/SC-801–805 сверены с текущими source и evidence выше.
Непроверенных/отложенных продуктовых требований в этой карте не осталось;
ограничение unit/static scope явно сохранено. Следующий workflow gate — Converge.

## Converge и итоговый workflow audit

Spec Kit Converge завершён: converged, findings0 (missing/partial/contradicts/
unrequested=0), проверены12FR+13AC+5SC,12 buildable plan decisions,30 tasks и6
принципов конституции. Сам Converge не изменял tasks.md: SHA256 до/после одинаковый
AFE4CD8CA7943DE8EEF7AB51DA27976A97E18A89BB3208CB16B81E611679BE0A.
Затем implementation tracking отметил T025. Новые convergence tasks не требуются.

| Этап / deliverable | Доказательство завершения |
|---|---|
| Specify | spec.md, все US/FR/AC/SC и проверяемые границы функции |
| Clarify | coverage map,0 обязательных вопросов; fresh review не выявил обязательных решений |
| Checklist | requirements16/16, reviewer-owned software14/14, повторное одобрение full reviewer |
| Plan / Phase0 / Phase1 | plan.md,research.md,data-model.md,contracts/tools.md,quickstart.md |
| Tasks | T001–T030:30/30 выполнены, история выполненных задач сохранена |
| Analyze | повторный read-only consistency/coverage pass,17 требований/30tasks,100%,findings0 |
| Implement | source UI/MCP/storage/console reuse и48 feature unit cases,915 полный suite |
| Converge | текущая source-based сверка:0 unbuilt/contradictory requirements |
| Required checks | format/analyze/flutter test/boundaries/official schemas/links:exit0 |
| Independent loops | подтверждённые findings исправлены; fresh full review:0 findings |
| Completion audit | каждый FR/AC/SC имеет текущие source и unit/static evidence выше |

Constitution update неприменим: действующие принципы не менялись.
Taskstoissues неприменим: публикация GitHub issues не запрошена и не входит в пакет.
Extensions.yml отсутствует: registered before/after hooks нет.

Код после полного независимого review не менялся. Итог ограничен реализованной
функцией и unit/static-приёмкой; реальная связка на чистой ОС этим не доказана.
Никаких публикаций, releases, коммитов или операций на реальном сервере не выполнялось.

## Спецификация компактных карточек — 2026-11-10

По запросу пользователя и примеру текущей карточки добавлен FR-813,
AC-814/815, SC-806 и нормативный UI-контракт в contracts/tools.md. Plan/quickstart
описывают применение существующих C09/C19 и функциональную приёмку;
T031–T033 добавлены открытыми, без стирания выполненной истории.
Код не менялся: предыдущие отчёты completion/converge относятся к базовой функции,
не доказывают реализацию или проверку нового редизайна. Модель, MCP, хранение,
runtime prerequisites и зависимости не меняются. Новый scope: сводка и раскрытие
технических сведений/действий, локальное состояние, прежние ограничения другой цели.

## Spec Kit — компактные карточки: реализация и проверки

Цель пользователя от 2026-11-10: пройти все применимые этапы для редизайна.
Specify/Plan/Tasks: обновлены текущие артефакты, T031–T033 добавлены к истории.
Предварительное независимое review спецификаций /root/review_compact_software_specs:
замечаний0, пакет готов к реализации; проверены шесть изменённых документов,
полный пакет и API общих компонентов.

Clarify: повторный coverage scan — вопросов0. Scope/данные/идентичность/UX,
доступность, auth/privacy, зависимости, recovery/concurrency, ограничения,
терминология и критерии завершения определены в spec/model/contracts/plan.
Новых обязательных решений не обнаружено; размер и схема локальных данных,
протоколы/совместимость и runtime prerequisites остаются прежними.
Checklist: базовые requirements16/16 и software14/14 прочитаны как gate;
новый reviewer-owned [compact-cards](checklists/compact-cards.md) содержит6 пунктов
качества требований, ожидающих независимой оценки. Это не отметки реализации.

Analyze (read-only): prerequisites -RequireSpec -RequireTasks -IncludeTasks
разрешили текущий пакет. Покрыты19 требований (13FR+6SC), 33 задачи, coverage100%,
ambiguities0, duplications0, contradictions0, critical0, unmapped tasks0,
constitution conflicts0. Базовая карта выше сохраняется; FR-813/SC-806 →
T031–T033 → AC-814/815. Исправления продуктовых требований Analyze не потребовались.

Implement T031/T032: SoftwareView использует C09/C19 с полной сводкой и
раскрываемыми C18/C28/DeckActions; вложенная карточка заголовка удалена.
Раскрытие по id сохраняется на refresh, сбрасывается при смене контекста;
исчезнувшие id удаляются. Формы/owner/MCP/storage/console не менялись.
В software_view_test.dart6 новых функциональных cases, всего14: данные/unknown/
literal paths/UTC fallback, независимость раскрытия без эффектов, keyboard и
semantic state через стандартные localized hints C19, pending/console callback,
смена профиля и возврат, refresh/filter/deletion. Прежние8 cases обновлены для
раскрытия; paging case также проверяет сброс при переходе и возврате.

Реальные проверки текущего кода:

- `dart format --output=none --set-exit-if-changed .`: exit0,506 файлов,0 изменений.
- `flutter analyze`: exit0,No issues found.
- `flutter test`: exit0,944 passed; лог `.local/software-008-compact-full-test.log`.
- `flutter test test/software/software_view_test.dart`: exit0,14 passed до
  замены deprecated semantics matcher; полный suite944 подтверждает итоговый matcher.
- `tools/check-test-boundaries.ps1`: exit0,117 Dart files.
- `git diff --check`: exit0 на изменениях кода до финального документационного отчёта.

Ранние прогоны выявили nullable DateTime в тесте, слишком широкий finder текста,
неверный способ focus, lifecycle SemanticsHandle и deprecated matcher/import;
исправлено. Текущие успешные результаты получены после исправлений.
Это unit/static scope: продукт, реальные SSH/Isar, layout/captures и release
не запускались; эти проверки не являются gates.

Converge (read-only): после Implement повторно проверены текущие source owners,
DTO, repository, router/composition, UI и tests против 13FR/15AC/6SC и плана,
включая все33 задачи и6 принципов конституции. По текущей реализации gaps0
(missing/partial/contradicts/unrequested=0); новый convergence-раздел не добавлен.
tasks.md SHA256 до/после оценки:
`008366BB6952815F0BAD25F45D95351C38B259F422C105AB4AD4B9B1209A52B3`.
Независимый review/fix loop и его отражение в T033 пока не завершены.

Extensions.yml отсутствует: зарегистрированных before/after hooks нет.
Конституция не меняется; Taskstoissues неприменим, публикация issues не запрошена.

## Компактные карточки — независимое review и завершение

/root/review_compact_cards_implementation выполнил fresh read-only review всех9
изменённых/новых файлов, пакета008, общих API и затронутых границ owner/router/
runtime/repository. Замечаний0; готовность подтверждена, незавершённого кода
в проверенном scope не обнаружено. Reviewer самостоятельно прочитал итог944
в логе полного unit suite; остальные checks оценил по переданным реальным результатам.
Явно одобрены все CHK001–006 compact-cards; существующие requirements16/16 и
software14/14 остаются одобренными. По разрешению reviewer отмечены6/6 и закрыт
T033, код после review не менялся. Review/fix loop завершён без открытых findings.

Полный link check перед review: exit0,387 total/163 unique/381OK/0errors/
6exclusions/2redirects; diff-check и boundary check также exit0.

| Этап редизайна | Итог |
|---|---|
| Specify | FR-813, AC-814/815, SC-806, текущий UI-контракт |
| Clarify | Coverage scan,0 обязательных вопросов |
| Checklist | requirements16/16, software14/14, compact-cards6/6; reviewer approval |
| Plan / Research / Model | Композиция C09/C19 и lifecycle; existing API достаточно, новых схем/зависимостей нет |
| Tasks | T031–T033 выполнены; общая история33/33 сохранена |
| Analyze | 19FR/SC,33tasks,coverage100%,findings0 |
| Implement | SoftwareView и14 функциональных widget cases |
| Converge | 13FR/15AC/6SC и задачи/план/конституция: gaps0, tasks не менялись самой оценкой |
| Checks | format/analyze/unit944/boundary/links/diff-check прошли |
| Independent review | fresh review:0 findings; checklist одобрен, код завершён |

Все применимые этапы текущего редизайна завершены. Вывод ограничен unit/static
scope; запуск продукта на чистой ОС и реальные SSH/Isar не доказаны.
Коммит, публикация issues и релиз не выполнялись.

## Компактные события — новый Spec Kit scope 2026-11-10

Пользователь запросил компактные события, обновление спецификаций и цель пройти
все этапы. Предыдущие completion/release evidence относятся к базе/карточкам,
не к новому редизайну событий. Код на этапе подготовки пакета не менялся.

Specify: FR-814, AC-816/817, SC-807. Plan/Research/Model: C09/C19/C18,
локальный eventId lifecycle и presentation-only preview; новые runtime/API/
зависимости/миграции не требуются. Tasks: добавлены T034–T036 к выполненной истории.
Clarify: coverage scan scope/data/UX/accessibility/privacy/recovery/constraints/
compatibility/completion — Clear; вопросов0, обязательных пробелов не обнаружено.
Checklist: новый [compact-events](checklists/compact-events.md),6 reviewer-owned
критериев качества; базовый requirements16/16 повторно оценён автором без изменения
маркеров, custom checklist ожидает независимой оценки до Implement.
Analyze: read-only сверка текущих spec/plan/tasks/constitution: 21FR/SC
(14FR+7SC),36 tasks,coverage100%,ambiguities0,duplications0,critical0,
unmapped tasks0,constitution conflicts0. Новая цепочка FR-814/SC-807 → T034–T036
→ AC-816/817; остальные карты сохраняются. Analyze не редактировал артефакты.
Prerequisites разрешили текущий пакет; .specify/feature.json указывает008,
extensions.yml отсутствует, зарегистрированных before/after hooks нет.
Constitution/taskstoissues не требуют действий: правила не меняются,
публикация issues не запрошена. До Implement необходим fresh review пакета.

Первое pre-implementation review /root/review_compact_events_specs выявило1 P2:
SC-807/T034 ограничивали итог160, контракт давал160+«…». Подтверждено и закрыто
T037: лимит160 включает многоточие, границы160/161 закреплены в spec/contract/
quickstart и задаче исправления без удаления истории. Требуется fresh reviewer;
исходные claims coverage scan о полной однозначности до исправления не являются
окончательным approval. Общий task count теперь37; FR/SC21 и coverage100% сохраняются.

## Уточнение выбора коллекций — 2026-11-10

Пользователь отклонил отдельные accordion-карточки как основной вид коллекции
и явно выбрал таблицу ПО с названием/версией/службой/хостом. Текущие FR-813,
AC-814/815, SC-806, контракт/plan/research/model/quickstart обновлены напрямую:
C06 для ПО с одной областью выбранной записи, C07 compact для списка событий
с локальными подробностями C18 и действием C02. Новая T038 сохраняет выполненную
историю T031–T033; новые event tasks034–036 продолжают ту же цель.
Всего38 tasks,21FR/SC; цепочки FR-813→T038 и FR-814→T034–T036 полны.
Analyze/Clarify повторно сверили новую спецификацию без обязательных пробелов.

До уточнения подготовлены6 новых event functional tests (RED на старом UI),
затем промежуточная C19 реализация:20 widget tests passed. Это промежуточное
evidence, не приёмка выбранных C06/C07. Код ещё предстоит заменить на C06/C07.
Предыдущее fresh spec review review_compact_events_specs_fixed после T037:
замечаний0, preview лимит согласован, requirements16/16. После смены коллекций
compact-events checklist возвращён reviewer на оценку, добавлен CHK007 о C06/C07.
Нужен новый pre-implementation review изменённых решений.

## C06/C07 — Implement и Converge

/root/review_collections_specs завершил новый read-only review пакета: findings0,
готов к реализации; явно одобрены все7 CHK compact-events и requirements16/16.
Маркеры checklist применены по его разрешению; implement прочитал все4 чеклиста
как gate без unchecked items (16+14+6+7). Предыдущий выбор C19 заменён по прямому
указанию пользователя, без удаления выполненной истории.

T034/T035/T038: SoftwareView теперь использует C06 DeckCollection с четырьмя
колонками, одной выбранной записью и общей областью C18/C28/действий; события
используют C07 compact/C02 и C18 подробности под строкой. Preview160 Unicode
code points включает многоточие; данные не меняются. Отдельные состояния
selectedSoftwareId/expandedEvents сохраняют refresh/reset/prune. Изменений
SoftwareOwner, DTO, MCP, storage, runtime и API общих компонентов нет.

Функциональная приёмка:20 software_view cases, включая6 новых event cases.
Покрыты kind/source/UTC/outcome, границы160/161 с emoji, whitespace/full literal
selectable текст, pointer по строке и button, Enter/Space/semantics, независимость
событий и выбора ПО, refresh/error/new/disappeared id, history filter/page/profile
reset и сохранение событий при смене страницы/фильтра ПО. Прежние CRUD/conflict/
pending/old-target/history/console и поля таблицы/single selection/close сохранены.

Реальные итоговые проверки кода:

- `dart format --output=none --set-exit-if-changed .`: exit0,507 files,0 changed.
- `flutter analyze`: exit0,No issues found.
- `flutter test`: exit0,950 passed; `.local/software-events-full-test.log`.
- `tools/check-test-boundaries.ps1`: exit0,117 Dart files.
- Промежуточный `flutter test test/software/software_view_test.dart`: exit0,20 passed;
  после добавления row-pointer и независимости card paging итоговый полный suite
  выше также прошёл. Лог `.local/software-collections-widget.log`.
- RED до реализации preview: exit1, отсутствие компактного summary;
  `.local/software-events-red.log`. Последующие тестовые finder/semantics ошибки
  исправлены до успешных итоговых checks.

В рабочем дереве параллельно меняются тема/кнопки и shared design tests001 другим
заданием; эти файлы не редактировались данным заданием и не входят в его review.
Root checks выше проверили доступное рабочее дерево; не являются отдельной
приёмкой или review параллельного scope001. Shared design tests этим заданием
не запускались. Нет запуска продукта/real SSH/Isar/integration/layout/release gates.

Converge после Implement: read-only source assessment текущих UI/owners/models/
repository/router/composition и fake tests против14FR+17AC+7SC,38 задач и6
принципов конституции: missing/partial/contradicts/unrequested=0. Новые buildable
решения C06/single selection, C07/preview/lifecycle реализованы; T036 ещё ожидает
заключения независимого reviewer. Converge не добавлял заголовков или задач:
SHA256 tasks.md до/после `5D2108297EBC6B35FED7FE39923ED70E3DFF3FD2902E9918A7AA2DADAA6B217F`.
Последующая отметка выполненных задач — отдельный implementation tracking.

## C06/C07 — итоговый independent review и закрытие цели

/root/review_collections_implementation завершил fresh read-only review кода,
функциональных тестов, пакета008 и связанных owner/model/repository/router/
composition/shared API границ: замечаний0, обязательных пробелов нет,
реализация соответствует текущим требованиям. Reviewer независимо прочитал950
passed в unit-логе и выполнил scope diff-check exit0; остальные checks оценил
по переданным результатам. Параллельный scope001 исключён из заключения.

По его явному разрешению административно закрыт T036, обновлён status.
После review application code не менялся. Подтверждённый spec finding о preview
закрыт T037 и двумя последующими чистыми review спецификации; финальный review
кода новых findings не обнаружил. Review/fix loop завершён.

Перед финальным review ссылки: exit0,394total166unique388OK0errors6excluded/
2redirects; git diff --check exit0. Итоговая документационная проверка после
закрытия статуса выполняется теми же командами.

| Этап | Результат текущего scope |
|---|---|
| Specify | FR-813/814, AC-814–817, SC-806/807 согласованы с выбранными коллекциями |
| Clarify | Явный ответ пользователя: таблица ПО с четырьмя полями; остальных обязательных вопросов0 |
| Checklist | requirements16/16, compact-events7/7 одобрены независимыми reviewers; исторические checklist сохранены |
| Plan / Research / Model / Contracts | C06/single selection ПО, C07/C02/C18 для событий, presentation-only lifecycle/preview |
| Tasks | T034–T038 выполнены; вся история38/38 сохранена |
| Analyze | 21FR/SC,38tasks,coverage100%, актуальных contradictions/ambiguities0 |
| Implement | ПО — таблица, события — компактный список, полные подробности по запросу |
| Converge | gaps0, дополнительных задач не потребовалось |
| Checks | format507/0, analyze0, unit950, boundaries117, links/diff-check0 |
| Independent review/fix | Итоговое review0 findings; подтверждённое замечание спеки закрыто |

Все применимые этапы цели завершены в unit/static scope. Рабочие изменения этого
задания не коммитились и не публиковались; релиз0.3.3 остаётся предыдущим выпуском.
Реальная связка продукта на чистой ОС этим заключением не доказана.
