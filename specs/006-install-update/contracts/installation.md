# Installation / maintenance v1

## Artifacts and paths

Public: full `ServerDeckSetup.exe`. RCDATA `SERVERDECK_APPLICATION_V1` contains final
application bytes; `SERVERDECK_SETUP_V1` is `SDSETUP001\n<version>\n<size>\n<sha256>\n`.
Both x64/asInvoker `/MT`; bootstrap OS imports only. Runtime resource remains
[002 packaging](../../002-desktop-runtime/contracts/packaging.md).

Known Folders determine roots, not CWD or untrusted argv/environment:

- install: `FOLDERID_LocalAppData/Programs/ServerDeck`;
- application: `install/ServerDeck.exe`, stable UI/MCP path;
- metadata/journal: `installation.v1`, `journal.v1` under install;
- durable commit proof: `install/commit.v1`, `SDCOMMIT001\n<UUIDv4>\n<SHA256 of canonical installation.v1 bytes>\n`, ≤8KiB;
- candidate/backup: `ServerDeck.new`, `ServerDeck.previous` under install;
- retained setup: `install/ServerDeckSetup.exe` for uninstall, no business owner/service;
- independent recovery image: `install/recovery/ServerDeckSetup.exe` with
  `install/recovery/recovery.v1`, not modified during application/setup replacement;
- pending: `install/pending/consent.v1` selects exactly one of two fixed
  `install/pending/slot{0,1}/{ServerDeckSetup.exe,catalog.v1,owner.v1}` sets;
- data: existing `FOLDERID_LocalAppData/ServerDeck`, unchanged;
- authority: `data/{maintenance.lock,owner.lock}` exclusive HANDLEs, retained;
- preferences: `data/update-preferences.v1`, retained settings;
- shortcut: `FOLDERID_Programs/ServerDeck.lnk`;
- recovery shortcut: `FOLDERID_Programs/ServerDeck — восстановление.lnk` points to
  the independent recovery image with fixed `--repair`;
- HKCU: `Software/Microsoft/Windows/CurrentVersion/Uninstall/ServerDeck`.

Registry: DisplayName/Publisher=ServerDeck; DisplayVersion canonical; InstallLocation
fixed root; DisplayIcon quoted app; UninstallString quoted retained setup + `--uninstall`;
NoModify/NoRepair=DWORD1. No HKLM/PATH/startup/desktop/external MCP config writes.
Reject reparse ancestors, unknown marker/SID; never remove unlisted files.
Each setup/app≤1GiB; metadata/journal≤8KiB. Free space before mutation must cover
candidate+old backup+retained setup+recovery setup+64MiB. Hash and length verified against bytes.

## Entry points and lifecycle

Setup without args confirms target/version/shortcut/registration before mutation.
Cancel makes no install changes. Equal version repairs registration without duplicates;
lower refuses downgrade. Newer user-selected full setup may explicitly update offline
with no owner: this is manual distribution trust boundary, not stale pending consent.

Setup `--uninstall` shows confirmation, copies own verified image into
`FOLDERID_LocalAppData/Temp/ServerDeck-maintenance/<UUID>/ServerDeckSetup.exe`.
Temp child uses deterministic install root; no target path accepted in argv. Temp image
may remain for ordinary OS temp cleanup (FR-614); no persistent process/service/task.
Partial deletion retains retry command to marked helper and original uninstall registration
until completion. The helper never opens runtime/DB or kills an owner.

`--apply-pending`: only the fixed slot selected by verified pending consent; fresh revalidation
per [releases](releases.md). Unknown/extra args fail closed. Internal inherited handle
arguments are numeric HANDLEs, never PID authority; validate type/process identity.
No arbitrary source/target path or URL. Readiness ack≤3s, parent termination wait≤10s;
timeout leaves complete old installation and pending state, no force termination.

GUI startup, before ExtractPayload/LoadLibrary/store-open, checks pending. With existing
owner perform normal activation and no apply; MCP stdio never applies/starts owner.
With free owner, verified pending setup receives leases, acknowledges readiness, waits
bootstrap termination, applies, launches canonical app. Bootstrap exits before opening
UI/DB, so it is startup handoff, not alternative tray exit. Failed handoff runs old app
with deferred/error status; unknown partial file state blocks runtime pending recovery.

Internal startup boundary: Executor::PrepareStartup requires maintenance+owner leases,
validates/reclaims only owned staging, recovers journal, verifies canonical bytes,
installation/commit binding and retained setup resources. Missing installation,
damaged bytes/proof, unknown staging or bad resources refuse startup. It does not
publish GUI owner, open data, or spawn a process. Only after verification and any
pending decision does AcquireOwnerFromLease transfer the exact already-held owner
HANDLE into GUI OwnerLease; maintenance remains held until caller releases it.
This internal transfer accepts a validated Lease, not raw inherited argv HANDLEs.
ActivateOwner is activation-only: disappearance of a previous owner is an error/retry,
not permission to skip maintenance/preflight and silently acquire new authority.
Wiring these boundaries into bootstrap and external helper handoff remains T018.

## Serialization / handoff

All launches/setup/uninstall acquire maintenance then owner. GUI releases maintenance
after taking normal owner lease. Mutations keep both leases through commit. If owner
held by another logon, mutation returns OWNER_RUNNING, instructs tray exit, never kills.
Download may run during owner activity into separate staging; pending publication is atomic.

CreateProcess STARTUPINFOEX with explicit HANDLE_LIST inherits only maintenance/owner
lease copies, synchronizable parent process handle, readiness and parent-permit events. Child validates
roots/mode and inherited leases before ack; parent drops its copies only after ack.
No lease gap. Failed spawn/ack keeps parent leases and complete old version. Helper
does not publish owner descriptor; only actual GUI owner does so. New launcher waits
bounded3s for maintenance lock, then visible BUSY/retry rather than another owner.

Apply helper argv is exactly `--apply-pending --maintenance-handle N --owner-handle N
--parent-handle N --ready-handle N --permit-handle N`; five unique nonzero canonical unsigned decimal
pointer-width values, no pseudohandles, extra/reordered/unknown arguments or paths.
Parent duplicates only those five objects as inheritable, never changes inheritance
on original lease handles, and passes STARTUPINFOEX/HANDLE_LIST with bInheritHandles.
Child validates regular zero-length File objects with read/write/WRITE_DAC/synchronize
rights, exact final lock paths/no reparse, and exclusive sharing. Lease::Adopt validates
these properties before storing the inherited leases. Readiness must be an unsignaled
Event with modify/synchronize access. Inheritance is cleared on accepted child handles.
Exclusive proof separately requests FILE_READ_DATA, FILE_WRITE_DATA and DELETE
through ReOpenFile on the exact inherited file object with fully permissive sharing;
each must fail with sharing violation. Other failures are not proof, and success
in any dimension rejects the handle before adoption/ack. No pathname-based probe
or combined-RW shortcut may substitute for these checks.

The parent is a live synchronizable Process with query-limited rights, canonical
installed ServerDeck.exe path, same user/logon SID and actual child-parent relationship;
creation times reject a recycled parent PID. PID alone is never authority.
NtQueryObject is dynamically resolved from system ntdll for type/granted access;
unavailable/failed queries refuse transfer, without a weaker fallback.
Parent sets the separate permit only after ready (≤3s) and a live child check,
then exits. Child receives exactly SYNCHRONIZE rights to permit, no modify/DACL
rights, and CompareObjectHandles must prove it is not an alias of the writable
ready Event. After acknowledging readiness, child first waits permit-or-parent-exit
(≤3s); missing permit or parent exit without permit forbids mutation even when the
parent later exits from its fallback GUI. It then waits parent termination (≤10s) before any
mutation. No timeout kills a process or drops parent's original leases. A helper
already exited when readiness is observed is a failed handoff. Canonical post-service
launch uses the fixed app path, no arguments and no inherited handles.
Process creation/wait ports use synthetic unit responses, not spawned test processes.
The earlier four-handle prototype in T060 history is superseded before release;
its argv is rejected, without a permissive compatibility path.

API references: [NtQueryObject](https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryobject),
[HANDLE_LIST](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute).

## Bootstrap / helper entry orchestration

GUI starts only from the fixed installed app path. It acquires maintenance→owner;
OWNER_RUNNING invokes activation-only and never applies pending. MCP stdio remains
an owner client and never enters this path. Executor::PrepareStartup verifies/recoveries
canonical installation before any owner descriptor, extraction, host load or data-open.
PrepareGuiStartup then reconciles retired targets, consumes matching deferOnce with
an invocation latch allocated outside the retry loop, and attempts the verified fixed
slot handoff. Failed spawn/ACK records and consumes bounded deferral and runs the old
verified GUI; successful handoff returns from bootstrap without entering host.

The app embeds `SERVERDECK_BUILD_V1` RCDATA, exact ASCII
`SDBUILD001\n<canonical version>\n`, ≤128bytes, LF only. CMake receives the pubspec
version from build-release and emits it with UNIX newlines; prepare/audit require
this resource to equal setup's version. Bootstrap compares its mapped resource with
the verified installed version after recovery. Mismatch relaunches the fixed canonical
app only after confirming that file's resource matches its installation record; no
old mapped payload is extracted. Leases are released after completed recovery before
this normal non-inheriting relaunch; another normal launcher may safely win ownership.

Before ACK, helper verifies inherited objects/creator and bounded slot consent+owner
metadata, including own fixed module path. Parent already verified all selected bytes
under the same continuously held leases. Heavy resource/file checks are repeated only
after permit and parent exit, keeping the readiness phase independent of artifact size.
After parent exit helper validates its own full setup and file identity, complete old
installation, original pending signature and installed app's embedded GitHub policy;
expected full consent must still match. Fresh FetchFor/Revalidate is mandatory before
Executor::Apply. Commit/retirement finish before fixed canonical relaunch. Source,
resource or apply failures relaunch only after proving a complete old installation
and recording deferOnce; unknown partial canonical state blocks relaunch for recovery.
Already committed target is never rolled back because cache cleanup failed.

Corrupt optional pending cache may disable updates but must not brick a verified
complete canonical installation: PrepareGuiStartup latches no apply for that invocation
and permits host startup, preserving unknown bytes. Persistence APIs still report the
cache error and refuse deletion; the live service reports failed restore when applicable.
Unresolved install journal/staging/canonical corruption remains outside this catch and
blocks host/data. A developer build with absent policy retires old owned targets but
leaves a future target untouched, starts the GUI with UPDATE_NOT_CONFIGURED and never
spawns a helper or contacts a source.

## Transaction / recovery

Atomic record/artifact writes use one bounded reserved staging slot in install root:
`.stage.lock` (exclusive HANDLE), `.stage-owner.v1`, `.stage.bin` (≤1GiB, or smaller
record limit). No UUID-named persistent siblings or wildcard deletion. Owner codec is
`SDSTAGE001` header + JSON `{id:UUIDv4,sid,target,size}` + LF, ≤8KiB. Target is from
the exact artifact/record allowlist, SID equals current roots, size within its limit.
Flush owner record BEFORE creating payload; hold slot lease through publication/cleanup.
This nested lock is acquired after any maintenance/owner leases, never in reverse.

Before each atomic write and during recovery/uninstall, under slot lease, reclaim
only a valid matching owner and its regular non-reparse payload of size≤recorded size.
Then remove owner. A missing/invalid/foreign owner, oversized payload or reparse object
causes RECOVERY_REQUIRED without deletion of unknown bytes; interrupted partial marker
is bounded and reported explicitly, not silently treated as an empty slot. Unlisted
files including arbitrary *.tmp are untouched. Exception cleanup retains owner if its
payload cannot be removed. Uninstall removes slot lock after releasing its HANDLE;
caller still holds maintenance/owner leases. These reserved three names are manifest-
owned maintenance elements, not a second application or user-data store.

## Pending publication binding

Two fixed slots preserve an already-ready update while a replacement downloads.
Only the GUI owner may prepare a download; it drains its worker before releasing
owner authority. Bootstrap/setup never start a second downloader. Select the inactive
slot under maintenance, reclaim only its verified owner-described files, then release
maintenance before streaming. A separate reserved `.download.lock/.download-owner.v1/
.download.bin` slot uses the same SDSTAGE001 bounds/ownership rules as `.stage`, but
its only targets are the two fixed pending setup files. Preference and short record
writes remain independent through `.stage`. Release the download lock before acquiring
maintenance for publication; no lock-order reversal and no long network maintenance lease.

Each slot owner and the active consent use the same bounded `SDPENDING001` header +
JSON + LF codec, ≤8192bytes. Exact fields: `id` UUIDv4, `sid`, `slot` integer0/1,
`version`, `appSize`, `appHash`, `setupSize`, `setupHash`, `catalogHash` (SHA256 of
the exact original signed envelope), `verifiedAt` nonnegative Int64 UTC seconds.
Unknown/duplicate/missing fields fail closed. The full Release, including URL/notes/
publication/compatibility, is reconstructed from that exact signed catalog and version;
its app/setup identities must match consent. Verify the original signature and its
validity at verifiedAt; fresh current-time network validation is still mandatory at apply.
This historical verification does not grant offline apply freshness.
The ready-commit gate invokes its atomic pointer write synchronously exactly once.
That write notifies the gate immediately after the durable rename, before fallible
staging-marker cleanup. The service marks committed/ready at that notification under
the same generation/cancellation mutex. A later cleanup exception cannot permit a
false cancel acknowledgement or leave a published pointer displayed as verifying.

Persist slot owner before writing its setup or catalog. Stream to the inactive slot
with create-only publication (an unexpected target appearing during download is never
overwritten),
verify exact setup size/hash and embedded manifest/policy, write the exact catalog,
then reacquire maintenance. Re-read the previously selected active consent; if changed,
refuse publication. Reverify the candidate and atomically publish consent last. This
single pointer write is the ready linearization point. Interrupted preparation leaves
the complete previous active slot unchanged; interruption after the pointer switch
leaves the complete new active slot. Do not erase the old slot in the commit path.

Readers of persisted pending files hold maintenance while selecting/verifying a slot;
these potentially large reads run on a worker or bootstrap before host, never the window
thread. Slot cleanup also holds maintenance and never touches the currently selected
slot. Missing files in an inactive owner-described preparation may be reclaimed; existing
files must match their recorded identities (catalog≤128KiB/setup≤1GiB), with no reparse.
Unknown/corrupt ownership or mismatched bytes refuse deletion. A mapped retired helper
may delay cleanup without invalidating active readiness. Uninstall enumerates both fixed
slots and the download staging elements. Two slots bound retained pending storage to
two setups and two catalogs; admission for a new candidate remains setupSize+64MiB.

Before the first destructive replacement, create and flush an independently launchable
full recovery setup and its metadata/shortcut. `recovery.v1` codec:
`SDRECOVERY001\n<userSID>\n<setupVersion>\n<setupSize>\n<setupSha256>\n` (≤8KiB).
Bytes must match the verified current retained setup, or the explicitly confirmed
full installer on first install; validate embedded manifest/policy as well. This is
the same initial-installer trust boundary, not trust granted by a filename. Refuse
mutation if the recovery image or shortcut cannot be prepared/verified.

Keep this recovery image unchanged from prepared journal through commit/rollback.
The two application/retained-setup files are replaced sequentially, never together;
the independent recovery image is not a replacement target during this interval.
Its refresh is allowed only with verified complete canonical app+retained setup and
no active transaction. Thus interruption during recovery refresh leaves normal startup
available; interruption losing canonical/retained setup leaves recovery available.

User invokes «ServerDeck — восстановление» even if canonical app is absent.
`--repair` confirms recovery, acquires maintenance→owner leases, verifies SID/reparse,
recovery image hash/embedded manifest/policy and journal candidates, and runs journal
recovery BEFORE ordinary installed-marker/version comparison or fresh-install logic.
It may restore verified backup or complete the exact journaled new version, never
install its own older embedded version just because it is the recovery executable.
If a full matching candidate cannot be established, show RECOVERY_REQUIRED with
option to obtain a fresh trusted full installer; no host/DB, false success or empty state.
Original downloaded full setup also supports this same explicit --repair path.
No running owner is terminated; a live owner produces tray-exit instruction.

Recover journal before mutation. Validate old marker/hash and prepare independent
recovery. Persist prepared journal before candidate/backup creation; stage+flush the
candidate and verified backup. Replace canonical in one same-volume
ReplaceFileW; fresh install uses MoveFileExW WRITE_THROUGH. Never rename canonical
away before replacement. Publish retained setup, persist files-stage journal (retain
old installation metadata until final commit), then shortcut/HKCU idempotently.
After verifying all required values/links, persist registered stage; write final
installation metadata and its commit proof before host. Cleanup backup/candidates,
then journal last. Equal-version repair journals registration too, without replacing
application/setup bytes. One-shot registration errors may reconcile to a verified
complete old OR new installation; the returned success must match the resulting state.
Registration failure restores old complete files+marker+registration, or removes
incomplete fresh install. Retained old setup backed up too until transaction commits.

Registered journal stage is an irreversible commit-intent barrier: after it, recovery
may repair required registration and finish the exact new metadata/commit proof, but
never downgrade files to previous version. Matching commit proof independently has
the same effect, even if cleanup was interrupted. Missing/corrupt new bytes in this
state produce RECOVERY_REQUIRED, not automatic data/executable rollback. A normal
host may open only with no unresolved journal and verified metadata+commit proof.

Partial registry/shortcut writes are replayed idempotently. Before beginning, reject
foreign InstallLocation or foreign pre-existing links. A validated same-SID journal
authorizes restoring the fixed registration elements created by that transaction;
validated recovery SID/size/hash evidence permits repairing its partially saved
recovery shortcut before the main journal exists. This never authorizes arbitrary
files/keys/targets. Already-correct recovery links are not rewritten unnecessarily.

ReplaceFile failure may change names: classify actual current/candidate/backup hashes,
including errors1175/1176/1177. Next startup/setup commits only when complete new
files/registration match; otherwise restores verified old backup before host. No
complete matching candidate → RECOVERY_REQUIRED, no runtime/DB. Do not promise
power-loss guarantees beyond flushed same-volume OS file operations.
Commit marker persisted before first new host; later DB error never triggers automatic
executable rollback/migration/reset. Old backup only repairs unfinished file replacement.

## Pending consumption / restart boundary

Installation commit metadata includes `consumedPendingVersion` and
`consumedPendingSetupSha256` (both absent for an unrelated install). After new files
and registration are verified, atomically flush installation metadata with this exact
consumed identity BEFORE removing journal and BEFORE launching canonical app/host.
Journal registered stage records the same identity, so recovery can finish consumption
idempotently if interrupted between registration, metadata commit and journal cleanup.
Do not roll back a committed installation just because pending cleanup failed.

At every bootstrap, after journal recovery and verified installed marker, a pending
version≤installed is never eligible for another handoff/network check. Equal version
with matching setup hash is consumed; same version with different hash is SOURCE_CHANGED
and non-applicable. Older pending is superseded by the newer verified installed version,
including successful offline manual installation. Mark superseded/consumed durably
before cleanup. Snapshot then reports installed current version, not stale ready offer.
An unsuccessful mutation/restored old version does not consume consent; preserve pending
for a future explicit ordinary application launch or download cancellation/replacement.

Helper executes from pending; it cannot reliably delete its own mapped setup image.
On commit remove/retire only exact consent/catalog identity under maintenance lease;
cleanup of setup image may fail with sharing violation while helper still lives.
Retain a consumed tombstone (version+hash) until a later bootstrap/setup can delete
that exact old file after helper exit. Never delete a newer pending file by directory
name alone. Pending publication and cleanup serialize on maintenance lease; cleanup
checks recorded identity and actual file hash. Leftover consumed bytes are not an
applicable update or a partial install; their cleanup failure cannot restart apply.

On failed fresh revalidation/apply that retains old installation, helper persists
`deferOnce` with attempt UUID/error and launches old canonical app. Its next bootstrap
atomically consumes deferOnce and skips pending for that entire invocation, including
startup retries. Thus offline/error fallback cannot loop through the same helper.
Pending consent remains for the next user-initiated ordinary launch. Interrupted helper
or missing parent acknowledgment never creates a second owner or consumes consent.

## Pending lifecycle record codecs

Both records are canonical UTF8 ASCII JSON envelopes with final LF, ≤8192bytes;
unknown/duplicate/missing fields, alternate encoding, invalid SID/UUID/version/hash
or unknown reason/code fail closed. Embedded `consent` is the complete exact canonical
SDPENDING001 record as a JSON string; it binds id, slot, SID, version, app/setup
identities, catalog hash and verifiedAt, not just the slot's pathname.

- `pending/tombstone.v1`: `SDRETIRED001\n<JSON>\n`, exact fields `consent`, `reason`.
  Reasons consumed/superseded/changed. PrepareStartup of PendingStore requires both
  leases and a verified Installation from Executor::PrepareStartup. It retires
  only target≤installed; equal identity (app/setup) consumed, lower superseded,
  equal-version differing identity changed/SOURCE_CHANGED. New retirement validates
  the exact slot owner before writing; no old signing root or surviving setup image
  is required to retire an already-installed identity.
- `pending/defer-once.v1`: `SDDEFER001\n<JSON>\n`, exact fields `consent`, `attempt`
  (UUIDv4), `code`, `consumed` (bool). Code is one existing update error from platform
  contract, excluding UNINSTALL_PARTIAL; never raw exception/response/path text.
  DeferOnce requires both leases and matching active unretired consent. Consumption
  validates SID/target and invokes an invocation-wide skip latch BEFORE fallible
  atomic record publication, then writes consumed=true. Startup retries keep the
  local skip latch; a subsequent ordinary launch may try the target again. A
  replaced/absent consent clears unrelated deferral without skipping the new target.

Retirement is durable before pointer detach or artifact cleanup. Read/Restore skips
an exact retired pointer even after interruption before detach or during cleanup;
it never requires missing retired setup bytes to present idle. Cleanup holds
maintenance and verifies owner plus existing setup/catalog hashes, ignores newer
identity at the same slot, and never deletes its pointer or bytes. Only STORAGE_IO
during cleanup is deferred; unknown ownership/corrupt metadata remains an error.
Changed retirement retains SOURCE_CHANGED notice until replacement or a newer
verified installation supersedes it. Normal consumed/superseded tombstones disappear
after exact owned artifacts are gone. Leftover slot owners remain bounded to two.

PendingPersistence::Notice is read on the same serialized worker immediately after
Restore. A matching deferral yields failed status with separately retained prepared
version/code, not false ready; it performs no network retry. A successful fresh check
may clear that startup failure. Retirement without a prepared update cannot restore
a stale ready offer. These APIs and records alone do not wire bootstrap/helper
invocation; T018/T028 still require that integration and invocation latch ownership.

## Uninstall

With both leases and no owner, helper validates marker/SID and removes only listed
application/setup/candidate/backup/pending files, shortcut and HKCU registration.
Remove only own empty directories; unlisted user files remain. Data/credentials/trust,
settings and owner.lock stay. Failures return UNINSTALL_PARTIAL with bounded relative
names/codes and retry; no success while owned install elements remain. Temporary
helper cache is explicitly excluded. Reinstall uses same data root and format preflight.
Recovery image/metadata/shortcut are manifest-owned maintenance elements and removed
by the temp uninstaller too; the executing temp image is outside this deletion scope.

### Marked helper and removal retry protocol

`--uninstall` accepts only the retained installed setup identity. After confirmation
and maintenance→owner acquisition, it recovers/validates canonical installation,
copies its verified complete setup bytes into the fixed Known Folder temp root above,
and flushes a private UUID directory's `ServerDeckSetup.exe` plus `removal.v1`.
The marker is canonical ≤8KiB `SDREMOVE001\n<JSON>\n` with exactly `id` (UUIDv4,
equal to directory name), `commitHash` (SHA256 of original commit.v1 bytes), and
`installation` (complete canonical SDINSTALL001 record encoded as a JSON string).
It binds the original installation instance, not merely version/file hashes: a
same-version reinstall has a new commit proof and refuses the stale removal ticket.
Unknown fields/alternate encoding, foreign SID, changed setup/app identity or paths
outside `<Known Folder temp root>/<UUID>/ServerDeckSetup.exe` are rejected.

Initial launch uses `--uninstall-helper` and the exact five-handle protocol above;
parent validation requires retained `install/ServerDeckSetup.exe`, same user/logon,
direct live parent and creation-time ordering. Apply mode still requires canonical
app parent. Child validates bounded ticket/path/SID before ACK, waits for permit
and parent exit, then validates full own setup resources/hash before removal.
No arbitrary source, install root, PID, or URL is accepted through the command line.
`--uninstall-retry` has no extra arguments, confirms again and acquires both leases
normally; its own fixed cache path/marker and full setup must pass the same checks.

Removal journal reuses SDJOURNAL001 kind=remove, target=previous=original installation,
id=marker UUID; a surviving exact journal authorizes resumption after partial deletion.
Before a new removal journal, installation record and original commitHash must match.
Before deleting install files, write journal then flush registration whose UninstallString
is quoted marked helper plus `--uninstall-retry`; retain DisplayName/Publisher/version,
fixed InstallLocation and NoModify/NoRepair. Setup parent can resume the same UUID
helper if a remove journal already exists. A failed retry publication prevents deletion.

Validate pending slot owners/SID and existing setup/catalog identities; unowned or
changed bytes block removal. During deletion keep a slot owner until its setup/catalog
are gone. Reclaim only existing owned bounded staging; no wildcard cleanup. Remove
payload/pending/recovery first, then maintenance metadata/shortcuts/registration, with
removal journal last. Partial failures retain journal and retry registration; known
relative failures are reported as UNINSTALL_PARTIAL. Remove only empty fixed directories;
foreign children remain. User data, locks and preferences are outside the deletion list.
No runtime/database entry, process kill, service, task or temp-image self-deletion.

Terminal interruption recovery does not rely on Windows registration surviving its
own removal. Ordinary trusted full setup (including `--repair`) checks for a remove
journal under both leases before its normal install/repair flow. It resolves only
the exact UUID marked cache, checks matching complete target/SID, physical helper
size/hash and embedded resources; after releasing leases it launches that fixed
helper with only `--uninstall-retry` and no inherited handles. The helper confirms
and reacquires both leases before resuming. This closes interruption after successful
registration removal but before journal removal. Completing removal then running
the full setup again permits ordinary reinstall; no manual Temp/journal edits.

## Update helper status before runtime

After parent permit/exit and before resource/freshness/file work, update helper opens
a native standard-control status window with its own message-loop thread. It shows
revalidation, applying and recovery stages; it does not create Flutter, a database,
SSH/MCP ownership, a fabricated percentage or a quit/restart/cancel command. Typed
MaintenanceReporter stages are recovering before canonical preflight, revalidating
before fresh source, applying only after successful revalidation and before Apply,
recovering after Apply or on failure before recovery. Native presentation keeps UI
message handling separate from blocking file/network work; stage delivery waits at
most3s. Status closes before canonical relaunch/error UI. Failure to create/deliver
status is an ordinary helper error handled through verified canonical recovery and
durable fallback, never permission to skip freshness or rollback a committed version.
Unit tests assert stage sequence/text and absence of applying on offline failure,
not window layout/pixels or product execution. Shared Flutter C23 remains the download
progress component; this pre-runtime maintenance presentation uses OS controls.

Physical canonical build-version and trust-resource reads use a read-only file mapping
with bounded x64 PE/resource traversal (file≤1GiB, sections≤96, directory entries≤256,
resource name≤128 UTF-16 units; build identity≤128 bytes, policy≤8KiB). No executable
image loading or import resolution is used: an already mapped old bootstrap cannot
substitute its cached resources for the canonical file replaced during recovery.
Ambiguous RVA mappings, duplicate selected resources, malformed trees, and multiple
resource languages fail with INVALID_ARTIFACT before canonical relaunch/apply.

## Native adapter corrections

The child binds each inherited lease HANDLE to the fixed expected lock path by
opening that path for `FILE_READ_ATTRIBUTES` with all sharing flags and comparing
`FileIdInfo` (volume serial plus the complete 128-bit file ID). Both objects must
be ordinary files, with no reparse point on the expected path. This supports
Windows packaged-desktop LocalCache redirection without accepting a different
file merely because its name, length or contents match. Required HANDLE rights,
zero length and independent exclusive read/write/delete sharing probes remain
mandatory. The attribute-only comparison handle does not acquire a second lease.
Parent process ancestry, image, user/logon and five-handle permission protocol are
unchanged. Synthetic temporary-file tests cover a hard-link alias to the same
object, different lock objects, insufficient rights and shared handles; no child
process is launched by these tests.

The HKCU string adapter bounds both the size probe and actual UTF-16 byte count
returned by the value read. It resizes to that actual count before checking and
removing the terminal NUL; an oversized probe is not part of the value. Odd,
zero, oversized or grown counts, read errors, missing terminators and embedded
NULs still fail closed. Regression units inject the read callback, without using
the real registry.
