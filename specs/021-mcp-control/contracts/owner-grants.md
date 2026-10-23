# Native owner grant writes — 021

[Owner methods](mcp.md), [records](records.md), [credential transactions](credential-files.md), [registry gate](target-fence.md), [gateway](gateway.md), [tasks](../tasks.md).

## Route and authority

OperationalGrantOwnerApi in packages/serverdeck_locald/lib/api/owner_grants.dart implements OperationalOwnerApi for exactly grants.create, grants.replace and grants.revoke. They map to the existing grant.create/replace/revoke OwnerGrantCommand and native StateStore transaction. Only the same registry's live native owner request with the exact matching admitted method can dispatch. Check registry identity and owner role before method-specific parsing/object access; a foreign registry, MCP request or mismatched method fails FORBIDDEN. The ordinary server's existing role gate still rejects MCP owner routes before calling this adapter. Unknown owner routes remain UNSUPPORTED; there are no singular wire aliases or arbitrary method forwarding.

The constructor requires an actual native-bound, nonstopped registry and an operational schema2 store. Missing native composition fails NOT_READY, an unavailable store fails STORAGE_BLOCKED. hasNativePublicationGate is a local lifecycle observation, not an authorization/readiness feature or a replacement for native proof. This adapter does not yet supply grants.list/configuration, other owner services or installed startup; original T010/T110 and view/activation gates remain open.

OwnerGrantCommand.parse captures immutable typed fields synchronously before waiting. Keep existing UUID/CAS/policy/lifetime/label validation and permanent owner-origin receipt rules unchanged. Mutating the caller's input during the gate wait cannot alter the admitted command. The acknowledgement is exactly the committed `{grantId,revision}` map; never return a mutable current record or credential. Same-ID identical input returns the original receipt without another rotation, changed input conflicts, and current records are obtained through separate owner reads.

## Publication and write ordering

OperationalSessions.runAuthorityMutation is a trusted internal service helper over the same private native generation gate. Its callback is static service code, never a wire function, role provider, grant override or arbitrary user program. Acquire the native publication gate **before** joining StateStore's serialized write queue. All future production target/credential/trust/grant adapters must preserve this order: a writer must not hold the store queue while waiting for a gate held by another queued writer. The existing internal OwnerGrantService/StateStore primitives remain storage/provisioning building blocks; they expose no external route by themselves, and installed owner grant routing must use this guarded adapter.

Native gate admission remains bounded at16 pending/held/late interests across registry authority and target-change users; StateStore's independent32-entry durable queue limit remains unchanged. Exhausting either budget returns RESOURCE_LIMIT before further admission. Authority mutations use the publication gate without the target-change open fence or unconditional workspace-wide MCP retirement. The existing native grant transaction/publication/current-binding logic invalidates changed authority. Grant create need not retire an unrelated grant solely because it shares a gate.

Pass the request's original remaining5second RPC budget, capped by the gate helper's5seconds. A nonpositive budget fails TIMEOUT without running the effect. After acquisition check stopping/deadline, then revalidate the actual owner request within its remaining original budget and check it again immediately before native transaction admission. Map a proof timeout to fixed TIMEOUT; late side-effect-free native proof work stays owned by its existing peer/worker and cannot start a late mutation. No reconnect or automatic effect retry.

Once the store write is admitted, the helper retains its actual lease through transaction commit/rollback, credential pointer reconciliation/readback, authority listener publication and real callback completion. A caller's reply timeout/disconnect does not unlock an in-progress durable effect. It observes the late result and relies on permanent receipts for recovery. Always release in finally; a physical release failure returns SERVICE_UNAVAILABLE and cannot publish a successful acknowledgement even if the transaction committed. The committed receipt is retained for recovery. Registry close waits for these gate-owned effects, including authority effects that have no target-fence interest; it never forces a lease free to satisfy a logical shutdown deadline. Product poison recovery/new-generation readiness remains T110.

## Acceptance scope

The format3 TrustedGrantOwnerApi additionally provides grants.list{}, optional
serverId filter, grants.get{grantId} and grants.configuration{grantId}. The
schema2 adapter and its three write methods remain unchanged. List result is
exactly `{items:[<public grant>]}` with all at most32 workspace grants sorted by
ID (including expired/revoked history); filter selects membership in serverIds.
Get returns exactly `{grant:<public grant>}` or NOT_FOUND. Public metadata is
exactly `{id,workspaceId,label,revision,scopes,serverIds,createdAt,issuedAt,
expiresAt,revokedAt}`; credential wrappers, keys and secretRef are excluded.
Protocol grant_owner capture validates exact fields/types/counters/timestamps,
scope policy, unique IDs and the full bounded512KiB result. The real format3
client selects this parser for both reads and stable mutation acknowledgements.

Reads hold the same actual registry publication gate and original5s native owner
proof before/after snapshot capture. They neither rotate credentials nor retire
sessions. Configuration requires a current grant again immediately before
return, a supplied opaque TrustedBuildBundle and matching native endpoint root
and build ID from the actual retained peer. The owning Windows worker returns
that normalized endpoint root only after current peer verification; neither RPC
params nor a role/path string can mint it. Missing verified bundle is NOT_READY,
foreign root/build is INCOMPATIBLE, expired/revoked grant is FORBIDDEN.
TrustedBuildBundle generates only its fixed mcp.exe command and fixed app-root/
grant-id argument vector after current MCP binary/manifest hash validation.
This read contains no secret and does not itself connect a client. Shared
composition accepts the verified bundle from installed startup; metadata and
write-only fixtures may omit it but cannot generate a launch configuration.

The Flutter automation panel reads this public list, explicitly creates/replaces
or revokes grants through the existing permanent-receipt transactions and can
display/copy the verified command/args. Initial scopes are read/logs/author/plan;
apply requires explicit policy selection and subsequent delegation/approval.
Replacement is shown as both a policy change and credential reissue. Delegation
uses an explicit choice of a live plan+apply client allowed on the current server,
then displays the captured exact profile/revision/digest and parameter predicates.
No grant ID is entered manually for that flow. The captured revision cannot
follow a later UI selection before submission. Installed activation and final
native/UI qualification remain required.

Actual format2 AOT/native owner and MCP clients use schema2 Isar/CurrentUser DPAPI and the normal OperationalApiServer/Channel/ApiClient. Qualify create/replace/revoke and stable receipt replay; no effect while an independently held native publication gate blocks the adapter; MCP rejection before owner dispatch; same-registry/method/role checks; immutable input across the gate wait; conflicting replay without a new revision; and registry close retaining a real committed grant callback's lease until it settles. No synthetic role or transaction provider substitutes for these paths.

The gateway native fixture creates its registry generation keeper before channel intake. Its blocked1MiB stdout/queued revoke and post-successful-ping ordering cases invoke this actual adapter with a real independently bootstrapped owner request, not a manually guarded storage callback. A fixed scheduling marker is set only after actual adapter dispatch has entered its gate acquisition. Require no grant commit/acknowledgement before the prior publication finishes, then deny queued stale data with unchanged wire semantics. These fixtures qualify the owner write/publication composition, not an installed owner UI, every production mutator, real target identity changes or executor/SSH effects.
