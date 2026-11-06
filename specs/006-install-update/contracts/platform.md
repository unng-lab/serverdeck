# Update platform / UI v1

Owner-only extension of epoch-checked `serverdeck/platform.v1`, no MCP tools:

| Method | Args besides ownerEpoch | Result |
| --- | --- | --- |
| updates.snapshot | none | Snapshot map |
| updates.check | none | accepted bool, background work |
| updates.download | version canonical | accepted bool, current verified offer only |
| updates.cancel | none | ack, cancels check/download only |
| updates.setEnabled | enabled bool | ack after atomic preference write |
| updates.defer | none | ack, suppress until next scheduled attempt |
| updates.stopAdmission | none | ack, latch no new native update work |
| updates.drained | none | bool, worker terminated and joined; nonblocking poll |

Reject unknown/extra args and stale epoch; no arbitrary URL/path/shell. During
shutdown reject new check/download/preferences/defer; same-epoch snapshot/cancel/
stopAdmission/drained remain available for cleanup. Housekeeping without an existing
service does not create it or touch storage/network. Stopped snapshot without a
service returns current build version and failed/CANCELLED. Stop is idempotent,
latched even before lazy creation; drained uses TryDrain without blocking GUI.
Only one command; repeats BUSY. Snapshot: state idle/checking/current/available/
downloading/verifying/ready/failed; currentVersion, targetVersion?, notes?, bytes,
total?, code?, enabled, lastAttempt?, lastSuccess?. Offer additionally includes
`publishedUTC` (signed UTC seconds), `setupSize` (signed exact positive bytes),
`platform` (windows-x64), `bootstrapAbi` (1), `storeFormat` (build-supported format),
and `compatibility` (compatible/incompatible) with bounded `compatibilityReason`.
These offer fields are mandatory in available/downloading/verifying/ready; unavailable
before a verified offer, never synthesized from download counters. `total?` is only
the observed download Content-Length, not the source of displayed signed setup size.
An incompatible candidate is shown only as failure details, without enabled download;
it is not an available/ready offer. Int64 nonnegative counters,
bounded allowlisted error codes, no raw response body or secret paths.
`preparedVersion?` identifies an already-published pending update independently of
the current check/download offer. `preparedCode?` is its latest validation failure
(revoked/changed/incompatible/network/storage), absent when last validated usable.
Checking for a newer release or cancelling its replacement never silently hides or
deletes the prior consent. If the newest offer is that same unchanged prepared release,
report ready; otherwise show the new available offer plus the retained prepared version.
Failed fresh checks preserve its bytes and report the reason; they do not prove current.
Restore runs on a worker with state checking until its full persisted set is verified.
Targets≤installed never restore as ready; bootstrap consumption/cleanup remains authoritative.
The installed native service receives the bootstrap-verified installation identity
for same-version byte-conflict checks; source-only/developer fixtures may omit it.
Cancel acknowledgement confirms receipt, not a cancelled result: an already-published
ready update wins. UI never projects CANCELLED optimistically; it keeps the last phase
until an authoritative snapshot confirms cancelled/ready/failure, including read errors.

Native service serializes worker/cancel/pending/preference IO; network never on window
thread. Snapshot under mutex; generation fences late/cancelled work. Cancellation
safely closes owned request handles; stopAdmission blocks commands, cancelPending
interrupts request, drain joins worker before native destruction. Runtime remains owner
of shutdown, not updater. Native test ports substitute network/file/process/time.

Dart UpdateOwner owns scheduling/polling and RuntimeCapability lifecycle. Start after
runtime accepts operations; initial/scheduled attempts only if enabled, at most once
per24h persisted lastAttempt. `enabled` restricts automatic checks ONLY: manual
`updates.check` is allowed even when enabled=false, bypasses the24h interval and
leaves enabled=false unchanged. Future timestamp
after clock rollback waits manual or24h monotonic elapsed in running process. Poll500ms
only active stages; retire cancels timers and rejects late replies. Snapshot restores
pending readiness. Disabling cancels background check/timers, not user-confirmed download.
NativeUpdatePort implements UpdateLifecyclePort; owner stop closes local timers and
admission immediately, then native admission. Cancel remains available; drain waits
outstanding Dart calls and polls native drained every25ms. Coordinator's existing10s
shutdown budget/retry retains owner authority when draining is incomplete. No forced
worker termination or early release. Retry of a failed native stop is permitted.
FeatureRuntime registers the update capability before startup; RuntimeView starts
it only after acceptsOperations, including storage-retry transitions, independent
of selected server or settings visibility. Tray hiding does not retire scheduling.

UI «Обновления» is global, reachable without selected server; uses OwnedSettingsRoute
and preserves monitoring/settings lifecycle. C02/C04/C10/C11/C12/C14/C18/C23/C27/C28;
ApplicationSettingsView switches between updates and MCP with shared DeckTabs;
both use the same OwnedSettingsRoute/nested Navigator. Retirement closes every
confirmation prompt, including when runtime/feature/update owner changes.
current version always visible. Offer shows target/notes/signed setupSize, publication
date through C28, platform and explicit compatibility details (ABI/storeFormat) through
C18. C14 before download
explicitly authorizes exact release apply next launch after user tray exit. Ready
instructs tray exit, no direct quit/restart callback. Test texts/data/enabled callbacks,
not layout/design. Native installer uses OS confirmation/error dialogs before Flutter.

Codes: UPDATE_NOT_CONFIGURED, NETWORK_UNAVAILABLE, TIMEOUT, CANCELLED, SOURCE_UNTRUSTED,
SOURCE_EXPIRED, SOURCE_CHANGED, RELEASE_REVOKED, RELEASE_INCOMPATIBLE, INVALID_CATALOG,
INVALID_ARTIFACT, DISK_SPACE, OWNER_RUNNING, BUSY, STORAGE_IO, RECOVERY_REQUIRED,
UNINSTALL_PARTIAL. Every failure preserves working old owner/data and distinguishes
failure from proved current version. No error replaces data with an empty database.


## Main-window installed version — FR-620

Existing native initialize.release contains the canonical version of the running
build (including +build); its value is independent of database and GitHub state.
RuntimePlatform exposes release as ValueListenable<String?> with read-only nullable
value. NativePlatform publishes it immediately after initialize context arrives,
before monitoring/data/feature initialization completes. RuntimeView uses
ValueListenableBuilder so an unfinished store.open cannot delay the known version.
NativePlatform reads it from
its initialized local PlatformContext; before initialize, or if release is missing/
empty, it returns null. Missing initialize.release must not invent fallback0.1.0.
Fake RuntimePlatform supplies synthetic release for functional units.

RuntimeView composes existing C18 DeckKeyValue(label=«Версия ServerDeck»,
value=release or «Не определена») with existing C10 status inside C17 status slot.
It passes the same widget to normal profile workspace or readiness/error shell.
No shared component API/theme/catalog change, no layout tests in feature scope.
Source is runtime.platform.release, never update offer/prepared/snapshot version.
Each rebuild/rebinding subscribes to current runtime metadata and detaches the old
ValueListenable through the builder lifecycle; no extra native calls, network, timers,
DB open or separate stored setting. Null/empty is a truthful temporary unknown state.
Settings keep their existing signed/native current-version display; backend uses
one build metadata source. Native wire methods/epoch/authorization unchanged.
