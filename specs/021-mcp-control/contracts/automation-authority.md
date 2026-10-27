# Shared delegation and approval services — 021

Uses [records](records.md), [plans](plans.md), [invocations](invocations.md)
and the existing native publication gate. This contract does not establish
runtime acceptance or grant permission from structural records.

## Owner and MCP entry points

The shared `TrustedAutomationAuthorityService` is owned by
`TrustedControlServices`, using its exact StateStore, TrustedSessions and
TrustedMcpAuthority. The owner adapter admits only actual native owner requests;
MCP exposes only the existing `serverdeck_approval_request` tool. AI cannot issue
delegations, approve a plan or supply an origin/role through these parameters.

Owner methods and exact parameters:

| Method | Parameters |
| --- | --- |
| delegations.create | requestId, grantId, serverIds, profileRevisions, predicates; optional lifetimeSeconds |
| delegations.revoke | requestId, delegationId, expectedRevision |
| delegations.get | delegationId |
| delegations.list | optional offset, limit |
| approvals.request | requestId, planId |
| approvals.decide | requestId, approvalId, planDigest, decision |
| approvals.get | approvalId |
| approvals.list | optional offset, limit |

Public IDs are UUIDv4. Profile references contain the full immutable revision
tuple. Delegation predicates name exactly all parameters of every referenced
revision and narrow its declared domains; integer ranges stay inside the declared
range, enum values retain scalar type and satisfy each parameter definition.
Archived/missing revisions cannot receive new delegation authority. Creation
requires current apply scope for every delegated server. Lifetime defaults3600s,
range300..86400s, never exceeds the grant expiry. Revision1 is creation; revision2
is revocation only. Revocation remains possible after the underlying grant expires
or is revoked. The original request replay returns the original acknowledgement.

Approval request resolves a runnable, unexpired plan with unchanged source target
counters and current apply grant/server scope. MCP may request only its own plan.
Owner requests preserve the plan's original grant; they never relabel it owner.
Pending approvals expire with the plan. Owner decision is exactly approved or
denied, requires the displayed planDigest, and cannot change a prior decision.
Repeating that same decision is allowed; original receipt replay retains its
original result. Approval is consumed only by atomic durable job admission.

Mutation success results are the exact closed acknowledgements in records.md.
Get returns exactly `{delegation:<record>}` or `{approval:<record>}`. Lists sort
by ID and return `{items:[records],nextOffset:<integer|null>}`. Offset defaults0,
range0..1000; limit defaults25, range1..50. Pages are live views; a later insertion
may change offsets. Historical status/expiry is data, not current execution
authority. Get/list do not grant AI access to owner authority records.

Owner domain errors PLAN_EXPIRED and PLAN_STALE return exactly
`{failure:{code:<code>}}`; other failures retain the existing native Local API
error envelope. The fixed native error vocabulary is unchanged. Shared strict
result capture is selected by the actual TrustedApiClient for all eight methods,
including nested immutable record validation and a2MiB result bound. MCP keeps
its normal allowlisted tool failure envelope.

## Durability and lifecycle

Commands capture original scalar JSON before awaits. HMAC request identity binds
operation, actual origin and all original public parameters. Native authority
mutation admission precedes the existing32-entry shared writer queue. One Isar
transaction writes the changed authority record and permanent receipt; all16
snapshot groups and foundation references remain validated, bounded64MiB, and
verified by complete retained native readback before ACK. There are at most1000
delegations,100 approvals and10000 permanent automation receipts. There is no
silent history deletion or delegation replacement operation.

Current grant scope/revision and approval expiry are checked again at transaction
entry. A known policy/expiry/capacity abort must reload the unchanged snapshot;
unknown commit/readback state blocks storage. Replay performs actual full native
reload and current actor checks, never another decision or lifetime extension.

Each MCP request has its original30s service budget; each native proof/gate shares
at most5s including waits. Owner routes retain their original5s RPC budget.
There are at most32 authority operations, including physically unfinished native
cleanup. Cancellation retires response interest and stops new work; an accepted
store transaction drains and retains its receipt. A late result cannot revive
cancelled output. Shared shutdown denies intake and drains actual native work.

Owner approvals.list and delegations.list accept optional serverId beside offset
and limit. It is a canonical UUID. Filtering occurs before sorting/pagination:
approvals resolve their retained immutable plan's serverId; delegations must
contain the selected server in serverIds. Result records/shapes remain unchanged.
Omitting the filter retains the complete workspace owner view. This is a local
metadata projection and grants no server/plan authority. Owner get and all MCP
mutation policy/origin rules remain unchanged.

Final qualification must exercise native owner/MCP scope and origin isolation,
predicate domains, expiry at transaction entry, exact displayed digest decisions,
same/conflicting receipt replay, known rollback/unknown readback, cancellation and
quota/drain behavior. Job driver checks must enforce live delegation/grant and
target before every step; this authority service alone does not implement apply.
