# Capability matrix встроенного движка

**Direct SSH amendment 2026-11-01**: [действующий контракт](direct-ssh.md). Новое выполнение использует прямой SSH без устанавливаемого executor/Ansible/enrollment. Прежние описания этих компонентов ниже относятся только к historical format1; они не разрешают его исполнение или fallback. Остальные правила данных, прав и лимитов сохраняются. При конфликте в исполнительной архитектуре действует поправка.

Целевая архитектура, не заявление существующей поддержки. Реальный код сегодня
Windows-зависим; native acceptance в текущем scope запрещена.

| Платформа | Процессы/lifecycle | Storage/credentials/runtime | Статус |
| --- | --- | --- | --- |
| Windows | один app с engine, tray после close, explicit exit; MCP stdio mode того же serverdeck.exe запускается ИИ-клиентом | текущая Isar DLL ABI3.3.2, DPAPI user scope, SID/ACL, общий mutex, app-verified pipes | первый этап001.E1/E2, native не проверено |
| Linux | один app, tray при поддержке desktop host; без него скрытие не допускается | Isar lib нужной arch, private directory/lock, Secret Service/libsecret; vault unavailable/locked блокирует secrets | последующая отдельная поставка |
| macOS | один app, tray/menu bar возвращает окно, Quit завершает | Isar dylib, sandbox paths/lock, Keychain с app identity | последующая отдельная поставка |
| Android | один app engine, foreground baseline, suspend останавливает observer | app-private Isar library, Android Keystore wrapping и private ciphertext, no secret backups | последующая поставка, FGS не включён |
| iOS/iPadOS | один app engine, без обещания постоянного background | sandbox Isar library/lock, device-only Keychain, locked key блокирует secrets | последующая поставка; external stdio MCP отсутствует |
| Web | UI без прямого SSH/локального TCP | нет native FFI/DPAPI; browser storage не native vault | вне локальной поставки, будущий optional remote node |

EngineCapabilities — immutable snapshot: platform, storageReady,
vaultStatus(available/locked/unavailable), directSsh, localMcpBridge, trayAvailable,
backgroundPolicy(desktopWhileRunning/foregroundOnly/unsupported), reasonCodes.
Windows Ready требует storage/vault available. До реализации иной host возвращает
unsupported без импорта Windows fallback. Runtime vault/lifecycle change создаёт
новый snapshot и закрывает admission; capability flag не выдаёт permissions.

Ports уже определены [engine](embedded-engine.md). Конкретные SDK/plugin версии
не-Windows поставок выбираются в планировании соответствующей поставки до её
implementation; не требуются для начала Windows extraction/adoption. Нельзя
включить platform build flag и объявить поддержку. Mobile baseline foregroundOnly
без FGS/постоянного MCP. Фоновое расширение требует отдельного согласованного scope.

Apple даёт ограниченное время/background modes, а не произвольную бессрочную
работу ([background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)).
Android FGS требует видимой работы и имеет ограничения
([официальный обзор](https://developer.android.com/develop/background-work/services/fgs)).
Отсюда suspend означает detach/reconcile. Источники проверены2026-10-30;
конкретная доступность API зависит от будущих minimum OS/target SDK.

## T326 — immutable runtime snapshot and resume binding

This section fixes the implementation decisions for T269/T326 in the existing
embedded change, under FR-SVC-EMB-10/11, AC-SVC-EMB-10/11/12 and SC-SVC-EMB-05.
It adds no non-Windows delivery, native qualification, storage format or public
MCP API. OperationalFeatures remains the installed domain feature projection;
it is not a substitute for observed runtime prerequisites.

### Model and platform rows

Implement EngineCapabilities in engine hosting/capability_snapshot.dart. It
imports no Flutter, Windows provider, dart:ffi or runtime loader. Its platform
enum is windows, linux, macos, android, ios, web. iOS and iPadOS share ios. The
immutable closed snapshot has exactly these eight fields in its private map:

| Field | Closed values / meaning |
| --- | --- |
| platform | one of the six enum names above |
| storageReady | boolean; current Host has validated usable schema3 storage, not merely an open physical handle |
| vaultStatus | available / locked / unavailable; unknown or invalidated positive proof projects unavailable |
| directSsh | boolean; currently admitted SSH component, not a live target connection or permission |
| localMcpBridge | boolean; currently admitted and published local bridge, independent of configured grant count |
| trayAvailable | boolean; actual desktop icon availability, supplied by desktop composition |
| backgroundPolicy | desktopWhileRunning / foregroundOnly / unsupported |
| reasonCodes | immutable canonical sorted unique list of at most8 fixed safe codes below |

The reason code set is NOT_READY, TIMEOUT, STORAGE_BLOCKED, INCOMPATIBLE,
PREREQUISITE_UNAVAILABLE, UNAUTHORIZED, RESOURCE_LIMIT, SERVICE_UNAVAILABLE.
Codes describe core admission blockers only. Optional SSH/MCP/tray absence does
not itself add a blocker or change a healthy Windows core to failure. Locked
or unavailable vault observed by a probe uses STORAGE_BLOCKED. Unknown initial
or lifecycle-invalidated prerequisites use NOT_READY. Terminal failure uses
the existing safe failure code; unsupported platform uses
PREREQUISITE_UNAVAILABLE. Unknown errors normalize to SERVICE_UNAVAILABLE.
No paths, owner credentials, native diagnostics or free-form reasons enter this
snapshot. Parser rejects unknown/extra/missing fields, wrong types/enum values,
duplicate/noncanonical reasons or internally contradictory success flags. There
is no old or optional snapshot shape. Constructors copy collections; toJson
cannot expose mutable state. A capability flag cannot mint a grant or bypass
runtime identity, lease, owner, trust or domain permission checks.

| Current row | storage / vault / SSH / MCP / tray | Background policy | Core admission |
| --- | --- | --- | --- |
| Windows before current validation, during suspend/restore or after stop | storage false; positive vault proof withdrawn to unavailable; known negative probe may retain locked/unavailable; SSH/MCP false; desktop supplies actual tray | desktopWhileRunning | blocked with current safe reason |
| Windows after actual successful startup/restore | storage true, vault available; SSH equals actual installed/admitted feature; MCP equals actual published/admitted bridge; desktop supplies actual tray | desktopWhileRunning | available; reasons empty |
| Linux | false / unavailable / false / false / false | unsupported | unsupported |
| macOS | false / unavailable / false / false / false | unsupported | unsupported |
| Android | false / unavailable / false / false / false | foregroundOnly | unsupported; no background promise |
| iOS/iPadOS | false / unavailable / false / false / false | foregroundOnly | unsupported; no external stdio bridge |
| Web | false / unavailable / false / false / false | unsupported | unsupported; no direct TCP/SSH |

All five unsupported rows have exactly PREREQUISITE_UNAVAILABLE as their reason.
The two Windows rows describe lifecycle states of the same platform, not two
platform implementations. All runtime-dependent success flags require the
Windows core prerequisites; storage true requires vault available and empty
blocker reasons. Non-Windows success flags or desktop tray true are rejected.
The derived core-admission predicate requires Windows, storageReady, available
vault and empty reasons. It is necessary but never sufficient authority.

### Host ownership and observation

EnginePlatform requires an explicit platform enum; the normal Windows root
supplies windows, all current RAM roots declare their row explicitly. No
implicit Windows default is retained. A non-Windows EngineHost fails startup
with PREREQUISITE_UNAVAILABLE before querying runtime identity, acquiring a
lease, checking/opening storage or probing a vault. The matrix factory itself
is pure and never constructs a platform adapter. Transferred fake/platform
objects still follow existing idempotent owned cleanup; unsupported does not
authorize abandoning already transferred resources. Future real non-Windows
composition is outside this implementation and cannot acquire support by merely
changing an enum. Current WindowsBootstrap retains its existing OS check before
any Windows native provider operation. The current Windows app is not claimed
to be a runnable non-Windows bundle.

EngineHost records actual vault probe results and successful workspace/service
validation. Initial/unknown state has no positive storage or vault proof. On
suspend, shutdown or observed runtime failure it withdraws positive proofs
before callbacks and external continuations. Physical handles/store/lease remain
owned until the existing cleanup completes; storageReady false is not closure.
Failure retains a known negative locked/unavailable probe for diagnosis. Runtime
identity/lease, vault, storage, executor/services and workspace checks remain
mandatory in startup/resume in their existing order and original deadlines.
Successful resume commits a new usable snapshot only after the current epoch's
final checks and service restore; superseded/expired work cannot restore flags.
Early paused startup uses its original checkpoint and budget, not another start.

Host readiness, open-owner admission and EngineSessions admission consult these
current prerequisites as well as the existing pause/stop/deadline/authority
guards. A live admitted session still goes through its normal runtime/domain
validation. Capability changes do not erase jobs, alter schema3, reopen store,
replace services/worker or replay operations. MCP activation still uses the
existing Host/pool publication guard. During the existing pre-publication Ready
phase, storage/vault core prerequisites must already be valid; MCP capability
becomes true only when the bridge is actually published. Required core admission
does not depend on optional localMcpBridge, avoiding a publication cycle.

Observation is performed at existing startup/resume checks and known failure
boundaries; this change introduces no continuous vault watcher, OS-lock callback,
health polling or guarantee that a silent provider change is instantly detected.
Once a changed prerequisite is observed, admission and snapshot are withdrawn
in the same Host transition. RAM vault/lifecycle tests change the actual fake
port result and run the existing transition; changing a fake field alone is not
evidence that production has observed an event.

### Private worker and desktop composition

EngineBootstrap and EngineWorkerController declare their expected platform
explicitly. Root verifies a created Host reports that same platform. A platform
mismatch retires the incarnation as INCOMPATIBLE without fallback or retry.
WorkerStatus gains required capabilities beside phase/reason/readiness; all
current producers, consumers and RAM fixtures adopt the new closed four-field
shape, with no optional compatibility parser. Ready requires a usable core
snapshot, and nonready status cannot carry storage/SSH/MCP success. Existing
generation pinning, exact envelope validation, quotas and physical reply ownership
remain unchanged. Power/failed/lost/closed projections withdraw success flags.
Root before Host creation uses its declared platform's unavailable snapshot.

The worker does not own the desktop icon and reports trayAvailable false.
DesktopEngineControl gains setTrayAvailable(bool), implemented as a local
controller projection only: it creates an immutable copy of the last accepted
snapshot with the actual desktop flag. No new control frame, credential, worker
resource or role is created. DesktopLifetime feeds the actual initialize result
and trayAvailable/trayUnavailable events through this method; stale initialize
results cannot undo a newer icon event. Controller overlays that same current
flag on each validated Root status, including late replies and lifecycle masks.
This overlay cannot change platform, core prerequisites, reasons or feature
flags; it never grants Host admission. Non-Windows rows cannot gain tray through
the overlay. A missing Windows tray preserves the existing visible-window
fallback and does not stop a healthy Host/MCP.

Ready observed while old parent detaches are pending remains masked exactly as
in T343–T348, including capabilities. Both metadata public continuations use
the accepted controller snapshot; old raw Root success cannot bypass this gate.
Fresh UI after T350 consumes the new current snapshot and new owner; it cannot
reuse old private state or mutation interests. No MCP discovery/readiness/public
tool wire schema or durable record is changed by these private VM metadata.

### Acceptance and evidence limits

RAM tests must cover closed immutable parsing, all six platform rows and each
background policy; negative vault/unknown observations; actual Host startup/
suspend/current resume/superseded resume/failure/shutdown; usable flags only
after proofs; original ownership after a failed/expired probe; explicit platform
mismatch/unsupported rejection without loader/probe/open attempts. Fake cleanup
is accounted separately from prohibited provider startup. Verify directSsh=false
and localMcpBridge=false on Web, foregroundOnly without admitted work for mobile,
and no success from a forged capability alone. Reuse actual Root/controller
RAM ports to verify required snapshot/generation/platform binding, masks and
late metadata, plus actual desktop policy with fake icon results/events and
stale initialize. Do not create native or non-Windows production adapters.

Static import/loader-source checks separately verify that the pure snapshot
module and engine matrix/fake-host paths do not import or select Windows, Flutter
or native FFI fallback. Preserve existing domain import-boundary coverage and
classify its source Directory/File scan as static, not RAM. Source checks do not
prove a runnable mobile/Web/Unix host, native loader behavior, power delivery or
FFI/Isar/vault correctness. Required full format/analyze/unit and specification
link checks plus a completed independent review/fix loop are needed for code
acceptance; Native/isolate/FS/SSH/process/UI/widget/design/build/install/deploy
execution remains outside the user's allowed verification scope.
