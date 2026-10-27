# Native durable job admission — 021

Extends [records](records.md), [plans](plans.md),
[automation authority](automation-authority.md) and [executor](executor.md).

`JobMutationCommand` captures exactly requestId/planId for job.apply and
requestId/jobId for job.cancel/reconcile. Only actual native service actors derive
origin, grant revision and target. No caller supplies jobId/attemptId for admission,
authorityRef, status, compiler approval or an arbitrary root request.

`StateStore.mutateTrustedJob` is the native durable metadata boundary, not an
executable tool by itself. The shared job service must first revalidate its actual
native session, qualified enrolled executor, current target, immutable plan's
compiler output and fresh full root observations. Its internal verifiedPlanDigest
argument only detects plan substitution between that work and the queued native
transaction; a supplied/matching digest cannot establish those facts or permission.
MCP/owner routing must never forward a public digest into this parameter.

New admission checks runnable/unexpired plan, nonarchived source, exact current
target counters and current origin/object grant apply/server scope. It rejects
occupied server or host, including unknown/reconciling jobs, without a host queue.
The native snapshot permits250 active and1000 terminal jobs. A plan can admit
only one job; aliases with another requestId return the original job/attempt and
authority without another admission or execution. Original receipt replay and
aliases need current authorization, but do not extend the old plan lifetime or
restart its job. Every alias consumes its own permanent receipt slot.

Authority selection is deterministic: matching live delegation first, ordered
by ID; otherwise an approved unexpired exact plan approval, ordered by creation
time then ID. Owner-origin plans always need approval. Owner use of a G-origin
plan retains G as job.grantId/objectGrantId, with current G policy still checked.
The chosen authority is immutable for this job. A later delegation cannot replace
a revoked/expired selected delegation during execution.

One native transaction inserts job, first queued event and permanent receipt,
and consumes the selected approval if applicable. Job/attempt IDs are generated
internally with bounded collision refusal. Initial event sequence is1 and the
job nextSequence is2. No remote write precedes durable admission. At transaction
entry recheck current actor/object policy, plan expiry, target and the selected
authority. If authority expires during the write wait, prove unchanged rollback;
unknown commit/readback state blocks storage. All groups/foundation receive full
candidate validation and native readback through the fixed automation delta writer.

## Driver handoff and cancellation

The driver must durably transition queued to running **before any root submit**.
Thus a persisted queued cancellation can safely terminate with effects none.
Once running, cancellation records cancel-requested and never claims rollback or
kills an admitted APT transaction. Unknown/reconciling jobs keep their occupancy;
cancellation records intent while observation establishes actual effects. Repeated
cancel intent with a new requestId creates an acknowledgement alias without
another state event. Terminal cancellation requests only acknowledge the existing
terminal job. Reconcile changes unknown to reconciling, clears the uncertain
outcome while observations are pending, and cannot grant step authority.

`validateTrustedJobStep` requires actual current actor/object apply/server scope,
exact captured target, executable job state, no cancellation and the immutable
selected authority. For delegation it checks the complete profile tuple, complete
parameter predicates, revision, current grant and expiry again. For approval it
requires the exact consumed approval/job/plan binding; original plan expiry does
not terminate an already admitted job. The caller must hold the actual native
publication gate through fresh native checks and root authorize_step CAS. This
method is structural/store validation; calling it alone never launches a step.

All admitted mutations use the existing32-entry queue, origin-bound HMAC request
identity and10000 permanent receipt bound. Event quota refuses new admission;
already admitted jobs can persist cancellation, uncertainty and terminal outcome
at that quota. Missing bounded events advance the durable sequence and are
reported explicitly as dropped history, never as an unchanged job status.

## Concrete driver and MCP projection

`TrustedJobService` composes the six existing apply/jobs MCP tools over the same
RemoteExecutorService. Before new admission it independently recompiles the whole
bound program, checks the qualified descriptor/runtime/boot/host/registry/target,
verifies the original cached root preflight capsule and effect/check output,
and reads every actual current managed observation to recompute fingerprints.
Expired/blocked plans never open a write stream. Original receipt replay verifies
native rows without repeating that preflight or restarting an old job.

The durable driver owns the enrolled helper session after metadata admission,
including after caller response cancellation. Concurrent equal requests cannot
transfer/leak a second session into the same job. Shared close drains request
operations first, then also drains drivers transferred by already accepted writes
during shutdown. Proof/publication cleanup remains charged until physical completion.

Driver persists running before root submit, polls the same receipt every1s, and
holds the native publication gate around fresh actor/selected-authority/target
checks and each root authorize_step CAS. It uses the root persisted
authorizationEpoch+1, never a guessed/reset controller epoch. Every unused
challenge is bound to the captured exact plan and next derived effect. There is
no automatic retry of submit or authorize after an ambiguous response. Root
uncertainty, native/session loss or changed trust stops further authority and
persists unknown with occupied target. Cancel sends only the stable stop intent;
the admitted effect can finish. Explicit reconcile obtains observations/status
without authorizing any subsequent effect.

Owner cancel/reconcile authority is independent of the accepted job's original
client grant: revoke, expiry or scope removal stops new effects but does not
prevent the verified owner from observing/stopping the admitted attempt. Current
owner native proof and publication gate remain mandatory, including on replay
and commit; immutable grant/plan/attempt/receipt identities are never relabelled.
MCP control still requires the original grant's current server/scope authority.
No owner apply/approval/authorize_step bypass is introduced.

Cancellation and observational reconciliation open a genuine **current**
owner-confirmed SSH/executor session for the same workspace/server profile and
the same immutable plan hostId. They use the historical hostAttemptId and
validate its actual receipt/status/outcome against the historical immutable
program. The current session's target/access/trust counters and registry can
differ after explicit owner maintenance: impossible historical counters are not
a recovery prerequisite. The executor facade still verifies the current
enrollment, qualified runtime identity and target before every request. No
submit or authorize_step is issued in these control modes. Different hostId,
missing current profile/trust/enrollment or unavailable/unproven receipt keeps
unknown/occupancy; never infer success, release a lock or silently rebind to
another profile. New admission and all effect authorization retain exact
original counters, registry, preflight and boot requirements.

Acceptance must cover original grant revoke/expiry/scope removal followed by
owner stop/reconcile, including terminal receipt replay; the owner still cannot
apply/approve for the retired grant. Also interrupt an actual effect, change
credentials or explicitly reconfirm a changed host key/enrollment for the same
hostId, and reconcile through the current session with no additional Ansible
launch. Another hostId must refuse and retain unknown occupancy.

Root status is captured with exact keys and bounded checks/events/challenge,
referenced against the immutable local program. Sequences, step index and epochs
cannot go backwards. A success must contain every declared passed check exactly
once. Failed/cancelled/unknown remain distinct from success. Native publication
atomically writes state/event plus last successful desired versions for all
owned resources only on fully checked success. Failed/unknown attempts never
replace those successful desired versions. Desired counters are checked before
admission as well as publication.

New generation recovery performs only local metadata writes under the native
gate: queued jobs are cancelled with no effects because submit requires a prior
running record; running/cancel-requested/reconciling become unknown. Existing
unknown remains occupied. No old root stream, nonce or permission is resurrected.

MCP projections:

- jobs_get returns exactly `{job,plan}` with immutable plan and current durable job.
- jobs_list returns `{items:[{job,serverId}],nextCursor?}`, current originating
  grant and currently allowed targets only. Limit defaults50,1..100. Sorted IDs
  form a stable snapshot. At most64 opaque random256-bit cursors, bound to actual
  session/grant/revision/filter, with one original5min expiry across pages.
- jobs_events returns exactly `{events,nextSequence,dropped,hasMore}`. `dropped`
  is the integer number of missing event sequences in this returned interval.
  `nextSequence-1` is the next after value. At the event quota durable job state
  still advances, and these gaps remain visible after restart. A future after
  value returns an empty page with the actual current nextSequence, without
  overflow. Limit defaults50,1..100.

Read and admission operations retain their original30s budget; native proof/gate
admission uses at most5s. Root requests remain bounded5s. The apply/cancel driver
has an absolute2h budget; observational reconcile30s. Service operations max32;
actual root work remains inside the same shared48-work/four-channel transport
limits. Temporary native snapshot publication is awaited as a bounded pause,
never treated as a revoked grant or permanent service failure.

Owner plan/job routes, desired/drift read projections, UI activation and qualified
installation recipe/runtime completion remain required functionality. The new
driver and these metadata services still require final native/remote/integration
checks and independent review after the whole feature is implemented.
