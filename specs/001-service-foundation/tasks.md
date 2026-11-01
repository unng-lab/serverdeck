# Tasks: 001.1 — Исполняемый сервис и защищённые профили

**Последнее указание пользователя — unit only**: все прежние собственные тесты,
fixtures и harness удаляются; пишутся только unit-тесты под эту задачу. Дизайн,
widget/visual/integration/native/реальные SSH/container проверки сейчас не выполняются.
Исторические результаты ниже остаются историей, не текущим gate. Изменение не
разрешает потерять функции, данные, права или проверки целевого поведения в новых units.

**Уточнение2026-10-30, без обратной совместимости**: действующий
[контракт](contracts/embedded-migration.md) исключает legacy runtime/API/bootstrap,
upgrade1/2, rollback к старым сборкам и переходные оболочки. Старый код удаляется
в этой же задаче после переноса используемой логики, а не остаётся «на переход».
Поддерживается только целевой schema3; несовместимые файлы не изменяются.

**Текущая работа 2026-10-30**: T253–T272 в конце файла. История T001–T252
сохраняется; старые Scope/Status/native gates описывают состояние до embedded-поправки.

**Input**: [Spec](spec.md), [Plan](plan.md), [research](research.md), [data model](data-model.md), [Local API](contracts/local-api.md), [runtime/storage](contracts/runtime-storage.md), [UI](contracts/ui-validation.md), [quickstart](quickstart.md).
**Scope**: только 001.1. US1 соответствует User Story 1 спецификации «Запустить собственное рабочее пространство», Priority P1. US2 (SSH) и US3 (job coordinator/recovery) не реализуются; базовые bootstrap/storage crash-сценарии AC 001.1 уже входят сюда. Нет backend, реальных серверных операций, installer/updater или импорта старого приложения.
**Status**: Implement 001.1 продолжается. Setup/Foundation и внутренние storage/custody/models/CRUD/coordinator приняты в отмеченных ниже задачах. Production locald выполняет owner bootstrap, handshake, readiness и Local API через настоящий named pipe; compiled console fixture подтвердил открытие/reopen, contender, watchdog и lease. T026–T028 приняты по совокупной unit/native/compiled evidence и завершённому независимому compiled_auth_owner_readiness_review; T030/T135–T140 приняты после независимого local_api_client_heartbeat_fixed_review без замечаний; T031/T142/T145 приняты после clean native_ui_bootstrap_review; attempt controller T141/T143 принят после clean bootstrap_attempt_disposal_fixed_review. UI оболочки, профилей/credentials/settings и mutation recovery реализованы и проверены в принятых scoped increments T147–T175. Из исходных aggregate задач завершены T033–T037, T041/T042, T045–T047 и T049; T038–T040, T043–T044, T048 и T050 остаются открытыми. Полная сквозная native/manual/CI приёмка и готовность всего001.1 к merge не установлены. Фактический scope и ограничения: [evidence](../../docs/development/foundation-verification.md).

## Format and execution rules

**Уточнение пользователя 2026-10-11**: открытыми и отложенными остаются только конкретные операции и проверки, которые отклоняет система защиты. Остальную реализацию, разрешённые checks и fresh reviews продолжать в порядке зависимостей. T016–T021/T082–T086 не отложены целиком; checkbox закрывается только по фактической реализации/checks/clean review, completed T020 сохраняется. Отклонённое действие не повторять через другой инструмент или перенос в runner как обход отказа; фиксировать точную операцию, причину и незакрытый gate. Известные отклонения: recursive cleanup старого Temp repository fixture и retained .local/notices-fixture-d26a7f2e13df4996ab163a618f89bba7; каталоги оставлены. Остальные прежние записи об откладывании всего блока являются историей, superseded этим уточнением. Полный001.1 и обязательные зависимости принимаются только по evidence.

`- [ ] Tnnn [P?] [US1?] действие с путями`. Пути — относительно корня репозитория, это будущие файлы. Source layout и контракты обязательны; не брать старую реализацию из worktrees/архивов. `[P]` разрешает параллельную работу лишь после общих prerequisites и только над разными файлами; конкретные batches ниже. Сохранять IDs и выполненные отметки, новые подтверждённые дефекты добавлять новыми задачами.

Tests обязательны по spec/Plan/конституции. Сначала создать проверки поведения, затем реализацию; для подтверждённого red нужен assertion failure при компилируемых интерфейсах, не missing import. При необходимости в начале implementation task объявить сигнатуры/throwing stub, выполнить связанный red test, затем реализовать и получить green. Заглушки не должны выдавать ready/success и не закрывают checkpoint. Секреты/fixtures не записывать в обычные логи/публичные материалы.

## Phase 1 — Setup

**Цель**: воспроизводимый новый workspace и инструменты, без обещания работающего сервиса.

- [x] T001 Создать новый Flutter Windows root и pure Dart packages по Plan в `pubspec.yaml`, `lib/main.dart`, `windows/`, `packages/serverdeck_protocol/pubspec.yaml`, `packages/serverdeck_windows/pubspec.yaml`, `packages/serverdeck_locald/pubspec.yaml`, `packages/serverdeck_locald/bin/locald.dart`; стандартный runner, минимальные компилируемые interfaces, no demo/старого кода/remote effects. W01.
- [x] T002 Зафиксировать SDK Flutter 3.47.7/Dart 3.13.5 и все exact direct pins/package allocation из Plan в `.flutter-version`, root/package `pubspec.yaml` и `pubspec.lock`; root bootstrap HMAC и locald envelope получают cryptography, locald не импортирует Flutter native-libs plugin, shared packages — path dependencies. Реально выполнить solver; если manifests не разрешаются, блокировать build и исправить Plan/checks/review, не менять pins молча. W01.
- [x] T003 [P] Настроить root/package анализ и форматирование в `analysis_options.yaml`, `packages/serverdeck_protocol/analysis_options.yaml`, `packages/serverdeck_windows/analysis_options.yaml`, `packages/serverdeck_locald/analysis_options.yaml` и `.gitignore`; исключить runtime/key/secret/build/test-evidence файлы из Git, не скрыть исходники/lockfiles. Root analyzer не проверяет `work/**` — отдельные Git worktrees старого приложения, но проверяет все новые packages/tests; обязательная format команда не меняется. W01/W07.
- [x] T004 [P] Создать SDK/prerequisite validation, AOT locald и Flutter build, native DLL копирование и dev manifest generation в `tools/build-locald.ps1`, `tools/run-foundation.ps1`; pinned bundled Dart, absolute app-root/hash allowlist, hidden UI-launched locald, layout/native runtime без download. Скрипт собирает оба процесса, а не запускает locald отдельно вручную. W01; полноценный smoke после T031/T034.
- [x] T005 [P] Создать основу synthetic native harness и compile-time test build entry в `tools/test-foundation-native.ps1`, `packages/serverdeck_locald/test/support/test_entry.dart`, `packages/serverdeck_locald/test/support/failpoints.dart`, `test/fixtures/foundation/markers.json`; runtime flags не должны включать test пути в normal build. Только disposable test user/VM, child PID и synthetic данные. W07.
- [x] T006 Создать Windows CI scaffold в `.github/workflows/foundation.yml`: pinned SDK, root/package resolution, генерация, build и необходимые checks с safe artifacts, без release publication; до реализации не обозначать отсутствующие acceptance tests успешно выполненными. W01/W07; завершение T044.

**Checkpoint**: scaffold/locks/build tooling воспроизводимы, все unfinished features честно недоступны. Это ещё не MVP и не основание merge 001.1.

## Phase 2 — Foundational

**Блокирующая граница**: shared wire/native infrastructure готова и проверена до integration US1. Ordinary API не включается без будущих storage/auth gates.

- [x] T007 Объявить shared DTO, method/capability/error/readiness enums и codec interfaces в `packages/serverdeck_protocol/lib/models.dart`, `packages/serverdeck_protocol/lib/protocol.dart`; все методы/union/полные schemas Local API v1, ProfileView без secret/blob/ref, mutation/status read correlation, версии и nullable workspaceId до ready. Не импортировать Isar/provider. W02/W05.
- [x] T008 [P] Написать contract/golden tests в `packages/serverdeck_protocol/test/codec_test.dart`, `packages/serverdeck_protocol/test/validation_test.dart`: canonical bytes, UUID/revision/union, repeated keys, unknown fields/invalid UTF8, framing/depth/размеры, safe error envelopes. W02/W05, Q03/Q10/Q11.
- [x] T009 Реализовать строгий codec/normalization/frame limits/canonical JSON в `packages/serverdeck_protocol/lib/codec.dart`, `packages/serverdeck_protocol/lib/validation.dart`; request≤256KiB/response≤8MiB/handshake≤8KiB/depth≤16, uint63 decimal strings, sorted keys/NFC и no input echo; T008 green. W02/W05.
- [x] T010 [P] Написать native security/path/DPAPI tests в `packages/serverdeck_windows/test/security_test.dart`, `packages/serverdeck_windows/test/paths_test.dart`: explicit SID ACL, unsafe reparse/UNC rejection, missing protection, separate entropy namespaces, native failure/handle cleanup, no impersonation/elevation. W02, Q03/Q06.
- [x] T011 Реализовать current-user SID/process identity/token queries, protected filesystem/flush/rename и DPAPI provider в `packages/serverdeck_windows/lib/security.dart`, `packages/serverdeck_windows/lib/paths.dart`, `packages/serverdeck_windows/lib/dpapi.dart`; exact ACL/entropy/flags из runtime contract, retained peer handle и creation-time/hash проверки, native errors safe; T010 green. W02.
- [x] T012 [P] Написать pipe/mutex/overlapped cancellation tests в `packages/serverdeck_windows/test/pipe_test.dart`, `packages/serverdeck_windows/test/mutex_test.dart`: восемь names/один instance каждого, remote/foreign-instance rejection, partial frame deadlines, CancelIoEx completion перед free/close. W02, Q02/Q03/Q10.
- [x] T013 Реализовать named mutex, восемь pipe slots/worker isolates/overlapped I/O/peer handle queries в `packages/serverdeck_windows/lib/mutex.dart`, `packages/serverdeck_windows/lib/pipe.dart`, `packages/serverdeck_windows/lib/process.dart`; non-inheritable handles, no GENERIC_WRITE/FILE_CREATE_PIPE_INSTANCE grants, exactly-once close, bounded resources; T012 green. W02.
- [x] T014 Реализовать safe code/retry mapping и diagnostic allowlist в `packages/serverdeck_protocol/lib/errors.dart`, `packages/serverdeck_locald/lib/api/diagnostics.dart`; только timestamp/requestId/generation/code/stage/duration, без native text/private values/paths/secret buffers; добавить regression в `test/security/diagnostic_test.dart`. W05, Q05/Q11.
- [x] T015 Добавить архитектурную проверку границ в `test/security/component_boundary_test.dart`: UI не импортирует Isar/locald storage/provider, только bootstrap/protocol; no LAN/SSH/executor/backend/export/test-fixture capabilities normal runtime. Schema и key bytes недоступны ordinary API. W01/W02/W05, Q04/Q05.

**Checkpoint**: T007–T015 проходят свои contract/native unit checks; не объявлять криптографию/DB готовыми по проверке mocked provider.

## Phase 3 — US1: открыть сервис и сохранить защищённый профиль (P1)

**Goal**: реальный compiled UI запускает один locald, получает защищённую пустую модель и CRUD с restart/retry/two-window поведением.
**Independent test**: disposable Windows user, normal build, сеть runtime заблокирована; два UI processes, private synthetic fields, create/replace/remove/delete, restart и failpoints. Будущие SSH/jobs пакеты не нужны. Полная приёмка — все семь AC 001.1 и Q01–Q12, не просто happy path.

### Storage и модели

- [x] T016 [P] [US1] Написать модели/CAS/credential lifecycle tests в `packages/serverdeck_locald/test/models_test.dart`, `packages/serverdeck_locald/test/credential_lifecycle_test.dart`: field bounds/defaults/refs, create none→replace→remove→replace1/2/3/4 с reopen, новые IDs, keep, selected-profile delete и no orphan blob. W03/W04, Q09.
- [x] T017 [P] [US1] Написать storage/initialization/crash tests в `packages/serverdeck_locald/test/state_store_test.dart`, `packages/serverdeck_locald/test/workspace_init_test.dart`: обычные читаемые метаданные, DPAPI секретов, отказ защиты/повреждённый blob/foreign wrapper, unsupported native schema до изменяющего open, durable transaction, valid empty staging promotion и partial/active+staging fail closed. W03, Q05/Q06/Q08; после T063.
- [x] T018 [US1] Создать WorkspaceState/Profile/Settings/CredentialRecord/MutationReceipt и пять обычных Isar collections в `packages/serverdeck_locald/lib/storage/models.dart`, `packages/serverdeck_locald/lib/storage/records.dart`, generated `records.g.dart`. Exact fields/indexes/cardinality/runtime-storage; lowercase UUIDv4/CSPRNG, Profile/Settings revision1/storeRevision0; CredentialRecord.revision равна Profile.credentialRevision. Profiles≤250, credentials один profile owner/no dangling refs, receipts≤10 000 immutable/no expiry/eviction. Per-record UTF8: profile≤16KiB, credential≤512KiB, workspace/settings/receipt≤4KiB. WorkspaceId/receiptKeyId UUID/ownerSid совпадают с manifest/wrapper. Native autoIncrement positive uint63/overflow rejected, entityId unique case-sensitive hash replace=false. Нет общего encrypted aggregate. W03/W04.
- [x] T019 [US1] Реализовать DPAPI CurrentUser credential custody и отдельный receipt HMAC key в `packages/serverdeck_locald/lib/storage/key_custody.dart`, `packages/serverdeck_locald/test/key_custody_test.dart`, `packages/serverdeck_locald/lib/storage/credential_validation.dart`: случайный receiptKey32bytes для digest, без root key/HKDF/AES-GCM базы; exact wrapper/entropy/bounds runtime contract, secrets never returned by read API, no plaintext fallback. DPAPI для password/privateKey/passphrase, validation всех blobs и identity/kind до ready; T017 custody tests green. W03, Q05/Q06.
- [x] T020 [US1] Реализовать durable Isar multi-record repository в `packages/serverdeck_locald/lib/storage/state_store.dart`, `packages/serverdeck_locald/lib/storage/native_schema.dart`: bundled native load, relaxedDurability false/inspector false/maxSizeMiB64, readonly snapshot registry validation по пяти generated schemas до open; startup cardinality/per-record size/ref/revision/DPAPI checks, one writer, changed records+deletes+receipt+storeRevision одной transaction до reply. Quota/map-full с доказанным rollback→RESOURCE_LIMIT/ready; неопределённая storage error блокирует requests до reopen, preserves bytes. T016/T017 repository tests green. W03, Q05/Q06/Q08.
- [x] T021 [US1] Реализовать staging create/open/recovery в `packages/serverdeck_locald/lib/storage/workspace.dart`: mutex до receiptKey/Isar; default.creating protected path; flush receipt-key.dpapi и plain manifest; durable empty StoredWorkspace/StoredSettings/close/validate/same-volume promotion/reopen. Existing/partial/active+staging/missing-part fail closed без удаления/замены технического key. До promotion не ready; T017 init tests green. W03, Q06/Q08.

### CRUD, credentials и устойчивые запросы

- [x] T022 [P] [US1] Написать mutation/status/CAS/receipt tests в `packages/serverdeck_locald/test/mutations_test.dart`: потеря reply/request, same-generation not-found retry, late original, differing digest, duplicate requester, cancelled-before-start/running disconnect, commit error не not-found, quota и atomic credential/settings effects. W04, Q07/Q09/Q10.
- [x] T023 [US1] Реализовать profile/secret validation в `packages/serverdeck_locald/lib/profiles/validation.dart` и shared UI validators в `packages/serverdeck_protocol/lib/profile_validation.dart`. Дословно: «Text обычных полей: UTF8/NFC; trim name/address/user/tags.»; «Секретные строки password/privateKey/passphrase сохраняют исходную последовательность Unicode и UTF8 bytes, без trim/NFC/преобразования переводов строк». Malformed Unicode/UTF8 отклоняется; NUL/C0/C1 запрещены кроме LF/CR key PEM. Length обычных строк — Unicode scalars; secret bounds — UTF8 bytes. Сохранить regressions T065; «Name1–128; address1–253 — IPv4/IPv6 без brackets либо ASCII DNS A-label, без scheme/slash/inline port/whitespace.»; «Port1–65535 default22; user1–64 без whitespace/control; tags≤16, каждый1–64, уникальны после NFC.»; «ProfileJSON≤16KiB; password непустой≤4KiB UTF8; privateKey≤64KiB PEM/OpenSSH envelope; passphrase≤4KiB.» Duplicate target разрешён, crypto SSH usability не заявлять. W04, Q09.
- [x] T024 [US1] Реализовать profile CRUD/credential lifecycle/settings service в `packages/serverdeck_locald/lib/profiles/service.dart`, `packages/serverdeck_locald/lib/credentials/provider.dart`, `packages/serverdeck_locald/lib/profiles/settings_service.dart`. Дословно: «CredentialRef null допустим.»; «Каждый replace создаёт новый случайный credentialId, удаляет прежнюю запись и атомарно меняет link.»; «Revision новой записи **равна получившейся Profile.credentialRevision**, может начинаться с2 или выше; отдельного revision-счётчика у CredentialRecord нет.»; settings «`revision:1,theme:system|light|dark` default system, `reduceMotion:boolean` false, `selectedProfileId:null|UUID` null.» Delete selected-profile повышает settings revision и очищает selection атомарно, no host change/secret readback. Все Profile revision/access/trust/keep/remove/timestamps правила data-model; T016 green. W04, Q09.
- [x] T025 [US1] Реализовать serial mutation coordinator/receipt/inflight/status в `packages/serverdeck_locald/lib/profiles/mutation_coordinator.dart`: «Persist только successful committed mutations.»; HMAC digest по canonical validated input, immutable compact receipt без raw request/secrets; register before async, serial status/CAS/commit, replay original result, duplicate attach, no-effect queued cancellation только без live requesters, not-found retry same id/input в любом ready generation, storage unknown blocked; T022 green. W04, Q07/Q10.

### Авторизованный locald и клиент

- [x] T026 [P] [US1] Написать bootstrap/auth/session/readiness/lifecycle tests в `packages/serverdeck_locald/test/bootstrap_native_test.dart`, `packages/serverdeck_locald/test/auth_test.dart`, `packages/serverdeck_locald/test/lifecycle_test.dart`: normal peer-check handshake, denied queries/proofs/caps, pre-ready gates, contenders, token/generation rotation, lease/grace и duplicate requester/shutdown transaction. W02/W05, Q02/Q03/Q04/Q11.
- [x] T027 [US1] Реализовать locald entry/bootstrap/manifest/native prerequisites/discovery/readiness в `packages/serverdeck_locald/bin/locald.dart`, `packages/serverdeck_locald/lib/bootstrap/bootstrap.dart`, `packages/serverdeck_locald/lib/bootstrap/discovery.dart`; winner/loser/abandoned mutex, DPAPI descriptor без root key, null workspaceId до open, same-generation polling, total startup watchdog30s, no kill/reset/old namespace; T026 startup tests green. W01/W02/W05, Q02/Q04/Q06/Q11.
- [x] T028 [US1] Реализовать handshake/auth/grants/session lease и shutdown в `packages/serverdeck_locald/lib/api/auth.dart`, `packages/serverdeck_locald/lib/api/sessions.dart`, `packages/serverdeck_locald/lib/bootstrap/lifecycle.dart`; exact proof transcript, peer token/hash/liveness checks без impersonation/elevation, ≤8 sessions/16 pending each, heartbeat20s/lease60s/grace2s, startup без sessions не завершается до watchdog30s, commit before close/release. T026 auth/lifecycle tests green. W02/W05, Q03/Q10/Q11.
- [x] T029 [US1] Реализовать Local API router в `packages/serverdeck_locald/lib/api/server.dart`: все методы из контракта, cap before business parse, ready-only CRUD/status, atomic snapshots/monotonic storeRevision, max32 mutation queue, safe errors/limits; profile projection без credentialRef/blob/key, no SSH/jobs/backend/export endpoints. Добавить exhaustive method/cap/readiness tests в `packages/serverdeck_locald/test/api_test.dart`. W04/W05, Q03/Q05/Q09/Q10/Q11.
- [x] T030 [US1] Реализовать Flutter-side protocol client в `lib/bootstrap/local_api_client.dart`: frame/auth/correlation, heartbeat/reconnect, свежий envelope id status read с params.requestId original mutation, immutable retries/late reply filtering, poll2s atomic snapshots и no auto-save; tests в `test/contract/local_api_client_test.dart`. W02/W05/W06, Q07/Q10/Q11.
- [x] T031 [US1] Реализовать UI bootstrap в `lib/bootstrap/bootstrap_controller.dart`, `lib/main.dart`: verified app-root/build manifest, discover/launch hidden locald без shell/secrets, DPAPI descriptor, peer verification, readiness poll250ms/connect backoff100→1000ms/total30s/manual retry joins live attempt; tests в `test/contract/bootstrap_controller_test.dart`. W01/W02/W05/W06, Q01/Q02/Q04/Q11.

### UI и сквозные проверки US1

- [x] T032 [P] [US1] Подключить существующие brand tokens/logos/Noto fonts к обеим темам в `lib/theme/brand_theme.dart`, root `pubspec.yaml`, `lib/theme/brand_assets.dart`; OFL/notices сохранить, source brandbook не менять, системный ICO соблюдать. W06, Q12.
- [x] T033 [P] [US1] Написать widget tests в `test/widget/foundation_shell_test.dart`, `test/widget/profile_form_test.dart`, `test/widget/settings_test.dart`: readiness/unavailable sections, target, empty/delete, CAS draft, save failure/lost reply, transient secrets, keyboard/focus, themes/four viewports/textscale200%. W06, Q01/Q09/Q11/Q12.
- [x] T034 [US1] Реализовать пятираздельную оболочку и startup/blocked/error состояния в `lib/app.dart`, `lib/shell/foundation_shell.dart`, `lib/shell/readiness_view.dart`; до ready no private data, future sections/actions unavailable, local failure не remote health, no demo. Подключить T031 и T032; T033 shell tests green. W06, Q01/Q11/Q12.
- [x] T035 [US1] Реализовать профильные list/detail/forms/delete в `lib/profiles/profile_list.dart`, `lib/profiles/profile_form.dart`, `lib/profiles/credential_input.dart`; A-label conversion до API, validation T023, явный key picker≤64KiB без path persistence/implicit SSH key, keep/replace/remove/reveal transient, atomic save без connect, cancel no effects, delete local confirmation, focus return. T033 form tests green. W04/W06, Q09/Q12.
- [x] T036 [US1] Реализовать theme/reduceMotion/selection settings UI в `lib/settings/settings_view.dart`, `lib/settings/settings_controller.dart`, `lib/profiles/profile_controller.dart`; DTO defaults/CAS, delete clears selection, profile target visible, reduced motion и drawer≤800px; persistent data только через locald. T033 settings tests green. W06, Q09/Q12.
- [x] T037 [US1] Завершить mutation-result recovery/draft/error UX в `lib/profiles/mutation_controller.dart`, `lib/shell/error_view.dart`: no optimistic success, same immutable id retry, status query correlation, no current snapshot overwrite by old revision, draft/reload choice, first startup list/recent после UI crash без auto-save, input buffers cleared after save/cancel. Tests в `test/widget/mutation_recovery_test.dart`. W04/W05/W06, Q07/Q10/Q11.
- [ ] T038 [US1] Написать и довести до green full profile journey в `integration_test/foundation_test.dart`, two-process scenarios в `packages/serverdeck_locald/test/support/two_window_scenarios.dart`: normal compiled client/real locald/real protected DB, offline Q01/Q02/Q07/Q09/Q11, separate UI processes/one owner, cancel/delete/reopen/lost reply/late request/second live window. Не заменять эталонный сценарий mocked repository. W07.
- [ ] T039 [US1] Реализовать native auth/prerequisite/corruption probes в `packages/serverdeck_locald/test/support/security_scenarios.dart`: полный Q03/Q04/Q06 с process-token failures/foreign slots/remote rejection/version/native loader/ACL/reparse/key/schema/tag errors, own identity unchanged, bytes preserved. W02/W03/W05/W07.
- [ ] T040 [US1] Реализовать secret-marker/init/commit crash scans в `packages/serverdeck_locald/test/support/storage_scenarios.dart`, `test/security/private_marker_scan_test.dart`: Q05/Q08, each init failpoint, DPAPI/credential binding/availability, committed state+receipt после kill, partial staging сохранён. Обычные метаданные читаемы в базе; секреты отсутствуют открыто в DB/index/log/temp/export. W03/W07.
- [x] T041 [US1] Реализовать resource/session/queue probes в `packages/serverdeck_locald/test/support/resource_scenarios.dart`: Q10, frames/partial5s/16pending/8sessions/32queue/10kreceipts/DB64MiB/profile250 и per-record bounds; превышение перед commit не меняет state, reads работают. Cancel queued only no live requesters/not-found same-generation retry, running commit не отменён/не not-found; native cleanup. W04/W05/W07.
- [x] T042 [US1] Довести T033/T037 widget suite до полной Q12 и добавить viewport acceptance в `test/widget/accessibility_test.dart`: обе темы, 1100×760/800×600/360×800/390×800, textscale200%, 48logicalpx targets, keyboard/focus/scroll/action reachability, target/errors/draft. Это Windows layout, не Android support. W06/W07.

**Checkpoint US1**: happy path и отказные проверки реализованы; пока T043–T050 не закрыты, нет основания заявить native acceptance/merge readiness. Все seven AC этапа обязательны.

## Phase 4 — Polish and cross-cutting acceptance

- [ ] T043 Завершить исполняемый native harness/build wiring в `tools/test-foundation-native.ps1`, `tools/run-foundation.ps1`, `packages/serverdeck_locald/test/support/test_entry.dart`: T038–T041 probes вызываются автоматически; test namespaces/failpoints только compiled test build; normal executable rejects test flags даже после manifest edit. PID/root boundaries проверены до cleanup/kill, обычные private файлы не публикуются. W01/W07, Q01–Q11.
- [ ] T044 Завершить `.github/workflows/foundation.yml`: root dart format/flutter analyze/flutter test/Windows integration, Dart analyze/test всех трёх packages, generator/AOT/Flutter build и native automatic harness; SDK/hash/locks enforced, safe logs, failures block merge, не выдать CI за manual reboot/other-user evidence. W01/W07.
- [x] T045 Проверить фактические resolved native/Dart/font лицензии и включить notices/corresponding native source references в `docs/development/third-party-notices.md` и bundled `THIRD_PARTY_NOTICES.txt`; MPL-2.0 MDBX/Apache/BSD/OFL не теряются. Лицензию ServerDeck автоматически не выбирать, public release вне scope. W01/W07.
- [x] T046 Обновить runnable инструкции и статус новой реализации в `README.md`, `docs/development/foundation.md`, `specs/001-service-foundation/quickstart.md`: actual SDK/package/native prerequisites/layout/commands, disposable VM/user preparation, recovery reasons без private dumps, future features unavailable; не заявлять невыполненные Q. W07.
- [x] T047 Выполнить обязательные command checks quickstart (root format/analyze/test/Windows integration, Dart analyze/test каждого package, обе сборки и lychee) и исправить failures; сохранить safe exitcodes/scope в `docs/development/foundation-verification.md`, T044 workflow и checks не заменить планом запуска. W07.
- [ ] T048 Выполнить всю Q01–Q12 native приёмку в disposable Windows среде, включая reboot/другой OS user, normal build offline и compiled test failpoints; записать реальные results/ограничения в `docs/development/foundation-verification.md`. Simulation и green CI не заменяют native gates. Если среда недоступна, оставить задачу открытой и указать blocker, не утверждать готовность. W07.
- [x] T049 Запустить независимое code/package review в fresh subagent fork_turns none по `AGENTS.md`; дать точный diff/этот package/check evidence, исправлять confirmed defects, добавляя новые задачи без стирания completed history, повторять applicable checks/fresh review до clean report. Отчёт и scope записать в `docs/development/foundation-verification.md`. W07.
- [ ] T050 Сверить все FR/AC/SC scope001.1 по таблицам ниже, реальные checks/native Q/review и итог в `docs/development/foundation-verification.md`; закрывать checkbox только по evidence. Следующий этап001.2 не включать автоматически. Не создавать PR/release/merge/publish без отдельной задачи пользователя. W07.

## Dependencies and execution order

- [x] T058 Исправить подтверждённое P2 independent storage primitives review5: принимать standard traditional encrypted RSA PEM headers Proc-Type/DEK-Info без SSH parsing, сохранив size/control/type/envelope bounds. Regression в `packages/serverdeck_protocol/test/profile_validation_test.dart` воспроизвёл VALIDATION до исправления; добавлены header/body checks в `lib/profile_validation.dart`. Проверки и fresh review обязательны.

- [x] T057 Зафиксировать exact persisted manifest/root/credential wrapper schemas и base64/byte bounds в `contracts/runtime-storage.md`, реализовать в `packages/serverdeck_locald/lib/storage/key_custody.dart`, проверить real CurrentUser DPAPI/root reopen/manifest integrity/credential entropy в `test/key_custody_test.dart`. Это закрывает serialization detail при T019, не custody lifecycle/initialization/storage acceptance целиком; T017–T021 остаются открытыми. Fresh independent review обязателен.

- [x] T055 Исправить ранний setup cleanup mutex в `packages/serverdeck_windows/lib/mutex.dart`: создавать native event до ReceivePorts, при ошибке SID/descriptor/event не оставлять ports. Regression в `packages/serverdeck_windows/test/mutex_test.dart` запускает отдельный child, проверяет normal shutdown после отказа; red timeout до исправления, green после. Причина: independent review round 2, P2.
- [x] T056 Уточнить обязательный Windows pipe ACL: FILE_READ_ATTRIBUTES вместе с read/write data, READ_CONTROL, SYNCHRONIZE, exact mask 0x120083 в `contracts/runtime-storage.md` и `packages/serverdeck_windows/lib/pipe.dart`. Старый mask 0x120003 даёт ERROR_ACCESS_DENIED даже своему пользователю при CreateFile; native regression подтверждает duplex/identity/cancellation с новым mask без grant создания instance. Fresh review обязателен; полный T012–T013 остаётся открытым.

- [x] T052 Исправить integer API version validation в `packages/serverdeck_protocol/lib/validation.dart` и добавить real-decode regression в `packages/serverdeck_protocol/test/validation_test.dart`. Причина: independent foundation review finding 1; FR-SVC-004, Local API v1.
- [x] T053 Убрать single-frame ограничение transport chunk из `packages/serverdeck_protocol/lib/codec.dart`, проверить coalesced frames и все chunk cuts в `packages/serverdeck_protocol/test/codec_test.dart`. Причина: independent foundation review finding 2; FR-SVC-004, framing. Session pending/queue лимиты остаются обязанностью T028–T029, не decoder chunk.
- [x] T054 Согласовать UNSUPPORTED в `specs/001-service-foundation/contracts/local-api.md`, `packages/serverdeck_protocol/lib/models.dart` и shared regression `packages/serverdeck_protocol/test/validation_test.dart`. Причина: independent foundation review finding 3; FR-002/FR-SVC-016. Закреплены local boundary/retry none/no effects; exhaustive router test при T029 обязателен.

- [x] T051 Зафиксировать NFC implementation dependency `unorm_dart 0.3.3` в `packages/serverdeck_protocol/pubspec.yaml`, обновить root/locald/protocol lockfiles и `specs/001-service-foundation/plan.md`; проверить canonical NFC/codepoint golden vectors в `packages/serverdeck_protocol/test/codec_test.dart`. Причина: выполнение обязательного NFC контракта T009 без самодельной Unicode таблицы. Выполняется до завершения T009; MIT notice остаётся обязательством T045. Новая запись сохраняет completed history T002.

- [x] T059 Исправить safe filesystem boundary в `packages/serverdeck_windows/lib/paths.dart`: чтение защищённой директории или native read failure не сохраняет private path/OS text в исключении; ограничить actual read даже при изменении размера файла. Добавить regression в `packages/serverdeck_windows/test/paths_test.dart`. Причина: подтверждённое P2 independent Foundation checkpoint review8; T010/T011, FR-SVC-016, Q06/Q11. Сохранить completed history.

- [x] T060 Проверять исторические entity revisions в persisted MutationReceipt parser `packages/serverdeck_locald/lib/storage/models.dart`: create revision1, profile revision≤committed store revision, settings revision≤committed store revision+1. Добавить regression в `packages/serverdeck_locald/test/models_test.dart` и закрепить serialization invariants в `data-model.md`. Причина: подтверждённое P2 independent storage-model review10; T016/T018, FR-SVC-015, Q06/Q09. Не сравнивать receipt с поздней текущей entity, completed history сохранить.

- [x] T061 Исправить классификацию native schema mismatch в `packages/serverdeck_locald/lib/storage/native_schema.dart`: корректно прочитанные чужие collection/schema names дают INCOMPATIBLE, структурные повреждения/cardinality дают STORAGE_BLOCKED. Уточнить реальные native regressions в `packages/serverdeck_locald/test/native_envelope_test.dart` до exact safe code. Причина: подтверждённое P2 independent native-schema review13; T017/T020, runtime-storage startup4, Q06. Completed history сохранить; full StateStore/staging acceptance не закрывается этим primitive.

- [x] T062 Историческое замечание review15 в `docs/development/foundation-verification.md`: несовместимость aggregate quota16MiB и uint24 native Isar. Задача утратила актуальность после явного уточнения пользователя 2026-10-11: единый encrypted aggregate удаляется, решение о уменьшении лимита не требуется. Не выполнять прежнее исправление; критерий закрытия — подтверждённый аудит замены по T063/T017–T020 и независимое ревью docs/development/storage-transition-audit.md. Исходное исправление quota не выполняется, historical review15 сохраняется; закрыто по completed clean storage_transition_obsolete_limit_review как superseded/replaced.

## Поправка охвата защиты 2026-10-11

Пользователь подтвердил защиту средствами ОС всех секретов доступа: SSH private keys, passwords и passphrase. Обычные metadata не шифруются приложением. Completed T002/T057 и прежние промежуточные tests/reviews сохраняют историческое содержание; части про envelope/root/manifest MAC не являются требованиями новой реализации. T016–T021/T040/T041 остаются открытыми и пересмотрены выше. T062 superseded, не входит в очередь исполнения. Наличие старых AES/StateEnvelope primitives в коде до T063 не означает соответствия новому Plan.

- [x] T063 [US1] Удалить ошибочный workspace-wide crypto path в `packages/serverdeck_locald/lib/storage/envelope_crypto.dart`, `packages/serverdeck_locald/lib/storage/state_envelope.dart`, generated `state_envelope.g.dart` и связанные obsolete tests; заменить root/HKDF/manifest-MAC references в `key_custody.dart`, `models.dart`, `native_schema.dart` и tests согласно runtime-storage. Не удалять DPAPI/ACL/IPC primitives или completed task history. Выполнить перед T017–T021; обязательные checks и fresh read-only review после изменения кода.

Порядок продолжения US1: clean review пересмотренных Spec/Plan/Tasks → T063 → T016/T017 → T018/T019 → T020/T021 → остальная незавершённая очередь. T063 не меняет gate всего001.1 и не разрешает пропустить его приёмку. Для001.2/001.3 по-прежнему нужны отдельные Plan/Tasks.

- [x] T064 Исправить подтверждённое P3 secret-scope design review: согласовать фактический статус scaffold/частичной реализации и незавершённой приёмки в `spec.md`, `plan.md`, `quickstart.md`, `checklists/requirements.md`, `specs/README.md`, `specs/business-requirements.md`; сохранить completed history и очередь продолжения с T063. Эта отметка фиксирует правку текста, не readiness runtime. Mandatory lychee и fresh independent review полного пакета выполняются после исправления.

- [x] T065 Сохранять секретные строки без NFC/trim/newline conversion в `packages/serverdeck_protocol/lib/codec.dart`, `lib/profile_validation.dart` и DPAPI custody; обычные metadata по-прежнему NFC. Два assertion regressions воспроизвели изменение NFD-пароля и collision receipt digest до исправления. Проверки wire/validation/CRLF/passphrase в `packages/serverdeck_protocol/test/secret_verbatim_test.dart`; real DPAPI/digest в `packages/serverdeck_locald/test/key_custody_test.dart`, `test/receipt_key_test.dart`. Exact правило закреплено в `data-model.md`; mandatory checks/fresh code review требуются перед принятием scope.

- [x] T066 Исправить воспроизводимый ложный timeout expectation в `packages/serverdeck_protocol/test/framing_test.dart`: прежний короткий frame завершался до deadline при geometric delays, полный suite дважды воспроизвёл failure. Fixture теперь остаётся незавершённым на всём deadline и поступает малыми порциями; проверка общего срока от первых bytes сохраняется. Production framing не меняется; обязательные checks/review применимы.

- [x] T067 Исправить подтверждённое P2 secret-custody replacement review в `specs/001-service-foundation/tasks.md`: открытая T023 больше не поручает NFC для секретов; согласовать verbatim и UTF8 byte bounds с `data-model.md` и regressions T065. Completed history сохранена; после правки повторить checks и запустить fresh read-only review до чистого результата.

- [x] T068 Создать native collection/transaction fixture в `packages/serverdeck_locald/test/records_test.dart`: compiled WorkspaceRecords stub дал red, затем проверить пять generated Isar schemas и exact unique/case-sensitive/hash/replace=false indexes, durable save/reopen всех entities, DPAPI-secret roundtrip, обычный адрес в DB bytes/отсутствие открытого секрета, protected DB/lock ACL и полный rollback после unique collision. Это schema/encoding coverage T018; не gate StateStore/pre-open inspection/staging T017/T020/T021. Mandatory checks/fresh review обязательны.

- [x] T069 Настроить `packages/serverdeck_locald/build.yaml` с source_gen combining-builder `ignore_for_file: experimental_member_use` для generated output: pinned Isar3.3.2 генерирует36 обращений к собственным experimental index conveniences. Ручные исходники остаются под проверкой, generated schema/serialization не исключаются из анализа, dependency pins не меняются. Реальная повторная generation и locald analyze/test прошли; root checks и fresh review обязательны.

- [x] T070 Создать точный read-only comparator native `_info` JSON documents в `packages/serverdeck_locald/lib/storage/native_registry.dart` и regression `test/native_registry_test.dart`: strict UTF8/JSON с duplicate-key rejection, bound16KiB/schema, пять generated names/properties/indexes/no links/embedded/version2, неизвестная well-formed schema→INCOMPATIBLE, malformed JSON→STORAGE_BLOCKED, safe errors без source. Три tests сначала red на compiled stub, затем green. Comparator не читает MDBX snapshot и не разрешает writable open; T020 остаётся открытой до bounded reader, его native failure tests и StateStore integration. Mandatory checks/fresh independent review обязательны.

- [x] T071 Реализовать read-only native registry snapshot preflight в `packages/serverdeck_locald/lib/storage/native_schema.dart` для pinned MDBX layout: snapshot≤64MiB, три meta pages/complete transaction/steady marker, bounded catalogue и `_info` branch/leaf/overflow traversal с cycle/overlap/count checks, exact five schemas и nine native tables/index DB descriptors до любого Isar.open. Actual native `records_test.dart` сначала red на compiled stub, затем принимает ordinary DB, отклоняет реальную four-collection DB→INCOMPATIBLE, schema version mismatch→INCOMPATIBLE, invalid JSON/truncation/meta/node/count damage→STORAGE_BLOCKED и доказывает неизменность source files. Это registry preflight, не full native data/index/GC integrity audit, не StateStore/staging/readiness; T020/T021 остаются открытыми. Mandatory checks/fresh review обязательны.

- [x] T072 Исправить подтверждённое P2 native_snapshot_review: в `native_schema.dart` проверять branch routing `previousChild.max < separator <= currentChild.min`, непустые последующие separators, сохранять ordered leaves/cycle/bounds guards. `test/support/native_snapshot_fixture.dart` строит catalogue и `_info` branch из real native entries только в RAM; positive branches принимаются, z-separator отвергается. Regression сначала дал assertion red при compiled reader, после fix green; mandatory checks/fresh review обязательны.

- [x] T073 Исправить второе подтверждённое P2 native_snapshot_review: структурно проверить все native named-tree descriptors перед schema/name compatibility в `native_schema.dart`. Mixed foreign version/name/missing `_info` + malformed StoredProfile root0 должны возвращать STORAGE_BLOCKED; well-formed actual foreign DB остаётся INCOMPATIBLE. Regression green после fix, completed history сохранена. Это не полный обход data/index/GC и не закрытие T020; mandatory checks/fresh review обязательны.

- [x] T074 Разрешить explicit protected snapshot read bound≤64MiB в `packages/serverdeck_windows/lib/paths.dart`, сохранить default32MiB и pre-read/actual-read bounds/ACL/safe errors. Native `test/paths_test.dart` читает собственный файл32MiB+1 при explicit64MiB и отклоняет превышение выбранного/максимального bound; assertion red на прежнем max32MiB, затем green. Это prerequisite T020, без изменения secret-wrapper write limit.

- [x] T075 Реализовать первый existing-workspace repository increment в `packages/serverdeck_locald/lib/storage/state_store.dart`, native fixture `test/state_store_test.dart`/`test/support/state_store_child.dart`: held MutexLease/owner SID, bundle verification, protected manifest/key/snapshot reads, registry preflight до open, cardinality/per-record/ID/ref/revision/DPAPI startup checks, serial durable changed entities/deletes/new receipt/storeRevision, native IDs сохраняются на update, replayed revision отклоняется, close/reopen проверяет actual state. Закрепить filename workspace.manifest.json в runtime contract. Child использует synthetic executable bytes только для проверки bundle hashes, не доказывает process auth; запускается direct dartvm с bounded kill/cleanup. Этот increment не закрывает T020: native map-full classification/proven rollback, crash/remaining failure coverage и последующая staging/bootstrap integration ещё открыты; entrypoint остаётся SERVICE_UNAVAILABLE. Initial repository fixture создан после первого варианта source; TDD red для этого source не заявляется. Mandatory checks/fresh review обязательны.

- [x] T076 Исправить воспроизведённое concurrent close в `state_store.dart`: единый retained close Future, drain pending repository operations, exactly-once native close, safe error. Два concurrent close сначала дали native already-closed error в actual child fixture, после fix green. Сохранить caller-owned mutex/key lifetime и историю Tasks; mandatory checks/fresh review обязательны.

- [x] T077 Исправить подтверждённое P2 state_repository_review в `state_store.dart`: синхронный process reservation до первого await, ownership transfer на успешный StateStore, release только после подтверждённого native close/full failed-open cleanup; неопределённый cleanup сохраняет reservation. Actual child fixture запускает два open одновременно: regression дал EXPECTED_REJECTION (второй ошибочно успешен), после fix ровно один owner, второму STORAGE_BLOCKED; первый продолжает commit/reopen, failed manifest open не препятствует следующему исправленному open. Mandatory checks и fresh independent review обязательны.
- [x] T078 Реализовать pinned native capacity classification в `native_failure.dart` и проверку фактического rollback в `state_store.dart`: только точные Isar3.3.2 DbFull/AutoIncrementOverflow сообщения внутри transaction, после abort перечитать все records/DPAPI и сравнить canonical state с предыдущим; лишь доказанный rollback возвращает RESOURCE_LIMIT/ready, неизвестный или несовпавший результат STORAGE_BLOCKED. Unit/native classifier тесты дали red против compiled stub, затем green. Actual10MiB native fixture достигает map-full, проверяет rollback предыдущих workspace/receipt writes, recovery write и reopen; это native transaction test с synthetic oversized payload, не full StateStore map-full acceptance. Actual StateStore child с валидными entities и native id=uint63 max проверяет allocator overflow→RESOURCE_LIMIT, неизменные profile/receipt/revision и reopen. Последний regression впервые запущен после fix; его red не заявлен. T020 остаётся открытой для полного map-full/crash/startup coverage; T021 ещё не выполнена. Mandatory checks/fresh read-only review обязательны.
- [x] T079 Расширить настоящие StateStore probes в `test/state_store_test.dart`, `test/support/state_store_child.dart`, `test/support/state_store_crash_child.dart`: production64MiB map-full при удержании native reader, bounded valid profile/DPAPI replacements и immutable receipts, RESOURCE_LIMIT/unchanged state и reopen; startup duplicate/unknown JSON, damaged/foreign/kind-mismatched DPAPI, invalid revision и singleton cardinality с сохранением испорченных payloads и восстановлением после явного fixture repair. Hard-kill только собственных child VM после наблюдаемой границы: native transaction до commit не оставляет effects; StateStore durable commit до потерянного reply сохраняется после нового процесса. Fixture-only native handle invalidation проверяет STORAGE_BLOCKED для failed/subsequent commit/state/close и восстановление в новом процессе. Нет production test hooks или readiness simulation; synthetic bundle/mutex/PEM не проверяют peer authentication/SSH usability/reboot/other-user. Новые tests впервые запускались против существующей реализации; первый неверный fixture не повышал trustRevision вместе с connectionRevision и исправлен, red production defect не заявлен. Full001.1/T021 остаются открытыми; T020 closure требует обязательных checks и завершённого fresh review.
- [x] T080 Исправить подтверждённое P2 state_store_acceptance_review: credential DPAPI validation candidate теперь внутри fail-closed try/catch StateStore, поэтому отказ после successful open фиксирует _blocked до reopen. Fixture-only переключаемый provider сначала делегирует actual DPAPI и сохраняет credential, затем отказывает на unprotect при валидном name update с прежним credential. Regression воспроизвёл EXPECTED_STORAGE_BLOCKED на доступном state до fix; после fix rejected commit и дальнейшие state/commit, восстановление provider не снимает latch, database bytes не изменены, close/reopen и свежий process восстанавливают предыдущие profile/receipt/revision. Production hooks не добавлять; mandatory checks/fresh independent review обязательны, stage acceptance остаётся открытой.

T020 implementation завершена на уровне repository: T074–T080 закрывают ownership/open/commit/native capacity/startup/process-crash/DPAPI latch probes; после T080 actual locald suite23 green. Эта отметка не закрывает T016 credential lifecycle service, T017 staging tests, T021, bootstrap/auth/CRUD/UI или full001.1. Приёмка repository и передача следующему implementation шагу требуют завершённого fresh review после T080; до него readiness не заявляется.

```text
Setup T001→T002→(T003,T004,T005)→T006
Foundation T007→(T008,T010,T012)→T009/T011/T013→T014→T015
US1 storage (T016,T017)→T018→T019→T020→T021
US1 services tests (T022,T026) after T021
CRUD T023→T024→T025; bootstrap/auth T027→T028
T025+T028→T029→T030→T031
UI (T032,T033)→T034→T035→T036→T037
T038→T039→T040→T041→T042→T043→T044→T045→T046→T047→T048→T049→T050
```

T009 зависит T008, T011 от T010, T013 от T011/T012: pipe security использует уже принятый OS adapter. Storage после полного Foundation. T023–T025 после T022; T027–T028 после T026/T021; T029 ждёт оба пути. Общий порядок остаётся последовательным, параллельность разрешена только обозначенным independent file batches. Все Tasks имеют предыдущий phase как prerequisite, если явно не указан более ранний batch. Runtime pipeline T004 не требует завершённой US1 для написания скрипта, но его полноценная проверка только после T034/T038/T043.

### Workspace coordinator increment

- [x] T081 Реализовать coordinator create/open/recovery в `packages/serverdeck_locald/lib/storage/workspace.dart` и native probes в `test/workspace_init_test.dart`, `test/support/workspace_child.dart`: compiled stub дал UnimplementedError red, затем actual CurrentUser DPAPI/Isar create, protected files, UUIDv4, concurrent open rejection/coalesced close, same identity/key reopen, complete empty staging promotion. Partial staging, active+staging, missing manifest/key/database/lock, unknown manifest schema, damaged DPAPI и non-default-settings staging отклоняются без reset/rekey/promotion. До writes проверяются lease/native prerequisites; closed lease/missing bundle не создают namespace. Для rejected nonempty staging native open/close может обновить MDBX meta pages; сохраняются application rows, manifest/key и файлы, byte-identical database не заявляется. Persisted pre-promotion fixture получена protected rename, не hard-kill между всеми init writes; T017/full crash acceptance остаются открытыми. T021 closure и передача следующему шагу требуют mandatory checks и завершённого fresh read-only review.

- [x] T082 Проверить реальный coordinator hard-kill на девяти init boundaries через test-only Dart VM debugger в `test/workspace_crash_test.dart`, `test/support/vm_debugger.dart`, `test/support/workspace_vm_child.dart`: exact paused script/line, отдельные own processes, bounded waits, fresh-process reopen, partial files/key/manifest сохранены, complete durable staging promoted, active reopened; no production failpoints. Начальная проверка выявила native lock `workspace.isar-lck`, который прежний код не создавал и не проверял: actual ACL regression дал PROTECTION_UNAVAILABLE. Исправить `workspace.dart`, `state_store.dart`, прежние native fixtures и закрепить exact native filenames в runtime-storage; не заменять это увеличением file count. После fix полный locald suite/mandatory checks/fresh independent review до принятия T017/T021 repository scope. Normal executable/auth/UI/reboot/other-user/full001.1 acceptance не покрыты.

### Initialization review follow-up

- [x] T083 Закрыть подтверждённое замечание `workspace_init_crash_review`: установить первичную native причину раннего STORAGE_BLOCKED, а не считать успешный повтор исправлением. Test-only VM tracing воспроизвёл UNSAFE_PATH до createProtectedEmptyFile; 160000 parallel probes дали 216 GetFileAttributes failures с потерянным GetLastError0, формальный regression дал 431 false rejection. В `packages/serverdeck_windows/lib/native_attributes.dart` и `paths.dart` получать NTSTATUS атомарно через NtQueryAttributesFile, принимать только OBJECT_NAME_NOT_FOUND/OBJECT_PATH_NOT_FOUND как отсутствие, блокировать остальные статусы и reparse; сохранить fixed-local-volume/root/ACL проверки. `test/path_concurrency_test.dart` обязан проходить без false rejection; actual junction tests обязаны блокировать запись. Test-only mutex child должен разделять startup и пятисекундный shutdown gate. Full Windows/locald suites, mandatory checks и fresh independent review обязательны; новый timeout fresh-process verification на manifest-flushed нельзя закрыть одним успешным повтором.

- [x] T084 Установить причину единственного timeout fresh verification на manifest-flushed после native path fix (полный suite32pass/1fail); повтор33pass сам по себе не закрывает этот gate. В test-only `vm_debugger.dart`/`workspace_crash_test.dart` получать safe source/pause diagnostics всех живых isolates при timeout, сохранять bounded waits, владение child processes и отсутствие production failpoints; воспроизвести и исправить подтверждённую причину либо собрать достаточные независимые evidence о границах проверки. До закрытия оставить T082/T017/T021 acceptance открытым. Полный001.1 native executable/auth/UI/reboot/other-user отдельно обязателен.

- [x] T085 Исправить подтверждённый P1 `native_path_status_review` в `packages/serverdeck_windows/lib/mutex.dart`: CreateMutex initialOwner=false, ownership только после WaitForSingleObject0→WAIT_OBJECT_0/WAIT_ABANDONED; WAIT_TIMEOUT→loser, остальные значения→OWNERSHIP_UNAVAILABLE. Не использовать TLS GetLastError для доказательства ownership; native acquire/release остаются на непрерывном worker native call stack, owner-only kernel ACL и bounded cleanup сохраняются. `test/mutex_ownership_test.dart`/`test/support/mutex_ownership_child.dart`: actual held owner, четыре concurrent child processes/4000 attempts, subsequent normal acquisition, hard-killed owner с retained safe native handle→abandoned acquisition и исключение нового contender. До fix actual production regression дал12 false owners/12 failed releases; после fix требуются zero false winners, actual normal/abandoned recovery, full Windows/locald suites/mandatory checks/fresh review. T084 cause отдельно не установлен.

- [x] T086 Исправить подтверждённый P1 `native_ownership_fix_review` в `packages/serverdeck_windows/lib/pipe.dart`: memory/event/OVERLAPPED каждого выданного I/O удерживаются до completion/cancel+drain независимо от потерянного TLS pending status. Безопасные probes дали75/80000 author и86/80000 reviewer ложных error!=997 при STATUS_PENDING. Actual owned-VM regression `test/pipe_pending_test.dart`/`test/support/pipe_pending_child.dart` до fix провалил read/write/connect с exit3 UNEXPECTED_IO_STATUS; после текущего fix targeted tests6 passed, включая4000 cancellations для каждого типа. Pending отмечается до API call, STATUS_PENDING fallback, failed completion сохраняет cancel/drain до finally. Общие checks и fresh review этого исправления ещё не выполнены. После уточнения пользователя T086 продолжить разрешёнными проверками и fresh review; только конкретный отклонённый системной защитой шаг оставить открытым.

- [x] T087 [P] [US1] После принятого root scaffold W01 подготовить независимую часть T032: `lib/theme/brand_theme.dart`, `lib/theme/brand_assets.dart`, root `pubspec.yaml` и подключение обеих тем к существующему unavailable scaffold в `lib/main.dart`. Существующий `docs/brandbook/tokens/serverdeck.tokens.json` — источник точных ролей цветов/типографики; никаких generated seed colors. Bundled Noto Sans400/600, Noto Sans Mono400, OFL и dark/light PNG logos из `assets/brand/`; source brandbook и Windows ICO сохраняются. Default ThemeMode.system соответствует001.1; persistence темы/reduceMotion остаётся T036 после LocalAPI. До ready остаётся только безопасное сообщение unavailable, без профилей/demo/service effects. Asset/token parity, actual Flutter asset bundle/font load, обе темы и смена platform brightness проверяются `test/theme/brand_theme_test.dart`; обязательные root format/analyze/flutter test, lychee и fresh read-only review этого UI increment. Этот шаг не запускает отложенные encryption/native acceptance tests и не закрывает T032 целиком/T031/T033–T050/Q12/full001.1.

- [x] T088 [P] [US1] После T087 подготовить presentation-only часть T033/T034 в `lib/shell/readiness_view.dart` и `test/widget/readiness_view_test.dart`. Компонент получает typed ReadinessState (кроме ready), safe ErrorCode? и nullable VoidCallback ручного retry, bool retryInProgress=false. Никаких private model/native/storage/bootstrap calls или локального таймера readiness; lifecycle/deadline остаются T031. Starting/recovering показывают ожидание; storageBlocked/incompatible/unavailable — локальную безопасную причину, stopping — завершение. Не передавать raw exception/native text. Reason переводится по allowlist ErrorCode в локализованный текст без input echo; неизвестное/непереданное значение не превращается в состояние удалённого сервера. Ready отвергается как неправильное использование отдельного pre-ready view; готовую модель показывает будущая оболочка T034. Retry виден только при non-null callback и terminal blocked/incompatible/unavailable; retryInProgress запрещает повтор и показывает ожидание текущей попытки. Это только визуальная защита, присоединение к живой попытке обеспечивает T031. Safe default unavailable в Main сохраняет исходный текст «Локальная служба ещё не реализована» и не показывает retry без реального controller. Центрированная прокручиваемая область, доступные текстовые состояния, Noto и brand colors обеих тем, retry target≥48logicalpx/видимый keyboard focus/Enter activation. Widget tests всех non-ready состояний, ready rejection, safe message mapping, retry callback/disabled/pending/no auto-retry, tab/focus, four Q12 viewports с textscale200% в обеих темах. Root format/analyze/Flutter test, lychee, fresh read-only review обязательны. Не закрывает T031/T033/T034/Q12/full001.1 и не запускает отложенный encryption/native блок.

- [x] T089 [P] Подготовить независимую часть T045 после W01 в `tools/collect-third-party-notices.ps1`, `tools/test-third-party-notices.ps1`, `docs/development/licenses/native/` и `docs/development/third-party-notices.md`: offline collector полных LICENSE/NOTICE/COPYING текстов hosted зависимостей из четырёх actual package configs/lockfiles, SDK Flutter/Dart/sky_engine и OFL; отдельно сохранить проверенные pinned Isar/libmdbx notices с source URL/hash/commit. Разные версии одного package не объединять; version/lock/source identity обязательна, отсутствующий/пустой license, расхождение версии, missing config/lock или changed pinned native text — ошибка до замены output. Output только внутри выбранного workspace, default build/foundation/notices; deterministic UTF8 `THIRD_PARTY_NOTICES.preview.txt` и inventory JSON без machine paths/credentials/timestamps. Native-chain incompleteness явно в header/JSON, final distribution THIRD_PARTY_NOTICES.txt не создаётся и build wiring не меняется. Принятые source refs не доказывают DLL provenance; T045 остаётся открытой до native dependency audit и actual complete bundle. Fixture tests own workspace temporary tree: deterministic runs, два resolved version одного package, полный text/hash/count, mismatch/missing-license preserves previous output, outside output rejected. Actual source collection, PowerShell parse/tests, lychee и fresh readonly review обязательны. Не запускает отложенные encryption/native acceptance.

- [x] T090 Исправить подтверждённый P2 notices_collection_code_review в T089: проверить оба конечных output paths до первой записи, отклонить reparse points/каталоги; записывать новые regular temporary files через CreateNew и заменять directory entries, не изменяя внешний hardlink alias. Owned fixture container содержит selected workspace и внешний marker; actual hardlink regression для обоих результатов, destination junction rejection до первой записи, marker/предыдущий preview сохранены. Повторить source fixtures/actual collection/PowerShell parse/lychee/fresh review. Это не native/security acceptance и не закрывает T045.

- [x] T091 Исправить подтверждённый P2 verifier_port_diagnostics_review в test-only `vm_debugger.dart`/`workspace_crash_test.dart`: diagnostic RPC failure не заменяет исходный verifier timeout и не скрывает safe lifecycle log; ошибки независимых getIsolate/getPorts/getStack не стирают доступные части snapshot, недоступная часть обозначается фиксированным маркером без raw error/port payload. Сохранить20second RPC bounds, concurrent collection, source-frame limit и production deadlines. Focused WebSocket regression: stack error плюс неотвечающий worker, partial main snapshot сохранён, завершение bounded; getVM failure сохраняет original exception/log и исключает endpoint URL. Повторить mandatory checks/full locald suite/fresh readonly review. T084 причина и T082/T017/T021/full001.1 отдельно открыты.

- [x] T092 Расширить test-only диагностику T084 в `vm_debugger.dart`, `workspace_crash_test.dart`, `vm_debugger_test.dart`: получать только VM allocationLocation StackTrace для максимум четырёх live ReceivePorts, максимум три подходящих source frames на порт, concurrent fetch с отдельным2second RPC bound, без port fields/handlers/messages/locals и raw error payload. Сохранить предыдущие partial snapshots/original verifier timeout/log. Контролируемый staging-created main snapshot должен показать реальные MutexLease.acquire source locations. Историческая гипотеза stdin-first: первоначальный probe12ownedchild processes с открытым parent stdin прошёл у автора, но упал у independent reviewer с Socket Event Handler port после main return; эта проверка и её отрицательная evidence сохранены в evidence, прежний критерий open-stdin superseded исправлением T093. Действующий `stdin_gate_test.dart`/`support/stdin_gate_child.dart` проверяет complete one-command protocol start→flush→EOF, single через EOF, подключённый debugger и natural exit0 за2seconds для12ownedchildren; cleanup только своих PID. Passing probe не устанавливает причину исторического сбоя и не закрывает T084. При воспроизведении timeout сохранить allocation evidence и установить подтверждённую причину до закрытия T084. Mandatory checks/fresh review обязательны.

- [x] T093 Исправить подтверждённый P2 live_port_allocation_diagnostics_review: isolated stdin-first probe нестабилен, после return main держит Socket Event Handler port; прежний cleanup закрывал stdin и сразу kill, не проверяя natural exit. В `workspace_crash_test.dart` отправлять единственную start-команду, flush и EOF обоим owned children; `workspace_vm_child.dart` читает single до EOF вместо отмены подписки через first. `stdin_gate_test.dart`/`support/stdin_gate_child.dart` проверяют тот же complete one-command protocol и natural exit с живым debugger, без kill/увеличения deadline; kill разрешён только cleanup уже упавшего owned child. Сохранить отрицательную reviewer evidence и отсутствие доказанного владельца historical T084 port; протокольное исправление не выдавать за установленный native mutex/storage defect. Повторить isolated+crash/full checks и fresh review, не закрывать T084 одним green повтором.

- [x] T094 Исправить подтверждённый P2 stdin_protocol_allocation_fixed_review: явно обозначить исходный stdin-first/open-parent probe T092 как historical evidence, его старый критерий superseded T093; действующие T092/T093 требуют start→flush→EOF, single через EOF, живой debugger и natural exit0 за2seconds для12ownedchildren. Сохранить отрицательный reviewer run и открытый historical T084, не закрывать старый критерий новым green test. Проверить links и повторить fresh independent review после поправки критериев.

- [x] T095 Дополнить repository-часть T016 отдельным `credential_lifecycle_test.dart` и owned native fixture: восемь durable snapshots с close/reopen после каждого commit — create без credential revision1, replace password revision2, remove revision3, replace privateKey/passphrase revision4, replace непустой записи новым ID revision5, keep при изменении name/tags, selection и atomic selected-profile delete. Проверить точные native credential IDs/count после каждого reopen, отсутствие orphan rows, сохранность секретных строк без NFC/trim/CRLF conversion, неизменность blob/record при keep, settings revision/reset и receipts. Fixture подаёт заранее построенные snapshots в StateStore и не подменяет проверку generation случайных IDs, CAS/CRUD/coordinator: полная T016 и W04 остаются открытыми до T024/T025. Только synthetic secrets и принадлежащие тесту PID/каталоги; mandatory checks и fresh review перед закрытием.

- [x] T096 Выполнить consolidation audit T084 по исходному разрешённому пути «достаточные независимые evidence о границах проверки» в `docs/development/workspace-recovery-audit.md`: сохранить historical failures/неустановленную причину, сопоставить все девять real hard-kill boundaries с fresh verifier outcome/preservation/natural exit, текущие исправления и завершённые scoped reviews. Повторить full Windows/locald suites и передать свежему независимому reviewer actual logs и исходные критерии T082/T084/T017/T021. Не менять deadline/ожидаемый результат, не считать один green repeat достаточным, не закрывать full001.1/reboot/other-user/compiled-service gates. По результату completed review определить допустимость closure только native coordinator/repository initialization scope; подтверждённые findings исправить с checks/fresh review до clean.

- [x] T097 Реализовать и проверить основной serial mutation increment T022–T025 в `profiles/validation.dart`, `profiles/service.dart`, `profiles/settings_service.dart`, `profiles/mutation_coordinator.dart`, `credentials/provider.dart`, `storage/key_custody.dart` и `test/mutations_test.dart`/owned `support/mutations.dart`. Pure validation + bounded owned input + synchronous receipt HMAC + inflight registration до первого async wait; CAS/create/update/delete/settings, новый CSPRNG credentialId на replace, atomic receipt/state, replay/reopen, no secret readback, queue32, duplicate requester, queued cancellation/retry, running disconnect, protection failure/storage-blocked reads. Compiled interface stub должен дать реальный red, затем native green. Это основной increment, а не закрытие полных T016/T022–T025: ещё проверить logical profiles250/receipts10000, coordinator-level native map-full rollback/unknown commit failure, граничные revisions и shutdown draining; service transport/auth/UI остаются следующие задачи. Mandatory checks и fresh review с исправлениями обязательны до закрытия increment.

- [x] T098 Исправить P2 serial_mutations_core_review: backward wall-clock adjustment создаёт updatedAt<createdAt и ложный storage-blocked либо более ранний committedAt при revision-desc recent, нарушая shared wire validator. Закрепить persisted timestamp floor в data-model; выбирать millisecond UTC max wall clock/Receipt.committedAt/Profile.updatedAt, equal timestamps допустимы, storeRevision сохраняет commit order. Внутренний clock dependency без runtime flags нужен для deterministic regression profile update и settings/recent после reopen. Дать red на текущем необработанном clock, затем green, сохранить evidence; повторить mandatory checks и fresh review. Не выдавать logical timestamp за elapsed timer/точные physical часы.

### Parallel examples (только US1 в этом scope)

- После T002: T003 lints, T004 build scripts, T005 fixture harness skeleton — разные файлы.
- После T007: T008 protocol tests, T010 security tests, T012 pipe tests — разные suites.
- После T015: T016 models/lifecycle tests и T017 crypto/init tests.
- После T021: T022 mutation tests и T026 auth/bootstrap tests; последующая интеграция T029 ждёт обе реализации.
- После T031: T032 themes/assets и T033 widget assertions — раздельные файлы.
- Исключение подготовки после пользовательского откладывания storage2026-10-11: T087 themes/assets не использует locald/storage и может выполняться после W01; рабочая UI/service integration по-прежнему ждёт T031. Незавершённые T016–T021/T082–T086 остаются открытыми до evidence, но больше не отложены целиком; выполненная T020 сохраняется.
- T088 готовит только pre-ready presentation после T087; реальная readiness/retry интеграция и полная оболочка по-прежнему ждут T031.
- T089 только собирает существующие license texts после W01; это независимая подготовка T045, не acceptance или packaging полной001.1.

US2/US3 parallel examples отсутствуют: это следующие этапы, их Tasks здесь не создаются.

## Traceability

| FR stage001.1 | W/design → tasks | Приёмка |
| --- | --- | --- |
| FR-001 | W03/W06 → T020,T034–T038,T048 | AC-SVC-1A; Q01/Q09 |
| FR-002 | W05/W06 → T015,T029,T034,T039 | AC-002-1B; Q04/Q11 |
| FR-007 | W04/W06 → T018,T023–T025,T035–T038 | AC-SVC-1A/1C; Q09 |
| FR-012 | W05/W06 → T030,T034,T037,T041 | AC-002-1B/1C; Q10/Q11; remote resilience сама только001.2 |
| FR-014 | W04/W06 → T018,T024,T034,T038 | AC-002-1A; Q01/Q09 |
| FR-121 | W02/W03/W04 → T011,T019,T024,T039–T040,T048 | AC-SVC-1B/BOOT; Q05/Q06/Q08 |
| FR-122 | W03 → T018–T021,T039–T040,T048 | AC-SVC-1B/BOOT; Q05/Q06/Q08 |
| FR-123 | W05/W06 → T014–T015,T029,T040,T045–T048 | AC-002-1B; Q05/Q11; intentional export вне001.1 |
| FR-002-LOCAL-01 | W04 → T007,T018,T023–T024,T035,T038 | AC-SVC-1A; Q09 |
| FR-002-LOCAL-02 | W03/W04/W06 → T018,T024,T034,T038,T041 | AC-002-1A; Q01/Q09/Q10 |
| FR-002-LOCAL-03 | W04 → T018,T024–T025,T036,T038 | AC-SVC-1C; Q09; trust/jobs guards при появлении001.2/001.3 |
| FR-SVC-001 | W01 → T001–T004,T027,T031,T038,T043,T048 | AC-SVC-1A; Q01/Q02; SSH gate только001.2 |
| FR-SVC-002 | W01/W02 → T007,T015,T029–T031,T038 | AC-SVC-1A; Q01/Q05 |
| FR-SVC-003 | W02 → T013,T021,T026–T027,T031,T038 | AC-SVC-1A/BOOT; Q02/Q11 |
| FR-SVC-004 | W02/W05 → T008–T013,T026,T028–T030,T039 | AC-SVC-1B; Q03/Q04 |
| FR-SVC-005 | W05 → T027–T031,T034,T039,T048 | AC-SVC-BOOT; Q01/Q06/Q11 |
| FR-SVC-006 | W02 → T011,T021,T027,T031,T039–T040 | AC-SVC-1B/BOOT; Q04/Q06/Q08 |
| FR-SVC-007 | W03 → T018–T021,T039–T040,T048 | AC-SVC-1B/BOOT; Q05/Q06/Q08 |
| FR-SVC-015 | W04 → T022,T025,T029–T030,T037–T038,T041 | AC-SVC-1C/AC-002-1C; Q07/Q10 |
| FR-SVC-016 | W05 → T014,T027,T029,T034,T037,T039–T040 | AC-002-1B; Q05/Q11 |
| FR-SVC-017 | W01 → T001,T015,T029,T034,T038 | AC-SVC-1A; Q01/Q04 |
| FR-SVC-018 | W06 → T032–T037,T042 | AC-SVC-1A/AC-002-1B; Q01/Q11/Q12 |
| FR-SVC-019 | W01 → T002,T004,T027,T031,T043,T046–T048 | AC-SVC-1A; Q01/Q02 |

| Q / AC | Реализуемые probes | Evidence gate |
| --- | --- | --- |
| Q01/Q02 | T026,T031,T033–T034,T038 | T047–T050 |
| Q03/Q04 | T008,T010–T015,T026,T028–T029,T039 | T047–T050 |
| Q05/Q06/Q08 | T010,T016–T021,T039–T040 | T047–T050 включая native reboot/other-user |
| Q07/Q09 | T016,T022–T025,T033,T035–T038 | T047–T050 |
| Q10/Q11 | T022,T026,T030–T031,T037–T038,T041 | T047–T050 |
| Q12 | T032–T037,T042 | T047–T050 |
| AC-SVC-1A/1B/1C/BOOT; AC-002-1A/1B/1C | Все Q по [UI mapping](contracts/ui-validation.md) | T050 требует все семь, не выборку |
| SC-SVC-001/004/005/008; SC-002-LOCAL-01–04 | Buildable checks readiness/privacy/concurrency/UI/native/review | T038–T050, только scope001.1 |

Каждая задача относится к W01–W07; номера W не replaced Tasks. FR/AC/SC остальных этапов не считаются покрытыми этим tasks.md.

## Implementation strategy

- [x] T111 Исправить P2 channel_transport_drain_review: `serverdeck_windows/lib/pipe_worker.dart` допускает управляющий disconnect независимо от трёх pending read/write/drain, coalesces repeated disconnect и не допускает ordinary I/O до подтверждённого drain. Ordinary quota3 сохраняется; успешный disconnect разрешает accept/reuse, failed teardown не выдаётся за reuse. Native owned child `test/pipe_worker_teardown_test.dart`/`support/pipe_worker_teardown_child.dart`: real pending read+1MiB backpressured write+drain, fourth ordinary RESOURCE_LIMIT, owner disconnect cancels all three, duplicate shares completion, during teardown ordinary SERVICE_UNAVAILABLE, same slot reused. Actual RESOURCE_LIMIT red→green, обязательные full checks и fresh review; T108/T109/T110 открыты до supported conclusion.

- [x] T110 Исправить actual native immediate-failure deadlock в `serverdeck_windows/lib/pipe.dart`: ERROR_PIPE_NOT_CONNECTED233 при ReadFile может оставить provisional OVERLAPPED.Internal=STATUS_PENDING, но I/O не queued; не ждать unsignaled event в finally. Known fatal native error имеет приоритет, fallback Internal используется только при lost zero last-error; pending997 cancellation/buffer retention сохраняется. Owned child `test/pipe_disconnected_test.dart`/`support/pipe_disconnected_child.dart` bounded15s red→green, disconnected read безопасно завершается; native output drain timeout/retained bytes/reuse/duplicate drain/cancel tests. Mandatory full Windows/locald/root checks и fresh review до closure.

- [x] T109 Проверить и исправить доставку session.close reply при delayed client read: native DisconnectNamedPipe отбрасывает unread output, поэтому write completion не доказывает доставку. Подтвердить actual regression на owned PipeWorker без ожидания server completion до чтения (такой порядок может сам блокировать graceful drain), обеспечить bounded native delivery/drain до disconnect без блокирования owner/UI isolate и без неограниченного ожидания чужого клиента. Добавить delayed-read/abandoned-client/native cancellation/reuse проверки, mandatory checks и fresh review. T108 не закрывать до подтверждённого решения; existing session.close contract сохраняется, никакие secrets/production processes не затрагивать.

- [x] T108 Подключить accepted-connection transport для T026/T027/T028 в `packages/serverdeck_locald/lib/api/channel.dart`: реальные framed read/write callbacks из owned PipeWorker, общий handshake deadline5s, partial frame deadline5s без обновления от фрагментов, strict header/size/EOF, authenticated dispatch, serialized writer и bounded16 active responses/backpressure, close reply перед disconnect, revoke/cancel/drain при framing/auth/I/O failure или owner close. Unit `test/channel_test.dart` и native `test/channel_native_test.dart`/`support/channel_scenarios.dart` через repository channel mode: actual kernel peer в обе стороны/повторно перед grant, proof, fragmented/coalesced byte-mode I/O, coordinator/Isar/DPAPI save/replay/status/privacy/close. Red compiled stub→green; mandatory checks и fresh review. Этот increment не закрывает entry/bootstrap/eight-slot accept/reuse, full lifecycle ownership/client/UI/Q01–Q12; не выдавать synthetic approved test executable за production manifest wiring.

- [x] T107 Подключить все Local API methods T029 в `api/server.dart`: bounded strict request/envelope, channel/session/cap до business validation, ready-only gates, sync inflight admission до первого await, safe projected responses/errors, pending accounting/finally и session.close reply+closeChannel disposition. Unit `test/api_test.dart` exhaustive method/cap/readiness/error/limit boundaries; native `test/api_native_test.dart`/`support/api_scenarios.dart` actual coordinator/Isar/DPAPI CRUD/settings/CAS/replay/status/recent/delete/privacy/blocked reads, harness api mode. Реальный red stub→green, mandatory checks/fresh review; transport обязан закрыть invalid frame/auth channel без echo, написать close reply прежде disconnect. T029 целиком закрывать только при поддержанном review scope; T027 transport/entry/client/fullstage отдельно открыты.

- [x] T106 Исправить P2 discovery_binding_corrected_review: сериализовать весь read→validate→protect→replace/remove по canonical discovery path для всех publisher instances, не по отдельному объекту. Общий drained учитывает очередь этого пути; завершённые queue entries освобождаются. Native overlapping regression с held DPAPI protect первой A и второй B через другой экземпляр должен показать actual red обе успешны, затем green A commit/B STORAGE_BLOCKED без смены established binding. Mandatory checks и fresh review; T104/T105 остаются открытыми.

- [x] T105 Исправить P2 discovery_custody_publication_review: same-generation publication после known workspace A не может вернуть null/B. На границе publish прочитать/DPAPI-validate существующий protected descriptor под matching mutex, сохранить established workspace/token/build/PID binding для same generation; отклонение без изменения файла. Restart новой generation может заменить valid stale discovery другой build, но owner inspection не выдаётся за client verification. Native regressions A→null/A→B, новый publisher object, разрешённая new generation/build replacement; real red→green, mandatory checks/fresh review до closure. T104 остаётся открытой.

- [x] T104 Реализовать обязательную discovery-часть T027: `bootstrap/discovery.dart` и `bootstrap/discovery_file.dart`, strict schema/namespace/DPAPI CurrentUser/bootstrap token ownership, generation/token rotation и same-generation workspaceId promotion, atomic protected publication/serialized removal только под held matching mutex. `serverdeck_windows/lib/mutex.dart` сохраняет имя acquired lease для namespace binding. Tests `test/discovery_test.dart`/`test/discovery_file_test.dart` проверяют real DPAPI entropy/build/fields/limits, owner vs loser, actual protected file update, close-owned snapshot и generation-bound removal. Red compiled stub→green, mandatory checks и fresh review до закрытия. Whole T027 entry/native pipes/bootstrap/watchdog/UI integration остаётся открытой; fixture runtime path принадлежит тесту, production namespace/workspace не изменяется.

- [x] T103 Исправить P2 lifecycle_scheduler_drain_review: после explicit disconnect последней session и задержки timer новая register на/после grace deadline не должна стирать `_graceAt` и оживлять generation. До отмены grace проверить старый deadline; post-notification guard register должен вернуть NOT_READY/no grant. Добавить deterministic regression до/ровно/после 2s со scheduler callback, который ещё не выполнился; получить red на текущем коде, затем green, все mandatory checks и fresh review до clean. T102 остаётся открытой до исправления.

- [x] T102 Подключить внутренний lifecycle scheduler T026/T028 в `bootstrap/lifecycle.dart`, notifications/deadlines `api/sessions.dart`, unit `test/lifecycle_test.dart` и native `test/lifecycle_native_test.dart`/`support/service_lifecycle.dart`. Monotonic lease60/watchdog30/grace2, один Timer без polling, grant отменяет grace только до deadline, late grant/bootstrap не обходят watchdog, delayed expiry сохраняет original grace deadline. Teardown revoke/cancel→drain→Isar→pipes→discovery→keys→mutex, idempotent completion; неизвестный close failure останавливает цепочку/не release mutex, safe STORAGE_BLOCKED. Native owned coordinator/store/key/mutex fixture доказывает running commit, queued cancellation, DPAPI/reopen после release; pipes/discovery callbacks там явно fixture noops, не full transport acceptance. Compiled red→green, mandatory checks и fresh review до closure; полные T026/T027/T028/router/client/UI/001.1 ещё открыты.

- [x] T101 Реализовать внутренний handshake/session increment T026/T028 в `api/auth.dart`, `api/sessions.dart` и `test/auth_test.dart`, `test/auth_sessions_test.dart`, `test/auth_native_test.dart`: exact HMAC transcript, bounded frame/allowlisted grants, single-use challenge, две mandatory peer checks, 5s deadline/close race, owned token/clearing, channel/generation binding, max8 sessions/max16 pending, monotonic lease60s/revocation/idempotent request completion. Native owned pipe проверяет реальный kernel peer SID/image/hash; unit callbacks не выдавать за весь native journey. Compiled stubs должны дать real red, затем green, mandatory checks и fresh review. Полные T026/T028 остаются открытыми до transport/session expiry scheduler/lease-grace/drain integration; T027 bootstrap/discovery/ready и UI не закрывать этим increment.

- [x] T100 Дополнить native coordinator acceptance в `test/support/mutations.dart` реальными create-with-credential revision1, name/tags keep, address/port/user connection+trust revisions, unchanged update, remove пустого доступа, одинаковыми повторными replace с новым credentialId/record timestamp, owned deep input, конкурентными profile/settings CAS и invalid settings selection. Проверить durable reopen canonically, без зависимости от порядка JSON fields. После mandatory checks передать fresh reviewer полную цепочку внутренних T016/T018/T019/T022–T025 и накопленное evidence T095/T097–T099; закрывать исходные задачи только при поддержанном scoped conclusion, не full001.1/transport/auth/UI/native reboot/other-user.

- [x] T099 Проверить оставшиеся границы внутреннего mutation coordinator через `test/mutations_boundary_test.dart` и owned `support/mutation_boundaries.dart`: profiles250/251, валидированный baseline10000 receipts с replay без eviction, uint63 CAS/nextRevision, shutdown queued cancellation/running drain, реальный native map-full rollback/readability/reopen, exhausted native IDs и uncertain native commit failure с fresh-process durable verification. Baseline receipt quota не выдавать за 10000 выполненных API mutations; injected native failure не называть отказом системы защиты. Mandatory checks и fresh read-only review до закрытия increment; full001.1/transport/auth/UI остаются отдельными gates.

Первый внутренний MVP — Setup+Foundation+T016–T037: запустить настоящий защищённый сервис и сохранить профиль из UI. Проверить эту вертикаль до расширений. Полный US1/этап001.1 принимается только после сквозных probes и T043–T050; промежуточный UI или mock не закрывает требования. Один этап — один MR либо ранее согласованная меньшая часть, не автоматический merge. После реализации обязательны actual checks/native acceptance/fresh code review; создание этого списка их не заменяет.

- [x] T112 Сохранить общий startup deadline T026/T027/T028 при позднем создании lifecycle: `bootstrap/lifecycle.dart` принимает абсолютный `startupDeadlineAt` в той же monotonic clock шкале, не разрешает отрицательный срок или продление бюджета30s; истёкший срок сразу запускает ordered close и запрещает readiness/grants. `test/lifecycle_test.dart` проверяет создание на29s, expiry30s, уже истёкший deadline и invalid budgets. Owner entry должен передать срок от начала процесса; wiring остаётся частью открытого T027. Red отсутствующий parameter → targeted green13; обязательные checks и fresh review до закрытия.
- [x] T113 Подключить fixed production launch contract T027: `bootstrap/entry.dart` и `bin/locald.dart` принимают только workspace default/app-root absolute, отвергают extra/duplicate/missing/secret/test overrides, читают системный LOCALAPPDATA, проверяют bundle/native prerequisites и actual retained process SID/image/hash против locald.exe в manifest. `test/entry_test.dart` проверяет strict argv; `test/entry_native_test.dart` запускает реальный child и проверяет unapproved executable при valid bundle, safe argv errors/no echo. Native regression выявила загрузку DLL до self-image check: `native_runtime.dart` выделяет `verifyBuildBundle` без загрузки, entry сначала сверяет self, затем вызывает native initialize. Compiled approved production entry/startup watchdog/owner composition остаются T027. На раннем boundary до owner composition executable выдавал только безопасный SERVICE_UNAVAILABLE, без ready/namespace/private writes; production owner затем реализован T114, compiled valid/invalid preflight принят T118/T119. Выполнить checks/fresh review boundary и отдельную compiled valid/invalid bundle/native preflight приёмку вместе с T027; whole T027 не закрывать unit parser tests.
- [x] T114 Реализовать owner composition T026/T027/T028 в `bootstrap/bootstrap.dart` и production `bin/locald.dart`: process-entry monotonic clock/deadline, matching mutex winner/loser, verified live peer probe без grant обхода, protected runtime и восемь owned workers, accept/reuse + approved UI peer/handshake/channel/router, discovery null→verified workspaceId, actual Workspace/MutationCoordinator/readiness, failure readiness и ordered cancel/startup drain→mutations→Isar→pipes/listeners→discovery→keys→mutex. `Workspace.open` cooperative checkStartup между операциями и hasOpenReservation предотвращают release при неудачном native close; token snapshots очищаются. SessionRegistry/lifecycle expiry callback закрывает конкретный канал, explicit close сохраняет reply delivery. `test/bootstrap_native_test.dart` компилирует два реальных fixture executable, использует owned temp LOCALAPPDATA и approved manifest hashes, проверяет handshake/server proof/ready/profiles list/close/discovery removal/Isar reopen/same workspace/new generation в двух starts; console fixture client не production Flutter UI. `test/auth_sessions_test.dart` различает expiry/explicit disconnect/stop. Initial compile failed nullable test descriptor; исправлено, targeted3green11s. Mandatory full checks/fresh review перед acceptance. Full contender/abandoned/deadline/failure/native drain/client/UI matrix остаётся обязательной T026/T027/T028: не закрывать её этим happy-path fixture. T113 approved compiled self process теперь покрывается этим fixture, но invalid compiled bundle variations ещё проверить.
- [x] T115 Исправить confirmed P1 bootstrap_resource_owner_review: StateStore.hasOpenReservation передаёт retained native-open reservation через Workspace.hasOpenReservation/requireNoOpenReservation в owner closeStorage. Failed nested StateStore.open до передачи store наружу не освобождает mutex при false/exception native close; native_close.confirmNativeClose трактует оба исхода как неподтверждённое закрытие. `test/native_close_test.dart` проверяет true/false/exception; real repository mode open-close-failure создаёт valid protected workspace/credential, test-only protection закрывает native instance перед credential failure и поэтому cleanup получает false, затем проверяются retained aggregate reservation, ordered close остановлен на storage и lease всё ещё held. Это моделирование false-result, не заявление о реальном leaked handle: fixture cleanup знает, что Isar уже закрыт. Первая regression попытка имела неправильный ACL parent при fixture move; исправлен fixture сразу в protected production layout. Targeted17green12s включая compiled owner/reopen. Mandatory checks/fresh review до acceptance.
- [x] T116 Исправить confirmed P2 bootstrap_resource_owner_review: lifecycle.checkStartupDeadline фиксирует TIMEOUT перед ordered close, даже если delayed watchdog callback ещё не выполнен; owner вызывает его в cooperative checks и при deadline в catch (включая mapped Workspace STORAGE_BLOCKED). Deterministic manual-clock test при30s без timer wake проверяет TIMEOUT, revoke, exact ordered teardown и отсутствие повторной cleanup. Targeted17green12s; mandatory checks/fresh review до acceptance. Полный native startup/deadline/failure matrix T026/T027/T028 остаётся открытым.
- [x] T117 Исправить confirmed P2 bootstrap_owner_fixed_review: fatal reusable listener path перед teardown вызывает lifecycle.close(reason:SERVICE_UNAVAILABLE); waitForExit ожидает реальную cleanup и сохраняет operational failure для production entry/nonzero exit. Idempotent close не заменяет ранее записанную причину, cleanup failure приоритетно STORAGE_BLOCKED. `test/lifecycle_test.dart` deterministic fatal listener reason→ordered teardown→error completion (включая failing storage/no release) и обычный grace→success; compiled owner normal two-start journey остаётся зелёным. Mandatory full checks/fresh review до acceptance; whole native fault/contender/deadline/expiry/drain и UI stage gates открыты.
- [x] T118 Дополнить compiled production bootstrap acceptance T113/T026/T027 в `test/bootstrap_native_test.dart` и `test/support/bootstrap_client.dart`: при активном authenticated client второй locald с отдельным owned LOCALAPPDATA должен завершиться без записи, без изменения discovery владельца и без отзыва действующей session. Проверить compiled entry с testOnly/invalid buildId/wrong appRoot/DLL hash manifest и отсутствующей DLL: safe INCOMPATIBLE либо PREREQUISITE_UNAVAILABLE, empty stdout, unchanged snapshot всех persisted files, discovery отсутствует после shutdown. Targeted actual compiled test прошёл (1 test,12s); mandatory full checks и fresh independent review до acceptance. Console test peer не Flutter UI; abandoned/startup deadline/lease expiry/native fault/full stage gates остаются открытыми.
- [x] T119 Исправить confirmed P2 bootstrap_contender_preflight_review: exitCode compiled peer не доказывает EOF stdout. Сохранить ready marker early observation, отдельно дождаться onDone с bounded timeout и обработкой onError до формирования ProcessResult; cancel subscription только как cleanup. Повторить mandatory checks/fresh review перед закрытием T118/T113; production behavior не изменяется.
- [x] T120 Проверить реальные сроки production owner T026/T027/T028 в compiled fixture: старт без клиента завершается TIMEOUT/nonzero после watchdog30s, discovery удалён; следующий approved клиент открывает тот же workspace с новой generation. Отдельный authenticated peer прекращает RPC/heartbeat, ждёт EOF/disconnect около lease60s, owner естественно завершает grace2s и удаляет discovery. Stopwatch/timeout assertions имеют явно ограниченный запас на native cleanup и scheduling; production deadlines не сокращать ради теста. Mandatory checks/fresh review перед acceptance. Console peer не UI; abandoned/native fault/commit shutdown/fullstage матрица остаётся открытой.
- [x] T121 Исправить реальную regression T120: idle production listener через5s получает ERROR_OPERATION_ABORTED995 без собственного timeout и owner завершается SERVICE_UNAVAILABLE до watchdog. Windows отменяет I/O при завершении issuing OS thread; обычный async Dart isolate не закрепляет thread. В NativePipe каждая I/O issuance→native wait→completion/cancel-drain выполняется на одном uninterrupted native call stack через bounded Isolate.run; controller остаётся async. Per-operation cancellation event покрывает close/deadline до issuance и после неё; buffer/event free только после actual completion. Попытка experimental group-bound event-loop host не прошла SDK/runtime проверки и удалена; новый DLL/runtime dependency не требуется. Добавить native accept/read idle дольше5s с последующим успешным обменом и cleanup; подтвердить watchdog30/lease60 compiled journey, удалить временную диагностику, обязательные root/locald/Windows checks и fresh review.
- [x] T122 Сохранить native reuse regression при async issuance T121: fixture `serverdeck_windows/test/support/pipe_disconnected_child.dart` делает bounded connect retry до начала async accept на reused slot, не считает вызов accept доказательством native issuance. `test/pipe_disconnected_test.dart` ждёт stdout EOF перед marker assertions. Подтвердить прежние immediate disconnected read failure, drain timeout/retained bytes/reuse/duplicate drain/cancel, не ослабляя production thresholds. Первый concurrent full Windows/locald run выявил kernel-service Out of memory и fixture busy race; suites повторить полностью последовательно с bounded test concurrency, recorded failures не выдавать за system denial. Mandatory checks/fresh review до acceptance.
- [x] T123 Исправить подтверждённое зависание accept в native cancellation stress после T121: diagnostic four-worker fixture показал остановку перед accepted, хотя остальные циклы завершились. BOOL+отдельный TLS GetLastError неоднозначны для уже подключённого pipe; прямые leaf calls/warmup не закрыли regression и удалены. Typed NtFsControlFile(FSCTL_PIPE_LISTEN)/NtReadFile/NtWriteFile возвращают NTSTATUS в том же syscall: STATUS_PENDING только для реально queued I/O, STATUS_PIPE_CONNECTED — immediate accepted; known failure не ждёт несуществующий event. IO_STATUS_BLOCK layout совпадает с Internal/InternalHigh OVERLAPPED; completion event/bytes/status проверять до free, cancel-drain прежние. Mandatory checks/4000 workload каждого kind/fresh review до acceptance; temporary diagnostic child удалить, failures/terminated diagnostics не выдавать за clean checks.
- [x] T124 Исправить конфликт native fixtures после расширения bootstrap journey: discovery_file_test и compiled bootstrap используют один canonical SID/default mutex; concurrency2 позволяла discovery fixture получить loser lease и упасть, пока production owner выполняет реальные30/60s. Закрепить package `dart_test.yaml` concurrency1 для обычного dart test/CI; внутри fixtures actual contender/requester concurrency сохраняется. Повторить весь locald suite, checks/fresh review; не вводить test namespace override в production launch contract.
- [x] T125 Исправить P1 native_io_thread_lifetime_review: NT syscall может вернуть STATUS_PENDING, не записав IOSB до completion. Перед issuance установить IOSB.Status=STATUS_PENDING, чтобы GetOverlappedResult(bWait:true) действительно дождался cancel completion; решение queued/immediate по-прежнему принимает только возвращённый NTSTATUS. Native regression в pipe_test.dart подтверждает queued read успешным CancelIoEx при отсутствии peer writes, ожидает terminal future и проверяет повторный обмен на том же pipe в100 циклах. Mandatory checks и fresh review до закрытия; этот regression не обещает детерминированного воспроизведения use-after-free.
- [x] T126 Исправить P2 native_io_cancel_completion_fixed_review: новая queued-read regression дважды упала в independent runs из-за false CancelIoEx/error0 вместо1168. Wrapper получает BOOL и GetLastError отдельными non-leaf calls, поэтому тест не классифицирует TLS error: retry false только до5s, обязательно получить successful BOOL, дождаться terminal read и проверить reuse100 cycles. Persistent false остаётся failure; это не system denial и не production fix. Повторить root/Windows mandatory checks, lychee и fresh review; locald production и fixture не меняются после green84 T125.
- [x] T127 Добавить actual compiled abandoned-owner recovery T026/T027/T028: approved console peer подтверждает durable profile+receipt, parent завершает только собственный locald child с проверенным fixture layout. Test-only Windows observer OpenMutex/query удерживает объект без wait/acquire, доказывает abandoned после смерти owner и held/non-abandoned после replacement. Stale DPAPI discovery сохраняется после crash; новый production owner готовит тот же workspace, новый generation/token, новый peer handshake читает прежний profile/committed receipt. Observer не входит runtime bundle, не меняет production namespace/ACL и не расходует abandoned acquisition. Scoped test не подменяет mid-commit/reboot/other-user/full UI acceptance. Mandatory checks и fresh review до closure.
- [x] T128 Актуализировать текущий Status tasks.md: прежнее описание public locald как scaffold/SERVICE_UNAVAILABLE устарело после accepted T114–T126. Указать actual production owner/API и compiled console evidence, сохранив открытыми полные T026–T028/client/UI/native/release gates и всю completed task history. Lychee/fresh review вместе с T127 до closure.
- [x] T129 Исправить confirmed P2 compiled_abandoned_owner_recovery_review: replacement открывает listeners до новой discovery публикации, console peer мог открыть новую pipe со stale descriptor и упасть на generation mismatch вне retry. В owner-recovery fixture parent до запуска recover peer bounded25s ждёт actual DPAPI descriptor с новой generation и PID своего replacement child; каждый snapshot закрывается, проверка доверия не обходится/ошибки read не скрываются. После crash прежние bytes/abandoned и после replacement сохранённые profile/receipt/new token всё ещё проверяются. Это синхронизация owner acceptance; UI stale-descriptor retry остаётся обязательной T030/T031 и этим сценарием не покрывается. Повторить mandatory checks и fresh review до closure.
- [x] T130 Дополнить compiled production owner failure matrix T026–T028: после committed profile/receipt повредить только owned fixture manifest JSON/schema, receipt-key DPAPI wrapper или native DB pages; approved peer подтверждает terminal storage-blocked/incompatible/reason/null workspace identity, ping/readiness/close работают, все9 ordinary методов отклонены safe correlated error без effect/empty/not-found. Owner завершается nonzero с safe reason, discovery удалён, все workspace files сохраняют damaged snapshot без reset/rekey/writable-open. Только после exit fixture восстанавливает original bytes, отдельный normal start читает прежний profile/committed receipt. Настоящие syscall/DPAPI/entry, не production failpoints и не UI/reboot/fullstage acceptance. Mandatory checks и fresh review до closure.
- [x] T131 Уточнить существующий runtime readiness guard по Local API/T029 implementation: ordinary starting/recovering/stopping/unavailable →NOT_READY, storage-blocked →STORAGE_BLOCKED, incompatible→INCOMPATIBLE; capability до state guard, semantic params/backend только ready. Прежнее blanket ordinary NOT_READY противоречило закреплённым safe terminal reasons и текущему dispatcher. Это явная фиксация принятого поведения, не новая схема ошибок; T130 подтверждает terminal guards native journey. Lychee/fresh review до closure.

- [x] T132 Расширить compiled production auth acceptance T026/T028: при живой approved session отдельные approved console peers отправляют неверный proof, несовместимый clientBuildId и запрещённую capability; каждый канал закрыт без grant/error echo, owner/discovery и исходная session сохраняются. Read-only peer проверяет safe FORBIDDEN всех четырёх write methods до business validation, неизменный list/storeRevision и ready после отказов; normal close, последующий legitimate peer и исходная session остаются работоспособны. Не подменять это full Q03/other-user/UI acceptance. Mandatory checks и fresh review до closure.

- [x] T133 Исправить actual T132 fixture timeout: discovery console peer должен перебрать восемь advertised slots при занятом первом, проверяя kernel owner/image после connect. Отдельные probes запускать через owned Process, stdout/stderr читать до EOF; timeout завершает только этот console child и ждёт его exit/EOF до fixture cleanup, owner не убивать. Initial targeted timeout26s не system denial и не green check. Повторить mandatory checks и fresh review перед closure.

- [x] T134 Устранить timeout общей длительности resource fixture: t133 full suite завершился83 passed/1 failure719s, mutation-limits child достиг actual map-full rollback, но не успел завершить reopen/10k-receipt quota за180s. Только для этого конечного workload закрепить bounded child budget360s и parent390s; остальные child180/parent210, production watchdog30/RPC5/lease60/grace2, объёмы64MiB/10k/1200 attempts и все assertions сохранить. Это test-harness timing, не system denial и не доказательство полной runtime performance. Повторить mandatory checks и fresh review вместе с T132/T133 до closure.

- [x] T135 Реализовать и принять T030 production protocol client в lib/bootstrap/local_api_client.dart и native_client_transport.dart: verified endpoint factory T031, two kernel checks/exact proofs/grant subset, bounded frames/16pending/single writer, heartbeat20, effect-free reconnect после actual prior close, safe correlated errors, immutable disposable MutationIntent и отдельный status read id, late/foreign replies без effects, polling2s atomic matching snapshots/monotonic revisions и suppression после stop; никакого auto-save. Tests test/contract/local_api_client_test.dart покрывают timeout/borrowed-buffer lifetime/duplicates/quota/invalid proof/result/disconnect/polling/partial deadline. Approved compiled bootstrap_client client-native mode использует эти production classes с actual locald/DPAPI CRUD/status/poll/delete/close при другом живом peer. Initial syntax/analyzer errors исправить; root mandatory checks, locald analyze/full suite/lychee/fresh review до closure T030/T135. UI bootstrap T031 и full UI/native/release gates остаются открытыми.

- [x] T136 Исправить воспроизведённое зависание T030 close при paused states listener: native transport и pending RPC завершить/дождаться, но не ждать consumer-owned StreamController.close future, зависящий от resume/cancel чужой подписки. Event streams получают close, новые callbacks не публикуются; snapshot cache очистить. Regression t136-paused-red.txt дал timeout100ms до fix; повторить весь contract/root suite и compiled actual client/full locald, checks/review до closure. MutationIntent валидирует id/method до создания private params buffer, ошибки input безопасны; остальные протокол/сроки сохраняются.

- [x] T137 Исправить confirmed T030 review: mutation commit/REVISION_CONFLICT во время активного refresh запоминает повторное чтение и выполняет его сразу после текущего, без ожидания poll2s и параллельных snapshot readers; stop/close suppression сохранить. Contract regressions для обеих веток, mandatory checks и fresh review до closure.

- [x] T138 Исправить confirmed T030 transport lifetime: при ошибке close после write timeout обе ветки auth/RPC всё равно ждут actual terminal write до очистки borrowed buffer; teardown error и запрет reconnect после failed retirement сохраняются. Pending-write/failing-close regressions обеих веток, mandatory checks и fresh review до closure.

- [x] T139 Исправить confirmed local_api_client_fixed_review: endpoint cleanup sync/async error не обходит safe LocalApiException boundary connect и disconnected event. Future.sync сохраняет failed retirement barrier, повторный connector запрещён; auth/RPC failing-close regressions требуют safe SERVICE_UNAVAILABLE и disconnected. T138 actual write completion остаётся обязательным. Повторить mandatory checks/current compiled journey/fresh review до closure.

- [x] T140 Исправить confirmed heartbeat teardown review: void scheduler вызывает отдельно наблюдаемый Future ping, включая ошибки physical close; unhandled zone error запрещён, disconnected/safe public errors и failed retirement barrier сохраняются. Regression heartbeat INTERNAL/failing-close проверяет отсутствие uncaught errors в test zone и safe errors; initial custom error-zone regression зависла на cross-zone Future и исправлена, это fixture failure, не system denial. Mandatory checks и fresh review до closure.

- [x] T141 Реализовать attempt/timing часть T031 в lib/bootstrap/bootstrap_controller.dart: verify callback перед ensureService, ready/error deadline30s, readiness250ms/connect100→1000ms, manual/reentrant retry joins actual live attempt, deadline показывает TIMEOUT при незавершённой native операции и подавляет поздний ready, safe terminal reasons/no private reads до ready, dispose suppression. Tests test/contract/bootstrap_controller_test.dart и root checks/lychee/fresh review. Это часть T031; без T142 и actual acceptance T031 не закрывать.

- [x] T142 Завершить T031: concrete Windows verified bundle и UI identity, DPAPI discovery/canonical slots/token lifetime и stale-descriptor retry, hidden launch без shell/secrets только при необходимости, связывание LocalApiClient и BootstrapController, ready disconnect/stopping bootstrap, main.dart integration. Использовать shared contracts без Isar в UI; actual compiled production UI/native acceptance и tests ошибок, mandatory checks/fresh review. Не считать T141 callback tests доказательством native bootstrap.

- [x] T143 Исправить confirmed bootstrap_attempt_controller_review: после starting/ready notification повторно проверить live перед prepare/private polling; disposal из listener не оставляет effects. ChangeNotifier base dispose отложить до завершения текущего notify stack, собственный disposed guard действует сразу; поздний deadline callback не выполняет новые effects. Regression обеих фаз, mandatory checks и fresh review. T031/T142 native integration остаётся open.

- [x] T144 Подготовить shared bootstrap для T142 без импорта locald/Isar в UI: DiscoveryNamespace/Descriptor в serverdeck_protocol/lib/discovery.dart (cryptography2.9.0), DiscoveryCustody и verifyBuildBundle в serverdeck_windows/lib/discovery.dart/build_bundle.dart (path dependency protocol). Locald compatibility exports сохраняют действующие call sites, initializeNativeRuntime остаётся только locald. Строгие схемы/entropy/ACL/hash/token ownership и закрытие без изменения runtime контракта. Root/package analyze/tests, full Windows/locald native regression, lychee/fresh review до closure; это не закрывает launch/main/actual UI gates T142/T031.

- [x] T145 Реализовать concrete T142 bootstrap: Windows ClientBootstrapEnvironment verifies own approved UI/bundle, protected DPAPI discovery и hidden CreateProcess с allowlisted OS env/no inherited handles; NativeBootstrapHost worker isolates/slot iteration/token lifetime/retained owned-child kernel handle monitoring. Main использует BootstrapController, безопасные pending/retry/ready состояния, ready disconnect и transient stopping recovery. Stale hello generation при verified peer →SERVICE_UNAVAILABLE/reread, не API/build incompatibility; неверные proof/version по-прежнему rejected. Controller/client regressions, normal engine integration_test/bootstrap_test.dart (real main/host/locald readiness и descriptor removal), actual build/run, root/packagechecks/lychee/fresh review. T031/T142 не закрывать до реального acceptance и clean review; full shell/forms/Q01–12 остаются последующими задачами.

- [x] T146 Выполнить navigation/readiness часть T033/T034 и production integration T032: FoundationApp вынести в lib/app.dart с совместимым export из main.dart; FoundationShell пять разделов/первый Серверы, width≤800 drawer иначе боковая панель, bundled logo обеих тем. До ready не монтировать private child/target, при потере ready убрать их; локальный section сохраняется. Future ПО/Журналы/Задания показывают безопасную причину без demo/remote health. Servers/settings принимают будущие конкретные views; пока они явно недоступны, пустота хранилища не выдумывается. T035/T036/T037 подключают реальные данные/формы/settings/target, T033/T034 не закрывать целиком этой частью. Widget normal/loss-of-ready/keyboard/nav48px и обе темы×четыре viewports×scale200, root mandatory checks, specs lychee, actual compiled UI smoke и fresh review.
- [x] T147 Подключить service-owned read projection T035/T036 к production UI: ProfileController подписывается на LocalApiClient snapshots, читает только ready, проверяет protocol schemas/coherence/current generation/monotonic revision и selected reference, типизирует immutable ProfileView/SettingsView без secret/ref. Потеря ready/disposal очищает приватную модель; queued callbacks/refresh errors не возвращают stale данные. ProfileList различает loading/error/empty, показывает реальные metadata/detail и доступность подключения; SettingsView пока read-only, theme и reduceMotion projection применены через app без UI DB. Header selected target из service-owned settings, long text прокручивается. CRUD/forms/selection/settings mutations/recovery и полное reduced-motion поведение остаются T035–37/T033/T034/T042. Controller/widget failure/coherence/max bounds/обе темы/four viewports/text200 tests, mandatory checks, compiled actual UI first snapshot и fresh review; не закрывать исходные T035/T036 целиком этим increment.
- [x] T148 Исправить два confirmed P1 profile_read_projection_review: duplicate suppression LocalApiClient учитывает publication epoch, сохраняя snapshot/monotonic rollback barrier; same-generation unchanged successful read после stop/start или read failure снова публикуется. Все refresh owners отправляют только безопасный ErrorCode в synchronous snapshotErrors stream с generation/epoch/disposal guards. ProfileController очищает private projection и показывает transient error/retry; BootstrapController прекращает ready/polling при STORAGE_BLOCKED/INCOMPATIBLE/NOT_READY с ручным recovery. Stream subscriptions закрываются/отзываются при disposal без ожидания paused consumer. Regression same-generation/no mutation, background live-channel storage-blocked/timeout, unchanged success aftererror, late retired-epoch error и terminal→manual recovery. Mandatory checks, actual compiled UI, focused locald compiled/native regression и fresh review до clean; T147 и исходные T035–37 не закрывать до evidence соответствующего scope.
- [x] T149 Исправить confirmed P2 profile_read_recovery_fixed_review: общий ReadErrorView в lib/shell/error_view.dart получает только ErrorCode и callbacks, локализует safe allowlist category/next step. ProfileList и SettingsView используют одинаковый error presentation; transient/readable categories дают explicit повтор чтения, service categories — explicit проверку службы, prohibited/unsupported дают честное пояснение без обещания retry. Никаких raw exception/private strings/path/credential. Widget regression всех15categories/actions, timeout recovery на Servers и internal recovery на Settings, no retained target/private content, target48px/200% обе темы. Mandatory root checks/lychee, rebuilt actual compiled UI и fresh review до clean; полный mutation recovery T037 остаётся open.
- [x] T150 Исправить confirmed P2 profile_read_error_presentation_fixed_review: ProfileController.refresh только инициирует/joins client refresh; Future rejection не изменяет UI, поскольку joined Future может принадлежать retired poll epoch. Единственный источник read-error presentation — client's guarded snapshotErrors; readiness/disposal guards остаются. Composition regression pending shared Future→loss-ready→new-ready→late STORAGE_BLOCKED без current error event сохраняет model.error null, затем current valid snapshot восстанавливает profiles/target/settings. Regression реально провален до fix (t150-red) и должен пройти после fix. Mandatory root checks/lychee, rebuilt actual UI и fresh review до clean; история T147–149 сохранена.

- [x] T151 Реализовать общий mutation controller для T035–T037 в `lib/profiles/mutation_controller.dart`, до подключения forms/settings. Один immutable MutationIntent/requestId в RAM, явный status lookup через existing client, queued/running без resend, ready not-found разрешает только явный same-intent retry. Потеря ready отзывает retry permission, late retired status не разрешает retry; durable committed receipt требует current coherent model storeRevision≥receipt и reread, не заменяет snapshot. Commit/read failure не разрешает повтор эффекта; CAS conflict сохраняет внешний draft до explicit reload/cancel, no-effect failure/reset создаёт новый id только для нового explicit действия. Reentrant disposal/late completion подавлены, owned intent bytes очищаются; raw exceptions не передаются presentation. Controller regressions before source, root mandatory checks/lychee/fresh review до closure. Это общий компонент: production forms, settings mutation UX, startup recent/recovery, полной T037/001.1 приёмки ещё нет; исходные T033–T037 остаются открытыми.

- [x] T152 Исправить confirmed P2 mutation_controller_fresh_review: после synchronous submitting/busy notification заново проверять ready, captured readiness epoch и generation перед mutate/status, поскольку listener может отозвать not-found retry permission даже при полном ready→unavailable→ready цикле. Сохранить immutable intent в unknown с safe NOT_READY, завершить busy без отправки и автоматического повтора. Шесть regressions submit/retry/status × loss/reconnect реально failed до fix; после fix targeted/root mandatory checks/lychee и fresh completed review до closure T151/T152. Первый mutation_controller_review failed infrastructure401, не clean evidence.

- [x] T153 Исправить confirmed P2 mutation_readiness_fixed_review: authoritative BootstrapController.readinessEpoch увеличивается при смене state до notifications, mutation guards читают actual bootstrap state/epoch вместо cached readiness. Entry sync отзывает прежнее retry permission даже если nested loss→ready был пропущен listener из-за порядка доставки. Четыре model-listener regressions submit/retry/status outside-ready и same-generation retry после nested recovery реально failed до fix, actual BootstrapController epoch test проверяет before-listener/nested recovery monotonicity. Existing sync notification/disposal/late completion tests остаются. Mandatory checks, actual rebuilt bootstrap UI (bootstrap source touched), fresh review до closure T151–T153; T033–T037/full001.1 не закрывать этим scope.

- [x] T154 Подключить production create/update формы T035 через принятый MutationController: `lib/profiles/{profile_form,credential_input,mutation_status}.dart`, action buttons в profile_list. Immutable profileId/expectedRevision, shared validators, Windows IDN→A-label до API, multiline tags без потери запятых, keep/remove/password/privateKey modes, transient reveal/no autofill/no normalization secrets, explicit bounded UTF8 key picker с worker isolate и без path persistence/implicit SSH directory. `packages/serverdeck_windows/lib/profile_input.dart` предоставляет OS conversion и explicit read≤64KiB/cleared owned bytes; new native tests. Snapshot не переписывает draft, loss-ready скрывает/снимает focus с формы без уничтожения RAM draft; input clear after confirmed save/cancel/dispose, CAS explicit reload/cancel, timeout status/same-id retry/readback без optimistic success. Form/credential widget regressions, обе темы/four viewports/200%/scroll48px, root mandatory checks, Windows package checks, lychee, actual compiled UI create→readback→close/reopen persistent metadata и fresh review. Исходные T033–T037 остаются открытыми: delete/selection/settings/startup recent/full keyboard/focus/error matrix/native key-picker interaction и full001.1 ещё не приняты; T154 не заменяет эти gates.

- [x] T155 Завершить production local-delete часть T035 в `lib/profiles/profile_delete.dart` и profile_list button, общий MutationStatus различает сохранение/удаление. Confirmation содержит immutable captured profile name/address/port и явное «Удаляется локальный профиль; сервер не меняется»; mutation profiles.delete с captured revision через общий controller, success только commit+coherent readback, timeout/status/same-id retry без повторного эффекта. При CAS snapshot не меняет confirmation сам: explicit reload и новое подтверждение; missing target после reload не объявляется собственным successful delete. Loss-ready скрывает metadata; close/Esc не отменяет отправленное удаление, до confirm cancel ничего не пишет, focus возвращается инициатору. Widget tests normal/readback/lostreply/readiness/CAS/Esc/focus/boththemes/fourviewports/text200/actions48px; root mandatory checks/lychee/actual compiled UI persistent create→reopen→delete→empty reopen/fresh review до closure. T033–T037/T042/full001.1 ещё открыты для selection/settings/recent/full input and recovery matrix/native key-picker/two-window/reboot/other-user acceptance; этот increment не заменяет fullstage gates.

- [x] T156 Подключить production settings/active selection часть T036: settings_controller.dart владеет RAM draft/captured settings revision/profile choices; settings_form.dart редактирует system/light/dark, reduceMotion и nullable selectedProfileId, отправляет один settings.update через принятый MutationController. Внешние snapshots не меняют draft; CAS требует explicit reload/new confirmation, uncertain status/same-intent retry и commit+coherent readback без optimistic theme/target. Loss-ready скрывает metadata, cancel/Esc не пишет, close после send не отменяет effect. SettingsView показывает persisted values и открывает форму; MutationStatus даёт settings-specific conflict/reload. Contract/widget normal/CAS/timeout/readiness/both themes/four viewports/text200/actions48px, mandatory checks/lychee, actual production settings save→reopen и selected-profile delete clears target, fresh readonly review до closure. Original T036/T033–T037/T042 остаются open для полного reduced-motion/keyboard/input/recovery/acceptance scope; не выдавать этот increment за полную001.1.
- [x] T157 Исправить два confirmed P2 settings_mutation_review: launcher→dialog race не использует settings! до coherent snapshot. SettingsController захватывает первый live ready snapshot через listener, initialized gate запрещает форму/save/default projection до capture; поздние snapshots не перезаписывают captured RAM draft, listener снимается на disposal. SettingsForm показывает safe readiness/loading/read-error и explicit read retry до capture. Два widget regressions loss-ready/read-error между click и dialog frame реально failed null assertion до fix. Compiled integration settings target assertions проверяют фактический combined name/address/Не подключён; повтор actual save→reopen→selected delete→empty reopen до terminal success. Все mandatory checks/fresh review; T156/T157 не закрывать до clean, полный001.1 остаётся open.
- [x] T158 Завершить policy уменьшения крупных переходов T036: lib/theme/motion.dart и FoundationApp учитывают OS disableAnimations OR persisted reduceMotion, MediaQuery.fromView реагирует на OS accessibility, theme swap/ExpansionTile без transition, кнопки без ripple/duration, live input/focus/status и RPC timers сохраняются. Production create/edit/delete/settings dialogs используют showMotionDialog zero duration в reduced mode; compact navigation показывает static Drawer modal без slide. MotionDropdown сохраняет ordinary Flutter dropdown и использует static selection modal при reduced mode; settings private choices в modal скрываются при loss-ready и stale callback запрещён. Brandbook/assets/tokens и storage/API не меняются. Widget all4 OS/preferences combinations, zero-route actual drawer/dialog/selector selection/privacy/controls functional, mandatory rootchecks/lychee, actual rebuilt UI saved reduceMotion/no-transition delete dialog, fresh review до closure. T036/full001.1 не закрывать до полной keyboard/input/recovery/Q12/native acceptance; уменьшение анимаций не замораживает tickers/действия/таймеры.
- [x] T159 Подключить startup list/recent recovery часть T037: StartupRecovery в lib/profiles/startup_recovery.dart принадлежит FoundationApp, после первого coherent ready snapshot читает mutations.recent limit20 один раз на readiness epoch. Receipt summaries immutable/validated/current generation, только committed history общего пространства; никакого restore intent/auto-save/mutation, historical result не применяет entity/settings. Before new CRUD/settings UI complete current-model/recent read; receipt newer than snapshot требует reread и coherent storeRevision≥max receipt, bounded5s floor wait/safe timeout без auto retry. Loss-ready/epoch/disposal отзывают pending callback и скрывают history, stale generation ignored/incompatible, errors safe с explicit read/service retry. recovery_view.dart даёт toolbar history dialog, current shared receipts/UTC/IDs/предел20/truncated и предупреждение что отсутствие receipt не доказывает исход потерянного запроса. Проверки controller start/coalescing/CAS floor/lost epoch/errors/noauto/disposal/malformed/timeout, widget gating/historyprivacy/20records/boththemes/fourviewports/text200/actions48px; rootchecks/lychee/actual compiled normal reopen recent/create/settings/delete/noadditionalreceipts/freshreview. Не закрывать actual crash/two-window/native/fullkeyboardQ12/T033–T037/T038/T042/full001.1 этим increment.
- [x] T160 Завершить keyboard часть profile forms T033/T035/T037: lib/shell/form_keyboard.dart определяет Escape close и submitIntent только для opted-in single-line fields через SubmitOnEnter (Enter/numpadEnter), owned FocusScope сохраняет Esc после disabled fields/unknown outcome. ProfileForm включает scope, first name autofocus, single-line IME done/onSubmitted; tags и revealed multiline key сохраняют newline, buttons/selectors сохраняют default activation. CredentialInput optional onSubmit связывает password/passphrase/hidden key single-line с тем же guarded save; secrets не нормализуются/не сохраняются UI. _save проверяет actual readiness/idle/model/picker и mounted FormState до validation/RPC; no secondsend после keyboard repeat/unknown. Esc/cancel clears buffers, restores launcher, doesn't cancel sent mutation; nonready close min48. profile_keyboard_test.dart реальные pre-fix3fails Enter/validation/Escsecret, afterfix Enter/numpad/IME/password/TabShiftTab/multiline/notready/unknown/secretclear/focus и existing Settings/Delete button keyboard verifies. Mandatory rootchecks/lychee, actual compiled form Enter-save/Esc-close with locald/commitreadback/reopen, freshreview до closure. FullQ12/nativepicker/fullinput/error/twowindow/crash/T033–T038/T042/full001.1 остаются open.
- [x] T161 Завершить picker-lifetime/input проверки T035/T037: CredentialInput отвергает поздний результат и safe error после enabled loss, даже если форма снова enabled; production ProfileForm передаёт reader actual ready/readinessEpoch, чтобы loss/recovery без widget rebuild тоже отзывали pending input. Один незавершённый picker сохраняет busy до фактического завершения, explicit retry доступен после завершения, no auto retry/no stale secret publication. Regressions текущего safe failure/explicit retry/verbatim input/clear disposal, lost-ready/current epoch и revealed multiline key Enter no submit/platform newline retention. Два pre-fix picker failures доказаны; synthetic Windows key event сам не создаёт platform editing update, это ограничение теста, не дефект продукта. Mandatory rootchecks/lychee/fresh readonly review до closure; native picker interaction/physical keyboard/fullQ12/двухоконная crash приёмка остаются open.

- [x] T162 Закрыть confirmed P2 q12_accessibility_review для T042: test/widget/accessibility_test.dart покрывает 48 сочетаний обеих тем/four viewports/text200/3forms/timeout-or-CAS. Каждый submit/status/same-intent retry/CAS reload достигается реальным Tab с assertion focus ancestry, ShiftTab уводит focus, Tab возвращает; Enter исполняет action с проверками status/retry/reload effects. Target≥48 обоих измерений/hit-testable после scroll; draft не меняется external snapshot, readiness loss скрывает private content, Esc restores launcher/no additional mutation. Первые16profile matrix failures были sequencing теста (pending caret scroll после enterText), corrected wait без production fix; не заявлять product red. Оценить весь existing widget suite вместе с новой matrix на T042 scope и закрывать original T042 только после mandatory checks/fresh clean review. Native physical keyboard/picker/full001.1/Q12 native/T048 остаются open.

- [x] T163 Реализовать и принять actual two-process UI часть T038: integration_test/foundation_test.dart запускает production app.main в двух отдельных UI processes/Flutter engines из одного verified compiled bundle. Acceptance-only Windows test/support/ui_actor.dart запускает hidden verified own image, allowlisted OS env+fixed observer role/no inherited handles; retains own process handle for exit/cleanup without arbitrary PID/root. tools/run-foundation.ps1 FoundationAcceptance и tools/test-foundation-ui.ps1 build/copy unique owned synthetic LOCALAPPDATA fixture, restore env, require scenario-specific stage-finished/primary-accepted markers (не принять unrelated compiled test). Atomic safe signal markers PID/generation only, no bootstrap token/credentials. Real create→second window update while first RAM draft→actual stale CAS→explicit reload/cancel; one serverPid/generation. Второе окно получает native WM_CLOSE только для собственного PID; первое проверяет его exit0 через retained handle и сохраняет новое имя при прежнем owner PID/generation. После release последней UI session дождаться удаления discovery с учётом lease60s/grace2s (test bound90s). Первый flutter drive завершает свой UI process; второй drive запускает fresh UI process в том же fixture, проверяет distinct UI PID/new owner generation, последнее имя и exactly3 committed history/no auto-save. Actual compiled UI/current protocol/locald/protected DB, no mocked repository. Root mandatory checks/Windows package analyze+tests/lychee/fresh review до closure. T038/Q02 simultaneous starts/third window, lostreply/late request, UI crash/inflight/offline/reboot/otheruser/native/full001.1 remain open; этот increment не заменяет эти gates.
- [x] T164 Исправить confirmed P2 two_ui_acceptance_review: первоначальный passing T163 run проверял disposal/recreation FoundationApp внутри одного процесса, а не native close/fresh process reopen; эти результаты сохраняются только как evidence двух UI actors/shared owner/CAS и session/widget lifecycle. Заменить observer disposal на native close собственного окна и kernel exit proof; primary остаётся живым и делает confirmed save. Reopen выделить в отдельный flutter drive после terminal первого; fresh process читает current model/recent без нового effect. SystemNavigator.pop в Windows runner не завершил observer (actual failed run OTHER_ACTOR_FAILED после CAS); acceptance-only helper отправляет WM_CLOSE по проверенному current PID/class. После WM_CLOSE frame-dependent tester.pump ожидание зависло: interrupted run не принят, process inventory после остановки не доказывает штатный выход. Kernel exit ожидается через runAsync/wall-clock polling с bound30s, без зависимости от Flutter frame. Повторить actual harness, обязательные checks и fresh readonly review; не закрывать T163/T164 по старому widget reopen evidence.
- [x] T165 Обработать native application exit в production FoundationApp: WidgetsBindingObserver.didRequestAppExit сначала освобождает recovery/model, отзывает bootstrap и ждёт controller/client/NativeBootstrapHost close, затем возвращает AppExitResponse.exit. Dispose использует тот же idempotent future, observer снимается; transport close failure не запрещает закрыть окно и не объявляется clean shutdown сервиса. Повторный native exit/dispose не закрывает ресурсы дважды. Acceptance-only observer window смещается100/80, размер1100×700: оба Windows views остаются частично видимыми, чтобы occlusion не остановил frame-dependent widget driver. Прогон с полностью перекрытым primary прерван без зачёта. Actual WM_CLOSE+wall-clock30s polling до этого исправления получил STILL_ACTIVE259, поэтому прежнее предположение об успешном native exit не считается доказанным. Widget regressions pending close/success/failure/dispose, root mandatory checks, actual native exit surviving-window save/fresh-process reopen и fresh review до closure.

Приёмка T163–T165: actual rebuilt FoundationAcceptance завершил два отдельных flutter drive с exit0 (первый2tests19s CAS/native close/surviving owner, второй2tests4s fresh process/current profile/3receipts). Root format212files0changes/analyzeNoissues/219tests; Windows analyzeNoissues/fullserial29tests2m11s; lychee514OK/52unique/0errors; git diff--check exit0. Bootstrap regression rebuilt2tests14s/12markers; current cached unrelated Bootstrap target drivepassed, но foundation script rejected exact Two-window stage proof missing. Fresh readonly native_ui_exit_fresh_review завершён: замечаний нет, ready только T163–T165 scope. Full001.1/open T038 и остальные gates не закрыты. Предыдущие failed/interrupted прогоны не зачтены.

- [x] T166 Принять оставшуюся normal Q02/T038 часть на actual compiled UI: tools/test-foundation-ui.ps1 -ThreeWindows выбирает acceptance-only concurrent-three scenario, сохраняет/восстанавливает env и требует отдельный final scenario proof. Первый UI process до app.main запускает verified observer; observer публикует boot-entry и ждёт shared start barrier, оба production app.main начинают bootstrap из empty fixture без discovery. После ready/empty оба подтверждают distinct UI PID и same owner PID/generation перед create. Затем inherited T163 actual create/update/CAS/reload; третий verified witness process читает Observer update с same owner пока первые оба live. Native close observer, primary committed save, witness current-model readback и native exit0, primary остаётся при прежнем owner; last close/fresh process reopen exactly3 receipts/noauto. Test windows partly visible; wall-clock30s startup/native waits; retained handles only owned children, even on failures оба cleanup attempts/handle closes. Production lifecycle/API/storage не меняются, default two-window scenario сохраняется. Mandatory rootchecks/Windows analyze+serial tests/lychee/default scenario regression/actual ThreeWindows/fresh readonly review до closure. Full001.1/crash/inflight/lostreply/offline/reboot/otheruser/nativeQ12 gates остаются open.

Приёмка T166: actual rebuilt ThreeWindows harness terminalexit0 — firstdrive2tests24s/second2tests4s, concurrent start/one owner/CAS/third current readback/native exits/fresh process exactly3receipts. Default samebundle regression23s/4s passed. Root format212files0changes/analyzeNoissues/219tests17s; Windows analyzeNoissues/fullserial29tests2m23s; lychee514OK52unique0errors; gitdiffcheckexit0. Fresh readonly concurrent_three_ui_review завершён: замечаний нет, ready scoped normalQ02/T038/T166; полный001.1 не принят. После finalreview currentcached negative завершён exit0 T166_CACHED_THREE_TARGET_REJECTED: Bootstrap rebuilt2tests15s, cacheddrive2tests14s passed, ThreeWindows harness rejected exact Two-window stage proof missing. Reviewer не выдавал pending negative за passed; final negative evidence проверен автором. Production code/storage/API не менялись; fullLocald suite не повторялся. Full T038/crash/inflight/lostreply/offline/reboot/otheruser/nativeQ12 и остальные gates остаются open.

- [x] T167 Принять UI-crash после confirmed commit и восстановление T037/T038 на actual production app/locald/DB: tools/test-foundation-ui.ps1 -CrashObserver выбирает отдельный acceptance-only crash-observer scenario (несовместим с ThreeWindows). Observer подтверждает update, затем держит unsent RAM draft; primary сохраняет собственный unsent draft после CAS/reload. Primary завершает только собственный verified observer через retained kernel handle, доказывает abnormal exit73, свой draft неизменным и live owner PID/generation прежними. Новый verified recovered UI process при живом primary читает persisted Observer update и exactly2committed receipts; unsent observer draft не восстановлен/не auto-saved. После explicit cancel primary отправляет третью confirmed mutation, recovered client читает current name и closes normally. Last close/fresh driver restart exactly3receipts/noauto. Root mandatory checks/Windows package checks/lychee/default+ThreeWindows regressions/actual crash scenario/fresh readonly review до closure. Это crash после известного confirmed commit и unsent draft, не crash неизвестного inflight mutation/потеря reply/UI durable intent; Q07/fullQ08/reboot/otheruser/full001.1 остаются open.

T167 diagnostic history: первые failed runs подтвердили abnormal exit73/live owner/primary draft и subsequent explicitcommit, но recovered follower не был принят. Missed Edit tap после Esc/lost native focus исправлен explicit Отмена/Закрыть с noDialog assertion только crash scenario. Role-specific phase/known-name booleans и first framework error kind/library/stack без input/credentials выявили исходную FileSystemException в _StdConsumer/_RandomAccessFile.writeFromSync: recovered child без inherited console писал stdout marker, framework завершал тест, затем follow pump assert inTest=false. Child теперь публикует bounded fixture history proof; primary проверяет её и выводит marker сам. Failed attempts не засчитывать как успешную приёмку и не объявлять storage/polling defect. Error handler делегирует прежнему и восстанавливается finally; child cleanup остаётся обязательным. На момент этих диагностических попыток finalchecks/freshreview ещё не были завершены; итоговая приёмка приведена ниже.

Приёмка T167: актуальный rebuilt crash harness terminalexit0, firstdrive2tests27s/second2tests5s, все шесть основных crash/recovery/native-close/fresh-reopen markers. Default regression21s/4s и ThreeWindows29s/4s, обе по2tests на каждом drive, passed. Root format212files0changes/analyzeNoissues/219tests19s; Windows analyzeNoissues/fullserial29tests2m8s; lychee514OK52unique0errors; gitdiffcheckexit0. Conflicting CrashObserver+ThreeWindows отвергнуты до SDK/build exact Choose one UI acceptance scenario. Fresh readonly ui_crash_recovery_review завершён: замечаний нет, ready только scoped T167 confirmedcommit/unsentdraft/currentmodel/recent/noauto; full001.1 не принят. После отчёта reviewer cached-target negative terminalexit0 T167_CACHED_CRASH_TARGET_REJECTED: Bootstrap regression2tests15s passed, unrelated cached drive2tests15s passed, crash-harness отверг exact Two-window stage proof missing. Pending negative не выдавался reviewer за passed, итог проверен автором отдельно. Evidence .local/audits/t167-*.txt. Production API/storage/lifecycle не менялись; fullLocald suite не повторялся. Unknown inflight/lostreply/Q07/fullQ08/reboot/otheruser/nativepicker и остальные исходные gates остаются open.

Уточнение отсрочки: открытыми и отложенными остаются только конкретные операции и проверки, отклонённые системой; их нельзя повторять или обходить другой средой/инструментом. Остальные доступные операции с OS-защитой всех секретов доступа и связанные проверки выполняются в обычном порядке. Это не отменяет реализацию шифрования и не закрывает непройденные критерии приёмки.
- [x] T168 Принять transport-level Q07 lost reply/request/late original через compiled normal owner и production LocalApiClient: acceptance-only LossTransport оборачивает verified NativeClientTransport в compiled synthetic bootstrap client, drop ровно одного ответа известного mutation id после получения полного server frame; original mutate должен TIMEOUT, committed status и same-id replay возвращают original result/одну revision. Hold одного original request до native write; status not-found в той же generation, explicit same-intent retry доставляется вместе с поздним identical original; current readback/recent доказывают один update/одну receipt, changed-input same-id отвергнут IDEMPOTENCY_CONFLICT. Другой compiled peer продолжает удерживать owner, fixture discovery/PID/generation не меняются. Управление loss отсутствует в production entry и API; synthetic request bytes очищаются после доставки/close. bootstrap_native_test запускает отдельный client-loss mode с30s acceptance bound (две настоящие5s RPC deadlines). Root mandatory checks, locald analyze/compiled bootstrap native regression, lychee и fresh readonly review до closure. Это transport acceptance, не widget unknown-outcome UX, не owner crash/reboot/весь Q07/T037/T038/001.1.
T168 diagnostic history: первый compiled run завершился exit1 (bootstrap test27s), client-loss получил LocalApiException VALIDATION. Новый fixture profiles.update пропустил обязательные port/tags, хотя profiles.create разрешает их defaults. Fixture исправлен полным update input; production validation не менялась. Этот запуск не считается приёмкой; повторные mandatory checks и native run ожидаются.
Приёмка T168: final checks terminalexit0 T168_FINAL_CHECKS_PASSED. Root format213files0changes/analyzeNoissues9.9s/219tests23s; locald analyzeNoissues; full compiled bootstrap native regression1test2m40s passed, включая client-loss mode на normal held-owner runs с обязательным final loss proof. Настоящие два5s RPC timeout, committed status/original replay, before-enqueue not-found/explicit retry+late original, currentmodel/recent exactly-one receipts и changed-input same-id conflict проверены executable assertions. Lychee514OK52unique0errors, gitdiffcheckexit0 (CRLF warnings only). Evidence .local/audits/t168-final-*.txt; первый failed fixture run сохранён отдельно и не засчитан. Fresh readonly compiled_client_loss_recovery_review завершён: замечаний нет, readiness ready scoped T168; reviewer прочитал source/contracts/logs, самостоятельно tests не запускал. Production code не менялся, full locald/Windows suites не повторялись; затронутый compiled bootstrap путь покрыт native regression. Widget unknown-outcome UX/fullQ07/T037/T038/owner crash/reboot/other-user/full001.1 остаются open. Goal active; no commit/push/PR/release/merge.
- [x] T169 Завершить form-level unknown-result recovery coverage T033/T037: test/widget/mutation_result_form_test.dart проверяет production ProfileForm/SettingsForm/ProfileDelete с controlled client replies: timeout→queued/running без resend, committed status без success до coherent readback, stale snapshot/read failure/manual read не дают повтор эффекта; ready loss отзывает not-found retry, новый explicit status разрешает retry только same immutable intent, close pending status игнорирует late receipt/не восстанавливает intent. RAM drafts не переписываются current snapshot; save disabled до разрешения результата. Введённые password/privateKey/passphrase сохраняются при unknown и knowncommit-before-readback, очищаются после success/cancel/disposal. Исправить обнаруженное LF removal hidden PEM: скрытый multiline key в CredentialInput read-only с helper, ручной ввод только после explicit reveal в multiline editor, chooser сохраняет hidden path; при повторном скрытии raw key не меняется. Два synthetic PEM typed-input regressions failed до fix, остальные failures typed snapshot maps/invalid PEM/getter test compilation являются fixture errors. Root mandatory checks/targeted regressions/lychee/rebuilt actual two-window UI/fresh readonly review до closure. Controlled widget client не доказывает physical keyboard/picker, native lost reply/T168 или full Q07/T037/T038/001.1.
- [x] T170 Исправить confirmed P2 mutation_result_pem_form_review для T169: fixtures должны отражать достижимую durable последовательность, не только достаточный presentation floor. Baseline store2 = create profile at1 + settings selection/theme/reduceMotion at2 (settings revision2/profile revision1). Explicit operation commits at3: profile entity2, settings entity3, delete historical profile entity1 с selected→null/settings revision3. Exact readback соответствует draft/secret credential kind+revision2; optional subsequent external edit commits at4 (profile entity3 либо settings entity4), поэтому current readback может отличаться от RAM draft без contradiction. Credentials/access revisions при keep/replace и unchanged profiles/settings согласованы с data-model. Первый review не clean: один confirmed finding о receipt/current fixture. Повторить targeted/root mandatory checks/lychee/rebuilt compiled UI и fresh readonly review; T169/T170 не закрывать до clean.
T170 diagnostic history: промежуточный corrected fixture targeted run28passed; дальнейшее уточнение baseline до create+selection на store2 сначала не компилировалось из-за local function baseline declaration после setUp. Helper перенесён в top-level, semantic требования не менялись; этот failed compile не считается проверкой. Текущая final приёмка и fresh review ещё ожидаются.
Приёмка T169/T170: final terminalsession75350 exit0 T170_CHECKS_PASSED; .local/audits/t170-targeted-corrected.txt28tests7s, format214files0changes, FlutteranalyzeNoissues9.2s, root232tests22s, rebuilt actualcompiledUI drive2tests22s/freshdrive2tests5s и proofs sharedowner/CAS/nativeclose-survivor/freshprocess-noautosave. Lychee514OK52unique0errors; gitdiffcheckexit0 (CRLFwarnings). Предыдущий mutation_result_pem_form_review completed с одним confirmed P2 невозможного receipt/current fixture; fixed baseline/commit3/externalcommit4/delete/settings/credential states приняты свежим completed readonly mutation_result_pem_fixed_review: замечаний нет, готов scoped T169/T170. Reviewer прочитал source/contracts/logs, tests самостоятельно не повторял. Production hidden PEM теперь read-only с explicit reveal multiline/manualinput/file chooser; picker может оставаться hidden, повторное скрытие не меняет raw key. 13 новых controlled-client form tests проверяют unknown/status/retry/readback/lateclose/secretclear; normalcompiled smoke не выдаётся за physicalPEM/picker proof. Full locald/Windows suites не повторялись, package production source не менялся; root/compiled UI включают затронутый CredentialInput. Physical input/picker/unknowninflightUIcrash/fullQ07/T033/T037/T038/full001.1 и остальные исходные gates остаются open. Goal active; no commit/push/PR/release/merge.
- [x] T171 Принять Q07 through actual compiled UI/normal locald/native transport: новый integration_test/loss_recovery_test.dart и test-only support/loss_client.dart собирают unchanged production FoundationApp/BootstrapController/NativeBootstrapHost с actual LocalApiClient и verified NativeClientTransport, обёрнутым acceptance-only LossTransport. Другой verified UI process использует normal app.main и остаётся live во время обеих потерь. One reply для next profiles.update удаляется после complete server frame; actual form unknown после5s, без false success/retry, explicit status+currentreadback→Saved и одна receipt. Next update frame удержан до native write:5s unknown, current revision2/old name и ready not-found; explicit same-intent retry доставляет retry+late identical original, current revision3/одна receipt/observer readback и прежний owner. Native observer close, all owned sessions close, fresh UI process normalmain получает persisted final name/exact3receipts/noautosave/newgeneration. tools/run-foundation.ps1 -LossAcceptance отдельный target, mutually exclusive с двумя прежними; новый tools/test-foundation-loss-ui.ps1 own unique synthetic fixture/stage+final exact proof/envrestore, no recursive cleanup. Normal main/owner не имеют loss controls. Root mandatory checks/locald analyze+compiled bootstrap regression/lychee/actual loss UI/defaultUI regression/cached unrelatedtarget rejection/fresh readonly review до closure. Это не unknown-inflight owner/UI kill, physicalPEM/nativepicker/full001.1.

T171 diagnostic history: первый build failed с несовместимыми ClientTransport types из-за mix package/file URI общих test-only imports, хотя preanalyze был green. Target/helper production imports приведены к единому relative graph; normal UI/owner source не менялись. Failed build не считать actual acceptance. Первый runtime запуск и final checks/review пока ожидаются.
T171 runtime history: consistent-imports build собран, lost-reply/actual form status/currentreadback proof пройден, но второй edit failed No element: fixture повторно toggle уже раскрытую profile row. Edit теперь раскрывает row только при отсутствии action. Cleanup теперь явно закрывает supplied BootstrapController до остальных owned clients/host, все шаги try/finally и retained observer handle cleanup выполняются даже при ошибке соседнего close. Первый partial run не считается полной T171 приёмкой.
T171 actual loss journey preliminary acceptance: rebuilt expanded-row target terminalexit0 T171_UI_PASSED, first drive2tests29s/fresh drive2tests6s. Markers COMPILED_UI_LOST_REPLY_STATUS_CURRENT_READBACK_PROVED, COMPILED_UI_LOST_REQUEST_EXPLICIT_RETRY_LATE_ORIGINAL_SINGLE_EFFECT_PROVED, COMPILED_UI_LOSS_FRESH_PROCESS_THREE_EFFECTS_NO_AUTOSAVE_PROVED. Этот source run подтверждает оба5s failure paths, UI actions/observer/native close/fresh generation/exact3receipts. Final mandatorychecks/default+native regressions/cached-target negative/fresh review пока ожидаются; T171 остаётся open.
Приёмка T171 завершена: fresh readonly compiled_ui_loss_recovery_review — замечаний нет, готов только scoped increment T171; полная 001.1 этим не принята. Reviewer проверил семь изменённых файлов, production composition, contracts/Q07 и журналы; самостоятельно проверки не повторял. Source был заморожен до completed FINAL. Actual terminalsession10646 exit0 T171_CHECKS_PASSED: format216files0changes, FlutteranalyzeNoissues8.2s, root232tests26s, localdanalyzeNoissues, compiledbootstrap1test2m39s, defaultUI2tests22s/fresh2tests4s, lychee514OK52unique0errors, diffcheck0. Actual loss UI terminalsession32107 exit0 T171_UI_PASSED: first2tests29s/fresh2tests6s с тремя loss/currentreadback/lateoriginal-singleeffect/freshprocess-noautosave proofs. Cached unrelated target прошёл свои2tests22s, но loss harness отверг exact UI loss stage proof missing; wrapper terminal marker T171_CACHED_TARGET_REJECTED. Bootstrap+Loss и Foundation+Loss отвергнуты до SDK/build exact Choose one acceptance target, marker T171_CONFLICTING_TARGETS_REJECTED. Evidence .local/audits/t171-*.txt. Failed build/partial runtime сохранены выше и не засчитаны. Production source не менялся; full locald/Windows suites не повторялись. Physical PEM/picker, unknown-inflight UI/owner kill, reboot/other-user/fullQ07/T037/T038 и остальные исходные gates остаются открытыми. Отложены только конкретные операции и проверки, отклонённые системой, без повторения/обхода; остальные работы с защитой секретов и доступные проверки продолжаются. Goal active; no commit/push/PR/release/merge.
- [x] T172 Актуализировать runnable documentation часть T046 по current source/evidence: README больше не утверждает отсутствие нового приложения; docs/development/foundation.md содержит pinned SDK/prerequisites, actual build/layout/normal launch/data lifetime, root/package checks, четыре runnable UI scenarios, fixture/canonical SID ограничения и recovery без private dumps. Quickstart сохраняет полную Q matrix, заменяет direct integration flutter test на действующие drive scripts и честно отмечает incomplete full native harness/intentional CI gate. Check links/PowerShell command syntax+script parameter/source correspondence/fresh readonly review до closure; documentation-only, без нового runtime/CI acceptance. T046/T043/T044/T047/T048 и весь001.1 этим не закрывать.
T172 accepted: README/current runnable docs/quickstart актуализированы по действующим source/scripts; новых runtime commands/CI runs не заявлено. Actual this-turn checks terminalexit0: lychee specs/**/*.md514OK53unique0errors, diffcheck0 (existingCRLFwarnings), PowerShell Parser всех fencedpowershell blocks README/foundation/quickstart без syntaxerrors и все localMarkdown links существуют, marker T172_DOCUMENT_COMMAND_SYNTAX_AND_LOCAL_LINKS_PASSED. Requirements checklist17checked0open; extensions.yml отсутствует. Fresh completed readonly runnable_foundation_docs_review: замечаний нет, готов scoped documentation increment; reviewer сверил commands/targets/layout/SID/runtime/recovery/source assertions и прочитал исторические T171logs, tests самостоятельно не запускал. Flutter/application/script source не менялся, root/native suites не повторялись. T172closed, T046/fullT043/T044/T047/T048/001.1 остаютсяopen; docs не заменяют runnable full native harness или Windows11/reboot/other-user/physicalinput evidence. Goal active; no commit/push/PR/release/merge.
- [x] T173 Принять credential/selection/cancel/delete часть Q09/T035–T038 через normal production app.main и настоящий locald/DPAPI: integration_test/credential_journey_test.dart, tools/run-foundation.ps1 -CredentialAcceptance и tools/test-foundation-credentials-ui.ps1. Восемь последовательных fresh UI drives одного owned synthetic fixture: create none→replace password→remove→replace PEM+passphrase→keep при изменении имени→settings selection→delete selected→reopen empty. Перед каждым новым commit current readback после нового owner generation совпадает с прошлым proof; credentialRevision1/2/3/4/4, connection/trust1; profile revision1..5, exact7unique receipts. Cancel create/profile secret draft/settings selection/delete confirmation не создаёт effects. Production forms explicit hidden/reveal PEM сохраняют CRLF и очищают transient secrets after known current readback. API responses не содержат synthetic secrets. Каждый owned session release ждёт discovery removal до proof; target controls только test entrypoint, ordinary owner unchanged. Mandatory root checks/lychee, actual compiled all8drives/defaultUI regression, conflictingtargets+caching negative/fresh readonly review до closure. Не закрывает DB/blob binding/scans/allQ09/physical keyboard/picker/full001.1.
T173 diagnostic history: первый compiled journey прошёл steps0–4 (create/password/remove/key+passphrase/keep), но step5 failed fixture No element: settings submit назывался Сохранить настройки, helper искал generic Сохранить. Исправлен test-only helper; edit row finder ограничен ExpansionTile, чтобы выбранный target в header не создавал duplicate match. Partial run .local/audits/t173-ui-first.txt не считается полной приёмкой; production source не менялся.
T173 second attempt .local/audits/t173-ui-corrected.txt passed steps0–1, step2 failed startup ready deadline30s (before actions/model acquisition). This is not a denied operation or a passing check. At inspection no locald remained running. Added fixed safe shell state/reason to fixture diagnostics and owned discovery cleanup wait to failure finally; no automatic retry or production timeout change. Re-run full journey on new owned fixture required.
T173 preliminary final evidence: terminalsession13953 exit0 T173_CREDENTIAL_UI_FINAL_PASSED, final current-source eight fresh drives .local/audits/t173-ui-final.txt each2tests passed (7/8/7/10/6/14/9/4seconds), eight stage markers. Earlier all-eight .local/audits/t173-ui-safe-diagnostic.txt also passed before strengthening raw string API marker scan/settings revision assertions. Final scan traverses raw decoded strings (including receipts), not JSON-escaped multiline PEM. terminalsession97718 exit0 T173_FINAL_CHECKS_PASSED/T173_CACHED_TARGET_REJECTED: format217files0changes, analyzeNoissues7.7s, root232tests22s, rebuilt defaultUI2tests22s/fresh2tests5s; unrelated cached Foundation target2tests22s passed its own scenario but Credential harness rejected exact UI credential stage proof missing. Allsix target pairs rejected beforeSDK/build; bothPSscripts parseclean. Lychee514OK53unique0errors/diffcheck0(CRLFwarnings). Scope no production source change, full locald/Windows suites not repeated. Fresh readonly review still pending; T173 OPEN; fullQ09/T035–T038/001.1 remainOPEN.
Приёмка T173 завершена 2026-10-12: fresh completed readonly compiled_credential_ui_review — замечаний нет, готов только scoped increment; sevenfiles source был заморожен до FINAL. Reviewer прочитал actualsource/contracts и journals, independently tests не повторял. terminal13953 exit0 T173_CREDENTIAL_UI_FINAL_PASSED: .local/audits/t173-ui-final.txt eight separate fresh drives, each2tests7/8/7/10/6/14/9/4s, all8markers. normal app.main/actualowner/DPAPI native path; none→password→remove→key+passphrase→keep→selection→selecteddelete→emptyreopen; credential revisions1/2/3/4/4, connection/trust1, settings1/2/3, store7/exact7unique receipts; current persisted metadata atnewgeneration beforeeachstage; cancellation no effects and transientsecret clear; CRLF reveal/hide exact; decodedstrings profiles/settings/recent no syntheticsecret markers. Previous all8 safe-diagnostic run also passed before final marker/settings assertions; failedfirst/second attempts remain recorded separately, historical startup timeout cause not established. terminal97718 exit0 T173_FINAL_CHECKS_PASSED/T173_CACHED_TARGET_REJECTED: format2170/analyzeNoissues7.7/root232tests22s/defaultrebuiltUI2tests22s+fresh2tests5s; cachedunrelatedFoundationown2tests22spassed butcredentialproofmissing exactrejection. All6targetpairs rejected beforeSDK; bothPSscripts syntaxclean. Lychee514OK53unique0errors/diffcheck0 incl pre-review spec evidence check; CRLF/oldworklint warnings preserved. Full locald/Windows suites not repeated, production package/application source unchanged. T173 closed, T035–T038/fullQ09/DBblob binding/scans/physicalkeyboard/picker/unknowninflightkill/reboot/otheruser/nativeharness/CI/full001.1 remainopen. docs have actual newcommand. Only exactsystem-denied ops/checks deferred/open withoutbypass; goalall20packages/60stages remainsactive. No commit/push/PR/release/merge.
- [x] T174 Принять восьмисессионный normal compiled native path Q10/T041: bootstrap_client client-sessions mode использует actual production LocalApiClient/verified NativeClientTransport и protected discovery. Один held peer parent плюс семь authenticated clients заполняют восемь canonical normal slots; девятый получает SERVICE_UNAVAILABLE без mutation, семь продолжают читать идентичную projection/owner generation. Explicit close одной сессии, bounded fixture reconnect≤5s, replacement и остальные читают тот же snapshot/generation; all owned clients закрываются, parent held peer survives/discovery unchanged. bootstrap_native_test автоматически требует marker в normal-owner runs. Root mandatory checks/locald analyze/actual compiled bootstrap regression/lychee/fresh readonly review до closure. Это не полный Q10 (16pending/32queue/partial frames/quotas/physical resource inventory) и не whole001.1.
T174 preliminary evidence: terminalsession68585 exit0 T174_CHECKS_PASSED, rootformat2170changes/analyzeNoissues7.3s/root232tests19s, localdanalyzeNoissues, actual compiledbootstrap_native_test passed incl client-sessions requiredmarker in normal held-owner paths; lychee514OK53unique0errors/diffcheck0. .local/audits/t174-*.txt. First packageanalyze warning unnecessary bang fixed before finalchecks; not counted as passed. Full locald/Windows suites not repeated (no production/packagehelper changes). Review pending, T174 OPEN; broaderQ10/001.1 not accepted.
- [x] T175 Исправить confirmed P2 supplementary compiled_eight_sessions_review: fixture watch проверял только допуск попытки, поэтому success connect started4.9s/finished8s мог принять вопреки заявленному reconnect≤5s. Перед publication replacement/marker проверить общий elapsed<5s; поздний connect не принимается, finally закрывает все owned candidates. Production handshake deadline неизменен; expectation относится к accepted replacement, не к принудительному завершению cleanup. Mandatory checks/compiled native regression/fresh readonly review до closure T174/T175. Первый clean report был скорректирован supplementary finding и не является final clean evidence.
Приёмка T174/T175 2026-10-12 завершена: fresh completed readonly compiled_eight_sessions_fixed_review — замечаний нет, готов только scopedincrement. Первый clean compiled_eight_sessions_review скорректирован supplementary confirmedP2 budget; исправлен общийelapsed guard послеconnect, beforeacceptedreplacement/marker. Lateconnect candidate принадлежит retired и закрывается finally; cleanup после5s допустим, productionhandshake deadline не менялся. terminal5885 exit0 T175_CHECKS_PASSED: .local/audits/t175-format.txt2170changes/analyzeNoissues7.4s/root232tests22s/localdanalyzeNoissues/actualcompiledbootstrap1test2m38s/lychee514OK53unique0errors/diffcheck0. Исторический t174compiled2m44s был pre-fix, не финальным clean evidence. Requiredclient-sessions mode в normalheld-owner paths проверяет1heldpeer+7actualproductionclient/nativeverifiedtransports/protecteddiscovery, ninthSERVICE_UNAVAILABLE, existingreadability/canonicalprojection/generation, explicitclose/replacement<5s, ownerlive/discoveryunchanged/heldpeerlaterread. Все ownedclients success/failure/retired закрываются. Source заморожен до FINAL; reviewer прочитал sources/contracts/logs, самостоятельно commands не повторял. Нет отдельного runtime late4.9→8s сценария; closure deadline defect установлен прямым guard/controlflow и currentcompiledregression. Форматтер oldworklint и CRLFwarnings сохранены. Production/app/packagehelper source не менялся; full locald/Windows suites, UI/manual/reboot/otheruser не повторялись. T174/T175closed, T041/fullQ10/full001.1 открыты. Exactsystem-denied ops/checks остаются deferred/open без обхода; остальные работы доступны. Goalall20packages/60stages active; no commit/push/PR/release/merge.
- [x] T176 Выполнить свежий последовательный command gate текущей реализации для T047: root enforce-lockfile/format/analyze/test; enforce-lockfile/analyze/full serial test всех трёх Dart packages; compiled bootstrap UI и все пять текущих foundation UI сценариев (two-window, concurrent-three, crash-observer, loss, credential eight drives); normal Debug и Release build обоих процессов, final format, lychee и diff check. Зафиксировать SDK/OS/lock/build identity, реальные terminal exitcodes и scope в evidence; актуализировать устаревшие status headers без расширения требований. Fresh readonly review документации по AGENTS.md до закрытия этой задачи. Полный native harness, CI run, network-blocked runtime, reboot, other-user и physical input этим не принимаются; T047/001.1 остаются открытыми до их полной приёмки. Только точные system-denied операции отложены без обхода.
Приёмка T176 2026-10-12 завершена: fresh completed readonly full_command_gate_evidence_review — замечаний не найдено, готов только документационный increment/current-command evidence; whole001.1 readiness не установлена. Source frozen до FINAL. Reviewer прочитал applicable AGENTS/package/source/scripts/logs и independently readonly сверил current hashes4locks/2manifests/3binaries perbuild; tests/builds самостоятельно не повторял, файлы не менял, private URI не выводил. Actual terminalsession37027 exit0 T176_CURRENT_COMMAND_GATES_PASSED: root232/protocol36/Windows29/locald84; все6rebuiltUIcommands с17drives (по2tests); normalDebug+Release; format2170before/aftergeneration; lychee514OK53unique0errors/diffcheck0. Actual post-build verifier exit0 T176_LOCKS_UNCHANGED_NORMAL_MANIFEST_HASHES_VERIFIED. Evidence в .local/audits/t176-command-gates/ и foundation-verification.md. T176closed; T047/alloriginalaggregate/fullnativeharness/test_entry/CI/networkblockedruntime/reboot/otheruser/physicalinput/unknowninflightkill/whole001.1 остаютсяopen. Production source в этом шаге не редактировался; только status/evidence docs. Exactsystem-denied ops не повторялись/не обходились; новыхdenials не было. Brandbook/hardcutover сохранены, goalall20/60active; no commit/push/PR/release/merge.
- [x] T177 Подключить первый compiled scenario T043: test_entry workspace-lifecycle использует build-time fixture-root/SID whitelist, проверяет protected root/testOnly self bundle/self image и отдельный verified normal bundle, затем выполняет существующий workspace_child probe через production Workspace/DPAPI/Isar. build-locald -TestBuild требует fixed owned fixture whitelist; test controls не импортируются normal locald. test-foundation-native -Scenario WorkspaceLifecycle собирает normal Debug и AOT test entry, создаёт уникальный protected owned fixture, выполняет normal test-flag negatives до/после manifest edit, test manifest/foreign-image/runtime-override negatives, actual creation/reopen/staging/corruption/preservation/prerequisite/no-owner probes и reject used fixture. Только retained launched Process handle, проверенные root boundaries до cleanup, никаких arbitrary PID/recursive deletes; logs safe, fixtures сохранены. Полный All всё ещё fail closed; эта partial local filesystem acceptance не выдаётся за disposable OS user/VM, compiled crash failpoints, fullQ или весь001.1. Root checks/locald analyze/actual compiled scenario/normal entry regression/lychee/fresh readonly review до closure.
T177 diagnostic history: first compiled scenario .local/audits/t177-native.txt terminalsession24547 exit1 failed before Workspace creation with TEST_SCENARIO_FAILED. PS fixture ACL used OI/CI inheritance flags; production requireOwnerOnlyFileAcl explicitly accepts only exact owner/SYSTEM FA ACEs without these flags. Fixed fixture ACL to InheritanceFlags.None; production guard unchanged. First failed fixture preserved, not a system denial or successful acceptance. Re-run on a fresh owned fixture required.
T177 second attempt terminalsession84145 exit1 (.local/audits/t177-native-fixed.txt): InheritanceFlags.None removed ACE inheritance but Set-Acl retained DACL_AUTO_INHERITED (SDDL D:PAI), still incompatible with the exact D:P production guard. No Workspace creation occurred. Fixture preparation now uses native CreateDirectory with the exact protected owner/SYSTEM SDDL, matching the existing adapter; it does not loosen production validation or change an existing private path. This is a fixture descriptor mismatch, not an OS/system denial. Both failed fixtures preserved. Build checks now inspect the output directory as well as its ancestors for reparse points; launched executables are restricted to the exact owned fixture subtree. Final fresh scenario required.
T177 third attempt terminalsession78772 exit1 (.local/audits/t177-native-exact-acl.txt): exact native root ACL validated; compiled workspace_child completed all cases, stdout had both required markers and the pinned native MDBX banner, stderr empty. Harness incorrectly required only two output lines, so final harness acceptance failed. Fixed explicit output allowlist (two required unique markers plus the known pinned native banner), no arbitrary stdout acceptance or production change. Actual compiled workspace cases succeeded but this failed harness run is not final T177 acceptance; fresh final run and mandatory checks required.
T177 final evidence pendingreview: terminal45174 exit0 T177_FINAL_CHECKS_AND_COMPILED_SCENARIO_PASSED (format2170/analyzeNoissues11.2/root23220/localdanalyze/normalentry+native-runtime+workspace-init6tests44s/nativecompiledscenario/lychee51453/diff0). После PS token disposal current-source rebuilt scenario terminal35123 exit0 T177_CURRENT_SOURCE_COMPILED_SCENARIO_PASSED; actual boundary negatives All/unbound whitelist/reparse output такжеexit0. FinalPSparseclean/postbuildformat2170. Safe evidence .local/audits/t177-*.txt/json и foundation-verification.md. Только fixed normal/shared production source unchanged; full locald/Windows suites не повторялись, ихT176baseline отдельный. T177open до fresh completed readonlyreview, fullT043/Q/001.1open.
- [x] T178 Исправить confirmed P2 compiled_native_workspace_harness_review: при Kill exception/WaitForExit false Dispose retained Process пропускался. Вынести cleanup в native-probe-process.ps1 с unconditional inner finally Dispose; сохранить fail-closed исходную ошибку/cleanup incomplete. test-native-probe-cleanup.ps1 проверяет шесть deterministic control-flow cases (notstarted/alreadyexited/running/Killthrow/Waitthrow/Waitfalse) с Dispose exactlyonce и сохранением error. Это model failure-branch proof, не искусственный kernel refusal/не OS termination claim. Actual compiled harness/current root checks/spec links/fresh readonly review до closure T177/T178; initial review с confirmedfinding не clean evidence.
T178 corrected evidence pendingreview: deterministic cleanup6cases passed .local/audits/t178-cleanup.txt, Dispose exactlyonce/errorspreserved (model, no kernel failure claimed). actualterminal69035 exit0 T178_CHECKS_AND_COMPILED_SCENARIO_PASSED: format2170/analyzeNoissues/root232/native rebuilt scenarioaccepted/lychee51453/diff0. FourPSfilesparseclean; unchangedDart/package/shared source keeps T177focused6tests44s as separatepriorregression. First completed T177review hadoneconfirmedP2, notclean; final freshreadonlyreviewpending T177/T178open.
Приёмка T177/T178 2026-10-12 завершена: fresh completed readonly compiled_native_workspace_cleanup_fixed_review — замечаний нет, готов только scopedincrement; whole001.1readiness не установлена. Все10reviewedfiles frozen до FINAL. Firstreview confirmedP2 Dispose-after-Kill/Wait исправлен unconditionalfinallyhelper и six model failure checks; firstreview не clean evidence. Currentterminal69035 exit0 T178_CHECKS_AND_COMPILED_SCENARIO_PASSED: format2170/analyzeNoissues7.1/root232tests18s/currentrebuiltcompiledworkspaceaccepted/lychee51453/diff0; parser4PSfilesclean. Actualfixture679c34e741f542af806a9c7491f4b108 содержитexpectednegatives, positive2uniquemarkers/stderrEmpty/accepted.json; model6cases proveexact1Dispose/errorpreservation, не kernelKillfailure/terminationwhenrefused. Reviewer прочиталsource/contracts/logs/proofs, tests/builds independentlynotrepeated, noedits. SeparateunchangedDartfocusedregression6tests44s сохраненакакpriorT177evidence, fullnative/WindowsT176baseline notnewrun. Allfailedfixturehistory preserved; defaultAllfullT043/compiledcrash/CI/offline-network/reboot/otheruser/physical/unknowninflight/allQ/full001.1open. Exactdeniedoldcleanup/HyperVnotrepeated/bypassed, no newdenials. Brandbook/hardcutoverpreserved, all20/60goalactive, no commit/push/PR/release/merge.
- [x] T179 Расширить compiled native harness T043 до CoreStorage: восемь allowlisted cases (workspace-lifecycle/repository/credential-lifecycle/mutations/api/channel/service-lifecycle/resource-limits) исполняют существующие actual Workspace/StateStore/custody/coordinator/router/native channel/lifecycle/quota probes в отдельных AOT child processes. Один build-time whitelisted protected root/SID, отдельные case directories; protected exclusive claim до любой case операции предотвращает concurrent/repeated/failed-case reuse. Unknown scenario/runtime paths отвергаются. Required unique markers и safe allowlist на каждый case, known bounded capacity counters; budgets180s кроме existing resource-limits360s, runtime deadlines unchanged. CoreStorage строит normal/test bundles один раз, normal/test negatives обязательны, per-case positive+reuse negative, final metadata только после всех case successes. WorkspaceLifecycle backward command сохранён, All/fullT043/Q/001.1 остаются open. Принятые shared/production probes не менять; честно различать repository snapshots, controlled router/time и actual native pipe от fullnormalowner/UI/compiledcrash. Root mandatorychecks/localdanalyze/native all8+workspace regression/cleanup checker/lychee/fresh readonly review до closure.
T179 first-run history: terminal94613 exit1 .local/audits/t179-core-first.txt. Compiled workspace/repository/credential snapshots/mutations passed (1.3/77.9/0.5/1.0s). Actual API also emitted all successful markers with emptystderr/code0, but driver allowlist omitted existing NATIVE_ROUTER_METHODS_PROVED and rejected it. Added that required marker and reviewed native channel's three existing intermediate/proof markers as required too. No shared/production probe changed. Failed composite fixture preserved, no full CoreStorage acceptance claimed; remaining cases not yet executed. Final complete fresh run required.
T179 final evidence pendingreview: terminal81703 exit0 rootformat2170/analyzeNoissues/root23218/localdanalyze/cleanup6model/directcompiledCoreStorage8passed/rebuiltWorkspaceLifecycle/lychee51453/diff0. Cases elapsed1.2/76/.6/1.2/.3/.5/.3/211.7s; root5f64091ba55449f88562d1bceffe3c32 accepted.json8completedcases. Additional actualconcurrent samecase2compiledchildren in previouslyunused channelcase of preservedfirstfailedfixture gaveonewinner0+oneloser1TEST_FIXTURE_USED, t179-concurrent-claim.json; no reset/oldfixturefullgreenclaim. Comment-only correction directory→CREATE_NEWclaim followedrootchecks terminal97190 exit0 finalformat2170/analyze/root232, no behavior change/repeated native needed. FinalPSparserclean. Evidence t179-*.txt/json/foundation-verification.md; T179open freshreviewpending. FullAll/T043/Q/001.1open.
Приёмка T179 2026-10-12 завершена: fresh completed readonly compiled_core_storage_harness_review — замечаний нет, готов scopedincrement; whole001.1 notestablished. Все7reviewedfiles frozen до FINAL. Reviewer directlyread source/contracts/logs/actualpositive+reuse/claims/accepted/concurrency artifacts; tests/builds notindependentlyrepeated/noedits. Currentactualterminal81703 exit0 rootchecks232/localdanalyze/cleanup6/all8compiledcases/workspacecompatibility/lychee51453/diff0. Caseelapsed1.2/76/.6/1.2/.3/.5/.3/211.7; additionalconcurrent2compiledsamecaseonewinner0+oneTEST_FIXTURE_USED1; finalcomment-onlyrootchecks97190exit0 format2170/analyze6.5/root23220. Historyfailedfirstcompositekept, partialfixture notfullgreen. Native/shared/productionruntimeunchanged; scopes repositorysnapshot/controlledrouter/controlledclock/sameprocessnativechannel/prepared10kreceiptsexplicit. T179closed; fullAll/T043/compiledcrash/CI/offline/reboot/otheruser/physical/unknowninflight/fullQ/whole001.1open. Exactdeniedopsnotrepeated/bypassed, no newdenials; brandbook/hardcutoverpreserved; goalall20/60active, no commit/push/PR/release/merge.
- [x] T180 Подключить compiled CommitRecovery T040/T043: fixed routes для before/after hard commit crash и controlled native-failure/DPAPI availability faults с fresh-process verifiers. Writer и verifier имеют разные protected exclusive claims, fixed общий case directory, verify требует существующий writer claim/directory и не создаёт новую базу. Native helper state_store_crash_child unchanged: before внутри незавершённой native transaction, after после StateStore.commit; driver ждёт unique CRASH_BOUNDARY≤30s, проверяет retained launched image/lifetime, kill только ownedchild+wait10s, затем новый AOT verifier ожидает state/profile/credential/receipt0 либо1 и DPAPI secret. Controlled faults не выдавать за реальные OS denies; before branch — native row transaction, не real API/coordinator call. Normal flags/manifest/path guards сохранены, повтор обеих фаз отвергается, partial failed files сохраняются. Root mandatorychecks/localdanalyze/focusedcrashregression/actualCommitRecovery+CoreStorage+Workspace regression/cleanupchecker/lychee/freshreadonlyreview до closure. Fullinit/replycrash/reboot/otheruser/fullQ/001.1open.

Проверки T180 выполнены 2026-10-12: terminal session26464 exit0 T180_ALL_CHECKS_PASSED — format217/0changes, analyze без замечаний, root232 tests, locald analyze, state_store5 tests2m20s, cleanup6 models, compiled CommitRecovery4 pairs, CoreStorage8 и отдельный WorkspaceLifecycle, lychee/diff exit0. PowerShell Parser clean. Evidence: docs/development/foundation-verification.md и .local/audits/t180-*.txt/json. Native negative effect assertion исправлен creation→cases. Новых системных запретов нет; только ранее отклонённые конкретные действия остаются deferred/open без обхода. T180 пока открыт до завершённого fresh readonly review; полная001.1 не принята.

Приёмка T180 завершена: fresh completed readonly compiled_commit_recovery_review — замечаний не найдено; готов scoped increment, готовность всего001.1 не установлена. Все7files заморожены до FINAL. Reviewer прочитал источники, контрактную цепочку, logs/claims/four pairs/reuse artifacts/accepted proof и независимо сверил все6 normal/test bundle hashes; tests/builds не повторял и файлов не менял. Подтверждённых нерешённых замечаний нет. T180 закрыт; fullinit/APIreply/reboot/otheruser/physical/fullAll/Q/001.1 остаются открытыми. Только конкретные отклонённые системой действия deferred/open без обхода; остальные проверки продолжаются. Goalall20packages/60stages active, no commit/push/PR/release/merge.

- [x] T181 Подключить InitializationRecovery к compiled native harness: nine compile-time guarded boundaries actual Workspace.open, enabled only separate TestBuild с fixed root/SID. Normal build не допускает установки/invocation handler, runtime flags/manifest не включают probe. Writer/verifier fixed routes и separate exclusive claims, protected boundary record только metadata hashes; writer подтверждает shape/ACL/files, driver kill retained child после flushed boundary, новый verifier проверяет partial blocked или valid initial-empty promotion/reopen и сохранность key/manifest identity. Partial native DB/lock byte invariance/full secret scans не подменять hashes; VM regression отдельно. Mandatory root checks, full serial locald suite, actual InitializationRecovery, CommitRecovery/CoreStorage/Workspace regressions, cleanup checker, PSParser, links/diff и fresh readonly review до closure. APIreply/reboot/otheruser/fullAll/fullQ/001.1 остаются открытыми; точные ранее system-denied операции не повторять/не обходить.

Промежуточное свидетельство T181: первый AOT InitializationRecovery terminal65423 exit0, все9pairs/guards/reuse прошли; fixture fb298ca360ef47b6b4f2e50f92828555 сохранён. Normal initialization_probe_test прошёл; PSParser2scripts clean. Последовательный полный gate session72855: rootformat220/0changes, analyze7.2s/root232tests20s/localdanalyze фактически прошли; full serial locald suite и следующие compiled regressions ещё выполняются. Evidence в foundation-verification.md/.local/audits/t181-*.txt/json. Это не final acceptance; T181 остаётся открыт до terminal checks и completed fresh readonly review.

- [x] T182 Исправить найденный при собственной проверке пробел T181: одинаковое число файлов не доказывает сохранение inventory. Проверять exact ожидаемые имена и типы на каждой стадии. Отдельный fixed single-use AOT case до открытия native DB: writer crash после создания4files, driver переименовывает только owned synthetic workspace.isar в unexpected.isar, verifier обязан отвергнуть inventory до Workspace.open; replacement bytes неизменны, обе фазы нельзя повторить. Девять обычных pairs остаются отдельными successes, negative отмечен отдельно в proof. Первый T181 run сохранён как pre-fix evidence, не final inventory acceptance. После исправления current mandatory root checks, locald analyze, fresh InitializationRecovery/negative, links/diff и independent review обязательны; full serial package suite продолжить через тот же live handle, не перезапускать из-за observation timeout.

T181/T182 checks завершены: terminal72855 exit0 T181_CHECKS_PASSED, full serial locald85tests14m34s/cleanup6/compiledCommit4/Core8/Workspace/links51453/diff0. Исполняемые package tests/production source не менялись во время suite; helper inventory fix проверен отдельно. Final terminal41570 exit0 T181_T182_FINAL_CHECKS_PASSED: current format220/0/analyze6.1/root232tests15s/localdanalyze/freshInitialization9pairs+inventorynegative/links51453/diff0. PSParser2scripts clean. First9pair artifact pre-fix сохранён; finalproof inventoryReplacementRejected=true. Evidence foundation-verification.md/.local/audits/t181-*.txt/json/t182-*.txt/json. T181/T182 пока открыты до fresh completed readonly review; whole001.1 не принята, denied exact actions не повторялись/не обходились, новых запретов нет.

Приёмка T181/T182 завершена: fresh completed readonly compiled_initialization_recovery_review — замечаний не найдено; готов scoped increment, готовность всей001.1 не установлена. Все12files заморожены до FINAL. Reviewer прочитал source/package/contract chain/evidence и независимо readonly сверил manifests/hashes всех6normal/test binaries,9case claims/markers/reuse/key+manifest identities и inventorynegative genericfailure/empty stdout. Его сверка artifacts exit0; tests/builds самостоятельно не повторял, файлов не менял. Подтверждённых нерешённых замечаний нет. Final Initialization fixture d455196e9c38498a8ebc7fa86483b5b2/format1/9success pairs/inventoryReplacementRejectedtrue; first pre-fix fixture сохранён. Fullpackage85 и currentroot232 checks реальны; остальные fullAll/APIreply/secretmarker/reboot/otheruser/physical/fullQ/001.1 gates остаются открытыми. Только конкретные ранее отклонённые системой действия deferred/open без обхода; новых запретов нет. Goalall20/60 active; no commit/push/PR/release/merge.

- [x] T183 Подключить compiled SecretMarkers для native persistence части Q05/T040: compile-time base64 JSON synthetic fixture password/PEM/passphrase, отдельные fixed writer/verifier routes/claims. Actual Workspace/DPAPI/Isar/coordinator/ApiServer с controlled session сохраняют2profiles+settings3commits, проверяют protected calls до записи и после каждого commit сканируют все owned case files. Fresh process читает обычные profile/settings payload native способом до DPAPI, затем открывает Workspace и раскрывает все3access secrets+receipt-key через real CurrentUser protection. API responses не содержат secret/blob/ref/key fields или markers; ошибки не echo input. Byte scanner ловит raw UTF8/UTF16LE/base64, PEM body/decoded body и raw generated receipt-key, потоковый64KiB read с overlap и buffer copies/cleanup. Проверять leak canaries, chunk boundaries, очистку producer buffer, exactroundtrip; stdout/stderr strictallowlist. Не сканировать source/test binaries с намеренными fixture inputs или чужой OS Temp; не выдавать controlled router за normal owner/UI/auth/полный Q05. Production code неизменен. Mandatory rootchecks/localdanalyze/actualfreshSecretMarkers/Workspace regression/cleanup/links/diff/fresh readonly review до closure; fullpackage85 предыдущий separate baseline, не новый run. Только точные ранее system-denied actions deferred/open без обхода.

- [x] T184 Довести failure cleanup нового T183 helper: при exception observer после реального unprotect очистить полученный clear buffer до rethrow; scanner patterns/input map очищать во внутреннем finally даже при cleanup error. Не освобождать fixture lease, если direct metadata native close не подтверждён или Workspace/StateStore сохранил reservation. Failed process остаётся fail closed и ограничивается retained parent cleanup; normal success/markers только после закрытия всех ресурсов. Current mandatory checks/actualfreshSecretMarkers/freshreview до closure. Не заявлять, что реальные native close refusals были индуцированы.

- [ ] T185 Проверять exact owner-only directory/file ACL перед direct native metadata open T183. В отдельном fixed single-use synthetic case сохранить те же данные, добавить Read ACE для BUILTIN Users только owned workspace.isar, потребовать generic refusal/empty stdout до native loader/open и неизменный DB hash; повтор failed phases отвергнуть. Это controlled unsafe ACL, не другой пользователь/реальный OS deny. Fresh current root/package analyze/compiledSecretMarkers+negative/Workspace regression/links/diff/freshreadonlyreview до closure. Старые pre-ACL proofs сохранить как partial history.

T185 negative 2026-10-12 отклонён ОС: shell65652 terminalexit1, Set-Acl tools/test-foundation-native.ps1 line177 требует отсутствующую SeSecurityPrivilege. Fixture сохранён, accepted proof не выпущен; preceding positive writer/verifier завершились, это не полный negative acceptance. Точная операция Set-Acl на workspace.isar этого synthetic fixture deferred/open, не повторять через иной инструмент/runner. ACL guard в helper реализован; проверка остаётся открытой. Обычный SecretMarkers запускает только доступную persistence часть и честно пишет unsafeAclRejected=false. Отдельный SecretMarkersUnsafeAcl предназначен для подготовленной disposable среды, сейчас не запускается и не считается пройденным.

Точный новый denied target: H:/projects/unng/serverdeck/.local/native-acceptance-359dac21f62d4daeb411454d7aaaf56a/cases/secret-markers-unsafe-acl/ServerDeckNext/v1/workspaces/default/workspace.isar. Файл фактически существует после отказа; after-failure SHA2562F3ED59EDF164F179803230019A0C22D26CC2C851A79C4D8C601F81A5AF51B62. Before-hash не сохранён отдельно, поэтому сохранность байтов этого failed ACL attempt не заявлена. Каталог не удалялся, ACL после отказа не восстанавливался/не менялся повторно.

Доступные checks T183/T184 завершены: shell65652 rootformat223/0/analyze5.9/root235tests14s/localdanalyze прошли до exactOS-denied Set-Acl; after harness separation shell60534 terminalexit0 T183_AVAILABLE_CHECKS_PASSED: freshcurrent SecretMarkers positive+freshprocess+reuse+normalguards, rebuiltWorkspace/links51453/diff0, PSParser2scripts clean. Current Dart source не менялся после rootchecks, только harness/docs. Proof persisted/freshProcessVerifiedtrue/unsafeAclRejectedfalse. Historical pre-ACL runs19836/27979/93657 сохранены отдельно. Evidence foundation-verification.md/.local/audits/t183-*/t184-*/t185-*. T183/T184 пока открыты до completed freshreadonlyreview; T185 negative deferred/open, fullQ05/Q06/001.1 не приняты. Denied action не повторялась/не обходилась; остальные checks выполнены.

- [x] T186 Исправить2confirmed P2 fresh compiled_secret_marker_persistence_review: scanTree сразу после третьего settings commit, до read/close; внешний try/finally включает input validation/scanner preparation/SID/hash/mutex acquisition, nullable obtained lease закрывается и при acquired=false, patterns/input cleanup unconditional. Сохранить запрет освобождения held lease при unconfirmed native close/reservation. Первый review не clean, T183/T184 open. Current mandatoryrootchecks/localdanalyze/actualSecretMarkers/freshreadonlyreview до closure. T185 denied negative не повторять/не обходить, оставить открытым.

T186 correctedchecks shell50908 terminalexit0 T183_T186_CURRENT_CHECKS_PASSED: format223/0/analyze6.2/root235tests17s/localdanalyze/currentcompiledSecretMarkers persistence+freshreopen+repeat/normalguards/links51453/diff0. Firstcompleted review had2confirmedP2, notclean; fixesrecorded, freshreadonlyreviewpending. CurrentproofunsafeAclRejectedfalse, T185deniedactionnotrepeated. ExistingWorkspace60534regression separateactualevidence; no build/harness/workspacebehaviorchanges afterit. T183/T184/T186open untilcleancompletedreview, T185negative remainsdeferred/open.

T183/T184/T186 закрыты после завершённого fresh readonly compiled_secret_marker_cleanup_fixed_review: замечаний не найдено; готовность подтверждена только для этого increment. Reviewer проверил 12 файлов, связанные контракты, actual logs и сохранённые native artifacts, включая hashes шести binaries, claims, output guards и owner-only ACL. Оба предыдущих P2 исправлены. Current checks shell50908 exit0: format223/0, Flutter analyze без замечаний, root235tests, locald analyze без замечаний, compiled SecretMarkers persistence/reopen/reuse/normal guards, links514/53/0errors и diff0. Reviewer тесты и сборки не повторял. T185 negative остаётся открытым: отклонённая ОС Set-Acl операция не повторялась; proof unsafeAclRejected=false. Полные Q05/Q06/All/001.1 не приняты. Пропускаются только конкретные отклонённые системой операции и проверки; остальные работы продолжаются.
- [x] T187 Исправить два P2 aggregate ui_aggregate_acceptance_review перед закрытием T033–T037: после succeeded очистить owned canonical MutationIntent payload, сохранив безопасные method/id; unknown/queued/running/not-found продолжают удерживать immutable payload для same-id retry. Проверить password и PEM/passphrase до закрытия успешной формы, при неизвестном исходе и cancel. Подключить ru-RU framework localizations без language preference, русский navigation tooltip и regression на English OS для standard/custom labels при обычном и reduced motion. Сохранить UTC semantics истории. Root SDK/lock resolution, format/analyze/test, actual notice source preview, spec links/diff и fresh readonly aggregate review до closure. T185 denied operation не повторять; full native/manual/CI acceptance остаётся отдельным gate.
- [x] T188 Исследовать actual compiled credential journey startup failure после T187: shell67574 step3 readiness storageBlocked до действия, failed fixture f01a7a773a1f47bd8caceeff9af0910b сохранён, preceding0/1/2 passed, readonly persisted schema preflight passed. Установить причину runtime discovery pending/publication failure, проверить concurrent discovery readers/atomic replacement и нормальное reopen; исправить подтверждённый defect с deterministic regression, applicable checks и freshreview. Не заявлять sharing contention установленной причиной до доказательства. Не удалять evidence, не ослаблять guards, не повторять ранее denied Set-Acl/cleanup; full native credential regression и T038 остаются открытыми до actual complete success.
T033–T037/T187 закрыты после completed fresh readonly ui_aggregate_fixed_review: замечаний не найдено, готов только implementation/widget scope этих задач. Reviewer проверил все UI source/tests и цепочку спецификации, оба P2 исправлены. Current root evidence: format224/0, analyzeNoissues10.0s,237tests19s, links514/53/0errors/diff0. Source заморожен до FINAL. Tests/builds reviewer не повторял. Native shell67574 overallexit1/credential step3 startup storageBlocked не засчитан; T188/T038 остаются открытыми. Physical picker/keyboard, native lifecycle/fullQ/CI/full001.1 отдельно не приняты. T185 exact rejected ACL check остаётся открытым, не повторялся. Цель по всем20packages/60stages активна; no commit/push/PR/release/merge.
T188 закрыт после completed fresh readonly discovery_snapshot_publication_review: замечаний не найдено; готов только increment T188, не весь001.1. Eight reviewed files frozen до FINAL. Current shell24752 terminalexit0: format224/0, Flutter analyzeNoissues9.7s/root237tests20s, Windows analyzeNoissues/full31tests2m19s, locald analyzeNoissues/full85tests14m21s; links514OK53unique0errors/diff0. Actual rebuilt compiled credential journey passed all8fresh drives (each2tests); current fixture01c24d1c4b934921834b9e3cd1004a50 has8step proofs/storeRevision1,2,3,4,5,6,7,7. Targeted9paths+1actualDPAPI publication tests separately passed. Reviewer read actuallogs, sources/contracts/callers and native ABI/cleanup/read bounds; no tests/builds repeated. Diagnostics established a reproducible reader/publication defect and verified its correction, but the precise native error from the historical failed step3 was not captured and is not claimed. Failed original fixture/evidence preserved; final success does not erase previous failures. T185/fullT038/All/physical/reboot/other-user/CI/full001.1 remainopen. Exact previously rejected ACL/cleanup/HyperV actions were not repeated or bypassed; permissions/brandbook/hardcutover unchanged. Goal all20packages/60stages remainsactive; no commit/push/PR/release/merge.
- [x] T189 Добавить actual compiled UI unknown-inflight crash/reopen acceptance для T038/Q07/Q10: normal primary и fresh-process reopen используют неизменный app.main; observer использует production FoundationApp с acceptance-only verified native LossClient, сохраняет update через actual owner/Isar и подавляет только его reply. Parent удерживает verified child process handle, начинает monotonic4s bound до send signal, требует observer submitting+replyDropped, завершает именно owned UI до5sRPCdeadline без status/retry/normal close. Live primary подтверждает один durable effect/receipt того же requestId при прежнем owner generation, затем выполняет собственную mutation. New UI/owner читает3effects/recent без auto-save. Metadata-only proofs/strict cached-target rejection; no test controls in production entry. Не заявлять before-enqueue/running-commit/owner-crash/physical/offline/reboot coverage. Mandatory root checks, Windows analyze, actual rebuilt target+baseline regression, all10 target-pair guards, spec links/diff/fresh readonly review до closure. Denied actions не повторять, T185/full001.1 остаются open.
T189 закрыт после завершённого независимого readonly review unknown_inflight_ui_review: замечаний не найдено; готовность подтверждена только для T189. Reviewer проверил девять изменённых файлов, связанные production компоненты и цепочку требований, а также сохранённые логи и proofs. Текущий run34126 exit0: format225/0, Flutter analyze без замечаний, root237tests, Windows analyze без замечаний; actual rebuilt inflight primary/reopen прошли, observed killElapsedMs=187 до неизменённого RPC deadline5s. Baseline LossAcceptance прошёл; все10 несовместимых пар selectors и чужой cached target отклонены ожидаемыми guards. Links514/53/0errors, diff0. Reviewer проверки не перезапускал. T038, fullQ, All, CI, physical/reboot/other-user и весь001.1 остаются открытыми. Откладываются только конкретные отклонённые системой операции и проверки; T185 и ранее отклонённые cleanup/Hyper-V действия не повторялись и не обходились. Цель всех20packages/60stages активна; no commit/push/PR/release/merge.
- [x] T190 Согласовать package test command в .github/workflows/foundation.yml с quickstart: для всех трёх packages использовать dart test --concurrency=1, поскольку native tests используют общий SID namespace и build directories. Сохранить последовательный foreach и finally Pop-Location; намеренный незавершённый acceptance gate T044 остаётся. Проверить реальную команду на protocol package и links/diff, затем независимое readonly review. Не считать локальный прогон запуском GitHub workflow или завершением T044; production код и test cases не меняются.
T190 закрыт после completed independent readonly ci_serial_package_review: замечаний не найдено; готов только T190. Package foreach/finally и wrapper exit handling согласованы с quickstart; намеренный T044 failure сохранён. Reviewer подтвердил actual protocol36tests log и самостоятельно выполнил обычный git diff --check exit0. Все три файла untracked: обычный diff не подтверждает их whitespace. Дополнительно исполнитель проверил каждый через git diff --no-index --check против NUL: exit1 означает наличие добавленного содержимого; whitespace diagnostics отсутствуют. Local check не является запуском workflow; T044 и весь001.1 открыты. Никакие отклонённые системой операции не повторялись.
- [x] T191 Усилить actual compiled owner crash/recovery probe в packages/serverdeck_locald/test/bootstrap_native_test.dart и support/bootstrap_client.dart: production LocalApiClient/native authenticated transport подавляет только reply реальной durable create; driver останавливает свой retained Process locald после replyDropped, пока mutation pending, и наблюдает exit раньше4s от conservative pre-send marker (RPC deadline5s неизменён). Pending завершается SERVICE_UNAVAILABLE без status/retry/success; existing abandoned mutex/stale discovery/new generation/bootstrap-token checks сохраняются. Fresh verified peer читает persisted profile revision1 и committed receipt; recent содержит ровно один requestId. Это console native acceptance, не UI/reboot/pre-commit cancellation/fullQ. Production sources неизменны, root format/analyze/test, locald analyze, actual bootstrap_native_test --concurrency=1, links/diff и fresh independent review обязательны до closure. Отклонённые системой операции не повторять.
- [x] T192 Исправить confirmed P2 native_owner_lost_reply_review: run4 observer мог OpenMutex до owner acquisition. До observer/pending interval bounded25s дождаться protected discovery с verified build, serverPid именно запущенного owner и новым generation. Missing publication допускает polling, существующий испорченный/unsafe descriptor не скрывать; descriptor закрывается. Затем observer подтверждает mutex held без захвата и parent разрешает mutation. Тот же barrier сохраняет run5 stale-owner recovery. Production deadlines/observer API неизменны. Повторить mandatory root checks/locald analyze/actual compiled bootstrap/links/whitespace и fresh independent review; T191 не закрывать до clean результата.
T191/T192 закрыты после completed fresh readonly native_owner_observer_barrier_review: замечаний не найдено, готов только scoped console native increment. Первый confirmedP2 устранён protected owner publication barrier до observer/send; reviewer проверил всю цепочку требований/контрактов/задач/проверок, actual logs и owned-process/pending/recovery control flow. Current shell61762 exit0: format225/0, Flutter analyzeNoissues8.1s/root237tests19s, locald analyzeNoissues; rebuilt bootstrap1test2m34, ordered publication и observed exit41ms, persisted effect/receipt/new generation. Lychee514/53/0errors; individual untracked-file no-index whitespace diagnostics0. Reviewer tests/builds не повторял, файлы не менял. Historical failures/firstreview preserved; no unresolved confirmed findings forT191/T192. Полные T038/T040/Q/All/CI/UIownerloss/reboot/otheruser/001.1 остаются открытыми. Только конкретные system-denied операции/проверки deferred/open без повторения/обхода. Goalall20/60 active, brandbook/hardcutover unchanged; no commit/push/PR/release/merge.
- [x] T193 Подключить фиксированный последовательный запуск уже реализованной automatic acceptance в tools/test-foundation-available.ps1: четыре compiled native suites (CoreStorage включает WorkspaceLifecycle), production-client owner-loss bootstrap и шесть compiled UI suites, всего11phases. Каждый child сам rebuild/проверяет proof; без SkipBuild/override/disposable flags, отдельные ignored local logs, stop first failure без retry/cleanup/upload. Metadata-only result всегда fullAcceptance=false и содержит completed phases/status/exclusions; ListOnly показывает scope без SDK/build. Exact denied unsafe ACL/manual/reboot/other-user/fullQ не запускаются; All/T043/T044/T048/001.1 не закрывать этим command. Проверить PSParser/ListOnly, actual full11phase run, links/whitespace и fresh independent review; production/Flutter код неизменен.
T193 закрыт после completed fresh readonly available_acceptance_dispatch_review: замечаний не найдено; готов scoped fixed aggregate. Reviewer проверил6files, связанные wrappers/build/sdk/contracts, actualresult/master и окончания11phase logs, fixedscope/exit propagation/proofs/environment/location/exclusions. Подтверждённых нерешённых замечаний нет. Actual full11phase run82063 exit0 принят только как available automated coverage; metadata fullAcceptance=false. Failure propagation оценена по source, искусственный failure run не выполнялся. Dispatcher не делает cleanup; existing bootstrap child сохраняет прежний собственный fixture cleanup. Current links после closure записаны отдельно .local/audits/t193-links.txt; шесть файлов индивидуально проверены no-index whitespace (content exit1/diagnostics0). Root/production code неизменен, предыдущие T192 checks не выданы за новыйrun. T043/T044/T048/fullQ/All/CI/manual/full001.1 открыты; только конкретные отклонённые системой действия deferred/open без повторения/обхода. Goalall20/60 active; brandbook/hardcutover preserved; no commit/push/PR/release/merge.
- [x] T194 Добавить actual native pipe/session queue lifecycle в packages/serverdeck_locald/test/support/native_queue_scenarios.dart, подключить к channel_scenarios и strict markers tools/test-foundation-native.ps1. Production LocalApiClient/NativeClientTransport/ServerChannel/auth/kernel peer checks + actual coordinator/Isar/DPAPI; только scheduling защиты синтетического password контролируется существующим GateProtection. Проверить last-requester disconnect queued→not-found/no state effect→explicit same-id retry; duplicate requester остаётся queued и commit once; running operation переживает потерю всех requesters и получает committed receipt. Прежний generation, последовательные store revisions и один receipt на каждый requestId. Controlled readiness/namespace/self-image fixture не выдавать за отдельные UI окна/normal owner/fullQ10. Не добавлять production hooks. Root format/analyze/test, locald analyze/targetednativechannel, rebuilt compiled CoreStorage со strict new markers, spec links/whitespace/fresh review до closure. Exact denied actions не повторять.
- [x] T195 Исправить confirmedP2 native_queue_disconnect_review: LocalApiClient.close сначала отправлял session.close, поэтому T194 не доказывал native EOF→ServerChannel revoke→detach. Сохранить реальные NativeClientTransport в owned fixture до возврата endpoint, в обоих раундах напрямую закрывать этот transport без graceful session.close. Наблюдать реальные pending failures и status/revocation/cancel/retry/duplicate/running условия; прежний cleanup clients/channels/pipes сохраняется. Production hooks/протокол/deadlines неизменны. Обновить evidence, повторить mandatory root/locald/nativechannel/compiledCore/links/whitespace/fresh review; T194 не закрывать до clean result.
T194/T195 закрыты после completed fresh readonly native_queue_abrupt_loss_review: замечаний не найдено; готов scoped native queue increment. Первый P2 graceful close устранён прямым закрытием retained NativeClientTransport; reviewer подтвердил actual EOF→ServerChannel close→session revoke→detach, duplicate/status registration ordering, single effects/receipts, generation и cleanup/strict proofs. Current shell32962 exit0: format226/0/analyzeNoissues8.0s/root237tests14s/locald analyze, nativechannel1test9s с3markers, compiled CoreStorage all8cases/resource177.4s; fixture239eb51f2a3f45e88c2593bd1a5b4e03 accepted.json/channel.stdout проверены reviewer readonly. Lychee514/53/0errors и individual no-index whitespace diagnostics0. Reviewer tests/builds не повторял. Исторический graceful run не принят за abrupt loss. Нет unresolved confirmed findings. FullT041/Q10/normal-owner/actual UI process death/001.1/All/CI/manual остаются открытыми; direct transport loss не выдаётся за отдельный UI process crash. Native close refusal не индуцировался; exact system-denied actions не повторялись/не обходились. Goalall20/60 active; no commit/push/PR/release/merge.
- [x] T196 Добавить actual native framing probes в existing native_queue_scenarios channel fixture: authenticated peers отправляют zero/oversize (>256KiB) header, частичный header и частичный body с поздним fragment через3s. Production partial deadline5s не продлевается поздним fragment: observed disconnect4.5–7s, malformed peer session revoked, никаких дополнительных server write attempts/echo/error. Store revision неизменён, surviving production client читает profiles при прежнем generation. Fixed new marker обязателен в compiled CoreStorage; controlled fixture не выдавать за normal owner/fullQ10/все codec ошибки. No production hooks/deadline changes. Root format/analyze/test, locald analyze/actual nativechannel/compiledCore, PSParser/links/whitespace и freshreview до closure; exact denied operations не повторять.
- [x] T197 Исправить confirmedP2 native_frame_deadline_review: zero/oversize могли пройти через5s partial timeout, не доказывая rejection по length. Наблюдать existing server read callback после второй handshake write (grant): actual received bytes и количество попыток payload read после четырёх header bytes. В length cases требовать ровно4bytes и0payload attempts, помимо revoke/noecho/noeffect/survivor. Это fixture-only counters без production hook/нового latency requirement. Сохранить absolute partialdeadline checks; повторить mandatory root/locald/nativechannel/compiledCore/PSParser/links/whitespace/fresh review; T196 open до clean.
T196/T197 закрыты после completed fresh readonly native_frame_length_observation_review: замечаний не найдено; готов scoped framing increment. P2 устраняется observation read attempts до await после4actualheaderbytes, поэтому oversized payload timeout не удовлетворяет0attempts. Reviewer подтвердил grant/read ordering, fragmentedheader support, zero/oversize/partial/noecho/revoke/noeffect/survivor и strict compiled proofs; inspected fixture6fe8f21caea245ffb5f74f4e15393745 accepted/channelstdout/emptystderr/reuserejection. Current shell39666 exit0 format226/0/analyzeNoissues8.0s/root237tests14s/locald analyze/nativechannel1test19s/CoreStorage8cases/channel10.6s/resource177s/links51453zeroerrors, individual no-index whitespace diagnostics0. Reviewer checks/builds не повторял. Format log package-resolution warnings в отдельном ignored work/isar-encryption-implementation не выданы за source defect или отдельный passed package run. Нет unresolved confirmed findings дляT196/T197. Fullnormal-owner/UI/allcodec/resources/T041/Q10/001.1/All/CI/manual остаются открытыми. Exact denied operations не выполнялись/не обходились. Goalall20/60 active, no commit/push/PR/release/merge.
T062 закрыт как superseded/replaced после completed fresh readonly storage_transition_obsolete_limit_review: замечаний не найдено; scoped replacement audit готов. Reviewer проверил3changeddocs, actual production/generated schema/wiring, требования DPAPI/plain metadata, T063/T017–T021 и непосредственно сохранённые T193 positiveSecretMarkers/11phase result и T197 CoreStorage8case proofs. Нет действующего persistence target для старой одной aggregate записи; RAM/canonical comparison не восстанавливают её. Исходный quota fix не выполнялся, review15/history сохранены. Обязательная проверка specs+audit522OK57unique0errors, индивидуальный no-index whitespace diagnostics0; новых builds/native/crypto tests не запускалось. Fullstorage/Q/All/CI/T039–T041/T045/T048/manual/001.1 остаются открытыми, denied actions не выполнялись. Goalall20/60 active; no commit/push/PR/release/merge.
- [x] T198 Подключить existing available11phase dispatcher к .github/workflows/foundation.yml после checks/Release build и до intentional full-acceptance failure. Windows Server2022/VS2022 остаётся CI target, не Windows11manual; job budget120min для fullserial package tests/build/11suites. Raw child logs не upload, dispatcher выводит safe phase markers/fullAcceptance=false; unsafe denied operations не добавлять. Проверить workflow schema/embeddedPS, spec links/whitespace и fresh independent review; actual GitHub execution требует отдельного evidence после публикации проверенного code snapshot, T044/001.1 не закрывать статическим lint/local T193. No PR/release/merge.T198 закрыт после completed fresh readonly ci_available_wiring_review: замечаний не найдено, готов только wiring. Reviewer проверил шесть файлов, SDK/build/runtime contracts, fixed dispatcher/wrappers и самостоятельно повторил ParseInput четырёх PowerShell blocks без ошибок. Actual executor checks: actionlint1.7.12 exit0, ParseInput4blocks zeroerrors, lychee514OK53unique0errors, individual six no-index whitespace diagnostics0. Hosted workflow/native/UI suites не запускались в T198; prior localT193 evidence отдельно. T044/full001.1/manual/unsafe denied checks остаются открытыми. Только конкретные системно отклонённые операции/проверки deferred/open, без повторения/обхода; остальные работы продолжаются. No commit/push/PR/release/merge.
- [x] T199 Закрыть native eight-session limit часть T041/Q10 через existing channel fixture: восемь actual named-pipe clients с production handshake/router/client получают grant, девятый закрывается без grant/error, все восемь продолжают read при неизменных revision/generation. После abrupt native transport close одного peer дождаться serving completion/count7, admit replacement/count8 и повторить reads; убрать дополнительные peers/count1. Dynamic idle-slot name исключает collision; compiled CoreStorage требует fixed marker NATIVE_EIGHT_SESSION_LIMIT_AND_REUSE_PROVED. Не заменять normal-owner/fullQ10; production limits/controls неизменны. Mandatory root checks/locald analyze/nativechannel/compiledCore, PSParse/links/individualwhitespace/fresh review до closure; denied actions не повторять.
T199 закрыт после completed fresh readonly native_session_capacity_review: замечаний не найдено; готов только eight-session registry capacity/reclamation increment. Reviewer inspected sixfiles/source/contracts/currentlogs/freshfixture60a96975b9b940c0b38abe1007abd591 accepted.json/all8cases/channelstdout/emptystderr. Current session77715 terminalexit0: format226/0, Flutter analyzeNoissues8.2s/root237tests14s/locald analyzeNoissues; targeted nativechannel1test21s, rebuilt CoreStorage8cases/channel11.1s/resource176.2s accepted. PSParser zeroerrors, lychee514OK53unique0errors, six individual no-index whitespace diagnostics0. Historical firstslot8 failure remains recorded; fixture namespaces fixed without modifying production slot0..7 contract. Proof establishes SessionRegistry capacity reuse, not reuse of the same physical pipe endpoint or normal owner/fullQ10. No unresolved confirmed findings forT199. FullT041/Q10/001.1/CI/manual and exact denied operations remainopen; no denied action retries/bypass, no commit/push/PR/release/merge. Goalall20/60 remainsactive.
- [x] T200 Проверить existing global32queued mutation limit T041/Q10 через native channel fixture: gate actual running create,32unique creates от3actual clients (≤12pending каждому), independent observer видит все queued/running, overflow→RESOURCE_LIMIT/not-found без revision/effect/receipt при работающих reads. Release gate:33exacteffects/receipts, same-generation explicit retry rejected request commits34th effect; workers detached/count1, strict compiled marker NATIVE_GLOBAL_QUEUE_LIMIT_AND_RECOVERY_PROVED. No production hooks/limits/deadline changes; helper controls only existing GateProtection. Rootformat/analyze/test/localdanalyze/actualnativechannel/rebuiltCoreStorage/PSParse/links/whitespace/freshreview before closure; fullQ10/normalowner and denied actions remain separate/open.
T200 закрыт после completed fresh readonly native_global_queue_review: замечаний не найдено; готов только global32queued native channel increment. Reviewer проверил6files/source/contracts/currentlogs/freshfixture7103d6f0410a4d629349fc566f307fd8 accepted.json/all8cases/newchannelmarker/emptystderr/reusefailure. Current shell66291 terminalexit0: format226/0, Flutter analyzeNoissues8.2s/root237tests16s/localdanalyzeNoissues; targetednativechannel1test24s, rebuiltCoreStorage8cases/channel12.3s/resource190.8s accepted. PSParserzeroerrors, lychee514OK53unique0errors, six individualnoindexwhitespace diagnostics0. First STORAGE_BLOCKED fixture failure retained; only acceptance gate.reached barrier fixed, no production changes. Pending12/11/10 avoids session16limit masking global32queue. Overflow no effect/receipt/notfound, reads available, drain33uniqueeffects/receipts and explicitsameidretry effect34 proved. No unresolved confirmed findings forT200. FullT041/Q10/normalowner/001.1/CI/manual remainopen; exact systemdenied actions deferredopen withoutretry/bypass. Goalall20/60 active; no commit/push/PR/release/merge.

## Phase 5: Convergence

Convergence assessment 2026-10-12, scope only Plan001.1. Inventory: 200 unique existing task IDs (187 checked,13 open); 12 native acceptance rows Q01–Q12, seven stage AC and the FR/SC mappings above, W01–W07 design and Constitution I–VIII considered. Checkbox state is not proof; corrective chains are assessed by resulting behavior, not superseded encrypted-aggregate requirements. This is a remaining-work assessment, not a completed whole-code independent audit. Eight actionable partial gaps, all HIGH because they block stage acceptance; no claim of completed full Q, native environment, CI, licenses or stage readiness. The tasks below decompose existing open gates rather than replace or close them. Existing scoped successes must be reused as evidence only within their demonstrated scope; do not rerun unchanged scenarios without a verification reason. Only exact system-denied operations/checks are deferred/open, without retry, tool substitution or runner transfer. Missing environment, an ordinary functional failure and a missing implementation are not system-denied operations.

- [ ] T201 [HIGH] Complete the native authentication/prerequisite/corruption matrix per FR-SVC-004/005/006/007, AC-SVC-BOOT and T039/Q03/Q04/Q06 (partial). Inspect current auth_native_test.dart, entry_native_test.dart, native_runtime_test.dart, paths/security/pipe tests and workspace cases; map each required row to actual existing assertions before adding missing cases in packages/serverdeck_locald/test/support/security_scenarios.dart and compiled test_entry.dart. Cover process/token acquisition failures, wrong SID/image/proof/replay/cross-identity/read-only write/remote rejection, unsupported API/build/platform, missing DLL/VC runtime, foreign existing pipe, receipt-key/DPAPI/blob/ACL/reparse/manifest/schema failures. Preserve existing data, thread identity and legitimate caller availability, safe refusal and resource cleanup; distinguish real native controls from controlled fault seams. Required other-user/VC/runtime environment results stay unproven until actually performed; exact refused T185 remains open and must not be retried or bypassed. Acceptance: criterion-by-criterion evidence, no ordinary request outside ready, no reset/fallback, unchanged protected bytes where required, actual normal-client baseline after negatives. Do not close whole T039 from selected cases.

- [ ] T202 [HIGH] Complete normal UI profile/offline/accessibility acceptance per FR-001/007/014, FR-002-LOCAL-01/02, AC-SVC-1A/1B/1C, SC-SVC-001/008, T038 and Q01/Q02/Q09/Q12 (partial). Extend integration_test/foundation_test.dart and existing UI drivers only for gaps beyond accepted two/three-window, credential journey and widget evidence: normal built client in isolated Windows11 user/profile, runtime network blocked, empty/five sections/future actions unavailable, CRUD/cancel/delete-selected/delete-last/reopen, 250/251 quota and invalid-input/noeffect, physical keyboard/focus/file-picker and both themes/four viewports/textscale200%. Verify the production Local API/locald/storage route and one writer during concurrent starts; normal UI must not substitute mocked repository or test data. Record each actual command/environment/proof and preserve failed evidence. Offline/network and physical results require their real conditions, not a declaration or a widget simulation; do not modify real user/server data or repeat exact denied environment operations.

- [ ] T203 [HIGH] Finish uncovered request/crash/recovery variants per FR-SVC-003/005/007/015, SC-SVC-004/005, AC-SVC-1B/1C/BOOT, T038/T040 and Q07/Q08/Q11 (partial). Reuse accepted loss-recovery UI, unknown-inflight UI, native owner-loss, StateStore commit and nine initialization failpoint evidence at their actual scope. Add missing production-client/real-locald variants: request lost before enqueue with another live window, late original after not-found and explicit same-id retry, changed-input rejection, API/coordinator commit boundaries including after commit/before reply, normal-owner UI death/retry/watchdog/version boundary and reboot durability. Use compile-time acceptance controls only in the separate test build; normal entry rejects them even after manifest changes. Verify original durable result/exactly one effect+receipt, retained draft/conflict semantics, no auto-repeat/reset, new-generation rehandshake and working survivor. Reboot requires actual isolated environment; do not substitute process restart. Kill only a retained owned verified child, not arbitrary PID. No closed historical task is erased.

- [ ] T204 [HIGH] Complete secret-marker coverage per FR-121/122/123 and SC-SVC-004, T040/Q05/Q06/Q08 (partial). Extend packages/serverdeck_locald/test/support/secret_marker_scenarios.dart, initialization/recovery drivers and test/security/private_marker_scan_test.dart only for uncovered normal UI/locald diagnostic and relevant initialization/API crash outputs. Current positive SecretMarkers verifies native persistence with controlled router session; it does not establish the whole normal UI/auth/diagnostic matrix. Use synthetic password/privateKey/passphrase and generated technical-key markers; scan the required owned DB/index/files/temp/stdout/stderr/log surfaces at their real boundaries and after restart, with ordinary metadata still readable. Distinguish intentionally embedded source/test fixture inputs from forbidden persisted/runtime plaintext, and define each scanned/excluded surface in evidence using the existing contract. No private user dumps/publication. Keep exact rejected unsafe-ACL negative separate/open; do not run or transfer it.

- [x] T205 [HIGH] Finish remaining native resource/backpressure/expiry acceptance per FR-012, FR-SVC-004/015 and Constitution IV, T041/Q10 (partial). Inventory existing resource cases, native_queue_scenarios.dart, channel/session tests and pipe worker teardown before adding uncovered cases in packages/serverdeck_locald/test/support/resource_scenarios.dart or the existing corresponding helper. Retain T196/T197 framing, T199 eight-session registry capacity and T200 global32queue proof without calling them normal-owner evidence. Cover per-session16 pending/backpressure, actual session expiry/timeout and required normal-owner resource composition, frame/receipt10k/DB64MiB/profile250/per-record bounds and read availability after rejected writes, cancellation/retry/duplicate/running semantics at required transport/owner boundaries. Verify real handle cleanup and required same-endpoint reuse separately from registry capacity reuse. No production deadline/limit relaxation or fabricated latency requirement. State which unchanged accepted cases already prove each row; add/run only missing coverage and justified regressions, then assess the entire T041 criterion set.

- [ ] T206 [HIGH] Complete full automatic harness and actual CI per FR-SVC-001/004/007/015/016, Constitution VII/VIII and T043/T044 (partial). After T201–T205 coverage is implemented and reviewed, wire all applicable available automatic cases into tools/test-foundation-native.ps1/test_entry.dart and the existing .github/workflows/foundation.yml. The present All throw and final workflow throw are evidence of incompleteness; remove each only when its real gate is met. Keep explicit prerequisite/refusal behavior for manual/deferred criteria and never report those as pass; a partial automatic result must remain distinguishable from full acceptance. Preserve SDK/hash/locks/generator/Debug+Release/AOT checks, fixed proof guards, safe output and no private artifacts. Actual hosted execution requires authorized publication of a reviewed source snapshot; T050 forbids publish/PR/release/merge without a separate user task, so no implicit push. Collect the real workflow revision/run conclusion and results rather than substituting lint or local T193/T198. Exact system-denied actions must remain excluded/open, including on runners. Do not make CI falsely green while required executable coverage is absent.

- [x] T207 [HIGH] Complete resolved native-chain notices per Constitution VIII, Plan reproducibility/licenses and T045 (partial). docs/development/third-party-notices.md establishes current Dart/font preview and the DLL/release asset identity, but the missing resolved Rust dependency graph is not proved by the unlocked build script or a new resolution. Establish authoritative source/dependency coverage for the actual bundled DLL without guessing versions or claiming a replacement build as its provenance. Finish required license/notice/corresponding-source material, then update tools/collect-third-party-notices.ps1 and build wiring to generate and include complete THIRD_PARTY_NOTICES.txt in both actual bundles. Verify deterministic complete inventory/texts and matching native/Dart/font versions and failures preserving prior output. Do not select the project's license or publish a release; leave unsupported source/provenance claims open with concrete evidence rather than treating preview distributionReady=false as complete.

- [ ] T208 [HIGH] Complete current instructions, whole checks/manual acceptance and final review/audit per FR-SVC-016, all seven stage AC, stage SC mappings, Constitution VI/VII and T046–T050 (partial). Correct stale current-status statements in README.md/docs/development/foundation.md/quickstart.md while preserving historical evidence: scoped unknown-inflight UI/owner-loss/queue/session work is implemented, but full Q remains open. After the preceding implementation tasks, perform the complete current quickstart command set/all three package suites/both builds/normal native Windows integrations and links; record actual exitcodes/current revision/environment/scope. Execute all still-required Q01–Q12 conditions, including real reboot/other OS user/physical/offline, in an authorized isolated environment without retrying exact denied operations; unavailable or denied criteria remain explicitly open. Run final fresh whole-code/package review under AGENTS.md, fix confirmed findings and repeat checks/review to a completed clean report. Reconcile every FR/AC/SC/Q and original open task against authoritative evidence; only then close its checkbox and decide stage readiness. Do not advance001.2 across unmet mandatory dependencies, replace full acceptance with partial proofs, or mark the overall20package/60stage goal achieved.

Convergence Phase5 independent review: completed fresh readonly convergence_remaining_gate_review, замечаний не найдено; готов к реализации только backlogT201–T208. Reviewer inspected original stage artifacts/current helpers/guards/notices and two saved CoreStorage proofs; confirmed preservation of200originalIDs/187checked/13open, existing scoped successes and fullQ/manual/CI/license gaps. This does not complete the stage or replace final whole-code review. Mandatory links actual514OK53unique0errors; individual tasks no-index whitespace diagnostics0. No new code/tests/builds/hosted/manual execution, no exact system-denied retries/bypass, no commit/push/PR/release/merge. Convergence outcome tasks_appended; next SpecKitImplement work starts T201 and follows these dependencies while original gates stay open. Overall20package/60stage goal remainsactive.
- [x] T209 Реализовать T201/Q03/Q04 native channel authentication increment: production LocalApiClient через actual pipes с неверными bootstrap proof/build/expected server image hash не получает grant, session/effect отсутствуют. Read-only grants допускают profiles.read, profiles.create→FORBIDDEN без эффекта/receipt, повтор read работает; detach/count0, затем прежний legitimate mutation baseline. Existing peer helper принимает только test-owned inputs; production API/limits/trust unchanged. Compiled CoreStorage требует marker NATIVE_AUTH_REFUSAL_AND_READ_ONLY_PROVED. Это не full auth/process-token/foreign-user/remote/replay/prerequisite/corruption matrix: T201/T039 remainopen. Rootformat/analyze/test/localdanalyze/nativechannel/rebuiltCore/PSParse/links/individualwhitespace/freshreview перед closure; точные denied actions не повторять.
T209 закрыт после completed fresh readonly native_auth_refusal_review: замечаний не найдено; готов только native proof/build/expected-server-hash refusal и read-only capability increment. Reviewer inspected6files/source/contracts/currentlogs/freshfixture7615875b8b0b4b139c7f64b9f64921a3 accepted.json/all8cases/channelproof/emptystderr. Current shell79406 terminalexit0: format226/0, Flutter analyzeNoissues7.4s/root237tests20s/localdanalyzeNoissues, actualnativechannel1test23s, rebuiltCoreStorage8cases/channel12.6s/resource212.9s accepted. PSParserzeroerrors, lychee514OK53unique0errors, six individualnoindexwhitespace diagnostics0. No grant/session/revisioneffect for badproof/build/expectedhash; read-onlywriteFORBIDDEN/noeffect/receipt, reads remainavailable, native detach/count0 and legitimate baselineproved. No unresolved confirmed findings forT209. T201/T039/fullQ03/Q04/Q06/001.1/CI/manual remainopen, including process/token, foreignuser, remote/replay, runtimeprerequisites/corruption. Exact deniedactions not retried/bypassed; no productionchange, commit/push/PR/release/merge. Goalall20/60 remainsactive.
- [x] T210 Реализовать T201/Q03 native identity-query failure composition: acceptance-only Windows helper вызывает production RetainedProcessIdentity.open с invalid nonzero DWORD PID и processUserSid с null process handle, требует original IDENTITY_UNAVAILABLE и unchanged current process SID. Native channel сначала делает real kernel peer verification, затем передаёт подтверждённую original native error на initial/repeated handshake stage. Четыре случая требуют exact1/2peerchecks,0/1hello writes/no grant/error, count0/no revision effect; subsequent legitimate baseline работает. Helper errors не должны masquerade as expected failure: отдельный confirmation marker после exact code/SID assertions. CompiledCoreStorage fixed marker NATIVE_IDENTITY_QUERY_FAILURE_CLOSED_PROVED. Контролируемые invalid inputs, не реальный отказ прав у pipe peer/foreign user и не проверка thread-token identity. T201/T039/fullQ03 remainopen. Rootformat/analyze/test, Windows/localdanalyze, actualnativechannel/rebuiltCore/PSParse/links/individualwhitespace/freshreview до closure; denied actions не повторять/обходить.
T210 закрыт после completed fresh readonly native_identity_query_failure_review: замечаний не найдено; готов только controlled native identity-query failure composition. Reviewer inspected7files/source/contracts/currentlogs/fixturec9b38f5f37ba45008b50f9571536bfc3 accepted.json/all8AOTcases/strictmarker/emptypositivecase stderrs/normalcontrols. Current shell63969 terminalexit0: format227/0, Flutter analyzeNoissues10.7s/root237tests20s, Windows/localdanalyzeNoissues, actualnativechannel1test26s, rebuiltCoreStorage8cases/channel12.7s/resource231.8s accepted. PSParserzeroerrors, lychee514OK53unique0errors,7individualnoindexwhitespace diagnostics0. Format warning in separate ignored work/isar-encryption-implementation about unresolvedflutter_lints is not a passed package check or T210sourcefailure. Originalnativeerror/unchangedprocessSID/confirmation/exactpeer-writes/no grant-session-effect and legitimatebaseline proved. This does not prove genuine pipe-peer access-denied/foreign-user/unchangedthreadtoken/fullT201/T039/Q03/001.1/CI/manual; allremainopen. No unresolved confirmed findings forT210. Exact deniedactions not retried/bypassed; no productionhooks/privileges/dependencies changes or commit/push/PR/release/merge. Goalall20/60 active.
- [x] T211 Реализовать native replay и cross-channel binding часть T201/Q03: acceptance-only transport сохраняет первый valid authenticate frame успешного production client, подставляет его на новом actual pipe с другим serverNonce; replay nativewrite завершён, server толькоhello/однаpeercheck/count1живойoriginal/noeffect. Новый authenticated channel отправляет profiles.create с sessionId другого ещё живого client; generic close/noecho, второй channel detached, receipt/profile/revision отсутствуют, original продолжаетread. Затемoriginaldetach/count0/legitimatebaseline. Exact grants отличаются; bytecopies bounded authenticate8KiB и очищаются после actualnativewrite/fixturecleanup; no logs/privateinput publication. Separate normalcompiledentry не использует controls. Strictmarker NATIVE_AUTH_REPLAY_AND_CHANNEL_BINDING_PROVED; production unchanged. T201/fullQ03/foreign-user/remote/prerequisites/corruption remainopen. Mandatoryroot/localdanalyze/nativechannel/rebuiltCore/PSParse/links/whitespace/freshreview beforeclosure.
T211 закрыт после completed independent readonly native_auth_replay_binding_review и completed final-proof supplement после terminalCoreStorage: замечаний не найдено; готов только replay/channel-binding increment. Source/docs unchanged между source review и finalproof inspection. Reviewer inspected6files/source/contracts/currentlogs/freshfixture4fc3b41b53e34aa68f6e615e50934aa3 accepted.json/all8AOTcases/newmarker/emptystderr/10normalcontrols. Current shell46710 terminalexit0: format227/0, Flutter analyzeNoissues8.0s/root237tests18s/localdanalyzeNoissues, nativechannel1test25s, rebuiltCoreStorage8cases/channel12.7s/resource219.6s accepted. PSParserzeroerrors, lychee514OK53unique0errors, six individualnoindexwhitespace diagnostics0. Firstcompileanalyzeerrors/fix retained. Accepted-frame replay against new observednonce and cross-channel live grant substitution refused with no effect, originalcaller continuesreads; captured/substitute buffers wiped, legitimatebaseline remains. No unresolved confirmed findings forT211. FullT201/Q03/foreignuser/remote/prereq/corruption/001.1/CI/manual remainopen. Exact deniedactions not retried/bypassed; no productionhooks/dependencies or commit/push/PR/release/merge. Goalall20/60 remainsactive.
- [x] T212 Реализовать T201/Q03 native server-side peer mismatch increment: production PipeWorker.verifyPeer/retained kernel identity сравнивает expected SID/path/hash с actual caller на initial/repeated handshake. Шестьcases требуют actual original IDENTITY_UNAVAILABLE, attempts1/2, successfulchecks0/1, writes0/1/no grant/no session/revisioneffect, последующий legitimate baseline. Acceptance-only ожидания используют другой valid well-known SID, иной absolute image path и hash0; ACL/privileges/productioncontrols unchanged. Это actual verifier mismatch на same-user process, не настоящий другой OSuser или remote case. Strictmarker NATIVE_PEER_SID_PATH_HASH_REFUSAL_PROVED; mandatoryroot/localdanalyze/nativechannel/rebuiltCore/PSParse/links/whitespace/freshreview доclosure. T201/fullQ03/foreign-user/remote/prereq/corruption remainopen; deniedactions не повторять/обходить.
T212 закрыт после completed fresh readonly native_server_peer_mismatch_review: замечаний не найдено; готов только server-side native SID/path/hash mismatch increment. Reviewer inspected6files/source/contracts/currentlogs/fixture4c2b2e14cbfe4742b854e53276ad959a accepted.json/all8cases/10normalcontrols/boundexe/newmarker/emptystderrs/reusefailure. Current shell16605 terminalexit0: format227/0, Flutter analyzeNoissues8.0s/root237tests20s/localdanalyzeNoissues, nativechannel1test25s, rebuiltCoreStorage8cases/channel13s/resource231.8s accepted. PSParserzeroerrors, lychee514OK53unique0errors, six individualnoindexwhitespace diagnostics0. Firstanalyzerwarning/fix preserved. Native originalerror/attempts1or2/successes0or1/writes0or1/no grantsessioneffect and legitimatebaseline verified. Same-user expectedidentitymismatch, not realforeignuser/remote/access-denied/fullT201/Q03/001.1/CI/manual; thosegates remainopen. No unresolved confirmed findings forT212; exactdeniedactions not retried/bypassed, productionACL/rights/controls unchanged; no commit/push/PR/release/merge. Goalall20/60 remainsactive.
- [x] T213 Добавить normal compiled prerequisite acceptance часть T201/Q04 в tools/test-foundation-prerequisites.ps1: rebuild pinned normal Debug bundle, проверка source hashes/testOnlyfalse, пять fresh ownedcases без runtime-testflags. MissingDLL и malformedDLL с обновлённым manifesthash→PREREQUISITE_UNAVAILABLE; format2 и exeHashmismatch→INCOMPATIBLE; exit1/empty stdout/safe exactstderr<30s, профиль толькоunchangedmarker/no namespace. Положительныйcontrol запускает normal locald и normal UI в отдельном copiedbundle/profile, удерживает оба>30s startupdeadline, закрывает только retained owned UI, требует naturalownerexit0 и workspacefiles/marker. Rawlogsignored/no upload, single-use roots/no cleanup/no ACLprivilegechanges. Metadataaccepted5cases/fullAcceptancefalse; actualmissingVC/otherplatform/foreignuser/fullQ04 remainopen. Initial bare-owner healthycontrol TIMEOUT не считатьpass: исправить harness реальным UI. PSParse/actualrebuilt5cases/specLinks/individualwhitespace/freshreview beforeclosure; productionFlutter/Dart codeunchanged.
T213 закрыт после completed fresh readonly normal_prerequisites_review: замечаний не найдено; готов только normal compiled prerequisite increment. Reviewer inspected5files/source/contracts/build/runtime/lifecycle/retainedcleanup/actuallogs/fixture6eb3c959bb41453dae4afeb1d413178d accepted5cases/fullAcceptancefalse. Current shell46700 terminalexit0: pinnednormalFlutter/AOTbuild + fournormalrefusals each0.4s exit1/emptystdout/safeerror/no namespace/preservedmarker; actualnormalUI+owner retained35s then ownUIterminated/naturalownerexit0/workspacefiles/proof37.5s. UIstderr only normalImpellerbackendnotice, no error/privateoutput repeated. First bare-owner positivecontrolTIMEOUT retained/notaccepted; fixedharnessactualUI, no productioncodechanges. PSParserzeroerrors repeatedindependently, lychee514OK53unique0errors/five individualnoindexwhitespace diagnostics0. No rootFluttertests rerun claimed; productionFlutter/Dartsource unchanged. No unresolved confirmed findings forT213. T201/fullQ04/missingVC/otherplatform/foreignuser-foreignpipe/001.1/CI/manual remainopen; exactdeniedactions not retried/bypassed, no commit/push/PR/release/merge. Goalall20/60 active.
- [x] T214 Подключить T213 normal-prerequisites как12th fixedphase к tools/test-foundation-available.ps1 после compiledsecretmarkers и передbootstrapownerloss; сохранить serial execution, rebuild/proofguards/firstfailurestop/rawlogsignored/fullAcceptancefalse/no argumentoverrides. Актуализировать текущие инструкции12phase, сохранив историческиеT193/T198 eleven-phase records. Выполнить actualcurrent aggregate12phase, проверитьresult exactordered12completed/fullfalse; PSParser/ListOnly12/links/individualwhitespace/freshreview доclosure. Это регрессия доступногоautomaticcoverage, не fullAll/T201/CI/manual/001.1. Rootproductioncode unchanged, exactdeniedactions не добавлять/повторять/переносить.
T214 закрыт после completed fresh readonly available_twelve_phase_review: замечаний не найдено; готов scoped12phaseaggregate. SAME shell12474 observed live across continuation then terminalexit0 T214_ACTUAL_TWELVE_PHASE_SUITE_PASSED. Currentroot5e98557d968844e9a904854731acb84c result.json statuspassed/required12/completed12/exactorderedListOnly/allcompletedtrue/failedPhasenull/fullAcceptancefalse; master12PASS, childsuccessmarkers and prerequisites5cases checked independently. Actualdurations seconds: Core344.7(resource202.5/channel12.8), Commit44.5, Init45.8, Markers44.4, Prereq67.2, bootstrap154.3, UI2 65, UI3 71.1, crash78.2, loss75.8, credentials135.4, inflight57.3. Reviewer inspected6files/contracts/driver/wrappers/CI and independentlyrepeatedPSParser0errors/ListOnly12; links514OK53unique0errors, sixindividualnoindexwhitespace diagnostics0. No artificialfailureinjection: propagation assessed fromsource. Earlier11phaseT193 evidence retained ashistory, notsubstituted. No productionFlutter/Dartchange/newrootchecksclaimed; actualfreshall12 wrappers rebuild/validateownproofs. No unresolved confirmed findings forT214. FullAll/T201/Q01–Q12/hostedCI/manual/001.1 remainopen; exactdeniedactions not added/retried/bypassed/transfered, no commit/push/PR/release/merge. Goalall20/60 active.
- [x] T215 Добавить T201/Q06 native workspace identity/corruption cases в workspace_child.dart: genuine valid CurrentUserDPAPI receipt key с чужимиworkspace/key IDs (proof собственногоunprotect), manifestworkspaceId mismatch, manifestreceiptKeyId mismatch, damagednativeDB послеlegitimatecreation/close. ВсеcaseOpen→STORAGE_BLOCKED; exactinventory/filebytes сохраняются послеотказа, no staging/reset/replacementkey, existinghealthycreation/reopen preserved. StrictcompiledWorkspaceLifecycle/CoreStorage требует4case markers ровноonce послеassertions. Acceptance-onlysyntheticmutations черезexistingprotectedreplace, productionunchanged. Rootformat/analyze/test/localdanalyze/actualrebuiltWorkspaceLifecycle/PSParse/links/individualwhitespace/freshreview доclosure. FullT201/Q06/credentialcorruption/DPAPIavailability/foreignuser/unsafeACL remainopen; exactdeniedactions не повторять/обходить.

T215 закрыт после completed fresh readonly workspace_identity_corruption_review: замечаний не найдено; готов только ограниченный workspace identity/corruption increment. Actual shell23140 terminal exit0: format227/0, Flutter analyze No issues7.4s, root237tests16s, locald analyze No issues, rebuilt WorkspaceLifecycle1.2s accepted; PSParser0errors, lychee514OK53unique0errors, six individual no-index whitespace diagnostics0. Reviewer непосредственно проверил журналы и fresh fixture d55df9beccdd4499b448c94d04f9013f: accepted WorkspaceLifecycle, четыре markers ровноonce, пустой case stderr и TEST_FIXTURE_USED при повторе. Каждый отказ STORAGE_BLOCKED сохраняет inventory и все байты, staging отсутствует; healthy cases сохранены. Reviewer source/evidence only, tests/builds не повторял. Current CoreStorage и aggregate12 не перезапускались; priorT214 evidence отдельно. FullT201/Q06/normalUI/credentialcorruption/DPAPIavailability/foreignuser/unsafeACL/001.1 remainopen. Только конкретные системно отклонённые операции и проверки отложены и открыты; остальные работы продолжаются. Нет unresolved confirmed findings дляT215; exactdeniedactions не повторялись/не обходились. Goalall20/60 active; no commit/push/PR/release/merge.

- [x] T216 Закрыть T201/Q06 wrapper metadata negatives: real CurrentUser DPAPI wrapper с format2, чужим product, чужим ownerSid и manifest ownerSid mismatch. Перед отказом подтвердить реальный protect/unprotect roundtrip изменённого wrapper; format2→INCOMPATIBLE, остальные→STORAGE_BLOCKED. Exact file inventory/bytes unchanged, no staging/reset/key replacement; cleartext buffers wiped, private inputs не логировать. Четыре markers после assertions обязательны в compiled WorkspaceLifecycle/CoreStorage. Production unchanged; rootformat/analyze/test/localdanalyze/rebuiltWorkspaceLifecycle/PSParser/links/whitespace/fresh readonly review до closure. FullT201/Q06/credential corruption/foreign-user/DPAPI availability/unsafeACL остаются открытыми, exactdeniedactions не повторять/обходить.

T216 закрыт после completed fresh readonly workspace_wrapper_metadata_review: замечаний не найдено; готов только wrapper metadata increment. Actual shell88018 terminalexit0: rootformat227/0, Flutter analyzeNoissues7.4s, root237tests17s, localdanalyzeNoissues, rebuiltWorkspaceLifecycle1.5s accepted; PSParser0errors, lychee514OK53unique0errors, threeindividualnoindexwhitespace diagnostics0. Reviewer inspected source/contracts/logs/freshfixture c2a742ad59554f3193a4fe4351760ab3 accepted.json, четыреnewmarkers ровноonce, пустойstderr, TEST_FIXTURE_USED/emptystdout приrepeat. RealDPAPI roundtrip/bytebufferwipe, expectedINCOMPATIBLE versusSTORAGE_BLOCKED, exactinventory/filebytes/no staging confirmed; no unresolvedconfirmedfindings. Reviewer tests/builds не повторял. CoreStorage/aggregate12 не перезапускались. FullT201/Q06/credential corruption/DPAPIavailability/foreign-user/unsafeACL/001.1 remainopen; exact system-denied operations/checks deferredopen безretry/bypass. Goalall20/60 active; no commit/push/PR/release/merge.

- [x] T217 Расширить existing repository startupDamage для T201/Q06: tampered actual DPAPI credential, чужие workspaceId/credentialId entropy, valid protected credential version2, StoredWorkspace schemaVersion2/workspaceId/receiptKeyId mismatch. Версии→INCOMPATIBLE, остальные→STORAGE_BLOCKED≤30s; после каждого отказа все прикладные rows/id/payload неизменны, restored original snapshot снова открывается revision2. Native writable open/close может менять MDBX meta pages: этот scoped proof доказывает сохранение rows, не exact DB bytes. Настоящий DPAPI roundtrip version2, owned cleartext buffers wipe; no private logging. Strict compiled repository/CoreStorage требует CREDENTIAL_AND_WORKSPACE_STARTUP_MATRIX_PROVED. Rootformat/analyze/test/localdanalyze/rebuiltCoreStorage/PSParser/links/whitespace/freshreadonlyreview до closure. Production unchanged; fullT201/Q06/foreign-user/unsafeACL/DPAPIavailability остаются open; exactdeniedoperations не повторять/обходить.

T217 закрыт после completed fresh readonly credential_workspace_startup_matrix_review: замечаний не найдено; готов только startup row/credential matrix increment. Actual shell82366 terminalexit0 T217_CHECKS_AND_COMPILED_CORE_PASSED: rootformat227/0, FlutteranalyzeNoissues9.6s, root237tests18s, localdanalyzeNoissues, rebuiltCoreStorage8cases allpass (Workspace1.8s/repository84.5s/credential0.6/mutations1.2/API0.3/channel12.9/service0.3/resource223.4); PSParser0errors, lychee514OK53unique0errors,3individualnoindexwhitespace diagnostics0. Reviewer inspected source/contracts/logs/currentfixture6c81b2909f3744a19497f77d3fabe648 accepted8cases/newmarkeronce/emptystderr/TEST_FIXTURE_USED withemptystdout, independently repeatedPSParser0errors. Foreignwrappers valid underownIDs; version2realDPAPI roundtrip/bufferwipe; refusal<30s; allfivecollectionIDs/payloads unchanged; restoredbaseline exactrows/productionreopen revision2 confirmed. No unresolved confirmed findings forT217. Preservation scope rows, notexactDBbytes afterwritable nativeopen. Reviewer builds/tests notrerun. Aggregate12/fullT201/Q06/normalUI/foreign-user/DPAPIavailability/unsafeACL/001.1 remainopen. Exactsystemdeniedactions deferredopen withoutretry/bypass; goalall20/60 active; no commit/push/PR/release/merge.

- [x] T218 Проверить T201/Q06 actual Workspace.open при real directory junction вместо product/active/staging. Junction и marker target только внутри fresh verified fixture, helper setup fixed PowerShell/env inputs; не удалять fixture/junction и не менять privileges. Требовать actual link identity, STORAGE_BLOCKED<30s, неизменныеtarget markerbytes/onlyfile/inventory, отсутствие дополнительныхentries черезreparse, same junction target. После3отказов normalWorkspacecreate/reopen даёттотжеidentity/initialempty. StrictcompiledWorkspaceLifecycle/CoreStorage требует3casemarkers+healthycontrolmarker. Productionunchanged; mandatoryrootchecks/localdanalyze/rebuiltWorkspaceLifecycle/PSParser/links/whitespace/freshreview доclosure. Это creation-path reparse scope, не foreign-user/unsafeACL/fullQ06; exactdeniedactions не повторять/обходить.

T218 закрыт после completed fresh readonly workspace_reparse_paths_review: замечаний не найдено; готов только creation-path reparse increment. Actual shell10628 terminalexit0 T218_CHECKS_AND_COMPILED_WORKSPACE_PASSED: format227/0, FlutteranalyzeNoissues8.6s/root237tests19s/localdanalyzeNoissues/rebuiltWorkspaceLifecycle2.4s accepted; PSParser0errors, lychee514OK53unique0errors,3individualnoindexwhitespace diagnostics0. Reviewer checkedsource/contracts/logs/freshfixturec8017e390b5a4414b7ac33992753776f acceptedproof/3retainedjunctions/exacttargets/onlyunchangedmarkers/4strictmarkersonce/emptystderr/TEST_FIXTURE_USED emptystdout, independently repeatedPSParser0errors. Production Workspace refuses3reparsepaths<30s withoutaddingtargetfiles; laterhealthycreate/reopen sameID/initialempty. No unresolvedconfirmedfindings. Reviewer builds/tests notrerun. CurrentCoreStorage/aggregate12 notrerun; priorT217Core precedesT218. Persisted-file reparse/foreign-user/unsafeACL/DPAPIavailability/fullT201/Q06/001.1 remainopen. No recursivejunctioncleanup/privilegechanges/exactdeniedactions retries or bypass. Goalall20/60 active; no commit/push/PR/release/merge.

- [x] T219 Проверить T201/Q04 actual occupied endpoint/pool rollback: independently retained native server occupies slot0/3/7 freshnamespace; NativePipe duplicate→UNSAFE_ENDPOINT, production PipeServerPool worker startup→genericSERVICE_UNAVAILABLE<30s. Original endpoint remainsusable with verifiedkernelpeer/bidirectionalI/O; after onlyownedhandlesclose allsame8names re-created, proving partialpoolcleanup. Store snapshot unchanged; subsequent existing authenticated productionchannel baseline works. Strictcompiledchannel/CoreStorage marker NATIVE_OCCUPIED_POOL_REFUSAL_AND_RECOVERY_PROVED. SameSID/testprocess retainedendpoint, не actualforeign-user process/normalowner/fullQ04. Mandatoryrootchecks/localdanalyze/targetnativechannel/rebuiltCoreStorage/PSParser/links/whitespace/freshreview доclosure; productionunchanged, exactdeniedoperations notretried/bypassed.

T219 закрыт после completed fresh readonly occupied_pipe_pool_review: замечаний не найдено; готов только occupiedendpoint/poolrollback increment. SAME shell7853 terminalexit0 T219_CHECKS_AND_COMPILED_CORE_PASSED: format227/0, FlutteranalyzeNoissues8.2s/root237tests19s/localdanalyzeNoissues; targetednativechannel1test26s; rebuiltCoreStorage8cases (Workspace2.5/repository87.1/credential0.4/mutations0.9/API0.2/channel12.9/service0.2/resource231s) accepted. PSParser0errors/lychee514OK53unique0errors/3individualnoindexwhitespace diagnostics0. Reviewer inspectedsource/contracts/logs/currentfixturee037cd2271a64f05b56c3585dbf50aab accepted8cases/allmarkers/emptystderrs/reuserefusals; independently repeatedPSParser0errors. Slots0/3/7 nativeUNSAFE_ENDPOINT versusgenericworkerSERVICE_UNAVAILABLE<30s, retainedendpointverifiedbidirI/O, same8firstinstancenames recovered/unchangedstate/authenticatedbaseline confirmed. No unresolvedconfirmedfindings; reviewer builds/tests notrerun. Formatter warning ignoredwork/isar-encryption-implementation is notpassedseparatepackageevidence. SameSID/testprocess scope, notphysicalforeign-user/normalowner/fullT201/Q04/remote/aggregate12/CI/manual/001.1. Exactdeniedactions remainopen withoutretry/bypass; goalall20/60 active; no commit/push/PR/release/merge.

- [x] T220 Добавить T203/Q08 compiled ApiCommitRecovery: actualproductionLocalApiClient/nativepipe/ServerChannel/ApiServer/MutationCoordinator. Separatetesttarget задерживает actualcredentialprotection доcommit (state0) или actualServerChannelwrite послеdurablecommit доreply (state1); authenticgrant/writes2/pendingcaller/receiptid asserts precede flushedboundary. Parent kills onlyretainedverifiedtestchild, freshverifierstate+profile+credential+receipt0/1 andCurrentUserDPAPIsecretafter; before/afterphases singleuse, normalentrycontrolsrejected. Fixedwriterproofmarkers+safeCRASHBOUNDARY, no private logging. Explicitowned testprocess controlledready/selfimage, не normalUI/reboot/fullQ08. Mandatoryrootchecks/localdanalyze/compiledApiCommitRecovery/PSParser/links/whitespace/freshreviewдоclosure. KeepexistingStateStoreCommitRecoveryunchanged; productionhooksnotadded; exactdeniedactions notretried/bypassed.

T220 закрыт после completed fresh readonly api_commit_boundary_review: замечаний не найдено; готов onlyApiCommitRecovery. Initialunusedimportwarning fixed beforeexecution; firsttwo-casepass4b799e6df18a483ab61e3a107506ac89 precedesfinalpendingfuture/RPCdeadlineassertions. SAME finalshell56148 terminalexit0 T220_FINAL_CHECKS_AND_API_COMMIT_RECOVERY_PASSED: rootformat228/0, FlutteranalyzeNoissues8.8s/root237tests16s/localdanalyzeNoissues; currentrebuiltApiCommitRecovery2hardcrash+freshverifycasesaccepted; PSParser0errors/lychee514OK53unique0errors/6individualnoindexwhitespace diagnostics0. Reviewer inspectedsixfiles/productionchain/contracts/logs/currentfixture1efba056d20b4307bf9db70248c39a91 strictmarkers/acceptedproofs/reuserefusals; no tests/buildsrerun. OldCommitRecovery4cases actuallypassed shell4147 fixture1b4af9bcf4f940d087a04c2db8ea2f5b aftersharedhelper/verifierchange beforelastnewApi-onlyguard; oldexecutedpathsunchangedsincethatrun. Boundaryasserts authenticgrant/writes2/unfinishedRPC<deadline/state0or1/fixedrequestid beforeflushedmarker; parentretainedownedchildkill/freshstate+receipt+credential0or1/CurrentUsersecret after verified. Livenessproved atpublishedboundary, notseparateobservedexit-beforeRPCdeadlineproof. No unresolvedconfirmedfindings. Productionunchanged/testcontrolsisolated; fullT203/Q08/normalownerUI/reboot/otheruser/CoreStorage/aggregate12/full001.1 remainunprovedbyT220. Exactdeniedoperations/checks deferredopen withoutretry/bypass; goalall20/60 active; no commit/push/PR/release/merge.

- [x] T221 Включить accepted T220 ApiCommitRecovery послеCommitRecovery в fixed available dispatcher, current13phases computedfromarray. Actualfresh13phaseaggregate regressescurrentT215–T220 withnative/bootstrap/prerequisite/UIhelpers; eachwrapper rebuilds/strictproof, no overrides/SkipBuild, firstfailurestops, fullAcceptance=false. Updatecurrentinstructions whilepreservinghistorical11/12evidence. PSParser/ListOnly13/spec links/6individualwhitespace + actualterminal13phasepass/resultinspection/freshreadonlyreview beforeclosure. No productionFlutter/Dartchange, no rootchecksrerunclaim. FullAll/T201/T203/Q/CI/manual/001.1 stayopen; exactdeniedactions excluded/notretried/bypassed/transferred.

T221 закрыт после completed fresh readonly available_thirteen_phase_review: замечаний не найдено; готов scoped13phaseaggregate. SAME shell65175 observedlive acrosscontinuation then terminalexit0 T221_ACTUAL_THIRTEEN_PHASE_SUITE_PASSED; no restart. Currentroot90c57f0b519043bb8668fa5b984c85c3 result.json directlyverified statuspassed/required13/completed13/exactListOnlyorder/allcompletedtrue/failedPhasenull/fullAcceptancefalse; master13PASS. Actualdurationsseconds Core411.4(resource242.8/channel13/Workspace3.6), Commit57.8, API59.8, Init55.5, Markers60.6, Prereq76.7, bootstrap154.8, UI2 68.7, UI3 78.7, crash82.3, loss77.9, credentials145.9, inflight62.8. Reviewer inspected6files/contracts/SDK/CIinvoker/drivers/helpers/currentresult+childproofs: Core8, Commit4, API2hardcrash/reopen, Init9+inventorynegative, markers/prereq5/bootstrap andUIproofs includingcredential8steps. StaticchecksactualPSParser0/ListOnly13/lychee514OK53unique0errors/sixindividualnoindexwhitespace diagnostics0; reviewer tests/buildsnotrerun/filesnotmodified. No productionFlutter/Dartchange/newrootcheckclaim inT221. Historical11/12phaseevidence retained, current13regressesT215–T220 plusexistingnative/UIhelpers. No unresolvedconfirmedfindings forT221. FullAll/T201/T203/Q01–Q12/hostedCI/manual/reboot/otheruser/physicaloffline/full001.1 remainopen; exactdeniedactions notadded/retried/bypassed/transferred. Goalall20/60 active; no commit/push/PR/release/merge.

T047 currentcommandgate evidence recorded in docs/development/foundation-verification.md after same shell40508 terminalexit0: root237/protocol36/Windows31/locald85, bothnormalbuilds/hashverification, currentT221sixUIproofs reusedwithoutsourcechange. T047 staysunchecked until completed independentreview verifies commandcoverage; notfullAll/CI/manual/stagereadiness.

T047 закрыт после completed fresh readonly current_command_gate_review: замечаний не найдено; готов только исходный commandgate. Reviewer inspectedAGENTS/task/spec/plan/quickstart/developercommands/scripts/actuallogs/T221sixUIproofs and independentlyrecomputed all3SHA256 ineachnormalDebug/Releasebundle; manifests format1/config/testOnlyfalse verified. Same shell40508 terminalexit0 actualrootformat228/0/analyzeNoissues/root237, fullprotocol36/Windows31/locald85 serialpackagechecks/enforcedlocks/bothnormalbuilds/lychee514OK53unique0errors. Immediatelypreceding unchanged-sourceT221UIintegration evidence reusedexplicitly, notrerun here; no separateT221source-digest snapshot claimed, frozen-source scope provided. Doctor reportedoneproblemcategory: diagnosticexit0 notallplatformhealth; formatterignoredwork warning notpassedseparatepackage. Reviewer builds/testsnotrerun, source/docfilesnotmodified; no unresolvedconfirmedfindings forT047. Dirtyworktree reported, no commit/push/PR/release/merge. T044/T048/T049/T050/fullAll/CI/manual/reboot/otheruser/physicaloffline/notices/full001.1 remainopen. Exactsystemdeniedactions/checks not retried/bypassed; goalall20/60 active.

- [x] T222 Закрыть T201 actualthreadidentity observation gap: synchronous test-only guard reads physicalthreadID/processSID andOpenThreadToken before/after productionnativepeerquery/verify andinvalidprocess/tokenqueries. ERROR_NO_TOKEN isexplicitabsence, otherqueryerrors/closeerrors failprobe; presenttoken comparesTokenId/AuthenticationId/TokenType/validimpersonationlevel/ModifiedId withoutlogging. No await/impersonation/token mutation/privilegechanges. Successfulnativepeer2checks andoriginalimage-hashrefusal verifiedin auth_native_test; negativecallbackmustconfirmoriginalIDENTITY_UNAVAILABLE so handshakeUNAUTHORIZED cannotmaskprobefailure. Existing4initial/repeatedqueryfailure channelcases propagateoriginalnativeerror onlyafteridentityguard; strictCoreStorage marker NATIVE_THREAD_TOKEN_QUERY_FAILURE_STABILITY_PROVED. Rootchecks/Windows+localdanalyze/targetauth+channel/rebuiltCoreStorage/PSParser/links/whitespace/freshreviewbeforeclosure. Controlledcurrentthread/nativequeries, notworker-internalinstrumentation orforcedexistingimpersonation/foreign-user/fullT201/Q03. Exactdeniedoperations not retried/bypassed.

- [x] T223 Исправить confirmedP2 native_thread_identity_review: guard-ownedcurrentUserSid failure currentlycollideswithoperationIDENTITY_UNAVAILABLE andcanfalse-confirmnativefailures. MapallguardSIDobservationerrors todedicatedTHREAD_PROCESS_SID_QUERY_UNAVAILABLE; test-onlyreader seam injectsbefore/afterfaultswithoutOSprivilege/tokenchanges. Regressiontests requirebeforefaultnooperation/afterfaultoverridesintendednativeerror/healthyrealobservations preserveoriginalerrorobject. Also wrapfirstserver.peerIdentity acquisition soauthpositivecoversinitialquerypluscachedrevalidation. T222 staysopenuntilfixedchecks+freshnone review clean. Rootmandatorychecks/Windows+localdanalyze/3regression+auth/channeltests/currentcompiledCoreStorage/PSParser/links/7filewhitespace/freshreadonlyreview; preserveearlierfailedreview/run evidence. No productionhooks/privilegechanges/exactdeniedretry.

T222/T223 закрыты после completed fresh readonly native_thread_identity_fixed_review: замечаний не найдено; готов только scopedthreadidentity increment. Initial completednative_thread_identity_review found1P2: guardSIDobservationIDENTITY_UNAVAILABLE couldfalseconfirmoperationfailure; originalpassingCore9bc7ebefb7e842979ee9e9c198769acb notclosureproof. T223 dedicatedTHREAD_PROCESS_SID_QUERY_UNAVAILABLE mapsallguardSIDreadfailures;3regressions before/after/healthyoriginalobject pass. Initialnativepeeracquisitionplus2cachedrevalidations nowguarded; negativecallbackchecksoriginalerrorbeforeUNAUTHORIZEDmask. SAME fixedshell15025 terminalexit0 T223_FIXED_CHECKS_AND_THREAD_IDENTITY_NATIVE_PROOFS_PASSED: rootformat230/0, FlutteranalyzeNoissues7.1s/root237tests17s, Windows/localdanalyzeNoissues, regression3+targetauth/channel2tests24spassed, rebuiltCoreStorage8cases/resource201.4s accepted. PSParser0errors/lychee514OK53unique0errors/7individualnoindexwhitespace diagnostics0. Reviewer inspected7files/contracts/currentlogs/freshfixture6c8ac3eed12641f593ba4e6b569a9b84 accepted8cases/newmarkeronce/allpositivestderrsempty/reuserefusal; no tests/buildsrerun/filesmodified. No unresolvedconfirmedfindings. Guardquery-only/synchronous, noimpersonation/token/privilegechanges; presenttokenbranchnotforced, workerinternal/foreignuser/accessdenied/fullT201/Q03/aggregate13/full001.1 unproved. Formatter ignoredwork/flutter_lints warning isnotseparatepackagecheckpass. ExistingT047/T221 remainhistoricalpreT222source evidence. Exactsystemdeniedoperations notretried/bypassed; goalall20/60 active; no commit/push/PR/release/merge.

- [x] T224 Покрыть T205/local-api transport bound: authenticated actual native pipe получает 17 valid read frames напрямую, минуя LocalApiClient pending limit. Test-only scheduling gate удерживает первый ordinary reply; actual production ServerChannel должен прочитать ровно16 frames и не читать17-й, включая replies waiting for single writer. Survivor read остаётся доступен, revision unchanged; release gate обрабатывает17-й и subsequent production client read, cleanup leaves survivor only. Strict compiled CoreStorage/channel marker NATIVE_SIXTEEN_PENDING_BACKPRESSURE_AND_RECOVERY_PROVED. Root format/analyze/test, locald analyze/native channel test, rebuilt CoreStorage, PSParser/links/individual whitespace, fresh readonly review до closure. Это controlled writer scheduling/real native transport, не normal owner/kernel saturated outbound buffer/fullQ10; no limits/deadline relaxation, production unchanged, exact denied operations не повторять/обходить.

T224 закрыт после completed fresh readonly native_pending_backpressure_review: замечаний не найдено, готов только T224 transport backpressure increment; fullT205/T041/Q10/001.1 остаютсяopen. Actual current rootformat230files/0changes, FlutteranalyzeNoissues9.4s/root237tests16s, localdanalyzeNoissues, channel_native_test1passed25s; rebuiltCoreStorage8cases allpass (Workspace2s/repository71.8/credential0.4/mutations0.8/API0.2/channel12.8/service0.2/resource209). Fixture .local/native-acceptance-c36e0cc290e345cb99905787b0539498 accepted8cases/newmarkeronce/all8positivecase stderr empty. Logs .local/audits/t224-{format,analyze,root,locald-analyze,channel-final,core,links}.txt. Combined shell74792 completed tests/links thenexit1 because git LF-to-CRLF warning was treated as whitespace output; follow-up git core.safecrlf=false individual noindex checks had no diagnostics/content-only exits0/1, PSParser0errors, terminalexit0 T224_CHECKS_AND_COMPILED_CORE_PASSED. lychee514OK/53unique/0errors. Reviewer inspected actualsource/contracts/proofs/logs, independentlyPSParser0/newmarkeronce; no builds/tests rerun and no source changes. Controlled scheduling holds first native-write callback, exact16 frames consumed with17th waiting, survivorread unchangedrevision, release then17successfulunique replies/subsequentproductionclientread/sessioncleanup. No normalowner/kerneloutbound saturation/fullresource/001.1 claim. Exactdeniedoperations not retried/bypassed; no commit/push/PR/release/merge; all20packages/60stages goalactive.

- [x] T225 Расширить существующую actual UI credential journey до10 sequential freshprocess steps для T202/Q09: после empty reopen заполнить249profiles через production authenticated LocalApiClient/normal locald, UI сохраняет250-й; invalid address/port/user не сохраняются, исправленная валидная251-я форма получаетRESOURCE_LIMIT/no optimistic success/retaineddraft. Model/revision/profile-result snapshot неизменны послеотказов, reads работают. Новый UI/owner generation открывает250profiles с exact result digest/revision257/nullselection; existing8steps остаютсяобязательными. No mock/directDB/testlocald, ownedsyntheticfixtureonly. Mandatoryrootformat/analyze/test, tenstep actualUIrebuild/drive, PSParser/links/individualwhitespace, freshreadonlyreviewдоclosure. Networkblocked/physicalkeyboard/normalproductionentrywithoutintegrationtarget/fullT202/Q09 не объявлятьпройденными; exactdeniedactionsнеповторять/обходить.

T225 закрыт после completed fresh readonly ui_profile_quota_reopen_review: замечаний не найдено, готов только T225; fullT202/Q09/001.1 remainopen. Actual shell66617 terminalexit0 T225_CHECKS_AND_TEN_STEP_UI_PASSED: rootformat230files/0changes, FlutteranalyzeNoissues7.8s/root237tests15s; rebuiltFlutterintegrationtarget+normalAOTlocald, all10mandatoryfreshprocessUIsteps green. Fixture .local/foundation-ui-d413f5d9dcf646629395af954310f11e/profile/ui-credentials/step-{0..9}.json:10proofs/10distinctowner generations/no failureproofs, step8/9 count250/revision257/nullselection/samedigest. Seed249actualproductionAPI, UI250save, invalid3fields/noeffect, valid251RESOURCE_LIMIT/nosuccess/retaineddraftname; exactprofile-result beforeafter refusal, reads work; reopened complete resultdigest unchanged. Existing8credential/cancel/delete/selection/reopensteps retained. Logs .local/audits/t225-{format,analyze,root,ui,links,pre-review-links}.txt. Strongerdriver count/digest/finalpairguards appended afterUIrun with noDartchange, executed againsteveryactualproof terminalexit0 T225_STRONGER_CURRENT_PROOF_GUARDS_PASSED; PSParser0/lychee514OK53unique0errors/4individualnoindexwhitespacediagnostics0. Reviewer independentlyreadsource/contracts/logs/10proofs, ranparser/currentguards, verified10distinctgenerations/UIPIDs/oneeachstagemarker/finaldigest; no builds/tests or edits. Recent asserts100lastunique receipts, notall257; noeffectsupportedby unchanged revision/result/startupinvariants. Controlledintegrationtarget usesproductionapp.main+normal locald/storage; notuninstrumentednormalFlutterentry/networkblocked/physicalkeyboard/picker/fullQ09/001.1. Exactdeniedoperations deferredopen/notretried/bypassed; no commit/push/PR/release/merge, overallgoalactive.

T046 закрыт после completed fresh readonly current_foundation_instructions_review: замечаний не найдено, ready scoped runnable instructions; wholeT208/Q01–Q12/001.1 не закрываются. README уточняет001.1local/001.2SSH/001.3jobs и partial13phase command. Developer foundation/quickstart отражают10credentialdrives, unknowninflight flags/command, ApiCommitRecovery, 13phase dispatcher/normalprerequisites; stale отсутствия APIcrash/unknowninflight убраны. DisposableWin11/twoSID/offline/reboot/interactive prerequisites, safeerrors/recovery/futureunavailable/native noticesdistributionReadyfalse и exactdeniedoperations остаютсячестными. Historical T198eleven/T214twelve/T221thirteen retained; T221 предшествует T222–T225, currentCore/10UI отдельные и не новыйaggregate. Actual docs-only checks: prerequisiteJson valid, ListOnly13 .local/audits/t046-current-list.txt; lychee514OK53unique0errors .local/audits/t046-current-links.txt; editeddocslinks20OK14unique0errors .local/audits/t046-doc-links.txt;3individualnoindexwhitespacediagnostics0; terminalexit0 T046_CURRENT_DOC_CHECKS_PASSED/T046_ALL_EDITED_DOC_LINKS_PASSED. Initialwrapper falsefailed on staleLASTEXITCODE aftersuccessfulPowerShellListOnly; correctedstatusguard succeeded, no acceptance failure hidden. Reviewer read scripts/contracts/source/evidence/current8caseproof/final250profileproof; no builds/tests/native/manual/CI rerun or edits. NoFlutter/Dartcodechanged, no unperformedtestpassclaimed. T047historicalcommandgate remains historical. Exactdeniedoperations not retried/bypassed; no commit/push/PR/release/merge; goalall20packages/60stagesactive.

- [x] T226 Дополнить T204/Q05/Q08 API crash coverage: ApiCommitRecovery обязательные4cases password/privateKey+passphrase × beforecommit/aftercommitbeforereply, existingproductionclient/pipe/router/coordinator/StateStore/DPAPI route. Acceptance-only observer capturesactualgenerated receipt key beforeprotect/onunprotect, registersraw/UTF8/UTF16/base64 accesssecretpatterns, wipesownedtechnicalkeycopies. BeforeflushedCRASH_BOUNDARY иfreshverifier scans everyownedcasefile включая DB/index/lock/wrapper/manifest/temp withoutfollowingreparse/ACLchanges, requires4+files/receiptkeyobserved, newstrictmarker. Existingexactstdout/stderrallowlists forbid unexpecteddiagnostics, rawtestsource/binariesandforeignTemp excluded. Verifierrequireszeroeffects before oroneoriginalafter plususablekind-specificcredential. OriginalCommitRecovery4cases regression aftersharedhelperchange; currentrootformat/analyze/test/localdanalyze/rebuiltAPI4cases/PSParser/links/whitespace/freshreadonlyreviewдоclosure. No normalUI/initialization/allruntime diagnostic/fullT204/fullQ claim, no productionhooks/limitrelaxation; exactdeniedactionsнеповторять/обходить.

T226 закрыт после completed fresh readonly api_crash_secret_markers_review: замечаний не найдено, ready scoped T226 only; fullT204/Q05/Q08/001.1 remainopen. Actual shell41367 terminalexit0 T226_CHECKS_API_MARKERS_AND_COMMIT_REGRESSION_PASSED: rootformat231/0, FlutteranalyzeNoissues7.7s/root237tests15s, localdanalyzeNoissues; rebuiltApiCommitRecovery4cases allpass fixture4326cf68219c4756822e41a1b8e0496a, rebuiltOriginalCommitRecovery4cases allpass fixture2d19cd7d71074b85bf9ac99fcff59fab. APIwriter/verifier8phases eachnewmarkerexactonce/emptystderr,8reusesTEST_FIXTURE_USED/emptystdout; productionclient/nativepipe/router/coordinator/storage/CurrentUserDPAPI route, password/privateKey+passphrase before/aftercommit;zero/oneeffects+originalreceipt/profile+usablekind-specificsecrets. Actualgeneratedtechnicalkeyobserver beforeprotect/onunprotect, owneddecodedcopieswiped, allownedcasefiles scannedraw/UTF8/UTF16/base64 beforereadyCRASH_BOUNDARY andafterfreshreopen; deadlineunchanged/rechecked, strictchilddiagnosticallowlists retained. Logs .local/audits/t226-{format,analyze,root,locald-analyze,api,commit,links,pre-review-links}.txt; PSParser0/lychee514OK53unique0errors/7individualwhitespacediagnostics0, terminalexit0 T226_PRE_REVIEW_CHECKS_PASSED. Initialanalyze invalidDartpatternsyntax failed beforetests, fixed; first-locald-analyze logpreserved. Reviewerreadsource/contracts/actual8phaseproofs/reusestats/regression/logs; no builds/tests repeated or edits. No normalUI/initialization/reboot/foreignuser/fullmatrix oractualchildexitbeforeRPCdeadline claim. Source/binaries/parentlogs/foreignTemp excludedfromcasefile scan; childstdout/stderr constrained separately byfixedallowlists. Exactdeniedoperations deferredopen/notretried/bypassed; no commit/push/PR/release/merge, globalgoalactive.

- [ ] T227 Дополнить T204/Q08 initialization scans по всем9failpoints иexistinginventorynegative. Test-only realDPAPI observer capturesactualreceiptkeyraw/base64/UTF16 patterns/wipesdecodedcopies. Writer сканируетвсеownedcasefiles послеboundaryrecord доflushedCRASH_BOUNDARY; freshverifierbindsoriginalprotectedwrapper черезread-onlyDPAPIoracle дажеpartialstage (неменяетего), сканируетдоWorkspace.open ипослеblocked/ready, требует unchangedwrapper/manifestidentities/preservedpartial. Stagecreatedbeforekey: отдельноеproofno-secret-created, !observed/zero stagingfiles/onlyboundaryJSON; невыдаватьunboundscanner заsecretclean. StrictInitdriverтребуетcorrespondingmarkerwriter/verifierодинраз; inventorynegative writer also scanned, verifier muststillrejectunexpectedinventorybeforeunwrap. Currentrootformat/analyze/test/localdanalyze/rebuiltInitializationRecovery9pairs+negative/PSParser/links/whitespace/freshreadonlyreviewдоclosure. No accesscredentialscreatedduringinit; no normalUI/fulldiagnostic/foreignTemp/reboot/fullT204/Q08 claim, productionunchanged/noACLchanges; exactdeniedactionsнеповторять/обходить.

T227 partial execution uncovered actual Windows LOCK_VIOLATION33 during recursive live-file scan at uncommittedInitialRows. Firstfixture6300c7081c9b4ec8abf64fcdd04cf9f5 passed first4pairs then failed; secondffea8fbcbd934d6d9630f2e95932313a repeatedgenericfailurebeforeoriginaldiagnosticwasknown; thirddiagnosticbuildfailednullableStringcompile254 thenfixed; fourthb927bcac35d44f6c8d42827b6ad8d721 preserved INIT_SCAN_READ_IO_33. Logs t227-init/second-init/third-init/fourth-init retained. Exact failed file path was lost by original generic wrapper; cannot attribute which native file. Do not repeat or bypass the live native transaction range-read check. Current partial writer still scans originalwrapper/manifest/boundaryJSON but excludes bothnativefiles workspace.isar/workspace.isar-lck at onlythisliveboundary; deferredmarker notcleanmarker. Freshverifier performs complete scan afterconfirmedownedchildtermination, withoutclaiminglivecoverage. Initialization accepted.json must carry fileSecretScanComplete=false/deferredexactphase; T227 remainsOPEN untilmissinglivecriterioncanbeactuallyestablished. Other8boundaries/9freshverifiers/inventorynegative continue. Safe fixedtestdiagnosticcode and boundedmissing-boundarylogcapture added; no rawexception/path/secret echo. This is partialcoverage, notclosureoforiginalallfilescriterion, fullT204/Q08/001.1 orblockedoverallgoal. Exactdeniedoperations are not retried/bypassed.

T227 current partial implementation reviewed by completed fresh readonly initialization_marker_partial_review: no findings, ready ONLYpartialincrement; originalT227 remainsOPEN because originalall-live-native-files criterion unproved afterWindowsLOCK_VIOLATION33. Current SAMEshell78704 terminalexit0 T227_CORRECTED_PARTIAL_CHECKS_AND_API_REGRESSION_PASSED: rootformat231/0, FlutteranalyzeNoissues7.3s/root237tests14s, localdanalyzeNoissues, rebuiltInit9pairs+inventorynegative fixturedaef65a43d374540a64f71e152bb5e1f passedpartialcontract, rebuiltAPI4casesregression fixturee9364253d6424840a81d141be803634b passed. Logs .local/audits/t227-corrected-{format,analyze,root,locald-analyze,init,api-regression,links}.txt; PSParser0/lychee514OK53unique0errors/5individualwhitespacediagnostics0. Direct18phaseoutputschecked: stage0no-keyproof,7fullkey-bearingwriters,1deferredlivewriter,8fullkey-bearingverifiers plusstage0absence; eachrequiredmarkeronce/positiveemptystderr. acceptedInitializationfileSecretScanComplete=false/deferredexactliveIO33, inventoryReplacementRejected=true. Deferredwriter excludesbothnativefiles becauseoriginalpathwasnotretained; no claimthatonlyoneknownfilewasdenied, no replayoflivefailedcheck oralternate reader/privilege/copy. Originalwrapper/manifest/boundaryJSON stillscanned; freshfullscan afterconfirmedchildexitdoesnotclose livecriterion. Safe EOFfailurecaptureboundedbyremaining30s andfixedtestdiagnostics kept; no rawprivateexception/path/secret. Initial4failedruns/compileerror andlaterunnecessarycastwarning preserved, correctedbeforecurrentchecks; onlycurrent correctedproof used. Reviewer inspectedsource/contracts/fixtures/markers/reusestats/currentlogs and didnotedit/build/test. FullT204/Q05/Q08/001.1, normalUI/diagnostics/reboot/otheruser/physicaloffline/CI/aggregate remainopen. Earlierexactdeniedoperationsunchanged/notretried/bypassed; no commit/push/PR/release/merge; global20package/60stagegoalactive.

- [x] T228 Дополнить T204/Q05 actualcredentialUI10steps: afterbootstrap/discoveryclose каждогопрогона test-only fileoracleboundtoownexecutablefixtureprofile читаетoriginalCurrentUserDPAPIreceiptwrapper послеsafe/owner-onlychecks, bindsactualtechnicalkeyraw/base64/UTF16, syntheticpassword/pem32bytes/passphrase/cancelledsecretpatterns. Сканироватьвсе productnamespace files includingDB/index/lock/wrapper/manifest/remainingruntime/temp, nofollowreparse/foreignsurface; verifyrequired4files/count/bytes, ownedbytecopywipe; noDBopen/metadatawrites. Proofcontainsmandatoryscanmetadata/newstagemarker, parentvalidatesall10; persistedsecretinputstablewithlongPEMbody avoidsambiguous3bytepattern. Currentrootformat/analyze/test/localdanalyze, rebuild10UIDrives, PSParser/links/whitespace/freshreadonlyreviewдоclosure. Not actualchildprocess-exit proof (discoveryremoval/productionstorageclose ordering), parentstdout/stderr/logs/source/testbinaries/foreignTemp excludedfromfilescan; notwholeT204/Q05/normaluninstrumentedentry/reboot/foreignuser. ExactdeniedliveuncommittedscanT227 not retried/bypassed.

T228 закрыт после completed fresh readonly ui_private_files_marker_review: nofindings/readyONLYscopedT228; fullT204/Q05/001.1 remainopen. Actual SAMEshell53850 terminalexit0 T228_ISOLATE_FIXED_CHECKS_AND_TEN_STEP_UI_PRIVATE_SCANS_PASSED: rootformat232/0, FlutteranalyzeNoissues7.4s/root237tests14s, localdanalyzeNoissues, rebuiltFluttertarget+normalAOTlocald/all10drivespassed. Fixture0131e1e4b6df414cae3b5c5282b8cc84:10distinctgenerations/0failureproofs/each4files1049269bytes/receiptKeyScantrue/scanAfterDiscoveryRemovaltrue;10scanmarkers oneeach. Previouscredential/cancel/delete/select/emptyreopen/quota250251/reopen assertions retained; final250/revision257/equaldigest. Test-onlyscannerboundtoownexefixtureprofile, nofollowpaths/ownerACL/productguard, originalDPAPIwrapper+manifestidentity, actualtechnicalkey andpassword/pem32bytes/passphrase/cancelledsecretpatterns; allnamespacefiles includingrequiredDB/lock/wrapper/manifest, owneddecodedcopy/patternwipe, noIsaropen/writes. Isolatewrapper captures3sendableargs only. Logs.local/audits/t228-isolate-fixed-{format,analyze,root,locald-analyze,ui,links}.txt; PSParser0/lychee514OK53unique0errors/6individualwhitespacediagnostics0; editeddoclinks8OK6unique0errors t228-doc-links.txt. Initialt228-ui Flutterbuildfailed because commoncheckimport pulledlocaldtestdependencies; fixedlocalhelpercheck. Secondt228-fixed-ui step0failedunsendabletestcontext, fixture795037a57d1b4159ac2abe987e250092 failedprivate-file-scan/ArgumentError; fixedtophelperIsolatewrapper, bothfailedlogsretained/no passclaimed. Reviewerreadsource/contracts/current10proofs/logs, independentlyparser0, no builds/tests/edits. Post-storage-close/discovery-removal scope, notactualprocessExit/parentstdoutstderrlogs/foreignTemp/sourcebinaries/uninstrumentedentry/fullT204/Q05/001.1. SpecificdeniedliveT227/ACL/HyperV/cleanup checks not retried/bypassed; no commit/push/PR/release/merge; globalgoalactive.

- [x] T229 Выполнить current fixed13phase available aggregate после T222–T228, безретрая/обходаexactdeniedoperations. Currentresult.json.excluded отдельноуказываетlive-uncommitted-native-file-read-LOCK_VIOLATION-33 помимоexistingunsafeACL/fullQ/manual/CI; fullAcceptance=false неизменен. Snapshot sourcefiles/hashes передпрогоном иvalidateafter: заморозитьapplication/test/build/spec/docs sources; generatedignored outputs permitted, changes sourceinvalidateproof. Same retainedprocesshandle untilterminal; all13exactphases actualserialrebuilds+strictchildproofs, API4pairs/init9partialpairs+negative/UI10privatefilescans включены. No defaultAll/manual/CIclaim ornewfullQgate closure. PSParser/ListOnly13/specLinks/whitespace/freshreadonlyreview and currentresult13complete/fullfalse/exactdeferredmetadata needed beforeclosure. PreservehistoricalT221 andallindividualpartialproofs, taskT227 remainsopen.

T229 закрыт после completed fresh readonly current_thirteen_phase_source_review: nofindings/readyONLYcurrentpartial13phaseincrement. Actual SAMEshell22649 retainedacrossautomaticcontinuation terminalexit0 T229_CURRENT_THIRTEEN_PHASE_AND_SOURCE_FREEZE_PASSED. Suite.local/available-acceptance-0affcc29914b4005b30984ff9037307a/result.json:statuspassed/13exactordercompleted/failedPhasenull/fullAcceptancefalse/excludedlive-uncommitted-native-file-read-LOCK_VIOLATION-33. Masterlog.local/audits/t229-suite.txt13START/PASS; durationssecondsCore330.2/Commit41.8/API43.2/Init44.5/Secret42.9/NormalPrereq66.7/Bootstrap149.1/UI2 63/UI3 64.1/ObserverCrash67.9/Loss67.2/Credentials173.5/Unknown56.9. ActualcurrentCore8 (resource190.5/channel12.9),Commit4/API4pairs/Init9pairs+negativepartial/SecretpositiveunsafeAclRejectedfalse/normalPrereq5/Bootstrapownerloss36ms+terminaltest/sixUIsuites/Credentials10privatefilescanproofs/currentquota250251/reopen. Sourcebefore.local/audits/t229-source-snapshot.json1580nonignoredsource/docs/assetsSHA; outerafterallhashesmatched andseparatepostinventory+hashcheckpassedterminalexit0 T229_CURRENT_RESULT_AND_1580_SOURCE_FILES_VERIFIED with.local/audits/t229-source-verified.json. No sourcepathsadded/removed/changedatthepostruncheck; snapshotendpointsnotcontinuousobservation. PSParser0/ListOnly13/lychee514OK53unique0errors/4individualwhitespacediagnostics0 logs t229-list/links/pre-review-links. NoFlutter/DartsourcechangeT229thusnoextraroottestsclaimed; T228rootchecks currentbeforefreeze, T047fullpackages historical. Reviewerindependentlyall1580hashes/inventory/parser0 andreadchildproofs/currentlimits; no builds/tests/edits. Closuremetadata/docs appendedAFTERhash/reviewinterval intentionally; application/test/buildsourcesunchanged, earlierendpointsproofnotclaimforpostclosuredoctext. OriginalT227open/initfileSecretScanCompletefalse/deferredwriterneverclean; fullT043/T044/T048/T049/T050/T201–208/001.1/manual/CI/licenses remainopen. Exactdeniedchecksnot retried/bypassed, no commit/push/PR/release/merge; overall20package/60stagegoalactive.

## Phase 6: Convergence

Targeted current diagnostic finding F230 (CRITICAL, partial), per Constitution III/FR-123/FR-SVC-016/SC-SVC-004/T204: production lib/main.dart onlyrunApp, no framework/platform/error-widget safe boundary. Installed pinnedFlutter3.47.7 assertions.dart FlutterError.onError=presentError→dumpErrorToConsole usesexception/stack/context/diagnosticcollectors; framework.dart defaultErrorWidget.builder stringifiesexceptioninDebug. Concretefailure: a framework exception/context/collector or unhandledUI-platform error contains enteredpassword/key/passphrase/privatepath; ordinaryfallbackcanprint/renderit. This is source-established fallback exposure, NOT a claimed observed actualsecret leak or full229task convergence audit. Existing domain/API normalization and native/at-rest scans do not cover this path. Other fullQ/manual/CI/license/runtime gates remain in their existingopen tasks; no wholeconverged/readiness claim.

- [x] T230 [CRITICAL] Define the UI runtime diagnostic boundary in current Plan/contracts before implementation per Constitution III/FR-123/FR-SVC-016/SC-SVC-004 (partial, F230). Specify components lib/main.dart + a presentation-independent helper, exactframework/platform/ErrorWidget coverage, fixedlocalUI category/safe nextstep, no rawexception/stack/context/library/informationCollector/identifier/credentials values. Decide sanitization beforedelegationtoexistingframework/test observers, exactly-once/idempotentinstallation/repeatedapp.main behavior, platformhandled/fallback semantics and helperfailure behavior; errorwidget mustnotrender rawdetails. No autosave/retry/reset/remoteeffects or inventedbackend status. Normal entry installation, release/debug behavior, oldcallback observability and acceptance controls remain separate. Add measurable normal/failure tests with syntheticsecret in ALLdiagnostic fields and renderedfallback, repeatedinstall/unhandledcases, no misleading fullT204closure; applicablelinks/freshreadonlyreview beforecodehandoff. This task records a missing decision rather than claiming a futuretask closes it.
- [x] T231 [CRITICAL] After T230 completed/clean package review, implement and verify the UI runtime privacy guard per Constitution III/FR-123/FR-SVC-016/SC-SVC-004 (partial, F230). Test realframeworkreporting and platformcallback/errorwidget boundaries withsyntheticpassword/key/passphrase/privatepath markers inexception/stack/context/library/collector; require ordinaryconsole/delegates/renderedfallback contain onlyspecifiedsafe values, preservefailureobservability and unchangeddata/mutations (no auto-repeat/reset). Rootformat/analyze/test plus appropriate compiledUI regression, relevantpackagechecks, specLinks/whitespace and freshcode/package review-fix loop mandatory. No swallowingunexpectedtestfailures, no rawdetail fallback when previoushandler absent/returnsfalse/throws, no globalstateleak betweentests. Current T228file and T229aggregate proofs remainhistorical for changedUIentry; do not reuse them as newguard acceptance. FullT204/normaluninstrumentedentry/failurematrix/manual gates needtheir actualevidence; specificdeniedT227/ACL/HyperV/cleanup checks remainopen/notretried/bypassed.

T230 design closed after completed fresh readonly ui_runtime_diagnostics_plan_review: nofindings/readyONLYT230→T231 implementation scope. Converge Phase6 appendedtwo tracedcriticaltasksforF230, thenPlanworkflowsetup-plan-Jsonpreservedexistingplan/templatecopyskipped. Plan/research/UIcontract/newruntime-diagnostics.md define exactsafe payload/category/ownership/callbackfalse/null/throw/reentrancy/sinkfail/ErrorWidgetdebugrelease/immutablebinding/restorationcollectability/testacceptance. No model/protocol/dependency/rights/mutation/retry/reset change. Sourceevidence inspectedpinnedFlutter3.47.7 assertions/framework/platform_dispatcher defaultflows + productionmain onlyrunApp; potentialfallbackexposure, no actualusersecretleak claimed. Actualdocs-onlychecks T230_FINAL_PLAN_CHECKS_PASSED terminalexit0: lychee520OK54unique0errors .local/audits/t230-plan-final-links.txt/5individualwhitespacediagnostics0. Reviewerreadartifacts/actualentry/SDK/contract, no builds/tests/edits. T231 codeabsent/open; runtimeprivacyacceptance/fullT204/Q05/001.1 notproven. Extensionhooksabsentbefore/afterConverge/Plan. Priorcompletedhistory/brandbook/hardcutover preserved; exactdeniedoperationsnotretried/bypassed; no commit/push/PR/release/merge; overallgoalactive.

T231 implementation in progress: production entry installs fixed-category framework/platform/error-widget guard; weak callback-owned immutable bindings preserve restored observer delegation and binding-local reentrancy. Root tests cover safe fields/no source stringification/collector/filter, callback restore/idempotence/null/false/throw/reentrant/sink-failure and test-binding failure observability. A separate compiled fault target and bounded output-checking driver are added; production-entry integration scenarios restore global hooks in finally before binding invariants. T231 remains open pending final current checks/compiled regression/fresh completed review. Prior failures/logs preserved; no fullT204/Q05/001.1 closure or exact-denied operation retry.

T231 closed after current implementation/checks and completed fresh readonly ui_runtime_diagnostics_code_review: no findings, ready only within T231. Final orchestration3435 terminalexit0 T231_FINAL_CURRENT_CHECKS_AND_UI_REGRESSIONS_PASSED: rootformat236/0 (ignored oldwork/flutter_lints warning retained), Flutteranalyze noissues7.3s, root250tests16s, rebuilt separate Debug runtime fault target with real build exception/safe observer fields/fixed console/render output and strict driver marker scan; normalReleasebuild; two/three-window/crash-observer/loss-recovery/unknown-inflight/bootstrap UI regressions all passed. Earlier completed orchestration49604 terminalexit0 ten-step production-entry credential regression; fixture foundation-ui-898257e1708b4a55ab276be2ec077056:10distinctgenerations, each postclose privatefile proof, final250profiles/revision257/equalstep8/9digest. Current faultfixture runtime-diagnostics-ac7574195b84453f84af18896516218e result passed/fullAcceptancefalse. Review-scope15hashes remained identical through all finalcode/UI checks. Actuallogs .local/audits/t231-final-{format,analyze,test,compiled}.txt, t231-credentials.txt, t231-release-build.txt, t231-{two,three,crash,loss,inflight,bootstrap}-ui.txt; lychee520OK54unique0errors, PSParser0,15individualwhitespace0. Earlier failed unit hook-restoration/analyzer attempts and interrupted diagnostic attempt preserved; no failure relabelledpass. Source literals/binaries/test inputs are outside runtime-output scan; no Release injectedfault/manual/fullT204/Q05/001.1 acceptance claim. Code/package/protocol/storage/credentials protection outside this UIguard unchanged; exactdenied operations untouched/open. Extensionhooksabsent before/after Implement. No commit/push/PR/release/merge. Overallgoal active; remaining mandatory stagegates stay open.

T205 current criterion inventory is recorded in [resource evidence](../../docs/development/foundation-resource-acceptance.md). Two missing native assertions are being added within existing scenarios, without extra product tasks: exact same physical normal-owner endpoint reuse with all other slots retained, and every five-row JSON cap/cap+1 startup preservation/reopen. Three protocol boundary vectors additionally cover the actual8KiB/256KiB/8MiB byte values. No production limits/hooks/storage/credential changes. Existing T194–T200/T224 and currentT231 UI evidence keep their actual scope; T205/T041 closure remains contingent on current checks and completed independent review, not on this inventory alone. Exact denied operations are untouched/open.

T205/T041 resource criteria closed after completed fresh readonly resource_acceptance_matrix_review: no findings, ready for the complete listed resource set only; reviewer explicitly supports both resource-checkbox closures while excluding fullQ10/001.1/manual/CI/otheruser/reboot/licenses/exactdeniedchecks. Criterion evidence is in foundation-resource-acceptance.md. Current completed exec11552 exit0: rootformat/analyze/root250tests, compiledCoreStorage8cases fixture8442b30c9f004b5bb8feeab79b8dafcb (Workspace2.1/repository74.1/credential0.4/mutations0.8/API0.2/channel13.1/lifecycle0.2/resources192.1), normalcompiledbootstrap1test145s and localdanalyze. New native5rowcap/cap+1/preservation/reopen marker exactlyonce; repository/channel/resource stderr empty; accepted.json8completed/boundTestExecutabletrue/10normalcontrolrejections. Normalbootstrap privately records endpoint names, saturates8slots with heldpeer, requires7distincthelperendpoints and replacement identicalreleasedphysicalname; exactchildmarker asserted in parent, stdout separately not retained. Completed exec41168 exit0 T205_CURRENT_ALL_REQUIRED_CHECKS_PASSED: finalrootformat237/0 (old ignoredwork flutter_lints warning retained), FlutteranalyzeNoissues/root250tests16s, protocolanalyze/39tests5s (actual8KiB/256KiB/8MiB cap/cap+1), Windows worker/pipe/disconnected4tests11s, localdauthsessions/lifecycle/channel23tests2s. PSParser0/9individualwhitespacediagnostics0/specLinks522OK55unique0errors. Source9hashes matched independent review snapshot; no code changed duringreview. T194–T200/T224 fixtures remain controlled native pressure; productionbootstrap sourcebinds same registry/coordinator/channel/workercallbacks and currentnormalowner sessions/reuse/lease plus T231production-main UIquota/loss cover requiredcomposition. No requirement to combineeveryceilinginnormalbinary added/waived.10000receipts seeded, not10000UIwrites; perrowchecks preserve rawrows, notDBbyteinvariance. Broader T038–T040/T043–T045/T048–T050/T185/T201–T204/T206–T208/T227 remainopen. Extensionhooksabsent. Exactdeniedoperations untouched/open; brandbook/hardcutover/historypreserved; no commit/push/PR/release/merge. Goalall20packages/60stages active.

T201 persisted-directory reparse increment implemented within existing task: [security evidence](../../docs/development/foundation-security-acceptance.md) inventories Q03/Q04/Q06 assertions and their unproven conditions. New workspace_reparse_scenarios.dart tests persisted product/workspaces/active and complete-empty-staging junctions against genuine DPAPI/Isar/owned Workspace.open. Refusal must precede protection/unwrap, preserve all target file hashes/inventory/parent/junction identity, and healthy recovery must retain workspace/key identity and state; production unchanged. Strict WorkspaceLifecycle/CoreStorage markers enforce allfourcases. This is not individual-file symlink/unsafeACL/foreignuser/normalUI/fullT201 closure. Initial test setup failed before move because destination parent lacked protected DACL; failed fixture retained/read-only ACL evidence, only new fixtures securely created. Current fixed checks pass; pending independent review. Exactdeniedoperations not retried/bypassed.

T201 expanded persisted reparse coverage to allfour private file paths (manifest/key/database/lock), using genuine Dart Windows file symbolic links to original regular files in an owned protected case root (DeveloperMode checked enabled). Exact4workspaceentries, independent WIN32_REPARSE_POINT guard, STORAGE_BLOCKED<30s, no protect/accesscredentialunwrap/no staging/reset, all4filehashes and linkidentity preserved, healthy originalworkspace/key/revision/profile/credential recovery. Source ordering is explicit: manifest/key0unwrap; DB/lock may have1originalsafe technicalreceipt-key unwrap before refusing their ownunsafe path. No requirement to forbid that safe earlier read is invented. Current expandedrootchecks/nativeWorkspaceLifecycle pass; prior directory-only freshreview nofindings remainshistorical, expandedfreshreview pending. WholeT201/T039/fullQ03/Q04/Q06/001.1 and exactdeniedoperations remainopen.

T201 persisted directory/file reparse increment accepted after completed fresh readonly persisted_file_and_directory_reparse_review: no findings, ready only for this increment. Reviewer inspected all6source/artifact hashes, complete chain FR-SVC-006/007→W02/W03→runtime-storage→T201/T039→Q06→eight compiled assertions; production APIs/formats/limits/ACLpolicy/protection unchanged. Actual completed exec73642 terminalexit0 T201_DIRECTORY_AND_FILE_REPARSE_CHECKS_PASSED: rootformat238/0 (oldignoredwork/flutter_lints warning retained), FlutteranalyzeNoissues7.5s, root250tests16s, localdanalyzeNoissues, rebuilt WorkspaceLifecycle3.7s. Fixture .local/native-acceptance-fa841a2dc2744672b907e682de601d06 accepted1completedcase/boundTestExecutabletrue/10normalcontrolrejections;8newdirectory/filemarkers exactlyonce/stdout strict/positive stderr0bytes. File setup actualDeveloperMode=true, trueDartfilelinks tooriginalregular targets outsideexact4nameworkspaceinventory, independentWIN32_REPARSE_POINT0x400. Directoryrefusal0protect/unwrap; filemanifest/key0unwrap, DB/lock1safe technicalreceiptunwrap permitted, all0protect/accesscredentialunwrap; targethashes/inventory/linkidentitypreserved; verifiedlink removal/ownedprotectedrestore recover original workspace/key/revision/profiles/credentials and realcredentialunwrap. No recursive targetdeletion, no skip/fallback/elevation on setupfailure. Initial unprotectedfixtureparent failedbeforemove/junction; failed22ffb268... data/rights preserved; fixed newfixturessecurelycreated. Earlier directory-only9eb88def... result/review historical, not substituted forexpandedacceptance. Logs .local/audits/t201-file-links-{format,analyze,root,native,locald-analyze,links}.txt; lychee524OK56unique0errors/PSParser0/6individualwhitespacediagnostics0; no code changed duringreview. FullCoreStorage/CI/manual not rerun/claimed. T201/T039 remainOPEN for genuineforeignuser/remote/missingVC/unsupporteddeployment/unprovedDPAPIconditions and remainingsecurityscope; exactdeniedACLnegative/liveuncommittedLOCK33/HyperV/cleanup/log403 checks untouched/open. No commit/push/PR/release/merge; brandbook/history/hardcutover preserved; overallgoal active.

## Native provenance convergence — T045/T207

- [x] T232 [HIGH] Complete Spec Kit Plan design for a new same-binding-version native source artifact: recipe/Cargo.lock, research, build-only entities, native-artifact contract, runtime sourcing transition and qualification quickstart. Trace Constitution VIII/FR-SVC-001/019 → pinned inputs/provider/notices → T233 → hash/offline/version/native/bundle acceptance. Run lychee and fresh independent readonly review; resolve confirmed mandatory gaps before implementation. Do not claim the new graph explains the old DLL; preserve existing completed history.
- [x] T233 [HIGH] Implement tools/prepare-native-isar.ps1, build-native-isar.ps1, native-artifact.ps1 and test-native-isar.ps1 per contracts/native-artifact.md. Produce the new DLL from checked Isar/MDBX/lock/toolchain inputs with a recorded minimal local-source patch, vendor checksums, offline frozen compilation and truthful graph/license/source artifacts. Integrate explicit candidate-only selection across build/test helpers; qualify current root/all-package checks, Debug/Release and available native/UI/fault phases against this DLL. Prove tampering/missing prerequisite/source/license/extraction failures preserve prior output. Extend notice collector and both actual bundles; activate only after successful qualification and clean fresh review. Rerun applicable mandatory checks and review/fix loop. No normal runtime override, silent cache fallback, user data migration/reset, publication or denied-operation retry. T045/T207 closure requires complete bundle evidence; full stage/CI/manual acceptance remains separate.

T232 design accepted after completed fresh native_artifact_plan_review: no findings; ready for T233 implementation only. All10 source hashes rechecked by reviewer. Actual lychee536OK/59unique/0errors, recipe JSON/lock digest and whitespace checks passed. No candidate DLL/build/compatibility/activation/bundle checks claimed; full001.1 and T045/T207/T233 remain open.

T233 preparation increment: tools/native-isar-inputs.ps1, prepare-native-isar.ps1 and test-native-isar-inputs.ps1 implement checked isolated source/toolchain acquisition and archive validation only. Actual cache-based preparation completed at .local/native-isar/prepared-11bf3827b4ab4443af95b134259261e4; compiler/Cargo identities and libclang DLL hash verified. First attempt preserved after intentional ZIP-link rejection; pinned README internal link handling corrected with recorded regular-file materialization. Eight malicious archive negatives, contained-link provenance and existing-output preservation passed at .local/native-isar-input-tests-5234890fc142405d842392082ad8a27b. No DLL build/vendor/license/provider/qualification/activation implemented or claimed by this increment. T233/T207/T045 remain open; independent preparation review pending.

T233 preparation increment accepted after fresh native_isar_preparation_fixed_review: no findings, readiness scoped to preparation only. First reviewer identified effective ZIP-byte budget omission; confirmed/fixed before extraction and reproduced with24byte payload/two links72byte output/48byte ceiling. Current tests exit0 include8archive negatives/materialization provenance/existing-output preservation/budget rejection; lychee536OK59unique0errors, PSParser0/5whitespace checks. Fresh corrected preparation also exit0 at .local/native-isar/prepared-7208609693364fa99ce485d016cd1016, no source files changed during review. Prior failed attempts remain preserved. TAR/reparse/hash/toolchain negative matrix still unproved.

T233 experimental build evidence, not qualification: ignored .local/audits/t233-build-probe.ps1 created isolated candidate-a7b3d4fb27394d01a42ae24b0acfc413; recorded minimal local MDBX-source patch, cargo vendor --locked, metadata --frozen and cargo build --frozen -p isar --target x86_64-pc-windows-msvc --release with CARGO_NET_OFFLINE=true succeeded. Release build41.02s, DLL1007104bytes/SHA2561e1819de8d1950b2d2e6fc5fe61f5736c05277cf661f9a776bb3753acadb4737, PE_machine8664, unchanged locked Cargo digest. Actual isolated absolute-DLL query exit0: isar_version3.3.2/isar_mdbx_versionv0.13.8-temp-upstream-fix. Compiler family detection warnings/unused original import/constant retained in build.log, not hidden. This proves an experimental same-version DLL can compile/load; no native storage/UI suites, second build, complete notices/source bundle, reusable build/provider/qualification tooling or activation established. Current runtime/default cached artifact unchanged. T233/T207/T045 and full001.1 remain OPEN; no denied operation/cleanup/ACL/global installation/publish/commit/push/PR/release/merge.

T233 reusable build increment: tools/build-native-isar.ps1 re-prepares checked inputs into a fresh owned directory, patches acquisition only, vendors locked dependencies, compiles frozen/offline with isolated Cargo/target and restored scoped environment, compares source/vendor/Rust/libclang inventories+hashes before/after, verifies lock/recipe/PE x64, and emits native-build.json state=built-unqualified/distributionReady=false. Actual build exit0 at .local/native-isar/candidate-9247f195b69041168218b67e59c99314, release38.30s; full tool invocation also includes preparation/hash passes. isar_version3.3.2 and MDBX tag queried separately. tools/test-native-isar-build.ps1 current exit0: bad cached hash rejected; child-only missing-MSVC-discovery condition rejected; prior candidate receipt+DLL bytes unchanged. Test fixture .local/native-isar-build-tests-8c9f03f75b9a46798ab188c41d5ad238. Initial negative driver failed before process start because Get-Command returned multiple pwsh paths; evidence retained, fixed to current PSHOME executable. No system-denial retry. Complete native-artifact/graph/license/source/qualification/provider/activation, product compatibility suites and second repeat build remain unproved. T233/T045/T207 stay OPEN; fresh independent reusable build review pending.

T233 reusable-build first review confirmed P1 ambient overrides omitted bindgen/cc host-target/archiver/MSVC variables. Corrected scoped clear/save/restore set to include Cargo/Rust, BINDGEN/clang/LLVM, HOST_/TARGET_, compiler/CXXSTDLIB/CRATE_CC/archiver, MSVC CL/_CL_/LINK/_LINK_, stale VSCMD; clears inherited VS inputs before pinned environment. Actual enhanced test driver terminalexit0 .local/audits/t233-build-environment-regression.txt: real fresh candidate-1261478a42c94735a016e998c9519302 release38.72s despite16syntheticinvalid overrides, all inputs verified; all16values restored after success and controlled missing ComSpec prerequisite inside scoped block. Parent environment restored finally; prior candidate-9247... DLL/receipt unchanged. Bad-cache and controlled missing-discovery negatives also pass. Fixture native-isar-build-tests-fad30773826f4c7db233911601284389; fresh version query3.3.2/MDBXtag succeeded. This is build isolation/repeat evidence only; graph/license/source/provider/qualification/native/UI/fullstage gates remain open. Fresh corrected review pending.

T233 reusable-build increment accepted after completed fresh native_isar_reusable_build_fixed_review: no findings; readiness scoped to this increment only. Reviewer independently checked all5frozen hashes, pinned dependency consumers, full requirement/contract/task/acceptance chain and actual logs/receipt/DLLhash. Confirmed previous ambient-isolation finding closed with expanded scoped isolation plus real16override build/restoration success+refusal evidence. No reviewed code changed. T233/T045/T207 and complete001.1 remainOPEN pending complete graph/licenses/sources, provider wiring, current native/UI qualification/bundles/failure matrix and fresh whole-increment review; new DLL not activated and default cache unchanged. Supplemental research only: official MPL2.0 plaintext downloaded to .local/native-license-research/MPL-2.0.txt, SHA3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04/16726bytes; not yet a recipe/notice/distribution input. No commit/push/PR/release/merge or denied-operation retry.

T233 bound-graph increment: native build receipt now binds metadata SHA and ordinal-sorted source/MDBX/vendor/Rust/libclang tree digests; collect-native-isar-graph.ps1 verifies receipt/recipe/lock/DLL/metadata/source trees/generatedversion and registry checksums/identities/edges, exports machine-path-free Windows-filtered conservative67package graph. Exact declared versions/licenses retained; root Rust0.0.0/undeclared license separately attributes pinned root Apache LICENSE. Graph remains graph-collected-unqualified/distributionReady=false, not linker inventory or complete native artifact/qualification. Full canonical MPL2 text added as pinned recipe/license input and copied with source/hash; https://www.mozilla.org/media/MPL/2.0/index.txt / SHA3f3d9e0024b1921b067d6f7f88deb4a60cbe7a78e76c64e3f1d7fc3b779b9d04 /16726bytes. Recipe change invalidates historical receipts for current collection; no retroactive provenance claims.

Actual bound build/environment regression terminalexit0 .local/audits/t233-provenance-bound-build.txt: candidate-5d19538b483f4c23b7dd16e3c16b2289 release38.58s,16poisoned override success/restoration plus scopedmissingComSpec/badcache/controlledmissingdiscovery/prioroutputpreservation. Earlier graph tests exit0 deterministic67packages/no absolute paths/DLL+metadata refusal/prior output preservation; canonicalMPLhash and all3 source trees/generatedC binding additionally checked. Final current tests/review evidence follows below. Complete notices/NATIVE_SOURCES.zip/provider/qualification/defaultbundle change unproved. Vendor contains91registry packages vs67Windows-filtered graph packages including3path crates; all included source-archive material needs license coverage. Eight unused-platform vendor packages lack root-level license files; supplemental coverage still needed. Rust runtime full copyright/licenses and MDBX LICENSE/COPYRIGHT/NOTICE available in checked inputs, not yet bundled. T233/T207/T045 OPEN; no denied operations or publication.

T233 bound-graph increment accepted after completed fresh native_isar_bound_graph_review: no findings, readiness scoped to this increment only. All9frozen hashes match. Reviewer independently compared67packages/67nodes/104directedge records to boundmetadata with0mismatches, recomputed source738/vendor6966/MDBX192file digests and checked actualDLL/metadata/patch/generatedversion/full16726byteMPL hashes;4PSParser0. Actual final graph tests terminalexit0 .local/audits/t233-native-graph-current-tests.txt output graph-43a29ba1039b4bf8ba78e1702d8ab9e2, deterministic JSON/no machine paths/root attribution/closed edges/pinnedMPL/DLL+metadata refusal/prior preservation. Actual build/override driverexit0 and separatecurrent versionquery3.3.2/MDBXtag; DLLSHA17fb5deaba528a0627cf5caf4526c6dbce91629e8c4805f05b3b2ffefac7e520/1009664bytes. Mandatory lychee537OK60unique0errors/9whitespacepassed. No reviewedcode changed. Full source/license inventory/archive/Rust runtime/notices/provider/nativeUIqualification/bundle activation remainOPEN; T233/T045/T207 notclosed. Additional readonly upstream-license research local: JNI/NDK publishedVCS commits and GNUwinapi license sources available; four Sheldon matching version tags lack standalone license files, publishedMIT/author metadata preserved, no copyright notice invented. Supplement strategy not yet distribution evidence. No deniedoperation/cleanup/ACL/commit/push/PR/release/merge; default cachedDLL unchanged, overallgoal active.

T233 source-supplement increment: independent supplemental-licenses.json pins8packages/9full source-license texts, actual published registry checksums/Cargo manifests/declared license+authors, upstream commit/text hashes. JNI/NDK published VCS evidence and GNUwinapi0.4.0 upstream package manifests verified; four olderMIT packages use exact pinned SPDX MIT standard template with placeholders unmodified and published authors separate, no fabricated copyright. native-isar-supplement-inputs.ps1 validates fixed input/file/identity; collect-native-isar-supplements.ps1 verifies bound graph/trees then copies all texts+manifest and emits partial notice/receipt unqualified/distributionReady=false. test-native-isar-supplements.ps1 actual terminalexit0 .local/audits/t233-source-supplement-tests.txt:8declared packages/9full texts, placeholder preservation, tampered text/registry identity refusal and original DLL/receipt/output preservation. Output candidate-5d19538b483f4c23b7dd16e3c16b2289/supplements-b6a037bbcf224e07a08a288cdb7f24eb. Build recipe/DLL unchanged. Full notice inventory/Rust runtime/NATIVE_SOURCES.zip/provider/qualification/activation not complete; T233/T207/T045 OPEN. Current mandatory checks/fresh independent review follow. No system-denial retry or publication.

T233 supplemental vendor-source increment accepted after completed fresh native_isar_source_supplement_review: no findings; readiness limited to supplement collection. Reviewer independently checked16frozen hashes, all8published.crate registry hashes, manifests/versions/licenses/authors, publishedJNI/NDKVCScommits, GNUwinapiupstream0.4.0 identities, all9immutable upstreamtext bytehashes, Sheldonversiontaglicenseabsence/templateorigin/noinventedcopyright, alloutput/build/graph/inputhashes and candidate source/vendor/MDBX bindings. Actual supplement tests terminalexit0 and lychee539OK61unique0errors/3PSParser0/7codeJSONdocwhitespacepassed;9upstreamrawtexts bytepreserved. No reviewedcode changed. Complete notices/Rust runtime/sourceZIP/provider/qualification/activation remainOPEN; no T233/T207/T045/fullstage closure. Independent Rust-material research found compiler/std archive-root COPYRIGHT/LICENSE-APACHE/LICENSE-MIT (1571/9723/1068bytes), distinct from installed Cargo license texts (10860/1023bytes); final runtime notice collection must preserve verified Rust archive texts and bound COPYRIGHT-library.html, not substitute Cargo licensing. Local research inventory .local/native-license-research/rust-license-files.json is not distribution evidence. Default DLL/buildrecipe unchanged; no deniedoperation/cleanup/ACL/commit/push/PR/release/merge; overallgoal active.

T233 Rust-material increment: rust-license-material.json independently pins8full distribution license/copyright files,3Rust archive identities and exactsource paths/hashes/lengths/roles. native-isar-rust-inputs.ps1 validates pinned archives/materials and completeassembledSDK against candidate build Rustdigest; collect-native-isar-rust.ps1 revalidatesboundgraph and freshly preparesinputs, copiesexactruntime/build-tool files, fullplainnotices/HTMLreferences/copiedmanifest/partialreceipt unqualified/distributionReady=false. Runtime std rootlicense9723/1068bytes explicitlydistinct from Cargo10860/1023; complete COPY library/compiler HTML bytes preserved as data, not executed/converted. First actual tests terminalexit0 .local/audits/t233-rust-material-tests.txt:8copies/roles/fulltextrefs, changednotice/archive and emptydifferentSDKrefusal, previousDLL/receipt/outputpreserved. Originaloutput rust-material-dca06bf8e6ea4970861e8901106c07de; negativefixture native-rust-license-tests-ac72076965df4ee582f4c3a60572a414. Added manifestbefore/afteridentity and exactcopiedmanifesthash guards; currentrerun/review evidence follows. Fullnative notices/SOURCEZIP/provider/compatibility/activation remainOPEN; T233/T207/T045 notclosed. NoFlutter/runtime/buildrecipe/DLL mutation, no deniedoperation/cleanup/ACL/publication.

T233 Rust distribution material increment accepted after completed fresh native_isar_rust_material_review: no findings, readiness scoped to this material collection only. All7frozen hashes unchanged. Reviewer independently checked3pinned archive hashes,8exact archive member/extraction/output bytehashes/lengths, runtime1068byteMIT vsCargo1023 distinction, full library/compiler HTML and explicitroles, fullnonHTMLnotice/ref completeness, and assembled SDK124file digest12450e51070b644586c73d7546c1c88e97d5dec805bae674d1f2d323654fc8ba matchingcompiledreceipt. Receiptbuild/graph/inputmanifest/notice bindings verified; unqualified/distributionReady=false. Actual final test driver terminalexit0 .local/audits/t233-rust-material-current-tests.txt output rust-material-12532e874e9a41349464c1575fd6e530, freshprepared390b081939ba477caeefb7e604ee2664, negativefixture958edbc5bc634884a311112e57858656;8copies/roles/texts/ref/tamperedmaterial/archive/differentSDKrefusal/priorDLL/receipt/noticepreservation. Mandatory lychee540OK62unique0errors/3PSParser0/7whitespacepassed. No reviewedcode changed. Fullnative notices/sourceZIP/reproducible source package/provider/nativeUIqualification/bundle verification/activation stillOPEN; T233/T045/T207 and001.1 notclosed. Source research inventory91vendor directories/160rootlicense texts/8supplementedmissingroottexts recorded locally at .local/native-license-research/vendor-root-texts.json for full notice assembly, not distribution proof. No deniedoperation/cleanup/ACL/commit/push/PR/release/merge; defaultDLL unchanged and overallgoal active.

T233 aggregate native notice increment: collect-native-isar-notices.ps1 revalidates source graph and same-build/current-graph component receipts, all91locked registry vendor identities/checksums/license declarations, collects183exact files (161recursive vendor inclnestedUnicode,1project,1MPL,3C MDBX,9supplemental,8Rust). Plain THIRD_PARTY_NATIVE_NOTICES.txt includes all declarations/fullnonHTMLtexts/relativefullHTMLrefs/templateorigin/authors; native-notice-inventory.json binds inputs/build/graph/manifests/notice and perfilehash/length/role. Freshnotice directories; unqualified/distributionReady=false, sourceZIP/qualification/activation open.

First aggregate attempt refused oldcomponent graph hashes. Integration confirmed prior graph nondeterminism across PowerShell processes: unordered Ccomponent fields and descriptor.Values hash-table iteration; named-property Sort-Object did not reliably project ordered-dictionary keys. Failed evidence preserved .local/audits/t233-native-notices-collection.txt and t233-graph-cross-process-tests.txt. Fixed explicit ordered Ccomponent, ordinal package keys and explicit dictionary sort selectors; graph repeat test now uses a new PowerShell process. Current crossprocessgraph driverexit0 .local/audits/t233-graph-cross-process-fixed-tests.txt, refreshed supplement/Rust drivers terminalexit0 .local/audits/t233-notices-{supplement,rust}-refresh.txt; all same graph SHAeb61390cefdbaa3e94e7047c7a72d2444cfbe171c127be5bba41a2d54305f6e2. Old process-dependent receipts remain historical, not relabelled. DLL/buildrecipe unchanged.

Actual final aggregate test driver terminalexit0 .local/audits/t233-native-notice-tests.txt:91packages/183exactcopies/completeplaintexts+HTMLrefs/nestedUnicode/perfileintegrity/privatepathabsence, exact notice/inventory equality across separatePowerShellprocesses, tamperedRustcopy refusal/priornotice/DLL/buildreceiptunchanged. Current output notices-6a4c5fe82ac246ea9202ffba9b968693 undercandidate5d195... . Complete notices collection does not establish corresponding sourceZIP, finalartifact, distribution/compliance/product compatibility; T233/T207/T045 OPEN. Current mandatorychecks/review follow; noFlutter/runtime/data/defaultDLL change, no deniedoperation/cleanup/ACL/publication.
T233 aggregate native-notice increment accepted after completed fresh native_isar_aggregate_notice_review: no findings; readiness scoped to aggregate collection and cross-process graph determinism only. Seven frozen file hashes unchanged; reviewer independently verified all91packages/183files,161recursive vendor texts, exact hashes/full texts/relative references, same-build graph/component bindings and separate-process output equality. Actual driver exit0 and mandatory lychee540OK62unique0errors; PSParser/whitespace passed. Source ZIP, finalartifact/provider, native/UI qualification and activation remainOPEN; T233/T207/T045 notclosed. No denied-operation retry or publication.
T233 offline vendor-reuse increment in progress: paired build-only VendorSource/VendorSha256 inputs check complete bounded plain-file snapshot before preparation, copy/verify into fresh candidate and use frozen offline compilation without cargo vendor. Fresh repeat build and changed/added/missing source refusal verification pending. Complete sourceZIP/provider/qualification/activation remainOPEN; no task closure or full acceptance claim.
T233 offline vendor first completed review confirmed one P2 relative-path defect: valid VendorSource was initially resolved in caller directory but reused after Push-Location source. Fixed early absolute normalization in caller context and changed actual repeat driver to supply a relative source. Original absolute-input driver terminalexit0, fresh release39.27s and actual DLL versions3.3.2/MDBXtag verified; this does not close the defect until corrected relative-input rerun and fresh review complete. All T233/T207/T045 gates remainOPEN.
T233 exact source-ZIP writer increment: native-isar-source-archive.ps1 implements bounded explicit SHA-bound inputs, safe-name preflight, ordinal fixed-metadata ZIP and existing-output preservation; actual source-writer driver terminalexit0 .local/audits/t233-source-archive-writer-tests.txt verifies separate-process/reversed-input byte equality, extracted binary/Unicode hashes, unsafe/duplicate names/wrong digest/no output replacement. Fixture native-source-archive-tests-478b84d8ef104a1a8ec4ab7b468cfe4b. Complete corresponding-source selection/manifest/reproduction/archive/provider/qualification remainsOPEN; this is a writer utility, not source completeness evidence. Review pending.
T233 offline vendor reuse and exact ZIP writer increments accepted after completed fresh native_isar_vendor_zip_fixed_review: no findings; readiness limited to these two increments. All8frozen hashes unchanged, reviewer independently parsed5PSfiles with0errors, inspected source/vendor/receipt bindings and read exact cross-process ZIP metadata/extracted binary+Unicode hashes. Original relative-path P2 closed by early caller-context normalization and actual relative-input fresh release build38.85s. Corrected driver terminalexit0 .local/audits/t233-native-vendor-relative-tests.txt includes both local-snapshot and caller-relative markers; candidate-fed22c3587304e8c92d44f192b739820, fixture69d7e50ac7ff4deda047f8744379489c. Separate actual DLL query exit0 .local/audits/t233-native-vendor-relative-version.txt reports Isar3.3.2/MDBXpinnedtag. Writer driver exit0; mandatory lychee540OK62unique0errors and8whitespace checks passed. No fullsourceZIP/artifact/provider/nativeUIqualification/bundle/activation closure; T233/T207/T045 remainOPEN. No denied-operation retry/publication/defaultDLLchange.
Next source-package assembly preparatory evidence only: .local/audits/t233-source-package-layout.json records738source files/193MDBXincluding separatelygeneratedversion.c/6966vendor files and adjacent source.materialized-links.json. Original GNU vendor .a inputs must be retained to preserve the vendor digest rather than treated as generated target products. tools/reproduce-native-isar.ps1 has a proposed standalone manifest/tool/archive verification and local-vendor build entry; parser/whitespace only, not executed or included in completed review. Complete source allowlist/manifest/archive/reproduction integration and new review remain required; no source completeness or qualification claimed.
T233 complete source-package increment in progress: collect-native-isar-sources.ps1 assembles exact original archives/compiled source trees/vendor/patch/README materialization/explicit native manifests+text allowlist/all183notices/graph/five standalone tools and relative reproduction manifest into fresh bounded deterministic ZIP. reproduce-native-isar.ps1 verifies manifest/tool/archive inputs, uses included local sources/vendor and external pinned toolchain, then checks resulting input identities. test-native-isar-sources.ps1 prepares full tree/notice checks, source-cache/manifest/archive refusal matrix, concurrent separate-process full repack and real standalone release/version test. No success or qualification claim yet. First assembly terminated because the agent changed reproduce-native-isar.ps1 after its digest was captured; exact-input writer refused Native source archive input changed. Failed sources-5802c4ed609447eea55340b4dfc95402 retained without successful source receipt. This was a mutable-input implementation failure, not an OS protection denial. Inputs now fixed; fresh assembly session69703 ongoing. T233/T207/T045 remainOPEN.
T233 first complete-source review found2confirmed P2 issues and concluded notready: inherited whitespace-split RUSTFLAGS breaks spaced roots; pinned linker failed opening an existing261character Rust rlib under the105character extraction root. Source driver session99870 terminalexit1/Frozen native build failed; full ZIP repack separately matched18a36760e67407a60ba6bdaa233ec023428769d79633aedeb4d7d6c2fe94c012. Reviewer independently checked all8107entries/compiled tree digests/183notice hashes/tool/archive/patch/materialization/receipt bindings. Actual Cargo1.88 probe stderr under .local/audits/t233-space-flags-probe-root.txt confirms split remap argument; probe assertion expected a different compiler diagnostic, evidence retained. These are code/prerequisite errors, not protection denials.
T233 fixes in progress: build helper now conveys remaps with CARGO_ENCODED_RUSTFLAGS/U001F and saves/restores the variable; builder/reproducer reject roots longer than80UTF16 characters before preparation. Manifest/REPRODUCE specify budget; actual driver selects short spaced extraction root and checks invalid encoded flag replacement/restoration plus both preflight refusals. Existing receipts retain original provenance; fresh assembly session36540 ongoing with fixed tool inputs. No current corrected standalone success or clean review claimed yet. All T233/T207/T045 and whole001.1 remainOPEN.
T233 complete corresponding-source package increment accepted after completed fresh native_isar_complete_source_fixed_review: no findings; readiness scoped to source assembly and standalone reproduction only. All7frozen file hashes unchanged. Reviewer independently checked8107ZIP entries,738/192/6966tree digests, originalarchives/patch/README record/manifests/fivetools/183fullnotice files/91packages/absenceofprivateSDKgeneratedroots and full cross-process repack SHA11bfc00c0b51b684c32e98d64df8e432bfe391caf4c61d6b09f457882887472d. Fixed sources-3d5473462bf0455897e86016dbabf258 zip46385306bytes remains sources-collected-unqualified/distributionReady=false.
Actual corrected full driver session96000 terminalexit0 .local/audits/t233-complete-source-fixed-tests.txt: complete archive/source/notice checks, missing/corrupt source cache and rewritten identity/tool/extracted-archive refusal, both early80UTF16root-budget refusals, separateprocess/reversedorder full8107file repack, fresh standalone frozen/offline release39.27s under53character spaced root .local/src space-e8d000bd, actual encoded inherited flag replacement/restoration, compiled input equality, safe-flag loaded DLL3.3.2/MDBXpinnedtag and originalDLL/build/source receipt/ZIPpreservation. Output candidate4b4e323a042a4b2b9f651e75939e8513 underextractedroot; fixtureefd1e5b838704103886fbbd600f2b8c3. Both previousP2findings closed. FourPSParser0/sevenwhitespace and mandatorylychee540OK62unique0errors passed. Failed first mutable-input ZIP and deep-root linker fixture preserved. No denied-operation retry/globalsetting/link/install/publication/defaultDLLchange. Final native-artifact/provider/nativeUIqualification/bundleverification/activation and T233/T207/T045/whole001.1 remainOPEN; no task checkbox closed by this increment.
T233 unqualified artifact assembly increment in progress: assemble-native-isar-artifact.ps1 and native-isar-artifact-inputs.ps1 combine197exact payload files, canonical recipe digest and complete source/notice/build/graph/tool bindings, validate owned parent/DLL/receipt, safe copy paths, unlisted data and embedded source-ZIP references. Native-artifact.json remains artifact-assembled-unqualified/distributionReady=false. First canonical implementation lost singleton-array shape through PowerShell pipeline assignment; corrected direct assignment. Expanded corpus exposed empty-object property enumeration under StrictMode, corrected before final rerun. Failed/older logs retained; no false success inferred from an enclosing shell exit0 when the driver reported an exception. Current final artifact driver session21998 pending; no qualified/provider/nativeUI/bundle/activation/T233/T207/T045 closure. No Flutter/user data/defaultDLL change or denied-operation retry/publication.

T233 partial follow-up: independent artifact assembly review reported two confirmed validator defects: missing embedded compiled-tree/allowlist binding and missing reproduction unqualified-state assertion. Validator now checks full source/MDBX/vendor inventories and digests, exact remaining ZIP references, pre-stream archive resource bounds and reproduction state. Four coherent rewrite regressions added; checks and fresh independent review pending. This does not close T233 or any qualification/activation gate. Prior completed task history remains unchanged.

T233 artifact review-fix verification: test-native-isar-artifact completed with terminal exit 0 and marker NATIVE_ARTIFACT_197_FILES_CANONICAL_ARRAYS_CROSS_PROCESS_AND_ELEVEN_REFUSALS_PRESERVATION_PASSED; evidence .local/audits/t233-native-artifact-review-fixed-tests.txt. Full candidate validation and separate-process assembly succeeded; all eleven refusal fixtures were rejected with expected diagnostics; original manifest/DLL/ZIP hashes preserved. Three PowerShell parsers and six whitespace checks passed. lychee specs/**/*.md: 540 OK / 62 unique / 0 errors (.local/audits/t233-native-artifact-review-fixed-links.txt). No Flutter or qualification/activation checks were claimed. Fresh independent review remains required.

T233 unqualified artifact assembly accepted after completed fresh native_isar_artifact_assembly_fixed_review: no findings; readiness limited to full unqualified candidate assembly/structural validation. All six frozen hashes unchanged. Reviewer independently validated the normal artifact, all eleven existing refusal fixtures, 738/192/6966 embedded tree digests, 8107 entries and resource/type metadata; three parsers had zero errors. Prior coherent-source/allowlist and reproduction-state findings closed. Actual driver exit0 and lychee540OK62unique0errors are recorded above. Full qualification/provider/bundles/activation/T233/T045/T207/001.1 remain open.

T233 qualification source snapshot increment in progress: build-only native-artifact-source-snapshot.ps1 computes an ordinal path/hash snapshot covering application/package code, assertions/fixtures, assets, Windows runner inputs, package manifests/locks, tools, native source recipe/licence inputs, workflow and normative service specification/plan/data-model/contracts/constitution. Mutable tasks/quickstart/evidence/local build roots are excluded. Regression uses only a fresh owned copied fixture; source/contract/lock/tool changes and additions must change the digest, missing root manifest must refuse, mutable evidence must not change it, cross-process equality and original preservation are required. Current test pending; no qualification receipt or active selection produced.
T233 snapshot first regression terminated with exit1/Original qualification source changed: the agent appended the normative contract while the driver was running. This is a correctly detected changed input, not a protection denial or successful run. Failed evidence preserved in .local/audits/t233-qualification-source-snapshot-tests.txt. Normative inputs now frozen for a fresh run.
T233 source snapshot actual fresh regression terminalexit0: .local/audits/t233-qualification-source-snapshot-fixed-tests.txt contains NATIVE_QUALIFICATION_SOURCE_SNAPSHOT_CROSS_PROCESS_MUTATION_EXCLUSION_AND_PRESERVATION_PASSED. Copied fixture1edf2c6ae56a4c079cc3d7411cf1535e retained; cross-process equality, four source mutation classes, added source, required-file refusal, mutable evidence exclusion and original preservation passed. Two parsers/five whitespace checks passed; lychee540OK62unique0errors. Fresh independent review pending. No Flutter code or DLL provider selection changed; T233 and stage gates remain open.
T233 snapshot first completed review found one confirmedP2: test_driver/integration_test.dart and locald build.yaml/dart_test.yaml omitted despite being executed assertion/generation/concurrency inputs. Added full required test_driver directory, required locald configs and optional root/otherpackage build/test config coverage; regression extends to allthree mutations, optionalconfig/assertion addition/removal and missing localdconfig refusals. Corrected checks/review pending; previous task history preserved.
T233 snapshot coverage fix actual final regression terminalexit0 .local/audits/t233-qualification-source-snapshot-final-tests.txt marker CROSS_PROCESS_MUTATION_EXCLUSION_AND_PRESERVATION_PASSED; fixture73e72742e5dc49e489b7b4e2b9c70cd4 preserved. Previously omitted UI driver/locald generation/concurrency configs are now covered and their mutations invalidate digest. Optional root/package config and added assertion inclusion/removal verified; missing fixed locald configs refuse; canonical separate-process equality, evidence exclusion and original preservation passed. Driver also handles pre-existing optional fixture inputs without assuming absence; that branch was inspected, not separately exercised on this checkout. Two parsers/five whitespace passed; fresh lychee/review below. No provider/qualification/activation or task closure claim.
T233 source snapshot increment accepted by completed fresh native_qualification_source_snapshot_fixed_review: no findings; readiness scoped to snapshot helper only. Allfivefrozenhashesmatch, independent344file/3841567byte snapshot matches retainedfixture and includes prioromittedtestdriver/localdconfigs. FullT233/provider/qualification/bundles/activation remainopen. Candidate selection integration nowinprogress; firstscope test failed because immutable JSON writer refuses replacing existingcontext. Operational context terminalwrite nowuses freshsibling plus same-directory atomic replacement; originalfailed evidence retained. No qualification success claimed.
T233 selection second regression failed with Invalid native qualification context identity: ConvertFrom-Json reads PID as Int64. Guard corrected to allow integer Int32/Int64 within valid positive PID range; priorfailed evidence retained. Mandatory root format firstattempt failed enumerating old failed standalone source fixture's overlong relative path before Dart's hidden-directory filter; no format/analyze/test success claimed. Byte-preserving relocation to a short owned .local root in progress with full before/after tree hashing; this is a path-length error, not a protection denial.
T233 integration actual earlier checks: candidate scope matrix terminalexit0 with childselection/sevenrefusals/success+failure env restoration/preservation; threepackage analyzers and tests39protocol/34Windows/85locald passed against explicitcandidate; rootformat239files0changed and FlutteranalyzeNoissues37.9s, rootFlutter250tests15s passed; source snapshot preserved. FivePSParser0/17whitespace and lychee passed. Formatter had long-path enumeration failures in retainednestedsource inputs; byte-preserving relocations .local/audits/t233-formatter-*-relocations.json and t233-formatter-failed-source-relocation.json retain exact maps/hashes. Current candidate bundle preservation logic added before Debug/Release validation so unqualified builds do not leave normal private bundles replaced; current checks/review pending for this additional PS change. FullT233 and qualification/activation remainopen.
T233 actual Debug/Release candidate bundle build scope terminalexit0: both run-foundation builds produced normal testOnlyfalse bundles with selectedDLL17fb5de... and matching manifests, generated source remained unchanged, outputs retained under ownedcontext/candidate-bundles, preexisting normalDebug/Release restored with exacttreehashes. No UI or fullqualification/activation claim. New eight-refusal/controlled partialbundle failure regression nowpending.
T233 candidate integration current final evidence: terminalexit0 .local/audits/t233-native-candidate-selection-final-tests.txt with CHILD_EIGHT_REFUSALS_SCOPE_AND_PARTIAL_BUNDLE_RESTORATION marker; malformed preservation type refused, controlled partial build failed as intended and both original normalbundle hashes restored. Actual successful Debug/Release build context1280d87fb9894b30a4662606abcf7f2a contains candidate-bundles and bundle-preservation.json with restored=true for both configurations; selectedDLL and both manifests match17fb5deaba528a0627cf5caf4526c6dbce91629e8c4805f05b3b2ffefac7e520. Captured paths remapappRoot; no normalentry/activepointer modified. Root250 and package39/34/85 tests and all analyzers passed against the candidate selection before the later PS bundle-preservation additions; Flutter/Dart implementation stayed unchanged afterward, build_runner wrote0outputs and scope sourcefreeze passed. Actual bundle builds and final selector regressions cover later PS changes. This is candidate integration, not full qualifier/normalqualifiedprovider/notices/UI/activation readiness. Fresh independent review pending; no task checkbox closed.
T233 candidate integration accepted by completed fresh native_candidate_integration_review: nofindings, readiness scoped to explicitcandidate selection and normalbundle preservation only. All17frozenhashesmatch; reviewer checked retainedDebug/Release manifests/DLLhashes/restoredreceipts. Supported checks/build/native suite order remains sequential perquickstart37; parallel controllers and crash outsidefinally notaccepted. Root/package tests and currentfinalselector/build evidence scope recorded above. Fullqualifier/qualifiednormalprovider/notices/nativeUI/activation/T233/001.1 remainopen.
T233 actual available candidate acceptance completed: controller session58781 terminalexit0 with CANDIDATE_THIRTEEN_AVAILABLE_PHASES_RUNTIME_DIAGNOSTICS_SOURCE_FREEZE_AND_BUNDLE_RESTORATION_PASSED. Suite .local/available-acceptance-6ccf518446f84cc5aa6dc3880c3ff860/result.json records all13 phases passed; .local/audits/t233-native-runtime-diagnostics.txt contains COMPILED_UI_RUNTIME_DIAGNOSTICS_ACCEPTANCE_PASSED. Context .local/native-qualification-d2a2914ff91349fd88cacd5ca9f4ad88 is candidate-validation-finished; DLL17fb5deaba528a0627cf5caf4526c6dbce91629e8c4805f05b3b2ffefac7e520; source snapshot e052dd1d7ebe8178eeb08383d770e66223425044959c2c3a9914872813e45df0 preserved. Independent postcompletion recheck verified the source digest and both original normal Debug/Release bundle tree digests. Bound evidence .local/audits/t233-available-candidate-completed-1bea50083b574721891f33355f6f1b26.json remains distributionReady=false/fullAcceptance=false/qualificationComplete=false; manual/Q/reboot/other-user/offline/CI and exact denied operations remain excluded/open. Additional read-only .local/audits/t233-candidate-abi-857853a75b6d4365a422d53f7eb8bf88.json proves PE32+x64, Isar3.3.2, pinned MDBX tag and all93 resolved binding exports, including both direct runtime finalizer lookups. Full qualifier, combined native/Dart/Flutter/font notices, normal qualified provider and activation remain open; no checkbox closed.
T233 combined notice/source collection implemented as explicit -NativeArtifact mode; historical no-argument preview retained. Actual fresh driver .local/audits/t233-bound-third-party-notices-tests.txt terminalexit0 marker BOUND_NATIVE_NOTICES_SOURCE_COPIES_CROSS_PROCESS_REFUSAL_AND_PRESERVATION_PASSED; fixture .local/bound-notice-tests-10229e13213041e5bcf18c773cae3e43 retained. Both separate-process outputs have199files, including196 non-DLL candidate payloads, native manifest and two combined files; full native aggregate and payload hashes match, corrupted native text and existing output refuse while prior output/original artifacts remain unchanged. Current resolved90hosted identities/95combined text blocks; distributionReady=false/bound-native-notices-unqualified. Two PS parsers/whitespace checks passed; lychee540OK62unique0errors. Combined collection only, not normalbundle integration/qualification/provider/activation. Fresh independent review pending; no task checkbox closed.
T233 candidate bundle notice attachment implemented in native-artifact.ps1/run-foundation.ps1. Actual synthetic regression terminalexit0 .local/audits/t233-bundle-notices-tests.txt marker CANDIDATE_NOTICE_ATTACHMENT_REPEAT_PRESERVATION_AND_REFUSALS_PASSED, fixture .local/native-bundle-notices-d63614824b374536a6082e393c13ea00. It verifies repeated identical199-file attachment, preserved predecessor bytes, no-preservation refusal and DLL mismatch refusal with prior notices unchanged. Actual sequential normal-entry Debug/Release candidate builds controller75492 terminalexit0 marker CANDIDATE_DEBUG_RELEASE_COMPLETE_NOTICES_AND_NORMAL_BUNDLE_RESTORATION_PASSED; logs .local/audits/t233-notices-{Debug,Release}-build.txt, context .local/native-qualification-c9f06d03379c4f2fbcae382077c5c12c. Both testOnly=false manifests bind DLL17fb5de...; both notice trees contain199files with identical SHA3541077fc18ceacbb0f00ef4db28c5092a1e3138fd433723ad30b80c752de74d. Source snapshot9e6d02de0306f557e800007ec03078b2463c24e62f00057eda6585c44614aeb2 preserved; generated0outputs. Context finished and both prior normal bundles restored=true/exacttreehashes. Three PS parser/whitespace checks passed and lychee540OK62unique0errors; no Flutter source edits. Previous13-phase/nativeUI acceptance remains historical for its earlier source snapshot, not current final qualification. Full qualifier, normal qualified provider, activation and task/stage gates remain open. Fresh review pending; no checkbox closed.
T233 first completed candidate_bundle_notices_review found one confirmedP2: helper excluded native input descendants but not exact .local/native-isar root. Fixed normalized exact-root equality using ordinal case-insensitive comparison; regression now proves refusal before collector directories or attachment receipts are created. Actual corrected full synthetic driver terminalexit0 .local/audits/t233-bundle-notices-fixed-tests.txt marker CANDIDATE_NOTICE_ATTACHMENT_REPEAT_PRESERVATION_AND_REFUSALS_PASSED; fixture .local/native-bundle-notices-17b2071c2dd44d13babec7a1fe62d3da retained. Repeated attachment/predecessor bytes and allthree refusals passed. Three current PS parsers/whitespace and lychee540OK62unique0errors passed. The actual Debug/Release builds above bind their recorded preceding snapshot9e6d02de..., not the subsequent guard correction; no new current full-build or qualification claim. Valid attachment path/repeat behavior is rerun in the corrected synthetic driver; the fix changes only refusal of prohibited input paths. Fresh corrected review pending; full T233 gates remain open.
T233 full current compatibility controller implemented in tools/test-native-isar.ps1 and tools/native-artifact-abi.ps1; fourteen sequential phases, preserved normal bundles and independently hash-bound source/ABI/logs/available phases/notices evidence, explicit compatibility-passed-unreviewed receipt only after source freeze and verified restoration. Actual ABI helper first run terminalexit0 .local/audits/t233-qualifier-abi-first.json validates PE32+x64/93exports/Isar3.3.2/pinnedMDBXtag. Two current PS parsers/whitespace and lychee540OK62unique0errors passed. Full controller runtime now pending; no compatibility/qualification/activation/task closure claim. Frozen inputs will remain unchanged during the invocation; fresh independent review follows applicable completed checks.
T233 full current compatibility controller actual completed invocation8330 terminalexit0: .local/audits/t233-qualifier-current-run.txt ends NATIVE_CANDIDATE_CURRENT_COMPATIBILITY_AND_NORMAL_OUTPUT_RESTORATION_PASSED_REVIEW_REQUIRED. Context .local/native-qualification-3553ea78e7844f078fc99064fba9c5bd has compatibility-receipt.json SHA34815acab4a607329b114cb895b556dbf9c3764807db4623ca44db9ffca8df8b, state compatibility-passed-unreviewed/distributionReady=false/fullAcceptance=false/activated=false. All14phase records passed: ABI93exports/version/PE64, exact rootformat239files0changed (historical work flutter_lints warning retained), rootanalyze/test250, threepackage analyze/tests39protocol/34Windows/85locald, normal Debug/Release with identical199file notices, all13 current available native/UI scenarios, runtime diagnostics. Source352files SHA1524314f1290bd3ddcf31437d8900e44b3346545b0cdd059cfdad71f0da26875 preserved; both normal bundles restored. Independent postcompletion check67362 terminalexit0 rehashed six receipt evidence bindings, all14phase logs and14available evidence files, both retained bundle trees, originalnormal restored digests and current source snapshot. Originalmanual/CI/Q/otheruser/reboot/offline and exact denied operations remain excluded/open. Earlier source-controller review had no findings but did not establish completed runtime; fresh full outcome review pending. Qualifiednormal provider/activation/fullT233/T045/T207/stage closure remain open; no checkbox closed.
T233 compatibility evidence validator added with historical audit/current-source-required separation; shared bundle snapshot helper moved unchanged into its module and provider imports it. First negative driver13268 failed because an early source-comparison variable named matches was overwritten by PowerShell automatic Matches during regex guards; renamed sourceMatches, retained failure evidence in tool output, no protection denial. Corrected full driver48355 terminalexit0 .local/audits/t233-compatibility-validator-fixed-tests.txt marker COMPATIBILITY_HISTORICAL_AUDIT_EIGHT_REFUSALS_AND_ORIGINAL_PRESERVATION_PASSED; bound result .local/audits/native-compatibility-validator-7a54661c3b22491380dd34e1551cb126.json. Real completed receipt remains structurally auditable but currentSourceMatches=false after new tooling; RequireCurrentSource refuses. Seven copied-fixture refusals cover readiness/path/log/phase/source corruption and preserve original receipt. Three current PS parser/whitespace checks passed; normal historical selection and both unchanged bundle helper digests independently checked. Full qualifiednormal selection/activation remain pending; the prior full compatibility invocation binds its recorded352file snapshot and is now historical for the changed source. Fresh review pending; no checkbox closed.
T233 first completed native_compatibility_validator_review found two confirmedP2 structural links missing: available result reference was not compared to bound phase log RESULT marker, and retained native copies/inventory were not directly checked against originalartifact payload/provenance hashes. Both fixed: exactlyoneabsolute matching marker; originalmanifest hash, exact196payload inventory/hash/length, combined notice hash/fullnative aggregate. Corrected full driver82753 terminalexit0 .local/audits/t233-compatibility-validator-coherent-fixed-tests.txt marker COMPATIBILITY_HISTORICAL_AUDIT_ELEVEN_REFUSALS_AND_ORIGINAL_PRESERVATION_PASSED; result .local/audits/native-compatibility-validator-cf856941e38246038fd1d1aee926bae0.json retains ten mutationfixtures plus outdatedsource refusal. Coherent substitutions include actual older completed13phase suite, edited license with rehashed inventory/notice/bundle/receipt records in both copiednormal bundles, and changed copied manifest with rehashed bundle records. Originals preserved; real historical receipt remains auditvalid/currentSourceMatches=false. Three current PS parsers/whitespace passed; fresh lychee below. Fresh corrected review pending; no currentqualification/provider/activation/taskclosure claim.
T233 qualified normal provider/explicit activation implemented: current-source compatibility and exact independent-review approval chain, immutable reviewed qualification receipt, atomic active pointer with preserved predecessor, established marker prevents missing-pointer cache fallback, normal build preflight and qualified notice attachment. No actual activation performed. Actual activation refusal driver terminalexit0 .local/audits/t233-activation-refusal-tests.txt marker NATIVE_ACTIVATION_EIGHT_REFUSALS_NO_CACHE_FALLBACK_AND_STATE_RESTORATION_PASSED, fixture .local/native-activation-tests-f881d99416f7432f971d666f1c73c904; synthetic owned pointers/marker moved into fixture and prior private selection restored. Actual candidate notice regression69772 terminalexit0 .local/audits/t233-activation-candidate-notice-regression.txt marker CANDIDATE_NOTICE_ATTACHMENT_REPEAT_PRESERVATION_AND_REFUSALS_PASSED, fixture .local/native-bundle-notices-81dd3f176b3d421e943e3244627fe3f2; prior bundle preservation/candidate behavior retained. Five current PS parsers/whitespace passed, lychee540OK62unique0errors. Source changed since historical compatibility, so successful activation/current-qualified DebugRelease acceptance still requires new full qualification and completed independent review. Fresh preactivation implementation review pending; T233/stage/no-publication gates remain open.

- [x] T234 Исправить подтверждённое P2 независимого native_current_outcome_review: в contracts/native-artifact.md заменить переходное требование отказа при любом active.json актуальной цепочкой pointer → qualification → current compatibility → independent review; отсутствие pointer допустимо для исторического private input только до первого activation, established marker запрещает fallback. Сохранить completed history. После изменения нормативного контракта выполнить lychee, новую полную current-source qualification T233 и fresh read-only review; прежний прогон не выдавать за qualification изменённого source snapshot. Успешная активация/normal Debug+Release и полная приёмка остаются отдельными gates.
T234: completed fresh native_current_outcome_review found one confirmed P2 contradiction in active-pointer contract; record .local/audits/t234-confirmed-contract-review.json. Qualification session56306 completed exit0 all14 phases, .local/native-qualification-22a65241bb334ab6b8ff9eda48dc5b15/compatibility-receipt.json; independent RequireCurrentSource validation session6959 exit0 before contract edit, receipt SHA e34ac07d4f57bc63b46233cfd962bd859612a7d5c882ad45876d2c1c189a61a2, source SHA e259c85117d8f1457f37141af7217f6684695af2867611de244cd465c62b8083. Contract corrected to one current verified active-pointer rule; refusal-test paragraph distinguishes implementation from positive activation evidence. Lychee .local/audits/t234-contract-fix-links.txt exit0 540OK/62unique/0errors and scoped diff whitespace check exit0. Prior successful qualification is now historical, not approval for changed normative source. New full qualification session68195 live, log .local/audits/t234-current-qualification-contract-fixed.txt; fresh readonly native_contract_fixed_review scope .local/audits/t234-corrected-review-scope.json pending. T234 remains open until checks/review evidence supports closure; T233 activation and qualified normal builds/full stage gates remain open. No publication or denied-operation retry.
T234 fresh native_contract_fixed_review completed: zero findings, source-scope controller/qualified normal provider/activation workflow ready; .local/audits/t234-contract-source-clean-review.json faithfully records currentCompatibilityResultVerified=false and excludes product/manual/CI/actual activation readiness. Live post-fix qualification68195 context .local/native-qualification-4656889443f3494b9f4d59547f10969a; root/protocol/windows checks passed, locald tests running. T234 checkbox stays open pending current complete qualification/outcome review. No activation approval generated.
T234 completed: post-fix current full qualification68195 exit0 all14 phases; receipt .local/native-qualification-4656889443f3494b9f4d59547f10969a/compatibility-receipt.json SHA3ab4ee02c44d74c4212dc0ef0a6c32ab23c3442c2358ff23bdc9c5df0f601d6f/source60c9ba37267657a16bb8978a3a31de664f063e3e9bdcc26eabce54334c953d94. Parent17870 and fresh native_postfix_completed_outcome_review independently validated current receipt, bound evidence/ABI/retained bundles/199notices and both restored original normal trees. Completed review0findings, native-build-only controller/provider/activation workflow ready; faithful record .local/audits/t233-compatibility-clean-review-3ac89444b2e248da905a06019bbc5eee.json excludes distribution/fullAcceptance/actualactivation. Applicable links540OK62unique0errors; contract correction task closed without erasing history. Explicit activation36437 then completed exit0 .local/audits/t233-qualified-activation-3ac89444b2e248da905a06019bbc5eee.txt, qualification-receipt-046fbc8d9e6041628872b3b5db226772.json SHA054be11ad9185e32fe9fa5aea12309cc7c8efdf7806da55d87b31fd2d8a42fa4. Actual output mode reviewed-qualified-native, DLL17fb5deaba528a0627cf5caf4526c6dbce91629e8c4805f05b3b2ffefac7e520/contextnull. Normal Debug/Release acceptance44935 running; T233/T045/T207/fullstage remain open. No publication or denied-operation retry.
T233 actual activated normal builds44935 exit0 Debug+Release logs .local/audits/t233-qualified-normal-3ac89444b2e248da905a06019bbc5eee-{Debug,Release}.txt. Actual acceptance29324 exit0 .local/audits/t233-qualified-normal-acceptance.txt marker QUALIFIED_NORMAL_TWO_BUNDLES_THREE_PROVIDER_AND_BUILD_REFUSALS_AND_STATE_RESTORATION_PASSED; fixture .local/native-activation-acceptance-e6d3fcef3aae431f8873c5afd0a49efa/result.json. Both actualnormal manifests testOnly=false/appRootcorrect/3binaryhashes verified/DLL17fb5d...e520, identical199notices/tree3541077fc18ceacbb0f00ef4db28c5092a1e3138fd433723ad30b80c752de74d. Invalidstate/qualificationhash/missingpointer-aftermarker refused by provider AND normal build preflight; pointer/marker/originalqualified selection and both fullnormalbundle trees preserved/restored. Executed local acceptance script PowerShell parser0errors. Updated docs/development/third-party-notices.md with factual2026-10-13 native graph/source/qualification/activation/bundle checkpoint and explicitly historical old-release unknown provenance; no projectlicense/publication/fullstageclaim. Links .local/audits/t233-activated-notices-links.txt540OK62unique0errors/scopeddiffcheck0. Final fresh activated-increment review pending; T233/T045/T207 remain open until assessment supports closure.
T233/T045/T207 completed after fresh native_activated_increment_final_review:0findings, native-build-only increment and scoped taskclosure supported. Frozen14file scope .local/audits/t233-activated-final-review-scope.json. Reviewer independently GetNativeArtifactBuildSelection exit0 currentcompatibility/ABI/artifact/approval chain reviewed-qualified-native/contextnull, rehashed actualnormal Debug+Release/3binaries/199notices and activepointer/marker against acceptance; source graph not attributed to olddownloaded DLL. Actual currentfullqualification/activation/normalbuilds/postactivation provider+buildrefusals/restoration evidence above; faithful finalreport record .local/audits/t233-activated-increment-clean-review.json. Closure changes only operational task/status documentation; reviewed qualification source inputs unchanged. Full001.1/Q/manual/CI/reboot/otheruser/physicaloffline/deferred criteria remain open, no publication or denied-operation retry. Completed history preserved.
- [x] T235 Дополнить T203/Q07/Q11 фактическим UI-восстановлением после аварии normal locald: acceptance-only UiActor.launchServiceOwner запускает проверенный normal locald с обычными workspace/app-root аргументами и сохраняет собственный kernel handle; после unoccupied SID namespace guard и готовности обоих UI окон завершать только этот child. Новый integration_test/owner_recovery_test.dart и tools/test-foundation-owner-ui.ps1: durable profile/receipt перед kill, прежний owner PID/generation общие двум окнам, unsent draft сохранён без автоэффекта, восстановленные два окна используют один новый generation/owner, сохранённые data/receipt читаются, explicit save и observer update дают по одному результату, closing one сохраняет survivor, fresh reopen подтверждает data/receipt. Обычный server/local API/storage, без injected repository или production kill/fault hooks. Wire отдельный OwnerRecoveryAcceptance build target; существующий fixed13phase aggregate не менять до standalone проверки/review. Root format/analyze/test, windows analyze/test, PS parse/links/whitespace, real compiled UI run в preserved candidate scope и fresh readonly review обязательны. Изменённые qualification source inputs требуют новой current qualification/review/activation перед normal build selection; не обходить current-source guard. Не закрывает reboot/other-user/offline/physical/CI/fullT203/001.1, не повторяет denied операции; сохранить failed fixtures и completed history.
T235 completed after fresh normal_owner_ui_recovery_review:0findings/ready only standalone normal-owner UI recovery. Frozen5files .local/audits/t235-review-scope.json; corrected checks32202 exit0 exactdotformat240/0/rootanalyzeNoissues/root250tests/windowsanalyzeNoissues/windows34tests, twoPSparsers0/specLinks540OK62unique0errors. First analyzer87771 failed2nullable errors; not substituted for corrected source. Actual standalone owner UI54260 exit0 .local/audits/t235-owner-ui-first{,-controller}.txt, context .local/native-qualification-5bd492d4aa8540a78fff6eaa5b0c50c1/sourceb4e6515d4dc5f0ceff4407ecce07d8e8f01d78bc33140321e065e5db34c16f06. Fixture .local/foundation-ui-71391cd677784df4a8d2bac3319db0be/profile/owner-recovery/accepted scenario normal-owner-ui-loss-recovery-reopen/revision3/receipts3. Reviewer independently verified all5hashes/fixture3binaryhashes/testOnlyfalse/DLL17fb...e520/signals with distinct original/recovered/reopen owners and PSparsers; parent65007 separately rehashed both original normal trees restored. Production app.main/bootstrap/native transport/normal locald; owned verified HANDLE kill73, two live windows rehandshake/newsharedgeneration, retained unsent draft/revision1/receipt1 before explicit save, finalrevision3/receipts3, observerexit0/survivor/freshreopen. Controlled integration target does not prove uninstrumented UI/reboot/otheruser/physicaloffline/CI/fullQ07Q11/T203/001.1. Existing13phaseaggregate unchanged. PRIOR nativequalification/activation source60c9...d94 is historical after codechanges; normal build selection must refuse until new current qualification/review/activation, no override/fallback. Exactdeniedoperations notretried. Completed history/brandbook/hardcutover preserved; no publication.

- [x] T236 Включить independently accepted T235 normal-owner UI recovery в fixed available automatic dispatcher и актуализировать controller/compatibility validator/native-artifact contract и текущие инструкции для нового набора. Сохранить строгое связывание результата с ordered phase logs/RESULT marker/source snapshot; current qualification требует полный текущий набор. Исторические canonical13phase receipts остаются inspectable только как историческое evidence, не допускаются для current selection/activation. Проверить retained исторические receipts и negative bindings без повторения denied операций. Выполнить новый full current native qualification с root/all-package checks, Debug/Release, расширенным native/UI набором/runtime diagnostics и точным restoration; fresh readonly review/fixloop, explicit reactivation и обе ordinary normal builds с complete199notices. Не объявлять partial dispatcher за FullAll/CI/manual/full001.1. Не переписывать old immutable qualification/artifact/review records и не разрешать cache fallback.
- [x] T237 Исследовать воспроизводимый SERVICE_UNAVAILABLE в pipe_worker_teardown_child.dart: failed qualification T236/fdb851 и повтор15 из серии подтверждают сбой после WORKER_THREE_IO_ADMITTED, при этом isolated/full Windows rerun проходили. Сохранить все результаты; добавить безопасные boundary diagnostics, установить фактическую причину и исправить подтверждённый дефект без ослабления cancellation/quota/reuse критериев или произвольных sleeps. Проверить targeted regression и Windows package, обязательные Flutter checks/links и fresh readonly review с исправлениями до clean; затем выполнить новый current qualification T236 на неизменном source snapshot. Boundary run25 подтверждает disconnect completed/old client closed/reaccept requested, но отказ до reuse client opened. Fixture должен учитывать асинхронное начало listening: test-only connect retry100→1000ms в пределах5s и accept deadline5s; повторять только SERVICE_UNAVAILABLE, остальные ошибки сохранять. Cancellation/quota/shared disconnect identity/read99/reuse acceptance не ослаблять. Исторический неуспех не заменять успешным повтором и не объявлять причину установленной без evidence.

- [x] T238 Исправить подтверждённый P2 completed native_fourteen_completed_outcome_review в Quickstart: obsolete qualification -Candidate/planned и private-development fallback заменить актуальной цепочкой complete artifact → -Artifact current qualification → completed independent review/approval → explicit activation → ordinary Debug/Release и проверка matching199notices. Уточнить отзыв по source change и отсутствие fallback после first activation, сохранить fullAcceptance/distributionReady=false и отдельные manual/CI/release gates. Исправлять только операционные инструкции, не переписывать immutable qualification/evidence и completed history; lychee/current source+restoration revalidation/fresh readonly review до clean. При unchanged native source snapshot не выдавать doc edit за новый полный прогон.

- [x] T239 Исправить P2 completed native_fourteen_corrected_outcome_review: в qualification/activation последовательности Quickstart обе ordinary Debug/Release команды должны иметь -BuildOnly. Не запускать real-profile UI в build-compatibility проверке; manual launch остаётся в отдельной disposable-user инструкции. Doc-only correction: сохранить native qualification01fc/9bb и предыдущие review/scope/proof records, выполнить lychee и current receipt/source/restoration revalidation, затем fresh readonly review/fixloop до clean. Не создавать approval до завершённого clean report.

T238/T239 completed after fresh readonly native_fourteen_build_only_final_review: no findings; controller/current compatibility, qualified provider and explicit activation workflow ready within native-build-compatibility-only. Current receipt9bb3/source01fc independently verified,17 scope hashes and both original normal trees restored; current-source old13 refused and historical13 inspection preserved. Actual doc checks: t239-build-only-links.txt541OK62unique0errors; t239-build-only-outcome-verification.txt exit0. Both postactivation ordinary build commands use -BuildOnly. Approval342d82d9b4e644689d03e73cc68ca200 was created only after completed clean review. New activation/build/acceptance remain T236 until verified; full001.1/manual/CI/deferred gates stay open.

- [x] T240 Исправить P3 completed native_fourteen_activated_outcome_review: current docs/development/foundation.md не должна утверждать незавершённость уже закрытых T045/T207. Зафиксировать provenance/resolved graph и199 bundled notices выбранного source-built DLL по actual T233/T236 evidence, сохранить distributionReady=false/public release/full001.1 gates. Operational doc correction не меняет qualification source01fc; предыдущие approval/review/evidence immutable. Выполнить lychee/fresh readonly review; после clean обновить approval и explicit activation, поскольку hash foundation.md входит в старый approval scope. Проверить current provider/сохранение firstmarker и прежних actual normal bundle proofs, не выдавать doc change за новую fullqualification.

T236/T240 completed after fresh readonly native_fourteen_documentation_fixed_review:0findings, ready native-build-compatibility-only. Prior activated-outcome review1P3 fixed via T240; all19 reviewed files/source01fc/current receipt9bb/both normal binary+199notice trees independently verified. Actual new approval and activation session29007 completed exit0: t240-current-activation.txt, qualification receiptc6fc4912fc594c8291169860f4b2bb7f SHA4a705b1483eedf088b8931b40ef88c5dc24729e02c51baf175f8a6db0536b276. Actual t240-reactivation-result.json proves successful current provider, preserved first marker and both previously built/tested ordinary normal bundle trees. Doc-only correction did not rerun or relabel full qualification or ordinary builds; previous actual75926/14phase/12negative evidence immutable. Current t240-corrected-links541OK62unique0errors. Full001.1/FullAll/actualCI/manual/reboot/otheruser/offline/physical/release and exactdenied gates remain OPEN. Closure recorded here and .local result; prior review journals retained as historical states.

- [x] T241 [US1] Закрыть automatic gap T039/T201 unsupported API через production LocalApiClient и настоящий owned native pipe: расширить acceptance-only peer в packages/serverdeck_locald/test/support/native_queue_scenarios.dart двумя well-formed hello вариантами apiMajor2/minor0 и major1/apiMinor1 при остальных correct identity/build/generation/nonce. Требовать INCOMPATIBLE, отсутствие authenticate frame/grant/session/ordinary request и неизменные profiles/settings/receipts/storeRevision; bounded disconnect/owned resources cleanup, затем legitimate native client baseline на том же store. Не менять production protocol/API compatibility или выдавать controlled server frame за unsupportedOS/remote/foreignuser. Уникальные proof markers в compiled Channel/harness по existing contracts; root format/analyze/test, affected package checks, actual rebuilt compiled acceptance в preserved candidate context, PS parse/links/fresh readonly review/fixloop до clean. Exact denied operations не выполнять. Новые source inputs требуют последующей current qualification/review/activation перед normal provider selection, без fallback. Основание: completed readonly remaining_security_gate_audit и Local API v1 major1/minor0.

- [x] T242 [US1] Закрыть automatic gap T039/T201 well-formed foreign native schema через actual Workspace.open: existing records_test.dart способ real Isar DB без StoredSettings использовать в packages/serverdeck_locald/test/support/workspace_child.dart либо связанной acceptance-only helper. После закрытия owned original workspace создать foreign DB в отдельном protected owned fixture, заменить только owned database безопасными protected operations и вызвать production Workspace.open. Требовать INCOMPATIBLE не позднее30s, exact inventory/bytes неизменны, no staging/key replacement/writable migration; восстановить только original owned DB и подтвердить прежние workspace identity/state/revisions/credential recovery и normal availability. Не заменять сценарий manifest schema2/malformed pages/direct validateNativeSnapshot, не менять native schema или migration policy. Root format/analyze/test, affected package checks, rebuilt WorkspaceLifecycle acceptance в preserved candidate context, PS parse/links/fresh readonly review/fixloop до clean; historical failed fixtures/proofs сохранять, exact denied operations не повторять. Не закрывает genuine foreignuser/remote/missingVC/unsupportedOS/OS-protection условия. Основание: completed readonly remaining_security_gate_audit, runtime-storage preflight и Q06.

T241 current implementation/check evidence: completed session80918 exit0; .local/audits/t241-checks-and-preserved-acceptance.txt, actual compiled8cases fixture83690c1cdf3446bebc3e1ae8adad712a, context74d6cebb78f34da3a710c5526022c472 sourcea39d. Root mandatory checks and affected package/native checks passed; task remains OPEN for independent review/fixloop. T241/T242 handoff previously clean security_gap_tasks_readiness_review. Fullcurrentqualification/manual/CI/001.1 not claimed.

T241 closed after completed fresh readonly native_api_version_refusal_review:0findings/ready scopedT241. Reviewer checked4frozenhashes/production handshake→actual native incompatible2.0+1.1→zero authenticate/clientwrites/grant/session/effects→canonical populatedstore preservation→healthy baseline, three unique rawmarkers/emptychannelstderr and actualchecks/CoreStorage8. FullT039/T201/001.1/newnormalproviderqualification/manual/CI remainOPEN; exactdeniedoperations untouched.

T242 actual implementation/check evidence: session84567 exit0, root mandatory/affectedpackage2tests/rebuiltWorkspaceLifecycle passed; fixturef4df148b996c42f99f0c9ece2246cdb9, .local/native-qualification-e49c5d5408994f8a834385a40bffeca6 sourceca2a7312b1c6b74467d65fa232c96753a6f62d707c82282be4e05c2dcc63b010, bothactualoriginalbundlehashes restored. Task remainsOPEN pending freshreview/fixloop; fullT039/T201/manual/CI/001.1/normalproviderqualification remainseparate.

T242 closed after completed fresh readonly foreign_native_schema_recovery_review:0findings/ready scopedT242. Reviewer inspected5hashes/fullrequirementchain, actual validforeign4schemas→Workspace.open INCOMPATIBLE≤30s→exactfilepreservation→protected originalrestore/canonicalwholepopulatedstate/actualDPAPIcredentialrecovery; rawcurrentchecks/compiledmarkers/6normal-testbinaryhashes/contextca2a verified. No fullT039/T201/manual/CI/001.1 claim, no retry/bypass/transfer of exactdeniedoperations. Following fullcurrentqualification/checks tracked under existingT208; no newsource change is needed for this closure.

## Phase 7: Convergence

Readonly Spec Kit convergence of current001.1 (not001.2/001.3): converge_security_storage_0011 found0newbuildablegaps; converge_ui_recovery_0011 found2alreadytrackedmanual/environmentgaps and0newsource/drivergaps; converge_runtime_diagnostics_ci_0011 found3HIGH partial harness/CI gaps below. Intent inventory:23unique stageFR,8SC,7stageAC,12Q,7W,8constitutionprinciples; existingcheckboxes/correctivechains assessed as currentbehavior, not completionproof. No new product/architecture requirement is introduced. Current fullqualification1603aa65578949d49629519681725d52 is still running; this assessment does not claim its success. Existinggenuineenvironment/manual/actualCI/fullreview gates and exactdeniedT185/T227/HyperV/cleanup/GitHub403 remainOPEN; futurestage001.2/001.3 not advanced.

- [ ] T243 [HIGH] Добавить исполняемые owned checkpoint/verify маршруты для оставшейся real environment приёмки per FR-SVC-001/004/007/015/016/019, SC-SVC-001/004/005, W07, Q01/Q03/Q05/Q08/Q11 (partial, DCI-001; parents T038/T039/T040/T043/T048/T201/T204/T206/T208). Использовать существующие production bootstrap/LocalApiClient/Workspace и отдельные acceptance-only actors/protected fixture controls; добавить test-only helper/PowerShell driver в tools и packages/serverdeck_locald/test/support, не новые production flags или обход проверки caller image/SID. Конкретные процедуры должны создавать одноразовый синтетический case с verified normal bundle/source binding и сохранять checkpoint оригинальных workspace/profile/credential/receipt/revision/file identities; после настоящего Windows reboot проверять другой OS boot instance и исходные durable results, при настоящем другом OS user проверять его фактическую identity и предусмотренный отказ без изменения исходных данных с working owner baseline, при runtime offline проверять реальные условия блокировки сети и работоспособность normal client/locald. Setup ОС, reboot, переключение пользователя и физический ввод могут оставаться явно внешними шагами в disposable Windows11 environment; driver не выполняет их автоматически и не объявляет состояние достигнутым по одному параметру или process restart. Проверяющий код обязан различать passed/unproven/deferred, сохранять отказные cases и privacy surface scope, работать только с удерживаемыми verified owned handles/paths, без arbitrary PID/cleanup/reset/impersonation в продукте. Нормальный неинструментированный UI и physical Q12 остаются самостоятельной ручной приёмкой, integration target их не заменяет. Actual real-condition acceptance нужна для соответствующих полных gates; отсутствие стенда не причина выдумывать успех. Точные ранее отклонённые операции не повторять, не обходить и не переносить на runners. Mandatory checks/applicable compiled tests/links и fresh readonly review/fixloop; user-server data не использовать.

- [x] T244 [HIGH] Подготовить reproducible cold-runner source-built native artifact pipeline/selection в .github/workflows/foundation.yml и существующих tools native preparation/build/qualification per FR-SVC-001/019, W01/W07, Constitution VIII, contracts/native-artifact.md (partial, DCI-002; parents T044/T206). На чистом checkout проверить закреплённые source/archive/vendor/toolchain/SDK inputs, реально собрать complete artifact с matching notices/provenance и выполнять применимые package/root/build/native проверки именно этого DLL через existing owned candidate qualification context. Не копировать private active pointer/локальные журналы, не выдавать historical-development-cache за source-built acceptance и не формировать фиктивный completed-review/activation record в CI. Сохранить current source/evidence bindings, first-activation no-fallback rule, проверяемый exit status и safe proof; private fixture DB/credential/key/profile dumps не публиковать. Доказательство cold-runner требует actual authorized hosted run текущего reviewed source snapshot и workflow revision; local lint/старый remote desktop-release workflow не закрывают его. T050 публикационные границы сохраняются; без отдельного разрешения snapshot не push/PR/release/merge. CI должен честно отделять available build compatibility от full Windows11/manual/deferred приёмки; final full gate не зелёный до действительных критериев. Подготовить concrete reviewed implementation до запроса недостающего разрешения/среды. Mandatory applicable checks/links и fresh readonly review/fixloop; источник build-only input может оставаться unreviewed-qualified без ложной product distribution.

- [x] T245 [HIGH] Подключить существующий tools/test-foundation-runtime-diagnostics.ps1 к применимому CI build/acceptance gate per FR-123, FR-SVC-016, SC-SVC-004, W05/W07, Constitution VII (partial, DCI-003; parents T044/T206). Использовать такой же явно выбранный complete source-built artifact/candidate scope, что и остальные native/UI проверки; existing native qualifier с mandatory runtime-diagnostics phase допустим вместо дублирующего запуска. Проверять actual compiled fault/render/output result и строгий безопасный proof, propagating failure в соответствующий job; root widget/unit или14available phases сами по себе не заменяют этот driver. Production guard T231 не переписывать без confirmeddefect, не ослаблять markers/privacy scan ради green. Actual authorized CI run/revision/phase evidence нужны для closure hosted portion; сохранять отдельные full/manual/deferred barriers и T050 ограничения. Applicable checks/links/fresh readonly review/fixloop, без повторения exactdeniedoperations.

## Phase 8: Review corrections

- [x] T246 [P3] Синхронизировать текущий Status этого файла с фактическими checkbox после полного `foundation_whole_code_package_review`: T033–T037, T041/T042 и T045–T047 уже завершены; T038–T040, T043–T044 и T048–T050 ещё открыты. Не стирать историю и не закрывать дополнительные acceptance gates этим исправлением. Критерий: вводный статус не направляет исполнителя повторно выполнять закрытые задачи и не объявляет полную001.1/native/manual/CI готовность; успешные links/whitespace checks и завершённое свежее readonly review исправления, scope полного code/package review записан в журнале проверки.

- [x] T247 [HIGH] Закрыть обнаруженный readonly remaining_automatic_acceptance_audit пробел T204/Q05 в диагностике реального credential UI journey (FR-123, FR-SVC-016, SC-SVC-004; parents T040/T204/T206). В tools/test-foundation-credentials-ui.ps1 приватно захватывать все потоки каждого из десяти flutter drive шагов; не выводить исходный текст в parent/CI. После завершения owned client/locald проверять законченные файлы существующим acceptance-only PrivateMarkerScan, связывая password/privateKey PEM и decoded body/passphrase/cancelled secret с текущими synthetic fixtures, а technical receipt key — read-only DPAPI oracle исходного workspace, без экспорта ключа. Проверять принадлежность log paths одноразовому fixture, отсутствие reparse и прежний postclose product scan; не читать запрещённые live DB/lck. Сохранить отдельный safe proof количества/байтов и точных scanned/excluded surfaces только после успешного scan; не выдавать current pre-output step proof за полную Q05. Controlled synthetic leak в captured output обязан безопасно отклонять proof, не публикуя маркер. Выполнить обязательные format/analyze/test, package checks, реальный compiled credential journey/output scan и отрицательный case в owned candidate context с восстановлением normal bundles; links/whitespace и fresh readonly review/fix loop. Не закрывать полный T204/Q05 или denied T227 только этим дополнением; completed history сохранить.

- [x] T248 [HIGH] Закрыть обнаруженный readonly remaining_automatic_acceptance_audit пробел клиентского verifier в T243/Q08 (FR-SVC-001/007/015, SC-SVC-004/005; parents T038/T040/T203/T243). Дополнить существующий owned environment checkpoint acceptance-only проверкой через production bootstrap/LocalApiClient/normal locald исходных публичных profiles/settings/receipts/revisions, сохранив исходные protected credential/file identities и существующий direct Workspace/DPAPI oracle. Зафиксировать checkpoint до остановки и проверять точное равенство ожидаемого public durable state после rehandshake; отсутствие эффекта не заменять появлением имени профиля. После настоящего другого OS boot запускать client verifier вместе с storage oracle и сохранять раздельные safe proofs; same-boot baseline проверяет исполнимость маршрута, но reboot остаётся unproven. Поддержать явные owned paths/held child boundaries, отказ при source/bundle/checkpoint mismatch и сохранение failed fixtures. Новые production test flags, OS reboot/account/firewall changes и обход SID/image проверки не вводить. Обязательные format/analyze/test/package checks, реальный compiled same-boot baseline и отрицательные binding cases, links/whitespace и fresh readonly review/fix loop. Separate Windows11 reboot/other-user/offline/physical и exact denied операции оставить открытыми; полный T243/Q08 этим baseline не закрывать. Выполнять после T247.

- [x] T249 [HIGH] Исправить обнаруженный в hosted run38549681107 таймаут native input expand-rust-rustc (parents T244/T206). Для каждого TAR names/types/extract использовать удерживаемый дочерний процесс с одновременным приватным чтением stdout/stderr, закрытым stdin, ограничением 300 секунд и завершением только своего child tree при отказе. Добавить отдельные safe phase JSON без исходных inventory/error contents. Сохранить pinned archive hashes, предварительный отказ traversal/links/special entries, fresh destinations и failed fixtures; не ослаблять production guards и не переносить exact denied проверки. Проверить dual-stream pipe-pressure, реальный timeout/child termination, безопасный nonzero отказ, существующие archive negatives и настоящую подготовку всех pinned Rust компонентов; подтвердить native build regression и generated source package с PowerShell7.4+ minimum. Обязательные parser/links/whitespace и fresh readonly review/fix loop до публикации; actual hosted completion остаётся самостоятельным доказательством T244 и не заменяется локальными проверками.
- [x] T250 [HIGH] Исправить подтверждённый hosted run38566954396 timeout TAR names для Rust compiler (parents T244/T206). Перевести только кодирование официальных Rust1.88.0 Windows x64 distribution archives с XZ на закреплённые TAR.GZ URLs/SHA256 из официального release manifest; синхронизировать recipe.json/rust-license-material.json, preparation kind и native-artifact contract/Plan. Никакой silent archive/PATH/tool fallback; предыдущие artifacts/cache/evidence не переписывать. Actual checked gzip payloads должны дать тот же полный extracted Rust tree digest и все исходные pinned license bytes. Сохранить T249 bounded owned child и archive guards. Получить новую recipe-bound native build regression/candidate, полный license/corresponding-source package и standalone offline reproduction, parser/links/whitespace и fresh readonly review/fix loop до commit/push. Hosted current-source gate после публикации проверить отдельно; Windows11/exact-denied проверки оставить открытыми.
- [x] T251 [HIGH] Устранить подтверждённый local qualification root-format отказ на длинных nested standalone source fixture paths, сохранив точную обязательную команду dart format --output=none --set-exit-if-changed . (parents T244/T206). Добавить owned completed-source retention tool по closed successful source-test log, фиксированным fixture/source namespaces и завершённым candidate/prepared receipts. Переносить только duplicate source деревья внутри workspace в короткие свежие .local paths; записывать исходные/новые paths, receipt hashes и before/after tree hashes. Не изменять product inputs/DLL/receipts, не удалять данные, не двигать failed/incomplete cases, не менять OS policy/права или exclusions проверки. Exact logged candidate и единственный completed preparation с matching recipe hash обязательны; дополнительный candidate/prepared (включая failed/incomplete attempt) отклоняет весь перенос до record/move. One-shot retention record и partial-state evidence сохранить; incomplete/repeated/ambiguous вызов должен безопасно отказывать. Реальные T249/T250 завершённые fixtures сохранить с независимой повторной проверкой всех четырёх деревьев; подтвердить literal root format. Parser/links/whitespace и fresh readonly review/fixloop; полную current qualification не объявлять по этому format check.
- [x] T252 [HIGH] Локализовать actual hosted run38571647321 qualification serverdeck_windows-tests отказ, не публикуя приватный тестовый лог (parents T244/T245/T206). Дополнить root/three-package test commands supported pinned SDK file-reporter JSON, оставляя все streams/reporter файлы приватными. После actual failure экспортировать только bounded safe projection: phase/current source+artifact binding, known current source files/valid declaration/frame lines, ограниченные whitelisted OS/safe StateError codes. Не экспортировать names/assertions/raw stack/outputs/private paths или secrets; controlled failure fixtures явно отличать от реальной qualification. Missing/malformed/incomplete reporter не обозначать passed; сохранить original test nonzero и fullAcceptance/distributionReady/activated=false. Upload allowlist расширить только safe-test-failure-*.json. Реальный controlled failed reporter/private-marker exclusion+invalid input, actual root/package supported reporter checks, parser/links/whitespace и fresh readonly review/fixloop; затем actual authorized hosted run для получения cause и дальнейшего исправления. Никаких Win11/exact-denied операций или обхода production guards.

T252 продолжение по hosted38580654334 на 7a3e8a0: safe reporter complete/failed указывает на owner/DACL comparisons в security.dart:286 и kernel_security.dart:42. Реальный native descriptor roundtrip в памяти подтвердил, что корректные SID Administrator/SYSTEM сериализуются как LA/SY и не совпадают с literal SID prefix. Исправить общий validator в packages/serverdeck_windows/lib/security.dart и его использование в kernel_security.dart: фактический и оба допустимых порядка ожидаемого owner/protected DACL сравниваются в каноническом формате одного Windows converter. Сохранить точный SID, два ACE, flags и существующие FA/mutex/pipe masks; не принимать дополнительные grants, чужого owner, unprotected/null DACL или иной mask. Добавить in-memory native descriptor regressions для обычного и alias SID и перечисленных отказов, без изменения OS ACL/token/privileges. После завершения текущего frozen qualification применить исправление, выполнить обязательные root Flutter checks, Windows/package checks, links и fresh readonly review/fixloop, опубликовать reviewed source и проверить следующий hosted result. Черновые in-memory проверки не закрывают product/current qualification или T252.

T252 продолжение по hosted38589096049 на b3ffe13: alias-related mutex/pipe/file ACL отказы исчезли; остались пять paths_test cases, которые создают parent через Directory.systemTemp, но передают настоящий LOCALAPPDATA как разрешённый root. requireSafePath корректно отвергает fixture вне этого root. Сделать synthetic local root этих native primitive tests явно равным нормализованному SystemTemp, сохранив прежние owned-temp guards, все native операции/ACL/refusal/cleanup assertions и отдельный ambient LOCALAPPDATA lexical case. Не менять production path validator, не перенаправлять окружение глобально, не ослаблять fixed-volume/UNC/reparse/containment guards. Добавить pure regression отказа при temp location вне объявленного root на том же и другом диске. Проверки root format/analyze/test и Windows analyze/test, links/whitespace, fresh readonly review/fixloop перед публикацией; unchanged production/locald tests не повторять без нового основания. Hosted подтверждение T252 пока открыто.

T252 продолжение по hosted38593531861 на 5f2bc65: Windows tests прошли; единственный reporter failure — workspace_init_test.dart:11, без child source frames. Передавать nonzero workspace child failure с его приватным stderr stack в error reporter, чтобы existing known-source projection могла назвать реальную строку причины. Capture максимум64KiB, поток полностью дренируется без роста captured buffer; raw streams/report не публикуются. Явные test-only WORKSPACE_CHILD_FAILED/TIMEOUT допустимы в safe projection, unchanged90s child deadline и bounded5s stderr drain; owned process cleanup и original failing outcome сохраняются. Проверить unchanged positive workspace VM route, real controlled child-code reporters/private-marker exclusion, root format/analyze/test, locald analyze/targeted test, PS parsers/links/whitespace и fresh readonly review/fixloop перед публикацией. Это диагностика, не закрытие причины hosted failure; T252/current CI/full gates остаются открытыми.
- T252 review correction: the private stderr reader now owns an explicit subscription and shares one drain Future/deadline across failure and cleanup. Completion/timeout cancels the subscription; controlled unterminated-stream and bounded-prefix tests verify no post-cleanup forwarding or second wait. Repeat mandatory checks and fresh independent review before publication; actual hosted failure cause remains open.

T252 continuation hosted38602085721/68b1658: actual WORKSPACE_CHILD_FAILED identifies only state_store_child.dart:31. A real controlled Dart reporter proves normalized relative frame paths were omitted by URI-only parsing. Accept package-relative Dart frame tokens with either separator only through existing known-source/hash/valid-line validation; controlled real reporters must exclude unknown/private paths and invalid lines. This closes a diagnostic gap, not the unknown workspace assertion cause. PS parsers/real controlled regressions/links/diff/fresh readonly review before publication; T252/full gates remain open.

T208 partial documentation reconciliation: README dispatcher count corrected to14; developer guide and verification journal record actual68b1658 full available local qualification, current-source receipt validation before6464 sync and restored bundle hashes. Source-bound local compatibility is not6464 qualification/activation, hosted acceptance or Windows11/fullQ completion. T208 and all unmet parent gates remain open; check links and complete fresh readonly documentation review before commit.

T252 hosted38608458146/6464b01 actual safe failure now locates workspace_child.dart:405: direct comparison of Link.targetSync() text with the originally requested target path. The fixture must first prove both directories resolve to the same target and retain the OS-reported junction target before Workspace.open; after the expected STORAGE_BLOCKED refusal require exact equality with that retained report, plus existing link type, marker bytes and target/inventory assertions. This tests preservation independently of OS target spelling without relaxing production reparse guards. Required root format/analyze/test and real workspace VM regression, links/diff and fresh readonly review remain pending after deletion of local pinned SDK/evidence. Do not claim the hosted cause fixed until actual rerun passes.

T252 local checks after shared SDK update: H:/flutter/flutter now pinned Flutter3.47.7/Dart3.13.5/revisionabaf9c5, existing SDK updated in place without new project SDK/native copies. Locked root/three-package pub get repaired deleted-SDK package_config references. Parent18952 exit0: root format/analyze/253tests, locald analyze, links541/0 and diff0; final literal root format rerun after the ignored tiny junction probe. Real controlled junction probe proves requested forward-slash spelling differs from the OS-reported target while both resolve to the same directory and the captured report remains unchanged. Evidence runner-artifacts/junction-fix/. This does not run the full Workspace VM regression: its complete native artifact was removed, and actual hosted rerun remains required. Fresh independent review pending; T252 remains open.

T252 hosted38614007679/3f6353f progressed past the original junction assertion and failed at workspace_reparse_scenarios.dart:354, the same requested-path versus OS-target comparison in the persisted junction setup. Apply canonical destination preconditions and exact captured OS-target preservation to both persisted directory junctions and analogous file symlink cases; keep actual native refusal, protection-call counts, complete inventory/byte hashes and healthy recovery assertions. No production guard changes or native artifact restoration. Repeat mandatory checks and fresh readonly review before publication; actual hosted Workspace regression/full gates remain open.

T252 hosted38618862005/2cdf787: package/root tests and both normal bundles reached
available-native-ui; no package test-failure report was produced, and runtime
 diagnostics was not entered. The failure is now inside the available dispatcher,
but published artifacts omit the failed child phase. Attach the fixed phase to
the private ErrorRecord and project only known phase/current source+artifact
bindings/up to3 hash-validated valid PowerShell source frames to a fixed safe JSON.
Do not publish raw error/output/stack/path fields or claim success from missing
metadata. Controlled real ErrorRecord privacy/unknown-phase/changed-source cases,
PowerShell parser/links/whitespace and fresh readonly review are required before
publishing. T252/T244/T245/full/manual gates remain open until actual proof.

T252 hosted38626791516/266841b failed at normal-prerequisites,
test-foundation-prerequisites.ps1:54, copying a hand-maintained Flutter support
filename. The safe report does not identify which optional filename was absent.
Copy the entire actual verified normal bundle for healthy-owner, validate all
copied entries/hashes before changing appRoot, and keep negative-case layouts
unchanged. Controlled complete bundle cases with optional native_assets.json
present/absent and an extra runtime file, nested assets, refusal/preservation of
nonempty/overlapping destinations; PS parse/links/diff and fresh readonly review
before publication. This does not prove the full healthy owner or resolve all
hosted failures; T252/T244/T245/manual/full gates remain open.

T252 prerequisite-copy review correction: trim ending directory separators on both absolute paths before equality/ancestor/descendant validation. Real controlled cases use existing empty nested destinations, both containment directions and every trailing-separator combination; require the overlap refusal and unchanged full source inventory/file hashes. Prior first review P2 must be followed by repeated checks and a fresh completed review.

T244/T245/T252 hosted closure: run [38635056439](https://github.com/unng-lab/serverdeck/actions/runs/38635056439) on reviewed60d8d3d completed cold source build/current qualification and artifact upload successfully. Final validated hosted proof binds source81a3c6fcb695ff7768fbe0d01772ffaa5174606b8ee68eae45f770df1badf6d4, manifestee48d19a0d361fc2bde137767a0fc4dcbb71445d051184077cce222ab8f777cc and receiptf718a2326bc69c25b3c3af59e0de661a0cccd274d5ec97a46f8ab2f31013ed30. It proves root/three-package suites, Debug/Release,14available phases and separate compiled runtimeDiagnostics through the final receipt validator, not merely started-phase JSON. Current closure changes only docs/evidence/tasks, not the qualified source inputs. Proof/API metadata and limits: [journal](../../docs/development/foundation-verification.md#hosted-compatibility-2026-10-15). The first prerequisite-copy review P2 was fixed, controlled tests passed and fresh prerequisite_complete_bundle_fixed_review completed with0findings. Fresh closure review follows mandatory links/diff checks. Overall job failure is the unchanged Acceptance remains incomplete barrier; all full/manual/Windows11/exact-denied gates and T208 dependency remainOPEN. No activation/distribution/PR/release/merge. Private hosted receipt/logs were not downloaded; public proof identifies runner-validated hashes without claiming independent local rehash of those private files.

T244/T245/T252 closed after completed fresh readonly hosted_automatic_closure_review:0findings/ready scoped automatic closure. Reviewer independently queried actual terminal run38635056439, byte-compared retained/downloaded safe proof, inspected requirement/contract/source/validator chain and unchanged full/manual barriers. Actual lychee543OK/0errors and diffcheck0; no private receipt/log rehash or full001.1 readiness claim. Historical completed tasks retained; T208 dependency and all remaining specified gates remainOPEN.


## Поправка 2026-10-30: встроенный движок в существующей основе

История T001–T252 сохраняется. Следующие задачи не выполнены. Старые открытые
native/integration/manual gates не запускать в текущем scope, не отмечать пройденными;
они не критерий выполнения этой поправки. Прошлая приёмка не переносится на engine.
Работать в согласованной кодовой базе, не менять worktree/процессы/установку003.

### Setup and foundational phase

- [x] T253 Зафиксировать разрешённые full static/unit/widget suites и отделить native cases по фактическим side effects в tools/test-unit.ps1, packages/*/test/ и .github/workflows/unit.yml, сохранив старые tests без skip-as-success; запретить native/integration/SSH/container/manual dispatch в scope поправки (FR-SVC-EMB-12/13).
- [x] T254 Вынести нейтральные platform ports и opaque host authority в packages/serverdeck_engine/lib/platform/ports.dart и lib/hosting/authority.dart: lease только после native close, vault locked/denied/corrupt не missing, owner capability не сериализуется (FR-SVC-EMB-02/03/05).
- [x] T255 Перенести profiles/credentials/storage/remote/automation/mcp из packages/serverdeck_locald/lib/ в packages/serverdeck_engine/lib/ с прежними validation/CAS/schema3/limits и без Flutter/Windows imports; прежний root удалён, без переходной оболочки (FR-SVC-EMB-02/12).
- [x] T256 Реализовать Windows ports в packages/serverdeck_windows/lib/engine_platform.dart, отделить UserProtection interface и store runtime от Windows imports в engine, сохранить SID/DPAPI entropy/ACL/mutex/retained identity и pinned Isar ABI (FR-SVC-EMB-03/05).

### US1 — одно приложение, lifecycle и ownership

Goal: app владеет engine; independent tests AC-SVC-EMB-01/02/03 через fakes/widgets.

- [x] T257 [US1] Реализовать EngineHost/EngineGateway в packages/serverdeck_engine/lib/hosting/engine_host.dart и in_process_gateway.dart: один store/writer, Ready после recovery, 64 pending/session и 256 суммарно с RESOURCE_LIMIT; сохранить прежние более строгие limits (FR-SVC-EMB-01/02/03).
- [x] T258 [US1] Перевести lib/bootstrap/ и lib/app.dart на host-owned owner gateway, сохранить DTO/controllers/readiness/CAS/receipt outcomes и presentation003; UI не открывает Isar/SSH, IPC owner token наружу отсутствует (FR-SVC-EMB-01/02). Обязателен один trusted engine worker и private Dart-port gateway по embedded-engine#engine-worker-and-ui-proxy-composition: никаких blocking native/hash calls в Flutter isolate, shared Timeline deadlines и physical settlement/close ack; lib/bootstrap/engine_worker.dart и engine_gateway.dart.
- [x] T259 [US1] Реализовать tray/menu lifecycle и fallback «Выйти»/«Остаться» в lib/platform/desktop_lifecycle.dart и lib/shell/; close окна сохраняет app/MCP, explicit exit закрывает admission сразу, drain10s, CloseBlocked удерживает lease, suspend/resume меняет fence (FR-SVC-EMB-04/09).
- [x] T260 [US1] Реализовать общий sampler/target fence и secondary-instance activation-only в packages/serverdeck_engine/lib/remote/observations.dart и hosting/instance_owner.dart; один sampler на существующую profile/revision binding и readKind, один writer на remote host, old responses/revoked rights не публикуются (FR-SVC-EMB-03/09).
- [x] T261 [US1] Добавить unit parity/ownership/late-response/close-failure tests в packages/serverdeck_engine/test/ и unit lifecycle/bootstrap tests в test/embedded_host_test.dart, включая tray absent, два окна/два MCP/second process, startup30s, два SSH transports и прежние лимиты (SC-SVC-EMB-01, AC-SVC-EMB-01/02/03). Включить RAM worker/channel/clock tests для trusted binding, mailbox stop barrier, original deadlines/queued-timeout capacity, late reply/close ack и lost-worker CloseBlocked без нового worker/store; native/UI/design тесты запрещены.

### US2 — целевые данные без compatibility

Goal: нынешние данные не теряются; independent tests AC-SVC-EMB-04/05/06.

- [x] T262 [US2] Реализовать adoption без schema bump в packages/serverdeck_engine/lib/storage/workspace.dart: тот же default path/mutex, schema3 preflight, только exact schema3, без legacy upgrade, busy/wrong owner/unknown schema/vault failure без reset/kill/параллельного writer (FR-SVC-EMB-05/06).
- [x] T263 [US2] Добавить synthetic record-family/blobs/IDs/revisions/grants/enrollment/history roundtrip и fault tests в packages/serverdeck_engine/test/storage/adoption_test.dart; runtime sessions/одноразовые permits не воскресают, CloseBlocked не освобождает lease (SC-SVC-EMB-02, AC-SVC-EMB-04/05).
- [x] T264 [US2] Описать и отобразить target-schema3-only, INCOMPATIBLE/writer-busy в docs/development/embedded-engine-storage.md и lib/shell/recovery_view.dart; без snapshot overwrite/downmigration и удаления старых данных (AC-SVC-EMB-06, FR-SVC-EMB-06).

### US3 — MCP и remote jobs

Goal: parity tools/rights и честный outcome; independent tests AC-SVC-EMB-07/08/09.

- [x] T265 [US3] Изменить packages/serverdeck_windows/lib/mcp_build_bundle.dart, discovery.dart и engine IPC host на verified app identity, новый embedded-v1 discovery descriptor без изменения closed-field format3 handshake; сохранить retained peer/ACL/challenge/proof/publication gate (FR-SVC-EMB-07/09).
- [x] T266 [US3] Перевести packages/serverdeck_mcp/lib/src/bootstrap.dart и local_gateway.dart на connection-only app bridge, absent app SERVICE_UNAVAILABLE≤5s, без autolaunch/reconnect после proof/effect; сохранить grants/custody/tool catalog021 (FR-SVC-EMB-07).
- [x] T267 [US3] Сохранить intent-before-submit и recovery неизвестных remote attempts в packages/serverdeck_engine/lib/automation/jobs.dart и job_session.dart; observer overlay attached/detached/stale не schema4; lost ACK/missing remote attempt не освобождают occupancy и не replay apply (FR-SVC-EMB-08/09).
- [x] T268 [US3] Добавить full unit permission/tool parity suite в packages/serverdeck_mcp/test/embedded_gateway_test.dart и packages/serverdeck_engine/test/automation/observer_recovery_test.dart: expired/revoked grants, owner forgery, target fence, lost ACK, restart, missing attempt, duplicate terminal и явный reconcile/cancel (SC-SVC-EMB-03/04, AC-SVC-EMB-07/08/09).

### US4 — переносимая граница, без ложного platform support

Goal: capabilities соответствуют реальности; independent tests AC-SVC-EMB-10/11/12.

- [x] T269 [US4] Реализовать EngineCapabilities/fake lifecycle-vault adapters и import-boundary unit checks в packages/serverdeck_engine/lib/hosting/capability_snapshot.dart и test/platform_contract_test.dart: engine без Flutter/Windows, не-Windows без транзитивного Windows FFI, mobile foregroundOnly, Web directSsh=false (FR-SVC-EMB-10/11, SC-SVC-EMB-05).
- [x] T270 [US4] Обновить platform status/prerequisites и future adapter handoff в README.md и docs/development/platform-capabilities.md по embedded-platforms contract, без реализации/деплоя backend, без объявления Linux/macOS/mobile поддержанными; это граница для отдельных последующих поставок (AC-SVC-EMB-10/11/12).

### Cross-cutting completion

- [x] T271 Обновить production/dev bundle manifests и startup scripts в tools/ и .github/workflows/ для app+Isar+встроенный MCP без locald, сохранив pinned runtime/notices/prerequisites и exact app peer identity; не устанавливать/не публиковать сборку и не запускать native dispatch (FR-SVC-EMB-01/12/13).
- [x] T272 Выполнить применимые format/analyze/full unit/link checks по quickstart, затем независимый read-only review/fix loop AGENTS.md; записать команды/scope/exit codes/непроверенные native сценарии в docs/development/embedded-engine-verification.md; не переносить старые галочки в новую приёмку (FR-SVC-EMB-12/13).

### Dependencies, parallel work and implementation strategy

T253→T254→T255→T256→T257. US1 T258–T260 после T257; T261 после всех US1 changes.
US2 T262 после T256/257, T263→T264; US3 T265→T266 после T257 и доверенного host,
T267 после T262, T268 после T265–T267. US4 T269 после T254/255, T270 после T269.
T271 после US1–US3, T272 после всех. MVP: extraction+Windows US1/US2/US3;
US4 фиксирует portability boundary, реальные другие OS не входят в этот MVP.
Не менять reviewed files во время review. Открытая параллельная работа003 не часть
этой очереди; перед implementation брать актуальную согласованную базу без её сброса.
Параллельно после общих prerequisites допустимы US1 widget tests и US2 synthetic
fixtures в разных файлах; US3 bridge tests и US4 capability docs. Production shared
files изменять последовательно; [P] не назначен задачам с общими dependencies.

### Traceability действующей поправки

| Requirements | Решение/контракт | Tasks | Acceptance |
| --- | --- | --- | --- |
| FR-SVC-EMB-01/02 | plan ownership; embedded-engine | T254–T258,T271 | AC-SVC-EMB-01/10, SC-SVC-EMB-01 |
| FR-SVC-EMB-03 | embedded-engine ownership/limits | T256/257/260/261 | AC-SVC-EMB-01/03 |
| FR-SVC-EMB-04 | embedded-engine lifecycle | T259/261 | AC-SVC-EMB-02/03 |
| FR-SVC-EMB-05/06 | embedded-migration, data-model | T262–T264 | AC-SVC-EMB-04/05/06, SC-SVC-EMB-02 |
| FR-SVC-EMB-07 | 021 embedded-host MCP | T265/266/268 | AC-SVC-EMB-07, SC-SVC-EMB-03 |
| FR-SVC-EMB-08/09 | 021 embedded-host jobs, engine event fence | T260/267/268 | AC-SVC-EMB-08/09, SC-SVC-EMB-04 |
| FR-SVC-EMB-10/11 | embedded-platforms | T269/270 | AC-SVC-EMB-10/11/12, SC-SVC-EMB-05 |
| FR-SVC-EMB-12/13 | plan phases, quickstart | T253/271/272 | все перечисленные AC, scope evidence |

### Исправление независимого ревью 2026-10-30

Первое completed review выявило P2: новый общий watch не имел topic/cursor/buffer
контракта. Решение — удалить новый streaming API, сохранить прежние typed methods,
bounded operation handles и polling. История задач не меняется; добавлена регрессия:

- [x] T273 Реализовать/проверить parity существующих typed snapshot/poll2s и observations start/status/cancel в packages/serverdeck_engine/test/hosting/gateway_parity_test.dart и lib/bootstrap/engine_gateway.dart, без общего watch/topic stream; использовать прежние DTO/operation/cursor bounds, cancellation interest не cancel remote job (FR-SVC-EMB-02/03/09, AC-SVC-EMB-01/08/09).

T273 зависит от T257/T258/T260, выполняется до T261/T268/T272. Дополняет traceability
FR-SVC-EMB-02/03/09. Всего в embedded-поправке21 открытая implementation задача;
US1 получает дополнительную T273. Это спецификационное исправление, тест не выполнен.

### Уточнение пользователя: один executable и полноценный tray

- [x] T274 Реализовать dispatch serverdeck.exe --mcp-stdio --grant-id UUID в lib/main.dart, packages/serverdeck_mcp/lib/entry.dart и windows/runner/main.cpp: headless engine/унаследованный stdio, без окна/tray/store/owner authority; перенести прежний bin entry без отдельного mcp.exe; unit argument/dispatch/EOF/ownership tests в test/entry_mode_test.dart (FR-SVC-EMB-01/07, AC-SVC-EMB-13).
- [x] T275 Реализовать и проверить полное tray menu «Открыть ServerDeck»/«Серверы»/«Настройки»/readiness/MCP count/«Выход» в lib/platform/desktop_lifecycle.dart и test/tray_menu_test.dart; keyboard/mouse callbacks, restore existing window, no second host, safe status, unavailable tray fallback и общий shutdown (FR-SVC-EMB-04, AC-SVC-EMB-14).

T274 зависит от T257/T265/T266 и выполняется до T271. T275 дополняет T259 и
выполняется до T261. Manifest4 исключает ОБА mcp.exe/locald.exe; app identity
одинакова в UI/MCP mode, поэтому только внутренний owner capability и MCP-only
IPC endpoint определяют полномочия. T265/T268 обязаны проверять невозможность
owner IPC из того же image. Всего23 implementation задачи T253–T275.

### Удаление всей заменённой архитектуры в этом же scope

- [x] T276 Удалить packages/serverdeck_locald и standalone packages/serverdeck_mcp/bin после переноса используемой логики; удалить старые lib/bootstrap IPC clients, неиспользуемые protocol/Windows legacy parsers/entry/verifiers/schema1/2 upgrade/rollback helpers, их tests/fixtures/build scripts/workflows. Обновить root и package manifests/locks, docs текущего запуска, test fixtures/imports и test/security/component_boundary_test.dart на единственный engine/MCP mode. Не оставлять re-export/deprecated/fallback facades; сохранить и перепривязать проверки действующих функций, прав, trust и unknown recovery (FR-SVC-EMB-14/15, AC-SVC-EMB-15).

T276 обязателен после T255–T275 и до финальной T272/review. Никакой отдельной
будущей cleanup-задачи: без удаления старой архитектуры вся поправка не завершена.
T262/T263/T264 теперь проверяют только exact schema3/отказ legacy без записи;
previous migration/return acceptance заменён прямым уточнением пользователя.
Всего24 открытые задачи T253–T276, новые требования14/15 покрыты T262–264/T276/T272.

### T253: проверенное основание реализации — 2026-10-30

T253 закрыта только в scope разрешённых full suites и split native case. Перенос
MCP custody и target manifest — частичный прогресс T254/T255/T262, не закрытие
этих задач. Checked source и результаты в
[implementation evidence](../../docs/development/embedded-engine-verification.md).
Завершённый independent `engine_foundation_code_review`:0 findings; допускает
продолжение реализации, не утверждает готовность всего engine/app/release.

### Указание пользователя: заменить весь прежний набор тестов

- [x] T277 Удалить все прежние собственные test/fixtures/harness и старый coverage/design test pipeline из main checkout; оставить только новые unit tests этой задачи в root/test и packages/serverdeck_engine/test и других целевых пакетах по мере переноса. Переписать tools/test-unit.ps1 и .github/workflows/unit.yml на полные текущие unit suites без design/widget/native/disposable fixtures. Обновить ссылки/инструкции и проверить, что старые результаты не выданы за текущую приёмку. Не менять чужой003 worktree и vendored third_party; generated ignored caches не являются test source. Нормальное поведение/отказы/границы новой архитектуры должны проверяться новыми units (FR-SVC-EMB-12/13/15).

T277 выполняется сейчас и обязателен до финальной T272. Ранее закрытая T253 сохраняет
историю своей редакции, но старый scope7448/coverage больше не текущая политика.
T261/T268/T273/T274/T275 реализуются только как unit tests, без widget/design suites.

### Независимое review unit reset / authority — 2026-10-30

- [x] T278 Исправить три подтверждённых замечания unit_reset_authority_review: поздний физический отказ runtime proof необратимо закрывает authority/gate и все owner capabilities после логического timeout (unit с двумя owners и восстановлением provider); удалить оставшийся собственный checkpoint/environment/MCP client harness и исключить из source snapshot; пометить прежний coverage gate021/T213 superseded без ложного completion. Полный текущий unit/static/link run и fresh independent review обязательны перед закрытием T277/T278. T254–T276 этим не закрываются.

- [x] T279 Исправить подтверждённый P2 unit_reset_authority_review_2: bindOwner учитывает монотонный срок от начала до публикации capability, включая синхронно затянувшийся provider и задержанный timer; elapsed>=5s возвращает TIMEOUT без новой owner session. Unit с управляемыми часами на точной границе5s и после неё; прежний owner остаётся доступен, повторное открытие не наследует просроченную выдачу. Полный unit/static/link run и fresh independent review.


T277/T278/T279 завершены после полного unit/static/link run и completed independent
`unit_reset_authority_review_3`:0 findings, scoped increment готов для продолжения.
Фактический scope: root2 + engine18 units, format0changes, Flutter/all-package
analysis без ошибок; lychee1462total1461OK0errors1excluded. Hosted/native/build
не запускались. Ignored generated caches не являются test source; их удаление
ранее отклонено автоматической проверкой. T254–T276 остаются открытыми; готовность
всего embedded app/release не установлена.


### T254 и перенос pure domain T255 — 2026-10-30

T254 закрыта в границах нейтральных ports/opaque HostAuthority после completed
unit_reset_authority_review_3 и полного unit/static/link run. Windows adapters
(T256), production Host (T257) и вся T255 этим не закрыты.

Частичный T255: исходники automation/compiler, profile_diff, job_session,
profiles/validation и remote/observations, ssh_transport, ssh_reads, ssh_executor
перемещены из locald/lib в engine/lib. Старые файлы удалены, re-export/facade нет;
все потребители импортируют engine напрямую. DartSSH2 pinned4.1.0 теперь dependency
engine, прежняя прямая locald dependency удалена. Поведение/лимиты переносимого
transport сохранены:2 shared slots, connect15s, read30s,4 channels/transport,
physical completion отдельно от logical cancellation. Новые units этой задачи
проверяют reservation/drain, typed endpoint/journal filters, compiler baseline/
qualification отказ, immutable snapshots, bounded deterministic diff и CAS input.
Реальные SSH/native/process/UI операции не запускаются. Storage/auth/services
остаются работой T255 и последующих задач; целиком T255 пока не закрыта.

Completed independent `portable_domain_extraction_review`, fork_turns=none,
read-only:0 findings; данный перенос готов для продолжения T255, не закрывает её.
Reviewer сравнил все8 файлов с git HEAD (только4 комментария изменены),9 consumers
(imports/formatting only), manifests/locks,8 новых unit cases и контрактную цепочку.
Фактический full unit/static/link/locked-dependency scope зафиксирован в
[implementation evidence](../../docs/development/embedded-engine-verification.md).
T255 и последующие implementation задачи остаются открытыми.

### T255: target-only models и graph — 2026-10-30

Ещё8 файлов перенесены из locald/lib в engine/lib: storage/{models,host_trust_models},
automation/{snapshot,configuration,authority_commands,job_commands,plan_commands,
profile_commands}. Старые source paths удалены, re-export/facade нет. Engine model
имеет только schema3 factory/empty, trust-aware receipt/profile parsing; прежние
schema1 factory и trusted-selector удалены. Graph loader принимает HostTrustState,
plans только schema3, schema2 load/selector отсутствует. IDs/blobs/revisions/
reference/history limits сохраняются. Команды остаются captured intent, не authority.

Текущие consumers перепривязаны напрямую. Оставшиеся старые native loaders в locald
больше не получают старый engine parser: их foundation также проходит строгий3
model/trust gate. Они подлежат удалению с остальной legacy архитектурой T276;
сам native/store opener и Windows custody ещё не перенесены. Физический отказ
до writable open и сохранность всех record families относятся к T262/T263, ими
не объявляется этот логический increment.

Добавлены7 units target foundation/trust/grant graph +2 command boundary units.
Synthetic RAM-only data, без Isar/DPAPI/SSH/process/widget/design. T255 остаётся
открытой; готовность всего app/release не установлена. Mandatory full checks и
completed independent review необходимы до завершения increment.

Completed independent `schema3_domain_extraction_review`, fork_turns=none,
read-only:0 findings; проверенный increment готов для продолжения T255. Reviewer
сравнил8 sources с HEAD,21 consumer и9 новых units/contract chain. Strict3 models
и graph сохранили прежнюю schema3 семантику; старые parser branches не доступны.
Full checks: root2+engine35passed, format325/0changes, Flutter/allpackage analysis
noissues; lychee1463total1462OK0errors1excluded. Native/store/tray/release не
проверены, T255/T262/T263/T276 остаются открытыми.

### T255: custody и подготовка mutations — 2026-10-30

Ещё6 sources перенесены из locald/lib в engine/lib: storage/{key_custody,
credential_validation}, credentials/provider, profiles/{service,settings_service,
host_trust}. Старые files удалены, re-export/facade нет. У custody удалены schema1
manifest helpers, единственный create/verifyWorkspaceManifest — exact3. Wrapper/
credential payload format1, entropy и HMAC не меняются: это целевые schema3 данные,
не поддержка старого workspace. OS-user gate остаётся обязанностью provider и
проверки owner SID у workspace, строка SID сама не создаёт native proof.

У ProfileService один prepare(HostTrustState,...) и PreparedMutation с trust map;
legacy prepare/schema1 и trusted selector удалены, внутренняя подготовка использует
private record. Coordinator/consumers импортируют engine напрямую. Остальные старые
coordinator/store/bootstrap modes ещё подлежат удалению T276; T255 не закрыта.

Новые7 pure units проверяют reopened receipt HMAC/canonicalization/close, credential
entropy/ID bindings, owner gate, manifest3 refusal, buffers cleanup, keep/replace/
remove, trust confirm/cosmetic/connection invalidation, settings CAS/delete и vault
failure без нового состояния. MemoryProtection — RAM-only token stub, без OS/
encryption claims. Receipt addition в unit setup не доказывает transaction/authority.
Mandatory full checks и completed independent review требуются до завершения increment.

Completed independent `custody_preparation_extraction_review`, fork_turns=none,
read-only:0 findings; текущий custody/preparation increment готов для продолжения
T255. Reviewer сравнил6sources сHEAD,12consumers,7units и target coordinator chain;
подтвердил сохранение bytes/entropy/HMAC/zeroing и прежней schema3 mutation semantics.
Fullchecks44units(root2+engine42), format326/0changes, Flutter/allpackageanalysis
noissues; lychee1463total1462OK0errors1excluded. Native/Isar/DPAPI/SSH/UI/build/CI
не запускались; T255/T256/T262/T263/T276 остаются открытыми.

### T255/T256/T265: shared bundle4 foundation — 2026-10-30

В рамках prerequisite Windows extraction (до полного T257/IPC T265) добавлены:
EmbeddedBuildManifest exact4/schema3 с closedfields/16KiB/immutable hashes и только
serverdeck.exe/libisar.dll/optional executor-release.json; EmbeddedBuildBundle с
actualartifact hashing/retained application peer без filename role, same-exe MCP
config, sticky refusal и private verified executor binding. RetainedProcessIdentity
сделан final, чтобы внешний Dart implementation не мог подменить native identity.
VerifiedExecutorRelease вынесен в engine port; прежнее public Windows определение
удалено без re-export,4consumers импортируют neutral contract напрямую.

WindowsNativeStoreRuntime в engine_platform.dart реализует initialize/revalidate
pinned Isar3.3.2/downloadfalse, требует именно current-process proof ТОГО ЖЕ bundle,
rejects testOnly, сохраняет sticky loading/failure/identity. Не открывает DB, не
закрывает lease, DLL живёт до process exit. Реальная DLL не загружалась для проверки;
другие Windows ports/новый Host/MCP IPC ещё не реализованы. Existing standalone
runtime остаётся pending T276, новая сборка ещё не переключена на manifest4.

Добавлены7 новых protocol units manifest4 (exact files/version/types/bounds,
immutability, Unicode/safe errors/testOnly); native verifier/runtime проверяются
статически и независимым review, не actual OS acceptance. T255/T256/T265/T271/T276
не закрываются этим foundation increment. Locks/Windows Isar runtime dependency
обновлены на тот же repository-owned ABI. Полный unit/static/link/locked dependency
run и completed independent review обязательны до завершения increment.

Completed independent `embedded_bundle_runtime_foundation_review`, fork_turns=none,
read-only:0 findings; текущий foundation/Windows contracts готовы для продолжения
T255/T256/T257/T265. Reviewer проверил source/Isar initialization API/4consumers/
locks/7units/contractchain и логи51units, static/links/lockeddeps. Реальные native
проверки не выполнял. T255/T256/T265/T271/T276 остаются открытыми; cutover, Host/IPC,
packaging и actual DLL/runtime readiness этим increment не установлены.

### T255/T256: storage ports и MCP credential artifacts — 2026-10-30

Добавлены WindowsProtectedFiles (canonical paths/ACL/no reparses/atomic retained
rename), WindowsWorkspaceLease (тот же namespace/genuine worker/acquire attempt) и
Windows vault factory с ManagedVault. Neutral ProtectedFiles дополнен kind/size/
one-level streamed children и replace flag. Vault disposal прекращает intake сразу,
ждёт physical return и wipes late output; mutable caller-owned buffers обязательны.
MutexLease sealed/мониторит exit, старые wrong-thread native test hooks и два relay
удалены; прочие legacy production hooks остаются работой T276.

McpCredentialFiles перемещён из Windows в engine/credentials без facade; IO только
через ProtectedFiles. Сохранены fixed layout, bindings/blob/lookup, read-onlybridge,
stage-before-publish, atomic pending→rename→readback, recovery/refusal и пределы
4096files/4096dirs/32MiB/128KiBheadroom. Windows MCP file-probe source удалён.
Четыре native construction sites inject WindowsProtectedFiles; все imports/type
consumers обновлены напрямую. Engine path1.9.1 direct dependency, locks обновлены.

Новые8units: managed vault physicaldrain/latewipe/ownerloss/status/reentrantclose;
MCP artifact stage/read-only/publish/revoke/idempotency/atomicfailure/inertpending/
recovery/space/inventory/owner/quota. Providers RAM-only, без FS/DPAPI/Isar/SSH/UI.
T255/T256/T262/T265/T276 не закрыты: полный store/auth/VerifiedRuntime+gate/Host
ещё не перенесены. Mandatory full checks/links/lockeddeps и independentreview
increment необходимы, native/platform qualification не заявляется.

### Исправление storage_ports_artifacts_review

- [x] T280 Исправить подтверждённый P2: MutexLease теряет isHeld непосредственно на native worker onExit, независимо от ожидания cleanup status/timeout5s. Cleanup result остаётся отдельной ответственностью close/CloseBlocked; publication gate отвергает уже потерянную acquisition и poison-ит generation при потере активного worker. Добавить unit consumer-level проверки отзыва owners при observed writer loss без освобождения cleanup ownership. Полный unit/static/link run и fresh independent review обязательны; native delivery этим unit не объявляется проверенной.


T280 завершена после fullunit/static/link run и completed independent
`storage_ports_artifacts_review_2`:0 findings. Reviewer подтвердил непосредственный
onExit→isHeld=false независимо от cleanup status, gate loss handling и preserved
artifact semantics/consumer wiring. Фактический scope60units(root2/engine51/protocol7),
format332/0changes, analysisroot+5packages noissues, lychee1463total1462OK0errors1excluded.
Native/platform/Host/tray/IPC qualification не установлена. T255/T256/T262/T265/T276
по-прежнему открыты; главная цель не завершена.


### T255/T262: target3 native metadata extraction — 2026-10-30

В engine/storage перемещены records/automation_records/host_trust_records с тремя
неизменёнными generated parts, native_registry/native_schema/native_close/native_failure.
Старые source paths удалены, consumers используют прямые engine imports без facade.
Единственный полный workspaceSchemas содержит16коллекций; WorkspaceRecords.fromState
сохраняет target3 row payloads и IDs. Удалены schema1/2 registry recognizers, selectors
и record constructors. Structural preflight распознаёт только target3 pinned MDBX.
Это проверка каталога/_info/геометрии, НЕ semantic row proof до writable open.
T255/T262/T263/T276 остаются открытыми: legacy store/migration controllers ещё
подлежат удалению, native repository и startup cutover не завершены.

Добавлены8units на literal metadata и synthetic in-memory pages: target registry,
отказ prior subsets, closed property/index/field semantics, corruption precedence,
immutable input, malformed geometry/unsupported format, incomplete meta, reused
catalogue nodes, schema3 singleton rows. Ни DB/FFI/OS/SSH/widget/design, ни build
не запускались. Полные unit/static/link checks и independent review требуются
для приёмки этого increment; результаты фиксируются ниже после выполнения.


Target3 metadata increment проверен: tools/test-unit.ps1 exit0
(.local/embedded-native-schema-full.log): format333files0changes, analyze root и
всех5packages noissues, root2+engine59+protocol7=68units passed. Windows/locald/MCP
тестов нет, test pass им не приписан. Первый полный run выявил только unused import,
он удалён, затем весь runner повторён успешно. Lychee exit0:1463total1462OK0errors
1excluded (.local/embedded-native-schema-links.log); root+5packages locked offline
pubget exit0 (.local/embedded-native-schema-locked-deps.log). Generated parts byte
unchanged против source inventory и HEAD, scoped diffcheck exit0.
Completed independent read-only native_schema_extraction_review:0findings,
перенос готов для продолжения T255/T262. Semantic preflight/native repository,
Host/tray/MCP cutover и удаление всех legacy controllers остаются незавершёнными.
Общая цель не завершена; native/platform/release readiness не заявляется.


### T255/T262/T276: schema3 row capture and upgrade-controller deletion

В engine добавлены workspace_rows/isar_rows/workspace_snapshot: sole schema3,
borrowed coherent16collection read, bounded count+read equality, fixed active/empty
creation paths, protected-files/lease ports, graph/custody/artifact validation и
committed lookup recovery. StoredRow хранит прежние IDs и exact payloads без migration
alias. Все consumers переведены на прямой engine API и IsarRowSource. Bootstrap/store/
discovery используют WorkspaceLease/WindowsWorkspaceLease; native abandoned metadata
сохранено на Windows adapter, engine не использует его как доказательство integrity.

Удалены четыре неиспользуемых runtime source: workspace_migration,
trusted_source_preflight, migration_journal и прежний combined trusted_snapshot;
source2/upgrade-target/preflight/digest branches не перенесены в engine. Удалены
ссылки на reservation несуществующего controller. Legacy foundation parser/helpers
и старые store modes ещё остаются работой T276, не объявляются очищенными целиком.
T255/T256/T257/T262/T263/T276 не закрыты; startup read-only semantic preflight ещё
обязателен и не заменяется loader уже открытого source с lookup recovery.

Новые7units используют RAM-only Files/Protection/RowSource/Lease и target3fixture
нынешней задачи: coherent capture all16, exact IDs/payloads/trust/grant history,
count bounds/incomplete view, singleton/duplicates/schema refusal, invalid rows
каждой из10automation families, writer/owner/custody failures без publication,
empty-stage/path/file gates. Общие данные и RAM doubles вынесены из двух новых
unit suites в test/support без старого harness, native/FS/SSH/UI или design tests.
Полный unit/static/link run и completed independent review обязательны ниже.


Row capture increment завершил проверки: tools/test-unit.ps1 exit0
(.local/embedded-row-source-checked.log), format335files0changes, root и все5packages
analyze noissues; root2+engine66+protocol7=75units passed. Для locald/MCP/Windows
tests отсутствуют и test pass не приписан. Первые полные прогоны нашли ошибки
consumer wiring/types/imports и typo в новом test getter; исправлены, targeted7
прошли, затем полный runner прошёл заново. Lychee exit0:1463total1462OK0errors
1excluded (.local/embedded-row-source-links.log); scoped git diffcheck exit0.
Новых dependencies нет. Completed independent read-only
workspace_snapshot_extraction_review:0findings, increment готов для продолжения
storage extraction. Native/DB/FS/DPAPI/mutex/SSH/UI/build/install не запускались.
T255/T256/T257/T262/T263/T276 и общая цель остаются открытыми; полный native
semantic preflight перед writable open и Host/cutover/tray ещё обязательны.


### T255/T276: single schema3 store and foundation queue

StateStore имеет единственный open/snapshot/commitFoundation/MCP-grant/profile-write
путь schema3; _AutomationFormat и оба nullable snapshot selectors удалены. Workspace
содержит только прежний target3 open/create; удалены schema1 creation/read-key/
commit, schema2 open/views/commit branches, foundation_snapshot/migration_rows/
operational_foundation_writes, неиспользуемый legacy bootstrap и initialization probe.
Сохранён live-job foundation identity fence. Старый LocaldEnvironment удалён,
LocaldArguments пока обслуживает единственный фактический format3 standalone entry.
Из старого native runtime удалены format1/2 loaders и verifier re-export.

MutationCoordinator имеет один schema3 constructor и trust queue; отдельный subclass,
legacy/operational modes и mode flags удалены. Все consumers прямо используют
новые имена без alias/facade. Сохранены custody proof, shared32 admission, HMAC
idempotency, receipt lifetime, native target/gate ownership и claim finish paths.
Typed native adapters/старые router classes пока остаются работой Host/cutover/T276,
не объявляются удалёнными целиком и не являются новым in-process owner interface.

Из native writer в engine/storage/row_plan.dart перенесён pure планировщик
retainRowIdentities: exact bytes при semantic equality, IDs обновляемых rows,
выделение после maximum входного snapshot, int64 overflow с отказом до commit, immutable
sorted result. Caller по-прежнему обязан проверить CAS/graph/custody и выполнить
native transaction/readback; row plan не выдаёт authority и не делает commit.
Четыре новых unit cases проверяют эти invariants, singleton IDs и corrupt/duplicate
raw inputs без DB/Windows/FS/UI. Engine extraction/native readonly semantic preflight
и полная реализация Host ещё не завершены; T255/T256/T257/T262/T263/T276 открыты.

Executor enrollment record.format1 и целевой sidecar.format2 — отдельные документы,
не schema1 workspace. Существующий sidecar.format1 read fallback замечен и остаётся
обязательным удалением/contract update T276; отсутствие legacy целиком не заявляется.
Mandatory full unit/static/link run и independent review increment фиксируются ниже.


### Исправление single_schema_store_review

Completed read-only review нашёл1P2: новый текст обещал глобальный never-reuse
nativeIDs, тогда как прежний schema3 planner использует maximum входного snapshot.
Исправлена область гарантии: surviving rows сохраняют IDs; новые получают ID выше
maximum до этого плана, включая удаляемые им строки; после предшествующего удаления
ID может встретиться вновь. NativeIDs не business identity/API references.
Это correction documentation overclaim, не изменение прежнего allocation и не
основание для нового persisted counter/schema bump. Код и4unit cases не менялись.
Остальных подтверждённых findings в completed review не найдено. Full checks и
fresh independent review обязательны перед принятием increment.


- [x] T281 Закрыть подтверждённый P2 single_schema_store_review: ограничить новый контракт/evidence nativeID allocation maximum входного snapshot (с удаляемыми этим планом rows), сохранить IDs surviving entities и int64 exhaustion refusal; не обещать lifetime never-reuse/новый persisted counter. Повторить applicable checks и completed fresh independent review всего increment; это не закрывает T255/T262/T276.


T281 завершена после повторного full runner tools/test-unit.ps1 exit0
(.local/target-only-store-review-fix.log): format332files0changes, root+5packages
analyze noissues, root2+engine70+protocol7=79units passed. Для locald/MCP/Windows
tests отсутствуют и test pass не заявлен. Lychee exit0:1463total1462OK0errors
1excluded (.local/target-only-store-review-fix-links.log); scoped diffcheck exit0.
Completed fresh independent read-only single_schema_store_review_2:0findings,
все42позиции текущего increment проверены; прежний P2 documentation overclaim закрыт.
Код allocation не изменён ради нового требования. Native/runtime/read-onlysemantic
preflight/полныйHost/tray/IPC/release acceptance не установлены. T255/T256/T257/
T262/T263/T276 и общая цель всё ещё открыты; отдельная новая feature не создавалась.


### T255/T276: executor sidecar engine port, exact outer format2

ExecutorEnrollmentStore в engine/storage/executor_enrollments.dart владеет
neutral parser/HMAC/replay/atomic publish/readback через ProtectedFiles,
WorkspaceLease и KeyCustody. Native StateStore содержит один lazily bound instance,
прямые calls через прежний shared32 writer tail; та же queue используется jobs
startup/progress, без alias или второй очереди. Структурированный capsule captures
UUID/method/input/digest и привязан к issuer; это не owner/target authority.
Actual owner adapter по-прежнему удерживает native gate/proof до physical completion.

Удалён outer sidecar.format1 read fallback: принимается только exact format2 с
обязательными receipts. Неподдержанный/foreign/corrupt файл остаётся нетронутым,
ошибка STORAGE_BLOCKED, без conversion/reset/missing fallback. Inner enrollment
record.format1, purpose executor-enrollments-v1 и mutation-v1 HMAC bytes/bindings
не менялись: это собственные форматы целевого payload, не schema1 workspace.
Existing target-format2 bindings/receipts/IDs/digests/createdAt сохраняются;
replay после revoke возвращает historical ACK без восстановления binding/effect.
Существующая запись T178 о readable format1 описывает прежнюю реализацию и больше
не является действующим требованием. Контракт021 executor-enrollment изменён на месте,
obsolete production-migrator/original.isar clauses удалены, новой feature нет.

Read-only absent read не создаёт файл. Missing/unsafe parents, lost owner/lease,
closed key, malformed/cross-workspace metadata и uncertain replacement/readback
закрывают admission и propagates poison к StateStore; lease не освобождается.
NOT_READY при overlapping physical operation не снимается caller timeout, пока
actual work не завершён. При лимите250records/10000receipts/64MiB нет eviction,
existing receipt replay разрешён, новый effect не публикуется.

7новых RAM-only unit cases: confirm/no-change/revoke/restart/stable ACK, immutable
issuer-bound capsule, schema/field refusal unchanged bytes, MAC/key/workspace/
duplicate corruption, capacity/replay, pre/post-commit/readback faults, owner/lease/
path/closed-key loss и timed-out physical read occupancy. Без FS/native/SSH/UI/design.
Native store/Host/MCP/tray cutover/semantic preflight ещё не завершены;
T255/T256/T257/T262/T263/T276 и общая цель остаются открытыми. Применимые full checks
и independent review этого increment фиксируются после фактического выполнения.


Executor enrollment port прошёл full tools/test-unit.ps1 exit0
(.local/executor-enrollment-port-checked.log): format334files0changes, analyze root
и всех5packages noissues, root2+engine77+protocol7=86units passed. Locald/MCP/Windows
tests отсутствуют и test pass не приписан. Первый full run нашёл wiring issues
sharedqueue/extensionfield, исправлены; следующий full выявил неверное fixture
подписания double2.0 строгим signer, заменено rawJSON для негативного теста.
После targeted7passed весь runner повторён успешно. Lychee exit0:1463total1462OK
0errors1excluded (.local/executor-enrollment-port-links.log); exactscopeddiffcheckexit0.
Completed independent read-only executor_enrollment_port_review:0findings;
перенос готов для продолжения T255/T276. Вендор/foreign003 не менялись,
native/FS/DPAPI/mutex/Isar/SSH/UI/Host/tray/IPC/build/install не запускались.
Открытые T255/T256/T257/T262/T263/T276 и общая цель этим не закрыты.


### T255/T256/T276: repository and workspace move into engine

15используемых sources перенесены из locald в engine: StateStore/Workspace,
workspace_creation/foundation_writes, все automation/grant/write/read parts,
executor_metadata_writes и mcp/grants. Старые paths удалены, consumers импортируют
реализацию напрямую. Engine не импортирует Windows/locald/dart:ffi/dart:io.
Storage получает ProtectedFiles/WorkspaceLease/NativeStoreRuntime; fixed default
layout, schema3/format3, 16generatedcollections, transaction flags, shared32tail,
CAS/HMAC/receipts/nativeIDs/opaque credential bindings сохранены.

Native core initialize/revalidate и filesystem операции проходят через существующие
порты. Проверки current owner/slot/root/lease повторяются вокруг async границ.
Native writeTxn и последующий snapshot/readback имеют до/после runtime revalidation;
ошибка после возможного commit блокирует admission, не превращается в ложный
RESOURCE_LIMIT/rollback proof. Close не требует здорового runtime и удерживает
reservation при неподтверждённом native close. Creation inventory streamed/bounded4,
не listSync; существующий stage получает exact native structural preflight до open.
Это НЕ semantic preflight всех rows до writable open: T262/T263 ещё обязательны.

Удалены standalone locald bin, TrustedLocaldBootstrap/entry/LocaldArguments/native
runtime loaders, discovery wrapper/publisher, old idle/grace lifecycle и grant
native test hook/probe. Никакой временный format3 NativeStoreRuntime adapter или
facade не добавлен. Остались legacy native typed services/router/Windows helpers
и UI bootstrap clients/build scripts — их удаление и новый in-process Host/MCP/tray
ещё впереди в этом же scope. Текущий UI ещё не подключён к engine; запуск приложения
после удаления старого entry не заявляется работоспособным до нового Host/cutover.

Locald больше не объявляет directIsar/generator/build_runner, их runtime/dev
ответственность принадлежит engine; offline resolver обновил только locald lock.
Новые6unit cases используют RAM Files/Protection/Lease и stub NativeStoreRuntime;
единственный затронутый Isar API — чистая VM getInstance map. Isar.open/core/DLL/
FS/Windows/DPAPI/SSH/UI не запускались. Проверены preopen runtime failure, retained
reservation при caller timeout/physical pending init, second writer refusal,
unsupported schema/malformed bytes unchanged, owner/slot/lease/path refusal без
keyreset, legacy residue и inert fresh stage при pre-native runtime failure.
Ни positive native adoption, ни полный writer/lifecycle, ни T255/T256/T257/T262/
T263/T276, ни общая цель этим не объявляются выполненными. Full checks/review ниже.


Repository port завершил full tools/test-unit.ps1 exit0
(.local/native-store-port-full.log): format325files0changes, root+5packages analyze
noissues, root2+engine83+protocol7=92units passed. Locald/MCP/Windows tests отсутствуют,
test pass не приписан. Первый fullrun нашёл unused runtime field; поле привязано
к actual native write/readback proof, весь runner повторён успешно. Lychee exit0:
1463total1462OK0errors1excluded (.local/native-store-port-links.log); root+5packages
locked offline pubget exit0 (.local/native-store-port-locked-deps.log); scoped
Gitdiffcheckexit0. Три generated parts побайтово неизменны поSHA256 inventory.
Completed independent read-only native_store_port_review:0findings, все60позиций
scope проверены; reviewer дополнительно сам пересчитал3generatedSHA. Перенос готов
для продолжения T255/T256/T276. Positive native open/adoption, полная semantic
preflight до writable open, новыйHost/UI/MCP/tray/cutover не проверены/не завершены.
Текущий UI после удаления old entry не объявляется запускаемым. Все названные
открытые задачи и главная цель остаются активными, новой feature нет.


### T262: native byte semantic preflight implementation

NativeWorkspaceRows читает exact schema3 pinned MDBX/Isar rows из bounded bytes:
integer IDs, string object offsets/UTF8, branch/overflow/counters/page ownership,
unique entityId hash index, GC/free-list bounds/disjointness. Public metadata-only
wrapper удалён, нет fallback старого schema/native layout. Pure Dart xxh3:1.2.0
добавлен как direct runtime dependency для существующего native index encoding.
Native/recipe archives SHA256 подтверждены, 11прочитанных Rust/C files побайтово
сверены с pinned zip entries; build/vendor sources не изменены и не запускались.

preflightWorkspace проводит полный graph/custody/MCP artifact и executor sidecar
read-only gate ДО Isar.open. После open inspectWorkspaceSnapshot+exact row comparison
предшествуют lookup recovery. Existing creation stage проверяется byte/initial graph
до native open и сравнивается после; freshly absent workspace создаётся как прежде.
Основной readWorkspaceSnapshot после mutations по-прежнему выполняет committed
lookup recovery; новый inspect entry всегда read-only, никакой role/mode от wire.

Новые12units покрывают bounded binary extraction/immutable16families, raw ID/bytes
readback и delayedlookup, numeric branch IDs и independent literal hello XXH3vector,
overflow и malformed pointers/UTF8, hash/id/index mismatch/reusedpage, GC overlap/
range/count, ambiguous equal meta/out-of-range txn, logical badrows beforepublish,
optional/unsupported sidecar и safe provider errors. Literal registry fixture
вынесен из нынешнего native_schema unit suite, не восстановлены прежние тесты.
Все fixtures построены в RAM без native writer/DB/FS/SSH/UI/design.
T262/T263 не закрыты: окончательная Host composition/whole-family positive/fault
acceptance ещё нужны; actual native qualification не выполняется по scope.
Full unit/static/link/locked-deps checks и completed independent review ниже.


### Confirmed readonly meta review fixes

- [x] T282 Исправить подтверждённый P2 native_semantic_preflight_review: exact pinned steady signature UINT64_MAX вместо допуска любого sign кроме0/1; исправить fixtures и добавить отрицательные signature cases.
- [x] T283 Исправить подтверждённый P2 native_semantic_preflight_review: проверить pinned x64 lower/upper/now geometry до native open без native normalization/fallback; исправить fixtures и добавить range/order/next-vs-now refusal с нулевыми writes.
- [x] T284 Исправить подтверждённый P2 native_semantic_preflight_review: отказаться от equal complete positive transaction IDs даже при одинаковых trees согласно normal native meta clash; fixtures distinct txn3/4/5 с page/tree modified3; добавить sameview clash case. Для T282–T284 повторить full applicable checks и completed fresh independent review.

Первый независимый read-only review выявил3P2; исходные104passing RAM units
повторяли ошибочные meta допущения и не доказывали native validity. Исправления
реализованы с3новыми units (15cases в native_semantic_preflight suite); финальные
checks и свежий review фиксируются после завершения. T262/T263 остаются открыты.


- [x] T285 Закрыть подтверждённый P2 native_semantic_meta_fix_review: передавать pinned transaction ancestry limits для tree root, branch child и leaf overflow до native open;3новых RAM regressions проверяют отказ при parent3/page4/meta5, unchanged input bytes и нулевые protected writes. Повторить full checks и fresh independent review.

Второй completed review подтвердил fixes T282–T284 и выявил1новый P2: общий
предел selectedtxn не заменяет root/tree/parent front. Исправлена передача front
по pinned page-get/tree-search/cursor; обратная совместимость не добавлена.


- [x] T286 Закрыть подтверждённый P2 native_semantic_ancestry_review: committed branch минимум2nodes и чётный upper у branch/leaf согласно pinned page-get;3RAM regressions single-child branch/odd leaf upper/odd branch upper через preflight с unchanged bytes/нулевыми writes. Повторить full checks и fresh completed independent review.

Третий completed review подтвердил T282–T285 и выявил1P2 с2page invariants;
110passing units не доказывали отказ этих malformed pages. Исправления и3новых
RAM cases реализованы; проверки и новый completed review ещё обязательны.


- [x] T287 Закрыть подтверждённый P2 native_semantic_page_review: GC N_BIG dsize>4 согласно FREE_DBI minimum; inline empty PNL4 остаётся допустимым. Добавить RAM preflight regression с unchanged bytes/no writes, повторить checks и fresh review.
- [x] T288 Закрыть подтверждённый P2 native_semantic_page_review: принять GC overwrite extent с1reserve page сверх minimum без ослабления range/uniqueness/counters/free-list overlap; positive RAM fixture и отрицательные truncated/outofrange/overlap/extrareserve cases. Повторить full checks и completed fresh independent review.

Четвёртый completed review:2P2 GC min overflow и ошибочный refusal допустимого
GC reserve. T282–T286 подтверждены;113units предшествовали этим fixes. Реализованы
GC-specific bounds без смены layout. Новые6RAM cases: inlineempty vs malformed
overflow4; valid8196byte PNL/2048freepages с1spare;4extent faults. Первый targeted
run обнаружил чрезмерно padded synthetic GC value при слишком малом snapshot;
fixture исправлен на2048реальных RAM freepages в рамках64MiB и прежнего value cap,
производственный cap не ослаблен. Полный targeted suite27cases завершён успешно.


### Completed readonly semantic gate review loop

После всех fixes tools/test-unit.ps1 exit0 (.local/native-semantic-gc-full.log):
format329files0changes, Flutter root и5packages analysis clean; root2+engine110+
protocol7=119units passed. Для locald/MCP/Windows test pass не заявлен. Lychee
exit0 (.local/native-semantic-gc-links.log):1463total1462OK0errors1excluded. Root+
5packages lockedoffline --enforce-lockfile pubget exit0 для неизменённых dependency
locks; scopedgitdiffcheckexit0.3generatedschema parts SHA256 не изменились.

Completed fresh independent read-only native_semantic_gc_review:0findings,
bounded increment готов для продолжения T262/T263. Reviewer проверил весь scoped
reader/open/snapshot/creation flow, fixtures/tests, dependencies и контракт по
pinned source; fixes T282–T288 подтверждены. История предыдущих3+1+1+2P2 сохранена.
Все обязательные findings данного increment закрыты; T262/T263/Host/UI/MCP/tray
cutover и общая цель остаются открытыми. Native/FS/DPAPI/SSH/UI/build qualification
не запускалась;119RAM units не объявляются доказательством native compatibility.


### T255/T256/T257: target publication ordering port

TargetChanges и opaque TargetChangeLease/ReconciledTargetChangeLease реализованы
в engine/hosting/target_changes.dart вместо прежнего locald part. Старый файл
удалён без facade. Native Windows gate/acquisition/lease напрямую реализуют
нейтральные ports; registry callbacks остаются у actual session owner и не выдают
permissions. Обновлены actual consumers/retirement logic; obsolete registry
native observation hook удалён. Shared16 physical charge, own-acquisition settled
вместо global polling, sticky failure, authority-effect/lease close drain сохраняют
ownership до физического завершения. Native/store lease не освобождается здесь.

10новых RAM-only units покрывают normal/reconciled retirement, immutable affected
IDs, shared16 limit afterlogicaltimeout, independent cleanup handles, timelyerror
с physical drain, close duringeffect/release, observerfail, lateacquiredeadline,
retirement/releasefailure. Нет Windows/native/FS/UI/design/integration tests.
T255/T256/T257/T260/T276 и общая цель ещё открыты: old sessions/native peer/server
classes, Host/UI/MCP/traycutover остаются обязательными. Checks/review ниже.


Target ordering port checks completed: tools/test-unit.ps1 exit0
(.local/target-fence-port-full.log), format330files0changes, root+5analysis clean,
root2+engine120+protocol7=129units passed. Locald/MCP/Windows tests отсутствуют,
pass не заявлен. Lychee exit0 (.local/target-fence-port-links.log):1463total1462OK
0errors1excluded; scopedgitdiffcheckexit0. Completed independent read-only
target_fence_port_review:0findings, перенос готов для продолжения T255/T256/T257.
Reviewer сопоставил весь scope с preincrement snapshot и проверил контрактную
цепочку, actual callback policy, cleanup/admission/limits. Открытые T255/T256/T257/
T260/T276 и общая цель не закрываются; новый Host/session/MCP/traycutover обязателен.
Native/platform/release qualification не выполнялась, runnable UI не заявлен.


### T255/T276: remove retired local API branches

Удалены10obsoletefiles: api/auth/channel/diagnostics/sessions/server,
api/operational_server/operational_channel/owner_foundation, owner_service_probe
и storage/migration_probe. Из сохранившихся частей удалены Operational handshake/
sessions/context/authority/openfailure/owner adapters, schema2 catalog/router/tool
entries и private factories, способные связывать прежние native generations.
26existing sources затронуты, net1952lines removed; никаких facade/aliases/new
format fallback не добавлено. Текущий native target branch и его protocol DTO
версии сохраняются, это не изменение DB schema или grant/HMAC binding.

Compile-time hooks старых native test harnesses удалены; старые tests/fixtures
не восстановлены. Новые source-text mirror tests не добавлялись: это удаление
неиспользуемых ветвей, полноценные units текущей задачи сохранены. Firstfullrun
нашёл unused errors import в удалённом branch context, import удалён. Repeatfull
runner exit0 .local/session-prune-full.log: format320/0changes, root+5analyses
clean; root2+engine120+protocol7=129units passed. Native runtime test pass не заявлен.
Review сравнивает со .local/session-cutover-before.json и exact26file inventory
.local/session-prune-review-files.json. Links/independent review ещё обязательны.
T255/T256/T257/T258/T265/T266/T276 и общая цель остаются открытыми: portable owner
capability/session/Host и app/MCP/tray ещё нужны, runnable UI не заявляется.


Completed retired_session_branches_review (independent/read-only):0findings,
удаление готово для продолжения T255/T276. Reviewer сопоставил все26исходников
с preincrement snapshot, import graph/roots и target composition. Подтверждены
сохранность target native3 proof/HMAC/grant/admission/limits/lateguards, отсутствие
forwarding facade/fallback, неизменные DTO версии. Applicable checks: full runner
exit0 format320/0changes, root+5analysis clean,129units; links exit0 1463total/
1462OK/0errors/1excluded; scopeddiffcheckexit0. T255/T276 и общая цель не закрыты:
portable sessions/owner/Host/UI/MCP/tray и remaining Windows/bootstrap/build
paths ещё обязательны. Нет native/platform/release acceptance или runnable UI claim.


### T255/T256/T257/T265/T276: portable sessions and actual service extraction

40remaining source files moved directly locald/lib→engine/lib (map in
.local/engine-sessions-moves.json); old source paths have no facades or exports.
EngineSessions/OwnerSession bind real HostAuthority capabilities, external handshake
and string admission are MCP-only. Owner wire dispatch removed from MCP server.
Host runtime+peer owner/root/build are checked across proof awaits; physical proof
observers preserve16pending charge and close drain after interest completion.
Existing8total/4MCP/60s/5s limits and all custody/CAS/job/observer/target services
remain; package imports are platform-neutral. Windows EmbeddedBuildBundle directly
implements VerifiedAppConfiguration; VerifiedMcpChannel native adapter remains open.

9new RAM-only units cover owner capability/string forgery, foreign authority and
duplicate registry, pending/repeated owner detach,16physical charges and close,
lease expiry, MCP HMAC/token capture, forged owner handshake, changed peer identity,
4MCP/8total caps. Full .local/engine-sessions-unit-full.log exit0: format322/0changes,
root+5analysis clean, root2+engine129+protocol7=138units passed. Earlier source-port
fullruns found unused _begin and handshake import; removed and fullrerun succeeded.
Native/platform/native-store/UI/FS/SSH/build qualification not performed.

An attempted guarded recursive removal of the now-source-empty locald package
and generated caches was rejected by automatic approval review: blocked by policy.
It was not retried via another mechanism. Old package configuration/cache cleanup
remains; current source root has zero Dart files. No claim all legacy paths are gone.
T255/T256/T257/T258/T265/T266/T276 and goal remain open until full composition and
cutover; link checks and independent review of this increment remain mandatory.


- [x] T289 Исправить подтверждённый P2 engine_sessions_port_review: expiry до openOwner capacity, safe Future errors и stop recheck aftercallbacks; добавить RAM all8expired/mixedlive-expired-pending/callbackfailure-stop regressions. Повторить checks и completed fresh review.
- [x] T290 Исправить подтверждённый P2 engine_sessions_port_review: общий physical proof tracking для grant-open/root/terminal helpers, cap4openwork до worker/key/finalphase/lateproof drain; aggregate256 acrossretired requests. Добавить RAM helper-timeout/complete/close и256retired-bound regressions; повторить checks и completed fresh review.

Первый completed engine_sessions_port_review:2P2 expirycapacity и3untrackedhelper
paths;138passingunits предшествовали fixes. Реализованы sharedtrackedhelper,
expiry-beforecapacity и retainedcharges/drain.5новых RAM cases вместе с прежними9
покрывают обе ошибки и явный256aggregatecap по уже отключённым records. Direct
MCP grant/terminal backend cases не симулируются native store; их полной приёмкой
T268 эти tests не объявляются. Full checks/fresh review ещё обязательны.


- [x] T291 Закрыть подтверждённый P2 engine_sessions_fix_review: MCP operation-context late-phase drain удерживает runtime→channel→runtime как один physical chain, зарегистрированный до первого await; fixed-point drain сохраняет поздний channel proof после logical failure. Registry также удерживает/ограничивает256chains и закрывает admission на stop; bootstrap verification использует тот же путь. Добавить RAM snapshot-consumer regression с short outer deadline/late runtime/channel logical error/physical pause, сохранив своевременный logical result. Проверить consumers connections/reads/executor/plans/jobs/authority/catalog, повторить full checks и fresh completed review.

Второй completed review подтвердил T289/T290 и выявил1P2 поздней chain за
actor snapshot. Fix uses physical chain handle beforework (не forwarding logical
error как physical failure).15session RAM cases всего; новый snapshot case
проверяет и retainedclose, и отсутствие ложного native-failure сигнала. Aggregate
case оставляет live session заранее, чтобы отдельно проверить256requests и отказ
нового proof до native вызова. Первый full chain run нашёл misplaced test variable;
исправлено, repeatfull144units exit0 .local/engine-sessions-chain-fixed-full.log.
Финальный полный прогон после усиления assertion и fresh review ещё обязательны.


### Completed portable session/service extraction review loop

Final full tools/test-unit.ps1 exit0 .local/engine-sessions-final-full.log:
format322/0changes, root+5analyses clean, root2+engine135+protocol7=144units passed.
Locald/MCP/Windows do not have currenttask tests; pass not claimed. Lychee exit0
.local/engine-sessions-final-links.log1463total1462OK0errors1excluded; scoped
gitdiffcheckexit0.3generatedschema parts SHA256 unchanged. Earlier failedruns and
review findings retained; no native/platform test evidence inferred.

Completed fresh independent read-only engine_sessions_chain_review:0findings,
all88scopedpaths/all40moves compared to baseline, T289–T291 fixes confirmed,
consumer chain ownership and typed service/store parity inspected. Increment
ready for continuation, not whole engine/app/cutover readiness. T255/T256/T257/
T258/T261/T265/T266/T268/T276 and main goal remain open. Actual grant/tool/terminal
backend parity, Host/gateway/UI/MCP bridge/tray/native adapters and cleanup remain
mandatory. Source-empty oldpackage/cache deletion still blocked by automatic
approval review (blocked by policy), no equivalent retry or success claim.


### T257/T258/T273: in-process owner gateway

EngineGateway/InProcessGateway route actual typed owner services through opaque
OwnerSession with initial/final proofs, Ready gates, immutable input/result
capture, original5s budget and physical-close drain. Retired unused
TrustedOwnerDispatch extension removed, no facade or new protocol/API selector.
Existing closed JSON byte/depth budgets include metadata via validation-only
placeholder (no owner credential serialization); Unicode/finite metrics preserved.
Error projection keeps existing safe public code/field/retry without diagnostics.

12new RAM units cover typed invocation/admission and immutable result; input
mutation during proof; readiness/builtins/domain denial; MCP gate beforepayload;
catalog projection; safe errors/invalidoutput; timeout vsphysicalclose;16pending
andlateclose; readiness/generation/revocation fences; session close/cleanup failure;
whole-message limits; noncanonical Unicode/finite JSON fidelity. Domain DTO/CAS
validation stays in its existing suites, not simulated by the dispatcher fake.
Firstfull source run found missing RetryAdvice import; firstnewtest run found
import-prefix shadowing; fixed and full checks rerun. No design/native/FS/SSH/UI
checks or new dependency/testmode interfaces. Mandatory checks/review below.
T257/T258/T261/T273 and full goal remain open until Host/UI lifecycle and remaining
parity/cutover work; this gateway is not completion of those tasks.


In-process gateway final checks completed: tools/test-unit.ps1 exit0
.local/inprocess-gateway-final-full.log, format324/0changes, root+5analyses clean,
root2+engine147+protocol7=156units passed. Lychee exit0
.local/inprocess-gateway-links.log1463total1462OK0errors1excluded; scoped
gitdiffcheckexit0. Completed independent read-only inprocess_gateway_review:
0findings, gateway increment ready for Host/UI composition. Reviewer inspected
real adapters/session lifetimes and request/response limits/DTO/cleanup parity,
not just fake tests. T257/T258/T261/T273 and main goal remain open; full Host,
UI/MCP/tray/cutover/parity and legacy cleanup remain required. No runnable app,
native/platform qualification or completed whole-task claim.


### T257/T259/T261: Host startup and explicit-exit ownership

Added EngineHost and engine-owned HostResources/WorkspaceHostResources. The normal
composition opens the sole existing Workspace/TrustedControlServices; OS ports do
not implement domain storage. Ready follows lease/runtime/vault/workspace and
service/job recovery plus final proof. Startup shares one30s operation, refuses
busy/wrong-owner/vault failures and tracks late physical startup through shutdown.
openOwner uses only Host-issued opaque authority with8total sessions, same-binding
pending deduplication and separate window response interests.

Explicit exit stops admission immediately, retains detached gateway drains and
waits startup/services/registry/authority/store/vault before lease. Default drain10s,
CloseBlocked keeps the lease after late resource completion until explicit
waitForClose; no retry/reopen/new generation. Failed cleanup/reservation/callback
keeps CloseBlocked. Actual lease release begun after confirmed drain is never
restarted. Safe readiness/errors do not contain provider diagnostics.

13RAM-only lifecycle units cover recovery readiness, shared startup/store, two
windows and detach/reopen, busy lease, owner/vault rejection, safe errors, startup
and monotonic deadlines, exit during late acquisition, CloseBlocked and explicit
waiting, failed service/store close/reservation, detached gateway physical work,
observed lease loss and throwing detach callback. No widget/design/native/realFS/
SSH/process/integration/UI test or execution was added. T257/T259/T261 remain open:
whole Windows/MCP/UI/capabilities/tray and suspend/resume composition remain
mandatory. Full checks and independent review are recorded after completion.


- [x] T292 Исправить подтверждённый P2 engine_host_ownership_review: перед same-binding replacement и pruning closed/expired gateway передать его в Host-owned physical drain, сохранить sticky cleanup failure и revoke прежний UI capability; isClosed не означает physical close. Добавить RAM regression для обоих путей с self-retired cleanup failure и late active dispatch. Повторить full checks/link check/fresh independent review; T257/T259/T261 и полная цель этим не закрываются.

Первый completed engine_host_ownership_review нашёл1P2: closed gateway мог быть
перезаписан/удалён без close, теряя cleanup failure. Исправлена единая retirement
ветка до reuse/pruning, включая revoke старого capability. Добавлены4RAMregressions
(по2на same-binding replacement и slot pruning):17Host units проходят адресно;
полный прогон и fresh review ещё обязательны. Исходная история13tests сохранена.


- [x] T293 Исправить подтверждённый P2 engine_host_fixed_review: резервировать Host pending owner future/physical work до runtime и retirement callouts; удалить/revoke весь old batch до gateway.close callbacks, чтобы synchronous reentry не создавала2gateways и не отзывала replacement. Добавить RAM onProof/detach/shutdown reentry regressions; full checks и fresh independent review обязательны.

Второй completed engine_host_fixed_review подтвердил исправление T292, нашёл1P2
T293: pending регистрировался после начала proof/retirement. Исправлено shared
Completer до callouts и batch retirement до close listeners.3новые RAM units
проверяют synchronous runtime proof reentry, expired2bindings с detach callback
и shutdown из retirement callback.20Host units проходят адресно. Полный final
runner и третий fresh review ещё обязательны; broad tasks/цель остаются открытыми.


- [x] T294 Исправить подтверждённый P2 engine_host_final_review: зарегистрировать physical startup Completer и timeout/readiness observers до _initialize/acquireLease; synchronous shutdown из provider ждёт actual startup, не dispose vault/Closed до late acquisition success/failure. Добавить RAM regressions, full checks/link check/fresh independent review.

Третий completed engine_host_final_review подтвердил T292/T293 и нашёл1P2 T294:
_startupWork присваивалась после начала _initialize и синхронного acquireLease.
Теперь physical startup/observers зарегистрированы до provider callout.2RAM cases
проверяют поздний успешный/ошибочный acquire после shutdown callback; до actual
completion нет vault dispose/Closed, успешный lease закрывается ровно1раз после
explicit waiting.22Host units проходят адресно. Убрано лишнее event-loop yield
между уже выданным release permission и lease.close после подтверждённого drain.
Final full checks и свежий независимый review обязательны, broad tasks/цель открыты.


Host increment final verification: .local/engine-host-owned-startup-full.log
EXIT0, repository format327files/0changes, root Flutter analyze plus5package
analyses clean, root2+engine169+protocol7=178units pass (22Host RAM units).
No test pass claimed for absent locald/MCP/Windows suites; excluded nested work
formatter lint-resolution warnings remain recorded. Lychee
.local/engine-host-owned-startup-links.log EXIT0:1463total1462OK0errors1excluded;
scoped git diff --check EXIT0 (CRLFwarningonly).

Fourth completed fresh read-only engine_host_startup_fixed_review:0findings,
bounded Host startup/local-owner/explicit-exit ready for further integration.
Reviewer independently confirmed T292/T293/T294 and the real Workspace/services
composition, cleanup ordering and request/physical-work ownership. Those3fix
tasks are closed; T257/T259/T261 and broader engine/Windows/MCP/UI/tray/capability/
suspend-resume tasks and main goal remain open. No native/realFS/SSH/process/UI/
integration/build/install acceptance was run; current UI is not connected to Host.
No new specification package or compatibility/production test-mode path was added.


### T265/T276: embedded-only discovery descriptor and portable custody

Replaced the sole protocol DiscoveryDescriptor parser with format2/hostKind app,
apiMinor1, required recovered workspace and Host generation; removed pre-ready
creation, random alternate generation and withWorkspace. Exactly8embedded-v1
pipes/newfile retain the old writer-mutex hash/name. Legacy versions/foreign
builds fail INCOMPATIBLE; bounded malformed payloads fail STORAGE_BLOCKED.
Moved DiscoveryCustody directly Windows→engine credentials, changed exact purpose
to embedded-v1, deleted the Windows implementation/export and rebound actual
Windows read imports/file paths. No façade, old-entropy/file fallback or legacy
migration/reset was introduced; old files remain untouched.

14new unit tests (8protocol+6engine) exercise Host bindings, exact fields/versions,
namespace/mutex hash, owner/slot/PID/build/UUID/nonce validation,8192byte raw and
16384byte wrapped limits, immutable copies/closed token, purpose binding, provider
failures, transient wipes, caller input mutation and late close. Tests use only
RAM protection; no native/realFS/process/SSH/integration/UI/design execution.
T265/T276 remain open: Windows runtime/publication/pipe worker, old client roots,
connection-only MCP bridge and actual Host/UI/tray composition are still required.
Full checks and fresh independent review follow before readiness conclusions.


- [x] T295 Исправить подтверждённый P3 embedded_discovery_review: проверять foreign build до closed-field validation, как требует embedded-host contract; закрепить смешанный случай foreign build+unknown field с INCOMPATIBLE. Повторить applicable full/link checks и fresh independent review всего descriptor/custody increment.

Первый completed embedded_discovery_review нашёл1P3: build проверялся после
closed fields вопреки точному порядку контракта. Код приведён к контракту,
в существующий unit добавлен foreign build+role field mixed case;14units сохраняют
normal/edge coverage. Full/fresh review обязательны; T265/T276/цель ещё открыты.


Embedded discovery final verification: .local/embedded-discovery-fixed-full.log
EXIT0: repository format329files/0changes, root Flutter analyze plus5package
analyses clean; root2+engine175+protocol15=192units pass,14new RAM units. No tests
pass claimed for absent locald/MCP/Windows suites; excluded nested checkout
formatter lint-resolution warnings retained. Lychee
.local/embedded-discovery-fixed-links.log EXIT0:1463total1462OK0errors1excluded;
scoped diffcheck EXIT0 CRLFwarningonly.
Fresh completed read-only embedded_discovery_fixed_review:0findings, bounded
descriptor/custody ready for continued runtime/IPC composition; T295 independently
confirmed. T265/T276 and all broader Host/Windows/MCP/UI/tray cutover tasks and
main goal remain open. No native/DPAPI/ACL/FS/SSH/process/UI/integration/build/
install acceptance, no new feature/spec or compatibility façade, no retry of
previously blocked cleanup. The current app still requires root/IPC integration.


### T256/T265/T276: actual Windows runtime and publication kernel extraction

Added genuine bundle4/current-app WindowsVerifiedRuntime with private-factory
WindowsWorkspaceLease identity binding, sticky proof failure, one-generation shared
gate creation registered before native callouts. It borrows root self identity
and never releases workspace lease. Extracted the single native gate directly to
publication_gate.dart as WindowsPublicationGate/acquisition/lease; old part file,
role dependency and gate-native observation hooks deleted, no forwarding aliases.
Existing kernel mutex/event/ACL/keeper and16actual/5s bounded drain/poison behavior
retained. Partial initialization returns a failed owned gate for Host close rather
than discarding native cleanup. Process handle close status is cached and checked
by the gate; every owned handle is attempted even after another cleanup failure.

Pure PublicationIdentity owns the unchanged kernel naming vector and validates
bounds/UUID/separators/Unicode without normalization.4RAM unit cases cover frozen
SHA256 identity, tuple separation, metadata boundaries and invalid generations.
Existing old IPC policy code remains outside kernel until the mandatory final
cutover; its direct gate references and MCP checked-creation paths were rebound,
not adapted into a new format3 runtime. T256/T265/T266/T274/T276 remain open for
new native MCP endpoint, root/bridge/UI/tray composition and complete old-source
removal. No Native/Win32/ACL/process/FS/SSH/UI/integration/build/install tests or
runtime qualification; full unit/static/link checks and independent review follow.


- [x] T296 Исправить подтверждённый P2 windows_runtime_gate_review: Windows publication namespace использует normalize+lowercase root до pure hash, как требует021publication-gate. Добавить RAM case/UNC/разные roots checks; full checks/fresh review обязательны.
- [x] T297 Закрепить подтверждённый P2 windows_runtime_gate_review: обязательный один engine worker владеет native Host/store/runtime/handles вне Flutter UI; trusted root-bound Dart-port proxy без owner export, общие monotonic deadlines/settlement bounds, window detach/shutdown/CloseBlocked/worker loss без in-process restart. Уточнить существующие plan/contract/T258/T261, проверить links и fresh review; реализация Root/proxy остаётся открытой.

Первый completed windows_runtime_gate_review нашёл2P2 T296/T297. Windows pure
publication_binding теперь выполняет normalize/lowercase до общего hash;3новые
RAM unit cases проверяют регистр/нормализацию/UNC/invalid roots без native imports.
В существующем plan и engine contract принято обязательное worker/UI размещение,
trusted private-port binding, Timeline.now budgets/physical settlement, shutdown
и lost-worker policy. Это prerequisite T258/T261, не опциональное предложение.
Эти две implementation задачи остаются открытыми: T258 включает private Root/
proxy/monotonic remaining-budget plumbing и все late/error paths из контракта;
T261 включает RAM worker/channel/clock/close-ack/loss coverage, без native/UI/design
запусков. Full checks и fresh independent review ещё обязательны для этого increment.


Windows runtime/gate final .local/windows-runtime-gate-reviewed-full.log EXIT0:
format333files/0changes, root Flutter analyze plus5package analyses clean;
root2+engine179+protocol15+Windows3=199unitpasses. Windows3units import only the
pure publication binding, no native Win32/FFI calls. No testpasses claimed for
absent locald/MCP suites; excluded nested work lint-resolution warnings retained.
Lychee .local/windows-runtime-gate-fixed-links.log EXIT0:1464total1463OK0errors/
1excluded; scoped diffcheck EXIT0 CRLFwarnings only.
Fresh completed independent windows_runtime_gate_fixed_review:0findings, bounded
runtime/kernel increment and prerequisite worker decisions ready for continuation.
T296/T297 independently confirmed; T297 closes the decision, not T258/T261 code.
Actual root/proxy/endpoint/MCP/UI/tray/capabilities/suspend-resume and old-source
removal T256/T258/T261/T265/T266/T274/T276 and main goal remain open. No native/
ACL/Win32/Isar/realFS/process/SSH/UI/integration/build/install qualification, no new
feature/spec, no retry of previously blocked package/cache cleanup. Current UI
still needs the mandatory engine-worker/proxy and same-executable MCP cutover.


### T258/T261/T273: bound worker gateway and original request ownership

Added EngineInvocation result/physical-settled split, absolute OwnerSession expiry
that cannot exceed5s, registered gateway work before preparation and shared exact
input capture. Added VmEngineClock, WorkerGatewayProxy/GatewayWorkerBinding and
actual private DartGatewayChannel (send/reply ports + opaque VM route binding).
Data adapter only consumes an existing private owner gateway, never attaches or
creates authority.16UI/worker tokens remain after response timeout until settlement;
reserved close, safe errors, generation/correlation, original deadlines, byte wipe,
terminal session.close and no retry on uncertain sends are implemented.

15RAM unit cases exercise capture/freeze/buffer wiping, completed-response physical
charges and17th denial, expired/queued/original5s budgets, accepted late effect,
reserved/reentrant close and cleanup failure, bad generation/control fields,
terminal close, uncertain call/reply sends, native-proof logical vs physical drain,
delayed timer/delivery and refusal to enlarge budget. Existing real session/owner
registry and gateway are used with RAM services/protection, no native/storage/UI
or actual engine-isolate dispatch. Root attach/control/native startup and UI/MCP/
tray replacement remain mandatory and open; this is not runnable app cutover.

- [x] T298 Закрыть выявленный full unit run unobserved proof Future: вычислять rpcBudgetRemaining до вызова final request.revalidate, чтобы expired budget не оставлял started Future без handler. Новый accepted-effect timeout regression должен проходить без uncaught UNAUTHORIZED. Full checks и независимый review всего bound worker increment обязательны.

First full worker-gateway-first-full run failed two unawaited test future lints and
an uncaught revalidate future when budget expired after accepted effect. Budget
ordering and lints fixed; targeted15new RAM units pass. Uncertain worker send never
resends an error/result; receipt checks absolute expiry even with delayed timers.
Full final checks/link validation and fresh independent review still required.


- [x] T299 Исправить подтверждённый P2 worker_gateway_review: early closed guards worker handle и proxy receive обязаны очищать owned mutable body даже до try/finally; поздний queued/in-flight пакет не выполняет prepare/effect и не создаёт другую close operation. Добавить RAM regressions обоих discard paths, full/link checks и fresh independent review всего increment.

Первый completed worker_gateway_review подтвердил остальные ownership/deadline/
authority ветки и нашёл1P2 discard wipe. Исправлены оба early guards, добавлены2RAM
cases: closed binding+queued body и in-flight listener callback после proxy cancel.
Итого17новых RAM tests проходят адресно. T298 ordering подтверждён чтением review;
T299 требует final full checks/fresh independent review. Root/UI/MCP/tray и цель
остаются открытыми, native/isolate/platform приёмка не заявляется.


Bound worker gateway final .local/worker-gateway-fixed-full.log EXIT0: repository
format336files/0changes, root Flutter analyze plus5package analyses clean;
root2+engine196+protocol15+Windows3=216unitpasses,17newRAM transport cases. Windows3
remain pure naming-policy units; no testpass claimed absentlocald/MCPsuites or
excluded nestedwork checkout (formatter lint-resolution warnings recorded).
Lychee .local/worker-gateway-fixed-links.log EXIT0:1464total1463OK0errors1excluded;
scoped diffcheckEXIT0 CRLFwarningonly.
Fresh completed read-only worker_gateway_fixed_review:0findings, bounded transport
ready for further integration, T298/T299 independently confirmed. Core actual
work/deadline/session consumers and17RAM scenarios were inspected. T258/T261/T273
remain open for trusted worker spawn/attach/control/native platform composition,
UIclient replacement and remaining parity; nativeMCP/tray/oldsource removal and
main goal remain open. No real isolate/native/FS/SSH/process/UI/integration/build/
install acceptance, no new feature/spec/compatibility facade or blocked cleanup
retry. Current UI still uses pending legacy bootstrap and is not claimed runnable.


### T258/T261: trusted worker root and Windows bootstrap

Added private VM-capability root routing, eight owner windows, reserved lifecycle
control, original startup/attach/exit budgets, partial startup ownership, explicit
CloseBlocked waiting, physical closed acknowledgement handshake, and Windows
worker entry/native bootstrap. Host adds runtime-metadata disposal before lease
release and managed automatic failure hold. Root controller/spawn and Flutter UI
cutover are still pending; existing UI remains legacy/not claimed runnable.
13newRAM tests (10root+3Host) exercise these boundaries; first full check found
Dart Capability/protocol enum collision, corrected by hiding protocol enum.
No old tests restored and no widget/design/integration/native tests added.
Full checks and independent review must finish before bounded readiness claim.


Trusted worker root final evidence: .local/worker-root-fixed-full.log EXIT0;
format339files/0changes, rootFlutter+5package analyses clean; root2+engine209+
protocol15+Windows3=229unitpasses, including13newRAMtests. Windows3 remain pure
policy tests; excludednestedwork formatter lint warnings do not imply qualification.
.local/worker-root-links.log EXIT0:1464total1463OK0errors1excluded. Scoped diffcheck
EXIT0, CRLFwarningonly. Completed independent read-only worker_root_review found
0findings and bounded Root/bootstrap readiness for further integration. No native/
FS/SSH/process/isolate/UI/design execution. Actual spawn/controller, UI cutover,
MCP publication, tray/suspend, broad tasks and goal remain open; current app still
uses pending legacy bootstrap and is not claimed runnable. No new feature spec,
compatibility facade, build/install/publish or blocked-cleanup retry.


### T258/T261: worker controller / concrete VM connection

Added EngineWorkerController and DartWorkerConnection, private actual spawn/control/
error/exit paths, retained original budgets/control slots, root-bound window links,
physical close acknowledgement before expected exit, loss without restart, and a
Windows desktop singleton factory. UI still uses old bootstrap; no runnable-app
claim.12newRAMtests exercise actual Root/Host/gateway with fake connection/timers,
not Isolate.spawn/native/UI/design. First full run caught two test errors; addressed
then all12targeted pass. Retired controller start now returns current CloseBlocked,
not old successful startup. Full checks/independent review follow.

- [x] T300 Исправить подтверждённую при concrete VM composition коллизию Capability: DartGatewayChannel.binding использовал protocol permission enum вместо VM capability. Скрыть protocol enum в enclosing gateway library, проверить concrete typed construction, RAM controller scenarios/full checks и независимое review. Не добавлять совместимость или owner DTO.


Worker controller final pre-review checks: .local/worker-controller-final-full.log
EXIT0, format342files/0changes, rootFlutter+5package analyses clean; root2+
engine223+protocol15+Windows3=243unitpasses,14newRAMcontroller cases. Added late
bootstrap/earlier exit deadline and changed generation rejection coverage. An
intermediate full run caught an outdated assertion expecting old Ready afterloss;
updated to require current CloseBlocked, then the complete suite passed. Native
spawn/FS/SSH/process/UI/design/build/install remains unexecuted. Formatter warnings
for excludednestedwork remain recorded; no qualification of that checkout.
Independent read-only review follows; broadgoal and UI/MCP/tray tasks stay open.


- [x] T301 Исправить подтверждённый P2 worker_controller_review: конкурентные shutdown/waitClose могут вернуть2Closed, concrete connection отклоняет второйACK, а observer зависает после_closed guard. Регистрировать physicalClosed/ACK однократно, до ACK завершать всех уже созданных same-root close observers с сохранением истёкших deadlines; второе сообщение не требуется. Добавить strict-ACK RAM regressions для обоих порядков ответов и onExit после первогоACK, затем fullchecks/linkcheck/fresh independent review.

First completed worker_controller_review found1P2 T301. Fixed shared physical-close
settlement before ACK and duplicate acknowledgement; retained bounded correlations
absorb queued close replies, no dependence on delivery after exit. Four new RAM
cases enforce oneACK across both response orders, with/without control-stream exit.
Current total18newcontroller RAM cases. Expired observers preserve their result;
late callbacks cannot overwrite current physicalClosed status. T300/T301 await
fresh completed review. No native/isolate/UI/design acceptance claimed.


Worker controller final reviewed evidence: .local/worker-controller-reviewed-fixed-full.log
EXIT0, format342files/0changes, rootFlutter+5package analyses clean; root2+
engine227+protocol15+Windows3=247unitpasses including18newcontrollerRAMcases.
.local/worker-controller-reviewed-fixed-links.log EXIT0:1464total1463OK0errors1excluded;
scopedgitdiffcheckEXIT0CRLFwarningonly. Fresh completed read-only
worker_controller_fixed_review found0findings and independently confirmed T300/
T301 closure. Bounded controller/VMconnection ready for further integration only;
actualIsolate/native/FS/SSH/process/UI/design/platform/build/install/release not
qualified. Excludednestedwork lint warnings recorded, no suite pass claimed there.
Existing T258/T261 and UI/MCP/tray/suspend/removal tasks and fullgoal stay open.
Current UI legacy bootstrap remains to be replaced; no runnable-app claim.


### T258/T261/T273/T276: UI embedded-engine owner cutover

FoundationApp/bootstrap now use DesktopEngineHost→single EngineWorkerController
and issued EngineClient/EngineApiClient; removed all four old UI IPC/native
bootstrap/child-launch source files. Rebound automation/server/software and profile
consumers without changing their widgets/layout. Bootstrap has one30s monotonic
budget, format3 readiness and no old prepare/ensure/relaunch/backoff path. Engine
Gateway gains logical retired notification separate from physicalclose. Explicit
app exit requires actualRootClosed before UI cleanup/Exit; CloseBlocked cancels.
Final tray/hide/menu/continue-waiting, activation, MCP mode/publication and broader
parity remain open. No feature readiness/runnable/runtime claim yet.
13newpresentation unit cases +3actualgateway/proxyRAM retirement cases exercise
logical behavior only; no design/widget/native/isolate/realFS/SSH/process tests.
First full run found callback defaultname collision/unnecessaryimport; corrected.
Retirement loss test initially expected serverclose success despite lost reply
channel; fixed to require SERVICE_UNAVAILABLE, and3targeted cases pass. Mandatory
complete checks/linkcheck/fresh independent review follow.


- [x] T302 Исправить подтверждённый P2 ui_engine_cutover_review: запоздавший snapshot/read вызывал _connected и мог создать attachment после retirement без explicit retry. Разрешить создание attachment только явному connect; reads/mutations могут ждать уже начатый connect. Проверять epoch/current session перед вторым snapshot read и polling перед queued callback. RAM regression с retirement после первого read, поздним detach, отсутствием скрытого attachment и ровно одним attachment после explicit retry; повторить full/link checks/fresh review.

First completed ui_engine_cutover_review found1P2 T302. Corrected attachment
admission and pre-second-read/queued-poll guards. Two new units cover no attachment
from read/mutate and retirement after first typed snapshot read with delayed
physicaldetach; completingdetach does not reopen, explicitconnect opensone next
session. Existing units now explicitly establish their sessions. Total15newUI
units+3actualgateway retirement units. No additional product decision introduced;
remaining tray/MCP/activation/suspend and broadgoal still open.


UI cutover final reviewed evidence: .local/ui-engine-cutover-fresh-full.log EXIT0,
format342files/0changes; rootFlutter+5package analyses clean; root17+engine230+
protocol15+Windows3=265unitpasses (15newUIlogic+3gateway/proxyRAMretirement).
.local/ui-engine-cutover-fresh-links.log EXIT0:1464total1463OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarnings. Fresh completed independent read-only
ui_engine_cutover_fixed_review found0findings and confirmed T302. Bounded UI
cutover ready for further integration only, no native/isolate/FS/SSH/process/UI/
design/build/install/runtime/release qualification. Excludednestedwork lint
warnings do not imply testing. T258/T261/T273/T276 remain open for complete path/
parity/cleanup reconciliation with remaining tray/MCP/activation/suspend work;
actual UIcomposition uses desktop_engine_host.dart and engine_client.dart plus
portable worker_controller/worker_connection, not the originally planned UI worker
filenames. No new feature spec or compatibility facade introduced.


### T259/T275: actual Windows tray/app lifetime and private desktop status

Added DesktopLifetime policy + native MethodChannel adapter + DesktopApplication
root, same-HWND restoration/section routing and window-subtree detach separate
from the one Host lifetime. Windows runner owns notification icon/menu/keyboard
callbacks, Explorer recreation, hide guard, custom Exit/Stay and CloseBlocked
Wait/Force/Stay dialogs, physical-only normalfinish and explicit whole-processforce.
CommonControls6 manifest and systemlibs/UTF8source options added; no executable,
build/install/deploy/publish or native/UI/design run. Added private bounded
Host→Root desktopStatus counts, no names/secrets or owner attachment. Old app-level
exit observer removed; close-to-tray is root-owned, no AppExit blanket-success.
15newRAM policy units plus2engine desktopstatus units cover these paths. Initial
full run caught an obsolete fallback after a newer Open; coalescing intent now
suppresses it. Root status validates0..4MCP and null/0..250unresolved jobs. Full
checks/linkcheck/independent review still required; suspension/activation/MCP and
fullfeature/native/release readiness remain open.


Tray final pre-review checks: .local/desktop-tray-reviewed-full.log EXIT0;
format347files/0changes, rootFlutter+5package analyses clean, root33+engine232+
protocol15+Windows3=283unitpasses.16newRAM desktop-policy cases+2desktopstatus cases;
one added case prevents physical wait completion destroying a native modal prompt
before it returns. Excludednestedwork formatter lint-resolution warnings remain,
notqualified. Lychee .local/desktop-tray-links.log EXIT0:1466total1465OK0errors1excluded.
Native C++/CMake/manifest source inspected against MicrosoftAPI references and local
Flutter headers only; no C++build/link, native/isolate/tray/dialog/FS/SSH/process/
UI/design/build/install qualification. Fresh independent read-only review follows.


Tray/lifetime final reviewed evidence: .local/desktop-tray-reviewed-full.log EXIT0,
format347files/0changes, rootFlutter+5package analyses clean; root33+engine232+
protocol15+Windows3=283unitpasses incl16newRAM policy+2private desktopstatus units.
.local/desktop-tray-reviewed-links.log EXIT0:1466total1465OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarnings. Completed independent read-only desktop_tray_review
found0findings and bounded tray/lifetime/status readiness for further integration.
Native C++/CMake/manifest inspected statically; build/link/Win32/tray/dialog/isolate/
FS/SSH/process/UI/design/runtime/release acceptance unexecuted. Excludednestedwork
lint warnings remain and that checkout is not qualified. Actual tray lifetime is
now wired in main/DesktopApplication and runner; T259/T275 remain open for final
path/acceptance reconciliation with pending suspend/resume, activation, MCP and
packaging/cleanup. Main goal stays active; no native build/install/deploy/publish.


### T256/T265/T274: genuine embedded MCP pipe ownership foundation

Added EmbeddedPipeListener/Channel with dedicated actual Windows I/O worker,
bundle4/self/peer proof, descriptorPID pin, actualSID embedded8 namespace, one-peer
listener/no handle reuse,16retained slots/original5s budgets and physicalclose ACK.
Publication gate factory uses same actual app/root and peer revalidation. Primitive
NativePipe now rejects old v1 names and propagates sticky close failures for pipe,
peer, event/cancellation handles and partial creation; client drain uses inbound
quota and server outboundquota per MicrosoftFSCC.4newpureWindows units cover these
policies only (no native imports/dispatch). Existing MCP bootstrap no longer owns
or starts any child process; missingdiscovery/availableendpoint is unavailable.
User reconfirmed MCP depends on alreadyrunningServerDeck (includingtray); absence
is a connector-side failure, no response from absent service, no autoHost. This
also applies to unconfigured/no-grant mode; live-app binding/entry remains open.
No new feature/spec created. Broadendpoint/handshake/stdio/legacy cleanup remain
pending; existing old bundledrole/session wiring not claimed runnable.

Finalpre-review .local/embedded-pipe-final-full.log EXIT0: format350files/0changes,
rootFlutter+5package analyses clean; root33+engine232+protocol15+Windows7=
287unitpasses.4newWindows tests pure RAM; no native worker/isolate/IPC/FS/SSH/process/
UI/design/build/install/deploy execution. Excludednestedwork lint warnings recorded,
notqualified. Linkcheck and mandatory independent source review follow.


- [x] T303 Исправить подтверждённый P2 embedded_pipe_review: общий5s producer limit запрещал штатное idle read60s из McpServerChannel. Разделить read≤60s и proof/write/drain≤5s; partialframe остаётся5s у framing owner. Оригинальные absolute deadlines включают очереди. RAM regression handshake5→idle60→partial5, исправить текущий контракт, повторить full/link checks и fresh independent review.

First completed embedded_pipe_review found1P2 T303 idle60 compatibility. Producer
now accepts read≤60s with unchanged absolute deadline; proof/write/drain≤5s and
server frame-owned partial5 remain. One new RAM sequence case covers this existing
server/port contract; no polling workaround or new protocol/compatibility mode.


Embedded pipe final reviewed evidence: .local/embedded-pipe-reviewed-fixed-full.log
EXIT0, format350files/0changes; rootFlutter+5packageanalyses clean; root33+engine232+
protocol15+Windows8=288unitpasses,5newpureWindows policy units. Lychee
.local/embedded-pipe-reviewed-fixed-links.log EXIT0:1467total1466OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarning. Fresh completed independent read-only
embedded_pipe_fixed_review found0findings and confirmed T303. Foundation ready
for further integration only; no native/isolate/IPC/FFI/FS/SSH/process/UI/design/
build/install/runtime qualification. Excludednestedwork lint warnings recorded,
notqualified. NewMCP endpoint/client/entry/oldbindingremoval and broadgoal remain
open. User clarification preserved: absent ServerDeck gives no service response;
only connector/client can report local connection failure, without starting app.


### T257/T265: actual Host-owned MCP endpoint pool

Added neutral ownedlistener/discovery ports and McpEndpointPool using the existing
McpServerHandshake/McpServerChannel/registry, eight bind-before-publish slots,
Ready-only activation, badpeer isolation, physicalclose-before-rebind, retained
latebind/publish work and stop/remove/descriptorwipe ownership. Native listener
implements the port. Host/WorkspaceHostResources now create same-actual-services
McpApiServer after recovery, require activated/exact API/generation/workspace,
optional platform pool factory, publish-before-parent-ready acknowledgement and
final runtime proof, published-only MCP feature, synchronous stop and physical
pool drain before store/vault/metadata/lease. Windows factory/discovery I/O is
still pending, so Windows MCP feature staysfalse, not a fake/stub available path.
13newRAM units (9pool+4Host) use actual core authority/router/session/handshake
and fake I/O/services without Native/FS/Isar or domain effects. First full checks
found a test await-on-void/unneededimport and an unobserved fake read error in
lateaccept; corrected, then13targeted cases passed. Full checks/linkcheck/fresh
independent review follow. App must already run; no autoHost/child process added.


Endpoint-pool final pre-review checks: .local/mcp-endpoint-pool-final-full.log EXIT0,
format353files/0changes; rootFlutter+5package analyses clean; root33+engine245+
protocol15+Windows8=301unitpasses including13newRAM pool/Host cases. Windows8remain
puremetadata/policy tests, no native dispatch. Existing excludednestedwork lint
warnings remain/notqualified. Native discovery owner/Windows bootstrap factory,
new client/bootstrap/stdio entry, suspend/activation/cleanup and broadgoal open.
Linkcheck and independent review follow before bounded readiness conclusion.


- [x] T304 Исправить P2 mcp_endpoint_pool_review: late accept после успешного listener.close не отменяет отдельное владение peer/channel. Ошибка физического disconnect остаётся sticky; pool.close завершается ошибкой, Host сохраняет lease/CloseBlocked. Добавить RAM regression в pool и Host, повторить обязательные проверки и независимое review.


T304 implementation and fresh independent review completed: mcp_endpoint_pool_fixed_review found no findings and confirmed separate late peer/channel close ownership, sticky physical failure, Host CloseBlocked and lease retention. Full .local/mcp-endpoint-pool-fixed-full.log EXIT0: format353/0changes, root Flutter plus5package analyses clean, root33+engine247+protocol15+Windows8=303RAM unitpasses. No native/runtime qualification. Scoped diff check EXIT0 (CRLF warning only). Link gate remains open: three lychee runs, including --timeout120 --max-retries1, exit2 with1467total1464OK0errors1excluded2timeouts at existing Mozilla MPL FAQ/index links. T304 checkbox remains unchecked until this mandatory gate passes. Windows discovery/factory/client/stdio and broad goal remain open; no end-to-end MCP readiness claimed.


Final link gate recovered: .local/mcp-endpoint-pool-final-record-links.log EXIT0 after completed independent review. Earlier Mozilla timeouts were transient. T304 is complete; broad T257/T265 and Windows/stdio integration remain open.


- [x] T305 Compose actual Windows Host MCP publication using the same retained runtime/lease/vault and fixed protected discovery file. Implement protected stale inspection, write/readback, exact retained-object removal, sticky unconfirmed native handle close and physical drain. Add RAM units, full mandatory checks/linkcheck and independent review. Keep full stdio/native qualification and remaining T265/T274/T276 open.


T305 final pre-review checks: .local/mcp-publication-final-full.log EXIT0,
format356/0changes, root Flutter plus5package analyses clean; root33+engine260+
protocol15+Windows8=316RAM unitpasses, including13new protected publisher cases.
First full run found generic T? return type and fixture legacy missing buildId;
fixed,13targeted units passed, then full suites passed. Added sticky unexpected
native I/O RemoteError handling and reran full checks successfully. Formatting
initially used wrong package-relative paths; formatted correctly from root
before successful full runs. Linkcheck .local/mcp-publication-final-links.log
EXIT0 (1469total1468OK0errors1excluded). Scoped diff check EXIT0 with CRLFwarning.
Source-empty locald/MCP have no tests and are not counted as passing suites.
Excluded nested work lint warnings are not qualification of that checkout.
No native/isolate/IPC/DPAPI/ACL/FS/Isar/SSH/process/UI/design/build/run/install
checks executed; static source analysis only for Windows implementation. Fresh
independent review is still required; broad client/stdio/cleanup goal remains.


Completed independent read-only mcp_publication_review found0findings and
confirmed bounded T305 readiness. Reviewed actual baseline6changed+3newfiles,
requirements/contracts/implementation/13RAM acceptance cases and supplied logs.
T305 complete. Actual Windows protected file/DPAPI/ACL/rename/disposition/pipes/
CloseHandle/isolate/build/run qualification is not established. Next work is
client/stdio/headless entry and oldbinding removal, not a new spec or a second
service. Whole goal remains active and broad T265/T274/T276 are not complete.


- [x] T306 Implement sole portable MCP-only client bootstrap/grant/RPC foundation over VerifiedMcpChannel, fixed API1.1 proof and descriptor binding, no owner method/role,16pending, absolute deadlines, no replay/reconnect, captured immutable frames/results and physical close ownership. Add RAM unit normal/edge/failure checks, run mandatory suites/links and independent review. Actual Windows client/gateway/stdin cutover and old source deletion remain T265/T274/T276.


T306 pre-review evidence: .local/mcp-client-fixed-full.log EXIT0, repository
format361/0changes, root Flutter plus5package analyses clean; root33+engine276+
protocol15+Windows8=332RAM unitpasses including16new client cases. First full
run failed missing host_trust protocol import and lint cleanup; corrected,
14targeted client cases passed, then two additional frame/envelope bound cases
and grant original-budget check were included in the successful final full run.
No source-empty locald/MCP tests are counted as passed. Excluded nested work lint
warnings are not qualification of that checkout. Lychee .local/mcp-client-links.log
EXIT0:1469total1468OK0errors1excluded. Scoped diff check EXIT0 CRLFwarning only.
Client tests use a scripted RAM peer, actual wire DTO/transcript MAC primitives
and fake memory file/protection providers; no Host/store/native/isolate/IPC/FS/
Isar/SSH/process/UI/design/build/run/install checks. Independent review follows;
actual Windows client/stdio cutover and full goal remain open.


- [x] T307 Fix confirmed P2 mcp_client_review: recursively freeze/capture result before final original-deadline and ownership check, then release pending slot/cancel timer/deliver. Add deterministic RAM CPU-boundary regression, rerun full/link checks and fresh independent review. Preserve T306 history and broad open cutover tasks.


T306/T307 final evidence: .local/mcp-client-reviewed-fixed-full.log EXIT0,
format361/0changes, clean root Flutter and5package analyses, root33+engine277+
protocol15+Windows8=333RAMunitpasses including17client cases. First independent
mcp_client_review found1P2 capture-after-deadline; T307 fixed it and added the
production-helper nested fake-clock boundary regression. Fresh completed
mcp_client_fixed_review found0findings and confirmed bounded foundation readiness.
Lychee .local/mcp-client-reviewed-fixed-links.log EXIT0:1469total1468OK0err1excluded.
No native/Host/Isar/FS/isolate/process/SSH/UI/design/build/install qualification.
Windows bootstrap/gateway migration, stdio/headless entry and old source removal
remain open T265/T274/T276; whole goal stays active, no end-to-end MCP claim.


- [x] T308 Switch actual Windows MCP connector/bootstrap/gateway to sole portable client and bundle4/descriptor2 without app-root/owner role/launch/store/writer or autonomous unconfigured mode. Own native connecting attempts and late startup, guard all fixed/builtin stdio output with live connection, separate logical retirement from physical drain, preserve publication through actual flush and return nonzero on uncertain EOF cleanup. Remove replaced separate MCP entry/ten old Windows client/bootstrap/worker files, add RAM units, mandatory checks/links and independent review. Keep lib/main/headless runner T274 and remaining T276 open.


- [x] T309 Preserve unconfirmed native protected-file close through WindowsProtectedFiles safe error conversion, latch it in desktop and stdio runtime owners, and check writer/copy/replacement CloseHandle outcomes. Desktop final disposal must fail and retain lease, stdio close must fail, including late credential reads. Verify existing RAM Host metadata-close boundary cases plus full static/unit/link checks and independent review; no native failure-injection qualification claimed.


T308/T309 pre-review evidence: .local/mcp-cutover-final-full.log EXIT0, repository
format353/0changes, root Flutter plus5package analyses clean. Root33+engine277+
MCP11+protocol15+Windows8=344RAMunitpasses,11new gateway/stdio cases; source-empty
locald has no testpass claim. First full failed missing extension imports and
nullable publication access, fixed; targeted first failed untyped empty-map
fixtures, fixed, then11targeted cases passed. Intermediate full passed before
final native file cleanup propagation; final full above includes T309 changes.
Lychee .local/mcp-cutover-final-links.log EXIT0:1469total1468OK0errors1excluded.
Scoped diffcheck EXIT0, CRLFwarnings only. Current-source rg has no deleted
Windows client/bootstrap/worker imports; engine's new client_bootstrap part is
unrelated to the deleted Windows file. No Host/store/realFS/native/isolate/pipe/
DPAPI/ACL/Isar/SSH/process/UI/design/build/run/install checks. Native source and
composition are statically checked only; excluded nestedwork notqualified.
Fresh independent review required. Main/headless branch and remaining legacy
artifact/source cleanup stay open; whole goal/end-to-end MCP notcomplete.


- [x] T310 Fix mcp_cutover_review P2 fixed RPC/overload no-op publication bypass. All fixed responses use native gate+verifyLive, update existing gateway.md exceptions, add RAM remote-error/overload acquisition+failed-proof regressions, rerun full/links/fresh independent review.
- [x] T311 Fix mcp_cutover_review P2 native worker identity factory uncertainty: failed factory latches failed physical close even with self=null, connector cannot reuse/advance slot after that close failure. Static Native lifecycle review plus full/link/fresh independent review; no native failure-injection qualification.


- [x] T312 Fix mcp_cutover_fixed_review P2 queued-expiry/domain-guard fallback without proof: settle/release denied original before stdout, then protect fixed fallback with fresh native gate+verifyLive under original writer budget. Preserve late guard/flush ownership, add RAM queued-expiry healthy/failed proof regression, full/link/fresh independent review.


T312 final pre-review evidence: .local/mcp-cutover-fallback-final-full.log EXIT0,
format353/0changes, clean root Flutter plus5package analyses; root33+engine277+
MCP15+protocol15+Windows8=348RAMunitpasses. Two added cases cover queued UTC grant
expiry with healthy/failed native proof and policy-ping denial after original
lease acquisition; fake gate refuses recursive/concurrent acquisition, proving
release-before-replacement ordering. No private fallback data or extra domain
request is sent. Earlier .local/mcp-cutover-fallback-fixed-full.log passed347
before this additional gate-ordering case; final log above is authoritative.
Fresh independent review and final links required; no native qualification or
main/headless single-exe readiness claim.


Completed fresh independent read-only mcp_fallback_fixed_review found0findings
and confirmed bounded T308-T312 readiness. Initial review found2P2 T310/T311;
second found1P2 T312, all fixed without erasing history. Final authoritative
.local/mcp-cutover-fallback-final-full.log EXIT0: format353/0changes, clean root
Flutter+5package analyses, root33+engine277+MCP15+protocol15+Windows8=348RAMunits.
.local/mcp-cutover-fallback-final-links.log EXIT0:1469total1468OK0err1excluded.
Review verified exact16changed+3new+11deleted sources/docs against scopedbaseline;
no deletedproductionimports/aliases. No native/Win32/DPAPI/ACL/FS/Host/Isar/isolate/
process/SSH/UI/widget/design/build/install/headless runtime qualification. Excluded
nestedwork and source-emptylocald notqualified. Normal main/headless mode binding
T274 and remaining T276artifact/protocol/sourcecleanup remain mandatory/open;
whole goal is active and single-exe MCP command is not yet declared runnable.


- [x] T313 Remove MCP direct dart:io stdio composition in favor of mandatory owned McpStdioPort, implement private pre-UI PlatformDispatcher carrier adapter with original physical I/O ownership and bounded diagnostics, RAM unit cases, full mandatory static/unit/link checks and independent review. Preserve native runner/main binding T274 as mandatory/open; do not claim a working headless command before that binding exists.


T313 pre-review evidence: .local/headless-port-reviewed-full.log EXIT0,
repository format356/0changes, root Flutter and5package analyses clean;
root45+engine277+MCP15+protocol15+Windows8=360RAMunitpasses, including12new
scripted carrier cases. First two full runs failed only Flutter analysis
(unnecessary import and missing unawaited in a test); fixed and final full passed.
Source-empty locald is not counted as a testpass. Formatter emitted existing
unresolved-lint warnings in excluded nested work; that checkout is notqualified.
flutter pub get added only the existing local serverdeck_mcp path dependency.
No native/realFS/Host/store/Isar/isolate/process/SSH/platform-dispatch/UI/widget/
design/build/install execution. Application main and Windows runner remain
unchanged, native carrier and headless dispatch T274 remain open. Independent
review and final link evidence are required before closing this bounded task.


- [x] T314 Fix headless_stdio_port_review P2: update existing021 gateway.md Process stdio runner to mandatory McpStdioPort/physical ACK/drain, remove normative direct-stdio fallback and clarify T115 history without erasing it. Rerun mandatory links, preserve successful unchanged-code full results and obtain fresh independent review.

First completed read-only headless_stdio_port_review found1P2 normative gateway
contract still requiring deleted direct IOSinks; no confirmed Dart code defect.
T314 updates that existing contract and records supersession of historical T115.
Code has not changed since .local/headless-port-reviewed-full.log EXIT0/360RAM
units. T274 native/main runner and whole-goal readiness remain unproven/open.


Completed fresh independent read-only headless_stdio_port_fixed_review found0
findings and confirmed bounded T313/T314 foundation readiness. Prior completed
review found1P2 contradictory normative direct-IOSink gateway section; fixed in
place, T115 history preserved. Authoritative unchanged-code full checks remain
.local/headless-port-reviewed-full.log EXIT0: format356/0changes, rootFlutter and
5package analyses clean, root45+engine277+MCP15+protocol15+Windows8=360RAMunits.
.local/headless-port-fixed-links.log EXIT0:1470total1469OK0errors1excluded
(the new relative contract link adds1 versus earlier1470-minus1 figures).
Reviewed12 exactsources/docs against scoped baseline; no native/platformdispatch/
realFS/Host/Isar/isolate/process/SSH/UI/widget/design/build/install execution.
Native carrier, SDKlog quarantine, argv/main/headless message pump T274 remain
mandatory/open. Single-executable stdio is not yet runnable or qualified, whole
Spec Kit goal remains active. No new feature/specification package was created.


- [x] T315 Complete T274 source binding: pre-UI native/Dart argv dispatch, same-executable viewless Flutter runtime and private owned stdio carrier, original handle capture/SDK log quarantine including transitive plugins and current CRT inheritance, physical I/O/close/owned-exit semantics, six RAM dispatch/zone units, full required checks plus C++ static syntax/links and independent review. No app/native I/O/build/install execution or runtime-readiness claim; keep T271 and overall acceptance open.


T274/T315 pre-review evidence: .local/headless-runner-final-full.log EXIT0,
format358/0changes, rootFlutter+5package analyses clean; root51+engine277+
MCP15+protocol15+Windows8=366RAMunitpasses,6new dispatch/owned-zone cases plus
12previous carrier cases. First full failed only avoid_print lint on the test
that intentionally exercises Zone.print; narrowly documented suppression fixed
that lint, then final full passed. No source-empty locald testpass claim;
excluded nested-work lintresolution warnings do not qualify that checkout.
.local/headless-runner-cpp-reviewed.log EXIT0: MSVC14.44.35207 cl /Zs /std:c++17
/EHsc /W4 /WX /wd4100 /D_HAS_EXCEPTIONS=0 /DUNICODE /D_UNICODE /DNOMINMAX
/D_WIN32_WINNT=0x0A00 /utf-8 on mcp_stdio.cpp/main.cpp/utils.cpp, using actual
WindowsSDK and pinned Flutter engine/wrapper headers; command and include paths
in .local/headless-runner-cpp-command.json. Syntax/type checking only: no object,
link, app build, executable dispatch or native I/O. Initial compiler invocation
used a missing default SDK include location; corrected from installed registry
path and array construction, actual final parse succeeded. Native control-handle
finish close was added after full Dart checks and included in final C++ parse;
Dart source has not changed since successful full. Native/platform/CRT/loader/
GPU/tray/FS/process/SSH/Isar/UI/widget/design/build/install behavior is unqualified.
Independent review and final link results are required before closure; T271 and
remaining full-goal acceptance stay open.


Completed independent read-only headless_runner_review found0findings and
accepted bounded T274/T315 source binding. It inspected all18 scopedfiles against
baseline, related001/021 contracts/bootstrap/connector/server and pinned SDK
messenger/task-runner semantics. Mandatory decision chain and current source
binding are supported; no native runtime/installed-command readiness concluded.
Authoritative .local/headless-runner-final-full.log EXIT0: format358/0changes,
rootFlutter+5package analyses clean, root51+engine277+MCP15+protocol15+Windows8=
366RAMunits. Six new production-dispatch/owned-zone cases complement existing
entry_mode argv cases,12 carrier cases and gateway EOF/physical-flush/close tests.
.local/headless-runner-cpp-reviewed.log EXIT0 is only cl /Zs syntax/type check
with /W4 /WX, no object/link/app execution. Exactcommand/sdkinclude paths saved
in .local/headless-runner-cpp-command.json. Lychee .local/headless-runner-final-links.log
EXIT0:1470total1469OK0errors1excluded; scoped diffcheckEXIT0 CRLFwarnings.
No native I/O/loader/CRT/GPU/FS/Isar/SSH/processfixture/UI/widget/design/build/
install/deploy qualification. T271 manifests/scripts and remaining T253-T276
acceptance/converge/finalgoal review remain mandatory; whole goal stays active.
No new feature/specification package was created; completed history preserved.


- [x] T316 Implement T271 embedded build entry/manifest4 source: one Flutter exe, engine codegen and current five locked contexts, strict RAM manifest composer plus8 RAM unit cases in full runner, current notice/source/ABI/review bindings, remove three replaced standalone/alias scripts, update existing startup/build contracts and quickstarts/docs in place. Full checks/static PowerShell parse/lychee and independent review required. No build/launch/notices collection/native activation or runtime qualification; T276 remaining legacy qualifier validators and overall readiness remain open.


T316 pre-review evidence: .local/embedded-build-reviewed-full.log EXIT0,
format358/0changes, rootFlutter+5package analyses clean; root51+engine277+MCP15+
protocol15+Windows8=366DartRAMunits plus8PowerShellRAMmanifest cases (374total).
Earlier two full runs also passed; final includes UTF8-byte overflow assertion,
engine build.yaml preserving generated-only experimental exemption and current
notices/source changes. Source-empty locald not counted as testpass; excluded
nestedwork lint-resolution warnings do not qualify that checkout.
.local/embedded-build-final-parse.log:8current PowerShell scripts AST-parsed,
0errors. No buildscript/collector/ABI/activation path was executed. No build,
app/native/realFS/processfixture/Isar/SSH/containers/UI/widget/design/install/deploy
checks. Existing NotoSansSC license is now included in collector sources without
changing foreign design/font assets. Three replaced individual source scripts
were removed; prior broad recursive cleanup refusals were not retried.
Native qualified-provider/old validator cleanup T276 and full T271/goal remain
open; source input/receipt guards were not replaced with RAM qualification.
Independent review and final links required before closing this increment.


- [x] T317 Fix embedded_build_review P2 output reparse guard gap: inspect existing layout descendants and explicit metadata paths before/post build, repeat exact output-file checks immediately before executor/manifest writes; full RAM/static/link checks and fresh independent review. No build or realFS fixtures; retain prior T316 history and open T271/T276 scope.

First completed read-only embedded_build_review found1P2: layout ancestor-only
guard allowed an existing metadata symlink to redirect Python/File.WriteAllText
outside output. T317 adds producer-path checks and existing-descendant validation.
The suspected NotoSansSC notice vs199payload count conflict was explicitly
unconfirmed: notices aggregate texts. No source-only/RAM check is promoted into
native behavior qualification, current-source activation or full T271 readiness.


T317 final pre-review evidence: .local/embedded-build-fixed-final-full.log EXIT0,
format358/0changes, clean rootFlutter+5package analyses,366DartRAM+8PSRAM=374
unitpasses. .local/embedded-build-fixed-final-parse.log:8PS ASTfiles0errors.
Actual output guard enumerates existing descendants without following directory
symlinks, checks each entry's own ReparsePoint attributes plus plain-path policy,
checks named destinations before and after Flutter, and repeats exact executor/
manifest destination guards immediately before each producer. Static inspection
covers these real calls; no filesystem fixture/source-golden test was introduced.
No build/native/collector/activation/app/processfixture/FS/Isar/SSH/UI/design/
install checks; no atomic hostile-filesystem or native-readiness claim. Fresh
independent review required, prior finding/history retained, whole goal active.


Completed fresh read-only embedded_build_fixed_review found0findings and
accepted bounded T316/T317 source readiness. Initial completed review found1P2
metadata reparse-output gap; fixed without FSfixtures or weakened source guards.
All23 scopedfiles compared with original baseline; deleted script callers absent
from currenttools. Current .local/embedded-build-fixed-final-full.log EXIT0:
format358/0changes, rootFlutter+5package analyses clean,366DartRAM+8PSRAM=374cases.
.local/embedded-build-fixed-final-parse.log:8PS ASTfiles0errors; actual build paths
not executed. .local/embedded-build-fixed-final-links.log EXIT0:1461total1460OK
0errors1excluded; scopedgitdiffcheckEXIT0 CRLFwarnings. Earlier history retained.
Native/FS/runtime/collector/ABI/activation/build/app/Isar/SSH/processfixtures/UI/
widget/design/install/deploy behavior unqualified. No atomic adversarial-path
or current-source native-provider qualification claimed. T271/T276 legacy qualifier
and remaining overall requirements stay open; whole Spec Kit goal stays active.


- [x] T318 Remove unused legacy protocol branches and bundle1/2/3 parsers/FramedReader/API1.0 handshake/schema1 readiness DTO+parser/old response validator/unused request-capability metadata, keep target sharedDTO/format3/schema3 behavior and Dart isolate Capability, remove obsolete import hides only, update existing021 bundle contract and add5RAM target boundary regressions. Full checks/links and independent review; no Native/FS/process/UI/design tests. T271/T276 broader cleanup remains open.


T318 pre-review evidence: .local/legacy-protocol-reviewed-full.log EXIT0,
repository format358/0changes, rootFlutter+5package analyses clean;
root51+engine277+MCP15+protocol20+Windows8=371DartRAMunits plus8PSRAM=379total.
Five new target-contract cases pass. First two full runs failed analysis because
one worker_root import still hid removed model Capability; fixed without changing
Dart isolate Capability, final full passed. Old tests were not deleted/relaxed;
existing current-task tests retain their assertions. Source-empty locald and
excluded nestedwork are not qualified. Current source search has no removed
symbol use; only ordinary English Authenticated in an unrelated comment remains.
No native/FS/Isar/processfixture/SSH/UI/widget/design/build/install execution.
UI changes are import-only; schema3 records/format3 handshake and permissions
unchanged. Independent review and final links required; T271/T276 remain open.


Completed independent read-only legacy_protocol_review found0findings and
accepted bounded T318 source/contract readiness. All16 scopedpaths compared to
originalbaseline; retained target parser bodies and UI bodies unchanged, actual
caller/admission/capture chains verified. Reviewer corrected an initial log-
reading omission after rereading line79:8PowerShellRAMpasses are indeed in the
actual full log, so total379RAM=371Dart+8PS confirmed. No codefix was required.
.local/legacy-protocol-reviewed-full.log EXIT0: format358/0changes, rootFlutter+
5package analyses clean; root51+engine277+MCP15+protocol20+Windows8. Final lychee
.local/legacy-protocol-final-links.log EXIT0:1462total1461OK0errors1excluded;
scopedgitdiffcheckEXIT0 CRLFwarnings. Excludednestedwork/sourceemptylocald not
qualified. No native/FS/Isar/processfixtures/SSH/container/UI/widget/design/build/
install/deploy checks, no whole T271/T276/goal or release readiness conclusion.
Current native qualifier legacy and other remaining implementation/audit work
stay mandatory/open. Completed task history preserved; no newfeature/spec created.


- [x] T319 Remove old normal-bundle format1/locald compatibility gate and shortened historical evidence fallback. Reuse strict current manifest4 composition for retained-bundle source-lock/DLL/root binding; current16 top-level analysis/native phases include engine/MCP and preserve all actual hash/ABI/review/current-source/activation requirements. Add8RAM metadata-policy groups, static AST/full checks/links and independent review. No native proof/receipt/provider qualification or build/activation execution; remaining T271/T276 procedure/producer cleanup open.


T319 pre-review evidence: .local/native-manifest-final-full.log EXIT0,
format358/0changes, clean rootFlutter+5package analyses;371DartRAMunits
(root51+engine277+MCP15+protocol20+Windows8) plus16PSRAMgroups=387total.
Eight added PS groups exercise retained map/JSON manifest/source/DLL/type/case/
Unicode/capture and exact current phase-policy boundary, including missing MCP,
legacy locald, false/string passed flags and nonstring names. Earlier full also
passed before final name/log type assertions; final is authoritative.
.local/native-manifest-final-parse.log:5PSscripts AST0errors. Actual filesystem
receipt/ABI/current-source/provider/build/collector/activation paths not executed.
Source-empty locald nottestpass; excludednestedwork lintwarnings notqualification.
Source review must confirm retained filehash/nativeABI/review gates and strict
14-runtime evidence remain required; RAM DTO success never supplies that proof.
No Native/FSfixtures/app/process/SSH/Isar/UI/design/build/install/deploy checks.
Independent review/final links required; broader T271/T276 and goal stay open.


Completed independent read-only native_manifest_gate_review found0findings and
accepted bounded T319 metadata-gate/source readiness. Reviewer compared9scoped
files, actual reader/policy/builder/source and activation call chain, preserved
Native checks and contracts; independently ran only pureRAM PSsuite16groups EXIT0.
Authoritative .local/native-manifest-final-full.log EXIT0: format358/0changes,
clean rootFlutter+5package analyses,371DartRAM+16PSRAM=387passes. AST5scripts0errors
.local/native-manifest-final-parse.log; lychee .local/native-manifest-final-links.log
EXIT0:1463total1462OK0errors1excluded; scoped diffcheck0 CRLFwarnings. Existing
assertions retained. No native reader/ABI/provider/build/collector/qualification/
activation/FSfixture/app/process/Isar/SSH/container/UI/widget/design/install/deploy
execution. Emptylocald/excludednestedwork notqualified. Full T271/T276/Native
workflow and overallgoal remain open; no newfeature/spec or readiness promotion.


## Phase 9: Convergence

2026-10-31, speckit-converge. Scope — действующая embedded-поправка001 и
сохраняемые обязательства002/021; пользовательские RAM/static-only и no-design/
no-native/build/install/deploy границы имеют приоритет над прежними harness.
Инвентарь:319 прежних task IDs, максимумT319; текущие15FR+15AC+5SC=35 items,
12групп решений плана,8принципов конституции. Прежние задачи оценены по результату
действующих corrective chains, не по галочкам; superseded отдельный daemon,
upgrade/rollback и старые native suites не восстановлены. Эта фаза append-only,
не меняет spec/plan/code/старые задачи и не подтверждает готовность всей feature.

Классификация11 findings: missing2, partial7, contradicts2, unrequested0;
HIGH8/MEDIUM3. Отдельного подтверждённого CRITICAL нарушения конституции этим
source-аудитом не установлено. Static/RAM результаты не native qualification.
Двенадцать проверенных групп решений: private worker/Host; portable ports;
verified bundle/peer; schema3 custody/adoption; owner/MCP authority; target sampler;
typed DTO/CAS/receipts; remote attempt recovery; executable/tray; capabilities;
bundle/runtime/notices; allowed checks/review. Реальные другие ОС и backend —
последующие поставки, не новая реализация в этой фазе.

- [x] T320 HIGH CG-01 Реализовать отдельный secondary-instance outcome в Windows/app bootstrap и engine ownership path per FR-SVC-EMB-03, AC-SVC-EMB-01, plan: ownership, T260 (partial). Сейчас windows/runner/main.cpp для каждого обычного запуска создаёт окно, DesktopLifetime запускает worker/Host, а lease-busy превращается в общий storage-blocked без отдельного activation/conflict outcome; hosting/instance_owner.dart отсутствует. Сохранить отсутствие второго store/writer; использовать только verified activation show-existing-window action, если такой канал предоставлен, иначе явно объяснять занятый экземпляр по действующему контракту, без owner/domain IPC, новых credentials, kill или автозапуска. RAM policy/contender tests должны проверять одновременный start, busy/starting owner, недоступную activation и отсутствие второго store/sampler; не создавать Native process fixtures. Новую обязательную activation-службу/протокол не изобретать: контракт допускает безопасный busy fallback.

- [x] T321 HIGH CG-02 Подключить suspend/resume к тому же worker/Host и observation/admission fence per FR-SVC-EMB-04/09, AC-SVC-EMB-02/08, plan: worker lifecycle, T259/T260/T261 (missing). DesktopAction/NativeDesktopPlatform/DesktopApplication и EngineHost сейчас не имеют этих переходов, Windows message handling не передаёт power/lifecycle events. Suspend закрывает новые эффекты и sampler/transports/interest, accepted remote jobs не cancel/replay; resume сверяет vault/capabilities/lease/revisions и делает новый observation fence с явным SSH connect. Тот же worker/store, без нового поколения как обхода незавершённого close. Добавить RAM original-deadline/late-reply/lost-callback/revoke/close-race cases; Native wiring только static, UI/design/native runtime не запускать.

- [x] T322 HIGH CG-03 Завершить target sampler/gateway parity проверку действительных сервисов per FR-SVC-EMB-02/03/09, AC-SVC-EMB-01/08/09, SC-SVC-EMB-01/04, T260/T261/T273 (partial). RemoteReadService._refreshes[profile]/_SharedRefresh уже реализуют shared work и identity checks, но имеющиеся hosting target/worker tests не проверяют этот сервис с несколькими UI/MCP interests и readKinds. Через RAM transport/store seams проверить сохранённые typed start/status/cancel и poll2s/cursor/cache bounds, одну физическую refresh identity, два SSH transports, разные scopes/revisions, revoke/target retirement и поздний physical drain. Переиспользовать реальную policy/domain логику, без общего watch/topic API, fake-success echo вместо сервиса или Native/SSH/Isar fixtures.

- [x] T323 HIGH CG-04 Добавить полную current MCP tool/permission parity через действительный router/domain services per FR-SVC-EMB-07, AC-SVC-EMB-07, SC-SVC-EMB-03, T268/T273 (partial). Сохранённые15 embedded_gateway_test cases проверяют client/gateway/publication на scripted peer, а не положительные/отказные маршруты всех24 tools. Catalog/router/services перенесены, но новый full parity suite отсутствует. Использовать общие RAM repositories/transport ports для реально вызываемых обработчиков; проверить все scopes/allowed targets, expired/revoked grant, private owner forgery, schema/input validation, proof-to-effect/publication fences, IDs и fixed errors без secrets. Не вводить production test-only authority bypass, не подменять assertion echo-ответом и не запускать Native/FS/Isar/SSH/process fixtures.

- [x] T324 HIGH CG-05 Завершить LocalJobObservation overlay и восстановление remote attempts per FR-SVC-EMB-08/09, AC-SVC-EMB-08/09, SC-SVC-EMB-04, T267/T268 (partial). jobs.dart уже сохраняет progress до submit и имеет recover/reconcile/unknown branches, но отдельного attached/detached/stale runtime observation overlay и новых observer_recovery RAM cases не найдено. Сохранить format3 external DTO и schema3 persistent identities, выражать observation отдельно от remote result; lost ACK после submit, detach/exit/crash, missing attempt, old generation/target, duplicate terminal/revoke и explicit authorized reconcile/cancel не освобождают occupancy и не отправляют submit заново. Проверять фактическую domain driver/state policy с RAM executor/repository; no native/SSH/process/FS fixtures и no restored one-time authority.

- [x] T325 HIGH CG-06 Дополнить synthetic adoption/retention полным непустым schema3 графом per FR-SVC-EMB-05/06, AC-SVC-EMB-04/05/06, SC-SVC-EMB-02, T262/T263 (partial). WorkspaceSnapshot reader захватывает16 collections и проверяет custody/graph, но populated fixture/schema3_state/workspace_snapshot tests заполняют в automation только grant/receipt, оставляя revision/plan/delegation/approval/job/event/desired families пустыми. Добавить допустимый связанный граф всех сохраняемых семейств, IDs/nativeIds/revisions/blobs/enrollment/history и refusal/fault cases; сравнить точные retained rows и semantic snapshot, убедиться что session/one-time permit не воскресает. Не открывать Isar/FS, не добавлять migration/rollback или snapshot reset; использовать существующие row-source/protection fakes.

- [x] T326 HIGH CG-07 Реализовать immutable EngineCapabilities и lifecycle/vault matrix fakes per FR-SVC-EMB-10/11, AC-SVC-EMB-10/11/12, SC-SVC-EMB-05, T269 (missing). platform/ports.dart имеет vault/protection/runtime contracts, но capability_snapshot.dart/эквивалент snapshot с platform/storageReady/vaultStatus/directSsh/localMcpBridge/tray/backgroundPolicy/reasonCodes отсутствует. OperationalFeatures не заменяет эту модель. Windows Ready/admission должны отражать соответствующие состояния; unknown/locked/unavailable не success. Для остальных5строк — честные unsupported/foregroundOnly/Web directSsh=false и fake-host import/loader boundaries без Windows fallback; реальные не-Windows adapters/backend не реализовывать. Добавить RAM matrix/vault/lifecycle tests, static import checks считать отдельно от RAM assertions.

- [x] T327 HIGH CG-08 Удалить оставшиеся legacy inputs и test-only helper dependencies per FR-SVC-EMB-14/15, AC-SVC-EMB-15, T271/T276 (contradicts). Source-empty packages/serverdeck_locald всё ещё содержит pubspec/build/analysis/lock, а .github/workflows/unit.yml и tools/test-unit.ps1 автоматически обходят все package directories и продолжают разрешать/анализировать этот старый package. Найти оставшиеся callers/внешние entry каждого старого helper и убрать только заменённый/неиспользуемый код без re-export/deprecated facades. Закрепить точный текущий package/build/CI input set; сохранить target schema3/format3 helpers, runtime/notices/source/receipt guards. Не обходить и не повторять эквивалентным способом ранее системно отклонённую broad recursive cleanup; разрешённую часть закрывать отдельно, недоступный остаток честно фиксировать. Наличие такого остатка не считать завершённым T276.

- [x] T328 MEDIUM CG-09 Завершить актуальные storage/platform инструкции и безопасную presentation copy per FR-SVC-EMB-06/10/12, AC-SVC-EMB-06/10/11/12, T264/T270 (partial). docs/development/embedded-engine-storage.md и platform-capabilities.md отсутствуют; README продолжает описывать client/locald и удалённый test-foundation-available.ps1, readiness/error views предлагают локальную службу и согласование client/service версий. Описать только target-schema3 refusal/preservation/writer-busy и реальные шесть platform statuses/prerequisites, существующий app/tray и отсутствие отдельной службы; не обещать миграцию, поддержку будущих OS или Native/release readiness. Presentation structure/design003 не менять и не тестировать; unit проверять лишь безопасный message/status policy, если он меняется.

- [x] T329 MEDIUM CG-10 Согласовать dependency pin и оставшиеся статусные утверждения плана с принятой current-source реализацией per plan: Technical Context/Reuse boundaries, FR-SVC-EMB-12, T255/T270 (contradicts). Embedded plan указывает dartssh2 4.2.0, engine pubspec/lock используют перенесённый4.1.0; план также сохраняет заявления об ещё отсутствующем Root/proxy после выполненных component increments. Исправить артефакты по подтверждённому текущему scope и pins без незапрошенного dependency upgrade, не стирая task history и не присваивая unsupported/native readiness. Converge сам spec/plan не меняет.

- [x] T330 MEDIUM CG-11 Завершить aggregate evidence/приёмку и повторный Analyze/Converge per FR-SVC-EMB-12/13, все35 FR/AC/SC поправки, T261/T268/T272 (partial). Текущие component checks/reviews не закрывают целиком незавершённые T255–T276; embedded-engine-verification.md заканчивается T312 и не отражает T313–T319. Перепроверить все применимые требования и task corrective chains по текущему source, записать точные commands/exit/scope/остатки и обновить агрегатные статусы лишь с доказательствами. engine/test/platform_boundary_test.dart читает source Directory/File и является static source check, а не RAM domain test: выделить его в static stage или явно разделить классификацию/count, не удаляя import-boundary coverage. Последний полный результат387checks содержит371Dart tests (один static source scan) и16PSRAMgroups; не выдавать все за RAM. Выполнить необходимые полные format/analyze/unit/link checks и обязательный независимый whole-scope review/fix loop; завершение только после подтверждения всей текущей цепочки, без Native/FS/process/SSH/UI/design/build/install/deploy запусков или пропуска unresolved findings.

Implementation handoff: выполнять T320–T330 в существующем пакете после
specification link check и обязательного независимого review/fix loop. Ни одна
прежняя галочка не изменена. Следующий Converge должен проверять полученное
поведение заново, не считать появление этих задач реализацией.


### Phase 9: independent review correction — 2026-10-31

Завершённый read-only converge_phase9_review нашёл1P2 в безусловной формулировке
T324 о release occupancy после cancel/reconcile. Это исправление требований
CG-05, не новая remote операция и не изменение существующего021. Остальные
findings подтверждены source review. Ни предыдущие задачи, ни их галочки не
переписываются; эта явная поправка имеет приоритет над спорной фразой T324.

Нормативный критерий T324/T331: detach, loss/отсутствие ACK, stale observation,
сам запрос cancel или reconcile и ответ pending/unknown НЕ освобождают occupancy
и не разрешают новый apply. Verified correlated terminal той же актуальной
attempt допускает release только по действующим условиям021: валидный terminal
receipt/sequence/identity, необходимые проверки результата и доказанное отсутствие
продолжающегося child (childrenStopped, где требуется). Поздний/чужой/некоррелированный
terminal не освобождает актуальную attempt. Успешно доказанный terminal не должен
оставлять бессрочную блокировку. Использовать существующие переходы
[records021](../021-mcp-control/contracts/records.md) и
[executor021](../021-mcp-control/contracts/executor.md), без нового wire/schema.

- [x] T331 HIGH Исполнить CG-05/T324 с исправленным occupancy criterion per FR-SVC-EMB-08/09, AC-SVC-EMB-08/09, SC-SVC-EMB-04 и completed converge_phase9_review P2 (partial). Для действительной domain policy добавить RAM случаи: cancel/reconcile intent и pending/unknown сохраняют occupancy; доказанный correlated terminal с необходимыми checks/childrenStopped освобождает; late/foreign terminal не освобождает актуальную attempt; затем разрешённая новая работа не блокируется навсегда. Эта задача уточняет приёмку T324, не отменяет её overlay/recovery работу и не выдаёт существующий запрос отмены за доказанный remote terminal. No Native/FS/Isar/process/SSH/UI/design fixtures.

Проверка append-only до Phase9:575353bytes SHA256
b28d5915936e4ea52a2de9ffbfa57808b638c492a107664a8c0c85a42dfbfc69 сохранены.
Исторический full результат T319387checks не перепроверялся этой Converge-фазой;
один из371Dart tests — static source scan, остальные370Dart и16PS группы RAM.
Code/spec/plan/constitution в Converge не менялись. После поправки требуются
повтор lychee и свежее независимое read-only review до implementation handoff.


Phase9 handoff review complete: initial converge_phase9_review found1P2 ambiguous
T324 terminal/occupancy wording; explicit normative append-only correction and
T331 added without rewriting oldtasks. Fresh completed read-only
converge_phase9_fixed_review found0findings and accepted bounded implementation
handoff for T320–T331. It confirmed both supplied prefix hashes and actual source
basis/contract trace. These12tasks remain unchecked/unimplemented; this does not
close T255–T276 or the whole goal. Code/spec/plan/constitution unchanged by this
Converge. No extension hooks registered. .local/converge-phase9-fixed-links.log
EXIT0:1465total1464OK0errors1excluded (two added relative contract references).
No Flutter/unit/native/runtime/FSfixture/process/Isar/SSH/UI/design/build/install/
deploy checks were run by Converge or its reviewers. Prior387checks are historical
current-source evidence only, including1static source scan, not387RAM assertions.
Next: speckit-implement against the remaining tasks, then repeat Analyze/Converge
and the mandatory final AGENTS review/fix loop; no feature recreation.


### T320 implementation evidence: explicit busy fallback

Platform/Host now distinguish immutable actual acquisition failure from a lost
acquired lease; only an owner/default-bound contender within its original startup
budget receives HostStartResult.workspaceBusy. No store/services/sampler/MCP opens.
Private worker status carries validated busy/readiness, preserving the historical
startup outcome separately from physical cleanup status. Bootstrap never attaches
an owner or retries that incarnation. The existing readiness screen explains the
conflict; no design/layout or widget tests were added. Closing the contender exits
its own process through the common cleanup/CloseBlocked/Wait/Force path, without
warning about another process's jobs. An early hidden window is restored on a late
busy outcome. No verified activation channel exists; the permitted safe fallback
is used without inventing IPC, compatibility, credentials or app auto-launch.

- [x] T332 Correct the confirmed C++ syntax defect in the affected desktop status
  parser: local identifier `small` collided with the Windows macro. Rename the
  int32/int64 locals; preserve numeric limits and behavior. Static MSVC `/Zs`
  checks only, without compilation/linking/executing a native application.

Actual checks before independent review: tools/test-unit.ps1 EXIT0 in
.local/secondary-instance-full.log: repository format358files/0changed; root
Flutter analysis and five package analyses clean; root54 + engine286 + MCP15 +
protocol20 + Windows8 =383 Dart checks, plus16 PS RAM groups. One existing Dart
check is a static source boundary scan, so this is398 RAM checks +1 static scan,
not399 RAM tests. The empty residual locald package has no tests/pass claim.
Formatter warnings concern the excluded nested work/ checkout's lint resolution.
The first Host-only full run failed one new asynchronous test assertion; after
waiting for actual owner startup, targeted31 Host tests and the subsequent full
suite passed. lychee EXIT0:1465total1464OK0errors1excluded. MSVC `/Zs` of
windows/runner/flutter_window.cpp with existing SDK include paths + /Iwindows
EXIT0 after correcting the macro collision; initial attempts failed (missing local
include path, then macro collision). No Native runtime/FS fixture/process/SSH/
Isar/UI/design/build/install/deploy tests were run. Completed independent secondary_instance_review found no findings and accepted
bounded T320/T332 readiness. It inspected the22-file baseline diff, actual
sources and supplied check logs, without executing tests or modifying files. Other Phase9 and T255-T276 tasks remain open.


### T321 session admission foundation (T333)

- [x] T333 Implement the same-registry admission pause needed by T321, per
  FR-SVC-EMB-04/09, AC-SVC-EMB-02/08 and the existing worker lifecycle contract.
  Pause synchronously retires owner/MCP session records and observation interests;
  physical proofs/pending charges remain owned. A new private epoch rejects late
  owner issuance/handshake proofs even after resume or reentrant expiry callbacks.
  Only the current same-registry opaque pause can resume admission once; repeated
  pause, foreign/stale tokens, failed detach and permanent stop cannot revive it.
  Do not block privileged local cleanup publications or interpret detach as remote
  cancel/terminal evidence. RAM tests exercise actual EngineSessions and retained
  platform proof futures, without Native/FS/process/store/SSH/UI/design fixtures.

This is a bounded internal admission component, not completion of T321. Host and
service physical pause/drain, sampler/cache/observation fence, vault/capability/
lease/revision recheck, same-worker desktop power routing, original deadlines and
close races remain required. No standalone runtime, new spec, compatibility or
wire role/credential was introduced. The public Host start summary above was
aligned with the already implemented WorkspaceBusy outcome from T320.

Initial full tools/test-unit.ps1 run failed one new test's expected safe code:
MCP reservation correctly rejects the already removed record as UNAUTHORIZED
before generic admission gating. The test was corrected to preserve that rule.
Source inspection also retained the existing safe expiry callback error handling
and added an epoch check around registration's reentrant expiry callback. The
subsequent targeted sessions suite passed24tests including9new pause cases.
Final full tools/test-unit.ps1 EXIT0 in .local/suspend-admission-final-full.log:
format358/0changed; root Flutter +5 package analyses clean; root54 +engine295
+MCP15 +protocol20 +Windows8 =392Dart checks, plus16PS RAM groups. One existing
Dart case is the static import boundary scan, so407RAM+1static, not408RAM. Empty
residual locald package has no tests/pass claim; formatter warnings refer only to
excluded work/ lint resolution. lychee EXIT0 in .local/suspend-admission-links.log:
1465total1464OK0errors1excluded. No Native/runtime/UI/build/install/deploy tests.
Mandatory independent review is pending. T321 and the full goal remain open.


- [x] T334 Fix confirmed P2 from completed suspend_admission_review: nested detach
  callbacks could pause/resume and admit a new owner before outer retirement
  completed. Track active retirement frames and reject resume until all unwind.
  Return the latest token from the outer pause after nested epochs, rather than
  stranding its caller with a stale token. Keep uncaught callback failures final.
  Two RAM regressions exercise caught resume refusal/no new owner and uncaught
  refusal/permanent stop. T333 review loop requires full applicable checks and a
  fresh independent reviewer; the initial review was not clean. T321 stays open.


T334 fix verification: full tools/test-unit.ps1 EXIT0 in
.local/suspend-admission-fixed-full.log: format358/0changed; rootFlutter and5
package analyses clean; root54+engine297+MCP15+protocol20+Windows8=394Dart checks,
plus16PSRAM groups. One existing Dart case is static, so409RAM+1static (not410RAM).
All11 new pause/regression cases are RAM-only and included in this full run.
lychee EXIT0 .local/suspend-admission-fixed-links.log:1465total1464OK0errors1excluded.
No Native/platform/UI/runtime/release qualification asserted. A fresh independent
review is required before treating T333/T334 as accepted. T321 stays unchecked.


Completed review evidence for T333/T334: fresh suspend_admission_fixed_review
found0findings and accepted bounded admission component readiness, after the
initial1P2 fix. It inspected the6-file baseline diff, current sources/contracts/
tasks and supplied check logs without running tests or modifying files. Full
T321 lifecycle and all remaining aggregate work are still open.

### T321 shared SSH pool physical pause foundation (T335)

- [x] T335 Implement the reusable physical pause boundary of the existing shared
  SshTransportPool for T321 / FR-SVC-EMB-04/09 / AC-SVC-EMB-02/08. Fence reserve,
  connect and probe synchronously; stop existing operations and own their physical
  settled futures. Preserve custody reservations until their actual owners close,
  so logical timeout cannot free either of the two transport slots. Return a
  same-pool opaque pause handle with the original physical settled future;
  repeated suspend shares it. Resume only after drain for the current handle;
  stale/foreign/reused handles, uncompleted drain and permanent close cannot open
  intake. Resume never connects, restores a reservation or replays a remote job.
  Six actual-pool RAM unit cases exercise these slot/handle/timeout/close rules
  without admitting any network operation or invoking files/processes/isolates.

The shared physical drain path is also used by permanent close. This does not
claim actual socket/client/key-worker failure-injection coverage or application
suspend implementation. Host/service owner cleanup must start before awaiting
pool.settled; domain admission/fences, sampler/observer/transport service wiring,
resume revalidation and desktop events remain openT321. No new feature spec,
compatibility path, dependency, wire protocol, credentials or independent runtime.

Actual full tools/test-unit.ps1 run completed successfully in .local/ssh-pause-full.log;
final counts and links are recorded below before independent review. No native,
SSH, FS fixture, process, Isar, integration, UI/design/widget, build/install/deploy
checks were run. Mandatory independent review remains required for this slice.


T335 pre-review evidence: .local/ssh-pause-full.log EXIT0: format359files/0changed,
rootFlutter +5package analyses clean; root54+engine303+MCP15+protocol20+Windows8
=400Dart checks, plus16PS RAM groups. One existing Dart case is a static import
boundary scan:415RAM+1static total416, not416RAM. Six new pool cases are RAM-only.
Empty residual locald package has no tests/pass claim; formatter lint warnings
concern only excluded work/ checkout. lychee .local/ssh-pause-links.log EXIT0:
1465total1464OK0errors1excluded. No native/platform/runtime/release qualification.
No application code changed after this successful full run; only in-place spec
contract/task evidence updated. Independent AGENTS review is pending for T335.


Completed T335 review: independent ssh_pool_pause_review found0findings and
accepted the bounded shared SSH pool pause. Read-only source/diff/spec/log review,
no independent test execution. FullT321/Host binding remains open.

### T321 actual service composition suspension (T336/T337)

- [x] T336 Implement same-composition suspension of actual TrustedControlServices
  and remote connections/reads/executor/trust probes/job observers per T321,
  FR-SVC-EMB-04/09 and AC-SVC-EMB-02/08. Retire external sessions before remote
  cleanup, start all service owners before awaiting pool reservations, preserve
  privileged local cleanup authority and physical proof/native work ownership.
  Clear old observation interests/cursors/cache/inspections, preserve store/key/
  trust/grants and service identity. Job driver drain includes late transfers;
  do not send remote cancel or repeat submit. Resume only the current successfully
  drained service handle, with current snapshot and provider gates restored before
  fresh external sessions. Failed partial restore seals pool/registry and begins
  permanent close. Keep original physical ownership after observer timeout and
  permanent-close races. Add actual-composition RAM tests over validated16family
  schema3 snapshot and explicit typed repository/runtime/publication RAM adapters.
- [x] T337 Correct the confirmed unit/analysis interface issue exposed by the first
  full run: assertAutomationCustody was a static extension and could not be
  implemented by the RAM repository adapter. Move its exact existing native-store/
  key-binding body into StateStore instance interface; remove extension definition
  entirely. No test-only production mode, weakened body, compatibility forwarding,
  different root factory or wire-selected provider. Actual root continues using
  native StateStore; unexpected RAM repository operations throw immediately.

Ten RAM cases exercise fresh settings/read/jobs after resume, stable snapshot/
component identity, retired handles, late request proof and logical timeout,
custody/local cleanup authority, handle identity, close race, failed snapshot
read, provider closure, superseded registry fence and detach failure. Empty remote
graph guarantees tests never open SSH/Isar/FS/process/isolate/native work. This is
not accepted-remote-job fault-injection, full snapshot parity or Host/desktop
lifecycle coverage. T321 remains unchecked: HostResources/Host/worker/controller/
desktop power wiring, full observation fence and runtime/vault/lease/capabilities/
revision recheck remain mandatory; T322-T331 and aggregate work remain open.

First full tools/test-unit.ps1 failed analysis and all7 initial new cases because
an extension cannot be overridden by the fake; T337 moved the unchanged body.
Subsequent targeted run found an explicit missing RAM isReady property; added it.
The targeted suite then passed, expanded to10cases and passed again. A failed
attempt to redirect the initial targeted command used the root working directory;
no tests ran in that attempt; the command was rerun from the package directory.
Normalized custody binding source body was compared to the saved baseline and
matched SHA256 2dd964b803ac18e4196971ca534dd29ccd4441ab0ea8c40bb1c39c46902c956a;
old extension definition is absent (.local/service-pause-custody-body.json).
Final full checks and independent review are recorded next; no wholeT321 readiness
or native/platform/runtime/release qualification is claimed.


T336/T337 pre-review evidence: .local/service-pause-final-full.log EXIT0:
format360files/0changed; rootFlutter and5package analyses clean; root54+engine313
+MCP15+protocol20+Windows8=410Dart checks plus16PSRAMgroups, total425RAM+1existing
static import boundary scan (not426RAM). Ten new cases use actual domain services
and gateway with RAM repository/proof ports. Empty residual oldlocald has no
current-task tests/pass claim; formatter lint warnings only excluded work/.
lychee .local/service-pause-links.log EXIT0:1465total1464OK0errors1excluded.
No source code changes after this full run; only spec evidence updated and links
rerun. Mandatory independent AGENTS review/fix loop remains pending for this slice.


Completed T336/T337 review: independent service_pause_review found0findings and
accepted bounded service component readiness. It inspected the12-file source/diff/
contract/tasks and actual logs read-only, independently verified unchanged custody
binding body and old extension removal, ran no tests. FullT321 remains open.

### T321 Host lifecycle ownership (T338/T339)

- [x] T338 Bind actual EngineHost to the existing same-composition service pause
  via required HostResources suspend/revalidate/resume methods, per T321,
  FR-SVC-EMB-04/09 and AC-SVC-EMB-02/08. Fence readiness/domain admission before
  callouts, retire pending/issued owner bindings, retain gateway/owner/runtime
  physical proofs and same store/vault/runtime/lease. Add startup services-ready
  checkpoint without extending original30s budget or publishing earlyReady.
  Resume current opaque Host pause with original<=30s observer budget and<=5s
  individual runtime proof; recheck runtime/vault/store runtime/current services/
  selected executor capability and fixed workspace identity before admission.
  Keep physical provider ownership beyond logical timeout, retire failed Host
  through existing10s shutdown/CloseBlocked/Wait path. Superseded/reentrant resume
  cannot open a gate or poison a new epoch; no replacementworker/store/services,
  reset, SSH reconnect or jobreplay. Add actual Host/authority/session/gateway/MCP
  policy RAM tests, including startup/shutdown and originaldeadline races.
- [x] T339 Correct confirmed Host/MCP activation boundaries while implementing
  T338: a pause after activation bind await must wait for the Host admission
  barrier before readiness/publication, not fail the same Host. Make activation's
  beforePublish callback required and bind the real Host checkpoint; update all
  current callers without an optional legacy/default path. Preserve the existing
  SERVICE_UNAVAILABLE mapping for an unactivated MCP server: lifecycle epoch
  NOT_READY is typed/scoped, not a broad change to startup error normalization.
  RAM regression validates deferred publication behind the actual pool barrier.

Fifteen new Host RAM cases plus one pool RAM case cover unstarted/no autostart,
foreign/consumed handles, fresh owner/singleopen, late revoked owner physicalproof,
startup publication pause, original startup/resume budgets, superseded/reentrant
resume, early startup shutdown, late servicepause/revalidation and vault/lease/
workspace/native metadata/snapshot/restore failures. Native ports/resources are
RAM fakes; actualHost/authority/session/gateway and MCP publication policy execute.
No actualNative/Isar/FS/process/SSH/UI/widget/design/integration/build/install/
deploy work was run. Actual service composition was separately exercised by T336;
these fakes do not assert end-to-end native or release readiness.

T321 stays unchecked: worker/controller lifecycle phases and desktop power event/
lostcallback handling, UI reattachment, immutable capability matrix T326 and its
full resume binding remain required. Root must apply an early power intent after
normal Host.start begins, without calling start from suspend. Resume during
startup observes the original startfuture for eventualReady. No newfeature/spec,
compatibility path, wire role/credential, data migration or optional noop recheck.

First full .local/host-pause-full.log failed one new superseded-resume code mapping.
Targeted8Host tests passed after a first correction. The expanded next full
.local/host-pause-final-full.log exposed an existing unactivated-MCP error mapping
regression from that overly broad safe-code change. Correction was narrowed to
lifecycle epoch errors; the original test/assertion was preserved. Added startup
monotonic-budget guard and mandatory activation barrier, then targeted31 Host/pool/
publication tests passed. Final fullchecks and mandatory independent review follow.


T338/T339 pre-review evidence: .local/host-pause-reviewed-full.log EXIT0:
format361files/0changed; rootFlutter +5package analyses clean; root54+engine329
+MCP15+protocol20+Windows8=426Dart checks plus16PSRAMgroups, total441RAM+1existing
static import boundary scan (not442RAM). The16new Host/pool cases are RAM-only.
Empty residual locald has no current-task tests/pass claim; formatter lintwarnings
refer only to excluded work/ checkout. lychee .local/host-pause-links.log EXIT0:
1465total1464OK0errors1excluded. No code changed after this successful full run;
only spec evidence updated and links rerun. Independent AGENTS review pending;
T321 and fullgoal readiness are not established by these bounded checks.


- [x] T340 Fix confirmed P2-1 from completed host_pause_review: a reentrant new
  suspend after service restore fenced only Host readiness while the shared
  registry stayed open until deferred physical suspension. Supply mandatory pure
  Host-owned admissionBlocked policy to EngineSessions; enforce it before owner
  proofs/registration and session current/domain admission independently of the
  service token. Update every actual/RAM root explicitly, with no optional default.
  Strengthen reentrant RAM case to reject MCP handshake synchronously inside the
  callback and verify no new provider proof starts.
- [x] T341 Fix confirmed P2-2 from completed host_pause_review: final startup
  timeout-success callback bypassed pause/monotonic deadline after initialize.
  Commit start Ready inside owned startup work immediately after final checks,
  without await/provider call before publication; observer only handles failures.
  Two RAM scheduling cases sweep41microtask offsets each across initialization
  completion, checking pause-held acknowledgement and expired startup budget,
  and assert coverage on both sides of Ready. Original physical startup future
  still owns the commit and cleanup. Full applicable checks/fresh review required.

Initial completed host_pause_review found2P2 and was not clean; its findings are
recorded above without erasing T338/T339 implementation history. T321 and the
whole goal remain open. Fixed source/check/review evidence follows below.


T340/T341 post-fix evidence: full tools/test-unit.ps1 EXIT0 in
.local/host-pause-fixed-full.log: format361files/0changed; rootFlutter +5package
analyses clean; root54+engine331+MCP15+protocol20+Windows8=428Dart cases plus16PS
RAMgroups, total443RAM+1existingstatic source scan (not444RAM). Eighteen new
Host/pool RAM cases include the82 scheduling variants inside two sweep cases.
No source changed after this full check. lychee .local/host-pause-fixed-links.log
EXIT0:1465total1464OK0errors1excluded; links rerun after this evidence update.
No Native/platform/runtime/UI/release qualification. Fresh independent review
required; original review2P2 does not establish readiness.


- [x] T342 Fix confirmed P2 from completed host_pause_fixed_review: suspend could
  arrive after beforePublish future completed but before pool continuation, making
  recovering readiness a terminal activation failure. Return a synchronous current
  Host epoch/deadline guard from the required barrier. Recheck after await and
  readiness, then accept publication I/O without an async gap. Superseded guard
  waits the current Host barrier in the same operation/budget; genuine readiness/
  identity errors remain terminal. Add pool epoch regression and an actualHost+
  pool RAM sweep across41activation microtask offsets, asserting no pre-resume
  publication for pauses before I/O, same startfuture/Host/store and eventualReady.

Completed host_pause_fixed_review found1P2 (not clean), while confirming the two
original fixes. The third review loop remains required. Full post-T342 check
.local/host-pause-publication-fixed-full.log EXIT0: format361/0changed, rootFlutter
+5package analyses clean; root54+engine333+MCP15+protocol20+Windows8=430Dart plus16PS
RAMgroups, total445RAM+1static import scan (not446RAM). Twenty new Host/pool cases
include123microtask scheduling variants inside3sweep cases. No source changes
after this full run; specification evidence only. No Native/platform/runtime/UI/
release qualification. T321/T326 and wholegoal remain open.

Completed third review evidence: host_publication_fixed_review reported zero
findings for T338–T342 after reading the scoped sources/specification/diff and
the actual full/link logs. It ran no tests and changed no files. This accepts
the bounded Host/pool scope; T321/T326 and the full goal remain open.

### T321 private worker/controller power ownership (T343–T345)

- [x] T343 Implement private capability-authenticated WorkerPowerIntent with a
  strictly increasing positive signed63-bit epoch, original at-most30s absolute
  deadline and latest-intent coalescing. Parent immediately masks readiness and
  retires owner interests; Root fences the same Host upon receipt independently
  of16ordinary correlation slots. One physical pump observes current pause,
  window retirement and restore. Pin generation, ignore stale acknowledgements,
  reject old metadata/attach replies with NOT_READY and wait actual parent owner
  detaches before fresh Ready/owner admission. No restart, replay or new service.
- [x] T344 Preserve early startup: retain power without launching anything,
  apply it after ordinary Host.start begins, permit resume to release original
  startup without blocking a newer intent on the start reply, preserve busy and
  expire failed restore through the shared shutdown barrier. Do not let a late
  initial lifecycle acknowledgement downgrade a newer power Ready. Retain the
  original startup/deadline/physical ownership and shutdown paused startup safely.
- [x] T345 Deliver coalesced early power before authenticated one-time begin in
  the actual worker connection and normal Windows worker entry, before storage
  or publication. Keep accepted discovery I/O runtime/owner/lease/generation/
  activation proofs after awaits; a later recovering phase alone cannot make
  accepted publication fatal. Add RAM boundary/queue/startup/quota/epoch/fresh
  owner cases. Apply the amended embedded-engine contract; do not claim native
  execution or completed desktop power event/capability integration.

T343–T345 checks: tools/test-unit.ps1 EXIT0 recorded in
.local/worker-power-coalesced-full.log. Formatter363files/0changed; rootFlutter
and5package analyses clean; root54+engine346+MCP15+protocol20+Windows8=443Dart,
plus16PS RAMgroups:458RAM+1existing static import scan. Thirteen new RAM cases
exercise actual private worker/controller/Host policy with RAM ports, including
1000-intent bursts,16pending ordinary controls, early busy/expired restore and
superseding physical restore. Native/isolate/FS/SSH/process/UI/design/build/
installation/release checks were not executed. Formatter warnings concern
unresolved lint includes in the excluded nested work checkout.

Independent review/fix loop and specification link results are recorded next.
T321 stays unchecked: desktop/native power event and phase binding, fresh UI
attachment and the full T326 capability snapshot/matrix remain required. MCP
requires a running app (tray counts); absent app permits only local connector
stderr/nonzero failure, never a service response or application autostart.

- [x] T346 Fix confirmed P2-1 from completed worker_power_review: add an
  independently observed original resume deadline spanning pending Host pause,
  window drain, restore and original startup. Expiry begins common shutdown;
  cancel the observer when superseded, current Ready succeeds, or shutdown
  begins. Retain physical work/lease ownership; add RAM case with a held service
  suspension, expired resume and later actual cleanup on the same Root.
- [x] T347 Fix confirmed P2-2/P2-3 from completed worker_power_review: a deferred
  Ready must not overwrite newer same-epoch terminal metadata. Validate pinned
  generation synchronously before deferring acceptance and observe callback
  exceptions through fail-closed retirement. Add RAM regressions for pending
  detach plus newer failed readiness, and foreign-generation power Ready without
  an unhandled asynchronous failure. No retry/new incarnation or new protocol.

Completed worker_power_review found3P2, not a clean result. The original full
checks above did not exercise these orders. All three findings were confirmed
against code and contract and corrected in T346/T347. Fresh full/link checks
and independent review are still required before accepting this increment.

T346/T347 post-fix checks completed: .local/worker-power-fixed-full.log EXIT0,
format363files/0changed; rootFlutter+5package analyses clean; root54+engine349+
MCP15+protocol20+Windows8=446Dart plus16PS RAMgroups =>461RAM+1static source scan.
All16new RAM cases pass. .local/worker-power-fixed-links.log EXIT0:
1465total1464OK0errors1excluded. No Native/isolate/UI/FS/SSH/process execution.
Fresh independent review remains required; the original3P2 report is not clean.

- [x] T348 Fix confirmed P2 from completed worker_power_fixed_review: public
  refreshReadiness/refreshDesktopStatus returned raw Root Ready while parent
  detaches still held the controller barrier. Return the controller-accepted
  status at the public await continuation, retaining validated desktop counts
  and original frame/correlation checks. Add RAM case for both metadata results
  while power Ready waits detach, plus two reply-to-public-continuation races
  with a newer intent. Fresh Ready is visible only after actual old detach.

Completed worker_power_fixed_review confirmed all original3P2 fixes and found
the new metadata projection P2; it was not clean. T348 corrects the confirmed
defect without introducing UI/design tests or changing power event scope.
Fresh full/link checks and independent review remain required.

T348 post-fix evidence: .local/worker-power-projection-fixed-full.log EXIT0;
format363files/0changed; rootFlutter+5package analyses clean; root54+engine352+
MCP15+protocol20+Windows8=449Dart plus16PS RAMgroups =>464RAM+1static import scan.
All19new RAM cases pass. .local/worker-power-projection-fixed-links.log EXIT0:
1465total1464OK0errors1excluded. Native/isolate/UI/FS/SSH/process qualification
was not executed. Third independent review is required before acceptance.

Completed third review worker_power_projection_fixed_review reported zero
findings for T343–T348, confirmed all4previous P2 fixes and accepted this bounded
worker/controller scope after read-only source/spec/diff/log inspection. It ran
no tests and changed no files. OverallT321/T326 readiness remains open.

### T321 desktop power and fresh presentation binding (T349–T350)

- [x] T349 Bind normal Windows WM_POWERBROADCAST to suspend/resume desktop actions
  and the existing worker power intent. Use APMSUSPEND and RESUMEAUTOMATIC;
  subsequent RESUMESUSPEND user activity does not start another restore. Retain
  one latest Native intent before Dart initialize and flush before its reply,
  after Dart subscribes and before ordinary engine start. Forward to Flutter/
  plugins and return TRUE for handled power events. Add three lifecycle phases
  to the existing tray status allowlist; preserve close/tray/Exit policy.
- [x] T350 Bind DesktopLifetime power revisions to private window epochs and
  current accepted status. Invalidate old private UI on intent; preserve window
  visibility and remembered section, sample one physically owned status at a
  time with one pending2s timer, reject stale revision samples and remount once
  on current resume Ready. Fresh presentation reattaches/new snapshot on the
  same worker without replay. DesktopEngineHost.start must project current
  status after its await, preserving confirmed historical busy. Add RAM unit
  coverage for early intent, hidden/visible restore,1000intent burst/stale poll,
  Exit barriers, initial resuming/currentReady and continuation races. No UI/
  design/native execution. T321 stays unchecked pending T326 and final audit.

T349/T350 pre-review evidence: tools/test-unit.ps1 EXIT0 in
.local/desktop-power-full.log; format364files/0changed, rootFlutter+5package
analyses clean; root62+engine352+MCP15+protocol20+Windows8=457Dart plus16PS
RAMgroups =>472RAM+1existingstatic import scan. Eight new RAM cases cover
desktop lifetime/current presentation projection; no widget/design/UI tests.
MSVC /Zs on actual windows/runner/flutter_window.cpp EXIT0 in
.local/desktop-power-cpp.log with existing compiler flags plus /Iwindows; no
object/link/build/run. Lychee .local/desktop-power-links.log EXIT0:
1467total1466OK0errors1excluded. Independent review/fix loop remains required.
T321/T326 and whole goal readiness remain open; no Native/platform qualification.

Completed desktop_power_review reported zero findings and accepted bounded
T349/T350 after read-only inspection of eight changed files, actual lifetime/
controller/presentation/native chain, specification and recorded full/C++/link
logs. It ran no checks or edits. This closes those increments only, not T326,
T321 or whole goal readiness.

### T326 capability snapshot design and implementation chain (T351–T355)

- [x] T351 Fix the concrete EngineCapabilities design in the existing
  embedded-platforms contract: six platform rows, eight closed fields, safe
  canonical reasons, explicit platform declarations, actual Host proof ownership,
  unsupported startup without provider access, required private WorkerStatus
  snapshot and controller-local actual tray overlay. Preserve existing authority,
  publication, deadlines, schema3 and cleanup; no Windows fallback or new public
  protocol. This marks written decisions, not implementation or review acceptance.
- [x] T352 Implement immutable hosting/capability_snapshot.dart per T351/T326:
  strict closed parser/capture, copied immutable collections, explicit matrix
  and derived necessary core predicate. Bind EnginePlatform's required enum and
  actual Windows composition. No native imports, implicit platform defaults,
  optional old shapes or metadata-derived permission authority.
- [x] T353 Bind actual EngineHost startup/suspend/resume/failure/stop and shared
  admission to the current snapshot per T351. Withdraw positive proofs before
  callbacks, retain observed negative vault status, revalidate existing actual
  ports and commit only current successful epoch. Unsupported start rejects
  before provider probes/open/lease; transferred cleanup remains owned. Preserve
  optional MCP publication order, original budgets and physical retention.
- [x] T354 Adopt required platform/snapshot in Bootstrap/Root/controller private
  status and all current callers/fixtures; pin platform alongside generation,
  mask power/loss/terminal projections and old replies, and retain current
  parent Ready barrier. Bind actual desktop tray observations through local
  immutable overlay with stale initialize protection, without a new worker frame
  or grant. Preserve visible fallback and current post-restore fresh UI policy.
- [x] T355 Add task RAM acceptance for all six rows/immutable shapes/unknown and
  negative vault, actual Host transition/proof ownership and superseded epochs,
  unsupported/mismatch without provider startup, Root/controller metadata masks,
  actual tray policy ordering and no metadata grant escalation. Separately run
  static import/loader-boundary checks and existing source scan; do not count
  filesystem source inspection as RAM. Full mandatory checks and independent
  code review/fix loop precede T326/T321 closure; no Native/platform qualification.

T351 is a specification handoff update only. T352–T355/T326/T321 remain open.
Mandatory link check and completed independent specification review are required
before treating this design as implementation-ready. No new feature/spec file,
runtime code, tests, dependencies, generated files or checklist markers changed.

Completed capabilities_design_review reported zero findings for the T351 design
handoff after read-only contract/task/current-source inspection. It confirmed
the separate Host core/pre-publication Ready and masked nonready Root projection,
and controller-local tray authority boundary. T352–T355 above are now implemented
with code review pending; T326/T321 aggregate closure still requires the evidence
and final trace audit, not merely these checked implementation subtasks.

T352–T355 pre-review checks: tools/test-unit.ps1 EXIT0 in
.local/capabilities-fixed-full.log: format366files/0changed; rootFlutter+5package
analyses clean; root64+engine373+MCP15+protocol20+Windows8=480Dart plus16PS RAMgroups,
495RAM+1existingstatic import scan. Twenty-three added RAM cases cover matrix,
closed immutable parsing, actual Host startup/unknown/vault failure/restore/stop,
unsupported early rejection and owned cleanup, Root mismatch, controller/tray
projection and stale desktop initialize. Existing lifecycle tests additionally
assert withdrawn/current capability state for timeout and superseded restore.
First full .local/capabilities-full.log failed one old desktop status fixture
missing the now-required capabilities field; only that fixture was corrected,
its original strict-field/count assertions preserved. No targeted runs.

Separate static .local/capabilities-static.json records the actual pure snapshot
import graph (capability_snapshot.dart and platform/ports.dart, SDK typed_data),
and source order of Windows OS guard before bundle/native providers. It is not
RAM or native loader execution. No Native/isolate/FSfixtures/SSH/process/UI/
widget/design/build/install/deploy qualification. Formatter lint-include warnings
concern the excluded nested checkout. Link check and independent code review/fix
loop follow; whole goal readiness remains unproved.

Completed capabilities_code_review reported zero findings for T352–T355 after
read-only inspection of sixteen changed files and actual Host/Root/controller/
desktop/source/check evidence. All proposed capabilities decisions are now
implemented; no source edits followed that review. The previous bounded review
alone did not close aggregate tasks. The following primary requirement audit
supports T269/T326 closure within their authorized implementation/unit scope:

| T269/T326 obligation | Current source and acceptance evidence |
| --- | --- |
| Immutable exact snapshot, safe canonical reasons and six platform rows | [snapshot](../../packages/serverdeck_engine/lib/hosting/capability_snapshot.dart), [matrix/parser/immutability tests](../../packages/serverdeck_engine/test/hosting/capability_snapshot_test.dart),9RAMcases |
| Unknown/locked/unavailable not successful; actual lifecycle/current resume and physical ownership | [Host](../../packages/serverdeck_engine/lib/hosting/engine_host.dart),8added [Host cases](../../packages/serverdeck_engine/test/hosting/engine_host_test.dart) and additional current/superseded/timeout assertions in [lifecycle cases](../../packages/serverdeck_engine/test/hosting/host_lifecycle_test.dart) |
| Unsupported five rows before provider startup, honest mobile/Web limits | explicit kinds and five actual Host failure cases with zero lease/vault/storage starts; matrix mobile foregroundOnly, Web no SSH/MCP; owned fake cleanup distinguished |
| Platform/generation and parent-detach masks; actual tray projection | [Root](../../packages/serverdeck_engine/lib/hosting/worker_root.dart), [controller](../../packages/serverdeck_engine/lib/hosting/worker_controller.dart), [desktop](../../lib/platform/desktop_lifecycle.dart), Root mismatch/three controller/two tray RAM cases plus existing worker/private metadata suite |
| Pure domain/platform import boundary, no UI direct Isar/SSH or Windows fallback startup | existing full [static domain source scan](../../packages/serverdeck_engine/test/platform_boundary_test.dart), pure two-file snapshot import graph and OS-guard ordering in .local/capabilities-static.json; fresh direct UI source scan0matches |

Fresh audit .local/capabilities-aggregate-audit.json confirmed the current source
reconstructs the exact reviewed capabilities diff and no direct UI storage/SSH
imports. Authoritative prior .local/capabilities-fixed-full.log EXIT0 includes
480Dart+16PSgroups:495RAM+1static. These checks prove the implementation/fake-host
matrix, not a real non-Windows adapter, native FFI/vault/loader or OS power event.
T269/T326 are marked complete accordingly. T270 documentation handoff, fullT321,
remote parity T322–T325/T331 and finalT330 audit remain open; no whole-goal or
platform/release readiness is promoted.

### T322 real sampler parity handoff (T356–T360)

- [x] T356 Fix the internal RAM I/O/key-handle/time seam and acceptance decisions
  in the existing embedded-engine contract for T322. Keep actual pool/sampler/
  connection/owner/MCP policies, quotas, original deadlines and physical drain;
  no echo service, forged role/context, public command API or Native execution.
  This marks written design, not implementation or review acceptance.
- [x] T357 Extract the existing native socket/key-worker/SSHClient lifecycle into
  one I/O provider behind factory/attempt/client/byte-session ports in the actual
  ssh_transport library. Actual SshTransportPool/Lease/read/executor classes keep
  all admission/host-pin/result/timer/quota/drain policy, including2transports and
  4channels. One shared pool receives the provider only at trusted composition;
  preserve safe errors, credential lifecycle and no success before verification.
- [x] T358 Provide the owned McpGrantKey repository handle interface with the
  existing private holder/body, no new grant or context constructor. Bind shared
  engine clock to RemoteReadService cache/cursor/history/receipt time and owner
  read-handle retention, preserving actual grant/session/proof/deadline clocks
  and parsed remote observation time. No write/Isar transaction API or production
  quota/default is weakened for tests.
- [x] T359 Exercise actual RemoteReadService/TrustedConnectionService and owner/
  MCP adapters/authority with validated RAM schema3 repository, real custody/HMAC
  and controlled byte I/O. Cover concurrent healthy shared refresh, authority
  handoff, profiles/read kinds/scopes/revisions, typed start/status/cancel, cache/
  cursor/history/ring/channel/work bounds, revoke/target retirement and late
  physical drains. Measure actual provider calls/owned slots; no fake result DTO
  in place of source capture/domain policy. Preserve existing no-secret behavior.
- [x] T360 Exercise list/settings poll2s and coherent owner snapshots through
  actual EngineApiClient/gateway/foundation/coordinator over RAM repository,
  scheduled callbacks and shared target sampler; no duplicate collector/start,
  old-generation publication or mutation replay. This is unit controller policy,
  not UI/widget/design execution; target5s minimum and owner500ms/MCP250ms poll
  remain distinct unchanged policies. Full required checks and independent code
  review/fix loop precede T322 closure.

T356 is specification handoff only. T357–T360/T322 remain unimplemented. Link
check and completed independent specification review are required before this
handoff is treated as implementation-ready. Existing runtime, tests, generated
files, dependencies and reviewer-owned checklist markers are unchanged here.

Completed sampler_design_review found zero findings, accepted T322/T357–T360
handoff and independently confirmed T269/T326 closure in implementation/RAM/
static scope after actual source/requirements inspection. It ran no tests and
changed no files. The T357 implementation now follows that accepted handoff;
T358–T360 and T322 remain open, with no real sampler parity claim yet.

T357 extraction keeps actual SshTransportPool/_SshOperation admission, host-pin
verification, logical result deadlines,2slots/4channels and physical drain. New
ssh_io.dart interfaces carry only typed SshIoCommand.read(existing request) or
fixed executor kind; no raw command selector reaches any wire. ssh_native_io.dart
owns the single former socket/key-worker/SSHClient provider lifecycle. The
key-worker/KDF/spawn code remains byte-for-byte identical SHA256
5020ef0f5540153ec84cc30d725f9060a19a9056ac988d8828e8d249d09b6079; algorithm source
also unchanged. Static .local/ssh-io-static.json records these comparisons and
one socket/client constructor and fixed executor literal. This is source proof,
not Native/SSH/key-isolate execution. TrustedControlServices supplies one provider
to its existing shared pool; default normal provider is native, RAM injection is
engine-only, with no role/profile/environment/wire toggle or legacy path.

T357 pre-review .local/ssh-io-fixed-full.log tools/test-unit.ps1 EXIT0:
format369files/0changed, rootFlutter+5package analyses clean; root64+engine383+
MCP15+protocol20+Windows8=490Dart plus16PS RAMgroups =>505RAM+1static source scan.
Ten new RAM I/O-event cases exercise actual pool/lease/read/executor policy:
2slots, typed output capture/truncation,4shared channels, no/mismatched pin,
probe-after-drain, late client/provider retention, synchronous factory stop,
shortened original connect budget and suspend/drain. First full
.local/ssh-io-full.log failed new fixture noncanonical fingerprint and two
unawaited observation Futures; corrected fixture/observations, preserving the
assertions. No targeted run. Link check and completed independent code review
remain required before bounded T357 acceptance; full T322 is not complete.
No Native/isolate/socket/SSH/process/FSfixture/UI/widget/design/build/install/
deploy qualification. Formatter warnings concern excluded nested lint includes.

- [x] T361 Fix confirmed P2 from completed ssh_io_review: provider settled error
  or synchronous cancel/close throw escaped run/finally and stranded public
  completion. Observe provider/client Futures on ownership receipt; report safe
  failed completion, seal intake and retain unconfirmed slot/channel ownership.
  Continue other cleanup and late observers; failed pause never resumes. Bound
  read/executor cleanup failures and retire connection metadata on errored lease
  completion. Add RAM regressions for settled/cancel/client/session failure,
  healthy peer drain and probe refusal; preserve normal native error mapping.

Completed ssh_io_review found1P2, not clean. T361 corrects the confirmed boundary
failure and amends the existing contract with failed-drain semantics; no product
role, wire/schema, retry, quota or native readiness is introduced. A successful
intermediate .local/ssh-io-drain-fixed-full.log is retained; final probe-regression
full/link checks and fresh independent review follow. T358–T360/T322 remain open.

T361 final post-fix evidence .local/ssh-io-reviewed-full.log EXIT0:
format369files/0changed; rootFlutter+5package analyses clean; root64+engine388+
MCP15+protocol20+Windows8=495Dart plus16PS RAMgroups =>510RAM+1static source scan.
Fifteen new RAM I/O cases now include errored provider drain, failed probe drain,
synchronous cancel/client/session-close failures, healthy-peer stop and denied
new read/executor after fatal pool seal, retained failed slot and denied resume.
Additional passing intermediate full logs retain probe/seal/handler steps; the
listed reviewed-full log covers the final source. Native provider forwards an
unexpected run/cleanup failure into its owned result/settled safe failure path;
field-only failure handler does not retain constructor credential arguments.
Key-worker/algorithm source remains unchanged; known native close normalization
is preserved. No Native workload was run. Final links and fresh independent
review/fix loop still precede acceptance; prior1P2 review was not a clean result.

- [x] T362 Fix confirmed remaining P2 from completed ssh_io_fixed_review:
  observe session.done immediately on execute handoff before pending stdin.close;
  known byte-session failure immediately fails its own public read/executor
  completion while remaining physical work stays owned. Add pending stdin-close
  with failed done and pending done with throwing close for both read/executor.
  Release retained provider/client handles only after positive complete drain,
  preserving native authentication-state lifetime after a closed lease.

Completed ssh_io_fixed_review confirmed the earlier general-provider fix but
found the remaining byte-session P2; it was not a clean result. T362 fixes that
confirmed case under the existing contract, without new product decisions.
Final .local/ssh-io-session-reviewed-full.log tools/test-unit.ps1 EXIT0:
format369files/0changed, rootFlutter+5package analyses clean; root64+engine391+
MCP15+protocol20+Windows8=498Dart plus16PS RAMgroups =>513RAM+1static source scan.
All18newRAM I/O cases pass. No targeted rerun or Native workload. Original
key-worker/algorithm source remains unchanged. Fresh links and third independent
review remain required; T358–T360/T322 and whole-goal readiness stay open.

- [x] T363 Fix confirmed P2 from completed ssh_io_session_review: propagate
  failed transport settlement through ConnectionReadWork/ConnectionExecutorWork
  and dependent refresh, read, executor and trust-probe completions. Start and
  observe all owned cleanup/proof/call drains despite the first error; publish
  only fixed SERVICE_UNAVAILABLE on failed drain, retain uncertain ownership
  and prevent registry resume. Add RAM regressions through the actual
  TrustedConnectionService and read refresh service. Complete mandatory full
  checks, links and a fresh independent review before accepting this fix.

The third completed review was not clean: transport settlement could throw from
connection wrappers' finally blocks, skipping their public done completion and
stranding service shutdown. T363 closes the dependent completion chain under the
already accepted T361/T362 failed-drain contract; it adds no product requirement.

T363 accepted after .local/connection-drain-full.log tools/test-unit.ps1 EXIT0:
formatter371/0changed; rootFlutter and all5package analyses clean;
root64+engine394+MCP15+protocol20+Windows8=501Dart plus16PS RAMgroups,
including3actual connection/read-service failure regressions. One existing
Dart test is a static source scan; other500Dart+16PSgroups are RAM.
.local/connection-drain-links.log lychee EXIT0:1476total/1475OK/0errors/1excluded.
Completed independent connection_drain_review:0findings; scoped implementation
readiness accepted for T357/T361/T362/T363 only. No Native/SSH/isolate/realFS/UI
workload or release qualification was run. T358–T360/T322 and whole-goal work
remain open; no new specification package, compatibility path or application
autostart was introduced.

T358 implementation: McpGrantKey is an owned repository return interface; the
existing private store holder retains the same open/revalidate/disposal body.
RemoteReadService owns one EngineClock (SystemEngineClock by default), passed
only at trusted composition; RemoteReadOwnerApi uses that same clock. Cache,
cursor, history and local observation receipt timestamps use it; parsed remote
system/metric/journal timestamps and CPU deltas remain unchanged. Operation,
proof, grant and session deadlines retain their independent existing clocks.
Six RAM units cover5s refresh/15s staleness,5min cursor,10min history,60s owner
handle boundaries and actual custody/HMAC key transfer/disposal.
First full .local/read-clock-full.log failed because the new test import prefix
was shadowed by its snapshot getter. Renaming the test-only import fixed the
compile error; .local/read-clock-targeted.log EXIT0 (6tests), run only after the
full failure. Fresh full checks, links and independent review precede acceptance.
This closes neither broad T359/T360 nor aggregate T322/native readiness.

T358 accepted: .local/read-clock-fixed-full.log tools/test-unit.ps1 EXIT0,
format373files/0changed, rootFlutter plus5package analyses clean;
root64+engine400+MCP15+protocol20+Windows8=507Dart, including1static source scan
and506RAM tests, plus16PS RAMgroups. All6newRAM cases pass.
.local/read-clock-links.log lychee EXIT0:1476total/1475OK/0errors/1excluded.
Completed independent read_clock_review:0findings, limited T358 implementation
readiness established. Native holder body except constructor name and operation
timer classes are unchanged by direct source comparison; no Native execution.
T359/T360/T322 and the remaining aggregate goal stay open.

- [x] T364 Implement the first T359 actual owner/MCP RAM read-service matrix:
  real bootstrap/grant-open/client+server HMAC and key disposal; healthy shared
  four-source refresh/poll reuse; per-interest cancel; revoked actor handoff
  with late physical drain; read/log/plan/server permission separation; stable
  principal/kind-bound owner handles; actual16per-principal/48total work and
  four-channel limits. Keep broader T359/T322 open for remaining identity,
  source-error, cursor/cache/history/ring and aggregate bounds acceptance.

T364 supplies a read-only validated schema3 RAM repository and actual domain
composition through declared ports. Owner/MCP sessions/contexts/authority, typed
owner adapter, MCP router/read+connection adapters, custody/HMAC, connection/pool,
byte capture and parsers are real; no successful domain output DTO is injected.
First .local/shared-reads-full.log full checks failed one new test: it awaited
cancel cleanup before releasing the shared source still needed by owner, thus
correctly reaching the unchanged5s cancellation deadline. Corrected concurrent
event ordering and the existing cancelled:true/FORBIDDEN-poll wire expectation.
.local/shared-reads-targeted.log EXIT0(8tests), run only after full failure.
Fresh complete checks, links and independent review precede T364 acceptance.
No production code/quotas/deadlines, native qualification or T359 closure claimed.

- [x] T365 Fix confirmed P2 from completed shared_reads_review: independently
  verify the48global work quota using a fourth admitted principal below its
  personal limit. Cancel a live interest while its physical proof is held and
  verify admission still refuses that fourth principal; after actual drain,
  verify fresh work is admitted. Preserve all existing per-principal assertions.

First shared_reads_review was not clean: the original3principals×16 case only
proved the personal quota. T365 adds independent global refusal, cancelled-work
retention and positive admission-after-drain criteria under the existing contract.
No product decision or production change. Fresh full/link checks and independent
review must pass before T364/T365 acceptance; T359/T360/T322 remain open.

T364/T365 accepted after .local/shared-reads-quota-full.log tools/test-unit.ps1
EXIT0: format375files/0changed, rootFlutter plus5package analyses clean;
root64+engine408+MCP15+protocol20+Windows8=515Dart(1static source scan,514RAM),
plus16PS RAMgroups. All8actual owner/MCP matrix units pass.
.local/shared-reads-quota-links.log lychee EXIT0:1476total/1475OK/0errors/1excluded.
Completed fresh independent shared_reads_quota_review found0findings and
confirmed closure of prior quota P2 in bounded T364/T365. No production code,
Native/SSH/Isar/OS/process/isolate/UI/build/install/deploy execution changed.
T359 remains open for profile/revision/identity and source-error isolation,
cache/cursor/history/ring and aggregate bounds; T360/T322 and whole goal open.

- [x] T366 Extend actual T359 RAM matrix with separately connected profile
  caches, reconciled revision/late-result/cursor retirement, partial/stale/denied
  observations without raw diagnostics,128cursor and8MiB cursor-byte bounds,
  history120/10min and inventory5min,500journal ring/duplicates, independent
  owner-handle16 retention, all five exact/overflow source capture limits,
  fitted1536KiB target cache and independent64MiB cache/journal aggregate budgets.
  Build multiple profiles through ordinary rows, complete receipt chains, actual
  schema3/custody validation and declared RAM read/publication boundaries.

T366 expands fixtures only; no production quotas/defaults or permission/deadline
policy is changed.16newRAM cases retain actual services/pool/parsers/custody.
The250profile cursor case reaches8MiB below128handles; cache uses72profiles and
journal uses3targets with507large records each, independently testing64MiB
rather than silently reducing limits. Source capture checks exact and one-byte
overflow for256KiB system/metrics,4MiB packages,2MiB units and8MiB journal.
First .local/read-bounds-full.log failed unused test import and invalid new
revision3 fixture without its required receipt; failed test also retained its
RAM target lease. Only that owned hung full process was stopped via its exec
handle, EXIT1; not a pass. Fixed complete receipt/cleanup, used complete system
source; .local/read-bounds-targeted.log EXIT0(7cases) after full failure.
Expanded .local/read-bounds-expanded-full.log failed two new budget tests because
empty catalog input was an untyped Dart map rather than the typed JSON object
contract. Corrected typed input; .local/read-aggregate-targeted.log EXIT0(2cases)
after that full failure, cache44s+journal15s RAM workloads. Fresh whole checks,
links and completed independent review precede T366 acceptance. T359 still
requires executor-backed read absence and its final whole-matrix assessment;
T360/T322 and remaining aggregate goal work stay open. No Native qualification.

- [x] T367 Fix confirmed P2 from completed read_bounds_review: keep an existing
  opaque cursor ID and mutate only its MAC to another well-formed32byte
  base64url value. First accept the original token in the same current session
  and filter; then require CURSOR_EXPIRED without another source execution for
  the altered MAC. Retain absent-ID, filter, principal and read-kind negatives.

First read_bounds_review was not clean: ID tampering alone could be rejected by
lookup with HMAC checking removed. T367 independently exercises signature
verification under the existing contract without production or crypto changes.
Fresh mandatory full checks, links and fresh independent review precede T366/
T367 acceptance; whole T359/T360/T322 and goal readiness remain open.

T366/T367 accepted after .local/read-bounds-mac-full.log tools/test-unit.ps1
EXIT0: format378files/0changed, rootFlutter plus5package analyses clean;
root64+engine424+MCP15+protocol20+Windows8=531Dart(1static source scan,530RAM),
plus16PS RAMgroups. All16newRAM cases pass, including finite real-size aggregate
cache/journal64MiB tests. .local/read-bounds-mac-links.log lychee EXIT0:
1476total/1475OK/0errors/1excluded. Completed fresh independent
read_bounds_mac_review:0findings, prior MAC P2 closed in bounded T366/T367.
No production code or Native/SSH/Isar/OS/realFS/process/isolate/UI/build/install/
deploy workload was changed or qualified. T359 remains open for executor-backed
read absence and final whole-matrix assessment; T360/T322 and whole goal open.

- [x] T368 Finish actual T359 read-policy acceptance: move the existing public
  enrollment read from extension dispatch to StateStore instance dispatch,
  retaining exactly its original queued metadata body and removing the old
  extension method/import. Supply the existing actual ExecutorEnrollmentStore
  over RAM protected files/custody/lease in the declared test repository port;
  do not expose write APIs or fake private native fields. Exercise owner and MCP
  absent-enrollment reads, cached unknown configuration/read-kind isolation,
  metadata cancellation/drain, last-waiter sampler retirement/suspend/resume,
  typed owner cancel, apply denial and session-detach handoff.

T368 is an internal read dependency extraction under accepted T356; the same
StateStore operation/name, native writer queue/metadata reader and wire/data
contracts remain. No fallback, native test branch, new context constructor or
compatibility facade. First .local/executor-read-full.log failed analysis on
imports made obsolete by instance dispatch and a new test unused type import;
its5new RAM cases passed but the full run is not a pass. Removed obsolete
production import and used explicit actual work type; after that full failure,
.local/executor-read-targeted.log EXIT0(6cases), including final-waiter physical
sampler drain. Three further acceptance cases now join the required fresh full
run: typed owner cancel, independent apply-scope denial and session detach.

T359 aggregate RAM evidence assembled for independent review (T359 remains
unchecked until that review completes; T360 and aggregate T322 remain open):

| Existing T359 criterion | Current real-service RAM evidence |
| --- | --- |
| Native I/O policy seams and2slots/4channels | ssh_io_policy_test.dart and ssh_pool_lifecycle_test.dart: real pool/reservations/leases, verifier, original deadline, late provider/client/channel drain; shared_reads_test.dart actual connection4channels and read48/16 |
| Current grant and owner authority | shared_reads_test.dart: actual schema3/custody, bootstrap, client/server HMAC, grant key disposal, owner admission and typed adapters; mcp_grant_handle_test.dart owned key versus current revoke |
| Healthy shared refresh and no polling replay | shared_reads_test.dart owner/MCP same4sources, repeated poll and cache reuse; read_clock_test.dart exact5s expiry |
| Typed start/status/cancel and foreign handles | shared_reads_test.dart stable principal/kind-bound owner handles; executor_read_absence_test.dart actual owner readCancel/repeat/foreign/late publication and MCP router cancel/poll |
| Actor handoff and detach/revoke | shared_reads_test.dart revoke with remaining owner and old physical work; executor_read_absence_test.dart session detach with unchanged grant and remaining owner |
| Profile/revision/read-kind and authority isolation | read_isolation_bounds_test.dart separate connected profiles, receipt-backed reconciled revision, old output/cursor retirement; shared_reads_test.dart read/log/plan/server scopes; executor_read_absence_test.dart read/plan cannot apply |
| Existing cache/cursor/receipt time policies | read_clock_test.dart exact5s/15s/5min/10min/60s under independent authority/operation clocks, remote observation times and CPU counters preserved |
| Source errors, stale/denied and safe errors | read_isolation_bounds_test.dart failed unknown/stale values, denied stderr and no raw diagnostic output; connection_drain_test.dart safe failed completion through actual services |
| Finite work/retention bounds | shared_reads_test.dart independent48global/16principal and no capacity release before proof drain; read_isolation_bounds_test.dart16owner handles and all5 source capture exact/overflow limits |
| Cache/history/inventory budgets | read_isolation_bounds_test.dart120points with121inside10min and inventory5min; read_aggregate_budget_test.dart1536KiB target and64MiB aggregate72profiles |
| Cursor/log budgets and bindings | read_isolation_bounds_test.dart live-ID MAC negative/positive control, filter/principal/kind/identity/expiry,128cursors independent8MiB/250profiles,500ring; read_aggregate_budget_test.dart separate64MiB journal budget3targets |
| Configuration/recipes preserve executor scope | executor_read_absence_test.dart actual metadata reader, owner and MCP EXECUTOR_UNAVAILABLE, unknown/unmanaged cached observation and independent state capture; no fake enrollment or privileged channel |
| Logical cancellation versus physical shutdown | ssh_io_policy_test.dart and connection_drain_test.dart provider/session/failed-close ownership; executor_read_absence_test.dart retained metadata and final shared sampler through suspend/resume without reconnect/replay |

All these are RAM/static acceptance, not Native/SSH/Isar/OS/process/isolate/UI,
real filesystem or release qualification. No UI/widget/design workload. Full
checks, links and independent full T359 matrix review still precede closure.

T368 final assertion audit adds3independent RAM checks before T359 review:
a grant revision alone invalidates an actual HMAC-open context with unchanged
current key/permission/lifetime and no revoke; isolated credential revision and
isolated trust revision invalidate a captured actual connection identity while
connection revision/key and the other credential/trust revision remain equal.
Both target snapshots use real schema3/custody loading and complete receipt3
under the real reconciled target lease, not private-state or context fabrication.
These cases close masked-guard coverage concerns; they do not add new policy.
The prior fixed-full run was green; these new cases require a fresh full run.

The fresh12case matrix-full run failed its new credential-only fixture because
CredentialRecord replacement is immutable: createdAt must equal updatedAt.
The schema3 loader correctly refused that invalid fixture. Fixed it to a new
credential ID/row, actual custody wrapper and matching replacement timestamps,
while connection/trust revision and host key remain unchanged. After full
failure, .local/executor-read-matrix-targeted.log EXIT0(12cases). No production
validation was relaxed; the corrected fixture passes the real loader. A final
fresh full suite and independent full T359 review remain mandatory.

T359/T368 accepted after .local/executor-read-final-full.log tools/test-unit.ps1
EXIT0: format379files/0changed, rootFlutter plus5package analyses clean;
root64+engine436+MCP15+protocol20+Windows8=543Dart(1static source scan,542RAM),
plus16PS RAMgroups. All12new cases pass. .local/executor-read-final-links.log
lychee EXIT0:1476total/1475OK/0errors/1excluded. Completed independent
read_matrix_completion_review:0findings, inspected current whole T359 assertions
and contracts and established bounded T368 plus RAM-matrixT359 readiness.
T359 checkbox is now closed on that criterion-by-criterion evidence, not merely
aggregate green counts. Static .local/executor-read-static.json confirms the
queued read body, remaining metadata writes/StateStore and executor body are
unchanged except the intended method move and obsolete import removal.
T360 and aggregateT322 remain open. This does not qualify Native/SSH/Isar/OS/
realFS/process/isolate/UI/build/install/deploy or a release. Whole goal active.

T360 implementation assembled for independent acceptance; checkbox remains open
until full checks and review. New root owner_snapshot_policy_test.dart runs the
actual EngineApiClient/EngineClient, InProcessGateway, HostAuthority/EngineSessions,
TrustedFoundationOwnerApi, MutationCoordinator and declared RAM StateStore with
validated schema3/custody. It shares actual RemoteReadService/owner/MCP sampler
from T359. Scheduler controls callbacks; TraceGateway only delegates/records real
calls and can delay captured real replies or inject a declared boundary timeout.
No successful list/settings DTO is synthesized and no writer/DB transaction API
is faked. The mutation fault is before writer admission: it verifies controller
no-resubmission policy, not a committed effect or native durability claim.

| T360 criterion | New actual-pipeline RAM assertion |
| --- | --- |
|2s snapshots and no collector restart | Four list/settings cycles from real coordinator, one immutable revision2 publication, one attachment, no SSH source calls;2s poll and20s heartbeat callbacks remain distinct |
| Shared in-flight reads | Repeated start/refresh shares one captured profiles read, one settings read and one active scheduled poll |
| Coherent snapshot | Real validated settings/receipt revision3 is published between actual list and settings replies; torn2/3 frame is suppressed; next poll publishes matching3/3 |
| UI/MCP share sampler | Actual typed owner start and HMAC-open MCP refresh share one4source group while2s snapshots run; fresh cache prevents repeat and explicit expiry5s allows only the next system/metrics collector |
| Retired epochs | Stopped poll and its stale callback cannot publish captured old data or schedule attachment; no late snapshot error |
| Actual generation replacement | Old real gateway/root closes after capture, a new real HostAuthority/gate/session generation attaches, delayed old reply/error is discarded and only new generation snapshot publishes |
| No mutation replay | Caller-owned stable UUID intent gets one declared gateway TIMEOUT; three actual read polling cycles never resubmit or admit the writer; state stays revision2 |

RAM Gate/Runtime fixture defaults preserve all existing tests, with explicit
new generation parameter for a new actual host incarnation. Repository custody
assertion checks original actual key/custody identities for coordinator creation.
No production client, gateway, mutation/read policy, timer or model code changed.
Initial .local/snapshot-policy-full.log failed new root test enum/import errors
and missing root package:test resolution for reused engine fixtures; not a pass.
Corrected to existing Local API TIMEOUT rather than adding a protocol code.
First targeted compile also failed missing package:test. Added exact dev pin
1.31.1 already used in engine, resolved with flutter pub get --offline EXIT0.
All existing lock versions are retained except dev-only package_config3.0.0→
2.2.0 required by that existing test toolchain;24new test-transitive entries.
Actual flutter pub deps --no-dev output excludes package_config/test/test_core:
no production dependency or runtime pin changed, no override/upgrade introduced.
.local/snapshot-policy-targeted-ready.log EXIT0(7cases), run after full failure.
Fresh full checks, links and independent T360/T322 aggregate review remain
required. T360/T322 and whole goal are still open; no Native/UI/design execution.

T360 and aggregateT322 RAM parity accepted after
.local/snapshot-policy-fixed-full.log tools/test-unit.ps1 EXIT0: format380files/
0changed, rootFlutter plus5package analyses clean; root71+engine436+MCP15+
protocol20+Windows8=550Dart(1static source scan,549RAM) plus16PS RAMgroups.
Seven actual-pipeline root cases pass. .local/snapshot-policy-links.log lychee
EXIT0:1476total/1475OK/0errors/1excluded. Completed independent
snapshot_policy_review:0findings, inspected current assertions and contracts,
confirmed both T360 and aggregateT322 accepted T356 RAM criteria complete.
Checkboxes close on that full chain, not merely aggregate green counts.
Production client remains unchanged by exact baseline comparison; devdependency
and generation fixtures do not introduce a runtime mode, writer API or native
claim. Native/SSH/Isar/OS/realFS/process/isolate/UI/design/build/install/release
qualification remains unperformed. Other aggregate goal tasks remain open;
this is not whole-feature or whole-goal completion.
## T323 actual transactional storage dependency — 2026-10-31

Direct IsarCollection access prevents the existing read-only RAM repositories
from proving positive mutation routes. Refine the accepted T323 requirement in
place under FR-SVC-EMB-07/14/15, AC-SVC-EMB-07 and SC-SVC-EMB-03; retain every
completed task and the separate remaining acceptance tasks. See the
[contract](contracts/embedded-engine.md#t323t369t373--transactional-storage-dependency-2026-10-31),
[plan](plan.md#t323-storage-dependency-refinement--2026-10-31) and
[research decision](research.md#t323-actual-mutation-tests-persistence-boundary--2026-10-31).

- [x] T369 Review the existing-package transactional dependency design after
  lychee passes. Independent read-only AGENTS.md reviewer must inspect current
  code and this contract for a complete requirement→decision→contract→task→RAM
  acceptance chain. No code handoff until confirmed mandatory gaps are fixed
  and a fresh completed review is clean. This is design scope, not T323 parity.
- [x] T370 Implement storage/workspace_storage.dart and storage/isar_storage.dart
  in packages/serverdeck_engine: fixed16-family enum, scoped transactional rows,
  explicit IDs/unique entity keys, Isar class mappings, exact pinned options,
  owned per-open attempt and conservative memoized close. Factor the current
  preflight common semantic/enrollment checks without weakening native byte
  preflight or allowing unchecked snapshot attachment. Verify static mapping/
  ownership and new RAM port cases; do not execute native Isar.
- [x] T371 Refactor StateStore.open and all foundation/profile/plan/grant/delta
  writes and snapshot reloads to that single owned dependency. Preserve actual
  common ownership/runtime checks, queue32, HMAC/idempotency/CAS, current row
  IDs/payloads, credential staging, policy/proof fences, readback and publication.
  Remove the replaced direct native access rather than retain a second path.
  Unknown open/close/write retains reservation/custody as contracted. Production
  root keeps the Native provider and exposes no wire/config provider choice.
- [x] T372 Add test/support-only transactional RAM storage with captured-byte
  decoding, atomic rollback, unique indexes and scoped lifetimes. Exercise the
  actual StateStore with actual fixture custody/lease/files/runtime: normal
  mutation families and exact resulting rows/receipts; pre/post mismatch,
  incompatible/invalid graph, wrong custody, capacity with actual prior-snapshot
  proof, callback/policy failure, late/escaped transaction and failed/unknown
  open/close. Full current unit/static checks and independent review are required;
  RAM results do not prove native durability, DB layout or OS close.
- [x] T373 Complete T323's actual24-tool matrix through real MCP authentication,
  router/domain services and the actual T371 StateStore over T372 RAM storage.
  Map each catalog tool to positive and denied assertions; check every scope/
  allowed target, expired/revoked grant, private owner forgery, input/schema,
  idempotency IDs, safe fixed errors and proof-to-effect/publication fences.
  Real remote command/framing/parser policy uses declared byte transport ports;
  no scripted domain-success handler. Run full checks, links and independent
  review before closing T373 or aggregate T323. T324/T325/T331 remain separate.

T369 design amendment assembled; link checks and completed independent review
are pending. T370–T373 and T323 remain open. No code, runtime mode, persisted
format, dependency, Native/Isar/FS/SSH/process/isolate/UI/design/build/install or
release behavior was executed or qualified by this document change.

T369 accepted: .local/transaction-storage-links.log lychee EXIT0,1483total/
1482OK/0errors/1excluded. Completed independent read-only
transaction_storage_design_review:0findings; bounded design readiness for
T370–T373 established, not implementation or T323 completion. Static document
audit confirmed all16 declared collection families match current IsarRowSource
and all6 changes preserve prior history. Native runtime/Isar/realFS/SSH/process/
isolate/UI/design/build/install/release checks were not performed. Production
code is unchanged. T370–T373, T323 and the whole goal remain open.

T370 implementation assembled for independent review: new workspace_storage.dart
fixed16-family port, shared transaction lifetime/abort/close mechanics and
isar_storage.dart pinned production adapter with attributable per-open cleanup.
preflightWorkspace delegates to the common lazy source/semantic/enrollment gate;
its native-byte parser still runs after owner checks. Test/support RAM row
backend exercises actual shared mechanics in14 new unit cases: all16 families,
exact payload/IDs, callback rollback, case-sensitive unique keys/caught failure,
max native ID/update/delete, invalid shape, expired scope/read zone, nested
transaction denial, pending unawaited operation abort/drain, coherent queued
read, close sealing/drain/false/throw memoization and capacity candidate. It is
not a fake StateStore or a successful domain handler. Captured-byte RAM provider
and actual StateStore/MCP integration remain T371–T373, not claimed here.

.local/transaction-port-full.log tools/test-unit.ps1 EXIT0: format384files/
0changed, rootFlutter plus5package analyses clean; root71+engine450+MCP15+
protocol20+Windows8=564Dart(1static source scan,563RAM) plus16PS RAMgroups.
No targeted tests were run. .local/transaction-port-static.json records a source
audit matching all16 adapter classes to current IsarRowSource, explicit ID/
payload/entity conversion and pinned open options. An initial audit regex did
not account for formatter line wrapping and failed; corrected whitespace-aware
audit passed. This is static evidence, not executed native I/O. No Native/Isar/
realFS/SSH/process/isolate/UI/design/build/install/release qualification. T370
checkbox stays open until links and a completed independent review.

T370 first completed transaction_port_code_review found2P2 defects. Accepted
against current code/SDK: a write scope checked storage identity but not its
original transaction context; public async read created a second unobserved
Future for abandoned failed reads. T370 stays open; first green checks do not
close the review loop. Record fixes without erasing the completed design/task
history:

- [x] T374 Bind each write scope to its exact originating transaction context;
  reject a reference used from another concurrent read/write context before
  backend access. Extend the RAM backend with coherent concurrent read snapshots
  and assert foreign-context rejection plus full rollback of the original write.
- [x] T375 Return the observed public read Future directly; add a held RAM read
  that fails after callback settlement and verify transaction abort/drain with
  no uncaught zone errors. Preserve all previously checked operation lifetimes.

T374/T375 fixes assembled;16RAM port cases now include genuine concurrent read
snapshot isolation, foreign-active-context rejection and late abandoned read
failure. Fresh complete checks and fresh independent review are required before
acceptance. No new architecture/product decisions or native workloads added.

T374/T375 fresh complete checks: .local/transaction-port-fixed-full.log
tools/test-unit.ps1 EXIT0, format384files/0changed, rootFlutter+5package analyses
clean; root71+engine452+MCP15+protocol20+Windows8=566Dart(1static565RAM)
plus16PS RAMgroups.16port unit cases pass; no targeted tests run.
.local/transaction-port-fixed-links.log lychee EXIT0:1483total/1482OK/0errors/
1excluded. Initial green T370 checks remain historical; acceptance requires the
fresh completed independent review of current fixes.

Second completed transaction_port_fixed_review confirmed T374/T375 fixes but
found1remainingP2: outer read/count scope stayed active while inner write scope
drained an abandoned put after callback settlement. T370 remains unaccepted.

- [x] T376 Use one operation scope for write callback and public read/count.
  On callback settlement expire all new row admission together while retaining
  already-started physical operations until drain. Extend held unawaited-put
  regression with saved callback zone: late count/read reject with unchanged
  backend-call counters before hold release; original write fully rolls back.

T376 fix assembled by replacing nested scope lifetimes with one shared write
operation scope. Existing16RAMcases now include no backend access from expired
read/count during mandatory write drain. Fresh full checks/links and another
completed independent review remain required. No native workloads executed.

T376 fresh complete checks: .local/transaction-port-scope-full.log
tools/test-unit.ps1 EXIT0, format384files/0changed, rootFlutter+5package analyses
clean; root71+engine452+MCP15+protocol20+Windows8=566Dart(1static565RAM)
plus16PS RAMgroups. All16port cases pass including expired saved-zone read/count
no-backend-access assertion before abandoned-put drain. No targeted tests run.
.local/transaction-port-scope-links.log lychee EXIT0:1483total/1482OK/0errors/
1excluded. Final fresh independent review still required; T370/T374–T376 open.

T370/T374–T376 accepted after completed independent transaction_port_scope_review:
0findings, bounded implementation readiness established against current
contract/source/assertions. Final mandatory full evidence remains
.local/transaction-port-scope-full.log EXIT0(format384/0changed; all analyses;
566Dart including16new RAM port cases,16PS RAMgroups). No targeted tests run.
Latest recorded-link run initially failed only an existing pub.dev version URL
with HTTP502; .local/transaction-port-scope-recorded-links-retry.log then passed
EXIT0(1483total/1482OK/0errors/1excluded), with no exclusions or URL changes.

Earlier2+1review findings are fixed and the whole applicable review loop is now
clean. Native adapter mappings/options and ownership were inspected statically;
no native/Isar/realFS/SSH/process/isolate/UI/design/build/install/release behavior
was executed or qualified. T371 StateStore integration, T372 captured-byte RAM
provider/actual mutations, T373 full24-tool matrix and aggregate T323 remain
open, as do the other goal tasks. This closes the storage dependency step, not
the full requested refactor or whole feature.

T371 implementation assembled for independent acceptance: StateStore.open uses
the checked WorkspaceStorageProvider dependency (default pinned Isar), one owned
WorkspaceStorage and attributable attempt cleanup. Common owner/root/runtime/
manifest/wrapper/lock/enrollment/preflight/post-open equality/recovery ordering
remains in StateStore. Uncertain failed-open attempt is retained together with
the writer reservation. Foundation/profile/plan/grant/delta row operations and
all actual snapshot reloads now use the one storage dependency; replaced direct
IsarCollection/IsarRowSource/_isar/_writeNative paths are removed from those
parts. Explicit returned native IDs are checked for equality. No wire/config
provider choice, unchecked attach or alternate domain implementation was added.

T372 partial evidence is now available without closing its full matrix:
test/support memory_workspace_provider.dart decodes captured synthetic bytes
and independently reopens from the current RAM byte store. The actual common
StateStore checks validate manifests/keys/semantic graph and exact pre/post rows.
RAM storage commits persist synthetic bytes and close releases only its owned
RAM handle.10new actual_state_store_test cases exercise real StateStore with
actual fixture custody/protected files/lease/runtime, actual coordinator and
typed commands:16-family ID/payload adoption; invalid captured bytes; exact
payload change before open; settings HMAC/receipt/replay/conflict; profile create/
update/archive/CAS/retained revisions; denied read-only grant before row write;
grant publication/revoke/key rejection; delegation create/revoke through common
delta; capacity with actual full prior-graph readback; post-commit runtime-proof
failure that blocks rather than claiming rollback, then checked reopen retaining
the committed receipt. These prove domain/persistence behavior in RAM, not wire
authentication for all tools or native byte/OS/durability qualification.

Initial .local/actual-store-full.log tools/test-unit.ps1 EXIT1: a new revoked-key
expectation used FORBIDDEN but the unchanged current-key contract returns
UNAUTHORIZED. Corrected the test to existing behavior; no production auth error
was changed. An attempted targeted command had a wrong log-relative path and
did not execute tests; it is not a pass. Actual subsequent
.local/actual-store-targeted.log dart test actual_state_store_test.dart EXIT0
(10cases), only after the full failure. Fresh full checks are pending.
.local/actual-store-static.json records exact unchanged _ensure/runtime proof/
custody binding bodies, snapshot reload with only its source dependency changed,
and no direct _isar/_writeNative references in changed store parts. This is
source evidence only. T371/T372/T373/T323 and whole-goal acceptance remain open.

The first fresh full run after the expectation fix
(.local/actual-store-fixed-full.log) completed tests/analyses successfully but
failed the repository formatter on the edited test indentation; not a pass.
Formatted that test, then .local/actual-store-final-full.log tools/test-unit.ps1
EXIT0: format386files/0changed, rootFlutter+5package analyses clean; root71+
engine462+MCP15+protocol20+Windows8=576Dart(1static575RAM) plus16PS RAMgroups,
including all10new actual-store cases and all16accepted port cases.
.local/actual-store-links.log lychee EXIT0:1483total/1482OK/0errors/1excluded.
T371 and partialT372 changes now await independent review before acceptance.
No Native/Isar/realFS/SSH/process/isolate/UI/design/build/install/release execution.

T371 accepted after completed independent actual_store_integration_review:
0findings, bounded readiness for the integration and presented partialT372
evidence established from the actual source/assertions and accepted contract.
Final gate .local/actual-store-final-full.log EXIT0: format386/0changed, all
applicable analyses,576Dart(1static575RAM) plus16PS RAMgroups; all10actual-store
and16port cases pass. .local/actual-store-recorded-links.log lychee EXIT0:
1483total/1482OK/0errors/1excluded. Native default composition and removed direct
store access were inspected; no native execution or whole-feature claim.

T372 remains open for its complete normal/failure/boundary mutation matrix,
including the remaining plan/job/progress/approval paths and uncertain open/close
retention cases; T373 actual24-tool positive/denied authorization matrix and
aggregateT323 remain open. T324/T325/T331 and other goal tasks retain their own
acceptance. No Native/Isar/realFS/SSH/process/isolate/UI/design/build/install/
release qualification. This is the completed StateStore dependency refactor,
not whole-goal completion.

T372 remaining RAM matrix assembled: five new test/support files and controlled
RAM-provider/backend fault hooks; no production code, schema, protocol, package
pin or runtime/config mode changed. actual_plan_fixture uses the real compiler,
strict preflight/plan DTO parsers and actual stored revision/target identities.
Its synthetic structural preflight is NOT a verified executor response or
permission for remote execution. Tests call the existing trusted StateStore
metadata primitives; no successful remote/domain service DTO is scripted. Full
MCP actor/auth/root framing acceptance remains T373.

| T372 acceptance | Actual current-task evidence |
| --- | --- |
| Mutation families | Existing10 actual-store cases plus new plan persistence/replay/TTL/blocked history, approvals and atomic consumption, canonical job aliases/replay, job progress/CAS/events/desired state/success+reopen, queued cancel, unknown occupancy/reconcile, foundation profile/credential create/rotate/delete and trusted-target edit revoking trust with retained native ID, grant secret/policy replacement |
| Permission before effect | Real grant expires in actual writer callback; no extra backend put/commit; actual prior snapshot restored and FORBIDDEN returned |
| Bounds/concurrency | Actual32 pending profile writes, shared duplicate future,33rd rejected without commit; admitted work drains before positive close/reservation release |
| Readback failures | Existing actual capacity→prior graph proof and postcommit runtime-proof failure; new failed rollback readback blocks instead of claiming RESOURCE_LIMIT |
| Checked open | Existing actual exact pre/post rows and invalid captured bytes; new schema2/orphan credential/wrong wrapper leave bytes unchanged and never open writer; known pre-owning failure cleans once then checked retry |
| Uncertain ownership | Separate terminal unit files exercise actual StateStore with unknown no-handle open and false close; reservation/key/lease retained, next open blocked and close memoized, without any production reset escape |
| Transaction mechanics | Existing16 accepted port RAM cases cover rollback/unique IDs/indexes/singletons/exact payloads/late and foreign scopes/unawaited drain/close outcomes; actual-store suites execute the real common loader/custody and domain callbacks |

Terminal ownership cases run as ordinary unit files under the existing Dart test
runner; no explicit engine/worker isolate or native process fixture is dispatched.
Each file intentionally leaves its synthetic reservation retained; no StateStore
reset, force-close or private-field assignment is introduced. Fixture teardown
only disposes synthetic RAM test data; these cases do not qualify production OS
handle closure, durable native rollback or Host-level native retention.

Initial .local/store-matrix-full.log tools/test-unit.ps1 EXIT1: new plan fixture
had an invalid trailing comma after a named-parameter group (formatter/analysis/
load failure); new profile test incorrectly expected accepted trust immediately
after creation. The former was corrected after that run had captured its parse
errors. The latter now asserts no confirmed key and exercises a real existing
trusted-target edit to cover actual trust-row writes/revocation. Initial targeted
retry then exposed missing ProfileRecord getters in the new test; corrected to
its existing toJson fields. .local/store-matrix-targeted-fixed.log EXIT0(15new
cases), only after the completed full failure. Added2further real grant replacement/
writer-expiry cases and launched fresh full checks; no pass claimed before exit.
T372 remains open until full checks, links and independent aggregate review.

T372 fresh full gate .local/store-matrix-fixed-full.log tools/test-unit.ps1
EXIT0: format391files/0changed, rootFlutter+5package analyses clean; root71+
engine479+MCP15+protocol20+Windows8=593Dart(1static592RAM), plus16PS RAMgroups.
All17new matrix cases,10actual-store cases and16port cases pass.
.local/store-matrix-links.log lychee EXIT0:1483total/1482OK/0errors/1excluded.
Independent aggregateT372 review remains required before closing that task.
All application production files remain unchanged in this matrix increment.

T372 accepted after completed independent store_matrix_completion_review:
0findings. The reviewer inspected all17new cases plus previous10actual-store/
16port/preopen/snapshot assertions and current source, and established aggregate
T372 RAM/static readiness against the accepted T369 contract. Acceptance is
not inferred from counts or prior review conclusions alone. Final full evidence
.local/store-matrix-fixed-full.log EXIT0: format391/0changed, rootFlutter+5package
analyses clean,593Dart(1static592RAM) plus16PS RAMgroups.
.local/store-matrix-recorded-links.log lychee EXIT0:1483total/1482OK/0errors/
1excluded. Production application code is unchanged by this matrix step.

Synthetic structural preflight/driver outcomes prove StateStore persistence,
not qualified remote facts or actual execution authority. T373 actual24-tool
positive/denied router/domain/framing matrix and aggregateT323 remain open.
T324/T325/T331 and other goal tasks keep separate acceptance. No Native/Isar/
realFS/SSH/process/engine-isolate/UI/design/integration/build/install/release
qualification; this is not whole-feature or whole-goal completion.

## T373 production MCP composition and first parity stage — T377

- [x] T377 Establish actual TrustedControlServices factory over the accepted
  actual StateStore/RAM storage, real HostAuthority/EngineSessions and two-stage
  bootstrap/grant HMAC. Verify literal24-tool catalog and policy/schema/owner/
  allowlist/expiry/revoke denials; positive seven author and six inventory/
  connection/state/log tools; committed mutation publication-proof loss and
  explicit stable-ID replay. Complete full checks/links/independent review for
  this prerequisite. Keep T373/T323 open until the other11positive executor/
  plan/approval/apply/job routes and their fences are accepted.

T377 implementation assembled: actual_mcp_setup composes the production factory
with real StateStore, custody/key/lease, protected metadata, HostAuthority,
EngineSessions, router and services. Only verified platform proofs/SSH byte I/O
are RAM ports. There is no repository noSuchMethod facade, scripted router or
successful domain response. Bootstrap and grant transcripts use real HMACs and
verify the returned server MAC. Valid source bytes run real SSH captures/parsers.

11new tests currently cover:
- Literal24-tool catalog; empty policy denies all24 before effects; six explicit
  valid policy lattice rows compare expected tool names and deny each missing
  required scope. Clients disconnect between rows, preserving the real4MCP limit.
- Each24tool has otherwise valid minimal arguments established before adding
  forbidden owner field; returns only protocolError -32602, zero new commits/SSH
  or charged operations. Direct MCP SessionRequest cannot enter owner prepare.
- Allowlist denial before missing-target lookup, actual stored revocation and
  expired-grant refusal despite a real protected-key proof, with actual authority
  close/drain before asserting no retained open work.
- All7profile tools over actual catalog/store, persisted caller/grant IDs, revisioned update,
  canonical digest, retained revisions, stable-ID replay and conflict; no SSH.
- Inventory/get/connect/state/log/disconnect: exact target/profile, connected
  state, parsed known hostname/packages and journald record; five exact read
  source kinds over one transport, no domain storage write beyond grant setup.
- Actual peer-proof failure after a committed profile suppresses ACK with fixed
  UNAUTHORIZED. Receipt survives, no automatic resubmission; a new authenticated
  peer's explicit same-ID request returns the retained result without a second
  commit. No wire success/authority is synthesized.

This is13positive tools plus denied/catalog coverage of24, not full24positive
parity. configuration_get,recipes_list,plan_create,plans_get,approval_request,
apply,jobs_list,jobs_get,jobs_events,jobs_cancel,jobs_reconcile remain positive
executor/framing stage work under T373. Existing15scripted gateway cases and
T372 structural metadata tests do not close those routes. No new specification
package or runtime mode, production code/dependencies unchanged.

Initial .local/mcp-router-full.log full checks EXIT1: policy loop exceeded the
real4MCP-session limit by retaining6clients, and expired-open test observed
cleanup counter before physical drain. Corrected fixture/client lifecycle,
not production bounds; first targeted mcp-router-targeted.log EXIT0(10cases),
only after full failure. Strengthened schema isolation/read semantics and added
publication loss/replay; next .local/mcp-router-fixed-full.log EXIT1 from a missing
operations.dart import in new test. Corrected import after its errors were
captured, then .local/mcp-router-targeted-fences.log EXIT0(11cases), after full
failure. Fresh complete checks are now running; no pass claimed before exit.
T377/T373/T323 remain open; no native/platform/remote execution qualification.

T377 fresh full checks .local/mcp-router-final-full.log tools/test-unit.ps1
EXIT0: format394files/0changed, rootFlutter+5package analyses clean; root71+
engine490+MCP15+protocol20+Windows8=604Dart(1static603RAM) plus16PS RAMgroups.
All11new actual-router cases pass. .local/mcp-router-links.log lychee EXIT0:
1483total/1482OK/0errors/1excluded. Current bounded T377 prerequisite awaits
independent review; T373/T323 remain open for the full executor-backed matrix.
No production changes, Native/Isar/realFS/SSH/process/engine-isolate/UI/design/
integration/build/install/release qualification by this increment.

T377 accepted after completed independent mcp_router_stage_review:0findings.
Actual factory/auth/store/router/domain assertions establish this prerequisite,
not the complete T373/T323 matrix. Final full evidence
.local/mcp-router-final-full.log EXIT0: format394/0changed, current app/package
analyses clean,604Dart(1static603RAM) plus16PS RAMgroups;11new cases pass.
Formatter warnings resolving lint includes in the separate historical
work/isar-encryption-implementation are not claimed absent or qualified.
.local/mcp-router-recorded-links.log lychee EXIT0:1483total/1482OK/0errors/
1excluded. No application production code changed by T377.

T373/T323 stay open for11positive executor-backed routes listed above, their
actual framing/parsers/command policy and remaining effect/publication fences.
T324/T325/T331 and other whole-goal acceptance tasks remain separate. No Native/
Isar/realFS/SSH/process/engine-isolate/UI/design/integration/build/install/release
qualification. The full objective remains active and incomplete.


## T373 actual framed executor stage — 2026-10-31

- [x] T378 Fix confirmed plan receipt ordering defect: plan compilation and
  later storage admission use distinct instants. The retained loader must
  accept createdAt >= plan.createdAt with exactly one exact-request creation
  receipt, preserving digest/origin/target authority and readback validation.
  Actual RAM StateStore persistence, reopen/replay and earlier/wrong-request/
  wrong-digest/duplicate graph rejection regressions; full checks and review.
- [x] T379 Establish the positive24-tool prerequisite of T373 through actual
  factory, owner inspect/challenge/confirm enrollment, HMAC MCP authentication,
  router/domain services and StateStore. A declared RAM byte peer supplies
  fragmented executor envelopes through actual SSH pool/framing/response parsers;
  no domain-success stub. Verify real plan/preflight/compiler comparison,
  approval, per-step authorization, success/desired-state, cancel, unknown and
  reconcile, explicit same-ID apply without another submit. Source release and
  root journal/effects are declared RAM models, not platform qualifications.
  Full checks, links and independent review before acceptance.

Initial .local/mcp-executor-full.log EXIT1 and subsequent diagnostic runs expose
an actual plan loader mismatch: creation() required equal plan/receipt times,
although persistence validates at a later instant. Fixed in snapshot.dart;
publication/authentication checks are unchanged. Deterministic regression first
exposed duplicate plan receipts under different request IDs; exact-one plan
creation receipt now closes that gap too. Targeted runs occur after the full
failure. Owner approval request ID and nested jobs-list expectations were also
corrected in the new fixture, without changing production wire contracts.
T373/T323 remain open for the remaining negative effect/publication fences.
No Native/Isar/realFS/SSH/process/explicit engine-isolate/UI/design/integration/
build/install/release qualification. Existing specification amended in place.


T378/T379 fresh full checks .local/mcp-executor-fixed-full.log EXIT0:
format397files/0changed, Flutter and all5package analyses clean; root71+
engine496+MCP15+protocol20+Windows8=610Dart cases(1static609RAM), plus16PS RAM
groups. Engine includes the new actual24-tool scenario and5receipt regressions.
.local/mcp-executor-links.log lychee EXIT0:1483total/1482OK/0errors/1excluded.
Formatter warnings from the separate historical worktree's lint include remain
outside this scope. Independent review is pending; T378/T379 are not accepted
yet. T373/T323 remain open and no platform/release readiness is claimed.


- [x] T380 Close confirmed independent-review finding in T378 wrong-request
  regression: change both receipt row.entityId and document.requestId together,
  retaining the plan's original requestId. This valid row identity must reach
  the exact plan-request guard and fail STORAGE_BLOCKED there, rather than
  passing only because of a malformed receipt row key. Fresh full checks and
  fresh independent review required; no production contract change.

Completed executor_positive_stage_review found1P2: the wrong-request regression
previously failed the earlier row/document identity check, leaving the intended
plan-request guard unprotected. T380 corrects only the fixture. T378/T379/T380
remain pending acceptance; no clean review or full T373 completion claimed.


The first attempted T380 replacement did not match formatted indentation; the
subsequent .local/mcp-executor-review-fixed-full.log run tested the unchanged
fixture and does not close T380. Corrected the exact line only after that run
completed; a new full run supplies the post-fix evidence.


T380 post-fix full .local/mcp-executor-final-full.log EXIT0: format397/0changed,
Flutter+5package analyses clean; root71+engine496+MCP15+protocol20+Windows8=
610Dart(1static609RAM), plus16PS RAMgroups. Corrected wrong-request graph case
passes only with mismatched plan/receipt request identity while receipt row and
document IDs agree. Fresh independent review pending; T378/T379/T380 not yet
accepted. .local/mcp-executor-final-links.log lychee EXIT0 1483/1482OK/0/1excluded.


T378/T379/T380 accepted after completed fresh independent
executor_positive_fixed_review:0findings. The previous1P2 regression finding is
closed by consistent receipt row/document IDs with a different plan request ID.
Final .local/mcp-executor-final-full.log EXIT0: format397/0changed, clean current
Flutter+5package analyses,610Dart(1static609RAM)+16PS RAMgroups.
.local/mcp-executor-review-ready-links.log EXIT0:1483total/1482OK/0errors/1excluded.
This accepts the positive24-tool prerequisite and receipt-order fix only.
T373/T323 remain unchecked for remaining negative effect/publication fences;
T324/T325/T331 and other whole-goal tasks remain open. No Native/platform/remote
Python executor/storage durability/UI/design/integration/build/install/release
qualification, and no new specification package or compatibility path.


## T373 negative effect/publication boundary stage — 2026-10-31

- [x] T381 Extend actual factory/HMAC/router/domain/StateStore RAM parity with
  corrupted executor preflight digest/compiler effects/target; blocked retained
  plans cannot request approval. Lose peer proof or revoke grant during pending
  preflight: no plan receipt/effect/ACK. Lose proof after plan commit: retained
  receipt supports explicit same-ID replay without another preflight or commit.
  At accepted submit/status boundaries, lost proof, foreign status or lost submit
  ACK must retain unknown, no step permit/effect, no resubmit on explicit replay.
  Inject only through declared RAM byte reply hook; no domain handlers/authority
  bypass. Full checks/links and independent review required. This does not close
  T324 overlay/recovery or T331 complete occupancy matrix by implication.


T381 also closes the previously uncovered inferred-target/object-origin policy
rows: retained known plan/job IDs under another full-scope grant, and the same
grant after target removal with fresh protected-key authentication. plans_get,
approval_request, apply, jobs_get/events/cancel/reconcile must return FORBIDDEN;
unfiltered jobs_list must hide these jobs. Assert no metadata write/root request/
step permit and no disclosed forged preflight effect diagnostic. These scenarios
use actual records and policy, not missing-object denial or synthetic handler ACK.

Initial .local/mcp-fences-full.log EXIT1 (8new cases failed): fixture omitted the
MCP client's explicit server_connect, so root preflight never ran. Corrected the
fixture and nested tool-error assertion without changing production connection
ownership or contracts. Only after that full failure,
.local/mcp-fences-targeted.log EXIT0:9new cases. Added2object-policy cases after
the coverage audit; fresh full checks follow. Production code unchanged.


The second full .local/mcp-fences-fixed-full.log EXIT1 caught an invalid fixture:
read/plan/apply grants require a nonempty target set. For target removal, create
an actual second foundation target through owner profiles.create, then replace
the grant's target set with that target (keep scopes). The inferred original
plan/job target is denied, while servers_list shows only the new allowed target.
After full failure .local/mcp-fences-object-targeted.log EXIT0:11cases. Added a
post-submit revoke-before-step case: owner observes unknown; the revoked client
cannot replay or reopen. No next step permit/root effect/submit; no implicit
cancel or reconciliation. This supplements preflight revocation with an already
accepted remote attempt and does not claim full occupancy release coverage.


T381 final full .local/mcp-fences-final-full.log EXIT0: format398/0changed,
Flutter+5package analyses clean; root71+engine508+MCP15+protocol20+Windows8=
622Dart(1static621RAM) plus16PS RAMgroups. All12new fence/policy cases pass.
.local/mcp-fences-final-links.log lychee EXIT0:1483total/1482OK/0errors/1excluded.
Formatter warnings for lint includes in the separate historical worktree are
outside qualification. Current application production code is unchanged.

T373/T323 aggregate evidence map, pending independent assessment:
- actual_router_policy_test.dart: literal24catalog and independent scope-lattice
  expectations, empty/missing scopes, all24 validated argument shapes plus owner
  forgery field, explicit target denial, private owner invocation denial,
  revoked session and valid-MAC expired grant open denied.
- actual_router_profiles_test.dart: actual profile CRUD/revisions/conflict/replay,
  known inventory/read parsing, commit-before-proof-loss and explicit replay.
- actual_router_executor_test.dart: positive24tool set through actual composition,
  enrollment and owner approval, fragmented byte transport and strict parsers;
  plan/capsule/compiler consistency, jobs success/cancel/unknown/reconcile,
  desired state, explicit apply replay without a second submit.
- actual_router_fences_test.dart: malformed preflight, pre/postcommit proof and
  revoke fences, accepted-submit proof/revoke/foreign status/lost ACK boundaries,
  retained unknown without permit/effect/resubmit; existing object origin and
  inferred target denial, authorized server-list filtering and hidden job rows.
- Test support owns only declared RAM platform proof/storage/protected-byte/SSH
  ports. Factory, StateStore, queues/CAS/HMAC, router and all domain handlers run
  unchanged. No replacement domain-success stub or test-only authority bypass.

T373/T323/T381 remain unchecked until completed independent review confirms this
scope. Their closure would not close T324/T325/T331 or whole-goal acceptance,
legacy cleanup, final Analyze/Converge or native/platform/release readiness.


T381 accepted independently by completed mcp_full_parity_review: no defects in
its12cases/hook. Aggregate T373/T323 not accepted:2P2 evidence gaps remain.
No production defect or missing architecture decision established by that review.
- [x] T382 Close AC-MCP-2A evidence gap: real StateStore/factory starts in an empty
  workspace, author-only HMAC grant with no targets successfully runs all7profile
  handlers/real revisions/receipts; no server read/apply authority or SSH.
- [x] T383 Close AC-MCP-3A/3B and FR-MCP-009 evidence gap through actual router:
  runnable own plan without approval/delegation and with pending approval returns
  APPROVAL_REQUIRED, no job admission/submit/effect. Matching owner delegation
  permits successful apply with exact authorityRef without separate approval.
  Wrong exact revision/body tuple or parameters, revoked or expired delegation
  denies admission without submit/permit/effect. Historical expiry fixture uses
  actual validated RAM trusted writes, not malformed row injection or a domain
  success handler. Full checks/links and fresh independent aggregate review.

Final accepted T381 evidence remains .local/mcp-fences-final-full.log EXIT0:
622Dart(1static621RAM)+16PS,format398/0; review-ready-links EXIT0:1483/1482OK/0/1.
T373/T323 remain unchecked until T382/T383 and fresh review close both findings.


T382/T383 implementation uses actual RAM fixture controls only: populated=false
now reaches actual StateStore.open and TrustedControlServices.create without
server/trust/credential rows; author-only grant is still generated/staged and
HMAC-authenticated normally. Existing populated defaults remain unchanged.
Test grant lifetime is selectable through the real grant command to leave room
for the existing minimum300s delegation; default300s remains unchanged. No
runtime permission/clock bypass or production implementation change.

New8cases: author-only7handlers in empty workspace; runnable apply with absent
and pending approval; successful live owner delegation with exact job/receipt
reference; wrong exact revision, body digest, parameter constraint, revoked and
expired delegation refuse admission. Expiry seed uses validated real trusted
RAM writes at a historical clock and authenticates a still-live grant with the
unchanged current factory clock; current apply/driver are never replaced.

Initial .local/mcp-authority-full.log EXIT1: new fixture omitted the public
StateStore extensions import, so Flutter/engine analysis and that test load
failed. Corrected the import after full completion. Only then targeted
.local/mcp-authority-targeted.log EXIT0:8cases. Fresh full checks are required;
T382/T383/T373/T323 remain unchecked pending checks and fresh independent review.


T382/T383 fresh full .local/mcp-authority-final-full.log EXIT0: format399/0changed,
Flutter+5package analyses clean; root71+engine516+MCP15+protocol20+Windows8=
630Dart(1static629RAM)+16PS RAMgroups. All8new authority cases pass alongside
T381's12fence cases and previous policy/profile/positive24tool suites.
.local/mcp-authority-final-links.log lychee EXIT0:1483total/1482OK/0errors/1excluded.
Separate historical-worktree lint-include formatter warnings are not qualified.
Fresh independent aggregate T373/T323 review remains pending. No production
runtime or protocol version changed; no platform/native/release claim.


T382/T383 and aggregate T373/T323 accepted after completed fresh independent
mcp_authority_parity_fixed_review:0findings, readiness established for the stated
actual24-tool RAM/static permission matrix. Both previous2P2 evidence findings
are closed by actual author-only empty-workspace and approval/delegation routes.
The reviewer inspected all5actual_router suites and current production handlers,
auth/storage/driver paths and the 001/021 trace, not only the incremental tests.

Final full .local/mcp-authority-final-full.log EXIT0: format399/0changed,
Flutter+5package analyses clean,630Dart(1static629RAM)+16PS RAMgroups.
.local/mcp-authority-review-ready-links.log EXIT0:1483total/1482OK/0errors/1excluded.
This establishes T323/T373 tool/permission parity through actual domain
composition. It does not mark T324/T331 observation/recovery/occupancy acceptance,
T325 complete retained16family adoption, old runtime cleanup, final documentation/
SDK audit, overall coverage, Analyze/Converge or whole-goal acceptance complete.
No Native/Isar/realFS/SSH/Python executor/explicit engine-isolate/UI/design/
integration/build/install/release qualification. Existing001/002/021 remain the
only amended feature packages; no new feature spec or compatibility path.


## Local job observation / recovery implementation decisions — T384–T388

- [x] T384 Refine existing001/021 for T324/T331: closed runtime observation view,
  component placement, no new protocol/schema, explicit lifecycle/freshness/
  identity/order/resource rules, owner projection and actual recovery/occupancy
  acceptance. Source confirms reconcile currently ignores false childrenStopped
  and the ACK sequence floor. Links and independent specification readiness
  review required before dependent implementation; no new feature package.
- [x] T385 Implement protocol observation DTO and bounded engine runtime model,
  current-driver lifecycle/status capture and authorized jobs_get/list sibling
  projections with existing factory clock. Preserve job/ACK/schema3 and private
  authority. Pure DTO/model plus actual factory projection RAM cases.
- [x] T386 Fix confirmed reconcile terminal gate in actual driver: validate ACK
  fields/ranges, honor childrenStopped and status sequence floors, preserve
  current attempt/session/target and nonbackwards progress. No ACK-only terminal
  or recovery step authority. Retain unknown on insufficient/malformed evidence;
  enforce existing terminal/check/CAS rules and prove actual same-host reuse only
  after valid terminal. Add tasks for further confirmed findings, preserve history.
- [x] T387 Add actual factory/store/framed-transport recovery and occupancy RAM
  matrix under T324/T331: checked reopen states, lost ACK/detach/power/close/revoke,
  missing/unavailable attempt, stale identity/old generation, monotonic/duplicate
  terminal, cancel/reconcile pending/childrenStopped=false, valid terminal release
  and no restored permit/resubmit. Keep separate claims for runtime model and
  actual domain/StateStore behavior; no native/SSH/FS/process/isolate fixtures.
- [x] T388 Wire separate observation through AutomationController and existing
  jobs display, validate generation/attempt and epoch, detach/stale local view on
  client/read loss without rewriting remote result or enabling auto-retry. Add
  controller-only RAM units; no widget/layout/design/native UI tests. Full required
  checks, links and independent code review before T324/T331 aggregate closure.

T384 is design only. T385–T388/T324/T331 remain unimplemented/unaccepted until
source evidence, mandatory checks and completed clean independent review prove
otherwise. Constitution I–VII and existing one executable/writer/format3/schema3
constraints are retained. No migration/legacy fallback, new service or release.


T384 specification readiness accepted after completed job_observation_design_review:
0findings, ready for T385–T388. Links .local/job-observation-design-links.log EXIT0:
1483total/1482OK/0errors/1excluded. Reviewed source confirms existing recovery and
reconcile proof gaps; no implementation has yet been accepted. Unknown+cancel
continues to follow unchanged021 graph: no direct unknown→terminal; explicit
reconcile is required. T385–T388/T324/T331 and the full goal remain open.


T385 first runtime full .local/job-observation-runtime-full.log EXIT1: model
incorrectly treated existing decimal-string target revisions as int32, cancelling
before submit; constructor also requested Store.state unnecessarily instead of
the already validated snapshot used by composition lifecycle fixtures. Corrected
to existing requireRevision/validated snapshot, without accepting an alternate
counter format. A protocol negative fixture had changed a valid UUID digit rather
than its version; corrected the fixture, not UUID validation. Added explicit
int64 decimal precision/no-int-substitute regression. No legacy fallback.

Only after completed full failure, .local/job-observation-runtime-targeted.log
EXIT0:40affected model/projection/lifecycle/MCP cases and
.local/job-observation-dto-targeted.log EXIT0:14DTO cases. A fresh full run follows.
New observer callbacks detach on actual session loss/target transport retirement,
not on ordinary request completion. Native work remains physically drained and
remote state/occupancy stays governed by the existing writer and authority.
T385 pending full checks/review; T386–T388/T324/T331 not accepted by this increment.


T385 fresh complete gate .local/job-observation-runtime-final-full.log EXIT0:
format404files/0changed; rootFlutter+5package analyses clean; root71+engine526+
MCP15+protocol34+Windows8=654Dart(1static653RAM)+16PS RAMgroups. Includes8new
engine model cases,2actual owner/MCP projection cases and14protocol DTO cases.
.local/job-observation-runtime-links.log lychee EXIT0:1483/1482OK/0errors/1excluded.
The historical separate-worktree lint-include warnings are not qualification.
Independent code review pending. This does not accept T386 false-child/ACK floor
fix, T387 recovery/occupancy matrix, T388 controller/display or aggregateT324/T331.


T385 accepted after completed independent job_observation_runtime_review:
0findings, bounded runtime/model/projection readiness established. The reviewer
inspected the exact8file increment, source dependencies and acceptedT384 trace.
Final full .local/job-observation-runtime-final-full.log EXIT0:format404/0changed,
clean current Flutter+5package analyses,654Dart(1static653RAM)+16PS RAMgroups.
.local/job-observation-runtime-review-links.log EXIT0:1483/1482OK/0errors/1excluded.

T386 remains required: actual driver must enforce reconcile childrenStopped and
ACK sequence floor, using the existing wire. T387 actual recovery/occupancy
matrix and T388 controller/display remain separate. T324/T331 and full-goal
acceptance remain unchecked. No Native/Python executor/Isar/realFS/SSH/process/
explicit engine-isolate/UI/design/integration/build/install/release qualification.


## T386 actual terminal proof regression/fix — 2026-10-31

First .local/job-reconcile-red-full.log EXIT1 established actual-domain regressions:
false childrenStopped, ACK sequence ahead of status, invalid ACK state/negative
sequence all wrongly published cancelled; negative submit ACK allowed a step.
Other malformed/foreign/status/postcheck cases retained unknown. The fractional
fault was rejected by the RAM peer's strict encoder before delivery and marked
peer.errors; replaced with valid-wire wrong-type sequence for that actual route,
while DTO units separately reject fractional data. No protocol weakening.

T386 introduces closed structural ExecutorReconcileResult over the existing4field
response and shares existing executor state enums. The actual driver captures
bounded ACK fields, rechecks actor proof, advances its retained runtime floor
from submit/reconcile ACK, and requires stopped-child proof before terminal
query/publication. False stopped proof publishes unknown/uncertain without
observationally inventing a status sample. Cancel/older apply cannot publish
unknown/reconciling directly terminal or overwrite a newer reconciling transition.
All existing private authority, format3/ACK/job/schema3/executor wire stay intact.

Actual11case matrix covers malformed evidence, current host occupancy while
unknown, subsequent explicit valid stopped terminal then distinct approved work
on the same host, unknown cancel then explicit reconcile, and negative submit
ACK with no step permit. Matching terminal in the declared peer is idempotently
reconciled just as the unchanged root protocol already specifies. Only after
completed full failure .local/job-reconcile-targeted.log EXIT0:11cases. Fresh
full checks/review are required before acceptance. T387/T388/T324/T331 remain open.

- [x] T389 Under T387, prove/fix accepted control handoff across owned physical
  driver drain with a deterministic RAM latch. Source risk is concrete:
  TrustedJobService._drive returns false while the prior driver remains charged,
  but accepted unknown→reconciling may already be durable; merely removing the
  old driver later does not start the accepted observation. Preserve one current
  driver, current actor proof/deadlines, bounded retained control interests,
  explicit cancel versus reconcile semantics and physical quiescence. No new
  apply/submit queue, restored permission or direct unknown→terminal. Refine any
  necessary continuation decision in existing001/021 and complete specification
  readiness review before that handoff implementation; do not claim it closed
  by T386 terminal safety or normal cancel/reconcile cases.


T386 fresh full .local/job-reconcile-final-full.log EXIT0: format406/0changed,
Flutter+5package analyses clean; root71+engine537+MCP15+protocol47+Windows8=
678Dart(1static677RAM)+16PS RAMgroups. All11new actual-driver and13new structural
reconcile DTO cases pass. .local/job-reconcile-links.log lychee EXIT0:
1483total/1482OK/0errors/1excluded. Historical separate-worktree lint warnings
are not qualification. Fresh independent T386 code review is pending.
T387/T388/T389 and aggregateT324/T331 remain open; no native/platform/release claim.


Completed job_reconciliation_gate_review found1P2 insideT386: its old-mode guard
was outside publish's read/CAS retry. Old cancel/apply error could read unknown,
then overwrite a newer durable reconciling on read/retry. This is distinct from
T389 control activation and blocks T386 acceptance despite the earlier green gate.
- [x] T390 Fix confirmed T386 review finding: move originating-driver mode/phase
  predicates into every progress CAS iteration, including after a conflict.
  Extract only the existing data publication loop into JobService-owned
  automation/job_progress.dart; actual driver uses the same real-store read/CAS
  ports and authority logic. Add deterministic actual StateStore RAM commit/latch
  regressions for awaited read and real REVISION_CONFLICT, proving newer accepted
  reconciling is untouched. No fake StateStore, result stub, new wire/authority,
  mode from caller JSON or restoration of permission. Fresh checks/review required.


T390 deterministic race proof: .local/job-reconcile-race-red-full.log full EXIT1
with both actual-store latches reproducing reconciling overwritten as unknown
using the unguarded extracted loop. The fixed loop re-evaluates originating mode
against each freshly read/CAS-retried state, rather than relying on stale guards
in terminal/catch callers. Redundant outside guards removed. Actual production
ports remain guarded store reads plus the same expected-sequence queued writer.

Expanded race matrix covers apply and cancel for both awaited-read and real
REVISION_CONFLICT windows, comparing the complete durable job and commit count.
These are metadata CAS boundary units using actual StateStore; they do not claim
native/root actor proof. Existing11actual factory/framed-driver cases cover the
composed terminal gate. Only after full red completed,
.local/job-reconcile-race-targeted.log EXIT0:4race+11driver=15cases. Fresh mandatory
checks and a new completed reviewer are still required; T386/T390 not accepted.


T386/T390 fresh post-fix full .local/job-reconcile-race-fixed-full.log EXIT0:
format408/0changed; current Flutter+5package analyses clean; root71+engine541+
MCP15+protocol47+Windows8=682Dart(1static681RAM)+16PS RAMgroups. Includes4actual
StateStore CAS race cases,11framed actual-driver cases and13reconcile DTO cases.
.local/job-reconcile-race-links.log lychee EXIT0:1483/1482OK/0errors/1excluded.
Initial independent1P2 is not declared closed until fresh review completes.
T387/T388/T389/T324/T331 and other whole-goal tasks stay open; no native claim.


T386/T390 accepted after completed fresh job_reconciliation_cas_fixed_review:
0findings, bounded terminal-gate/CAS publication readiness supported. Previous
job_reconciliation_gate_review1P2 is closed by predicate evaluation inside each
read/CAS iteration and4actual-store latch regressions; not by a stale caller guard.
Final .local/job-reconcile-race-fixed-full.log EXIT0:format408/0changed, clean
Flutter+5package analyses,682Dart(1static681RAM)+16PS RAMgroups.
.local/job-reconcile-race-review-links.log EXIT0:1483/1482OK/0errors/1excluded.

T389 accepted-control activation after physical drain remains open and requires
its existing-package decision/readiness work and deterministic actual acceptance.
T387/T388/T324/T331 and all remaining whole-goal acceptance/cleanup/coverage/
Analyze/Converge tasks remain open. No Native/Python/Isar/realFS/SSH/process/
explicit engine-isolate/UI/design/integration/build/install/release qualification.
No new feature/spec package, protocol/schema version or compatibility path.


## Accepted job control handoff decisions — T391–T393

- [x] T391 Refine T389 in existing001/021: one bounded FIFO control metadata
  coordinator, per-kind pending slots and original30s invocation deadline;
  admission/readback registration ordering; no old-driver drain under its lock;
  fresh proof, fair one-shot control activation, replay rearm, conservative
  expiry/sealing and explicit resource/ownership limits. Links and independent
  specification readiness review before dependent code. No new feature package.
- [x] T392 Implement JobService-owned automation/job_controls.dart and actual
  registration/driver completion/activation in jobs.dart using T391. One current
  driver, separate real cancel/read actors, no apply queue/resubmit/permission
  restoration; keep T386/T390 terminal/CAS fences. Standard internal time port,
  bounded metadata mutex/slots/pump/timer and no discarded accepted continuation.
  Pure bookkeeping/time units and full mandatory checks; no caller-supplied mode.
- [x] T393 Prove T389 through actual factory/StateStore/native-boundary RAM actors
  and framed peer with physical stdin/channel drain latch, not scripted tool
  success. Cover deadlines, coalescing/fairness, role/identity loss, terminal,
  seal/late native completion, limits and exact retained IDs/events/receipts;
  no root work before positive quiescence, no submit/permit after handoff.
  Fresh complete checks/links and independent code review before T389 closure.

T391 only supplies design; T392/T393/T389 remain open until their own evidence.
T387's full recovery/occupancy matrix, T388 controller/display and aggregate
T324/T331 are not closed by this decision package. Existing single executable,
private worker/MCP/tray and schema3/format3 constraints remain unchanged.


T391 design readiness evidence: independent read-only review
job_control_handoff_design_review completed with no findings and readiness for
T392/T393 only. The reviewer inspected the eight changed existing001/021 documents,
actual admission/driver/CAS/store/actor code and factory/framed RAM support.
Link gate .local/job-control-design-reviewed-links.log EXIT0:1483total/1482OK/
0errors/1excluded. No application code changed in T391; no new SDK test pass or
handoff implementation is claimed. T392/T393/T389 remain unchecked; full recovery,
controller and aggregate T387/T388/T324/T331 also remain open. No native/platform/
build/install/release qualification. Original requirements/receipts/identities and
single executable with tray/MCP lifecycle remain unchanged.


T392 implementation increment (pending checks and independent source review):
JobControlContinuations and actual JobOperation registration/pump/physical-driver
completion now replace the lost boolean handoff. One FIFO metadata interest,
per-kind actor slot, original monotonic deadline and service timer retain native
settlement ownership. Control activation replays the actual receipt and may rearm
unknown through queued CAS; root work starts after coordinator release. An internal
continuation fence runs after asynchronous transport proof, immediately before
root bytes; it grants no actor rights. Standalone cancel is one stop/status cycle,
with typed correlated stop ACK coalescing, no submit or permit. Seal/resume does not
restore pending contexts. No new wire/schema/service or compatibility path.

T393 has an initial actual factory/store/framed RAM regression holding the old
executor session's physical done with autoClose=false. Its corrected-fixture red
run .local/job-control-red-target-fixed-fixture.log EXIT1 leaves reconciling after
release; initial implementation targeted run .local/job-control-first-target.log
EXIT0 passed16 cases (one handoff plus existing reconcile/CAS cases). Five new
coordinator-only RAM units cover FIFO/cancellation, same-kind actor replacement,
one-cancel fairness, monotonic original deadline/retired timer, bounded capacity,
seal and stop-ACK pruning. These are limited evidence, not the complete T393 matrix.
The first full post-code run .local/job-control-runtime-full.log EXIT1 had one
unawaited_futures lint in the new unit; all test suites ran, engine547 passed.
The lint is fixed; a fresh full gate and independent review remain required.
T389/T392/T393/T387/T388/T324/T331 remain open until their complete required evidence.
No Native/realFS/Isar/SSH/process/engine-isolate/UI/design/build/release check.


T392 subsequent evidence before final source review: full
.local/job-control-runtime-final-full.log completed EXIT0 (format411/0changed,
root71+engine547+MCP15+protocol47+Windows8 =688 Dart including one static source
check, plus16 PowerShell RAM groups). Further source inspection added an operation
settlement wake so a native write finishing after its logical wrapper failed does
not strand reconciling without a ticket. Actual handoff RAM cases now additionally
cover original30s wait expiry with a still-live real grant, a newer same-kind
invocation retaining its own deadline without an extra state event, revocation,
and JobService suspend waiting actual close then resuming without old intents.
The existing factory readClock port is forwarded by RAM helpers; actor/native
proof clocks and grant lifetime are not replaced. Targeted10 cases passed after
correcting a test-only assertion to the actual ClientGrantRecord.id field.
The688-check evidence predates these later changes; a fresh complete gate and
independent review are required. Full T393 role/identity/native-write/terminal/
false-proof/generation/fairness matrix and whole-goal aggregates remain open.


T392/T393 current increment full gate .local/job-control-expanded-full.log completed
EXIT0: format411/0changed, Flutter and five package analyses clean; root71+
engine551+MCP15+protocol47+Windows8 =692 Dart checks (one static source boundary,
691 RAM units), plus16 PowerShell RAM groups. Includes the five actual handoff
cases and five coordinator units above. Empty locald test directory is not a test
pass. Link gate .local/job-control-expanded-links.log EXIT0:1483/1482OK/0errors/
1excluded. Independent review of this implementation increment is required next;
T392/T393/T389 and whole-goal aggregates remain unchecked. No native qualification.


## Stop-ACK retirement correction — T394

- [x] T394 Fix confirmed P2 from completed job_control_handoff_runtime_review:
  retire cached stop-ACK for the corresponding server/connection/enrollment;
  late pre-retirement ACK must not restore it. Preserve actual physical drain
  ownership and pending actor retirement. Prove ACK→unknown→full disconnect→
  explicit current reconnect→new stable cancel/status in actual factory/store/
  framed RAM, plus stale ACK/token scheduling units. Fresh full checks/links
  and new independent review; do not close the remaining T393 matrix.

Review found1 confirmed lifetime defect; T391 remains ready for implementation,
but current T392 increment is unaccepted until T394 fix/review. Existing task
history and T389/T392/T393/T387/T388/T324/T331 unchecked state are preserved.


T394 red evidence: .local/job-control-retirement-red-full.log EXIT1 first exposed
fixture reconnect before physical connection retirement; the fixture now awaits
actual disconnected view before explicit reconnect. Corrected actual regression
.local/job-control-retirement-red-target.log EXIT1: expected2 stable cancel requests,
actual1. Cache retirement now uses the entry's immutable server binding and rotates
an opaque stop-ACK correlation token; an in-flight old ACK cannot repopulate the
fact after retirement. No snapshot read or new Native work is added to retirement
notification. Pending actors and physical driver ownership keep their existing
retirement/drain rules. Actual reconnect plus six coordinator units now pass12
addressed cases in .local/job-control-retirement-fixed-target.log EXIT0. Fresh
full gate, links and independent fix review remain required; T394 stays open.


T394 fixed full .local/job-control-retirement-fixed-full.log completed EXIT0:
format411/0changed; Flutter+five package analyses clean; root71+engine553+MCP15+
protocol47+Windows8 =694 Dart (one static source check,693 RAM), plus16PSRAMgroups.
Six actual factory handoff/retirement cases and six coordinator RAM units pass.
Current code now awaits fresh independent fix review; T394 is not yet accepted.
No Native/platform/integration qualification or full T393 closure is claimed.


T394 accepted after completed independent job_control_retirement_fixed_review:
0findings; server-bound stop-ACK retirement and stale ACK correlation inspected
against actual source/spec, no unresolved confirmed finding in this increment.
Full .local/job-control-retirement-fixed-full.log EXIT0:411formatted/0changed,
Flutter+five package analyses clean,694Dart (one static,693RAM)+16PSRAMgroups.
Links .local/job-control-retirement-review-links.log EXIT0:1483/1482OK/0errors/
1excluded. Review is limited to the implemented increment and T394 correction;
it does not establish the remaining T393 matrix or whole service readiness.
T392/T393/T389/T387/T388/T324/T331 remain unchecked. No native/platform/release
qualification, new service/package/schema or compatibility path was introduced.


## Owner cancellation envelope correction — T395

- [x] T395 Fix concrete failure exposed by actual T393 native-write interest loss:
  automation.cancel must retain the CANCELLED envelope already required by021
  owner-automation. Shared closed McpToolResult allowlist currently rejects that
  code, throwing VALIDATION after marking the handle cancelled but before
  cancelling its response interest. Add the fixed lifecycle category to the same
  shared business envelope, freeze it before changing handle state, preserve
  closed error parsing and local/none semantics. No new envelope/schema/version,
  authority, job stop, compatibility branch or rollback. Protocol RAM and actual
  factory/native-write tests; full checks/links/independent review before closure.

T393 first complete .local/job-control-matrix-first-full.log EXIT1: two new
readonly-denial tests expected an envelope where the actual router correctly
throws FORBIDDEN; one test inspected metadata during temporary authority
publication. Test boundaries corrected without production relaxation. Subsequent
actual same-ID rearm, accepted pending terminal pruning and response-interest
loss cases plus queued expiry/retired epoch units extend the matrix. The interest
loss regression .local/job-control-matrix-lifetimes-target.log EXIT1 establishes
T395 (McpToolResult.failure CANCELLED→FormatException VALIDATION). Native write,
actor permission and physical ownership behavior remain required, not mocked ACKs.


## T393 handoff acceptance matrix and T395 verification

Current actual factory/StateStore/actor/framed RAM evidence is19 handoff cases:
six in job_control_handoff_test.dart and thirteen in job_control_roles_test.dart.
These use actual metadata receipts/CAS/readback, HMAC/owner contexts and byte
framing; the declared RAM peer is not Native/root artifact qualification.

| Required behavior | Evidence in current unit sources |
| --- | --- |
| Old physical owner must drain before accepted control starts | Held executor session done, immediate durable reconciling, no root control before release, one activation without another invocation |
| Original deadline and coalescing | Still-live grant with elapsed31s refuses expired ticket; newer invocation retains its own deadline and no duplicate state event; private retired timer units |
| Separate actor rights and fairness | Read-only originating MCP context is forbidden cancel; owner cancel then read reconcile; new cancel alias during malformed stop ACK gets its turn only after pending reconcile |
| Trust/target loss | Actual grant revoke; owner profile target revision update; actual owner enrollment revoke under target fence, then explicit inspection/re-enrollment and fresh HMAC recovery |
| Terminal and replay correlation | Already accepted pending cancel/reconcile pruned after current observer proves terminal, before its close; terminal replay immutable; same-ID explicit unknown cycle rearm uses same receipt/attempt/authority and exactly two state events |
| Insufficient proof keeps occupancy | False childrenStopped, foreign reconcile/status IDs after handoff; distinct approved apply remains HOST_BUSY, no additional submit/permit |
| Native ownership and sealing | Actual RAM storage holdPut through JobService suspend/exit; no positive drain before settlement; accepted receipt survives; resume needs fresh invocation; response-only cancellation retains accepted continuation |
| Cleanup failure fails closed | Actual executor session done error suppresses pending root control; pause/close fail and resume is refused; retained job remains nonterminal and workspace lease is not released |
| Bounds and retired callbacks | Eight coordinator-only units: FIFO unstarted cancel/expiry, charged active interest, latest slots/fairness, one timer,250entries/500actors/33interests, stop-ACK retirement/prune, late timer/ACK and resumed epoch |

The factory seal/native-write cases and coordinator epoch assertions cover this
service's retirement boundary. Checked workspace reopen/new-generation recovery
and the larger power/close/occupancy matrix remain T387; controller view remains
T388. They are not closed by the T389 handoff slice. No engine-isolate fixture.

T395 uses the cancellation category already required by021 owner-automation;
protocol units assert fixed local/none cancellation, immutable owner capture,
rejection of arbitrary diagnostic codes and extra owner fields. Actual cancelled
response remains CANCELLED while accepted reconciliation completes without stop,
resubmit or permission restoration. No envelope/schema/version or raw error
text was added. Production change is the shared code allowlist and capture before
marking the owner handle, not a second result parser or compatibility branch.

Full .local/job-control-matrix-fixed-full.log completed EXIT0: format413/0changed,
Flutter+five package analyses clean; root71+engine568+MCP15+protocol49+Windows8=
711 Dart (one static source check,710 RAM), plus16PSRAMgroups. No tests claimed for
empty locald. Complete first run failed before addressed checks; later targeted
20 cases passed after the concrete fixture corrections and T395 fix. Two protocol
units and the final physical-close failure case are included in this fresh full
run. T389/T392/T393/T395 remain unchecked pending independent acceptance review;
T387/T388/T324/T331 and all other whole-goal work remain open. No Native/Python/
Isar/realFS/SSH/process/container/UI/design/build/install/release qualification.


T389/T392/T393/T395 accepted after completed independent
job_control_complete_matrix_review:0findings, ready for this handoff/cancellation
slice. Review directly inspected coordinator, actual JobService/driver/CAS,
actor/native transport dispatch/cleanup, owner API/protocol and nineteen actual
factory/framed RAM cases, eight coordinator units and two cancellation protocol
units. Full .local/job-control-matrix-fixed-full.log EXIT0: format413/0changed,
Flutter+five package analyses clean,711Dart (one static710RAM)+16PSRAMgroups.
Links .local/job-control-matrix-review-links.log EXIT0:1484/1483OK/0errors/1excluded.
T395 closes the documented CANCELLED producer/parser mismatch, not a new result
shape or job cancellation side effect. Earlier T394 stop-ACK retirement acceptance
is retained. Task history and earlier red/partial evidence are not erased.

This acceptance closes only accepted-control physical handoff and its verified
boundaries. T387 reopen/new-generation/power/recovery/occupancy, T388 controller,
T324/T331 aggregates and all other remaining implementation/cleanup/Spec Kit/final
whole-goal checks stay open. No Native/platform/Isar/realFS/SSH/process/isolate/UI/
design/integration/build/install/release readiness is established.


## T387 checked reopen and recovery RAM matrix

job_reopen_recovery_test.dart adds15 actual factory/store/HMAC/owner/framed RAM
cases. Capture existing admitted states from MemoryWorkspaceProvider.afterCommit;
no job/receipt rows are invented. Queued capture seals JobService during the
actual queued commit before any root submit. Running/unknown captures use an
actual accepted root submit whose framed ACK is lost at session EOF, with no
step permit. Other captures follow actual cancel, reconcile, failure or fully
checked success. Captured bytes are restored only inside the declared RAM
provider after old services/host/store positively close; this models a retained
crash image, not user-file mutation or a production rollback feature.

A new actual HostAuthority/EngineSessions generation and real StateStore.open
repeat signed metadata/custody/semantic validation. Checks assert queued→cancelled/
none, running/cancel-requested/reconciling→unknown/uncertain, existing unknown and
three terminal states unchanged; exact job/plan/attempt/request/authority and
cancel flag survive, state sequence advances only when required. Every other
native collection row/native ID/payload is retained byte-exact, previous event
rows stay exact with only the required recovery event, including retained grants,
credentials/trust, approval/delegation and desired state. Runtime observation is
new-generation detached with no sequence/sample restored. Startup creates no SSH
attempt and issues no root call, submit or step permission. Original apply receipt
replay remains exactly its retained ACK and does not restart a job.

Actual detach, full TrustedControlServices suspend/resume and full close retain
an already admitted attempt while its physical channel close is held. A new
factory/store generation then observes unknown; no permission is restored, and
only an explicit fresh reconciliation obtains a proven stopped terminal. Revoked
origin grant stays revoked through reopen: its valid-key client is denied, owner
apply replay is denied, while actual owner observational recovery preserves the
original grant/attempt/authority and writes an owner-origin control receipt.

Missing root attempt is a typed framed NOT_FOUND; unavailable control returns
EXECUTOR_UNAVAILABLE, and foreign status is rejected. Each remains unknown and
HOST_BUSY for a distinct approved plan. Only a separate valid correlated stopped
reconciliation releases occupancy; retrying the previously denied new admission
then creates a distinct job and one new authorized effect. Terminal cancel and
reconcile aliases preserve immutable terminal rows/events without root I/O.
T386/T390 correlation/CAS and T393 false-proof/physical-failure/fairness acceptance
remain part of this chain. Their accepted task history is retained.

The declared byte peer now models no-launch queued/waiting reconciliation using
the current executor/serverdeck_executor/jobs.py reconcile/_job source: stopped
no-launch jobs become cancelled, missing attempt reports NOT_FOUND, and explicit
fixture errors retain the existing closed root error frame. No Python process,
SSH/socket, native database/FS or native artifact qualification is exercised.
New test setup reopen supplies a fresh generation and distinct RPC counter range;
ordinary setup defaults and the actual production factory/loader remain unchanged.

First complete .local/job-reopen-first-full.log EXIT1: a final-local assignment
in the extended RAM peer prevented affected test loads; two then-planned imports
were unused. Fixture compiler issue fixed, revoked-owner case added using those
imports. After that completed failure, .local/job-reopen-expanded-target.log EXIT0
passed15cases. Fresh full gate and independent source/spec acceptance review are
required before T387 closure. T388/controller and T324/T331 aggregates remain open;
no Native/platform/realFS/Isar/SSH/process/isolate/UI/design/build/release readiness.


T387 fresh complete .local/job-reopen-final-full.log finished EXIT0:
format414/0changed; Flutter+five package analyses clean; root71+engine583+MCP15+
protocol49+Windows8=726Dart (one static source check,725RAM)+16PSRAMgroups.
Link gate .local/job-reopen-links.log EXIT0:1484total/1483OK/0errors/1excluded.
The15case addressed matrix is included in this full run, together with all prior
T386/T390/T393 regressions. No current production application code was changed;
RAM factory setup/peer support and acceptance tests exercise the existing loader,
recovery and shared services. T387 remains unchecked until completed independent
acceptance review confirms the full stated scope, not merely successful tests.
T388/controller, T324/T331 aggregates and remaining whole-goal work stay open.


T387 accepted after completed independent job_reopen_recovery_review:0findings,
ready for this checked-reopen/recovery/occupancy RAM scope. Review directly read
the exact four-file increment, actual loader/factory/JobService/CAS/actor paths,
previous accepted correlation/handoff matrices and primary Root _job/reconcile
source; no domain-success substitution or mandatory gap was found. Fresh full
.local/job-reopen-final-full.log EXIT0:414formatted/0changed, clean Flutter+five
package analyses,726Dart(one static725RAM)+16PSRAMgroups. Latest links
.local/job-reopen-review-links.log EXIT0:1484/1483OK/0errors/1excluded.

This closes T387's stated static/RAM acceptance only. T388 controller/local
observation display and T324/T331 aggregates, plus all other remaining whole-goal
implementation/adoption/cleanup/docs/final Spec Kit audits, remain open. Native,
real FS/Isar/Python/SSH/process/isolate/UI/design/build/install/release qualification
was not performed and is not established by these assertions. Existing task
history, including red checks and narrower prior acceptance, remains intact.


## T388 controller observation projection

AutomationController now stores immutable LocalJobObservationView separately for
selected/listed jobs, removes the raw observation from displayed job rows, and
validates current bound generation plus exact immutable job/hostAttemptId before
installing replies. A whole list page is captured before any row is installed;
selected job/events are captured before changing selection. Read loss changes
only local observation confidence: sample→stale, no sample→detached. Client loss
retires the epoch/timer and detaches local observations while keeping durable
job state/outcome/IDs untouched. Disposed or older-epoch callbacks cannot update
remote result or local observation. No automatic control/retry/permission flow is
introduced; existing explicit owner actions and pending request IDs remain.

One normal1s Timer/scheduling port is internal to the controller. Token, epoch,
selected ID and client generation fence the fired callback; busy reads cannot
create overlapping polling, and the current action schedules one next poll.
Existing native store bound250active+1000terminal limits retained list data;
listpage25/events200 display bounds stay in force. Existing jobs section receives
the separate views and adds observation state and last response sequence/time
alongside remote job state, using existing DeckKeyValue composition and unchanged
action rules. No design003 layout/theme rewrite or visual readiness assertion.

Fifteen controller-only RAM units use the real EngineClient/strict owner framing
with a bounded declared gateway and structural presentation records, not native
permission or domain success proof. They cover separate selected/listed data,
invalid generation/attempt/state/extra fields and changed known attempt, atomic
list/event failure, stale/no-sample behavior without changing succeeded, client
loss, old timer/selection, busy timer coalescing, dispose/late reply and changed
client generation. Existing T385/T386/T387/T393 actual factory/store/actor/framed
RAM acceptance remains the independent backend half of the T384 chain.

First complete .local/job-controller-red-full.log EXIT1: the new controller API
and scheduling seam were absent before implementation, so the new test did not
compile. After the completed full failure, addressed13case units passed; two
additional atomic-events/busy-timer units and the disposed-observation fence were
included in the fresh full .local/job-controller-final-full.log EXIT0:
format415/0changed; Flutter+five package analyses clean; root86+engine583+MCP15+
protocol49+Windows8=741Dart(one static source740RAM)+16PSRAMgroups. No pass claimed
for empty locald, no widget/layout/design/native tests. Links and independent
review/fix loop are required before marking T388 accepted. T324/T331 aggregate
acceptance and all other remaining whole-goal tasks stay open.


T388 accepted after completed independent job_observation_controller_review:
0findings, ready for the specified controller/RAM scope. Reviewer directly read
current controller/client/DTO/backend projection, the exact five-file increment,
functional fields in the existing jobs view and15 controller RAM cases. Full
.local/job-controller-final-full.log EXIT0:415formatted/0changed, clean Flutter+
five package analyses,741Dart(one static740RAM)+16PSRAMgroups. Link gate
.local/job-controller-review-links.log EXIT0:1484/1483OK/0errors/1excluded.
Read/dispose/client loss does not rewrite remote outcome or start job control.
No widget/layout/design/native UI qualification; prior task history is retained.

## T324/T331 aggregate observation/recovery traceability audit

The aggregate checkboxes remain open pending an independent review of this
complete chain; accepted component results alone are not a whole-goal claim.

| Aggregate requirement | Accepted source and actual verification chain |
| --- | --- |
| FR-SVC-EMB-08/AC08: unknown occupancy, no automatic apply | T386 actual correlated stopped proof and HOST_BUSY/new approved work; T387 checked reopen/lost ACK/missing/unavailable/foreign/current authorized recovery; T389/T392/T393 actual physical handoff, no submit/permit restoration |
| FR-SVC-EMB-09/AC09: observation separated from remote result and authority | T384 decisions; T385 strict sibling DTO/runtime-only observations and actual owner/MCP projection without reads opening SSH or metadata writes; T388 separate selected/listed views and unchanged remote outcome/control rules |
| Current generation/target/trust/grant/event ordering | T385 monotonic5s/UTC jump, old token/target/generation/semantic sequence rules; T386/T390 actual StateStore CAS conflict/retry fences; T393 role/target/enrollment/revoke/deadline/retirement; T387 fresh generation/old session refusal; T388 reply/timer/client epoch and attempt fences |
| SC-SVC-EMB-04: no false success from loss or intent ACK | T386 false childrenStopped/foreign/bad ACK/status/postchecks keep unknown+HOST_BUSY; T393 cancel ACK only stop intent, physical cleanup failure blocks activation/pause; T387 native loader recovery retains uncertainty, owner control after revoke stays observational |
| T331 terminal releases only after proof and no observer-only lock | T386 actual valid terminal plus distinct approved apply; T387 same-host admission after separately valid reconciliation and exact terminal alias/no-event preservation; T393 accepted pending control terminal prune and same-ID rearm without a new receipt |

Source locations are engine/automation/job_observations.dart, jobs.dart,
job_controls.dart, job_progress.dart and storage/automation_job_progress.dart;
protocol/automation/job_observation.dart and executor_jobs.dart; Flutter
AutomationController and existing jobs section. Actual RAM evidence is retained
in job_observation_projection_test, job_reconciliation_test, job_progress_race_test,
job_control_handoff_test, job_control_roles_test and job_reopen_recovery_test;
pure model/DTO/controller evidence is separately labelled. No alternate service,
wire/schema version, legacy fallback, permission producer or apply queue was
introduced. T324/T331 acceptance must be assessed against FR08/09, AC08/09, SC04,
not inferred from all-green compilation. Whole feature/runtime/bundle/adoption/
cleanup/platform/Spec Kit final acceptance remains separate and incomplete.


T324/T331 aggregate acceptance confirmed by completed independent
job_observation_recovery_aggregate_review:0findings, both aggregate tasks may
close; T388 acceptance also confirmed. Reviewer independently inspected the
current DTO/overlay/projection/driver/handoff/CAS/recovery/controller chain,
FR-SVC-EMB-08/09, AC08/09 and SC04 against actual unit sources and logs, not
merely the green component statuses. All11 recorded source hashes matched.
741Dart(one static740RAM)+16PSRAMgroups, format415/0changed and clean Flutter+
five package analyses remain .local/job-controller-final-full.log EXIT0.
Current package links .local/job-controller-aggregate-links.log EXIT0:
1484total/1483OK/0errors/1excluded. All earlier completed task/evidence history
is retained; narrowed component acceptance is not rewritten as global acceptance.

T324/T331/T388 close only observation/recovery/controller static/RAM obligations.
Remaining adoption/retention, source cleanup, platform/storage copy, pins, bundle
and final whole-feature Spec Kit/requirement acceptance tasks stay open. No native,
real FS/Isar/SSH/process/isolate/UI/design/integration/build/install/release
qualification is claimed; the full goal remains active and incomplete.


## T325 nonempty schema3 retention matrix

The increment in `packages/serverdeck_engine/test/storage/full_schema3_retention_test.dart`
creates a runnable plan through the actual service factory, owner-approved apply,
framed RAM Root peer, terminal succeeded job and then an owner-created delegation.
Every one of the16 WorkspaceCollection families must be nonempty before assertions;
this closes the empty-family limitation of earlier retention/recovery fixtures.
No production snapshot restore, migration or compatibility path is introduced.

The positive test closes the original actual store/services, reopens the current
persisted RAM bytes through the actual preflight/custody/loader/factory and compares
all16 raw nativeId/entityId/payload families, foundation semantic state, terminal
job semantic state, signed executor enrollment and every protected RAM file byte.
These comparisons include IDs, revisions, credentials and their bindings, trust,
grants, delegation, consumed approval, history/events, receipts and desired state.
Startup performs no SSH/Root request. The prior client cannot use the new host
session generation; a fresh HMAC client can read and replay the original apply
receipt without resubmitting, consuming a new permit or changing any retained row.
Persistent delegation policy is retained; it is not a runtime session or one-time
Root permission.

Sixteen refusal cases corrupt a native ID in each separately populated family;
five more cover schema1/schema2/unknown schema99, broken credential reference and
invalid receipt-key wrapper. All use only the declared RAM provider, require no
additional writable open and compare every input file unchanged after rejection.
The existing T371/T372 and snapshot/preopen custody, concurrent-writer and semantic
fault checks remain applicable; this increment does not replace their coverage.
T325 remains unchecked pending the full check result and independent review.
Native/realFS/Isar/SSH/Python/process/isolate/UI/design/build/release qualification
is outside these unit assertions and has not been performed.


T325 accepted after completed independent schema3_retention_review:0findings,
ready in the scoped synthetic/RAM retention matrix. Reviewer inspected the exact
two-file increment, actual loader/custody/factory and related001/002-security-storage/
021 requirements, and the existing prerequisite fault/recovery suites. Exact raw
payload retention followed by actual semantic revalidation was assessed sufficient;
separate serialization of every automation map is not an unresolved requirement.

Fresh complete `.local/schema3-retention-first-full.log` finished EXIT0:
416formatted/0changed; Flutter+five package analyses clean; root86+engine605+MCP15+
protocol49+Windows8=763Dart (one static source check,762RAM)+16PSRAMgroups.
`.local/schema3-retention-links.log` EXIT0:1484total/1483OK/0errors/1excluded.
The22 new cases are included in that full run; no addressed-only run was needed.
Existing nested work/ lint-include formatter warnings do not change its success.
Empty residual locald has no current-task suite and is not counted as a test pass.

This closes T325 only. T321, cleanup/documentation/pin work and final whole-feature
Spec Kit Analyze/Converge/acceptance remain separate. No native/platform/realFS/
Isar/SSH/Python/process/isolate/UI/design/build/install/release qualification is
claimed. Existing task history and narrower earlier acceptance are preserved.


## T321 complete power lifecycle aggregate acceptance

T321 accepted after completed independent power_lifecycle_aggregate_review:
0findings, ready only for this implementation/RAM/static scope. The review read
current Desktop/worker/Root/Host/services/SSH/jobs/capabilities source and the full
applicable requirement→contract→task→acceptance chain; earlier T333–T350 clean
reviews were provenance rather than a substitute for this aggregate assessment.

Native WM_POWERBROADCAST/early latest intent → subscribed desktop actions →
controller epoch/private owner retirement → authenticated coalesced Root power
intent → synchronous Host admission fence → actual service/sampler/transport/job
drain → current runtime/vault/lease/store/revisions/capability restore → fresh
observation/window binding is connected. Same worker/Host/store/lease/generation
is retained; uncertain physical close never permits replacement. Resume without
a suspend callback fences first. Cleanup failure prevents resume. One original
resume deadline includes pending pause, owner detach, restore and startup; late
replies and superseding epochs cannot publish stale Ready/capabilities.

Actual jobs seal/drain does not remotely cancel, resubmit or restore one-time
permits. Accepted remote history/occupancy remains governed by current actor and
repository rules; explicit SSH reconnect and explicit recovery remain required.
Static wiring and RAM tests cover original deadline, late reply, lost suspend
callback, revoke, close/shutdown races and fresh private binding. Native delivery,
real sleep/wake and actual UI remount are not established by these checks.

Current complete `.local/schema3-retention-first-full.log` EXIT0 covers this code:
416formatted/0changed; Flutter+five package analyses clean;763Dart(one static,
762RAM)+16PSRAMgroups. No application code changed for the aggregate audit.
`.local/schema3-retention-accepted-links.log` EXIT0:1484total/1483OK/0errors/
1excluded. Historical component MSVC `/Zs` evidence is syntax only, not execution.
No Native/realFS/Isar/SSH/Python/process/isolate/UI/design/build/install/release
qualification is claimed. T327/T328/T329/T330 and remaining whole-goal work stay
open; T321 acceptance does not close the feature or those separate requirements.


## T329 current plan and existing dependency pins

Correct the embedded Technical Context from dartssh2 4.2.0 to the already-used
4.1.0 in packages/serverdeck_engine/pubspec.yaml and root/engine pubspec.lock.
Replace the stale assertion that Root/proxy is absent with current implementation
and accepted static/RAM lifecycle/owner/gateway scope. Keep historical foundation
sections/task history, the distinct constitution version, and explicit limits on
native/isolate/IPC/FFI/UI/build/release qualification. No source, manifest, lockfile
or dependency resolution is changed. T327/T328/T330 remain separate. T329 remains
unchecked until links and completed independent review establish this correction.


T329 accepted after completed independent plan_current_status_review:0findings,
ready for this documentation-only pin/current-source correction. Direct engine
pubspec and both current lockfiles confirm4.1.0; current Root/controller/gateway/
desktop source and prior accepted T321/T324/T331/T325 evidence support the scoped
status. No dependency resolution, upgrade, application source or lockfile change.
`.local/plan-status-links.log` EXIT0:1484total/1483OK/0errors/1excluded. The cited
763Dart/16PS full gate is historical source evidence, not a new app execution for
this docs-only change. T327/T328/T330 remain open; no whole-feature or native/
platform/isolate/IPC/FFI/UI/build/install/release readiness is implied.


## T328 current storage/platform instructions and presentation wording

README now describes the existing single executable, tray/Exit lifetime and
connection-only MCP mode; absent app means no MCP response, local stderr/nonzero.
It links the current test-unit entry and existing build/setup instructions rather
than the deleted available-foundation runner. New developer storage/platform
instructions document target-schema3 retention/refusal/writer-busy/custody,
all six current platform rows, actual capabilities and prerequisites, suspend/
resume and explicit runtime/platform/release qualification limits.

Only display literals change in readiness_view.dart, error_view.dart, motion.dart
and software_panel.dart: ServerDeck wording replaces separate local-service and
client/service-version instructions. Error codes, permissions, retry/action/tone
policy, layout/widget structure, styling and callbacks are unchanged. Existing
closed safe ErrorCode mapping excludes arbitrary exception text; no new message
transport or runtime decision is introduced. No UI/design/widget/native checks
are added or run; the full existing static/unit gate applies to this text change.
T328 remains unchecked until actual checks and completed independent review.


T328 accepted after completed independent current_storage_platform_docs_review:
0findings, ready in this storage/platform instruction and presentation-copy scope.
The review read all eight changed files and actual storage/capability/MCP/desktop
source,001/002/021 contracts and evidence. Display changes retain the closed
safe-code mapping, actions/retry/tone/auth policy and widget/layout structure.
No UI/design/widget test or native dispatch was added or run.

Fresh complete `.local/current-docs-full.log` finished EXIT0:416formatted/0changed;
Flutter+five package analyses clean; root86+engine605+MCP15+protocol49+Windows8=
763Dart(one static762RAM)+16PSRAMgroups. Empty residual locald is not a passed
suite; historical nested work/ lint warnings do not change the formatter success.
`.local/current-docs-spec-links.log` EXIT0:1484total/1483OK/0errors/1excluded;
`.local/current-docs-guide-links.log` EXIT0:22total/22OK/0errors. The auxiliary
literal comparison is only a one-off lexical check; actual diff and independent
source review establish the limited copy change. No message/runtime policy or
current test coverage was replaced by this comparison.

T329 was separately accepted by completed plan_current_status_review and
plan_status_acceptance_record_review, both0findings; its pins/locks/source were
not changed. T327 cleanup and T330 final whole-feature Analyze/Converge/evidence
remain open. These current instructions do not establish native/platform/realFS/
Isar/SSH/Python/process/isolate/UI/design/build/install/release readiness, and no
whole-goal completion is claimed. Earlier task/check history is retained.


## T327 exact package inputs and remaining owner configuration parser

- [x] T396 Remove the concrete old MCP owner configuration contract still present
  in protocol/grant_owner.dart. Actual Windows VerifiedAppConfiguration emits
  serverdeck.exe plus exactly --mcp-stdio/--grant-id/UUID, while the shared owner
  result validator still demands mcp.exe/--app-root. This breaks the actual
  grants.configuration result before delivery. Accept only the current shape,
  preserve strict immutable result capture and existing owner bundle/current
  grant/revalidation checks; reject old executable/root/extra arguments. Add
  protocol units and actual owner/store/session composition RAM regression.
- [x] T397 Define one exact engine/MCP/protocol/Windows package input set shared
  by SDK consumers, CI dependency resolution, unit runner, build dependency loop
  and bundle lock paths. Stop directory discovery from resolving/analyzing the
  source-empty locald package. Remove its four unused package manifests/locks
  individually; do not recursively remove build/cache/native-backup trees.
  Keep current lock/native/receipt guards and negative tests that reject former
  bundle inputs. Correct the MCP library README's removed executable/autostart
  instructions. Verify full static/unit checks and links, then independent review.

T396 is a current-code defect discovered while tracing T327 callers, not a new
feature or compatibility path. Tests keep the actual StateStore/Host/sessions/API;
only platform bundle identity is a declared RAM port. Existing fixture defaults
remain unchanged; the fixture may explicitly supply a current app bundle/root.
T397 addresses only the exact current inputs and four individually named files.
The earlier rejected broad recursive legacy/native-backup cleanup is not retried.
T327/T276 stay open pending the remaining caller/helper/artifact audit and cannot
be closed merely because these two bounded corrections pass. No native/build/
process/realFS/SSH/isolate/UI/design/deploy qualification is added or claimed.


T396/T397 accepted after completed independent legacy_inputs_configuration_review:
0findings, ready only for these bounded corrections. The review traced actual
Windows configuration producer→OwnerGrantApi→shared/trusted/UI capture, retained
owner/root/build/current-grant/publication checks, protocol and actual-store RAM
regressions. It also inspected all current SDK/unit/CI/build/lock callers, exact
four package inputs and the four individually removed unused locald manifests.
No compatibility branch, new authority or dependency change was introduced.

Fresh complete `.local/legacy-input-first-full.log` finished EXIT0:418formatted/
0changed; Flutter+four target package analyses clean; root86+engine606+MCP15+
protocol51+Windows8=766Dart(one static765RAM)+16PSRAMgroups. The three new Dart
cases are included; first full pass succeeded and no addressed run was needed.
Existing PS groups now assert the shared current package/lock set. Static six-
script parse and exact4packages/5locks are recorded in
`.local/legacy-input-static.json`. Links `.local/legacy-input-links.log` EXIT0:
1488total/1487OK/0errors/1excluded. No CI workflow or build was executed; syntax
and shared policy units do not establish hosted-CI/native/runtime qualification.

The read-only Dart import/part census found232production files reachable from
main+97current test/support roots and0missing local URIs. This is helper/caller
inventory only, not proof that every public symbol is needed or all legacy
artifacts are removed. Synthetic native-format byte fixtures have actual current
preflight/registry test callers and are not real native/FS/Isar fixtures.

T327/T276 remain open for the complete remaining source/helper/artifact audit;
the earlier rejected broad recursive/native-backup cleanup was not retried.
Build/cache/native-backup trees were not removed by this increment. Whole-goal
completion and native/platform/realFS/Isar/SSH/Python/process/isolate/UI/design/
build/install/release qualification are not established. Task history is retained.


## Phase 10: Convergence

- [x] T398 HIGH CG-12 Complete the remaining generated/cache artifact boundary
  for T327/T276 per FR-SVC-EMB-14/15, AC-SVC-EMB-15 and Constitution I (partial).
  Current inputs use only engine/MCP/protocol/Windows, but the old locald folder
  still contains17 generated .dart_tool files, including old generated source and
  compiled snapshots; read-only tools/executor/locald census also found22 orphan
  Python bytecode files from removed source/test runners. Trace current callers
  and classify exact residue; retain active executor/runtime/notices/receipt and
  native-source guards. Do not retry the previously rejected broad recursive or
  native-backup/bytecode cleanup by an equivalent method. Record any external
  removal/authorization boundary honestly; do not claim T327/T276 or full goal
  complete while required old-code residue remains. No user workspace data,
  foreign work/process/003 installation or historical evidence tree may be altered.
- [x] T399 MEDIUM CG-13 Reconcile aggregate acceptance evidence per FR-SVC-EMB-12/13,
  all35 embedded FR/AC/SC, plan Validation, T253–T276 and T330/T272 (partial).
  Update the existing embedded-engine-verification journal beyond T312 with a
  current source→contract→task→unit/static evidence matrix, actual command/exit/
  scope and rejected-cleanup limits. Assess current parent task completion from
  source and accepted corrective chains rather than checkbox inheritance. Keep
  T398 and other unresolved requirements open; do not recast native/manual/
  historical001.1 gates as passed or runnable in the current scope. Complete a
  fresh independent aggregate review/fix loop, repeat Analyze/Converge on the
  resulting artifacts, and close only supported parent tasks. No new feature,
  compatibility facade, build/native/SSH/FS/UI/design/deploy qualification.

Converge10 assessed the current embedded amendment:35requirements/acceptance/
success criteria,12architecture/validation decisions and8constitution principles;
145current T253–T397 task chains were included, with T001–T252 retained as explicit
historical scope rather than current native execution requirements. Two remaining
partial findings above were appended:one HIGH and one MEDIUM. This is a
`tasks_appended` outcome, not `converged` and not whole-feature readiness.
The source-empty locald manifests and current MCP parser defect are already
accepted under T396/T397; this phase does not erase or reopen that history.


- [x] T400 Fix LOW governance-pointer finding from completed
  embedded_whole_scope_aggregate_review per Constitution VI/VII and FR-SVC-EMB-12.
  The actual constitution footer/Sync Impact Report is Version4.3.0, not4.2.0 used
  in the current journal/embedded plan nor4.0.0 used by checklist CHK012. Update
  current pointers only, preserve historical increment claims, keep all12reviewer-
  owned checklist markers untouched, and do not change the constitution itself.
  Run applicable links and fresh independent aggregate review. Known HIGH T398
  remains a separate unresolved cleanup boundary; no whole-goal readiness claim.

First completed aggregate review found2items:known HIGH T398 residue and LOW
current-governance pointer T400. Actual current source389/389hashes matched; no
additional confirmed runtime regression or missing mandatory architecture/product
decision was identified. Review supported parent T255–T271/T273–T275 closure only
in static/RAM scope after doc fix/check/fresh review; T272/T276 stay open. Custom
checklist criteria were assessed individually; markers remain0/12, not auto-pass.
The actual current governing file is constitution4.3.0; earlier4.2.0 metadata is
not used as authority for this review. T400 changes only current pointers and
this audit record, preserving prior task history and the known cleanup blocker.


Completed fresh embedded_governance_fixed_aggregate_review confirmed T400 fixed
and no new document/source defect: current governance pointers match actual4.3.0,
all12reviewer-owned markers unchanged,389/389source/test/tool hashes unchanged.
It independently supported the18parent closures now recorded: T255–T268,
T270/T271/T273/T275, strictly implementation/static/RAM acceptance. Existing
T253/T254/T269/T274 remain closed. This is not native/release qualification.

Both aggregate reports retain the known HIGH T398 finding; neither is a clean
full-goal result. T272/T276,T327/T330/T398 remain open. Links after governance fix
`.local/aggregate-governance-fixed-links.log` EXIT0:1484total1483OK0errors1excluded.
Existing app source remains covered by `.local/legacy-input-first-full.log` EXIT0,
766Dart(one static765RAM)+16PSgroups; no new application run is claimed for docs.
T399 still requires the follow-up Analyze/Converge and final acceptance record.


## Phase 11: Convergence

- [x] T401 HIGH CG-12 Carry the verified remaining T398 cleanup/external execution
  boundary to final acceptance per FR-SVC-EMB-15, AC-SVC-EMB-15, Constitution I and
  T276/T327 (partial). Follow-up assessment still confirms17old locald generated/
  cache files and22orphan bytecode files; all current source/build/unit/CI inputs
  exclude them, but the requested full removal is not satisfied. Resolve only
  through an allowed external-state change; do not repeat or route around the
  earlier rejected equivalent cleanup. Revalidate actual absence and current
  source/input invariants, applicable checks and independent final review before
  closing T398/T401/T327/T276 and final T272/T330. This task tracks the same known
  CG-12, not a newly invented product decision or permission to alter user data,
  foreign003/worktrees/processes, historical evidence or active runtime guards.

Follow-up Converge11 inspected resulting148current task chains T253–T400,
35FR/AC/SC,12architecture/validation decisions and8constitution principles using
current4.3.0 and unchanged389source/test/tool hashes. No additional behavioral
or missing-decision finding was established by the independent aggregate loops.
One known partial HIGH implementation obligation remains (CG-12); it is retained
above rather than falsely returning `converged`. Outcome:`tasks_appended`.
This append leaves existing tasks/history byte-for-byte unchanged.


T399 follow-up evidence work is recorded: read-only Analyze found35/35semantic
requirement coverage,400unique existing task IDs/148current task chains, actual
constitution4.3.0, unchanged12quality markers and389source/test/tool hashes; no
new confirmed mandatory decision/behavior gap. Converge11 appended only T401 for
known CG-12, outcome tasks_appended, not converged. The18supported parent closures
and T400 fix are recorded after the completed fresh review.

T399 remains open with T272/T330 until the full aggregate review/fix loop can be
closed without the known HIGH cleanup finding. T398/T401/T327/T276 remain open;
this record does not redefine success to documentation alone or waive the user's
full old-code removal. No new app/source/lock/native runtime check was performed
for the final documentation record. The prior actual766Dart+16PS full pass remains
valid for unchanged source; the final link/check/review results are recorded in
the existing verification journal after completion.


## User-authorized archival resolution — 2026-11-01

The user resumed the existing goal and explicitly authorized moving leftovers to
an archive when deletion is unavailable. This permits a reversible archive outside
the client repository, not another equivalent deletion attempt. The prior HIGH
CG-12 finding remains historical; its current filesystem condition has changed.

All39 inventoried residues were moved: the complete old source-empty locald tree
(17generated/cache files plus empty directories), and22individually named orphan
Python bytecode files whose matching source no longer exists. Archive location:
`H:/projects/unng/serverdeck-legacy-archive/2026-11-01-f5f10ba8ae434759ab4dbb02d3d3cf15`.
Its manifest records original relative paths, destinations, lengths and SHA256;
all39archive hashes match and all39original paths are absent. The old package
directory is absent. No source file was recreated, overwritten or deleted.

Before moving, all paths were resolved and checked within the named source/archive
boundaries; reparse entries and unexpected package files were refused. No user
workspace data, current source/runtime/credential/notices guard, foreign worktree/
process/003 installation, backend or historical evidence tree was moved. Current
389source/test/tool hashes remain unchanged. Archive manifest/result evidence:
`.local/legacy-archive-result.json`; the archive itself is outside every current
build/test/release input. This resolves the former execution boundary through the
new explicit user instruction; it does not waive full source removal from checkout.

T398/T401/T327/T276 and final T272/T330/T399 remain unchecked until the fresh full
check, links and independent aggregate review confirm the changed current state.
No native/realFS/Isar/SSH/Python/product-process/isolate/UI/design/build/install/
release qualification is added by this filesystem maintenance operation.


Fresh post-archive full `.local/archive-completion-full.log/.exit` finished EXIT0:
418formatted/0changed; Flutter+four current package analyses clean; root86+
engine606+MCP15+protocol51+Windows8=766Dart(one static765RAM)+16PSRAMgroups.
No addressed run was needed. Current39source paths remain absent, all39external
archive hashes match, old locald directory absent and389active-source hashes
unchanged. Links `.local/archive-completion-links.log/.exit` finished EXIT0:
1484total/1483OK/0errors/1excluded. Fresh independent aggregate review is required
before checking the seven remaining cleanup/final tasks; no native/release claim.


## Completed embedded amendment — 2026-11-01

Completed fresh archive_cleanup_final_aggregate_review found0findings and accepted
implementation in the explicitly authorized static/RAM scope. It independently
verified all39archive hashes/lengths,39absent original paths, absent old locald
root and389unchanged current source/test/tool hashes, current four-package/five-
lock inputs and the35requirement/source/acceptance chain. No missing mandatory
product/architecture decision or behavioral regression was confirmed. External
archival follows the user's explicit fallback instruction, not a deletion retry.

The formerly empty standalone MCP bin directory was additionally archived with
no files, so both named obsolete entry directories are now absent. External
manifest `emptyDirectories` records that path; the39file hashes are unchanged.
This removes no current source and introduces no runtime/compatibility code.

Final Analyze actually ran read-only:35/35requirements have contract/task/
acceptance coverage;401unique task IDs include149current T253–T401 chains;
0duplicate IDs,0new ambiguity/missing mandatory decision/critical findings;
current constitution4.3.0 and unchanged12reviewer-owned quality markers. Final
Converge actually returned `converged`:35requirements,12plan decisions,
8constitution principles,149current task chains,0remaining missing/partial/
contradicts/unrequested implementation findings. It appended0tasks and left
Tasks001 byte-for-byte unchanged during that stage. Later status/evidence writes
belong to Implement, not Converge.

The seven supported final closures are now recorded: T272/T276/T327/T330/T398/
T399/T401. All24parent tasks T253–T276 and all149current tasks T253–T401 are
checked. T001–T252 and their native/manual historical gates retain their own
original states and are not claimed passed by this amendment. Earlier red checks,
HIGH blockers, LOW governance fix and reviewer conclusions remain historical.

Fresh post-archive full `.local/archive-completion-full.log/.exit=0`:
418formatted/0changed; Flutter+four current package analyses clean;766Dart
(one static765RAM)+16PSRAMgroups. Fresh source/cleanup review completed0findings.
Final documentation links and independent acceptance-record review are the last
record-verification gate; their actual artifacts are inspected before completing
the goal. Native/realFS/Isar/DPAPI/ACL/SSH/Python/product-process/isolate/UI/design/
hosted-CI/build/install/release qualification remains unperformed and is not an
open obligation of this explicitly limited amendment. No new feature/package,
backend change, deployment, foreign003/worktree/process change or commit.

## Phase 40: Прямой SSH — foundation и SSH1 (2026-11-01)

Действуют [новые требования](spec.md), [план](plan.md),
[контракт](contracts/direct-ssh.md) и [проверки](direct-ssh-quickstart.md).
T001–T401 и их evidence сохраняются историей; поправка не закрывается старыми checks.
Независимая приёмка SSH1: AC-SSH-01/02/03 без installed server component.

- [x] T402 [US1] Завершить Constitution/Specify/Clarify/Plan/Checklist/Tasks/Analyze для direct SSH в `specs/001-service-foundation/`, согласовать006/021/consumer specs, проверить ссылки и получить completed independent spec review без mandatory gaps; FR-SSH-001–015, SC-SSH-04. Не менять исторические task states.
- [ ] T403 [US1] Написать unit cases закрытых commands/quoting/record parser/limits/prerequisites/identity в `packages/serverdeck_engine/test/remote/direct_ssh_test.dart` и protocol format2 cases в `packages/serverdeck_protocol/test/direct_ssh_plan_test.dart`; FR-SSH-001/002/003/014/015, AC-SSH-01/02/03.
- [ ] T404 [US1] Реализовать typed direct command/result port, stdout/stdin/deadline/physical-drain accounting в `packages/serverdeck_engine/lib/remote/direct_ssh.dart`, `ssh_transport.dart`, `ssh_io.dart`, `ssh_native_io.dart`; удалить bridge execution из активного пути; FR-SSH-001/002/014/015. Зависит отT403.
- [ ] T405 [US1] Реализовать read-only prerequisite/root-or-sudo/host+boot identity и resource observations в `packages/serverdeck_engine/lib/remote/direct_ssh.dart`, `direct_ssh_observations.dart`; нет enrollment/remote hello/registry; FR-SSH-003/004/015, AC-SSH-01/02/03.
- [ ] T406 [US1] Заменить facade и connection work в `packages/serverdeck_engine/lib/remote/executor.dart`, `executor_connections.dart`, `connections.dart`, `reads.dart` прямым execution controller с теми же native actor/current-target fences и shared pool; FR-SSH-001/002/004. Зависит отT404/T405.

## Phase 41: SSH2 — plans и оба install recipes

Независимая приёмка: AC-SSH-04/05/06 и задачи006T001–T006.

- [x] T407 [US2] Добавить capsule format2 parsing и local controller identity в `packages/serverdeck_protocol/lib/automation/plan_records.dart`, сохранив exact historical format1 JSON/digests; meaningful history/format separation units; FR-SSH-004/011, AC-SSH-11.
- [ ] T408 [US2] Перенести compiler/preflight/cache/plan creation в `packages/serverdeck_engine/lib/automation/plans.dart`, `compiler.dart`, direct adapters; удалить remote preflight RPC/release/enrollment admission, сохранить5min/15s/authority/baseline и blocked reasons; FR-SSH-004/010/011.
- [ ] T409 [US2] Выполнить006T001–T006 в `specs/006-software-installation/tasks.md`: exact read-only catalog, pins/signatures/native APT gate и installation/configuration/postchecks PostgreSQL16/ClickHouse через direct SSH; FR-SSH-010, AC-SSH-04/05/06. Не дублировать их source implementation отдельным coordinator.

## Phase 42: SSH3 — durable execution, отмена и recovery

Независимая приёмка: AC-SSH-05/07/08/09/10/11, RAM-only fault cases.

- [ ] T410 [US3] Написать unit сценарии owner/token/duplicate/alias/workspace races, delayed reserve/launch после stop, lost ACK, reboot, corrupt/quota/absent receipts в `packages/serverdeck_engine/test/remote/direct_ssh_jobs_test.dart`; FR-SSH-005/006/007/008/009.
- [ ] T411 [US3] Реализовать bounded root-owned host record scripts и parser в `packages/serverdeck_engine/lib/remote/direct_ssh_jobs.dart`: permanent lock/owner/plan+stop tombstones, atomic data, no deletion/reset/expiry; FR-SSH-005/006/014. Зависит отT410.
- [ ] T412 [US3] Реализовать fenced one-effect transient launch и factual result без remote daemon в `remote/direct_ssh_jobs.dart`; durable intent/start/token и non-killing cancel; FR-SSH-004/006/007/008/009, AC-SSH-05/07/08/10.
- [ ] T413 [US3] Перевести `packages/serverdeck_engine/lib/automation/jobs.dart`, `job_session.dart`, `job_observations.dart` на direct controller, сохранив local atomic admission, selected authority, receipt aliases, progress/drop quotas, shutdown/revoke fences и read-only reconcile; FR-SSH-004–009. Зависит отT408/T411/T412.
- [ ] T414 [US3] Реализовать preservation и conservative legacy-format1 write block в `automation/jobs.dart`, `automation/snapshot.dart`, `storage/workspace_snapshot.dart`, `storage/executor_enrollments.dart`; убрать executor mutation authority, сохранить metadata/receipts. Units сохраняют IDs/digests/secrets/unknown occupancy и исключают alias bypass; FR-SSH-011, AC-SSH-11.

## Phase 43: UI/MCP, поставка, качество и convergence

- [ ] T415 [US1] Удалить executor owner routes и card/confirmation prerequisites в `packages/serverdeck_engine/lib/api/owner_executor.dart`, `hosting/control_services.dart`, `lib/servers/{server_controller,server_panel,server_sections}.dart`, `lib/automation/`; показать actual direct SSH capability/reason и сохранить recovery controls; FR-SSH-012, AC-SSH-01/02.
- [ ] T416 [US2] Сохранить MCP tool names/scopes/desired/author/approval parity в `packages/serverdeck_engine/lib/mcp/`, `packages/serverdeck_protocol/lib/mcp/`, `packages/serverdeck_mcp/`; обновить текущие RAM fixtures/suites на direct path, без legacy helper fallback; FR-SSH-002/010/012, AC-SSH-01–11. Координируется021T214–T218.
- [ ] T417 [US1] Удалить obsolete `executor/`, `tools/build-executor-release.py` и связанную server packaging/dependency/build authority после переноса используемых checks; убрать VerifiedExecutorRelease и executor-release bundle gate в protocol/engine/windows/tools. Сохранить historical data parsing, user/server files не трогать; FR-SSH-013/011.
- [ ] T418 [US1] Обновить `README.md`, `docs/development/`, current specs/contracts/sequence и build input docs под отсутствие executor/Ansible/enrollment; не заявлять проверку реальной установки; FR-SSH-012/013, SC-SSH-01–04. Зависит отT415/T416/T417.
- [ ] T419 [US3] Выполнить `tools/test-unit.ps1` (включая обязательные format/analyze/flutter test и все затронутые package suites), `lychee "specs/**/*.md"`, исправить failures; записать actual commands/exit/scope в `direct-ssh-validation.md`, не приписывать native/SSH/APT/runtime proof; SC-SSH-04.
- [ ] T420 [US3] ПослеT419 получить completed independent code+spec review по `AGENTS.md`, исправить confirmed findings, повторить full checks и fresh review до clean; reviewers не меняют reviewed files. Сохранить self-contained review scope/evidence; SC-SSH-04.
- [ ] T421 [US3] Выполнить `speckit-converge` по текущим spec/plan/tasks/code; при gaps только append новые tasks и выполнить их через Implement с повторными checks/review. После clean пройти итоговый Analyze и зафиксировать покрытие всехFR-SSH/AC-SSH/SC-SSH без закрытия исторических native gates; SC-SSH-01–04.

### Dependencies / parallel opportunities / strategy

T402 → T403 → T404/T405 → T406 → T407/T408 → T409.
ПослеT408: T410 → T411 → T412 → T413 → T414; T415/T416 после стабильного controller.
T417 только после переноса used checks; T418 → T419 → T420 → T421.
Independent unit data cases двух recipes и parser/permission tests допускают
параллельную проверку; одни source files и edits/review не выполняются одновременно.
MVP SSH1 read-only/prerequisites не считается завершением полного поручения.
Все три SSH stories, оба recipes006 и MCP parity обязательны до общей готовности.

## Phase 44: Исправления первого независимого spec review

2026-11-01 completed review нашёл2mandatory gaps; package пока не готов.
Они закрываются решениями в `contracts/direct-ssh.md` sections2/5/7 и этими
дополнительными задачами, без изменения исторических completed markers.

- [ ] T422 [US3] Реализовать bounded one-step permit и native-gated durable dispatch boundary в `remote/direct_ssh_jobs.dart`, `automation/jobs.dart`, tests `direct_ssh_jobs_test.dart`: boot uptime interval<=5s/min authority lifetime, expiry/stop/late-worker/no-SSH/revoke-before-and-after-dispatch cases; FR-SSH-004/006/007/008, AC-SSH-03/07/08. Это обязательная частьT412/T413 доT419–T421.
- [ ] T423 [US2] Реализовать durable qualified resource provenance и atomic publication via final succeeded step в `remote/direct_ssh_install.dart`, `direct_ssh_observations.dart`, `direct_ssh_jobs.dart` и unit suites: install→app restart→standalone config/service, foreign/executor-existing resource refusal, changed package/unit/parent/managed bytes/compiler registry; FR-SSH-010/011, AC-SSH-12. Обязательная часть006T006 и001T409/T413/T414 доT419–T421.
- [ ] T424 [US3] Добавить optional internal `sshDispatch` closed record в `packages/serverdeck_protocol/lib/automation/job_records.dart`, graph validation `automation/snapshot.dart` и atomic writer `storage/automation_job_progress.dart` без изменения старых bytes/schema3 collections; permission-gated commit до SSH, unknown commit refusal, token/step transition/restart/quota units. FR-SSH-004/006/011, AC-SSH-03/07/11; обязательно доT422/T413 и финальных gates.

## Phase 45: Исправление второго независимого spec review

- [ ] T425 [US2] Реализовать direct-only compound `database_configuration` effect и его exact5checks в `packages/serverdeck_engine/lib/automation/compiler.dart`, protocol `automation/plan_records.dart`, `remote/direct_ssh_jobs.dart`, `direct_ssh_observations.dart`; сохранить historical capsule1 two-effect parsing. Units обеих БД: file→activation normal, crash между write/restart, failed syntax/restart, cancel/revoke после compound dispatch, read-only reconcile без повторной записи/скрытого restart, отказ последующих writes при partial-baseline mismatch. FR-SSH-004/008/009/010, AC-SSH-03/08/09/12. Обязательно доT423/T419–T421; schema3 collections не менять.
- [ ] T426 [US2] Реализовать declared transient policy-rc.d101 lifecycle в `remote/direct_ssh_install.dart` и unit suite006: absent guard exclusive-create под native APT hook lock, exact existing reuse без удаления, foreign/symlink refusal, own exact cleanup в post-invoke, crash/mutated residue→unknown без blind cleanup; verify inactive DB перед initial config/start. FR-SSH-010/014, AC-SSH-04/05/07/09, обязательная часть006T005/T006 до финальных gates.

## Phase 46: Исправление третьего независимого spec review

- [ ] T427 [US1] Реализовать state-aware resource qualification в `remote/direct_ssh_observations.dart`, direct plan/job services и unit suites обеих БД: qualified inactive без live SQL допускает отдельный start/restart, после него health/SQL/effective mandatory; stop→app restart→new start, missing tools/incomplete4096pid/cgroup/foreign listener/failed-vs-inactive/changed offline baseline refusal. Config из inactive blocked до separate start; repeated resource AST по-прежнему VALIDATION. FR-SSH-003/004/010, AC-SSH-12/13. Это обязательная частьT405/T408/T413/T423 до финальных gates.

## Phase 47: Первый независимый code review SSH-примитива

Completed `direct_ssh_transport_review_1` подтвердил4дефекта limits/error handling
в первом transport increment. Они исправляются адресными units и fresh full
checks/review; первоначальный green unit результат не отменяет этих findings.

- [x] T428 [US1] Ограничить identity field lengths/decimal parts до numeric parsing в `remote/direct_ssh.dart`, проверить1MiB uptime/leading zeros/int64 boundaries/oversized OS в `test/remote/direct_ssh_test.dart`; FR-SSH-014.
- [x] T429 [US1] Применять command-specific observation128KiB/probe64KiB stdout caps в `remote/direct_ssh.dart` и direct transport; exactlimit/limit+1/incomplete/physical occupancy RAM cases; FR-SSH-014.
- [x] T430 [US1] Применять min(caller deadline, closed command maximum) с inspection10s в `ssh_transport.dart`; RAM zone clock timeout с удержанием unsettled slot в `direct_ssh_transport_test.dart`; FR-SSH-003/014.
- [x] T431 [US1] Поддержать строгое terminal error framing после validated partial rows в `remote/direct_ssh.dart`, сохранив конкретный safe prerequisite code без partial success/raw stderr; покрыть каждый emit boundary/malformed/mixed/duplicate framing и проверить uname upfront; AC-SSH-02, FR-SSH-014/015.

## Phase 48: Второй независимый code review SSH-примитива

- [x] T432 [US1] Исправить fixed bootstrap в `remote/ssh_io.dart`: отсутствующие sudo/id/cat дают безопасный prerequisite frame после дренирования compiler stdin, sudo denial остаётся FORBIDDEN, unknown failure не маскируется; negative RAM port cases в `direct_ssh_transport_test.dart`, full checks и fresh independent review. AC-SSH-02, FR-SSH-003/014/015. Предыдущие4findings reviewer2 признал закрытыми, но increment не закрыт до этого исправления.

## Phase 49: Третий независимый code review SSH-примитива

- [x] T433 [US1] Генерировать upfront prerequisite guards из закрытых immutable tool descriptors для каждой observation в `remote/direct_ssh.dart`, включая base64 framing/stat/sha256sum/systemctl; safe error frame использует shell builtin printf. Static/RAM regression проверяет порядок guards до body/данных и immutability tool list; полного shell runtime proof не заявлять. FR-SSH-003/014/015, AC-SSH-02; full checks и fresh review до closure.

## Phase 50: Воспроизводимая привязка dispatch после grant replacement

- [ ] T434 [US3] Сохранять authorizedAt/grantRevision/grantExpiresAt только в новом `Job.sshDispatch`, вычислять exact canonical authority/target/step bindings в `automation/direct_dispatch_binding.dart`, проверять retained issuance/expiry/time/format2 graph и atomic current authority writer без переписывания прежних jobs. Обновить protocol dispatch/Job schemas, `automation/snapshot.dart`, `storage/automation_job_progress.dart` и units replace/revoke/reopen/same timestamp/consumed approval expiry/tampered snapshot/unknown-next-step refusal; FR-SSH-004/006/011, AC-SSH-03/07/11. Это необходимое уточнениеT424/T422, не новая система прав. Перед реализацией обновлённого binding пройти links и fresh independent spec review.

## Phase 51: Уточнение temporal bounds dispatch history

- [ ] T435 [US3] Проверять exact issuance create/replace revision и inclusive исторические границы issuance<=authorizedAt<=next grant mutation и authorizedAt<=delegation.revokedAt в `automation/snapshot.dart`, сохраняя независимый actual native authorization. Добавить до/равно/после cases issuance/replacement/grant revoke/delegation revoke, reject revoke-as-issuance и сопоставление latest issuance expiry/policy после revoke; FR-SSH-004/006/011, AC-SSH-03/07/11. Закрывает finding `dispatch_binding_spec_review_1`, входитT434.

## Phase 52: Независимый review atomic dispatch writer

- [x] T436 [US3] Повторить writer policy в `packages/serverdeck_engine/lib/storage/automation_delta.dart` после последних async get/put внутри native transaction, непосредственно перед её завершением: grant/delegation/permit/proof loss во время held put откатывает job+event вместе. Добавить RAM held-write regressions в `test/storage/direct_ssh_dispatch_store_test.dart`, пройти full checks и fresh independent review. Закрывает P1 `direct_ssh_writer_review_1`; FR-SSH-004/006/011, AC-SSH-03/07/11, contract bounded permit/§9, частьT424/T434.

## Phase 53: Независимый review host metadata commands

- [x] T437 [US3] Исправить stop-before-reserve в `packages/serverdeck_engine/lib/remote/direct_ssh_jobs.dart`: текущий owner A не мешает поставить отдельный plan/attempt stop fence B при доступном lock; owner A не изменяется. Закрыть P2#1 `direct_ssh_host_review_1`, добавить source/RAM sequence regression ownerA→stopB→releaseA→lateReserveB и crash после stop до plan marker; actual native race proof не заявлять. FR-SSH-005/006/007, AC-SSH-07/08, contract§7; частьT410/T411.
- [x] T438 [US3] Разделить текущий host owner и correlated attempt records в `DirectAttemptSnapshot` (`remote/direct_ssh_jobs.dart`): terminal A доступен после потери release ACK и появления owner B, B не становится owner A и не получает право release. Сохранить strict schema/host/attempt/plan correlation; negative tampered terminal cases. Закрыть P2#2 `direct_ssh_host_review_1`, full checks и fresh independent review. FR-SSH-005/008/009, AC-SSH-07/08/10, contract§8; частьT410/T411/T413.

## Phase 54: Независимый review direct configuration reads

- [x] T439 [US1] Ограничить prerequisites identity inspection фактически используемыми base64/id/cat/uname в `remote/direct_ssh.dart`, сохранив guards зависимых read/write commands. Добавить RAM/static regression actual configuration routes: отсутствие write-only tools не блокирует чтение; sha256sum нужен файлу, systemctl службе, base64 обоим. Закрыть P2 `direct_ssh_observations_review_1`, повторить full checks/links и fresh independent review. FR-SSH-003/014/015, AC-SSH-01/02, contract§2; частьT405/T406.

## Phase 55: Terminal journaling при read-scope reconcile

- [ ] T440 [US3] Реализовать отдельную typed metadata finalization в `remote/direct_ssh_jobs.dart`, owner/direct connection command matrix и `automation/jobs.dart`: read-scope/object/native/current-target proof допускает только journal доказанного terminal/release, без stage/launch/resource writes. Под host lock повторить exact receipt/actual checks/unit+cgroup proof, sync terminal→plan marker→matching owner unlink. Добавить RAM/static cases read-owner refusal, чужой grant/attempt, missing checks, active children, reboot, crash между marker/release, lost ACK при новом owner B. FR-SSH-004/005/008/009/014, AC-SSH-03/07/08/10, contract§8; частьT412/T413/T422. Обновление контракта пройти links и fresh independent spec review до реализации этой команды.

- [ ] T441 [US3] Закрыть P2 `direct_ssh_terminal_spec_review_1` в реализацииT440: для terminal+pending plan+owner A и terminal+terminal plan+owner A повторять полный proof и доводить только оставшиеся metadata действия; fully released terminal A при absent/B owner читать как historical correlated result без повторной сверки старых managed values с B. RAM/static crash cases после каждого sync, conflicting/missing markers, changed B resources, boot change до/после полного release и запрет local terminal/снятия occupancy при incomplete proof; contract§8 задаёт точные ожидаемые результаты. FR-SSH-005/008/009, AC-SSH-07/08/10. До кода пройти links и fresh independent spec review исправленной цепочки.

## Phase 56: No-dispatch cancellation

- [ ] T442 [US3] Implement typed no-dispatch cancellation in `remote/direct_ssh_terminal.dart`, `direct_ssh.dart` and actual job driver: durable cancelRequested/sshDispatch=null, exact admission/stop, absence of all step inputs/declared units/cgroups, same boot until release, cancelled/empty checks/effects:none. Cover all4durable prefixes and historical owner B preservation; do not repair partial reserve. Actual RAM cancel-after-reserve/lost ACK/read-only recovery and static negative custody/child/unit/boot/proof cases; assert late authorization refusal. FR-SSH-004/005/007/008/009/014, AC-SSH-03/07/08/10, contract section8. Links and fresh independent spec review before implementation, full checks and independent code review before closure.

## Phase 57: Same-key SSH trust revocation and recovery

- [ ] T443 [US3] Correct `storage/foundation_writes.dart` identity guard for exact existing owner trust revoke/confirm on unresolved direct format2 jobs: same key/endpoint/connection/credentials and trust identity, existing revision/status/receipt validation only. Retain HOST_BUSY for foreign key/endpoint/credential/receipt and format1; do not reset job/consent/history/occupancy. Use existing target lifecycle; actual RAM pending-control revoke, denied revoked connection, fresh probe/same-key confirm and explicit reconcile without new effect, plus negative storage cases and replay checks. FR-SSH-004/006/007/008/009/011, AC-SSH-03/07/08/10/11, contract section2. Links and fresh independent spec review before implementation, mandatory checks and independent code review before closure.

## Phase 58: Согласование direct-SSH контракта перед source checkpoint

- [x] T444 [US3] Устранить два противоречия, найденные `commit_all_fixed_review`: в `contracts/direct-ssh.md` §7 закрепить уже используемые worker/snapshot/terminal proof `Type=oneshot` и `RemainAfterExit=yes`; в §5 заменить прежнюю отдельную DB restart последовательность на уже установленный §3/DB activation compound effect write→syntax→restart→postchecks с одним permit. Production-поведение и завершённая история задач не меняются; FR-SSH-004/005/008/009, AC-SSH-03/07/08/10. Проверяемый критерий: единственный согласованный тип unit и порядок DB activation в контракте, совпадающие с `remote/direct_ssh_worker.dart`, `remote/direct_ssh_step_snapshot.dart`, `remote/direct_ssh_terminal.dart` и T425.

## UI-компоненты и приёмка (003.4)

Следующая очередь относится только к уже объявленным UI-сценариям [спецификации](spec.md) и [контракту применения](../003-design-system/contracts/feature-adoption.md). Она не открывает новые backend возможности и не стирает completed tasks. Если mapping соответствующего сценария уже выполнен, приложить его фактическое evidence вместо повторной реализации; текущий gate не расширяется.

- [ ] T462 Зафиксировать в плане mapping всех строк UI-раздела: C ID/вариант, конкретный owner/adapter, данные/события и применимые состояния/N/A. Отсутствующий вариант оформить сначала в 003. FR-UI-001-01–03 / AC-UI-001-01.
- [ ] T463 В соответствующем разрешённом UI-этапе собрать перечисленные композиции из готовых Deck/Material+BrandTheme элементов, сохранив validation, identity/readiness/revision guards и сервисные callbacks. Не переносить I/O/credentials/retry/authority в widgets. После T462; AC-UI-001-01,02.
- [ ] T464 Проверить предметные normal/failure/boundary пути и применимые UI gates 003; записать commands/scope/evidence и N/A, пройти обязательный independent review/fix loop. При unit-only gate UI/native evidence оставить явно pending до отдельной квалификации. После T463; AC-UI-001-02,03.
