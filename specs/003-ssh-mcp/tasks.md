# Tasks: 003 — SSH и локальный MCP

**Prerequisite**: runtime002 полностью выполнен с clean review; [Plan](plan.md),
[data-model](data-model.md), [contracts](contracts/operations.md). Ниже только задачи,
а не выполненная реализация. Строго использовать C ID001; без screen design tests.
**Политика 2026-11-03:** только юнит-тесты, без integration/e2e/VM/process-kill.
Незавершённые T022/T023 пересмотрены до реализации согласно указанию пользователя;
это не результаты проведённых интеграций. Dependencies002 завершены по
[unit-only итог002](../002-desktop-runtime/reviews/unit-only-final.md).

## Phase 1 — Setup

- [X] T001 Закрепить pristine dartssh2-4.1.0 archive/hash/license и policy patch в `third_party/dartssh2/`, `patches/dartssh2-4.1.0-policy.patch`, `pubspec.yaml`, `pubspec.lock`; проверить только описанные raw-blob/rekey/method/timer изменения (FR-303, FR-307, FR-314, FR-317).

## Phase 2 — Foundational

- [X] T002 Расширить полный schema set2 и migration-copy publication в `lib/storage/records.dart`, `lib/storage/migrations.dart`; профиль/credentials/trust/grants/receipts/SecurityState, no old-schema partial open (FR-301–306, FR-308, FR-325, FR-328, FR-332).
- [X] T003 Создать typed AppOperations/DTO/UiActor/McpActor и bounded writer gate в `lib/domain/app_operations.dart`, `lib/domain/actor.dart`, `lib/domain/models.dart`; authorize/version checks и endpoint fences (FR-312, FR-316, FR-323–324, FR-328–331).

## Phase 3 — US1 Сохранённые профили

**Independent acceptance**: AC-301–304, SC-301/306, fake snapshot re-open/data/error unit tests без сети.

- [X] T004 [US1] Добавить profile/credential/refcount/atomic error/injected rollback unit tests в `test/domain/profile_store_test.dart`, `test/domain/credential_test.dart`, `test/storage/format2_migration_test.dart` (FR-301–306, FR-308, FR-313, FR-318).
- [X] T005 [US1] Реализовать validation/protect original key bytes и cancellable parsing isolate в `lib/profiles/credential_input.dart`, `lib/profiles/credential_parser.dart`; passphrase never persisted/reformatted key, password exact (FR-302–305).
- [X] T006 [US1] Реализовать concrete profile AppOperations с общим DomainCommandGate и create/update/UI-only delete/refcount+receipt atomic writes в `lib/domain/app_operations.dart`, `lib/storage/workspace_store.dart`; actor cannot be forged in JSON (FR-301, FR-306, FR-308, FR-313, FR-324, FR-328).
- [X] T007 [US1] Подключить C02/C03/C04/C07/C09/C10/C11/C12/C13/C14/C18 к profiles UI/controller в `lib/profiles/profile_controller.dart`, `lib/profiles/profile_view.dart`, `lib/profiles/profile_form.dart`, `lib/app.dart`; profile CRUD functional tests в `test/profiles/profile_actions_test.dart` (FR-301–306, FR-320–321).

## Phase 4 — US2 Подключение и первое доверие

**Independent acceptance**: AC-305–309, SC-302–303/305, in-memory protocol unit fixtures.

- [X] T008 [US2] Добавить in-memory byte-stream unit tests auth order/raw fingerprint/one auth method/cancel/timeout в `test/connections/ssh_policy_test.dart`, `test/connections/network_budget_test.dart`; synthetic key material only (FR-303–304, FR-307, FR-309, FR-314–319).
- [X] T009 [US2] Реализовать patched SSH adapter, выбранные algorithms, network/crypto error mapping в `lib/connections/ssh_transport.dart`; host callback mandatory, no shell/exec/agent/none fallback (FR-303–304, FR-307, FR-309, FR-314, FR-319).
- [X] T010 [US2] Реализовать attempt/session generation, own30s budget/prompt5min/watchdog15+10 и shutdown capability в `lib/connections/connection_owner.dart`, `lib/connections/network_budget.dart`, `lib/connections/owned_dial.dart`; сохранение before auth, late callbacks fenced (FR-309, FR-312, FR-314–318).
- [X] T011 [US2] Подключить C02/C03/C10/C11/C12/C14/C18 для connect/cancel/disconnect/passphrase/first trust в `lib/profiles/profile_controller.dart`, `lib/profiles/profile_view.dart`; action/state tests в `test/profiles/connection_actions_test.dart` (FR-304, FR-307–309, FR-314–315, FR-320–321).

## Phase 5 — US3 Изменение доверия

**Independent acceptance**: AC-310–313, SC-304–305; B→C stale decision, matchingA retain.

- [X] T012 [US3] Добавить persistent warning/nonce/revisions/endpoint-manyprofiles/rekey/race tests в `test/domain/trust_lifecycle_test.dart` и `test/connections/rekey_test.dart` (FR-308–313, FR-316).
- [X] T013 [US3] Реализовать trust owner/challenge/replace/retain/quarantine и store txn в `lib/trust/trust_owner.dart`, `lib/storage/workspace_store.dart`; переименование не рвёт SSH, stale profile consent rejected (FR-308–313, FR-316).
- [X] T014 [US3] Подключить C10/C11/C14/C18 warnings в списке/подробностях и exact-fingerprint actions в `lib/profiles/profile_view.dart`, `lib/profiles/profile_controller.dart`; functional fake-snapshot/actions unit test в `test/profiles/trust_actions_test.dart` (FR-310–313, FR-320–321).

## Phase 6 — US4 MCP поверх приложения

**Independent acceptance**: AC-314–322, SC-307–309; same application/operations, no delete.

- [X] T015 [US4] Добавить grant issue/rotate/revoke/expiry/exportPending/clockrollback tests в `test/mcp/grant_test.dart`, `test/mcp/authorization_race_test.dart`; stale replay cannot bypass current auth (FR-325, FR-328, FR-331–334).
- [X] T016 [US4] Реализовать canonical grant owner/OperationState auth binding/DPAPI export reconciliation/24h receipts в `lib/mcp/grant_owner.dart`, `lib/storage/workspace_store.dart`; admission blocks unsynced grant, durable revoke before success (FR-325, FR-328, FR-331–332).
- [X] T017 [US4] Реализовать stdio branch/native Named Pipe/peer identity/framing/limits в `native/bootstrap/main.cpp`, `native/bootstrap/mcp_pipe.cpp`, `native/include/mcp_pipe.h`, `native/include/mcp_json.h`, `windows/runner/platform_channel.cpp`, `lib/mcp/pipe_adapter.dart`; no Flutter/Isar in helper, no auto-start GUI (FR-322, FR-326, FR-330, FR-333–334).
- [X] T018 [P] [US4] Создать exhaustive13tools/schema/protocol/delete-bypass tests в `test/mcp/router_contract_test.dart`, `native/tests/ipc_auth_test.cpp`; проверить root Tool definitions/tools-list по официальной MCP2025-11-25 schema, null/fractional/duplicate request IDs до эффекта; build input/output contracts from `specs/003-ssh-mcp/contracts/mcp-tools.json` (FR-323–324, FR-326–329, FR-333).
- [X] T019 [US4] Реализовать allowlist router и built-in schema validation/typed result projection в `lib/mcp/router.dart`, `lib/mcp/tool_schemas.dart`; валидация extras/unknown methods/non-null unique request IDs до domain dispatch, корректные root type object Tool schemas, no actor/secret result/delete (FR-322–324, FR-327–329).
- [X] T020 [US4] Подключить C02/C03/C04/C10/C11/C13/C18 к grant settings и wiring owner capabilities в `lib/mcp/settings_view.dart`, `lib/mcp/settings_controller.dart`, `lib/app.dart`; готовые command/args без token, UI revoke/rotate tests в `test/mcp/settings_actions_test.dart` (FR-325, FR-330–334, FR-320–321).
- [X] T021 [US4] Закрыть UI/MCP concurrency/idempotency/revoke/expiry/exit ordering в `lib/domain/app_operations.dart`, `lib/mcp/grant_owner.dart`, `test/mcp/shared_operations_test.dart`; connect/input/trust используют shared current generations (FR-312, FR-316, FR-323, FR-327–331).

## Phase 7 — Cross-cutting

- [X] T022 Дополнить изолированные SSH unit fixtures в `test/connections/` и `test/fixtures/ssh/`: password/encryptedkey/A→B/rekey/blackhole/cancel на memory streams, synthetic keys и fake clock/parser; без TCP/SSH-сервера, процессов или production credentials (FR-303–319, SC-301–306).
- [X] T023 Дополнить изолированные stdio/IPC/Windows identity/export unit fixtures в `test/mcp/`, `native/tests/ipc_auth_test.cpp`: EOF/owner absent/trayhidden/exit/13tools, partial frames, fake peer identities/ACL/DPAPI failures; без sameEXE subprocess/Isar/VM. Подключить только unit checks и static build/import audit в `.github/workflows/release.yml` (FR-322–334, SC-307–309).
- [X] T024 Выполнить обязательные format/analyze/flutter test/boundary, native unit, build/static manifest/import checks, lychee и clean independent review; фактические результаты/ограничения записать в `specs/003-ssh-mcp/reviews/implementation.md`. Не запускать и не требовать интеграционные/VM проверки (FR-321).

## Dependencies / independent increments

002:T042 (completed) → T001–003 → US1:T004–007 → US2:T008–011 → US3:T012–014 →
US4:T015–021 → T022–024. US3 требует working handshake seamUS2; US4 не отдельный
сервер, включается в уже работающее приложение. T018 можно писать после typed
contractT003 параллельно native implementationT017; production UI shared files
не редактировать параллельно. MVP: UI profiles+SSH+trust US1–US3; законченная003
обязательно включаетUS4. Разработка только MCP до приложения не планируется.

## Traceability

| Requirement | Contract / model | Implementation+test tasks | Acceptance |
| --- | --- | --- | --- |
| FR-301 | operations/data-model | T004,T006,T007 | AC-301–304,SC-301 |
| FR-302 | operations | T004,T005,T007 | AC-303,SC-301 |
| FR-303 | ssh/credentials | T001,T004,T005,T008,T009,T022 | AC-302/303,SC-301 |
| FR-304 | ssh/operations | T005,T008,T009,T011 | AC-308,SC-303 |
| FR-305 | storage002/data-model | T002,T004,T005 | SC-306 |
| FR-306 | operations/data-model | T002,T004,T006 | AC-304,SC-306 |
| FR-307 | ssh | T001,T008,T009 | AC-305/306,SC-302 |
| FR-308 | data-model/trust | T002,T004,T006,T012,T013 | AC-310–313,SC-304 |
| FR-309 | ssh/operations | T008,T010,T011 | AC-305–307,SC-302/303 |
| FR-310 | operations/trust | T012,T013,T014 | AC-310/311,SC-304 |
| FR-311 | operations/trust | T012,T013,T014 | AC-312/313,SC-304 |
| FR-312 | operations | T003,T010,T012,T013,T021 | AC-313,SC-305 |
| FR-313 | data-model/operations | T004,T006,T012,T013 | AC-304,SC-306 |
| FR-314 | ssh/operations | T001,T008,T009,T010,T011 | AC-307–309,SC-303 |
| FR-315 | operations/DTOs | T008,T010,T011 | AC-307–309,SC-303 |
| FR-316 | operations | T003,T010,T012,T021 | SC-305 |
| FR-317 | ssh/network budget | T001,T008,T010 | SC-305 |
| FR-318 | ssh/storage002 | T004,T008,T010,T022 | AC-309,SC-303/306 |
| FR-319 | operations/ssh | T008,T009,T022 | AC-308,SC-303 |
| FR-320 | plan001 | T007,T011,T014,T020 | functional UI actions |
| FR-321 | quickstart/constitution | T004,T008,T012,T015,T018,T024 | SC-301–309 |
| FR-322 | ipc/runtime002 | T017,T019,T023 | AC-315/318,SC-307/308 |
| FR-323 | operations/mcp-tools | T003,T018,T019,T021 | AC-315/316,SC-307 |
| FR-324 | operations/mcp-tools | T003,T006,T018,T019,T023 | AC-317,SC-307 |
| FR-325 | mcp-access/ipc | T002,T015,T016,T020 | AC-314/320,SC-308/309 |
| FR-326 | ipc/mcp | T017,T018,T023 | AC-320/321,SC-309 |
| FR-327 | operations/ssh/mcp | T018,T019,T021 | AC-316,SC-307 |
| FR-328 | operations/receipt | T002,T003,T006,T015,T016,T021 | AC-319,SC-308 |
| FR-329 | operations/mcp | T003,T018,T019 | AC-314–317,SC-307 |
| FR-330 | runtime002/ipc | T017,T020,T023 | AC-318,SC-308 |
| FR-331 | mcp-access/operations | T003,T015,T016,T021 | AC-322,SC-309 |
| FR-332 | mcp-access/data-model | T002,T015,T016 | AC-321/322,SC-309 |
| FR-333 | ipc | T017,T018,T023 | AC-321,SC-309 |
| FR-334 | mcp-access/ipc | T015,T017,T020,T023 | AC-320,SC-309 |


## История доработки спецификаций по независимому review

[2026-11-02 protocol review](reviews/2026-11-02-plan-round1.md): R001/R002 —
выполненные исправления документов. Регрессии будущей реализации закреплены в
существующих T018/T019; ни одна задача приложения не объявлена выполненной.


## Phase 8 — Recovery decisions from package review, 2026-11-03

- [X] T025 Реализовать durable authorizationEpoch/high-water clock guard по data-model: rollback блокирует старые grants; rotation A не оживляет B, restart/failed-persistence fail closed. Дополнить T015/T016 fake-clock/snapshot unit tests двух grants и повторного rollback (FR-325/331–332, review003 R003).
- [X] T026 Реализовать endpoint/grant quarantine и CLEANUP_REQUIRED по operations recovery contract:5s bounded exact-handle cleanup retry, read availability, pending grant version/export reconciliation, restart, repeated failure и отсутствие auto-reconnect/new secret on retry. Дополнить T010/T013/T015/T021 unit tests (FR-312/316/318/331, review003 R004).

T025 — prerequisite grant acceptance T015/T016; T026 — prerequisite fault/recovery
acceptance T010/T013/T015/T021. Финальный gate T024 требует их выполнения.


## Phase 9 — Vendor reproducibility review fixes

- [X] T027 Нормализовать hashed vendor sources/added files и policy patch в LF согласно .gitattributes; пересчитать manifest, проверить provenance в checkout representation и forward/reverse apply на pristine scratch tree. Дополнить static build guard reverse-check; выполнить mandatory checks и fresh review перед закрытием T001 (T001, FR303/307, reviewT001 P1/P2).


## Phase 10 — Exact SSH signature policy

- [X] T028 В составе T009 проверить embedded RSA signature.type на соответствие negotiated rsa-sha2-256/512 и запрету SHA1; upstream verify выбирает digest из signature.type, поэтому одной hostkey allowlist недостаточно. Расширить policy patch/provenance в разрешённом ssh_transport.dart и T008/T022 in-memory unit vectors: negotiated RSA-SHA2 с ssh-rsa/SHA1 signature отклоняется до host acceptance/auth; корректные RSA-SHA2 принимаются по обычному trust flow (FR307/314, SSH contract No SHA1 signatures, reviewT001 round2 implementation note).

T028 обязателен до закрытия algorithm-policy T009 и финального T024.


## Phase 11 — DPAPI credential bounds

- [X] T029 При реализации T005/T016 согласовать native secret.protect input<=1MiB и secret.unprotect ciphertext<=2MiB: DPAPI overhead не должен делать допустимый private key1MiB нечитаемым. Проверять output plaintext bounds, очищать buffers и добавить isolated native boundary fixtures; без real Isar/SSH и интеграционных процессов (FR303/305/332, Credential protectedBytes<=2MiB).


## Phase 12 — Credential review corrections

- [X] T030 Исправить normalizeHost по FR-308: снять одну пару скобок корректного IPv6 и сохранить общую endpoint identity; отвергать zones/embedded ports/nested brackets, согласовать data-model и unit cases. Очистить отправительскую копию parsed key после isolate SendPort.send до natural exit; rerun mandatory checks и fresh independent review (T005, review_credentials_1 P2).


## Phase 13 — Passphrase error mapping

- [X] T031 Для поддерживаемого encrypted OpenSSH container явно отличить отсутствующую passphrase (PASSPHRASE_REQUIRED) от пустой предоставленной (PASSPHRASE_INVALID/passphrase); regression units Ed25519/RSA. Сохранить original key/password и фиксированные ошибки, rerun checks/fresh review (T005, FR304/AC308, review_credentials_2 P2).


T006 foundation progress: DomainRepository/WorkspaceStore consistent+ambient reads,
private DomainCommandGate.prepare and ReceiptSigner implemented with focused units.
This does not close T006 or T004: profile CRUD/refcounts/atomic receipts and canonical
owner bindings still need implementation. Foundation evidence/review tracked in
[implementation journal](reviews/implementation.md).


## Phase 14 — Shared profile validation and wire payload identity

- [X] T032 Убрать raw maxLength100 из ProfileInput/ProfilePatch displayName schemas: FR302 ограничивает имя после trim, общий domain validator сохраняет scalar bound100. Frame limit ограничивает raw input; outputProfileView сохраняет100. Проверить13Tool/26schemas по pinned MCP schema и positive raw padded100 case; закрепить omitted port vs explicit22 и canonical base64 для receipt payload до T018/T019 (FR302/323/328).

T007 controller/form units can proceed afterT006; its production composition wiring
requires real ConnectionOwner/ConnectionVersionState fromT010 and trust projections
fromT013. Do not put a fake/no-op transport or allow-all grant state in production
for an interim UI. Complete those owner seams then wire T007/T011/T014 together;
T020 later registers complete grants/pipe/runtime capabilities. This refines wiring
order only, preserves US1–US4 product scope and all task history.


## Phase 15 — Concurrent update replay before close admission

- [X] T033 Исправить delayed duplicate connection-affecting update: authorized receipt lookup в той же gate фазе ДО revision/fence/invalidation/close и повторно до post-close fence. ProfileConnectionPort возвращает replay либо confirmed-close fence; error recovery сначала разрешает уже committed receipt без нового эффекта. Unit cases задержки protect/close admission, deletion послеcommit и late protection failure; один commit, replay IDs/revision, никаких новых close послеreceipt. Rerun mandatory checks и fresh review (FR328, review_profiles_1 P2, T004/T006).


## Phase 16 — Bound untrusted host signature CPU

- [X] T034 До закрытияT009 вынести host signature verification в cancellable owned-isolate pool4/<=30s по SSH contract, async vendor hook before host acceptance, pure shared verifier preservesT028 exactalg policy. Ограничить bytes доdispatch, admission/stop/late/exit-confirmed retry; strict adapter всегда устанавливаетhook. Fake-worker/deadline+memory KEX units prove budget/cancel/no-auth and static patch/provenance checks. Синхронный RSA verify с server-controlled exponent не должен блокировать owner timer/UI; не добавлять произвольный product key-size policy или integration gate (FR307/314/317, T008/T009/T010).


## Phase 17 — Bound buffered bytes across asynchronous handshake waits

- [X] T035 Ограничить суммарный receive backlog SSHTransport<=1MiB ДО buffer.add, в том числе во время async signature/trust waits. Overflow закрывает транспорт фиксированным SSHResourceLimitError; late positive result не продолжает callback/NEWKEYS/auth. Single-chunk и cumulative small-chunk memory unit cases для обоих ожиданий; фиксированный RESOURCE_EXHAUSTED mapping вT009. Никаких TCP/server/process tests (FR307/314/317, T008/T009/T034).

T034 progress: shared owned-work reservation/lifecycle core now reused by private
key parser and separate host-signature pool (4slots each), async hook and canonical
pure vendor verifier implemented. T034 remains open until strict adapterT009 installs
the pool and maps its fixed failure reasons. T035 resource guard/typed carrier and
units are implemented, mapping/whole adapter acceptance remainsT009. Review evidence
covers components only; no production SSH/AppOperations connection wiring claimed.


## Phase 18 — Bound private authentication signing CPU

- [X] T036 ДоT009 реализовать async SSHIdentity + root-owned private signing pool4/<=remaining30s на owned_work, исходные key bytes<=1MiB/passphrase<=64KiB/sign challenge<=2MiB. Public-only bounded hint reader без private math; parse/validate/sign выполняются внутри owned isolate, возвращается только signature, private material/buffers очищаются. Freeze selected Ed25519/RSA-SHA2 scheme per attempt, defaultRSA256 без server-sig-algs, предпочестьRSA512 если advertised, no overlap→UNSUPPORTED_SERVER, без fallback послеfailure. Metadata/public hint связаны с credentialRevision; passphrase prompt только после verified+accepted host и recheck перед auth. Fake-worker/real synthetic sign/cancel/late/exit units, строгий adapter не передаёт synchronous parsed-key signer в SSHClient (FR303/304/314/317, T005/T008/T009/T010).


## Phase 19 — Late successful completion deadline fence

- [X] T037 Закрыть замечание review_003_timers_1: отделить NetworkBudget.tryComplete от cancel/error finish, fresh monotonic deadline check перед connected внутри guarded owner transition; no success while prompt pending, expired/ended returns false, timeout once. Fake-clock boundary success-before/at30s, undelivered timer, active/expired prompt и late callbacks; установить обязательный binding в T010 (FR317/318,T008/T010).


## Phase 20 — Strict transport byte ownership and terminal races

- [X] T038 Исправить подтверждённые замечания review_003_strict_adapter_1: raw IOSink получает отдельную immutable wire copy без последующей мутации; bounded packet/byte reservation удерживается до raw.flush вне gate; deferred-consumer/backpressure/cancel units. Все subordinate async errors (включая raw.flush/auth при destroy) после changed-host обнаружения не фиксируют terminal code до persistence/ended; outstanding ping ждёт этот общий итог и не маскирует HOST_KEY_CHANGED либо STORAGE_UNAVAILABLE. Добавить оба race units, mandatory checks и fresh clean review до T010 (FR307/314/317/318/319,T009/T010).


## Phase 21 — Obtain physical-close acknowledgment before interpreting it

- [X] T039 Исправить review_003_owned_dial_1: синхронное исключение getter done не является подтверждением cleanup. Получить Future до внутреннего catch его asynchronous error; throwing getter сохраняет точный task/socket для retry с CLEANUP_REQUIRED retryable. Применить к OwnedSshDial, NativeSshSocket fallback и аналогичной strict-adapter raw-close ветке. Units throwing getter→retry для всех трёх, errored полученный done Future остаётся acknowledgment; mandatory checks/fresh review (FR317/318/319,T009/T010).


## Phase 22 — Established-session terminal and canonical endpoint projection

- [X] T040 Исправить review_003_connection_owner_1: после потери установленного сеанса/disconnect-watchdog публиковать disconnected с причиной, pending auth failure остаётся failed, unconfirmed cleanup приоритетно failed/CLEANUP_REQUIRED. Quarantine projection и retained-ID cleanup должны использовать актуальную canonical endpoint/connection/credential binding после перемещения профиля A→B; старые session/attempt IDs не управляют другим endpoint. Units terminal/watchdog state, quarantineA/quarantineB после move, rename preserves session; mandatory checks/fresh clean review (FR315/316/318,T010).


Execution steering from user (2026-11-03): remaining functional implementation first,
then missing unit tests and all verification/review. No further incremental test
runs while implementing. Historical checked tasks remain history; new implementation
is unverified until the consolidated unit/static/review phase.


## Phase 23: Convergence

- [X] T041 Завершить grant-owned expiry lifecycle: независимо от наличия pipe отменять pending SSH клиента и закрывать его каналы через owned exact cleanup вне gate; established OwnerActor sessions сохранять. Fake-clock trust/passphrase/EOF/late-close units (FR325/331, data-model grant lifecycle, review_003_full_1 R1; partial).
- [X] T042 Выключать MCP best effort для всех клиентов и listener: начать все cleanup независимо от ошибки/5s deadline одного, собрать ошибки после необходимых действий, сохранить exact future/retry. Units двух клиентов с failed/held A и живым B (FR330/331, review_003_full_1 R2; partial).
- [X] T043 Добавить injectable native read/write/peer/metadata/DPAPI boundaries и isolated synthetic fixtures нового broker/stdio control flow: wrong PID/creation/user/logon/token inspection до grant read/unprotect, ACL/reparse, partial I/O, EOF/close/owned workers. Не запускать продукт/bridge subprocess/SSH/Isar/VM. Согласовать фактические native source paths в plan с T017 (plan Unit isolation boundaries, FR326/330/333, review_003_full_1 R3; partial).
- [X] T044 Подтверждать native physical close до удаления channel registry и mcpChannelClosed: concurrent accept reaping/explicit Close должны ждать тот же exact join; EOF/invalid frame не оставляет подключённый pipe handle, который Dart уже перестал учитывать. Synthetic native worker/handle acknowledgment units (FR330/331, operations exact cleanup; partial).
- [X] T045 CRITICAL оформить функциональную privacy-корректировку C03 secret copy/cut в scope001 с трассировкой FR305, без feature-screen design checks; сохранить обычный unit regression секретного поля (Constitution I, FR305/320; contradicts).
- [X] T046 Добавить безопасные понятные сообщения и допустимый следующий шаг по каждому OperationFailure в profile/form/connection/grant UI; не показывать только wire code/field, не включать secret values. Pure presentation/controller units (FR319, AC303/308; partial).

Convergence inventory:34FR,9SC,22AC,13architecture/testing ownership decisions,
5constitution principles. Findings:6partial/contradiction gaps listed above;
no unrequested product capability or missing product decision was introduced.
This append does not erase prior completed task history. Implement fixes, then run
all applicable mandatory checks and a fresh whole003 independent review.


T045 is the constitution-priority correction for this convergence batch. Native
T043/T044 also retain incoming frame reservations until internal Dart ack, covering
the engine-delivery backlog; synthetic boundary units live in ipc_boundary_test.cpp
alongside the codec-only ipc_auth_test.cpp. No product acceptance gate is added.


## Phase 24 — Native key import error categories

- [X] T047 Разделить native key picker open/GetFileSizeEx/ReadFile failures и empty/>1MiB validation; Dart mapping сохраняет фиксированные STORAGE_IO/INVALID_ARGUMENT без native text/credentials и даёт корректный следующий шаг. Pure native decision + fake picker widget units без реального диалога/файла пользователя; applicable checks и fresh independent review (FR319, AC303, review_003_full_2 R1).


## Phase 25: Convergence

- [X] T048 CRITICAL использовать готовый C07 DeckListItem для строки профиля вместо локальной композиции title/description в C09; передать selected/onTap и warning через штатные inputs. Functional unit проверяет данные строки, предупреждение, callback выбора и отсутствие auto-connect; без geometry/design acceptance. Mandatory Flutter/link/build checks и fresh independent review (Constitution I, FR320, T007/T014; contradicts).


## Phase 26: Convergence

- [X] T049 CRITICAL переиспользовать C18 DeckKeyValue(selectable) для public fingerprints/JSON metadata и DeckCopyButton для token-free MCP configuration вместо ручного Clipboard callback. Functional synthetic unit проверяет exact public JSON copy и безопасный feedback при clipboard failure, без owner graph/реального clipboard/design acceptance. Mandatory Flutter/link/build checks и fresh independent review (Constitution I, FR305/319/320/334, T014/T020; contradicts).

## Post-completion — Reported private-key save failure (2026-11-04)

- [X] T050 Add bounded local diagnostic evidence for profile/command failures in `lib/runtime/local_diagnostics.dart`, injected from the composition root. File: `<dataRoot>/operation-diagnostics.json`, latest 8 in-process failures, max 12 method frames per failure. Store only fixed stage, runtime type, public failure-code enum and method names; never exception messages, input/credential bytes, passphrases, hostnames, paths or full stack traces. Failure to write diagnostics must not affect operation results. Cover redaction, retention and sink failure with synthetic unit inputs; run required checks and independent review.
- [X] T051 Diagnose and correct the reported save failure using safe evidence; add isolated regression units for the confirmed cause. Preserve the user's existing database and credentials. No real-Isar/integration/VM tests. Do not declare the save defect resolved merely because the key parser accepts the converted key.


T051 confirmed cause: NativePlatform returned read-only codec-owned Uint8List views. CredentialPreparer's finally wiped secret.protect output and threw UnsupportedError, masking successful protection (and potentially prior parser errors) as storageUnavailable. Picker cleanup and unprotect consumers had the same ownership mismatch. Fix all three typed-data replies at NativePlatform with detached writable copies; null picker cancellation preserved. `native_binary_ownership_test.dart` injects read-only encoded ByteData, not merely an unmodifiable value re-encoded by a mutable mock envelope. `profile_form_save_test.dart` exercises actual form/controller/ProfileOwner/CredentialPreparer/codec with synthetic RSA/password and in-memory repository. Both form cases and all three binary ownership tests fail against HEAD's old NativePlatform and pass with the fix; cancellation remains passing. No native OS/real credentials/real Isar used by regression tests. T051 mandatory checks and independent reviews completed; see reviews/2026-11-04-save-buffer-fix.md.


## Уточнение профилей/ключей/модального потока — 2026-11-04

Обновляется существующий003, без отдельного нового пакета. Constitution1.4.0/VI запрещает compatibility aliases, old-schema adapters, migrations/backfill доapp1.0. История прежних задач сохраняется; текущие решения ниже её заменяют. Весь productcode до обновления tests.

- [X] T052 Уточнить существующие spec/plan/data-model/research/contracts/checklists003, связи001/002/004; выполнить clarify/checklist/analyze/linkcheck и independent package review до current-onlycleanup (FR-335–341).
- [X] T053 RSA PEM/OpenSSH inputs в lib/profiles/legacy_pem.dart,credential_parser.dart,key_envelope.dart: strict PEM/DER/RSAproof, AES128/192/256CBC/DES3, input1MiB/phrase65536bytes/4workers30s; единственный parsePrivateKey API безalias (FR-335/341,AC-323,SC-310).
- [X] T054 Mandatory canonical publicKeyBytes/type/bits дляprivateKey в lib/profiles/credential_input.dart,profile_owner.dart,lib/storage/records.dart/records.g.dart; null толькоpassword, nooldrecordfallback/backfill (FR-336/341,AC-324/330).
- [X] T055 Required explicit PublicKeyHint в PrivateKeyCredential/OwnedPrivateIdentity, mandatorymetadata snapshot и frozenexpectedpublicbytes в lib/connections/connection_owner.dart,ssh_transport.dart,private_signer.dart; mismatch до подписи, originalbytesDPAPI, currentlabels/errors (FR-335/336,AC-323/324,SC-310).
- [X] T056 Live C12 modal details/actions в lib/profiles/profile_view.dart вместо нижней панели, select/read безconnect; зависимости004/T026 и001/R014 (FR-337,AC-325).
- [X] T057 ProfileSaveOutcome иpostcommit manualverify в lib/profiles/profile_form.dart,profile_controller.dart,profile_view.dart; new/connectionaffecting only, serializedfirsttrust/phrase, noautoaccept/rollback/retry (FR-338/340,AC-326/327,SC-311).
- [X] T058 Changed-key/action badges иexplicittrustrecovery в lib/profiles/profile_view.dart; noordinary/backgroundmodal (FR-339,AC-328).
- [X] T059 Удалить parseralias/optionalidentityfallback в003 и migration/copyStore в002/T044, обновить callers напрямую; userdata не стирать/автоматическинепереносить (FR-341,AC-330,ConstitutionVI).
- [X] T060 После всегокода обновить currentAPIfixtures/deepcopies иsyntheticunits в test/profiles/,test/connections/,test/domain/: PEM/OpenSSH errors/DER/metadata/signature иmodal/save/actions; inputformats неoldapp-recordfallback (FR-335–341,SC-310–312).
- [X] T061 Route-owned phrasecontroller доunmount в lib/profiles/profile_view.dart; clearonsubmit/cancel/dispose, repeated/stalerouteguards иfunctionalregression (FR-340,AC-329).
- [X] T062 VerificationLease lateconnect/refresh, onStarted доrefresh иcancelOwnedAttempt безUIpendingsuppression в profile_view.dart/profile_controller.dart; canonicalexactattempt/nonsession/auth guards. Regressionlatepending/newattempt/establishedsession/refresh (FR-338/340,AC-327/329,SC-312).
- [X] T063 Controller/profile/navigationgeneration binding до/послеpostsave refresh в profile_view.dart; lateA не меняетB/неоткрываетзакрытыйflow; two-profile regression (FR-339/340,AC-328/329,SC-312).
- [X] T064 Mandatoryformat/analyze/fluttertest/boundary/schemaunits/nativeifchanged/sharedC21units иlychee; записатьфактическиеscope/results в reviews/profile-workflow.md (FR-335–341).
- [X] T065 Полноеindependentreview существующих001/002/003/004 изменений послеchecks; confirmedfixes новымиtasks, rerunchecks/freshreviewдоclean (всеFR/AC/SCуточнения).
- [X] T066 ФинальныеSpecKitanalyze/converge текущих003 и004; singleEXEbuild/staticaudit вместе004, безновогопакета/commit/pushбеззапроса (всеFR/AC/SC).

Dependencies: T052→T053–T059+001R014/002T044/004T026→T060–T063→T064→T065→T066. T061–063 сохраняютfunctional/reviewcorrectionhistory. PlanP35→T053;P36→T054;P37→T055/059;P38→T056/057/061;P39→T062/063;P40→002T044;P41→T060/064–066. FR335→T053/055/060;FR336→T054/055/060;FR337→T056/060;FR338→T057/062/060;FR339→T058/063/060;FR340→T057/061/062/063/060;FR341→T053/054/059/002T044.

## Исправления независимого ревью текущей реализации

- [X] T067 Обрабатывать актуальный trust challenge перед terminal-state завершением onboarding в profile_view.dart, включая уже connected ветку _verifySaved. Functional units failed+replace и connected+retain проверяют явное согласие, отсутствие дублирования и отсутствие фоновых prompts. Сохранить nonce/revision guards и established session (FR-338–340, AC-326–329, review_current_packages_implementation P2).
- [X] T068 Удалить CredentialCancelled/CredentialCancellation/ScheduleKeyDeadline aliases из key_parse_worker.dart; product/test callers и contracts/ssh.md используют WorkCancelled/WorkCancellation/ScheduleOwnedDeadline напрямую. После обоих fixes выполнить mandatory checks и свежее независимое ревью (FR-341, Constitution VI, review_current_packages_implementation P2).


## Server workspace — утверждённая навигация2026-11-04

- [X] T069 Обновить существующие001–004 spec/plan/model/research/contracts/checklists, выполнить clarify/analyze/lychee и independent package review; no newpackage (FR-342–347).
- [X] T070 Обновить общие C07/C10/C17/C21 и catalog в scope001/R015: lib/ui/deck_patterns.dart,lib/ui/deck_components.dart,lib/shell/foundation_shell.dart,tool/component_catalog/examples.dart; прямое удаление старых slots/FoundationSection, безcompat shims (FR-342/346).
- [X] T071 Реализовать selection/search/CRUD/sidebar и4server tabs/settings в lib/profiles/profile_view.dart,profile_controller.dart; immutable public connections map иunknown failures, no demo remote data (FR-342/343/345,AC-331/332/334).
- [X] T072 Runtime композиция C17 иобщие MCP settings route изsidebar в lib/runtime/runtime_view.dart; active во всех tabs, overlay pause/restore, readiness/tray recovery;002/T045 (FR-343/347,AC-332).
- [X] T073 Перенести onboarding ownership в workspace generation в lib/profiles/profile_view.dart: save exactid/filterclear, leave/deletion/controller/globalsettings/dispose retire prompts/lease, lateA/B иconnectedretain; сохранить routephrase controller/backend fences (FR-344,AC-333,SC-313).
- [X] T074 Подключить sidebar priority/errorlabels иcompact icon metrics/status/tooltips в lib/profiles/profile_view.dart,lib/monitoring/monitoring_view.dart;004/T029, no time/secret data (FR-345/346,AC-334/335).
- [X] T075 Только после всего product code обновить текущие callers/fakes/functional units в test/profiles/,test/monitoring/,test/runtime/ иshared synthetic tests test_design/components/; directcurrentAPI, no featurelayout/integration (все FR-342–347,SC-314).
- [X] T076 Выполнить tools/test-unit.ps1, shared components unit suite, lychee; fix checks иполный независимый review/fix loop существующих001–004, actualevidence в reviews/server-workspace.md (все FR/AC/SC).
- [X] T077 Финальные analyze/converge003/004, проверить001R015/002T045, собрать один EXE соstatic audit; без commit/push инового пакета (все FR/AC/SC).

Dependencies: T069→T070–074→T075→T076→T077. Product implementation sequential where files overlap; no implementation subagents required. Independent package/code reviews обязательны. User override: весь code до tests; history прежних задач сохранена. FR342→T070/071;FR343→T071/072;FR344→T073;FR345→T071/074;FR346→T070/074;FR347→T072/004T029. P42→T070;P43→T071;P44→T073;P45→T072;P46→T075–077.

## Workspace retirement review corrections

- [X] T078 Удалять принадлежащие workspace trust/phrase routes при controller rebind (включая тот же selected ID) и dispose в lib/profiles/profile_view.dart; безопасное route retirement после frame, exact lease/nonce guards сохраняются. Functional rebind/removed-subtree units без screen geometry (FR-344, AC-333, review_server_workspace_implementation_1 P2).
- [X] T079 Привязать общий MCP route и вложенные confirmation/input routes к конкретным runtime/features/settings owner; закрывать при release/admission loss/dispose, builder не читает mutable nullable controller. McpSettingsController не dispatch после dispose. Изолированные fake route/controller tests и mandatory checks/fresh review (FR-343/347,002FR-220, review_server_workspace_implementation_1 P2).

- [X] T080 Распространить owner-bound retirement на все C12 профиля (form/delete/trust/phrase) в lib/profiles/profile_view.dart; delete captures controller/generation/profile после await; обычный ProfileController._action отказывает после dispose, cancelOwnedAttempt cleanup остаётся разрешённым. Functional fake units filled form/delete same-ID rebind/removal без dispatch старому/новому владельцу; rerun checks/fresh review (FR-344,AC-333,SC-313,review_server_workspace_implementation_2 P2).

- [X] T081 Различать отсутствующее trust-наблюдение и известный unpinned endpoint в lib/profiles/profile_view.dart: canonical needTrust/needPassphrase/connected имеют свой смысл, cached unpinned badge только disconnected/cancelled. Fake failed-getTrust и stale-unpinned units, rerun mandatory checks/fresh review (FR-345,AC-334,review_server_workspace_implementation_3 P2).

- [X] T082 Передать иконки четырёх вкладок в C16, добавить иконку общих настроек
  в lib/profiles/profile_view.dart согласно contracts/server-workspace.md;
  001/R016 и002/T046 исправляют shared API и asset delivery. Реализация до тестов,
  mandatory checks/build/static audit, independent review; без новых разделов/данных.
