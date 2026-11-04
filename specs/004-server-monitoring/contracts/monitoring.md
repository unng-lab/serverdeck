# Monitoring contract v1

## Application boundary

No new external API/MCP. MonitoringOwner receives AppOperations, UiActor,
ConnectionOwner monitoring port, monotonic/UTC clock, timer scheduler and
startupAutoAllowed. setActive(bool), startExplicitly(), Listenable changes and
snapshot(profileId) drive UI. RuntimeCapability stops admission, cancels/drains
owned work idempotently. Explicit start opens global gate, не clears manualStop
or attempted marks; UI explicit connect remains possible via 003.

Reconcile at activation and 1s tick, one async reconcile at a time, epoch fenced.
Lists all profiles and canonical ConnectionViews; prunes deleted states. Existing
connecting/prompt attempts occupy auto capacity; only auto admissions guaranteed
≤4. Mark attempted before async connect; returned response is admission, slot
held until connected/terminal, including prompt wait. Canonical ConnectionOwner.generation(profileId)>0 marks attempted regardless of
observed state, even disconnected and even if the entire UI/MCP attempt completed
between ticks. The generation survives endpoint/credential revisions for a still
existing profile during this runtime; only deletion prunes it. Retained
attemptId/sessionId also marks attempted. Before auto connect recheck generation
and live state at admission, not only an earlier async snapshot, so a concurrent
manual/MCP attempt is not overridden. UI/MCP cancellation/failure never auto retries.
MonitoringConnectionPort.connectForMonitoring(UiActor,profileId,expectedRevision,
cancellation) returns MonitoringConnectResult(operation,cancelledBeforeAdmission)
and delegates to the same canonical connect implementation. The immutable receipt
sets cancelledBeforeAdmission ONLY when its gate cancellation guard actually
rejects the inactive lease; later cancellation cannot relabel a completed failure,
even when the canonical generation is still0. Queue/capacity/version failures
remain terminal auto attempts until explicit connect. Inside its
gate effect it requires generation==0 and a still-live activation cancellation
lease. Ordinary explicit connect does not require generation==0. This is internal
only, absent from AppOperations/MCP. A cancelled, not-yet-admitted attempt with
canonical generation==0 returns to the queue on reactivation; completed failures
or manual operations do not. Fresh profile revision read before auto connect. Active false never launches.
New profiles while inactive included on return. RESOURCE_EXHAUSTED from 64-live
SSH limit is safe unavailable and requires explicit retry.

Four collection workers separate from auto slots; one request per profile,
round-robin rotation, initial due immediately then dueAt=start+5s. No backlog.
ConnectionOwner exposes internal beginMonitoring(UiActor, profileId, sessionId,
expectedConnectionRevision, cancellation) → MonitoringJob(result,cancel).
The result is LinuxSample with normalized counters/percentages/fixed reasons,
never raw stdout. The optional transport capability takes only cancellation and
remaining timeout; the collector command is compiled into its implementation.
Owner additionally bounds admitted/unresolved jobs to four globally and one per
profile. Caller cancellation/deadline completes its result promptly; jobs still
waiting on gate/adapter cleanup retain admission slots until their underlying
work finishes, preventing unbounded late work. The owner's5s timer starts before
gate admission; transport receives only the remaining budget. Entry invalidation
cancels the child; runtime stop cancels jobs and drains tracked continuations. Admission and response under DomainCommandGate,
_check(auth:true), exact session/generation/connection+credential revisions,
quarantine/trust plus UiActor and CURRENT canonical OwnerActor session authorization.
Established sessions were promoted to application ownership under 003: never
retain/revalidate the initiating MCP grant for monitoring, and grant revocation
after promotion does not stop UI metrics. Pending attempts still use the original
actor under 003 and cannot continue after its revocation before promotion. All writes
retain existing admitWrite linearization. No raw output reaches UI/MCP.
Transport optional MonitoringSshConnection interface; no unsafe fallback.

## Constant command and grammar

One constant POSIX shell exec, no PTY/X11/env request/stdin/user interpolation.
Set LC_ALL=C. Commands uname -s, cat /proc/stat, cat /proc/meminfo, df -Pk /;
shell read/case selects only aggregate cpu and MemTotal/MemAvailable lines so
output independent of core count. Redirect command stderr to /dev/null. Emit:

```text
SDM1
OS
Linux
CPU
<aggregate cpu line or empty>
MEM
<MemTotal and MemAvailable lines or empty>
DISK
<df -Pk / output or empty>
END
```

Markers exact once/in order. Nonempty OS≠Linux → unsupportedSession, need not read sources.
Empty OS (uname unavailable/failure) → sourceUnavailable, retried next cycle;
absence of detection is not proof of a permanently unsupported OS.
Command failure does not suppress later markers. UTF-8 strict, LF/CRLF accepted,
line≤4096 bytes, total stdout+stderr≤65536. Invalid framing/encoding/control chars
(except tab/line endings), nonzero/missing exit status → fixed invalidResponse.
No received text in errors/logs. Empty source section → sourceUnavailable.

Numbers ASCII unsigned base10≤2^63−1. CPU requires ≥8 counters; sum first eight,
idle+iowait unbusy, guest fields ignored. Any decrement/zero total delta invalid;
reset baseline. RAM exact keys/kB units, duplicates invalid, total>0,
0≤available≤total. df header ignored; exactly one data row ending mount `/`,
parse final five fields blocks/used/available/capacity/mount, ignore filesystem
label. Validate numeric fields/capacity token; used,available≥0, sum>0; use
used/(used+available). Multiple/wrapped rows invalid disk. Per-metric invalidity
retains other valid readings. Percent must finite 0..100.

## Bounded transport extension

Vendor startBoundedExec returns synchronous handle with result/cancel before any
await. It owns pending open, exec ACK, receive buffer and channel. Deadline 5s
starts before open. Register metadata before CHANNEL_OPEN send; budget configured
before confirmation (data can follow in same input). Initial window≤65536,
max packet≤32768. Cumulative hook in channel data admission before stream buffer
counts stdout and every extended data kind; crossing packet not retained.
Retain bounded stdout only, stderr counted/discarded. Consumer before exec send.
No run/join or Future.timeout without actual cancellation.

At most ONE unresolved opening/open/retired monitoring channel per SSH session.
Cancel locally completes collection, destroys channel/subscriptions, suppresses
further exec/window grants and reply queues. Global worker releases after local
cleanup; protocol slot retained until peer CLOSE/open-failure or transport close.
Cancelled pending open retains tombstone/ID; late confirmation sends close without
exec, never reuses ID prematurely. Later collections report cleanupPending without
allocating channels until retired slot freed. Retired data discarded without
window replenishment; bounded retained channel count≤64 (existing live SSH limit).
Explicit reconnect recovers permanently silent peer. Exit closes transport as in
003. Hide preserves SSH. Remote process termination cannot be guaranteed by close;
collector runs only finite read-only commands, no new unresolved local overlap.
Vendor patch/provenance maintained in patches/dartssh2-4.1.0-policy.patch,
third_party/dartssh2/SERVERDECK.md and existing provenance metadata.

## Runtime marker

monitoring.beginRun on serverdeck/platform.v1 uses same ownerEpoch gate, accepts
no paths/arguments. Secure dataRoot/data under owner lock, RejectReparse target,
bounded native read≤128 bytes, distinguish missing vs I/O; exact payloads from
[data model](../data-model.md). Cache previous classification once per owner epoch.
AtomicFile running before returning {autoAllowed:bool}; missing/clean permit auto;
all other previous states block auto. Running write failure fixed STORAGE_IO and
no monitoring admission until retry succeeds. Explicit start does not waive need
for durable running publication. First missing marker supports upgrade/new install.
Validated runtime.finishExit writes clean after shutdownComplete+activationClosed+
exitRequested checks; failed write preserves shutdown-blocked. No generic arbitrary
path file API, no Isar migration or release asset.

## Activation and presentation

RuntimeView tracks FoundationShell.onSectionChanged, runtime.window and state.
Active iff servers selected, not trayHidden and acceptsOperations. Minimize alone
retains monitoring. Late reconcile cannot launch after deactivation. FeatureRuntime
owns monitor beyond widget lifetime so manual-stop marks survive screen rebuilds.

C21 metric label CPU/RAM/Диск /, one decimal percent; `<90,0` for rounding across
threshold. Only fresh≥90 error tone with «Порог достигнут: CPU ≥ 90%» (or RAM/Диск /).
Fresh normal «Актуально», stale «Устарело», missing value null; old invalid sample
«Устарело: данные недоступны». C18 per-metric last successful local date/time.
C10 aggregate critical/partial/waiting/paused independent; preserve trust warnings.
C11 safe reason and next action. Per-source failures each have a notice titled
with the metric name, preserving every distinct cause/action even when multiple
sources fail together; whole-collection/connection failures use a global notice.
Waiting trust/passphrase row is selectable and
opens existing 003 detail controls. startExplicitly via C02 after crash gate.

Fixed reasons: waiting, baseline, unsupportedOs, sourceUnavailable, invalidResponse,
timeout, outputLimit, disconnected, paused, stopped, cleanupPending. Next actions
fixed: await, reconnect, check permissions/tools/proc, return to screen, explicit
start. Не показывать raw SSH exceptions и данные сервера в error texts.


## Scheduler implementation boundaries

One MonitoringOwner capability in FeatureRuntime; UI observes Listenable projections.
MonitoringConnectionPort is the existing ConnectionOwner, not a second SSH graph.
Startup gate suppresses automatic connect AND scheduled collection until explicit
start; explicit003 connect remains available. Inactive owner stops its1s timer,
cancels queued auto admission leases and collections, preserves established SSH,
marks cached readings stale and clears CPU baseline. Resume needs a new CPU pair.
Unsupported-OS classification remains sticky only for that session, including
pause/resume; reconnect clears it. Snapshot checks canonical session synchronously
before publishing cached data, even before async reconciliation catches up.
Active collection work uses FIFO round-robin rotation; canceled work retains slots
until its local future completes. Reconcile is coalesced and epoch-fenced;
profiles bounded1000, pagination bounded/repeated cursors rejected safely.


Transient inactivity masks snapshot status as paused while inactive but does not
overwrite a stored server failure/disconnected reason. Cached readings still become
stale and CPU baseline clears; on activation canonical disconnected/failed state
is restored without leaving a permanent paused next-action on an active screen.
