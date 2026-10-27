# Implementation Plan: Дизайн и доступность

**Feature**: `003-design-system` | **Date**: 2026-10-26 | **Spec**: [spec.md](spec.md)

**Checkout**: существующая ветка `feature/mcp-control`; новая ветка не создаётся. Первоначальный Setup выполнен с временным override для003 без записи общего указателя. Для продолжения полного цикла текущей цели существующий003 затем выбран в локальном `.specify/feature.json`; история001/021 и рабочая ветка сохранены. План охватывает003.1–003.3; реализация и приёмка им не подтверждены.

## Summary

Применить [дизайн ServerDeck](../../docs/design/README.md) к существующим Flutter widgets через точные темы, общие presentation components, адаптивный shell и доступную историю. Scope —35 scenario origins и общие компоненты пяти разделов;35 отдельных routes не требуются.63 концепта остаются у профильных пакетов. Демоданные/handlers атласа не входят в клиент. Runtime controllers, Local API, полномочия и storage не заменяются.

T100/P07 закрывает найденный при T041 пропуск existing context в log-record modal: ServerPanel захватывает авторизованный ProfileView/source/observedAt соответствующего logs result вместе с record; ServerLogRecordDialog принимает только эти display props и показывает их с различимыми UTC подписями времени записи и времени наблюдения вне bounded message scroll. Все production/test callers обновляются, реальные target/source не извлекаются из demo. Новых owners/API/хранилищ/зависимостей нет; проверяются F16, keyboard/semantics/scroll, честный missing source и P10 retirement. После fix повторяются full mandatory/native checks, свежие captures/visual delta и fresh T041.

Решения Phase0: [research.md](research.md). Phase1: [data-model.md](data-model.md), [UI contract](contracts/presentation.md), [validation guide](quickstart.md). Конкретные task IDs и результаты добавляются последующими Tasks/Implement, без изменения происхождения references.

## Переносимость эталона перед preview-релизом (T103)

FR-003-LOCAL-08/09 и AC-003-1A/1B проверяются также в отдельном checkout.
Descriptor `AcceptanceBinding.result=not-run` остаётся метаданными регистрации;
итоговая колонка screen-map сохраняет фактический статус `passed; scoped UI`
для35origins, а63concepts — `not-runtime-accepted`. Тест проверяет эти два уровня
отдельно. Descriptor экрана23 сохраняет завершённые T100/T102 в taskIds и точный
notApplicableReason той же строки screen-map, включая существующие target/source/
observedAt/identity и границу N/A; equality assertions не ослабляются.
Четыре canonical snapshots (brandbook tokens, DESIGN.md, HTML и
screens.json) сохраняют исходные байты через точечный Git attribute `-text`;
контрольные суммы validator и проверки изменения содержимого не ослабляются.
Существующий MCP UI helper сохраняется как исходная ссылка карты; его включение
не подтверждает full021. Минимальная существующая зависимость recipe-plan
controller включается в source handoff и проверяется с прежними authority gates.
Самостоятельный `tools/unit-coverage-zero.dart` включается как уже используемый
dev preflight по R11; quickstart явно создаёт generated protocol package context
через offline locked pub get перед запуском helper. Другие coverage tools/CI
не включаются. CR в canonical snapshots разрешён как окончание строки Git,
остальные whitespace checks остаются включёнными.
T103 не добавляет runtime, storage, API или возможности63concepts и не закрывает
gates подписи, native provenance либо public distribution005. Выпуск preview,
выбор MIT владельцем и локальная установка учитываются отдельно в release notes.

## Revoke target — T104

По существующим FR-126/P04 оба revoke-confirmations получают readonly snapshot
уже авторизованного ProfileView и показывают name/address:port в target-slot
DeckDialogLayout до согласия, включая корректные IPv6 brackets. Snapshot берётся
при открытии; обычные rebuild/resize/theme его не подменяют. Общий route flow
может быть выделен в presentation helper, чтобы тестировать actual modal без
подмены TrustedApiClient. Native revoke/CAS/read-before-write/owner/mounted и
private epoch остаются прежними; новых authority/ретarget правил не вводится.
F16 modal/semantics/cancel и существующие P10 revoke cases проверяют новый текст;
scoped visual captures/review покрывают только эту композиционную дельту.

## Profile body error wrapping — T105

По FR-126/FR-003-LOCAL-11/P04 JSON body field существующего
AutomationProfileEditorDialog задаёт errorMaxLines20, как соседние metadata
fields. Полное сообщение automationDraftInputError(profileBody:true) переносится
в поле без ellipsis в F16; общий dialog scroll сохраняет доступ к действиям.
Validation flow, точный draft, callback admission, pending/readOnly и ошибки
владельца не меняются. Actual malformed-save regression проверяет painted
RenderParagraph.didExceedMaxLines=false и полное сообщение, не только наличие
строки в widget tree. Scoped captures/visual QA покрывают эту error-state delta.

## Existing native CI fixture contracts — T106

Source-preview не ослабляет существующий GitHub CI. Для native fixtures
сохраняются действующие контракты001/021: обычный RPC заблокированного owner
возвращает STORAGE_BLOCKED до unsupported lookup; connected composition
сохраняет ту же MCP session при metadata-only profile edit; последующий
grant replace/revoke по-прежнему отзывает доступ. Bootstrap fixture ожидает
protected publication выбранного owner до запуска предполагаемого loser,
поскольку Process.start не доказывает владение mutex. Три исправления касаются
только существующих тестов; production/native/provider/API не меняются.
Два stale assertions воспроизведены локально до исправления. Выполняются
targeted native GREEN, оставшийся probes file, анализ и полный locald suite,
затем неизменённый GitHub workflow на точной commit revision. Результат
локальных targeted tests не объявляется cold qualification или успешным CI.

## Source-preview CI applicability — T107

Автоматический gate source-preview — существующий `mcp.yml` (SSH transport,
executor prerequisites, Windows MCP tests и полный cold-runner). Он сохраняется
без изменений и должен успешно завершиться на точной revision до merge/release.
`foundation.yml` остаётся ручным full-product acceptance workflow: удалить только
автоматические push/pull_request triggers, сохранив все шаги, cold-runner,
safe-proof и финальный unconditional отказ о незавершённых T044/Q01–Q12/Win11.
Эта ручная проверка не объявляется пройденной. Автоматические исполнимые Windows
проверки по-прежнему выполняются тем же cold-runner в MCP workflow; удаляется
дублирующий автоматический запуск full-product marker, а не тесты/ограничения.
Source-only preview и локальная review-установка не объявляют production готовность.
Локальные implementation-задачи T106/T107 закрываются после code/check/review;
post-commit CI — отдельный обязательный external gate. Его run/commit/conclusion
сохраняются в release evidence после выполнения, без изменения проверенного кода.
До фактического успешного terminal CI результата merge/publication запрещены.

## Technical Context

| Поле | Решение |
| --- | --- |
| Language/Version | Flutter3.47.7 / Dart3.13.5, framework `abaf9c523780a608bd46686fd5e53740a07077f8`; pin через `tools/foundation-sdk.ps1` |
| Dependencies | Существующие Flutter Material/Services, localizations, protocol/windows-пакеты; production set неизменен. Preflight добавляет только root dev dependency `analyzer:13.3.0` с offline pinned lock resolution поR11 |
| Platform | Windows; phone/compact — логические layouts, не новая заявленная mobile-платформа |
| Storage/compatibility | Существующий locald/store/DTO/schema; новых persistence entities, миграций, API versions или cutover нет |
| Assets | Bundled Noto Sans400/600, Noto Sans Mono400, брендбук1.1 logos и OFL; дополнительный offline Noto Sans SC fallback поR12 для отсутствующих glyphs, отдельные OFL/provenance; без runtime сети |
| Resource constraints | Нет новых timers/requests на resize/theme; history≤120points, разрыв линии при gap>15000ms; service limits/polling не меняются |
| Testing | Token/contrast assertions, widget/semantics/keyboard/layout fixtures, synthetic visual captures; существующий Windows bootstrap smoke |
| Static design tooling | Python≥3.10 со stdlib для `tools/validate-design.py`; `python` на PATH либо явный executable через `tools/check-design-references.ps1 -Python` после T003; новых production dependencies нет |
| Optional capture gallery | `tools/build-design-capture-gallery.py`, Python≥3.10; Pillow только для contact sheets, `--no-contact-sheets` использует stdlib. Читает local synthetic captures/records, не создаёт runtime acceptance |
| Scale | Две темы ×4frames ×100%/200%;98references =35origins+63concepts |

## Constitution Check

Проверено до Phase0 и повторно после Phase1 решений. Это проектная оценка, не runtime acceptance.

| Принципы | Вывод |
| --- | --- |
| I, II: границы/полномочия | Flutter→существующий trusted Local API; presentation-only components не получают DB/SSH. Layout не connect/trust/approve/apply |
| III, IV: secrets/наблюдения | Текущий credential lifecycle/readiness gate, synthetic captures; quality/source/time из DTO, без demo fallback и новых caches |
| V, VI: надёжность/полнота | Request identity/retry/cancel/expiry принадлежат001/021; UI contracts/adoption groups заданы; Tasks свяжут их с реальными task IDs до реализации |
| VII, VIII: проверка/поставка | Mandatory checks+fresh review; SDK/licensed bundled assets сохранены; публикация/merge не включены |

Нарушений выбранными решениями не выявлено. FR-125 целиком действует в003.1: текущие graph text values и различимые series внедряются уже там.003.2 расширяет keyboard/touch/phone/gap проверки поLOCAL-12, а не впервые вводит обязательную текстовую альтернативу.

## Project Structure and Responsibilities

| Место реализации | Ответственность |
| --- | --- |
| `lib/theme/brand_theme.dart` | Exact palettes; role-specific text/widget themes, включая button13/20/600 |
| `lib/theme/brand_tokens.dart` (новый) | Spacing/radii/icon/focus/minTarget и выбранные layout constants |
| `lib/theme/brand_assets.dart`, `motion.dart` | Существующие bundled assets/reduced-motion lifecycle |
| `lib/ui/deck_components.dart` (новый) | `DeckSurface`, `DeckSectionHeader`, `DeckStatus`, `DeckNotice`, `DeckKeyValue`, `DeckActions`, `DeckFormSection`, `DeckDialogLayout`; значения/callbacks без I/O/controllers |
| `lib/shell/foundation_shell.dart` | Пять sections, adaptive chrome, стабильный content slot, local readiness/target context |
| `lib/app.dart`, `lib/shell/private_session.dart` | Существующий composition root/bootstrap/settings/profile projections; pure UI scope текущего bootstrap epoch для private dialog retirement через existing `showMotionDialog`, без новых service effects |
| `lib/profiles/`, `lib/servers/`, `lib/software/`, `lib/automation/`, `lib/settings/` | Текущие owners UI-сценариев, controllers, subscriptions, drafts и disposal |
| `lib/automation/automation_presentation.dart` | Safe vocabulary/current phase и bounded1 retained write outcome отдельно от read error, token/context fences; deadline и existing protocol metadata/body validators; route-owned profile и generic JSON submission/recovery state. Generic flow различает read/durable callbacks и собственный retained request; draft остаётся в прежнем controller. Borrowed callbacks сохраняют payload/revision/authority у owners; helper сам не начинает commands/reads/timers |
| `test/support/design_scenarios.dart` (новый) | Synthetic bindings35IDs→owner/state/FR/AC; не runtime asset |
| `test/support/design_state_matrix.dart`, `design_{foundation,server,automation}_state_cases.dart`, `test/widget/design_state_test.dart` | Typed applicability35×12:253 planned cases и167 source-backed N/A; реальные production component/local-owner journeys. Registry не содержит выдуманных passed results; фактические enclosing exits и scope записываются отдельно |
| `test/widget/design_privacy_test.dart`, `test/support/design_state_capture.dart` | Actual FoundationApp/private epoch compositions и opt-in PNG тех же утверждённых checkpoints. Ordinary runs ничего не пишут; capture не заменяет assertions, независимую visual review или native authority |
| `test/support/design_privacy_state_cases.dart`, `design_privacy_bodies.dart` | Общий actual-root privacy runner и реальные production bodies с synthetic DTOs для32IDs/дополнительных modal variants. Один существующий root ProfileController, точные lifecycle counters; fixtures не создают native authority/вторую root model |
| `test/widget/design_adoption_test.dart`, `design_graph_test.dart` (новые) | Bounded adoption/layout/status/graph regression matrix |
| `test/theme/brand_theme_test.dart`, текущие shell/form/accessibility tests | Exact roles/assets, focus/target/readiness/draft регрессии |

Допустимо извлекать presentation sections из больших panels внутри этих families; переносить lifecycle в общий widget не требуется. Документы пакета: spec/plan/research/data-model/quickstart/contracts; Tasks и evidence создаются следующим workflow.

## Technical Design

**Visual roles**: exact colors без seed, radii8/12/16, spacing4/8/12/16/24/32/48, icon20, focus2/gap2; интерактивная область≥44×44 независимо от visual control36. Noto page24/32/600, body14/20/400, table/log13/20/400, button/table-header13/20/600, caption12/16/400. Состояния не заменяются opacity; error/focus/selection сохраняются одновременно. Полный logo≥140width, mark≥24.

**Adaptive shell**: phone≤520 — растущий bottom Wrap;521–1060 — rail72;>1060 — sidebar210. Content padding16/24, topbar56 с compact body14/20; page title24/32 и длинный target context находятся в растущем content. P02–P04 закрепляют exact boundaries, phone measurement/keyboard и focus. У shell нет собственного SSH факта: без real connection projection показывает только profile metadata/local readiness, без literal «Не подключён» как производного от выбора профиля.

**State ownership**: breakpoint/theme меняют chrome вокруг стабильного content slot; идентичность feature State/controller/TextEditingController сохраняется, новых reads/connect нет. Нет blanket `IndexedStack` с приватными скрытыми экранами. При ready loss private subtree/target/secret draft/consent очищаются или удаляются действующим lifecycle; поздние ответы не возвращают их. Сохранённые jobs/store не удаляются. Уход из UI не означает physical job cancel; существующая очистка интереса/подписок остаётся у owner.

**Existing capabilities**: global Logs/Jobs объясняют, что общий список пока недоступен, а существующий журнал/задания открываются в контексте сервера при действующих доступе/доверии и нужных условиях. Действие «К серверам» переключает только local section, без connection/read/approval. Blanket «Выполнение заданий пока недоступно» не сохраняется, поскольку nested AutomationPanel уже предоставляет jobs. Нет новых агрегации, fleet search/сводок, log pause/advanced filters, inventory, guided-save-and-connect или backend функций. Неактивный handler не изображается рабочей кнопкой. JSON/IDs раскрываются как selectable details; обязательные target/effects/scope/deadline читаются обычным языком.

**Readable targets**: существующие ProfileList/SoftwarePanel передают authorized ProfileView через presentation props, без нового чтения. Server trust/executor и AutomationServerTargets показывают name/address:port для exact ID, включая каждую grant target; automation profile name сопоставляется с фактическим profileId/workspaceId. Plan target учитывает существующие serverRevision/connectionRevision/accessRevision/trustRevision, где accessRevision соответствует credential revision, без изменения wire. Exact version/digest остаются у immutable plan. Unresolved/mismatched context объясняется, чужой selected profile не подставляется; captured consent не retarget и не восстанавливается после утраты/смены контекста. Component/owner safeguards описаныP09.

**History**: `MetricsHistory` получает существующую history≤120 и parent metrics quality/source/time как constructor projection, без изменения DTO. Актуальные CPU=accent/solid/circle, RAM=chart2/dash6-4/square, disk=chart3/dot2-4/triangle; parent stale меняет все curve/legend strokes на dash6-4, сохраняя series symbols/names/roles. По FR-004-LOCAL-02/03 общий блок300px на1100 и270px на800 содержит три plot25px одной строкой, без отдельных рамок/больших процентов; actions снизу слева, graphs справа с общей нижней линией, errors выше. При тесноте actions переносятся перед graphs; phone сохраняет graphs перед connection/navigation actions. Подписи растут, plot остаётся25px. Text samples/UTC/% и gaps доступны уже003.1; no interpolation/fake zero, gap>15000ms/time reversal разрывают path. P08 определяет edge cases.

## Bounded Adoption: все35 origins

Каждая группа покрывается theme/shared components и существующим owner; full IDs сверяются со stable `screens.json`. A01–A12 — ключи traceability, не task completion. Tasks добавят реальный task ID и evidence каждого применимого state/frame/theme/scale; not-applicable требует причины поP12.

| Group / screen IDs | Owner и конкретная композиция | Проверка |
| --- | --- | --- |
| A01:01-startup,02-service-unavailable,03-storage-blocked | `shell/readiness_view.dart`, `error_view.dart`: state surface/symbol/reason/retry | Readiness/retry/late reply; P05/P06/P10 |
| A02:04-empty-workspace,05-server-list | `profiles/profile_list.dart`: welcome/action toolbar/profile cards/metadata | Empty/maxnames/tags/phone no horizontal scroll; P03/P07 |
| A03:06-server-overview | `servers/server_panel.dart`, `metrics_history.dart`: connection/system/metrics/history sections | Real quality/time/values/gaps; P05/P08 |
| A04:07-profile-create,08-profile-edit,09-profile-delete,12-credential-input | `profile_form.dart`, `profile_delete.dart`, `credential_input.dart`: form/dialog groups/consequences | Validation/draft/keyboard/picker/privacy; P04/P09/P10 |
| A05:10-host-trust,40-executor-binding | `servers/server_panel.dart`: target/fingerprint/executor confirmations | Cancel/expiry/revoke/no auto trust; P09/P10 |
| A06:13-mutation-conflict,31-recent-operations | `mutation_status.dart`, `recovery_view.dart`: notice/actions/receipt cards/details | Unknown/exact retry/conflict; receipts≤20; P06/P09 |
| A07:16-install-catalog,17-recipe-detail,18-install-preflight,19-plan-approval,94-plan-invalidated | `software_panel.dart`, `automation_panel.dart`: selector/recipe cards/plan/reasons | Explicit connect, exact recipe/plan/deadline/stale; P05/P09/P11 |
| A08:22-server-logs,23-log-record | `server_panel.dart`: current filter/records/full-message dialog/quality | UTC/empty/gaps/cursor/long text; P05/P07 |
| A09:27-job-list,28-job-detail,29-job-unknown,30-job-cancel | `automation_panel.dart`: current jobs/events/postchecks/action groups | Unknown/safe cancel vs stop waiting/dropped; P06/P09 |
| A10:32-automation-profiles,33-profile-authoring,34-profile-revisions,35-plan-parameters,39-delegations | `automation_panel.dart`: profile/revision/parameter/delegation sections/editors | Immutable revision/digest, validation/scope/deadline; P09/P11 |
| A11:36-ai-grants,37-ai-grant-form,38-mcp-client-config | `automation_panel.dart`: grants form/config/details | Default deny, scope/target/expiry/revoke, secret-free fixture; P09/P10/P11 |
| A12:84-settings,85-settings-form | `settings_view.dart`, `settings_form.dart`: current values/RAM draft | Theme/reduced motion/selected profile/no connect; P04/P09 |

Все63concept IDs сохраняют `source` owners stable registry и статус concept. Проверяется количество/уникальность/ссылки всех98; не нужно дублировать63 routes или product requirements в003. Поведение концептов принимается по их собственным пакетам002/004–020;11/93/97 и другие cross-cutting states продолжают ссылаться на указанных registry owners.

## Stages and Requirement Traceability

| FR | Решения/контракты | Gate |
| --- | --- | --- |
| FR-125 | R04–R09; P01–P08 | 003.1: все A01–A12 с двумя темами, baseline keyboard/narrow composition и graph text |
| FR-126 | P04/P09/P11 | 003.2: language/consequences/errors/details |
| LOCAL-01/02/03 | P01/P02/P03/P05/P06 | 003.1:5sections, roles/contrast/focus, bundled fonts/logo/OFL |
| LOCAL-04/05 | P02–P04/P07/P10 | 003.2:4frames/200%, state identity/no extra effects, targets/no overflow |
| LOCAL-06/07 | P04/P06/P09 | С первого затронутого widget;003.3 полная validation/pending/trust/storage/unknown matrix |
| LOCAL-08 | P01–P03 | 003.1:exact tokens/geometry/frozen reference |
| LOCAL-09/10 | P11/P12 и A01–A12 | 003.1:98/35/63 mapping/task bindings; actual results отдельно |
| LOCAL-11 | P01–P04/P07 | 003.2:200%/keyboard/focus/names/reduced motion; baseline действует003.1 |
| LOCAL-12 | P08 | Text/patterns уже003.1 поFR-125;003.2 full keyboard/touch/gap/frame matrix |
| LOCAL-13/14 | P05/P06/P08/P10/P11 | С первого изменения;003.3 local/remote/quality/privacy/late replies |

003.1 не принимается только по theme unit tests: применение A01–A12 и доступный current graph обязательны.003.2 завершает adaptive/accessibility matrix.003.3 завершает matrix состояний/защиты без временных обходов в ранних этапах. Каждый этап — отдельный reviewable increment/MR либо согласованная меньшая часть; merge всех трёх одним MR не планируется.

## Validation and Completion Gates

Команды/проверяемые outcomes описаны в quickstart. После Flutter increment обязательны format/analyze/test, затем fresh independent review/fix loop поAGENTS.md. После package changes обязательны lychee и review полного пакета после Tasks. Screenshot comparison использует synthetic values/bundled fonts/fixed frame/theme/scale/reduced motion; сравниваются композиция/роли/spacing, а не адреса/метрики демо.

Baseline, сообщённый root25.10.2026 до UI-изменений: format611files exit0; Flutter tests253/253 exit0; analyze завершился с13issues в несвязанном untracked unit tool. Это не чистый analyze и не новое evidence003. Scope/исправление анализатора и повтор обязательных checks фиксируются отдельно. Исторический HTML render не заменяет Flutter/runtime приёмку. Native bootstrap smoke проверяет composition/readiness, не все remote/security matrices.

Preflight fix поR11: root dev dependency `analyzer:13.3.0`, pinned `flutter pub get --offline` и root lock; helper source не меняется и не исключается из analysis. После resolution повторяются root analyze и existing explicit-context helper smoke из quickstart. Это подготовительная задача после Tasks/review, не изменение production runtime.

## Complexity Tracking

Новых сервисов и исключений из конституции нет. Дополнительная сложность — presentation components и custom phone Wrap для полных подписей при200%; lifecycle/authorization остаются у прежних owners. Существующий dirty worktree сохраняется, соседние изменения не откатываются ради чистого diff.


## T102 — matching log target до открытия

P07 использует readonly presentation value ServerLogRecordContext.capture в lib/servers/server_sections.dart. Factory получает existing authorized ProfileView и тот же logs result; сверяет serverId/identity.profileId и connection/credential/trust revisions, копирует source/observedAt и включает profile metadata только при совпадении. Missing/malformed/mismatched identity даёт честный unresolved context с ID исходного result и next step, без current endpoint. ServerPanel захватывает projection совместно с Section records; ServerLogRecordDialog получает её вместо независимых необусловленных profile/source/time props. Все production/test callers обновляются; состояние/service owners/Local API/cache/deps не меняются. Metadata-only update при тех же connection identities остаётся допустим. Regression проверяет endpoint change ДО открытия, все identity оси, unknown metadata, последующий matching result и прежний after-open snapshot/P10/F16. Fresh mandatory/native/capture/visual/T041 обязательны.

## T108 — Windows fixture timing, cleanup и безопасная диагностика

Реальные PR40372935619 attempts1/2 на A933 дали разные harness failures: весь JIT subprocess pipe_disconnected_test не завершился за15s; затем другой test trusted-client-receipts дошёл до удаления собственного temp root и завершился на deleteSync. Safe artifacts не содержат фаз первого subprocess и Win32 errno второго; причинная связь с cold JIT, scanning или конкретной native ошибкой не установлена. Production defect из этих данных не следует. Локальный полный Windows пакет на A933 прошёл127tests; проблемный subprocess занял13168ms, доля startup неизвестна.

Test-only решение T108 сохраняет native assertions и operation deadlines. Pipe fixture компилируется AOT до измеряемого сценария существующим compilePeer с90s budget; group120s покрывает setup, отдельный native behavioral exit watchdog остаётся15s. Его known timeout получает fixed phase из exact child markers: started/connected/disconnected/read-terminated/reuse-cancel-proved. Cleanup helper проверяет absolute/resolved owned temp root сprefix serverdeck-mcp-bundle-, запрещает reparse root, после прежних joins повторяет только delete errors5/32/33/145 с25ms interval до5s; неизвестная ошибка и исчерпанный deadline остаются отказом. Никаких ACL changes или убийства чужих процессов.

Safe schema1 допускает nullable fixed fixturePhase и WIN32_FIXTURE_DELETE numeric evidence лишь для известного fixture/declaration и проверенного current source/hash/line; arbitrary error text, private paths, stdout и stderr не становятся public evidence. Контрольные projections проверяют refusal unknown/spoof/mismatched inputs, native helper tests используют реальные locks. Новая metadata build0.2.0-preview.1+3 связывает source commit/tag/archive с заново собранной локальной установкой; предыдущая+2 сохраняется. Это не runtime feature или новый контракт001/021. Локальные checks/review и exact-revision successful external MCP CI остаются последовательными обязательными gate; production/distribution границы source-only preview прежние.

## T109 — общий CI resource ceiling и явные параметры locald

Old push40372896426 на A933 завершился cancelled: job121748051467 started17:53:55Z, completed19:55:04Z; GitHub annotation прямо сообщает превышение120min. Последний safe artifact12684515482 содержит только started/serverdeck_locald-tests, без completed counters или failure report; это не доказывает отсутствие накопленных ошибок или зависания. Прежние root/protocol/Windows phases завершились по последовательному control flow; full qualification не завершилась.

DiscoveryNamespace.forOwner определяет имя owner mutex через SHA256(SID+default), а не temp LOCALAPPDATA. bootstrap_native_test и discovery_file_test требуют владения этим общим mutex; Tracked packages/serverdeck_locald/dart_test.yaml уже задаёт concurrency:1 и читается при прежнем Push-Location; default test_core не был фактическим значением CI. Параллельная гонка этого прогона не установлена. Native qualification явно сохраняет полный locald с --concurrency=1, сохраняя внутренние конкурентные child/workload assertions. --fail-fast возвращает отказ при первой ошибке; при успешном результате выполняются все прежние tests. Root/protocol/Windows invocation и per-test/operation deadlines не меняются.

Windows job budget становится240min только как bounded outer resource ceiling для cold source/material build, root/package suites, двух configurations и available UI/runtime diagnostics. Это не новый срок native operation, не отключение tests и не обещание достаточности/ETA: actual terminal exact-revision CI остаётся обязательным. ЛокальныеT106serial930pass/1skip58m45s используются лишь как отдельное evidence конфигурации, не как текущая cold qualification. T109 проверяется точным workflow diff, PowerShell AST и isolated execution настоящего package-tests argument block с mock command (никакого native запуска), pinned CLI help, root mandatory checks, links и fresh review. Metadata version+4 позволит связать последующие source/tag/build/install с одним новым commit; +2/+3 сохраняются. Все production/distribution ограничения прежние.

## T110 — подготовка fixture отдельно от неизменного bootstrap поведения

Push40395514770 на2af завершился failure: reporterComplete=true, bootstrap_native_test declaration17, timeout, без sourceFrames/phase. Это первый locald failure после fail-fast, а не новый общий240min cutoff. Старый test4min включал два unbounded Process.run AOT compile, synchronous PowerShell resolver, подготовку bundle/manifest и все сценарии. T106cached native test занял223970ms; timing-only ignored copy на cached provider прошла211s (setup около12.6s, от first run до cleanup198.5s). Эти наблюдения не локализуют фазу холодного CI и не доказывают production startup regression.

Группа compiled bootstrap подготавливает только owned temp root/bundle/local, AOT locald и прежний client, native selection/copies/hash manifest в setUpAll. Будущее поведение получает готовые owned paths; namespace reservation и все шесть запусков/пробы/watchdogs/recovery/refusal checks остаются в прежнем runtime test4min. Per-operation limits, включая startup30s/owner-loss4s/lease expiry и existing cleanup joins, не меняются. Hook framework limit12min не объявляется управляемым group timeout. Два compiler и resolver получают отдельные completion90s и owned-child join10s, bounded64KiB stream capture. Selection использует прежний resolver и inherited qualification environment, без direct env/DLL fallback. Native production, callbacks, схемы, grants, доверие и provider не меняются.

Внешний test timeout не отменяет продолжающийся async body. Поэтому не добавляются blanket body Future.timeout и unconditional tearDownAll deletion. Existing body finally сохраняет физические joins peers/observer/owner и удаляет fixture лишь после подтверждённого успеха. Preparation failure не запускает owner и сохраняет evidence; завершаются только собственные preparation subprocess, не чужие services.

Fixed print markers проходят в machine JSONL, в отличие от прежнего stdout.writeln. Whitelist: prepare-start,compile-owner,compile-client,select-native,manifest,prepared,behavior-start,namespace-check,run-0…run-5,refusal-checks,cleanup,complete. Projector хранит не более32 phase IDs, связывает phase с exact known bootstrap body/hook testID/file/current source hashes/declaration и точным marker/type, failclosed на нарушениях. Hook null declaration не выдумывается; допустимость требует проверенного current source/hook/producer. Public proof содержит только fixed fixtureCase/nullable fixturePhase, без message/stdout/paths/PIDs/времён. Подготовка не заменяет runtime oracle; новый current-source coldCI обязателен.

T110 проверяется real targeted bootstrap/full serial locald, existing root checks, controlled reporter positives/negatives/privacy, links и independent review. Metadata+5 и последующие commit/build/install/tag/source receipts сохраняют единую revision; предыдущие локальные установки/data и unknown причины прошлых CI сохраняются. Public assets по-прежнему только source ZIP/SHA; full001/021/005 и public native distribution вне принятого scope.

## T111 — fixed trust-probe case projection

Другой current-source CI4 PR40395530655 прошёл bootstrap и позднее failed на trust_probes_native_test declaration85/frame117: parent child.exitCode55s watchdog, outer test80s. Safeartifact12691076818 не содержит mode или actor phase, поэтому конкретный сценарий/причина не установлены. Это отдельный отказ, не подтверждение причины bootstrap failure. Native код/SSH операционные сроки не меняются на основании неизвестного case.

Safe parser добавляет только точный36-case vocabulary из существующего trust_probes_native_test и fixtureCase=trust-probe-<mode> при проверенных locald phase/current source hash/file/declaration/exact test name/type. Frame117 не обязателен для распознавания других действительных ошибок того же case; существующие поля error classification остаются. Unknown/foreign/spoof/mismatched cases остаются без case, arbitrary data не публикуются. Controlled regression охватывает36positive cases и negative/hash/line/type/privacy variants. Код actor/fixtures/production, 55/80s и provider не меняются.

Это diagnostic-only implementation; sufficiency как исправления реального probe timeout не заявляется. Source5 coldCI обязан завершиться успешно; если таймаут повторится, fixed case даст основание дальнейшему точечному исследованию. T106all36cachedGREEN и T110localfullsuite не подменяют current sourcebuilt qualification. T111 проходит full diagnostics/rootapplicablechecks/links/fresh review с T110; post-commit receipts и публичные source-only границы прежние.


## T112: первичная ошибка gateway test и body-owned cleanup

Actual CI5 push40413693379 failed на gateway-quota; exported frames указывают stderr-empty assertion close119 и finally94. Это не delete failure: delete121 ещё не достигнут. Private actor output не включён в safe artifact; реальные exit/cause неизвестны. Services.start16 не доказывает delivery ACK; production cancelInterest уже ждёт _ack в5s, поэтому sleeps, serial cancellation, retries или смена quota oracle не обоснованы. Возможная worker-slot contention остаётся гипотезой.

Test-only support helper получает callbacks body/cleanup и всегда ждёт body до запуска прежнего cleanup. Успех требует обоих successes. При одной ошибке сохраняет исходные object/stack; при двух throws test-only aggregate с primary/secondary object и stack, whose toString начинается с исходной primary.toString и дописывает secondary private evidence; throwing stack остаётся primary. Никаких background cleanup/tasks, framework addTearDown, cancellation или новых deadlines. Gateway native body/oracles/owned Fixture.close остаются прежними; ответственность helper ограничена failure propagation. Meaningful unit criteria: все четыре исхода, identity/stack сохранены, cleanup ровно один раз и только после body settlement, caller ждёт cleanup.

Public projection сохраняет schema1/старые поля/total bounds и не выводит aggregate private text. Numeric gateway exit разрешён только по current source/hash/known full test case/declaration и проверенной форме прежнего zero-exit assertion плюс helper; диапазон прежнего Windows signed/unsigned32 exit, ненулевое значение. sourceFrames уже принимают только актуальные hash/line known sources и остаются ограниченными3. Controlled tests обязаны отвергать foreign source/case/phase, изменённые source/helper, неправильные declarations и произвольные сообщения. Новый exact successful CI остаётся внешним gate: диагностическое исправление не доказывает устранение underlying quota failure. Product/runtime/actor/provider/gateway protocol не меняются; metadata+6 и private installation/source-only boundaries прежние.


## T113: capacity setup без лишнего async FFI и safe phase evidence

CI5PR40413702225 actual case success-write-capacity/timeout55s известен, фаза неизвестна. Prefill в trust_write_scenarios.dart171–207 выполняет до20000 независимых durable transactions с alternate/original fixed row1 под pinned reader; они нужны для MVCC pressure production64MiB. Это setup до создания confirm request (5s budget), но он старит real owner60s lease. Увеличение timeout либо объединение toggles в одну transaction не обосновано. Read-only diagnosis подтвердил поддержанные одинаково durable async/sync Isar APIs; отдельные synchronous commits сокращают async FFI overhead, их performance effect должен быть измерен. Large padding/extra rows/reduced map не используются.

Test-only capacity_fixture.dart не импортирует Isar: принимает synchronous commit callback и существующий native-capacity classifier, выполняет не более20000 отдельных вызовов, возвращает full только при real classified capacity error; остальные ошибки перебрасывает с исходным stack. Actor callback содержит ровно один writeTxnSync и прежние два putSync с явным fixedID1. После каждых16успешных commits helper делает один zero-delay event-queue yield (не microtask-only), поддерживая timers/owner responsiveness. Reader остаётся async pinned до прежнего finally/release. Существующие confirmation/rollback/same challenge/replay/revoke assertions не заменяются; raw snapshot всех16collections/IDs до prefill и после отказа дополнительно проверяет отсутствие durable effect. Unit tests доказывают limit/one callback per commit/early native failure/noncapacity propagation/event-queue fairness; реальные DB/owner oracles проверяются native probe.

Фазы только для capacity mode: capacity-start, capacity-reader-ready, capacity-prefill-0/1000/.../20000, capacity-full, capacity-confirm-refused, capacity-reader-released, capacity-recovery-confirm, capacity-recovered, capacity-replay-verified, capacity-revoke-verified, capacity-complete. Source helper пишет последний whitelisted token+newline в owned trust-capacity-fixture-phase (<=64ASCII bytes). Observer failures не подменяют actor outcome: missing/invalid/oversize/partial/unreadable дают unknown. На55s timeout parent читает значение перед существующим awaited cleanup и бросает TimeoutException с фиксированным TRUST_CAPACITY_FIXTURE_TIMEOUT:<token> и Duration55s; остальные35modes сохраняют прежний timeout. Private profiling capsule может содержать bounded counters/elapsed, но публичная projection получает лишь fixed phase/bucket, без raw contents/paths/elapsed/messages. Новых schema fields не требуется.

Projection проверяет exact locald phase/case/URL/name/declaration/current source hashes helper+parent+actor writer, checked55s producer и фиксированную timeout shape; Только в этом полностью проверенном capacity-контексте exact fixed fallback `unknown` даёт fixturePhase=unknown. Любые другие нераспознанные tokens, stale/foreign/spoof дают null; raw текст не переносится. Старые T108/T110/T111/T112 cases и limits остаются. До/после измерения выполняются последовательно после текущего cached full suite через новый assembled unqualified artifact/current strict CandidateScope; он не активируется и не меняет normal bundles. Старый H candidate с CRLF recipe receipt не переписывается. Поддержанные build/collect/assemble commands закреплены в .local/release candidate audit; archives/source/vendor проверяются штатными tools. Context snapshot/source/artifact остаются неизменными внутри каждого Action. Такое измерение не заменяет full qualification/compatibility/distribution; public source-only и private cached-provider app boundaries прежние.

T113 local gate: helper unit RED/GREEN, same-artifact before/after capacity actor и cached36probe cases, root mandatory Flutter checks, locald analyze, controlled diagnostics, strict links и fresh independent review. Полный cached T112 suite исполняется на прежнем capacity actor до T113 и остаётся отдельным evidence; неизменённые остальные native paths не объявляются повторно выполненными. Новый exact-revision full coldCI остаётся обязательным release gate. Metadata+6 ещё не имеет commit/build/install/tag/publication; T112/T113 закрываются только после их local checks/review.

## T114 — завершение trusted-client fixture и сохранение первого отказа

### Основание и граница

PR CI6 run40433707316 на29c05212b462b3af33c284a19c7995d4652f2500 завершился failure: Windows121957250368, `trusted-client-oversize`, exit1, declaration65/frame90, reporterComplete=true, nativeErrors=[], fixturePhase/safeCode=null. Push40433701962 на момент начала T114 ещё выполнялся, затем также failed: locald phase, trusted_auth_native_test.dart declaration127/frame155 finally и shared close119 stderr-empty, reporterComplete=true; точный case/первичная причина неизвестны. Второй failure требует отдельного follow-up и не выдаётся за тот же oversize дефект. Четыре Linux/executor jobs завершены успешно. Десять неизменённых локальных oversize probes завершились exit0; это не воспроизведение CI.

Разбор исходников установил отдельную fixture race: корректный client после terminal UNAUTHORIZED на oversized frame может дождаться api.done, проверить closed/pending0, напечатать CLIENT_PASS, выполнить cleanup и завершить процесс раньше continuation server peer.write. Retained process identity проверяется после записи и требует STILL_ACTIVE; поэтому server ещё может получить UNAUTHORIZED. Это обоснование completion barrier, а не доказанный механизм конкретного CI отказа. Проверка identity после write, физическое api.close после oracle, native trust/epoch/security и строгий await sender write сохраняются. Observe hook, который останавливает только explicit peerVerify, не выдаётся за остановку I/O postverify или воспроизведение старого CI.

Та же source-level race присутствует в cleanup2/cleanup3: после server await последнего authenticatedReply write клиент проверяет close/done/close expected failure, закрывает actual worker и может выйти до server postverify. Поэтому barrier обязателен во всех37 modes, включая эти две версии; исключение касается только phase/code projection, не completion. Формат2/3 bootstrap, FailureAfterClose и все проверки identity/terminal/transport/closed/pending0 сохраняются.

T114 — только Windows test support, его unit/native adapters и существующая safe projection. [Operational client](../021-mcp-control/contracts/operational-client.md), [channel](../021-mcp-control/contracts/operational-channel.md) и [native artifact/privacy gate](../001-service-foundation/contracts/native-artifact.md) не меняются. Production/native/DLL/provider, auth/credentials, wire/schema/версии API, ресурсы RPC и backend остаются прежними. Никаких retries, swallowing write errors, sleeps для успешности, ослабления oracles или увеличения deadlines.

### Компоненты и completion contract

| Компонент | Ответственность |
| --- | --- |
| `packages/serverdeck_windows/test/support/trusted_client_completion.dart` | Test-only streaming capture, READY/ACK/exit completion и закрытие owned stdin; без импорта locald helper или product transport |
| `packages/serverdeck_windows/test/support/trusted_client_fixture.dart` | Generic test-only `runOwnedFixtureLifecycle`, first failure phase/code, bounded owned diagnostic writer/reader и fixed reason marker; lifecycle не зависит от gateway/client API/production и пригоден для других native fixtures |
| `packages/serverdeck_windows/test/trusted_client_completion_test.dart`, `trusted_client_fixture_test.dart` | Pure unit RED/GREEN для соответствующих контрактов, controlled clock/Completer вместо flaky sleeps |
| `packages/serverdeck_windows/test/support/trusted_client_actor.dart` | Существующий actual client/server adapter для35 ordinary modes и прежний ранний main dispatch cleanup2/cleanup3 |
| `packages/serverdeck_windows/test/support/client_cleanup_fixture.dart` | Тот же barrier для cleanup2/cleanup3 после client actual worker.close; server streaming capture16KiB и complete(10s) после строгого последнего write, прежние close-failure oracles |
| `packages/serverdeck_windows/test/trusted_client_native_test.dart` | Прежние37 native cases, lifecycle wrapper вокруг body/await Fixture.close и чтение server record после actual exit до cleanup |
| `tools/qualification-test-diagnostics.ps1`, `tools/test-qualification-test-diagnostics.ps1` | Строго проверенная schema1 projection и controlled regression старых/новых случаев |

После `await client(args)` вернулся, включая успешный client finally, client main пишет ровно ASCII `TRUSTED_CLIENT_READY_TO_EXIT\n`, flush и ожидает ровно ASCII `TRUSTED_CLIENT_EXIT_ACK\n` с последующим EOF. Только эта последовательность разрешает exit0. ACK parser читает не более64 bytes; лишний/не-ASCII byte, неполная строка, EOF до полного ACK или отсутствие завершающего EOF, stream error и исчерпание одного12s монотонного бюджета остаются failure. Не применять trim или разрешение trailing bytes. CLIENT_PASS и все прежние клиентские assertions сохраняются; READY не заменяет CLIENT_PASS и не отправляется при client/body/finally failure.

Сразу после Process.start completion object устанавливает обработчики stdout/stderr/exit и наблюдает ранние ошибки, чтобы они не стали unhandled. Каждый stream имеет прежний предел16KiB. Streaming parser распознаёт exact READY line через произвольную фрагментацию chunks при ещё открытом stdout; substring/prefix/suffix не подходят. Сервер не ждёт EOF/outDone перед ACK. `complete(budget)` — non-async entry point, который кэширует и возвращает один identical Future на child; повторный вызов не перезапускает работу и не продлевает срок.

Первый complete фиксирует один absolute monotonic deadline. В его remaining budget входят READY, server stdin write→flush→close, actual child exit и bounded drain capture. ACK разрешён только после READY и после завершения ожидаемого server protocol/write epilogue; late READY/continuation после terminal failure или deadline не может отправить ACK. Exit event может прийти раньше последних buffered stdout bytes: разрешён лишь drain в том же оставшемся budget, без новых12s. Каждая async boundary повторно проверяет terminal/expired state. Owned stdin close — одна идемпотентная операция, переиспользуемая cleanup.

Четыре прежних9s ожидания actor — bootstrap-timeout, hello-* refusal, bad-proof/single-use и timeout — вызывают complete(9s) в прежнем месте. Общий финальный complete(12s) возвращает тот же future/result, если ранее был9s вызов; только остальные ordinary modes впервые получают12s. cleanup2/cleanup3 сохраняют ранний main dispatch и свою server completion границу10s: общий helper вызывается после awaited authenticatedReply write, READY client отправляет внутри cleanup.run только после успешного finally/actual worker.close. Их оба streams ограничены16KiB; прежние CLIENT_PASS/exit0/empty stderr и все synthetic close failure assertions обязательны. Прежние cleanup child join5s, outer server child35s и native test50s во всех modes не меняются. Повторный join/cleanup не может превратить failure в success; server PASS появляется только после успешного server cleanup.

### Lifecycle и безопасный first failure

Generic `runOwnedFixtureLifecycle` исполняет body, затем awaited cleanup в том же body lifetime; cleanup никогда не запускается до settlement body и всегда ожидается вызывающим кодом. Success требует двух successes. При body-only или cleanup-only failure перебрасываются тот же object и stack. При двух failures typed test-only aggregate хранит обе private причины/stack; его текст начинается с primary.toString, throwing stack остаётся primary, secondary добавляется только в private suffix. Best-effort `onFirstFailure` вызывается перед cleanup при body failure либо при cleanup-only failure; observer failure не меняет outcome и не подменяет исходную ошибку. Такой wrapper используется в ordinary actor server и parent test, без locald helper refactor/import и без framework unconditional teardown. Он не связывает error propagation с trusted-client phases, transport или gateway и допускает повторное использование другим test fixture без production dependencies.

Диагностика server действует только для35 ordinary modes внутри существующего server try после успешного создания worker и fixture containment; ошибки до этой границы не получают выдуманных phase/code. Для cleanup2/cleanup3 добавляется только barrier/capture, их fixturePhase/safeCode остаются null. Внутри ordinary server фиксируются ровно семь phase literals:

| Phase | Граница установки перед операцией |
| --- | --- |
| `prepare` | Оставшаяся существующая подготовка в try: grant files, child spawn/capture и начало accept |
| `bootstrap` | Ожидание accept, native peer verification и существующий bootstrap exchange |
| `rpc-read` | Очередное ordinary RPC read |
| `rpc-write` | Очередной ordinary response write, включая oversize/invalid-json direct peer.write |
| `completion` | Cached READY/ACK/exit/drain и прежние child result assertions |
| `cleanup-child` | Owned stdin close, kill и существующий child join |
| `cleanup-worker` | Существующий worker.close |

Код берётся только из StateError.message при exact membership в восьми существующих PipeWorker._safeCode literals: SERVICE_UNAVAILABLE, UNSAFE_ENDPOINT, IDENTITY_UNAVAILABLE, TIMEOUT, RESOURCE_LIMIT, UNAUTHORIZED, INCOMPATIBLE, PREREQUISITE_UNAVAILABLE. TimeoutException даёт TIMEOUT; любая другая ошибка даёт null. Не вызывать raw toString для классификации и не заменять неизвестный code на SERVICE_UNAVAILABLE. First phase/code фиксируются один раз, secondary cleanup failure их не перезаписывает. Raw exception/stack/aggregate и child output остаются private.

Только server first-failure observer best-effort пишет в собственный fixture root exact basename `trusted-client-server-failure`, формат ровно ASCII `1|<phase>|<code-or->\n`, максимум128 bytes. `-` кодирует null; иной phase/code не записывается. Reader проверяет длину<=128, читает не более129 bytes, повторно проверяет длину/соответствие прочитанному и exact whole-file grammar без trim/CRLF/trailing bytes. Missing/corrupt/oversize/unreadable/изменившийся при чтении файл означает отсутствие diagnostic, без нового исключения или raw fallback. Fixed record не зависит от stderr и сохраняется при существующем65KiB OUTPUT_LIMIT parent capture.

Parent читает record только после actual server child exit, до await Fixture.close. При valid record первая строка reason существующего zero-exit expect — ровно `TRUSTED_CLIENT_FIXTURE_FAILURE:<phase>:<code-or->`, затем прежние private out/err. При отсутствии valid record marker не добавляется и новые public phase/code остаются null. Primary zero-exit assertion не может быть замещён последующим Fixture.close failure благодаря lifecycle wrapper; прежние child PASS и empty stderr assertions сохранены.

### Public schema1 и проверяемая цепочка

Новых public полей/протоколов нет: используются только прежние nullable fixturePhase/safeCode. Projector принимает marker исключительно в serverdeck_windows-tests для exact current `trusted_client_native_test.dart`, suite/URL/declaration/exact full test name одного из существующих35 ordinary literals (37case whitelist минус cleanup2/cleanup3), при current source inventory/hash parent+actor+обоих helpers и проверенном producer zero-exit assertion/reader/lifecycle wrapper. Учитывается только primary error segment, до private aggregate secondary suffix. Marker должен быть единственной marker-строкой и строго первой reason line проверенного Expected0/Actual nonzero assertion, с exact phase/code grammar. Matching raw stderr, повтор, неверный position/shape, malformed/foreign/stale source/helper/producer/case дают null для новых phase/code. Отсутствие record не публикуется как phase unknown. Существующие numeric exit/failureKind, nativeErrors, максимум3 sourceFrames и все T108–T113 privacy/total bounds сохраняются.

| Требование | Решение/контракт | Задача | Проверяемая приёмка |
| --- | --- | --- | --- |
| Constitution VII, truthful fixture outcome; strict native retained identity | Process completion barrier после client finally, без изменения api.close/peer.write | T114 completion helper и actor | Meaningful RED/GREEN; controlled liveness удерживает client process через sender continuation, все прежние terminal/pending/write oracles |
| Constitution III/IV, failure не маскируется cleanup | Same-lifetime lifecycle и first-only safe record | T114 fixture helper/actor/parent | Single error identity+stack, both private aggregate/primary stack, observer refusal, cleanup order/await, seven phases/eight codes |
| Native-artifact schema1 privacy и bounded evidence | 128ASCII record и exact sole-first reason producer | T114 PowerShell projector/tests | Все valid phases/codes и35cases; malformed/EOF/129byte/foreign/stale/spoof/private markers дают refusal/null, старые diagnostics проходят |
| Constitution VII/VIII, source-only exact revision | Локальные checks/reviews отдельно от coldCI/build/install/release | T114 и прежний внешний release gate | Ни local probes, ни review не заменяют actual terminal successful full CI точного нового commit |

Unit RED/GREEN покрывают fragmented READY/ACK, exact line/EOF/limits, ACK после client finally и server epilogue, identical future и9→12 без restart, один absolute budget всех стадий, early exit/buffered output, failure/timeout cleanup и запрет late ACK. Controlled clock/Completer проверяют сроки без flaky sleeps. Native focused checks дополнительно проверяют реальные stdin flush/EOF и early child exit. Controlled liveness regression доказывает удержание process через sender continuation; если использован hook только explicit peerVerify, результат не объявляется I/O-postverify reproduction. После изменения выполняются все37 trusted-client cases,10 oversize repetitions и полный Windows native package serial, Windows analyze; root exact format/analyze/fullFluttertests; полный controlled PowerShell diagnostics T108–T114, strict `lychee "specs/**/*.md"`, diff check и fresh independent code/spec review, затем recording review. Реальные servers не используются.

Metadata `0.2.0-preview.1+7` готовит следующий exact commit. Сейчас фактически проверена private unsigned+6 с cached f1 provider; пять предыдущих установок и workspace сохраняются. Sourcebuilt c45 candidate остаётся unqualified/unactivated. Для+7 отдельно нужны новые commit/полный successful exact-revision CI/build/install/source ZIP/SHA/tag/merge/publication receipts. Публичных assets по-прежнему только два: source ZIP и SHA256SUMS.txt; binary/signing/native distribution и full001/021/005 не приняты. Предыдущие RED, оба CI6 run records и completed T001–T113 не переписываются. До independent readiness review пакет не передаётся на implementation; T114 остаётся unchecked до фактических implementation/checks/clean review.

### T114: уточнение bounded child cleanup перед implementation review

Если cached stdin.close остаётся pending после failure/timeout completion, ожидание close перед kill может не дойти до прежнего5s child join. Поэтому child cleanup использует один общий absolute monotonic budget5s: инициирует и сразу наблюдает cached stdin.close, затем prompt kill только своего child до await close; после этого ждёт тот же close и actual exitCode в оставшемся общем5s budget. Сохраняется initiation order close→kill→join; join предпринимается и при failure/pending close. Отдельные5s для каждой стадии, ожидание close до kill и новый deadline не вводятся. При успешном body actual child exit уже доказан completion; оставаться активным на этой границе child может только после failed body. Прежний broad catch для owned stdin.close сохраняется буквально: допустима любая IOException, без нового errno enum/filter109/232/233. StateError и другие non-IO ошибки не подавляются. Pending-close timeout остаётся failure даже если actual child exit/join уже подтверждён. Cached close не запускается заново, late continuation после terminal/timeout не разрешает ACK.

Worker.close всегда выполняется в finally после попытки child cleanup, в том числе при pending-close timeout или join failure. Общий runOwnedFixtureLifecycle сохраняет primary failure и private secondary cleanup evidence по согласованному контракту. Это ограничивает старый unbounded close внутри прежнего5s child-cleanup срока, не меняя operation/outer/test deadlines, retained identity, sender write или успешные oracles. Pure unit checks обязаны показать pending close/timeout→prompt owned kill→attempted join в одном5s budget/no late ACK и cleanup-only/dual-error preservation; actual native execution остаётся последующим отдельным gate. Это одно уточнение T114 в рамках текущего implementation, без новой задачи или изменения старых checklist lines; fresh review T115 также проверяет эту узкую delta.

## T115 — trusted-auth: первичная ошибка и безопасный case/exit

### Фактическое основание и scope

Push CI6 `40433701962`, Windows job `121957233017`, завершился failure в02:38UTC на29c05212b462b3af33c284a19c7995d4652f2500. Сохранённый `.local/release/ci-failure-40433701962/safe-proof/native-qualification-1d48e8ed0599428a97e1257b97d994ba/safe-test-failure-serverdeck_locald-tests.json` содержит phase=serverdeck_locald-tests, trusted_auth_native_test declaration127/source155 finally и mcp_build_bundle_test source119 stderr-empty assertion, reporterComplete=true/nativeErrors=[], fixtureCase/fixtureExitCode/failureKind/fixturePhase/safeCode=null. Удаление121 ещё не достигнуто. Proof не различает body failure, замещённый cleanup, и cleanup-only failure. Actual actor outcome, scenario и root cause остаются неизвестны; это отдельный от trusted-client-oversize PR CI6 failure. Оба Windows CI6 failed, четыре Linux/executor jobs successful; full CI success не заявляется.

В существующем parent25-case loop finally может замещать exit/PASS failure; scenario actor имеет такую же границу registry.stop/reverse Pair.close, а Pair.start catch — failed-start cleanup. T115 сохраняет их private причины, расширяет только безопасное распознавание case/primary exit и проверяет прежние native oracles. [Handshake](../021-mcp-control/contracts/handshake.md), [retained identity/bundle](../021-mcp-control/contracts/bundle.md), [Local API](../001-service-foundation/contracts/local-api.md) и [native artifact privacy/release gate](../001-service-foundation/contracts/native-artifact.md) не меняются. Новых runtime dependencies, schema/API versions, миграций, полномочий или credentials нет. Production/native/provider/SSH/server changes отсутствуют; реальные servers для проверок не используются.

### Компоненты и test-only interface

| Компонент | Ответственность T115 |
| --- | --- |
| `packages/serverdeck_windows/test/support/trusted_client_fixture.dart` | Существующий по T114 generic lifecycle; его интерфейс и error contract ниже переиспользуются без client/transport coupling |
| `packages/serverdeck_locald/test/mcp/trusted_auth_native_test.dart` | Same-lifetime wrapper25 ordinary bodies и отдельного orphan body; прежние assertions и cleanup, без новых phase records |
| `packages/serverdeck_locald/test/support/trusted_auth_actor.dart` | Wrapper scenario body/finally и реальный startup adapter в Pair.start; private nonclient StateError stack |
| `packages/serverdeck_locald/test/support/trusted_auth_fixture.dart` | Pure test-only `runTrustedAuthStartup<T>` с typed result holder/success flag поверх generic lifecycle; без native/production imports |
| `packages/serverdeck_locald/test/trusted_auth_fixture_test.dart` | Meaningful unit regressions actual startup adapter и reused lifecycle, включая nullable result success |
| `tools/qualification-test-diagnostics.ps1`, `tools/test-qualification-test-diagnostics.ps1` | Current-source schema1 case/primary-exit projection и все старые/новые controlled tests |

Общий test-only API T114/T115 фиксирован: `Future<void> runOwnedFixtureLifecycle({required Future<void> Function() body, required Future<void> Function() cleanup, void Function(Object, StackTrace)? onFirstFailure})`. Locald tests импортируют Windows test helper напрямую; production libraries его не импортируют. Gateway helper и gateway tests не рефакторятся. Shared helper frozen после координации с владельцем T114; изменение его bytes требует повторных применимых unit checks и обновления current-source guards обоих scopes.

Body полностью settles до единственного await прежнего cleanup, в том же lifetime. Успех требует двух success; нет фонового teardown или превращения ошибки в pass. При single body-only/cleanup-only failure перебрасываются исходные object и stack без замены. При двух failures `OwnedFixtureFailure` хранит ровно `Object primary`, `StackTrace primaryStack`, `Object secondary`, `StackTrace secondaryStack`; toString равен `'$primary\nOWNED_FIXTURE_CLEANUP_FAILURE:\n$secondary\n$secondaryStack'`. Фиксированный разделитель — `\nOWNED_FIXTURE_CLEANUP_FAILURE:\n`, после colon newline. Aggregate перебрасывается через Error.throwWithStackTrace с primaryStack. First observer T114 best-effort не меняет outcome; T115 не добавляет authoritative actor record и не использует observer для публичной классификации. Это один shared контракт T114, locald его импортирует и не создаёт fork helper.

Адаптер `Future<T> runTrustedAuthStartup<T>({required Future<T> Function() start, required Future<void> Function() cleanup})` использует именно общий lifecycle и реальный результат start. Отдельный success flag устанавливается только после успешного await start и сохранения typed result; null допустим при nullable T и также означает success. Cleanup callback выполняет реальные failed-start действия только если start не завершился успешно. Pair.start вызывает этот adapter вокруг прежнего try body: Process.start, stream captures, await accepting, прежний optional native publication gate и создание Pair. Failed-start cleanup остаётся child?.kill→при child await exitCode→await server.close, с прежним fail-fast. Успешно созданный/возвращённый Pair остаётся открытым и закрывается прежним сценарием. Исходные server creation и начало accept до старого try не переносятся; новая общая resource policy для ранних failures не вводится.

В parent wrapper заменяет только существующий try/finally. Для25cases сохраняются child exit70s, expected0, private output/error reason, exact PASS и outer90s. Отдельный hard-killed owner/orphan test также сохраняет body failure; его cleanup по-прежнему await lines?.cancel, затем await Fixture.close, с прежним fail-fast. Hard-kill/retained process identity/child-exited polling и все его существующие сроки остаются. Orphan не входит в новый case/exit whitelist.

В actor wrapper охватывает прежний scenario try body и прежний cleanup: registry.stop(), затем последовательный await Pair.close по pairs.reversed. Не менять порядок, не продолжать после первого cleanup failure и не повторять cleanup. Все nested handshake/read/write/finishClient/Pair.close bounds и resource/role/session/epoch oracles сохраняются. Main для nonclient StateError печатает private error и stack, как общий catch; exitCode остаётся1. Client StateError по-прежнему печатает `ERROR:<message>` в stdout и сохраняет прежний default exit0; client worker finally, wire protocol и клиентские assertions не меняются.

Граница результата: T115 сохраняет ошибки parent/scenario/failed-start на этих трёх уровнях, включая orphan parent. Он не обещает устранить masking client worker finally или изменить Pair.close first-failure policy; вторичные ошибки внутри прежнего fail-fast cleanup могут остаться ненаблюдаемыми. Completion barrier T114 здесь не добавляется: отдельный actor уже удерживает client через существующий stdin lifecycle.

### Schema1: точный case и только primary zero-exit

Ровно25 разрешённых scenario literals из существующего parent loop100–126: `roles`, `native-gate`, `stale-close`, `proofs`, `quota`, `expiry`, `close`, `snapshot`, `deadline`, `client`, `framing`, `tamper`, `owner-context`, `owner-context-detach`, `owner-context-expiry`, `owner-context-budget`, `owner-context-native`, `owner-context-stop`, `owner-context-physical`, `owner-connection`, `owner-connection-budget`, `owner-connection-detach`, `owner-connection-native`, `owner-connection-stop`, `owner-connection-physical`. Exact full name — `actual format3 API1.1 bootstrap and session <scenario>`; fixed exported fixtureCase — `trusted-auth-<scenario>`. Unknown names, child modes и orphan не добавляются в этот vocabulary.

Проектор допускает эту новую classification только в phase `serverdeck_locald-tests`, для точного suite URL/file текущего parent, valid current test declaration и exact full name. Current source inventory/hash обязателен для parent, actor, Windows generic helper и locald startup adapter; проверяются actual lifecycle wrapper/cleanup, whitelist и checked zero-exit producer с70s, а не произвольная строка Expected/Actual. Неверные suite/URL/file/hash/declaration/name/sourceLine и stale/изменённые helper/actor/producer дают null новой classification/exit; сохраняются независимо допустимые старые поля. Source line numbers вычисляются из фактических проверенных sources, старые127/155 не назначаются новому коду.

`fixtureExitCode` и `failureKind=fixture-exit` разрешены лишь для checked primary Expected0/ActualN assertion этого producer: целое ненулевое N в закрытом диапазоне `-2147483648..4294967295`, без дробей/лишнего текста/overflow. Первичный segment заканчивается до fixed `\nOWNED_FIXTURE_CLEANUP_FAILURE:\n` suffix; secondary error/stack никогда не становится источником exit или primary sourceFrames. PASS assertion, cleanup-only failure, orphan и Expected/Actual внутри raw stdout/stderr/private stack либо aggregate secondary не производят exit. FixtureCase может сохраняться при другом валидном failure того же ordinary case, но exit остаётся null без проверенного producer/primary assertion. Hash/declaration/sourceLine refusal проверяется отдельно и для case, и для exit.

`fixturePhase` и `safeCode` для newly identified trusted-auth-* принудительно устанавливаются в null, переопределяя возможный результат существующего generic legacy classifier: authoritative actor record здесь отсутствует. Нельзя искать `Bad state: ...` в произвольном private output и приписывать code/phase actor, даже если строка содержит exact known native code. Существующие T108–T114 поля/значения/total bounds/privacy и reporter validity сохраняются для остальных families; schemaVersion остаётся1. sourceFrames по-прежнему не более3, только known current hashed sources/valid lines и primary evidence до exact aggregate suffix; private aggregate text, paths, stdout/stderr, произвольные test names и stacks не экспортируются. Failed reporter/test по-прежнему означает failure qualification.

### Приёмка, порядок и неизменные release gates

| Требование | Решение/контракт | Задача | Проверяемый критерий |
| --- | --- | --- | --- |
| Constitution IV/VII: cleanup не стирает исходный результат | Общий lifecycle, прежний cleanup parent/orphan/scenario | T115 parent/actor adapters | Legacy masking meaningful RED; single object+stack identity; both typed private causes и primary throwing stack; cleanup once после settlement и ожидается caller |
| Failed startup не теряет ошибку и не закрывает success | Реальный typed-result/success-flag runTrustedAuthStartup в Pair.start | T115 locald helper/actor/unit | Failed start с успешным/failing cleanup; nullable success; успешный result идентичен и cleanup ресурсов не вызван |
| Constitution III/IV: safe truthful diagnostic | Exact25 names, hashed producer/primary nonzero exit, phase/code null | T115 projector/controlled tests | Все25cases; signed/unsigned границы, aggregate primary, foreign/stale/invalid/secondary/private negatives; предыдущие diagnostics неизменны |
| Constitution VII/VIII: old native oracles и exact revision | Actual25+orphan, root/locald checks, reviews; coldCI отдельно | T115 и общий release gate T114/T115 | Реальные26 native cases без weakened assertions; clean fresh review; только actual exact-source full coldCI разрешает следующий release gate |

Сначала meaningful unit RED/GREEN на actual reused lifecycle и startup adapter: original finally masking воспроизводится как failure необходимой проверки, не compile/scaffold failure. Проверяются success/body-only/cleanup-only/both, object/stack preservation, точные aggregate поля/primary prefix/suffix/throwing stack, cleanup после body settlement/ровно один раз/await до возврата и observer nonmasking. T114 generic unit coverage переиспользуется только при совпадающих bytes helper и явно записанном scope; startup-specific regressions вызывают реальный adapter, используемый Pair.start, а не копию его success-flag логики. Обязательны successful Pair-like object остаётся открытым, nullable null success не запускает failed-start cleanup, failed startup с success-flag=false сохраняет original error/stack при успешном и при failing cleanup. Нет новых обязательств менять Pair.close или client finally.

Затем выполняются actual trusted_auth_native_test25 ordinary cases плюс orphan (все26) с прежними oracles, locald analyze, root `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`. Controlled PowerShell suite включает все прежние T108–T114 проверки и новые25cases/primaryexit/aggregate, нулевое/дробное/overflow/non-numeric N, lower/upper границы, PASS/cleanup-only/orphan, secondary-only/spoof/raw marker/private output, foreign phase/URL/name/file/declaration/line и stale/mutated parent/actor/оба helpers. Privacy проверяется отсутствием raw sentinels в public JSON. Strict `lychee "specs/**/*.md"`, diff check, completed fresh independent code/spec review/fix loop и затем recording review обязательны. Actual native runs T115 и T11437/fullWindows сериализуются; текущие frozen inputs не меняются во время чужого run/review.

Общая будущая metadata `0.2.0-preview.1+7` уже подготовлена и включает T114/T115; повторный increment не нужен. T114/T115 остаются unchecked до их actual local implementation/checks/clean review. Этот spec этап меняет только четыре003 документа; pubspec+7 входит в пятифайловый freeze без изменения. После strict links/diff требуется отдельный fresh readiness review T115, до него code handoff не выполняется. Новый пакет/branch, production changes, tests/native/build/remote/commit в spec этап не входят.

После будущего exact+7 commit обязателен terminal successful полный cold MCP CI этой revision до merge/tag/source-only release. Отдельно записываются build/install/source ZIP/SHA/tag/merge/publication receipts; local/cached passes не доказывают CI6 root cause и не заменяют CI. Actual installed private+6/source ZIP6, normal private cachedf1, пять старых versions/workspace, исходный dirty H checkout, unqualified/unactivated c45 candidate, все completed T001–T113 и все RED/оба CI6 records сохраняются. MIT уже выбран; public binary/signing/native distribution/full001/021/005 gates не меняются.

## T114/T115 — запись локальной реализации и проверки

Запись 27 октября 2026 года фиксирует исполнение согласованных T114/T115 без новых требований. Readiness reviews T114 и T115 завершены без замечаний; последний также охватил уточнение T114 о едином пятисекундном бюджете child cleanup. Реализованы T114 Dart8, T115 Dart4 и diagnostics PS2. Shared lifecycle остаётся одним test-only helper; production, native, provider, credentials и runtime contracts 001/021 не менялись.

Фактические проверки: pure units31+8 с сохранёнными meaningful RED/GREEN; root exact format639 files/0 changes, Flutter analyze0 issues, full Flutter7505 passed+1 expected opt-in capture skip/301309ms/process0/reporterSuccess=true; полный serial Windows168 passed/0 skips/242619ms, включая все37 trusted-client cases и3 focused native completion tests; updated oversize10/10; trusted-auth25+orphan26/26/48421ms; Windows/locald analyze0. Isolated full controlled PowerShell suite завершён16/16 successful groups/125470ms/exit0, включая прежние T108–T113 и новые T114/T115 source/privacy checks. До recording strict links дали1475 total/1474 OK/0 errors/1 excluded/exit0, root diff-final — exit0. Подробные receipts и ограничения приведены в [evidence](evidence.md).

Оба fresh implementation review завершены0 findings: `t114_t115_dart_independent_review` проверил frozen17 files — Dart12 и пять spec/metadata interface inputs, без PS2 implementation; `t114_t115_ps_independent_review` проверил PS2 diagnostics и связанные inputs на frozen19 files. В обоих завершённых scopes все bytes/SHA совпали. T114/T115 закрыты только в local implementation/checks/review scope; T001–T113 и тексты обеих задач сохранены. После административной записи strict links дали1478 total/1477 OK/0 errors/1 excluded/exit0, diff — exit0; перед freeze они повторяются после записи этих receipts. Отдельный independent recording review ещё обязателен; до его clean результата commit не выполняется.

Working metadata0.2.0-preview.1+7 ещё uncommitted. Actual HEAD, installed private и source ZIP остаются+6/29c05212b462b3af33c284a19c7995d4652f2500; новые commit, CI7, build/install, source ZIP, tag, merge и publication ещё не выполнены. Оба Windows CI6 RED сохранены; actual actor outcome/scenario/root cause не установлены. Full cached locald936 passed/1 skip T112 остаётся отдельным историческим run до T113 и не выдан за новый full locald/cold CI. Sourcebuilt c45 по-прежнему unqualified/unactivated; normal private f1, пять старых versions/workspace/dirty H и completed T001–T113 сохранены. Прежние exact-revision cold CI, source-only/public binary/signing/full001/021/005 release gates не меняются.
