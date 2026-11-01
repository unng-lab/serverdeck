# MCP в работающем приложении и lifecycle jobs

**Direct SSH amendment 2026-11-01**: [действующий контракт](../../001-service-foundation/contracts/direct-ssh.md). Новое выполнение использует прямой SSH без устанавливаемого executor/Ansible/enrollment. Прежние описания этих компонентов ниже относятся только к historical format1; они не разрешают его исполнение или fallback. Остальные правила данных, прав и лимитов сохраняются. При конфликте в исполнительной архитектуре действует поправка.

Действующая поправка021 от2026-10-30 вместе с [основой](../../001-service-foundation/contracts/embedded-engine.md).
Меняет host/transport boundary на месте, новый feature не создаётся.

## MCP endpoint and authority

Сохраняются stdio entry point packages/serverdeck_mcp, MCP protocol negotiation,
tools/input/output schemas/resources/ошибки021. Процесс MCP — необязательный
adapter ИИ-клиента, без БД, engine, SSH, sampler и собственных permissions.
Отдельный mcp.exe не поставляется: stdio — режим того же serverdeck.exe,
с теми же Dart MCP libraries. Native/runtime библиотеки app остаются частью поставки.

Новый bridge подключается только к работающему app (включая tray), не запускает
app/locald и не владеет app lifetime. Закрытое app → SERVICE_UNAVAILABLE максимум
за5s, безопасная инструкция открыть ServerDeck. После grant proof/effect submission
нет reconnect/retry. Внешний MCP wire прежний; локальный discovery — отдельный
namespace embedded-v1 и descriptor новой версии с hostKind=application.
Legacy descriptor/major/bundle несовместимы → INCOMPATIBLE. Внутренний format3
handshake сохраняет apiMajor1/apiMinor1 и exact compatible build identity,
добавлять hostKind в прежний closed-field wire нельзя.

Windows сохраняет named pipes/ACL/retained PID/SID/image/challenge/nonce/grant proof.
App image в новом verified bundle заменяет locald.exe; удалять process checks
нельзя. Owner IPC наружу не публикуется, channel bridge имеет только MCP role.
Существующие grants/credential files/custody/expiry/revoke сохраняются; новый мост
открывает их после app readiness по прежнему binding, без экспорта секретов.
Revoke закрывает admission до публикации pending результатов/следующих эффектов.
Host-created owner capability невозможно получить из caller DTO/role flag.
Все owner confirmation/delegation checks и publication fencing остаются.

Parity: существующие server.dart/router catalog и положительные/отказные tests021,
без переименования tools. Mobile external stdio не поддерживается; удалённый
постоянный endpoint требует будущего необязательного узла, вне текущей задачи.

## Remote work versus local observation

Сохраняются jobId/attemptId/controllerId/workspaceId/expectedHostId/planDigest/
profileRevision/sequence, протокол executor и immutable inputs021. Новые receipts/
hash pipelines не вводятся. Локальный intent/attempt сохраняется до submit.
После отправки любых submit bytes без валидного correlated ACK — unknown.
Accepted ACK означает приём, не completion. Сбой до отправки не доказывает
remote success; повтор имеющейся неопределённой attempt не разрешён.

Наблюдение attached/detached/stale — отдельный runtime overlay над persistent job,
не новый remote status и не schema4. После restart nonterminal отправленная
attempt unknown до query/reconcile того же attempt на проверенном enrolled host.
Недоступный executor, missing attempt и изменённая identity не доказывают отсутствие
эффекта: occupancy сохраняется, пользователь восстанавливает доступ/доверие.
Нет локального reset/«повторить apply» для unknown.

Query/reconcile только действующему owner/допустимому grant через прежние
SSH trust/access/enrollment. Expired grant получает FORBIDDEN, owner продолжает
recovery. Используется существующий executor reconciliation, без восстановления
прежнего одноразового разрешения. Cancel — отдельный явный запрос, detach/exit
его не отправляет. Terminal требует подтверждённого remote status/postcheck021;
монотонная sequence и fence исключают rollback/duplicate terminal/late result.

## Evidence and limits

remote/ssh_executor.dart явно закрывает channel без гарантии отменить committed
effect. executor/serverdeck_executor/jobs.py хранит admission/launch commitment,
recover_generation переводит committed работу в unknown; runner.py использует
systemd-run, journal.py — постоянное состояние. Это основание консервативного
контракта, не доказательство реальной crash/reboot/network устойчивости.
Supervisor/wire не расширяются этой поправкой; runtime native проверки запрещены.

AC-SVC-EMB-07/08/09: fake transport/executor, lost ACK, exit после submit,
stale generation/trust/grant, missing attempt, duplicate terminal и revoke перед
effect. Не запускать SSH/systemd/Ansible ради проверки.


## Точная Windows bundle/discovery совместимость

Новый EmbeddedBuildManifest в protocol/build_manifest.dart имеет те же closed fields,
что TrustedBuildManifest format3, с format=4, apiMajor=1/apiMinor=1/workspaceSchema=3.
sha256 содержит serverdeck.exe, libisar.dll и только если существующая
format3 поставка включает executor-release.json — тот же executor-release.json.
locald.exe и mcp.exe исключены. Значения, bounds16KiB, buildId grammar, testOnly/root binding,
hash verification и immutable copies остаются format3; неизвестные поля/файлы
отвергаются. Verified app получает server role только внутри нового embedded
runtime; внешний peer имеет только проверенную application image identity. MCP session
role получается через MCP-only endpoint и grant proof, а не из имени файла/argv. Enum server host proof не равен owner UI capability.
Оба verifier взаимно отклоняют manifest3/4; нет fallback. Bundle format4 — версия
поставки, не storage schema4. Windows x64/VC++/pinned Isar dependencies сохраняются.

Descriptor format=2 имеет ровно прежние DiscoveryDescriptor поля из protocol/discovery.dart
плюс hostKind="application"; apiMajor=1/apiMinor=1, workspaceId UUID после Ready,
остальные типы/nonce32bytes/PID32bit/buildId/8slots/bounds8192 прежние. Legacy descriptor
format1 отклоняется. Имя DPAPI-защищённого файла: runtime/embedded-v1.discovery,
его entropy: UTF8 `ServerDeckNext\nv1\ndefault\n{ownerSid}\nembedded-v1`.
Pipe names используют `ServerDeckNext.embedded-v1.{ownerHash}.{slot}` с прежним
ownerHash=SHA256(UTF8(ownerSid+"default")) и slots0–7. Mutex остаётся прежним
`Global\ServerDeckNext.v1.{ownerHash}` для совместного exclusion с legacy locald.
Descriptor publish/remove atomic под lease, stale discovery не удаляет чужой lease
или данные. Startup failure виден локальному UI; MCP discovery публикуется лишь
после Ready, так что workspaceId не null. Изменённые namespace/format/host identity
не меняют прежний HMAC transcript format3 handshake, привязанный к build/generation.

## Единственный executable и выбор режима — уточнение 2026-10-30

Нормальный запуск `serverdeck.exe` создаёт UI/tray и EngineHost. Команда MCP:
`serverdeck.exe --mcp-stdio --grant-id <UUIDv4>`. Без grant-id разрешён только
unconfigured stdio с прежним пустым tool list; неверные/повторные/лишние arguments
отклоняются до app/DB/UI startup. App root выводится из проверенного executable,
не из внешнего --app-root. Режим stdio не создаёт окно/tray/engine/store, не берёт
writer mutex и не запускает app. Работает только при уже работающем основном app.
Это второй краткоживущий процесс того же файла для stdin/stdout ИИ-клиента,
а не второй daemon/вторая поставка. Его exit/EOF не завершает основной app.

lib/main.dart принимает args и выбирает app либо MCP до runApp. Windows runner
выбирает headless Flutter engine в stdio mode, сохраняет унаследованные stdin/
stdout/stderr pipe handles и не вызывает AttachConsole/AllocConsole/ShowWindow
в этом режиме. Только MCP protocol bytes идут в stdout, безопасные bounded
diagnostics — в stderr; Flutter startup/plugin diagnostics не пишутся в stdout.
Нет нового console executable или скрытого locald. Сроки/EOF/backpressure/error
поведение прежнего serveMcpStdio сохраняются. Нативная работоспособность headless
runner в текущем scope не проверяется и не объявляется установленной.

Оба процесса имеют одно и то же проверенное app image/hash. В новом verifier
role из filename больше не различает owner и MCP. На опубликованном IPC разрешён
только MCP handshake/clientRole=mcp + grant proof; clientRole=owner отвергается
независимо от image и argv. Owner capability создаётся только внутри основного
EngineHost/UI binding. Server endpoint дополнительно связан с retained app self
proof, writer lease, защищённым discovery token и native publication fencing.
Режим запуска не является доказательством прав и не ослабляет checks021.

Unit acceptance: mode dispatch не создаёт app/DB/tray для stdio, не auto-launch;
одна и та же verified image не позволяет owner IPC; grant/revoke проверки прежние;
выход bridge не закрывает основной host. Packaging/static acceptance: manifest4
не содержит mcp.exe/locald.exe; MCP client example указывает только serverdeck.exe.


## Target discovery implementation and custody ownership

The sole protocol DiscoveryDescriptor now encodes/decodes only format2,
apiMajor1/apiMinor1 and hostKind=application. Creation requires the recovered
workspace UUID and the existing EngineHost generation UUID; it cannot create a
pre-ready/null-workspace descriptor or a separate discovery generation.
withWorkspace and the former format1 parser are removed. Descriptor data never
issues an owner capability or proves application readiness by itself; the Host
publisher must still enforce Ready, retained runtime/lease binding and atomic
publication/removal.

DiscoveryNamespace preserves the existing SID+default SHA256 mutex namespace,
changes exactly8ordered pipe slots to embedded-v1, and defines the sole filename
embedded-v1.discovery. Owner identity is bounded4096characters as in HostAuthority;
Windows obtains it from actual current SID, not a client payload. Decode rejects
legacy/future versions and foreign hostKind/build with INCOMPATIBLE before
closed-field validation. Malformed fields/tokens/slots return STORAGE_BLOCKED.
8192byte descriptor and16384byte wrapped limits, canonical32byte bootstrap token,
immutable pipe names and caller-owned token copies remain enforced. Closing a
descriptor wipes its private token and prohibits further encoding/export.

DiscoveryCustody moves directly from Windows into engine/credentials, using the
same UserProtection port with the embedded-v1 purpose specified above. There is
no Windows forwarding file or old-entropy fallback. All transient cleartext is
wiped after protect/unprotect success or error, including late close during
protect; input ciphertext is captured before awaited provider work. Client reads
check the expected verified build. inspectForOwner can inspect a different build
as data for the lease-owning publisher's stale-file handling; it grants no write,
store, session or cleanup authority. Existing Windows discovery read sites use
only the new filename and this sole custody implementation. Former descriptor
files are not read, migrated, deleted or overwritten by this change.

This prerequisite alone does not compose the new publisher or make the remaining
old client bootstrap/pipe/image-role paths usable with bundle4. Their removal and
Windows VerifiedRuntime/MCP-only channel/connection-only bridge/root integration
remain mandatory T256/T265/T266/T274/T276. No legacy/new transport adapter is
introduced. Actual DPAPI/ACL/named-pipe behavior is not qualified by RAM units.


Publication synchronization now has one WindowsPublicationGate implementation,
independent of old pipe-worker/image-role types. The new WindowsVerifiedRuntime
binds only actual bundle4 app identity and a genuine held writer lease; its gate
factory does not accept a wire role or issue an owner credential. The internal
kernel primitive accepts a trusted root verification policy, keeps native SID/PID/
ACL checks and revalidates the retained current process around it. The existing
publication mutex/event SHA256 identity,16actual-work/5s limits, poison and physical
reuse barriers remain. This is separate from descriptor format2 and unchanged
format3 HMAC wire. Old peer policies are still isolated in the old IPC source and
must disappear in T265/T266/T276; no new compatibility runtime or public type alias
replaces them. The actual new MCP-only endpoint/client and publication root remain
mandatory before the app's MCP path is usable.


## Уточнение зависимости от работающего ServerDeck — 2026-10-30

MCP не является автономным сервисом: основной ServerDeck должен быть уже запущен,
в том числе в трее. «Без окна/трея/store/доменного worker» относится только к
stdio-подключению ИИ-клиента тем же executable, чтобы оно не открывало второе окно.
Отсутствие живого основного app означает SERVICE_UNAVAILABLE≤5s, без запуска
ServerDeck/locald/фонового Host. Это правило действует и без grant-id: unconfigured
пустой tool list допускается лишь при сохранённом проверенном подключении к
работающему app; после его потери bridge прекращает обслуживание. Ни проверка
argv, ни unconfigured режим не являются обходом проверки app liveness. Выход
bridge/EOF закрывает только его подключение. Уже принятые удалённые задания
подчиняются executor и не объявляются отменёнными при выходе основного app.

Ошибка при отсутствующем app — локальный результат попытки подключения bridge/ИИ-клиента, а не ответ незапущенного сервиса. Сервер не запускается ради выдачи ошибки.


### Concrete Windows MCP publication binding (T305)

Normal WindowsEngineBootstrap now supplies its Host mcpPublication factory.
It borrows the exact retained self/bundle4/runtime, vault, protected files and
actual writer lease acquired for that Host. Factory creates no I/O before
returning the owned pool; descriptor uses actual PID, build, Host generation
and recovered workspace. No separate writer/store, new process, argv owner
role or legacy transport is involved. Eight EmbeddedPipeListener attempts bind
before activation. The live publication guard checks actual retained image/SID,
held lease and runtime, then Ready plus matching generation/workspace. Pool
admission and parent ready acknowledgement still await completed publication.

ProtectedMcpDiscovery owns one descriptor identity and one publish/remove
attempt, registered before provider callbacks. McpDiscoveryFile is a fixed-name
protected file port, with read, atomic replace, retained-object compare/remove
and physical close. Windows binds only LocalAppData/ServerDeckNext/v1/runtime/
embedded-v1.discovery. The existing protected product parent must exist;
runtime directory is created owner-only if absent. Every operation checks the
retained owner/lease, safe local paths and protected parent. Reads reject
reparses/nonregular files, enforce handle ACL and bound wrapped bytes to16384.
Clear descriptor remains8192, custody entropy/format2 are unchanged. Existing
format2 metadata of a different valid build may be inspected as data under the
writer lease and replaced. Legacy/future versions return INCOMPATIBLE;
corrupt/denied metadata returns STORAGE_BLOCKED. These failures do not overwrite
or remove the previous file. Former discovery filenames are never accessed.

Publish validates stale bytes, protects its own descriptor, retains exact
wrapped bytes BEFORE replacement, atomically writes, reads back the exact
ciphertext and unprotects/compares the complete canonical descriptor. Every
await is followed by the live guard before success; all transient buffers and
loaded tokens are wiped. Publish failure after a possible commit still owns
removal. Remove stops new publication, waits its real completion, then removes
only exact retained ciphertext. Missing/different content stays untouched.
Cleanup can run after Ready loss while the same genuine owner/lease is held;
it does not require Ready and cannot publish a new file. File close drains all
issued work. Any unconfirmed native CloseHandle stays sticky in this adapter,
including failed reads before a write or an unexpected native I/O isolate RemoteError; pool close fails and Host retains lease.
No timeout converts native/file work into successful physical completion.

The native writer uses CREATE_NEW on a random16byte .pending name with explicit
owner-only ACL, writes/flushes, then FileRenameInfoEx REPLACE_IF_EXISTS plus
POSIX_SEMANTICS on that SAME retained object. If writing/rename fails, it marks
only the newly created retained object for deletion before closing, including
partial writes; it never deletes a colliding name. Native compare/remove opens
one regular protected object with GENERIC_READ|DELETE and READ sharing only,
compares at most16384bytes, then FileDispositionInfoEx DELETE|POSIX_SEMANTICS and
checked CloseHandle. No pathname delete race, delete-first gap, readonly bypass,
elevated permissions, compatibility fallback or retry is allowed. Unsupported
native semantics fail closed. See [Microsoft file disposition semantics](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/2e860264-018a-47b3-8555-565a13b35a45).

RAM acceptance covers normal write/readback/wipe, different-build stale data,
legacy/corrupt/oversized preservation, absent Ready, proof loss after commit,
readback corruption, write-then-failure, late write versus close, exact removal
versus different bytes, sticky removal/physical-close failure and descriptor
identity isolation. Unit ports execute no native/file/Isar/process/isolate I/O.
The Windows implementation and composition are statically checked; actual
DPAPI/ACL/rename/disposition/pipe execution is unqualified. Remaining client,
headless stdio entry, old binding removal and broad T265/T274/T276 stay open.


### MCP-only client ownership foundation (T306)

Engine mcp/client.dart is the single new portable client implementation for the
embedded endpoint. Its bootstrap/grant/RPC parts belong to the same library;
there are no owner operations, schema switches, old image-role adapters or raw
transport callbacks. The trusted root obtains VerifiedMcpChannel from the new
native connector and verifies descriptor PID there. Client captures actual peer
owner/root/build and checks them on use against its captured binding. Descriptor
supplies matching owner/build, Host generation, recovered workspace and a copied
bootstrap token; it is not authority and can be closed by its owner afterwards.
Construct and retain McpClient BEFORE awaiting authenticate. Constructor creates
no native object/process/store/writer or new connection.

Authenticate is single-use and always requests only mcp, rejecting owner hello,
wrong build/generation/API and bad server HMAC. It preserves the exact API1.1
bootstrap transcripts with token32 and constant-time proof comparison. The
original bootstrap budget is at most5s, including provider work, framing and
proofs; CPU/queued work does not renew it. Token copies and mutable frame buffers
are wiped. Provider actual work is registered before callouts, with observed
native proof futures retained separately from a logical timeout. Only successful
bootstrap starts one ordinary reader. There is no reconnect or automatic retry.

Before grant, public call permits readiness.get, session.ping, session.close and
mcp.close; mcp.invoke requires a successfully verified grant. Owner/unknown
methods and raw mcp.open are rejected locally without bytes. One openGrant takes
McpCredentialFiles bound to the actual owner and descriptor workspace, performs
readForBridge without creation/repair, sends the existing mcp.open transcript,
verifies server proof/binding/expiry and closes its temporary key in finally.
It may run only with no ordinary call pending; public calls are rejected while
it runs. Another grant attempt cannot emit a second open. Timeout, malformed
proof or policy failure stops the connection; late credential/native work
remains owned and cannot issue open or publish grant after retirement.

RPC generates UUID request IDs internally; callers cannot replay old envelope
IDs. Request capture includes the entire256KiB envelope, retains exact Unicode
wire text and charges one of16pending slots before collection/encode callouts.
A serialized writer checks native identity and the original5s deadline before
I/O. Responses are bounded8MiB, closed-envelope validated and correlated by both
ID and generation. A response before issue, unknown ID or wrong generation is
terminal. Reply cannot release its pending charge or caller result before the
actual write ACK and final native proof. Readiness also validates recovered
workspace; ping/close/MCP operation result shapes are checked. Results are
recursively immutable. Fixed safe exceptions retain local/remote/transport
origin and existing retry advice; the client never performs that retry itself.
The reader uses idle60s and partial-frame5s absolute deadlines.

Close registers its shared completion before disconnect, stops admission and
rejects pending RPCs synchronously, then waits actual disconnect and every
registered provider/read/write/reader/grant work item. A physical disconnect
failure remains failed on repeated close. Logical timeouts never report physical
completion or permit another connection; late results are discarded and keys
closed. No client close can terminate the main app or cancel durable remote jobs.

RAM unit acceptance covers actual bootstrap/grant transcript MACs with scripted
peer and fake in-memory file/protection ports, owner/MAC rejection, retained
proofs, original deadlines,16pending/serialized write ACK, correlation/generation,
workspace/identity mismatch, read-only grant files, one grant attempt, queued
input capture, malformed result, late credential read and sticky physical close.
No native, process, isolate, real filesystem, Host/database, SSH or UI/design is
started by these cases. Windows bootstrap/gateway migration to this client,
stdio/headless entry and removal of the old client files remain required by
T265/T274/T276. This foundation does not claim working end-to-end MCP.


T307 final-delivery boundary: recursively capture the immutable response BEFORE releasing its pending slot or cancelling its timer. Recheck the original deadline after capture and then current pending ownership immediately before completion. captureMcpResult charges this CPU work to the original EngineClock deadline; it grants no authority and never publishes. Deterministic RAM regression advances a fake clock while reading a nested input collection, proving that capture crossing5s fails instead of returning data.


### Windows MCP client/gateway cutover (T308)

McpProcessBootstrap now creates only WindowsMcpConnector and the new portable
McpClient. Both configured and unconfigured modes require the actual already
running ServerDeck. WindowsMcpConnector is owned synchronously before any connect
work. It derives root from Platform.resolvedExecutable and owner/LocalAppData
from the actual OS, verifies the exact production bundle4/serverdeck.exe/current
process identity, and reads only the protected fixed embedded-v1.discovery.
No caller app-root, owner role, process launch, writer lease, Isar/domain Host,
old filename or schema fallback exists. Missing runtime/file/usable endpoints
is local SERVICE_UNAVAILABLE. Incompatible metadata remains untouched. Existing
paths must be protected directories/regular file, safe/owner-only, wrapped read
at most16KiB. Discovery is unprotected with the same managed CurrentUser vault
and expected actual build. All transient bytes are wiped; descriptor token is
closed as soon as McpClient captures its independent copy.

Connect owns one original5s budget covering verification/discovery, up to8ordered
endpoint attempts, native ready and MCP authentication. Each failed attempt must
physically close before another slot is tried; there is no retry after bootstrap
or effect. EmbeddedPipeChannel.connecting returns an owned native attempt before
ready, including failed/late creation. The expected descriptor server PID is
verified natively; both processes retain same-image/SID/build checks. A logical
timeout stops further attempts and begins close; actual connect/proof/file work
remains owned. Unknown native I/O loss/unconfirmed reader close, failed identity
factory or failed gate creation cannot report a clean connector close. Close
interrupts client/channel first, waits late connect/gate work, then drains client,
channel, gate, vault and retained metadata. It never releases a writer lease or
terminates the main app, since this connector owns neither.

Process bootstrap has a30s startup ceiling, requires Ready with MCP available,
performs exactly one protected read-only grant proof if grant-id is present,
then opens the native generation-bound publication gate and attaches the sole
LocalMcpGateway. No standalone unconfigured gateway constructor remains. The
gateway takes this actual client/gate pair, checks generation/closed state and
uses the EngineClock port (normal monotonic+UTC, no CLI override). Empty tools
or FORBIDDEN without grant require that same live client; no mcp.open/invoke is
sent in this mode. Configured tools preserve existing invoke/poll/cancel, live
policy session.ping under native publication fencing,20s heartbeat,16tool
interests, and exact cancellation of request interest only, never durable jobs.

McpClient.retired and gateway.retired report logical loss independently of their
physical close futures. Stdio observes retirement even when stdin is idle,
stops with terminal status and rejects later output. Every otherwise unguarded
fixed/builtin response (including initialize/ping/protocol errors) obtains a
fixed publication interest when its serialized writer turn begins. It holds the
same native gate and performs client.verifyLive with the remaining5s budget,
then synchronously checks current lifetime before issuing stdout. Fixed data
contains no domain result and requires native liveness rather than grant-policy
ping; configured domain data still requires the full policy ping and expiry.
At most16tool interests plus one active fixed writer guard are retained. Native
lease release waits actual guard and stdout flush settlement, including after
logical retirement; no timeout turns a live flush into physical completion.

McpServer checks gateway lifetime at queue/guard/issue boundaries. EOF normally
closes only this bridge; physical gateway-close failure or bounded cleanup
failure returns nonzero so entry cannot join the same uncertain cleanup twice.
The reusable entry function runMcpStdio(grantId) is ready for the single exe's
Dart --mcp-stdio branch; it bounds fixed diagnostics to stderr and returns an
exit status. Nonzero requires terminating only that owned connector process.
The separate package bin/mcp.dart and ten replaced Windows bootstrap/build/
operational-client/old pipe-worker source files are removed, with no alias or
compatibility facade. Other unused runtime/artifact cleanup remains T276.

RAM acceptance exercises unconfigured live binding/empty list/forbidden call,
logical retirement before physical close, configured catalog with gate+policy
ping, cancel-interest without jobs cancellation, remote unavailable versus
terminal transport/no replay, protected builtin/list publication, idle stdio
termination on app loss, failed fresh proof/no output, actual-flush-before-lease
release and terminal status on EOF cleanup failure. Fake peer/file/protection/
gate and memory streams are used, with actual client/DTO/HMAC/gateway/stdio
policy code. No OS/native pipe/DPAPI/ACL/realFS/Host/Isar/isolate/process/SSH/UI/
design/build/run dispatch is executed. The normal lib/main.dart mode selection
and headless Windows runner are still required by T274; this cutover does not
claim that the single exe's MCP command is runnable or platform-qualified yet.


T309 protected-file cleanup propagation: WindowsProtectedFiles keeps its public
safe STORAGE_BLOCKED result, but reports a PHYSICAL_CLOSE_UNCONFIRMED native
file failure or unexpected I/O RemoteError to the trusted runtime composition.
This notification grants no authority and cannot be configured by CLI/DTO.
Both actual WindowsEngineBootstrap and WindowsMcpConnector latch it permanently.
The desktop metadata-disposal hook fails after store/vault drain so EngineHost
keeps CloseBlocked/writer lease; the stdio connector cannot report clean close.
New-file/empty-file writer, copy target, retained snapshot and replacement
primitives check CloseHandle and preserve this internal failure marker after
wiping/freeing buffers. It cannot disappear during safe exception conversion.
Existing RAM Host metadata-close ordering/failure tests cover the lease-boundary
policy; actual marker production/Win32 close and adapter callbacks are checked
statically only, without native qualification. This also covers late credential
file reads owned by the new client during stdio startup.


T310 closes the first mcp_cutover_review P2: every locally synthesized fixed RPC
failure and overload invocation now owns real native gate/proof callbacks; no
_immediate/no-op guard or _fixed early-return is permitted. Data-free fixed
failures skip grant-policy ping/expiry, but never live native identity/lifetime.
Original-domain operation interests still cannot publish after stdio cancellation.
The existing gateway.md exceptions are updated in place. RAM regressions check
actual acquisition/proof on remote SERVICE_UNAVAILABLE and overload at16pending,
including failed fresh proof before read-side retirement is observed.

T311 closes the second P2: native pipe worker records failed self-identity factory
as sticky cleanup uncertainty, even when no RetainedProcessIdentity was returned.
Its close cannot send a successful physical ACK or allow slot reuse/next endpoint.
WindowsMcpConnector retains that failed channel and propagates close failure.
This conservative rule does not assert a native handle leak happened; it denies
clean-close when partial factory cleanup cannot be proved. Actual Win32 identity
factory/CloseHandle failure is checked statically, not native-injected in tests.


T311 also covers the peer factory: RetainedProcessIdentity.open explicitly
reports PHYSICAL_CLOSE_UNCONFIRMED if its partial process-handle cleanup fails.
NativePipe latches only that uncertainty when opening a peer; an ordinary vanished
peer with confirmed cleanup remains isolated to its connection. Native pipe
worker self-factory failure stays conservatively sticky. Desktop root and its
runtime gate-factory callback retain the explicit uncertainty until final
metadata disposal, so it cannot release a held writer lease without confirmation.
StdIO root already rejects a clean close on failed identity/gate creation. This
is static native lifecycle evidence only, not a native failure-injection pass.
The unused old McpServer.forTesting timeout constructor is removed; current RAM
stdio tests exercise production30/5/35second policy without runtime overrides.


T312 fixed-fallback guard: a failed domain guard or final validation may precede
any native proof/lease (for example grant expiry while queued). Before issuing
the fixed fallback, stdio waits actual original guard settlement and releases
that publication, since no stdout was issued. Only after confirmed release does
it create a separate gateway.protect interest and obtain a fresh gate+verifyLive
for fallback. This avoids reacquiring a gate still owned by the failed original.
All stages share the original writer5s budget; timeout cannot start a replacement
and original late ownership remains in finally. New fallback guard/proof failure
stops without output; no recursive fallback or effect retry. Fallback lease
remains held through actual flush. RAM regression queues a second domain reply
behind a real memory flush future, advances only fake UTC to grant expiry and
checks guarded FORBIDDEN for live proof versus no second output for failed proof.


T312 also checks a policy-ping failure AFTER the original lease is acquired. The RAM gate rejects recursive/concurrent acquisition, so a healthy fixed fallback proves confirmed original release before replacement acquisition. No private domain bytes are emitted, and the replacement lease settles after stdout.


## T313 — private stdio carrier boundary (2026-10-30)

The MCP library no longer uses dart:io stdin/stdout/stderr. Its required
McpStdioPort is owned by the same executable's stdio composition; no standalone
entry, alternate executable or direct-stdio compatibility fallback is supplied.
ChannelMcpStdioPort calls PlatformDispatcher directly with StandardMethodCodec,
without WidgetsBinding, ServicesBinding, runApp, tray, plugins or domain Host.
The existing application entry remains unchanged in this bounded increment:
T274 must still bind the native carrier and select the headless branch. This
increment does not make --mcp-stdio runnable and does not qualify native I/O.

The private channel is serverdeck/mcp_stdio. It is not an MCP tool or public IPC
endpoint. It accepts no caller handle/path/role/root. Exact methods and replies:

| Method | Argument | Success reply | Physical meaning |
| --- | --- | --- | --- |
| attach | integer1 | integer1 | carrier version1, once per owned connector |
| read | null | Uint8List, length0..65536 | one actual inherited-stdin read; empty means EOF |
| write | Uint8List, length1..8388609 | true | every byte actually written to original inherited stdout |
| diagnostic | ASCII MCP:CODE plus LF, CODE matches [A-Z][A-Z0-9_]{0,63} | true | separate inherited stderr, best effort |
| close | null | true | cancellation and physical drain of all carrier I/O/handles confirmed |

False/malformed/error replies are failures. Dart exposes only STDIO_UNAVAILABLE,
never raw platform errors. Attach requires an integer version, not double/string.
One read and one write may be pending independently. The output bound is8MiB
plus the framing LF. A write claims its slot and snapshots bytes before awaiting
attach. The snapshot remains owned until actual native settlement, then is wiped.
Timeout/cancellation above this layer must not release the gateway publication
lease while actual write is still pending. The existing stdio writer owns its
original5s budget; the entry returns nonzero for uncertain cleanup so the future
headless caller can terminate only its own connector process.

Input is one-subscription, pull-based, with at most one pending read while
paused. Cancellation drops observation and prevents further pulls; it does not
claim that the outstanding native read finished. Close is sent immediately,
not queued after possibly blocked input/output. It waits native confirmation and
all already-owned attach/read/write/diagnostic futures. A failed close is cached
and cannot become successful through retry. Pending writes may fail due to native
cancellation; physical completion and successful byte publication are distinct.
Diagnostics accept only fixed codes, at most32 over the incarnation, with one
pending operation and no unbounded queue. The server/entry diagnostic wait is1s;
normal successful shutdown closes the carrier within5s after confirmed gateway
and connector cleanup. Nonzero shutdown must not join uncertain I/O again.

T274 native implementation obligations: capture private duplicates of original
stdio before any SDK output; quarantine SDK/logger stdout/stderr before Flutter
DLL initialization (including transitive plugin imports); never call the SDK's
CONOUT$ resync in MCP mode. Blocking ReadFile/WriteFile must run off the platform
thread with bounded admission; return channel replies on the platform thread.
close ACK requires actual completion/cancellation and confirmed handle disposal,
not logical interest cancellation. Main must parse argv before UI initialization,
use a viewless engine/message pump, bind only this carrier, and never initialize
application Host/store/tray/plugins in stdio mode. These are existing T274
requirements made concrete at this boundary, not a separate service or process.

Acceptance for this Dart boundary is RAM scripted-call units: strict attach,
read pause/resume/EOF/malformed data, cancel versus physical drain, write snapshot/
ACK/slot/size/error wiping, close while attach/read/write is outstanding, sticky
close failure, and fixed bounded separate diagnostics. They inject the invocation
function and do not dispatch native platform messages or create any UI binding.
Native implementation and whole single-executable readiness remain open.


## T274/T315 — same-executable Windows headless binding (2026-10-30)

The source entry is now bound: Windows main parses argv before console/COM/UI
initialization and accepts only empty application argv, --mcp-stdio, or
--mcp-stdio --grant-id plus one canonical lowercase v4 UUID. Failed argument
conversion is distinct from empty argv. Unknown/legacy/root/owner/repeated flags
fail locally, without echo and without a UI/Host fallback. Dart revalidates using
the same grammar before either side effect. Empty argv alone installs UI runtime
diagnostics and runs DesktopApplication. MCP invokes only runDesktopMcp, awaits
the private carrier version1 readiness (5s), then the existing connection-only
bootstrap. It never creates a domain EngineHost, app store, tray, view or plugin
registry. The Flutter VM engine is a library runtime for this same executable's
short-lived connector, not a second domain service. A missing main application
still yields only local startup failure; no main app is launched.

Native McpStdio owns duplicates of inherited stdio before the first SDK call.
Stdin and stdout must be valid Windows pipe handles. Both synchronous and
overlapped pipe handles are accepted, using NtQueryInformationFile's
FileModeInformation16 to select the appropriate ReadFile/WriteFile form. Valid
stderr is duplicated separately; absent stderr or the same underlying object as
stdout is replaced by an owned NUL diagnostic handle. Character stderr uses
synchronous writes. Diagnostics remain fixed ASCII, <=64code characters plus
MCP: and LF, one pending and32 total. No caller-supplied handles/paths/roles.

The runner and every generated runner plugin import are delay-loaded, so a
plugin's transitive Flutter import cannot initialize SDK stdio prematurely.
Only this connector sets process/CRT standard streams to NUL. Before delayed SDK
CRT initialization, it neutralizes the already-consumed CRT startup inheritance
count in its own process; this is necessary for normal Node/libuv clients, not
an old-version compatibility path. Accepted current UCRT/libuv table ABI is a
32bit count followed by count flags and count pointer-sized handles, count<=2048
and within cbReserved2; zero/no table also works. The count is read, zeroed and
read back through checked current-process Read/WriteProcessMemory. Original byte
handles have already been duplicated and remain unchanged. Unknown/truncated or
unwritable startup metadata fails closed. A preloaded Flutter DLL fails closed.
The SDK is explicitly loaded from the executable's directory after quarantine;
SDK loader/error dialogs are suppressed only in the connector process. It never
calls CONOUT$ resync, AttachConsole, AllocConsole or RegisterPlugins.

The supported native source target remains Windows10 x64 and the pinned Flutter/
Dart runtime. The carrier creates one Win32 worker per input/output/diagnostic,
each with one private event and a stable retained thread HANDLE. No blocking pipe
I/O runs on Dart or the platform thread. Writes handle partial completion in
<=64KiB chunks; an ACK means the entire frame was physically written. Overlapped
I/O buffers/events remain alive through GetOverlappedResult. Read replies contain
only the actually read bytes, EOF is empty, and native buffers are wiped after
platform-thread method reply encoding. No write replay or observation retry.
Method completions run only on the platform thread, with slots charged through
reply. Platform event pumping obeys Flutter ProcessMessages' deadline, wakes on
native completions and dispatches messages without creating a FlutterView/window.

Close stops admission, sends CancelIoEx plus CancelSynchronousIo to its own
workers, then waits for actual I/O settlement, checked I/O/event close, signaled
thread exit and checked thread HANDLE close. Cancel return is never a completion
ACK. A race where cancellation precedes kernel issue remains physically owned;
no false drain: native close watchdog terminates only this connector after its
original5s. A separate native watchdog covers capture/SDK/bootstrap startup30s,
then is disarmed by the first server input read after successful bootstrap.
It re-arms on close and is itself signaled/closed before a clean close ACK.
Unconfirmed CloseHandle latches failure and prevents successful close/exit.

Additional private channel method finish takes integer0..255 and never replies:
it terminates only GetCurrentProcess via TerminateProcess, bypassing DLL/CRT
detach locks on uncertain writes. Zero is permitted only after confirmed clean
carrier I/O close and checked disposal of the retained wake/NUL control handles;
otherwise the owned process exits nonzero. SDK/library process-lifetime memory
is reclaimed by the OS. A normal EOF first completes gateway/connector cleanup,
then carrier close, then finish0. A nonzero result never joins uncertain I/O or
cleanup again and cannot terminate the main desktop process or cancel its jobs.
An unexpected WM_QUIT, SDK load/run error or watchdog expiry is owned exit1.
Dart's MCP zone drops print and maps uncaught async faults to nonzero exit,
without forwarding exception text. The native channel is private trusted code,
not an externally callable MCP method. If native finish is unavailable, Dart
falls back to nonzero exit. Invalid native argv exits nonzero before SDK loading;
the pure Dart dispatcher returns64 if independently invoked with invalid argv.

RAM acceptance: existing argv/EOF/publication/physical-close cases plus six new
production-dispatch/owned-zone cases check branch isolation, forwarded grant,
late terminal code, no rejoin/retry, failed factory and suppressed print/uncaught
async faults. Native static /Zs checking parses the changed C++ with MSVC17 flags
and pinned SDK headers, generating no object/binary and running no app/I/O. This
is not Win32 I/O/CRT inheritance, loader, GPU, lifecycle or installed-command
qualification. Unit/static evidence does not prove runtime success. Production
bundle/scripts T271, wider T253-T276 acceptance and final review remain open.


## LocalJobObservation projection and terminal gate — T384

The existing format3 successful job-read data now includes the runtime observation
beside job for jobs_get/jobs_list and owner equivalents; the durable job document,
stable ACKs and executor wire are unchanged. Exact fields generation,attemptId,
state(attached|detached|stale),lastSequence,observedAt and their null/freshness/
identity rules are defined in001 contracts/embedded-engine.md, Local job
observation and recovery. This refines the overlay requirement above, not a new
remote state/schema or a permission/compatibility format. Clients require the
current field, and rejected/old-generation data cannot become current observation.

Reconciliation terminal acceptance requires actual current owner/grant and
same enrolled host/attempt, nonbackwards status relative to the ACK/prior runtime
floor, required postchecks and childrenStopped=true. False or missing stopped
proof, pending/unknown, malformed/foreign/late responses retain unknown and host
occupancy. An ACK alone never publishes terminal. A valid terminal frees local
occupancy for a distinct authorized plan; retrying an admitted plan never submits
again. New-generation recovery recreates detached observations and restores no
one-time permits. Queued unsent intent is safely cancelled; running/cancel-requested/
reconciling become unknown, existing unknown/terminal remain unchanged.


## Accepted control after local driver drain — T391

The existing engine-owned continuation coordinator keeps at most one pending
cancel and one pending reconcile per nonterminal job. Each retains its actual
currently authorized actor and the original30s invocation deadline, never a
wire role/permission or restored old grant. One metadata FIFO mutex registers
accepted new/replayed intents atomically with runtime ordering; it is not held
while waiting for old physical drain or new root I/O. Only positive owned driver
completion permits another actor/session on that job. Latest pending same-kind
invocation coalesces earlier interest, but operation polling never renews it.

Activation uses fresh proof/receipt/target/enrollment and, if needed, rearms the
existing unknown→reconciling through trusted progress for that accepted intent.
No new receipt, submit, approval consumption or permit. Separate read/apply-scope
actors are never borrowed between modes. Cancel is one stable stop intent plus
at most one status query; reconcile remains stopped-proof/status-only under T386.
Expiry, revoke, suspend or Exit does not launch pending work; uncertainty stays
occupied. Closing the last window to tray is not Exit and does not seal the
running engine. Full ordering, quotas, lifecycle and RAM acceptance are in001
contracts/embedded-engine.md, Accepted job control handoff. No wire/schema upgrade.
