# Accepted-peer native control coordination

## Current validation stage (2026-10-27)

The explicit user instruction and Constitution4.0.0/VII limit local and
automatic push/PR CI validation to **unit/widget and static checks** for
PR3/source-only MIT preview `0.2.0-preview.1+9`. Apply the
[current-stage gate](../../003-design-system/plan.md#unit-widget-stage-2026-10-27)
and [pure queue/static commands](../quickstart.md#current-unit-widget-commands)
before the older full-cold/native acceptance instructions in this contract.
This is a verification-stage change, not a product-contract change.

All coordination, identity, authority, logical/physical settlement, admission,
quota, original deadline, failure and cleanup requirements below remain intact.
Current-stage source acceptance uses pure scheduler RED/GREEN/regressions,
root unit/widget and static checks, pure protocol checks, strict links and a
fresh independent source/policy/spec review with actual recorded scope.
[T213](../tasks.md#current-unit-widget-stage-2026-10-27) is separate from
uncompleted original T207 full-native acceptance.

The full genuine native acceptance below, including channel72/Windows176/
grant66 and original16/17/native3 oracles, remains future qualification.
Previously completed TerminalFocused2 and ObserverFocused8 are focused
evidence only; the user-cancelled ChannelFull72 after8passes/0failures has
no terminal success and remains incomplete. No native/FFI/Isar/DPAPI,
service/process/pipe/integration/real-SSH/container or cold test workload runs
now without a new user instruction. Native CI jobs are preserved for explicit
future manual qualification; skipped/not-selected are not successful execution.
The new exact-source push/PR unit gate replaces the old cold gate only for
this current merge/source-only preview. It does not establish full021,
native distribution/signing, full001/005 or production readiness.

## Purpose and compatibility

This corrects server self-overload under FR-MCP-004/005 and AC-MCP-1B, preserving
the [channel](operational-channel.md), [invocation](invocations.md) and
[gateway](gateway.md) contracts. A standing read, an unfinished write and one
proof can legitimately occupy all three ordinary PipeWorker entries. A second
independently admitted logical request must wait for a fresh proof rather than
issue a fourth native command. Native quota3, channel/session16, seventeenth
logical refusal, original deadlines and cancellation semantics remain in force.

This is an internal Dart scheduling change in locald, shared by format2 and
format3. There is no wire/schema/storage migration, native worker modification,
new credential, client reconnection, completed-proof cache or native retry.
Existing private native peer constructors and exact role/build/epoch tuple
validation remain the only source of peer authority. A pure scheduler with
injected functions for testing cannot mint a server peer or session.

## Components and ownership

`packages/serverdeck_locald/lib/api/native_control_queue.dart` owns a bounded
control scheduler. The private `_ServerPeer` in `server_peer.dart` captures the
actual peer's revalidation and bundle-root functions and owns exactly one
scheduler for the accepted peer. The handshake passes this same binding into
its registered session; requests and derived contexts reuse it. Never share a
scheduler across accepted epochs/workers or construct a new one per request.

One issued control job is permitted per binding. Jobs are either a proof
cohort or one distinct bundle-root request. A pending proof cohort accepts
members until it is sealed immediately before native issue. A caller arriving
after sealing joins a later cohort, even if the active proof has already
succeeded but its delegate workflow has not settled. Thus every member joins
before its actual fresh native proof is issued. Each cohort issues exactly
once; no successful proof is reused by later arrivals. Metadata requests are
not coalesced and return the original validated root without caching.

Control jobs are selected in creation order. There is at most one joinable
pending proof cohort; joining it does not create a new job. Metadata jobs
already ahead of a newly created cohort run first. A pending cohort ahead of
metadata is issued once and sealed; subsequent arrivals cannot prolong it.
Empty/expired pending jobs are removed without native issue.

## Bounds, budgets and logical membership

The hard internal bound is1024 live tickets per binding, counting issued and
queued members and individual metadata requests together. The1025th live
registration returns existing RESOURCE_LIMIT before native issue, without an
observer callback, peer poisoning or session retirement. This is an internal
defensive bound, not a replacement for existing RPC/service admission; normal
channel16/shared16 cancellation and bounded backpressure remain required.
The conservative production accounting is443: RPC16, router RPC context16,
catalog128, authority32, plans32, job operations32, job drivers48, probes16,
remote reads48, combined connection work48, transport setup2, shared refresh2,
grant opens4, bootstrap2, sealed terminal1 and metadata16. These existing global
maxima are deliberately counted against one peer, including overlapping parent
and child work. Arbitrary repeated public context calls are instead constrained
by the unconditional1024 guard. Re-audit this accounting when adding consumers.
Each ticket owns at most one completer, timer, remaining-budget guard and
optional actual-completion observer. Jobs and their member sets cannot grow
beyond this bound. Once issued, one cohort can deliver observers to at most
1024 members; later expired/replacement tickets cannot join that cohort.

Adapters provide a synchronous remaining-budget getter for their existing
admitted lifetime. The scheduler evaluates it at registration and again
immediately before issue, rejecting an expired/ineligible ticket without native
work. A timer uses the original remaining duration, capped at the existing
native/RPC5seconds; queue wait, issue and logical completion share that attempt
budget. No wait restarts an RPC/operation budget. Timer expiry is represented
as TimeoutException so adapters preserve their existing fixed TIMEOUT mapping.
An existing StateError(TIMEOUT) from a remaining getter has the same expiry
meaning. Other getter failures preserve existing adapter fail-closed mapping.
Keep locally rejected/expired/capacity/withdrawn outcomes distinguishable from
actual native failure internally. Adapters return the corresponding existing
fixed code without treating a local ticket rejection as a new physical identity
failure or detaching a different/live session. These internal tags are never
wire fields. Actual native failure retains the existing identity-checked detach.

The request getter checks original request completion, exact current session
and original RPC time. MCP context attempts check exact current session and a
single stopwatch budget within the supplied remaining deadline. Owner contexts
use min(original remaining15s/30s/2h,5s). Bootstrap, open and sealed failed-open
use their existing remaining guards. Preissue identity checks do not perform a
new store lookup during an authority publication pause: the existing stable
preparation and fresh post-await authorization loops remain responsible for
grant/scope checks. A native proof alone never authorizes effects or output.

Expiry/retirement removes a ticket from the scheduler and clears its guard,
observer and timer references. Do not attach a permanent per-attempt listener
to a session's long-lived detached future. A caller's outer timeout does not
release physical native occupancy. Cancellation of higher-level response
interest preserves its existing semantics: an already-admitted read-only proof
attempt remains bounded by its original attempt/session lifetime; success
cannot bypass the service's existing cancellation and post-await guards.
Use detachable logical owner scopes for exact session and request lifetimes:
session removal synchronously withdraws its ordinary tickets, request.complete
withdraws that request's tickets, and helper retirement withdraws all tickets.
An independently admitted context uses the session scope without the completed
RPC's scope. The sealed failed-open permit uses its request scope and special
remaining guard, without the detached ordinary session scope. Scope removal
only settles logical tickets; already-issued native ownership is preserved.

## Actual completion and errors

The raw proof delegate supplies its actual epoch/role/build-validated native
future through observeNativeCompletion. Seal/set the active job before calling
the delegate, including synchronous/reentrant paths. Deliver that same actual
future once to each member eligible at the issue frontier. Install each issued
ticket's physical ownership before invoking any external observer. A synchronous
observer that retires another member cannot erase that member's already-issued
actual accounting or prevent its notification. A throwing observer
fails only its member with existing SERVICE_UNAVAILABLE after actual completion
(or its earlier original timeout); continue delivering all other observers.
Observer failure does not turn a valid proof into authority failure for peers.

The physical control gate is retained until both that actual future and the
raw delegate workflow have settled, including failure, observer reentrancy and
logical timeout. Observe all errors; a logical future is not a native drain.
Each ticket has a logical result and a separate settled completion: unissued
withdrawal settles both; an issued ticket settles physically only after actual
and delegate completion, even if its logical result expired. Owner async/probe
context `settled` tracking must retain this combined queued/physical settled
handle before the scheduled pump can issue. Observing only a logical Future
or taking a reentrant snapshot before actual-observer delivery is insufficient.
Its queued attempt cannot
issue after the service has drained and released its admission. Preserve the
existing stop-issuing-before-settled rule. Existing shorter outer deadlines in
`automation/plans.dart` and `automation/jobs.dart` must be passed into the owner
context via an additive optional deadline argument, defaulting to5seconds.
The original min(operation remaining, outer remaining,5s) applies before queueing.
An unissued/expired ticket supplies no actual-completion observer.

A delegate refusal before any actual future, including native RESOURCE_LIMIT,
settles the issued cohort without retry. RESOURCE_LIMIT alone does not poison
the binding; other native identity/transport failures retire it. A failed
actual proof also retires the binding and all queued work fail-closed, with no
success for other members or later native issue. Existing adapters retain their
fixed UNAUTHORIZED/TIMEOUT/RESOURCE_LIMIT mappings. Metadata holds the same gate
until its actual returned workflow settles even after logical timeout; native
metadata identity/transport failure likewise retires the binding.
At session registration install one private binding-failure callback capturing
the original registry/channel/session. Actual/delegate failure invokes it once
even after every logical ticket expired; detach only if that exact session is
still current. Isolate hook failures so all tickets and actual errors remain
observed. Pre-registration failure remains owned by handshake/channel cleanup.

## Lifecycle and all ordinary control commands

Route `TrustedSessionRequest.verifiedOwnerBundleRoot()` through this same gate,
with original rpcRemaining and role/admission guards. Its distinct native
peerPublicationIdentity request cannot overlap a proof. Registry publication
gate creation is before channel intake; bootstrap raw write-verification is
sequential before the client can issue ordinary RPCs. Route the latter through
a narrow handshake binding method too, using the channel's original remaining
budget; it must still work after authenticate has disposed the token. Neither
path can introduce a concurrent post-bootstrap escape around this gate.

Handshake `close()` retires the binding synchronously before native drain and
disconnect. Successful authenticate's token disposal does not retire it.
Session detach alone does not retire the raw binding: the sealed initial
failed-open error still needs its single special guarded proof/write. Ordinary
queued members fail their existing session/request guard instead. Retirement
rejects and detaches logical members but retains active actual ownership.

An ordinary session.close/mcp.close ACK retains the channel's one serialized
writer through its ensuing close. Its write completion is followed in that same
continuation by handshake retirement, before waiting for actual control
settlement or issuing native drain. A later queued reply cannot enter its
publication proof/write after the ACK, including while its body remains unread.
Already issued actual control remains owned until settlement; retirement neither
cancels physical completion nor grants a new deadline. Failed-open terminal
supersession still drops an ordinary close that did not own the terminal
publication. Original-last-write-budget settlement/drain, quota-exempt
current-epoch disconnect, post-disconnect join, failed-disconnect ownership and
replacement-epoch isolation remain exact. T211's genuine owner/MCP tests for
both formats use the header/body hold and same-worker reuse specified in the
[channel contract](operational-channel.md#close-and-acceptance); observing drain
does not introduce a fourth ordinary native command.

T212 records the immutable channel dispatch deadline for ordinary and sealed
first-open terminal writes at native worker command admission, before awaiting
completion. The additive peer.write observer receives the actual completion
future only after synchronous peerWrite admission succeeds; no callback occurs
on local size/quota/closing refusal. The sealed permit forwards it after its
existing proof and final lifetime/budget guard. Pre-admission refusal preserves
the prior admitted deadline; admission after an earlier ordinary write replaces
that deadline with the terminal request's own original deadline. A concurrent
close sees pending admitted writes. Callback-null write behavior stays exact.
A synchronously throwing observer cannot abandon the actual command: observe and await its
physical completion, then fail with fixed SERVICE_UNAVAILABLE without retry.
This callback conveys accounting only, creates no native/session authority and
does not add a control command, quota or deadline. A native rejection after
command admission still supplies its actual failed completion. No production
fault hook is introduced.

Genuine format2/3 native worker tests cover notification while a large write is
pending, synchronous fourth-command quota refusal with zero notifications,
throwing-observer retention until independent consumption/cancellation, actual
error observation, unchanged callback-null writes and replacement-epoch reuse.
Channel first-RPC failed-open tests use the independent terminal header/body
hold defined in the [channel contract](operational-channel.md#failed-grant-open-terminal-response).
Pre-write proof/permit refusal must not reset an earlier admitted budget;
terminal supersession, earlier ordinary-tail ownership and concurrent close
must preserve each applicable original deadline. These cases supplement, and
do not replace, T211's ordinary close cases or original16/17/native3 assertions.

Before close's optional outbound-buffer drain, wait for active control settlement
only within the last issued write's original remaining deadline. If that wait
expires, skip drain and proceed to quota-exempt epoch-bound disconnect. Never
wait indefinitely before disconnect or extend committed-tail delivery time.
After successful disconnect, join control settlement before claiming channel
cleanup complete. A failed disconnect remains failed and cannot permit reuse;
the outer pipe-pool retains failed physical ownership. New accepted epochs get
new bindings, and stale queued work can never issue on a replacement epoch.

## Acceptance and scope of evidence

T204–T207 in [tasks](../tasks.md) implement and verify this contract. Pure tests
must reproduce the source-reachable W+V+R quota3 schedule against the old direct
adapter, then pass with coordination. Cover fresh preissue cohort membership,
FIFO metadata, expiry before/after issue,1024/1025 bound and reclaimed tickets,
observer isolation/actual+delegate drain, immediate refusal without retry,
native failure/retirement, and reentrant callbacks. Model completions do not
qualify actual native identity or wire behavior.

Genuine Windows tests retain all original16/17/shared cancellation assertions,
continuously-reading17 correlated replies, format2/3 admission/role/epoch checks,
sealed first-open failure, queued revoke/expiry rejection, physical teardown and
worker quota3 rejection of a direct fourth ordinary native command. Add actual
metadata/proof overlap coverage without an extra observation command consuming
a fourth slot. Run mandatory root format/analyze/test, affected package/native
checks, strict spec links and the independent AGENTS review/fix loop.

The T208 physical-probe fixture correction distinguishes two real boundaries.
A public owner cancel RPC started behind an intentionally paused native proof
must remain pending; the fixture releases that pause independently, within the
original RPC budget, before awaiting the authenticated cancel result and physical
cleanup. It cannot await that cancel and only then release the proof it needs.
Separately, retain cancellation's service-level physical-ownership oracle using
an independent genuine owner cancel request admitted before the pause, within
its original budget, and the actual `HostTrustProbeService.cancel` method. This
case still requires retained admission, no SSH work, and close remaining
unfinished until the held actual proof is released, followed by zero retained
work/transports. This lower-layer case does not claim an extra API revalidation;
the separate public-RPC case and existing ordinary `probe-cancel` case exercise
that complete path. Production owner API checks, coordinator gate and original
timeouts are unchanged; no fake request/proof or extra production test hook is
introduced. Physical detach/stale cases retain their original assertions.

T209 keeps native capacity qualification separate from expensive artifact setup.
The existing `native_failure_test.dart` map-full case must perform the full
candidate/source validation and core initialization in its Windows-only native
group's suite setup, before the workload's unchanged default30second budget.
The portable exact-error classifier stays outside that group and does not
require a native library when selected alone. Preserve the10MiB map,128
transaction bound,256KiB profile payloads and unique identifiers, atomic rollback assertions,
delete/recovery and close/reopen proof. Record setup and workload timing with
fixed markers only. Do not cache around source validation, weaken rollback
classification, raise the workload timeout or change production/native code.

T210 applies that same setup boundary to the two remaining default30second
fixtures identified by source audit. In `native_runtime_test.dart`, only full
artifact selection moves to the Windows native group's suite setup; fabricated
bundle bytes, manifest/hash rejection and the absolute pinned native load in
the owned child remain the measured test. In `records_test.dart`, selection and
core initialization move to Windows native-group setup; DPAPI protection,
metadata/index assertions, real unique-collision rollback, corruption refusal,
unchanged source bytes/ACL checks, persisted-secret recovery and foreign-schema
rejection all remain in the measured body. Preserve both original30second work
budgets, every input/assertion and owned-child/database cleanup. Record fixed
setup/workload timing markers; no validation cache, timeout override, skip,
native/runtime/product modification or changed test payload is introduced.

The observed controlled cancellation failure and FIFO-preserving source witness
establish a self-orchestration defect. They do not establish the exact cause of
the historical CI8 failure. Exact new-source cold CI must succeed before merge
or publication. No whole021, source-qualified native distribution, signing or
full product acceptance is inferred from this fix or from local installation.
