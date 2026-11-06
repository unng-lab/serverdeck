# Data model v1

Служебные записи не входят в Isar и не меняют logicalFormat.

| Entity | Fields and constraints | Owner |
| --- | --- | --- |
| BuildPolicy | schema1, HTTPS endpoint, hosts≤8, built-in P256 keys≤3, current storeFormat | immutable build resources |
| Release | canonical version, platform, abi, storeFormat, publishedUTC, setup/app sizes+SHA256, HTTPS URL, notes≤16KiB | signed catalog |
| Catalog | protocol2 production: keyId, issuedUTC, releases≤32, signature64, no expiry; protocol1 legacy retains expiresUTC | native verifier |
| Installation | SDINSTALL001, SID, version, app/setup size+hash, optional consumed pending version+setup hash | maintenance |
| Journal | SDJOURNAL001, UUID, SID, kind, stage, old/new versions+hashes+sizes | maintenance |
| Commit proof | SDCOMMIT001, transaction UUIDv4, SHA256 of canonical committed installation record; ≤8KiB | executor before host |
| Recovery | SDRECOVERY001, SID, setup version/size/hash; independently launchable full setup and repair shortcut | maintenance |
| Atomic stage | fixed .stage.lock/.stage-owner.v1/.stage.bin; SDSTAGE001 JSON id/SID/allowlisted target/size; one payload≤1GiB, marker8KiB | native file adapter |
| Pending | SDPENDING001 active consent selecting fixed slot0/1; SID/UUID/version/app+setup identities/catalog hash/verifiedAt; exact signed catalog+setup in slot, consumed/superseded tombstone; optional deferOnce attempt UUID+code | update service |
| Preferences | SDUPREF001, enabled, lastAttemptUTC, lastSuccessUTC, deferredUntilUTC | update service |
| Retirement | SDRETIRED001, exact consent string, reason consumed/superseded/changed; ≤8KiB canonical JSON | maintenance / pending store |
| Deferral | SDDEFER001, exact consent string, attempt UUIDv4, allowlisted code, consumed bool; ≤8KiB canonical JSON | helper → bootstrap, worker reads notice |
| Snapshot | state, current/target version, notes, signed setupSize/publishedUTC/platform/ABI/storeFormat/compatibility, bytes/total?, code?, enabled, timestamps, independently retained preparedVersion?/preparedCode? | native → Dart |

Versions: stable `major.minor.patch` (first `0.1.1`), three integers0..65535,
no leading zeros except0, no prerelease/build metadata. Compare numeric three-field
tuple. Windows numeric VERSIONINFO is `major,minor,patch,0`; revision0 is not part
of the release ID. `+build` is rejected in every runtime/publisher codec. This is a
clean-install cutover; old installation metadata/pending/catalogs are unsupported.
Same version with other hash/size is a trust failure, not alias. Format/ABI validated before offer, actual DB-open remains authoritative
for data corruption/unsupported format; no remote-selected migration.

```text
idle → checking → current | available | failed
available → downloading → verifying → ready | failed | cancelled
ready → applying (bootstrap without live owner) → committed | deferred | failed
```

Only one network command; generation fences cancel/retired callbacks. Snapshot is read-only.
Failure changes lastAttempt, not lastSuccess. Consent binds exact release fields/signature,
never follows new latest automatically. Journal flushed before mutation; recovery verifies
actual bytes. Corrupt/unknown record blocks runtime with explicit error, not empty state.
Committed consumption is durable before relaunch; target≤installed never reapplies.
Consumed-file cleanup is identity-bound and may finish after helper image is unmapped.
Fallback deferOnce suppresses retry for one whole bootstrap invocation, avoiding loops.

## Native persistent codecs (implementation binding)

`SDINSTALL001` / `SDJOURNAL001`: header line, one UTF8 JSON body, final LF; ≤8192bytes,
no NUL/CR, duplicate/unknown/missing fields rejected. Installation body fields `sid`,
`version`, `appSize`, `appHash`, `setupSize`, `setupHash`; optional consumed pair
`consumedVersion`/`consumedSetupHash` exists together or neither. Consumed version≤installed;
for equal version consumed hash must match installed setup hash. Same version cannot
acquire different app/setup bytes through repair or update.
Journal fields `id` (canonical UUIDv4), `kind` install/update/remove, `stage`
prepared/files/registered, `previous` (null or full installation record string),
`target` (full record string). Fresh install has no previous; update/remove require it,
same SID, no downgrade. Removal retains the same previous version/app/setup identities.
Recovery uses the exact five-line `SDRECOVERY001` codec from installation contract.
Unknown/corrupt records do not trigger implicit deletion, empty state or data migration.
Executor requires matching metadata/commit proof outside a transaction. Registered
journal stage or matching target commit proof forbids later automatic rollback to old
files: repair new registration and commit, or fail closed if its full bytes are lost.

`SDUPREF001` is header + bounded UTF8 JSON + final LF, ≤8192bytes. Required
`enabled` boolean; optional nonnegative Int64 `lastAttempt`, `lastSuccess`,
`deferredUntil` UTC seconds (each≤Int64Max−86400); duplicate/unknown fields fail closed.
Native file adapter maps only internal `data/update-preferences.v1` to the existing
data root. Atomic publication uses the same SID-bound reserved staging slot; fixed
Known Folder install/data roots are on the same volume. It never opens a database.
Deferral suppresses until the next future lastAttempt+24h deadline; if already due
or no attempt exists, until now+24h. Manual checks bypass this deferral.

RemovalTicket SDREMOVE001 binds UUID/cache-directory/removal-journal identity, original
canonical Installation and SHA256 of original commit.v1. Stored outside install root in
Known Folder temp cache; ≤8KiB canonical envelope. It grants only deterministic removal
of the matching installation under both leases, never target-path selection.


Current UI version is an ephemeral nullable projection of PlatformContext.release
from the running executable. No persisted entity/schema/format change. It is not an
update target or consent field. Unknown is represented by null/empty until native
context is known; RuntimeView binds to its current runtime owner on every rebuild.

## Update restart (transient)

Native restart intent: optional canonical prepared version, live-owner lifetime only.
Acceptance requires persisted prepared release with no validation error and no worker;
acceptance closes update admission. Plain tray exit/OS ending clear intent. No persistence
or storage format change. Existing pending consent remains the sole apply authority.
Host result8 means cleanup completed and an explicit update restart was accepted; it
never grants arbitrary executable/path authority. Owner.lock moves to maintenance Lease
without an unlocked interval, then existing pending helper inherits it.
