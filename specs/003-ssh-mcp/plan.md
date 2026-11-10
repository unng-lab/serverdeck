# Implementation Plan: 003 — SSH и локальный MCP


**Feature context**: `003-ssh-mcp` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

## Summary

На runtime002 добавляются domain owners профилей/SSH/доверия и MCP router.
Единственный WorkspaceStore переходит в logical format2. UI и MCP вызывают один
типизированный AppOperations; исключение — deleteProfile принимается только UI
через неподделываемый внутренний UiActor, отсутствует в wire schemas/router.
Стандартный stdio MCP идёт через transport-only ветку того же EXE к private Named Pipe.

## Technical Context

- **Language/Version**: Flutter3.47.7/Dart3.13.5; C++17 MSVCv143x64 из002.
- **Dependencies**: Isar trio3.4.1, build_runner2.16.2 (--force-jit), vendored dartssh2
  upstream4.1.0 с минимальным policy/host-key hook patch. JSON-RPC/MCP небольшой
  allowlist router на dart:convert, без внешнего MCP server package/runtime.
- **Storage**: полный format2 schema set, DPAPI blobs в Isar; credential export для
  моста — производный protected blob, не вторая база. [Data model](data-model.md).
- **Testing**: только unit dart/flutter_test с fake store/transport/clock и native
  CTest изолированных IPC adapters/codecs с synthetic identity hooks. SSH bytes
  подаются in-memory; реальные TCP/SSH/stdio processes/Isar/VM не используются.
  Нет feature screen design acceptance.
- **Target**: Windows10/11x64, один user/main owner, только тот же logon для MCP.
- **Performance**: network budget30s, prompt5min, half-open watchdog≤25s (внутри90s),
  auth handshake5s; 8 bridge channels total, no per-grant quota, frame≤2MiB, writer queue≤64.
- **Constraints**: no shell/exec/terminal, no HTTP listener, no remote pipe,
  no auth fallback, no secret read/copy, no host deletion through MCP.
- **Scope**: все34 FR003; зависит от полностью реализованной002. Визуальный контракт C01–C30 не меняется; функциональная privacy-поправка C03 оформлена в scope001/R013 (T045).

## Constitution Check

| Правило | Проектное решение |
| --- | --- |
| C01–C30 | C02/03/04/07/09/10/11/12/13/14/18 и BrandTheme используются напрямую |
| Без screen design тестов | text/data/actions/guards/native protocol/recovery, не layout |
| Только юнит-тесты | fake transports/store/clock/identity; доверие до auth, revoke/expiry/races/retries |
| Один EXE / Isar | основной owner002; bootstrap stdio bridge без Flutter/БД |
| Tray-only exit | MCP не получает exit/token-admin/delete; скрытие не меняет owners |

Проверка до и после design: исключений не требуется. Native bridge — разрешённый
конституцией режим того же EXE, не отдельный сервер продукта.

## Project Structure

### Documentation

[Research](research.md), [access model](mcp-access.md), [data-model](data-model.md),
[operations](contracts/operations.md), [SSH](contracts/ssh.md),
[IPC](contracts/ipc.md), [MCP](contracts/mcp.md), [JSON schemas](contracts/mcp-tools.json),
[quickstart](quickstart.md), [tasks](tasks.md).

### Source Code (repository root)

| Планируемое место | Ответственность |
| --- | --- |
| `lib/domain/app_operations.dart`, `actor.dart`, `models.dart` | единственные typed операции/DTOs/authority |
| `lib/profiles/profile_controller.dart`, `profile_view.dart`, `profile_form.dart` | UI owner/controllers, C IDs без I/O в widgets |
| `lib/connections/connection_owner.dart`, `ssh_transport.dart`, `network_budget.dart` | attempt/session/generation, host verify, timers |
| `lib/trust/trust_owner.dart` | endpoint trust/challenges/warning persistence/epoch |
| `lib/mcp/router.dart`, `grant_owner.dart`, `pipe_adapter.dart`, `tool_schemas.dart` | allowlist+authorization+projection, no raw Isar |
| `lib/storage/records.dart`, `store_manifest.dart`, `workspace_store.dart` | полный schema2 и atomic domain txn |
| `native/bootstrap/mcp_pipe.cpp`, `native/include/mcp_boundary.h`, `mcp_pipe.h`, `mcp_json.h` | stdio/pipe/Windows identities/DPAPI/export |
| `third_party/dartssh2/`, `patches/dartssh2-4.1.0-policy.patch` | pinned upstream+small explicit patch, preserved license |
| `test/domain/`, `test/mcp/`, `test/connections/`, `native/tests/` | functional/protocol/ACL/recovery |
| `tools/test-unit.ps1`, `tools/test-release.ps1` | только unit gates; сборка/static audit отдельно |

## Architecture and ownership

AppOperations обрабатывает commands через один FIFO command gate. Внутри:
валидация actor/grant/current versions → store transaction → domain linearization.
Network/DPAPI/file IO вынесены из writeTxn; перед irreversible action повторяется
fence check в gate. Нет длительных locks пока пользователь рассматривает fingerprint.
UI controllers получают immutable DTOs; MCP router использует те же DTOs и не
умеет вызывать deleteProfile/начинать произвольный generic command.

attemptId UUID + monotonically increasing attemptGeneration; profile.connectionRevision,
endpoint.trustRevision, endpoint.observationRevision и actor.grantVersion захватываются
каждой попыткой/согласованием. На mismatch socket закрывается, поздний результат игнорируется.
Profile rename меняет profileRevision, но не connectionRevision; уже захваченное
подтверждение профиля при rename считается устаревшим, сам SSH-сеанс не рвётся.

Native broker dispatch не запускает Dart code в stdio helper. Main native pipe server
передаёт проверенные frames основному Dart owner по typed platform extension;
все authorization/commit decisions остаются у владельца. В native есть только
bounded channel state, проверки Windows peer и производные encrypted credential blobs.

## Phases / Complexity

Сначала store2/domain/UI profile CRUD, затем SSH+first trust, затем trust-change
и concurrency, затем grants/IPC/MCP parity. Tasks содержат runnable increments и
traceability всех FR. Vendored SSH patch нужен для буквального chosen-method-only
и получения полного host public key; upstream default не объявляется соответствующим.


## Unit isolation boundaries

Использовать StoreBackend seam002 для storage и fake canonical snapshot для domain
unit tests. SSH transport зависит от injectable socket byte stream, monotonic
clock/timer и key parser worker boundary. Отдельные tests pure-Dart cryptographic
парсера используют synthetic vectors; network endpoints не открываются.
Pipe/stdio adapters получают injectable read/write/identity/DPAPI operations:
фреймы, EOF, partial writes, spoofed peer, wrong logon, ACL failure и export retry
проверяются на synthetic inputs, без запуска процесса. Продуктовые native adapters
вызывают Win32 API; tests отдельных функций могут использовать свои временные
файлы/handles, но не связку Flutter/Isar/SSH/bridge. fake behavior не объявляется
доказательством фактической интеграции или engine durability. Remote CI run не
требуется выдавать за проведённый локальными unit checks.


**T003 implementation mapping:** typed AppOperations interface и concrete
DomainCommandGate/CommandContext в app_operations.dart; ActorAuthority/UiActor/
McpActor и отдельный internal OwnerActor в actor.dart; sealed public DTOs, typed
errors и ephemeral inputs в models.dart. Concrete business owners и canonical
OperationState binding подключаются последующими T006/T010/T013/T016/T025;
наличие kernel не означает готовые profile/SSH/MCP operations.


**T005 implementation mapping:** credential_input.dart validates profile fields and
prepares original credential bytes through SecretProtector; credential_parser.dart
is the pure bounded OpenSSH parser; key_parse_worker.dart owns cancellable Dart
isolates (4 slots/30s/confirmed exit), registered as a runtime capability by the
composition root in subsequent wiring. Import preparation returns protected bytes
and public key metadata only, never serialized signing material or passphrase.
PointyCastle4.0.0 is a direct pinned dependency for endpoint SHA256 (already used by
dartssh2). Embedded Blowfish/bcrypt notices accompany the MIT vendor license in
release licenses/dartssh2-notices.txt. Atomic profile persistence is still T006.


**T006 foundation mapping (not completed CRUD):** DomainRepository in
lib/storage/domain_repository.dart adapts the same WorkspaceStore to owner-only
record reads/transactions; no DB/cache in widgets/router. WorkspaceStore.readSync
opens a consistent read transaction outside writes and reuses its current sync
read/write transaction for canonical checks at linearization (no nested Isar txn).
DomainCommandGate.prepare is a private split-phase result with admission/response
checks and the same FIFO limit; it cannot return a live CommandContext. After any
outside-gate parse/protect/close wait the final command reacquires gate and checks
current auth/fence inside the actual write. Public submit still requires PublicValue.
ReceiptSigner in lib/domain/mutation_receipts.dart holds an owned32byte store key,
HMAC-SHA256 over canonical {method,payload}; JSON object keys ordinal sorted,
arrays/exact strings preserved, floats/non-JSON/malformed Unicode rejected. Owned
encoded bytes and key clear on disposal; library internal copies/immutable strings
have no global wipe promise. No secrets or canonical plaintext payload persisted.
These are foundations; actual profile CRUD/refcount/receipt bindings, receipt-key
unprotect/root lifecycle, canonical grant/state ports and UI remain open tasks.


**T006 owner mapping:** lib/profiles/profile_owner.dart implements typed
ProfileOperations subset, uses ReceiptBook and CredentialPreparer outside gate,
actual DomainRepository.write + CommandContext.linearize for atomic commit. Required
ProfileConnectionPort/ConnectionVersionState belongs to real ConnectionOwnerT010;
UI production wiring therefore follows that owner, with no fake production transport.
lib/domain/canonical_state.dart composes current DB/runtime/required grant+connection
ports; grant authority remains canonical GrantOwnerT016/T025. receipt_key.dart loads
existing store HMAC32, receipt_book.dart supplies namespace/expiry/replay/indexed
retention. Controller/form units can proceed independently; T007/T011/T014 root wiring
after owner seams, complete grant/native capabilities atT020. Data/operations contract
contains exact payload and revision decisions. This does not change task completion
or assert GUI/SSH/MCP integration; only isolated owner behavior is tested here.


Root lifecycle binding forT007/T020: register one composite domain capability before
RuntimeCoordinator.start, then use an application RuntimeStore wrapper whose open
awaits WorkspaceStore.open and complete domain graph initialization (including
loadReceiptSigner) before returning. Coordinator only then publishes running. The
composite is created before registration and retains partial initialization/owned
handles for cancel/drain/dispose retry; no late registration, dummy signer or fake
connection/grant owner. Its phases forward to initialized/initializing owners, and
store close occurs after accepted work drains. Explicit retry of initialization may
reload the same canonical HMAC key, never regenerate it. Shutdown prevents a late
initializer from reopening admission. Functional fake-root tests inT007/T020 verify
these orders; no product/Isar integration test is needed or permitted.


**T028/T034 mapping:** exact RSA signature.type vs negotiated algorithm in vendor
ssh_transport.dart before host callback; same3policyfiles, reproducibleLFpatch.
Separate mandatoryT034 bounded signature pool/hook in lib/connections/host_signature.dart
and vendor client/transport beforeT009, follows4slots/remainingbudget/confirmedexit
contract. This keeps expensive untrusted RSA math off main owner while preserving
supported algorithms; private-key parser remains its own4slot owner. Low-level
memory pre-NEWKEYS fixtures directly test cryptographic wire policy without TCP.


**T034/T035 implementation mapping:** runtime/owned_work.dart is domain-independent
resource ownership; profiles/key_parse_worker.dart reuses it without changing parser
validation/private-isolate API. connections/host_signature.dart owns public-signature
requests/typed async failures and in-process verifier workers. Vendor3source patch
adds onVerifyHostSignature + shared pure/canonical verifier and late-close guards;
receive backlog cap1MiB/fixed error bounds incoming data while async work waits.
Strict adapter/root installation and domain error mapping still required byT009,
owner remainingbudget/cancel bindingT010. Components are not complete SSH wiring.


**T036 next-step decision:** pinned SSHIdentity supports FutureOr signature; use
an owned async identity instead of passing ParsedPrivateKey.key into client. Add
public-only key hint and lib/connections/private_signer.dart, separate4slot pool on
owned_work; static scheme selection/cancellation/budget/error behavior fixed in SSH
contract. Source verified SSHClient awaits identity.sign while OpenSSHRsaKeyPair.sign
is synchronous. Implement this before strict adapterT009, not as a future layout or
integration gate. No additional package or product key-size floor is required.


**T036 component implementation:** profiles/key_envelope.dart now owns shared
single-key OpenSSH framing/cipher/KDF checks and canonical public hints; parser
and parser worker reuse its byte-bound validation. connections/private_signer.dart
implements signature-only isolate messages, async single-use SSHIdentity and fixed
scheme selection. Root admission/prompt/budget callbacks are mandatory constructor
inputs, no production defaults. Root pool registration and strict-adapter bindings
remain T009/T010/T036; no application-runtime connection graph is claimed here.


**T008/T010 timer component mapping:** connections/network_budget.dart owns the
30s active/5min explicit-prompt deadline and separate15s/10s liveness timers;
network_budget_test.dart injects monotonic time/timers/ping promises. The connection
owner must create/finish the budget with each attempt, bind prompt leases to current
fences, start/stop watchdog at session ownership changes and close exact resources
on callbacks. T008/T010 stay open until those owner/adapter scenarios are built.


**T037 review fix:** final guarded connected publication must first succeed at
NetworkBudget.tryComplete; elapsed monotonic time is checked even if the timer
callback is queued. Active prompts/previously ended attempts cannot complete.
finish remains cancellation/error cleanup only. OwnerT010 must use this distinction.


**T008/T022 encrypted-memory fixture increment:** test/fixtures/ssh_auth_peer.dart
is a narrow synthetic byte peer for pinned SSHClient packet writes: X25519,
Ed/RSA256 host proofs, AES128-CTR and HMAC-SHA256. It verifies real encrypted MACs
and userauth challenge signatures, serves only service/auth/ping/rekey messages,
and has no socket/listener/channel/command implementation. Unit harness installs
real owned host/private signing pools and an explicit fake admission callback.
ssh_auth_policy_test.dart covers fragmented incoming bytes, exact password,
Ed/RSA userauth, server-sig-algs selection, rejection/partial MFA without fallback,
late trust/passphrase cancellation, same/changed host rekey and pending ping close.
This is low-level policy evidence; real strict adapter authority/error/resource
bindings, owner persistence and overall T008/T009/T010/T022 remain open.


**T009 strict adapter component:** connections/ssh_transport.dart is the only
application SSH client construction site: explicit algorithms, mandatory shared
signature/signer owners and host callbacks, bounded FIFO actual-write admission,
fixed errors, auth prerequisites, public-only observations and physical close retry.
RootT010 supplies gate-backed write admission/current auth checks/budget/prompt/
trust callbacks and owns dial reservations, final tryComplete publication and
session watchdog. Switchover to OwnerActor at connected is mandatory for writes and
rekey, preserving sessions after initiating grant revocation. No root defaults or
local allow-all production binding is supplied. T009/T034/T035/T036 remain open
until this component passes independent review and root bindings are implemented;
all previous completion history is retained. Unit ssh_policy_test.dart uses the
memory encrypted peer and explicit fake authority/admission callbacks only.


**T010 dial resource component:** connections/owned_dial.dart retains pending native
factory/task/late socket until acknowledged closure or explicit single transfer.
NativeSshSocket forwards Dart Socket without protocol defaults; owner constructs
OwnedSshDial inside guarded slot admission, uses its budget/cleanup deadline, records
takeSocket in the entry and closes known raw handle even on SSH constructor failure.
This is the dial seam for ConnectionOwner, not a replacement owner or root wiring.


**T010 ConnectionOwner implementation increment:** connections/connection_owner.dart
now implements ConnectionOperations and the real ProfileConnectionPort over the
shared canonical gate/state/repository. ConnectionOperations is extracted without
changing AppOperations signatures. SshConnection is the narrow transport seam;
StrictSshTransport implements it, and the owner default factory constructs the
strict adapter with shared required crypto pools and real gate-backed write callback.
Injected transport/task/repository/policy/clock implementations exist only in units.
Owner owns64-slot registry (including pending prep/dial/uncertain close), perprofile
attempt/session IDs/generations,30s budget/5min input leases,15+10 watchdog,5s cleanup,
endpoint quarantine and RuntimeCapability. Complete root composition and real
ConnectionTrustPolicy implementation remain T013/T007/T011/T014/T020. No permissive
policy or production graph is introduced just to make interim UI work.

TrustOwner will use opaque ConnectionProof (attempt identity/current generation,
base connection/credential/endpoint fence, current actor) and the guarded controls
proofFor/checkProof, beginTrustWait and allowAuthentication. TrustInputWait carries
the Future OUT of the prepare phase to avoid awaiting a prompt under the gate.
allowAuthentication independently checks canonical accepted bytes/type/fingerprint,
updates trust/observation fences and resumes the same initial trust wait only after
policy's durable commit. invalidateEndpoint returns an exact cleanup batch to await
outside gate; fresh replacement challenge can bind a new terminal proof after that
invalidation. Real nonce/observation/receipt persistence and challenge expiry are T013.


**User execution-order override (2026-11-03):** implement ALL remaining functional
003 tasks first. Add/update and execute the remaining unit suites, mandatory static/
link/build checks and independent review in one following verification phase. Do
not run per-component unit/review cycles during this implementation batch. Existing
405-unit/clean component evidence remains historical and does not prove new code.
Test/acceptance tasks stay open until that final phase; product scope is unchanged.


## Convergence correction bindings T041–T046

GrantOwner owns the earliest canonical grant-expiry timer independently of channel
lifetime. Expiry queues version-fenced private cancellation/cleanup outside the gate,
including after stdio EOF. Disable starts all client cleanup and transport removal
before aggregating errors; pending physical-disable work is retained for retry.

The shared native boundaries in `native/include/mcp_boundary.h` are the actual
production code used by broker/stdio: BridgePorts/AuthenticateBridge preserves owner
metadata→actual peer→grant read→DPAPI→auth order; ClientPeerPorts always reverts after
impersonated token inspection; FrameReader/WriteFrame and stdio pumps own bounded
partial I/O behavior; OwnedIoWorkers joins exact workers before releasing handles.
Synthetic units exercise these boundaries, without launching ServerDeck or a pipe
peer. Win32 bindings remain in mcp_pipe.cpp, not another owner or executable.

Native frame reservations survive platform-message delivery until Dart sends its
internal mcp.ackFrame. This bounds both native queued frames and frames delivered
into the engine but not yet processed. Channel stop disconnects the peer; registry
retirement/closed notification follow the exact join and handle release, including
concurrent explicit close and accept-side retirement. No detached cleanup thread.

Fixed OperationPresentation text supplies FR319 next steps without input/native
error interpolation. Existing C10 notices render those instructions. C03 copy/cut
privacy is registered in001/R013; its functional synthetic test and shared component
unit checks remain separate from feature-screen design (which is not tested).
Python jsonschema4.26.0 is an offline test-tool dependency only, listed in
`tools/unit-requirements.txt`; no Python/runtime is shipped or required by the app.


## Текущий план уточнения профилей — 2026-11-04

Пакет003 расширяется непосредственно, по constitution1.4.0/VI. [key-input](contracts/key-input.md), [profile-workflow](contracts/profile-workflow.md) — текущие контракты.
P35: strict legacy_pem.dart + parsePrivateKey единственный parser API; Crypto внутри имеющихся4slot/30s workers, вход1MiB/phrase65536UTF8bytes, AES128/192/256CBC/DES3 и строгие DER/RSA proof. Vendor/runtime tools не добавлять.
P36: KeyInspection→CredentialPreparer→ProfileOwner→Credential.publicKeyBytes: обязательная canonical public metadata дляprivateKey, null толькоpassword. Regenerate records.g.dart; snapshot/copier обязаны копировать bytes. Нет old-record fallback или backfill.
P37: ConnectionOwner→PrivateKeyCredential→OwnedPrivateIdentity требуют явный PublicKeyHint; PrivateSignRequest получает frozenexpectedbytes, сравнение до подписи. Удалить старые aliases/optional compatibility arguments, обновить все callers/tests напрямую.
P38: profile_form/controller возвращают ProfileSaveOutcome; profile_view C12 modal. Manualconnect после успешного commit, coalescing/promotion004; oneprompt ledger64tokens; секрет phrase принадлежит routeState до unmount.
P39: VerificationLease удерживает controller/profile/exactattempt до позднего admission, cancelOwnedAttempt обходит толькоUIpending; backendauth/exactattempt/non-session guards остаются. Capture navigationgeneration/controller/profile до формы и повторно до/послеrefresh; позднийA не меняетB.
P40: StoreBackend/migrations формат1 удаляются в scope002, оставшийся manifest/publication модуль store_manifest.dart принимаеттолькоformat2. Несовместимое отвергается до открытияDB, безreset.
P41: После всего code — synthetic PEM/parser/signing/metadata/form/controller/modal tests, затем mandatoryformat/analyze/fluttertest/boundary/schemaunits/native(ifchanged)/lychee; C21sharedunits scope001. Fresh independentreview loop, analyze/converge текущего003; сборка одногоEXE с004.


## План рабочей области сервера — 2026-11-04

P42: Обновить C17 FoundationShell напрямую до sidebar/child/state/status/recovery
слотов; старые FoundationSection и feature-specific slots удалить. C07 compact/error,
C10 iconOnly/icon и C21 compact/icon оформить в001/R015, C13 reuse для вкладок.
P43: ProfileViewPanel владеет выбранным server workspace и четырьмя вкладками.
ProfileController добавляет public connections projection через getConnection;
неуспех чтения не оставляет успешный статус. Поиск/CRUD слева; настройки профиля
справа, C12 только формы/consent/phrase. Нет новых runtime dependencies/schema.
P44: Сохранить verification lease и nonce ledger, заменить modal ownership на
workspace navigation generation. Selection/deletion/global settings/controller/
dispose инвалидируют continuations и закрывают собственный prompt. Late admission
отменяется exact-attempt через canonical backend, established/new session сохраняется.
P45: RuntimeView открывает общий MCP C12 из sidebar; active во всех server tabs,
paused во время общей settings route, восстановление прежнего выбора при закрытии.
Readiness/tray recovery и общий owner graph002 остаются. Текущий source of intent:
[server workspace](contracts/server-workspace.md), заменяющий parts profile-workflow.
P46: Сначала весь product code, затем обновление текущих functional tests/fakes и
shared synthetic component tests, mandatory checks/links, fresh independent review,
analyze/converge и один EXE. Никаких BC APIs, screen layout/VM/integration gates.


## P47 — mandatory retirement corrections from implementation review
T078 сохраняет prompt Route/NavigatorState до retirement и удаляет route after frame
при controller rebind/dispose; никаких ancestor lookup из disposing contexts.
T079: lib/runtime/owned_settings_route.dart owns global dialog/nested Navigator;
RuntimeView binds it to exact runtime/features/settings session and retires before
release. lib/mcp/settings_view.dart child dialogs use nearest Navigator and own
name controller to actual unmount; settings_controller.dart blocks effects after
dispose. New fake route/controller tests in test/runtime/owned_settings_route_test.dart,
test/profiles/server_workflow_test.dart,test/mcp/settings_actions_test.dart.


P48/T080: заменить special-prompt bookkeeping единым registry owned DialogRoute →
NavigatorState для всех profile C12 в profile_view.dart, capture deletion controller/
generation/selected identity до/после await. ProfileController._action disposed guard
не касается cancelOwnedAttempt. Synthetic tests заполненных forms/deletion иsame-id
replacement/subtree removal; обычный disposed dispatch denied, cleanup still allowed.


P49/T081: _rowStatus различает null observation иknown unpinned. Нельзя заменять
canonical connected/needPassphrase на inferred needTrust из отсутствующего/cached
TrustView. Explicit needTrust и known disconnected unpinned сохраняют badge;
failed getTrust иstale cached unpinned покрываются isolated fake widgets.


P50/T086–T088: jittered reconnect with capped backoff in ConnectionOwner; volatile intent
with generation/revision/authority fences, cleanup before scheduling, unlimited retries,
one-minute stability reset. ConnectionView optional reconnectAttempt feeds existing
C-status/notice/actions in profile_view.dart; monitoring text reflects shared recovery.
Requirements FR-348–351 and contracts/ssh.md define policy and compatibility.
Fake monotonic clock/transport units cover normal recovery and cancellation/failure
boundaries. No schema migration, new dependency or automatic console/input replay.

P51/T090: после восьмой попытки продолжать повторы без предела количества,
с cap=30s и прежним jitter; ограничить exponent до shift, счётчик насыщать
на максимальном safe JSON integer. UI не показывает общий лимит; MCP schemas
расширяют диапазон reconnectAttempt, без новых storage/runtime dependencies.
