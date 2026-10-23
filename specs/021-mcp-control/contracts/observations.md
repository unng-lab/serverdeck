# Shared remote observations

[Plan](../plan.md), [tasks](../tasks.md), [connections](connections.md),
[MCP](mcp.md), [observability](../../009-observability/spec.md),
[managed resources](plans.md).

`RemoteReadService` in locald owns one bounded in-memory observation cache and
refresh sampler per connected target. `RemoteReadOwnerApi` and the MCP read
backend use this identical service and `TrustedConnectionService`. Read access
never issues a credential, arbitrary command/path or transport to a client.
Refresh requires an existing authorized attached connection; it never reconnects
implicitly. Owner and MCP connection/session/target retirement rules apply to
every source request and publication.

## Native owner interface

New routes alongside the five connection routes:

| Method | Parameters | Result |
| --- | --- | --- |
| servers.state | profileId, optional refresh:boolean | operationId, state:running |
| servers.logs | profileId, optional unit/since/until/priority/text/limit/cursor | operationId, state:running |
| servers.configuration | profileId, resourceId, optional refresh:boolean | operationId, state:running |
| servers.readStatus | operationId | running, succeeded with kind/result, or failed with safe code |
| servers.readCancel | operationId | operationId, cancelled:boolean |

IDs are existing UUIDs, exact required/optional fields only. The first admitted
native owner request issues `TrustedOwnerReadContext` with one original30s budget;
each fresh native proof remains capped5s. This grants no trust-write authority.
There are16 owner handles including reservations and physical cleanup; completed
results expire60s after completion. Handles bind the actual native session, never
a caller string. Foreign/absent/expired status is NOT_FOUND; cancel is uniformly
false. Target retirement discards completed retained results as well. Logical
cancel/timeout does not release physical work before streams/native proofs drain.

Succeeded readStatus is exactly `{operationId,state:"succeeded",kind,result}`,
where kind is `state|logs|configuration`. Running is exactly
`{operationId,state:"running"}`; failed is exactly
`{operationId,state:"failed",code}`. Cancel is exactly
`{operationId,cancelled}`. The verified format3 client selects the dedicated
`remote_reads.dart` capture path. Shape validation never establishes authority.

## State and inventory

State is exactly `{serverId,identity,connection,system,metrics,packages,units,
history,cacheDropped}`. `identity` is the captured source connection identity,
nullable before any observation; changing target never relabels old facts.
`connection` is the current caller's connection snapshot. Cached known facts may
remain visible as stale; refresh:false performs no remote IO.

Every component has `{source,observedAt,receivedAt,quality,value}`, optional
`code,truncated,stale,parseErrors`. Quality is
`known|stale|unknown|unsupported|denied|incomplete|error`. UTC source time may be
null when unavailable; local received time is separate. Missing/failing facts
remain null/unknown, never synthesized zeros. `system` and `metrics` values are
objects, package and unit values are lists capped2048 rows each. Values are
untrusted display data. Uptime seconds and displayed CPU/RAM/rootdisk percentages
are integers (percent rounded to nearest whole percent); byte/counter quantities
remain integers and first CPU delta is null. No floating value is introduced into
the shared Local API canonical encoder. Source identifiers identify the actual
fixed SSH probes; missing-source observations may use `ssh:<component>`.

Concurrent authorized refresh callers share one sampler and its actual four
source reads. Detaching one caller preserves work while another authorized
interest remains. Minimum refresh interval5s; metrics stale15s, inventory5min.
Inventory age is tracked per component and never refreshed by a metrics read.
History holds at most120 small scalar points over10min. Per-server state data
is bounded1.5MiB, complete returned data2MiB, global state cache64MiB. Eviction is
explicit through cacheDropped/RESOURCE_LIMIT and does not create permission.

## Journald

Log result is exactly `{serverId,identity,source:"journald",timezone:"UTC",
observedAt,quality,records,gaps,dropped,duplicates,parseErrors,truncated}`, optional
nextCursor. Limit defaults100, range1..1000. Priority is integer0..7; text filter
is at most256 code points; since/until are UTC and since cannot exceed until.
MCP unit selectors are registered resource IDs: postgresql.service maps to
postgresql@16-main.service, clickhouse.service to clickhouse-server.service.
Owner exact unit names still undergo typed fixed-command validation.

Records retain well-formed public message text and source UTC timestamps, sorted
ascending. A record is at most64KiB; malformed/oversized/duplicate/truncated
records and byte gaps are explicit. The SSH reader has a bounded8MiB source
capture; public log page data stays within2MiB. Inclusive native cursors are
deduplicated without advancing past an unreturned over-budget record.

There are at most128 opaque cursors with5min TTL, signed by a generation-local
random key and bound to actual principal, tool, target identity and normalized
filter/defaults. They carry no credential or execution authority. Reusing a
cursor for another principal/filter/target fails CURSOR_EXPIRED. The recent ring
holds500 records/server with a global64MiB cap and is never persisted to Isar.

## Managed configuration and acceptance

Configuration result is exactly `{serverId,observation,desired,expected,comparison}`.
observation retains the exact schema3 ManagedResourceObservation from plans.
desired is null or the last successful confirmed DesiredState record for this
server/resource, resolved through its immutable job/plan. A failed/unknown/pending
attempt never replaces it. expected is null without desired, otherwise exactly:

- Config: `{kind:"config_file",fileDigest,values}`. FileDigest comes from the
  immutable renderer effect; motd expected text includes its actual rendered final
  newline. Observed text is compared verbatim and retains its Unicode.
- Service: `{kind:"service",activeState,unitFileState}`, each nullable if that
  property was not part of intent. Restart means desired active; its one-time
  restart proof belongs to the successful job, not an ongoing PID equality test.
- Recipe: `{kind:"recipe",id,version,recipeDigest}` for an owned resource. Current
  comparison remains unknown/recipe-evidence until qualified recipe-specific
  evidence is implemented, rather than inferring defaults from package presence.

comparison is exactly `{status,basis,reason,observedAt,confirmedAt,comparedAt,
differences}`. Status is unmanaged|unknown|stale|matched|drift; basis is
none|file|service|recipe. Reason is none|no-desired|observation-unavailable|
stale-observation|target-changed|recipe-evidence. Timestamps are UTC milliseconds;
observedAt is null without known/stale evidence, confirmedAt is the actual last
successful job update or null, comparedAt is the current comparison time.
Differences are at most8 unique `{field,desired,observed}` records with literal
scalar data. Known comparisons require fresh evidence<=15s and matching original
target/host/registry. Stale/missing/changed-target data never becomes matched.

For managed files comparison covers exact rendered bytes/file existence and
declared values; it does not claim a fresh database SQL/effective-runtime probe.
The UI labels that file comparison explicitly. Services compare declared active
state and persistent enabled/disabled intent against actual systemd observations.
Reading/comparing never rebases an approved plan or repairs the server.

Same owner/MCP service and the actual format3 strict client select this closed
comparison DTO. Flutter shows desired version, successful application time,
actual observation time, explicit data gaps and per-field differences. It makes
no automatic fix. Missing/unqualified root executor remains EXECUTOR_UNAVAILABLE/
RUNTIME_INCOMPATIBLE on requested refresh, rather than fabricated configuration.

T012/T172/T174 and the final checks cover actual authorized normal reads,
concurrent refresh/session retirement, target changes, no reconnect, missing and
denied sources, malformed UTF8/JSON, partial metrics, counter resets, stale
inventory, all bounds, normalized filters, cursor isolation/expiry, pagination,
physical cleanup and no raw persistent logs. Existing historical test results do
not establish acceptance of these new paths.
