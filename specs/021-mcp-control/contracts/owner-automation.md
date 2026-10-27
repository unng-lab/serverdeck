# Shared native owner automation projection — 021

[Plans](plans.md), [job admission](job-admission.md), [MCP](mcp.md),
[operational client](operational-client.md).

The owner UI uses TrustedPlanService/TrustedJobService directly through owner
adapters. It never receives an MCP grant by substituting a role, or bypasses
grant-origin object policy. Endpoints are plans.create/get and jobs.apply/list/
get/events/cancel/reconcile with the same exact corresponding MCP parameters. New owner plans
have originGrantId null; owner get can inspect historical grant-origin plans.

For mutations AutomationOwnerApi starts with `{operationId,state:"running"}` within the
original5s native RPC budget. operationId is the original owner RPC envelope UUID
so UI can cancel an operation whose start acknowledgement is pending. A durable
mutation requestId remains a separate parameter, with the same permanent receipt
semantics. There are16 retained/in-flight owner automation handles, including
prepared requests and physically unfinished cancelled work.

Metadata reads plans.get/jobs.list/get/events return the done shape directly
within their original5s native RPC. They do not allocate a retained response
handle, so normal live job polling cannot exhaust the16-entry60s response cache.
At most16 physically unfinished inline reads remain owned separately until
actual service/native completion, including after an RPC timeout. Close cancels
and drains them. A timed-out pure read never starts a durable mutation.

automation.status takes exactly `{operationId}` and returns that running shape
or `{operationId,state:"done",kind:<original owner method>,result:<tool result>}`.
result reuses the closed bounded McpToolResult business envelope: success data is
the exact shared-domain acknowledgement/plan result, errors retain the shared
allowlisted code/boundary/retry fields. This is wire framing reuse; owner requests
do not enter mcp.invoke or acquire an MCP role. The native Local API error
vocabulary is unchanged. The actual TrustedApiClient selects the strict owner
handle/result parser. Output is bounded2MiB with normal depth reservations.

automation.cancel takes exactly `{operationId}`, returns `{operationId,cancelled}`
and drops response interest only. It never means jobs.cancel or receipt rollback.
Cancel before deferred start prevents late remote work. A late result cannot
replace the retained CANCELLED envelope. Completed/cancelled results last60s;
expiry/session detach retires output immediately, while actual service/native
cleanup remains charged. Foreign/expired/missing handles use NOT_FOUND for owner
requests. Each poll/cancel revalidates its actual native owner request first.
Prepared request reservations remain owned until invocation close.

Owner and MCP job actors are a private typed union over actual native contexts;
no JSON role/owner flag selects it. Owner may inspect workspace job history and
apply a grant-origin plan while preserving its original grant on job/receipt.
The same storage admission/driver still validates that object's current grant,
server scope, selected approval/delegation and exact target before an effect.
MCP job list/get remains isolated to its originating live grant. Owner list
cursors bind the actual native owner session separately from MCP grant bindings.

## Native automation contexts

TrustedSessionRequest privately mints TrustedOwnerAutomationContext only for an
initially admitted native owner request with one fixed method. It retains exact
session/generation/principal and original start time. There is no public
constructor or JSON role/intent field. Existing owner read contexts remain unable
to send preflight, submit, authorize or cancel through the root adapter.

Contexts for plans.create/get and jobs.list/get/events/reconcile have30s original
budget; jobs.apply/cancel2h for their durable driver. Root requests are closed by
the originating method: plan create may hello/observe/preflight/get; job apply
may hello/observe/preflight_get/submit/status/authorize_step/cancel; cancel only
hello/status/cancel; reconcile only hello/status/reconcile. Metadata-only get/list
contexts cannot open a helper. Each actual root request verifies this fixed
method set in addition to fresh native/session/current connection checks.

Owner helper work uses the same protected enrollment, qualified descriptor,
connection interest, SSH pool,48-work/four-channel limits and physical drain.
It cannot provide arbitrary commands, paths or a second transport. Root methods
do not themselves establish grant-origin job permission: the shared job service
must still check current object grant, exact selected authority and target.

## Flutter owner management

The concrete borrowed-client controller and panel are
[automation_controller.dart](../../../lib/automation/automation_controller.dart)
and [automation_panel.dart](../../../lib/automation/automation_panel.dart).
ProfileList places the panel beside the existing server controls only when it
receives the actual TrustedApiClient; it does not construct a role/client or SSH.
Profile authoring uses the closed JSON AST, name/description and immutable
version selection, with explicit new version save and archival. The owner can
inspect recipes, resolve complete parameter defaults, create/get exact plans,
review all parameters/effects/checks/digest/target/expiry before approving or
denying, then explicitly apply. Current plan expiry also ages locally in the UI.

Jobs list/get/events use actual owner inline reads. A selected unfinished job
polls local metadata once per second, pauses while another action is busy, and
stops on terminal state/panel disposal/client closure. It never resumes an effect
or reconnects. Cancel is an explicit jobs.cancel intent at the step boundary;
unknown results have an explicit observational reconcile action. The panel
retains the last200 received events and displays source drop counts. Separate
pagination controls retrieve profiles, jobs, approvals and delegations. Server
filters ensure approvals/delegations shown belong to this server. Approval plans
are opened through the actual immutable plan service before any decision.

Delegation creation binds the displayed exact profile revision/digest, current
server, explicit grantId, complete predicates and lifetime; default predicates
allow only the declared default parameter values. Owners may edit those closed
constraints and explicitly revoke a delegation. Client selection uses the actual
current public grant list and requires a live allowed plan+apply grant.
The panel also provides grant creation/policy replacement/revocation and verified
MCP command/args display/copy through [owner grants](owner-grants.md).

Each UI mutation captures its durable domain requestId and exact original input
before starting. A failed/unacknowledged action is retained for explicit replay
with the same domain IDs, including multi-step approval request/decision. New
mutations are disabled until that action is retried or its notification
dismissed. Reads can still inspect current state. There is no automatic mutation
retry. RPC async handle ID is separately assigned before sending, so cancellation
and disposal can retire pending/late response interest. Late results never update
a retired panel. UI cancellation closes only response interest; durable jobs
remain in the shared service and need the separate job-cancel action.

Installed format3 startup/client activation and final
UI/native/full-feature qualification remain open. Presence of these widgets and
selected source analysis does not establish product readiness.
