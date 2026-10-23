# Shared format3 control services — 021

[Host trust](host-trust.md), [owner foundation](owner-foundation.md),
[owner grants](owner-grants.md), [catalog](profile-catalog.md),
[handshake](handshake.md), [channel](operational-channel.md),
[target fence](target-fence.md), [tasks](../tasks.md).

## Component and entry

Implement `TrustedControlServices` in locald
`lib/bootstrap/trusted_services.dart`. This is the internal composition of
already implemented schema3 services, selected by the verified format3
runtime. It is not an alternate bootstrap, schema selector, transport endpoint
or readiness claim. Existing format1/2 entries remain unchanged. Installed
startup, read/executor services and UI remain separate implementation tasks.

An asynchronous `create` entry requires the existing `StateStore`, live
`KeyCustody`/`ReceiptKeyMaterial`, and actual native-gated `TrustedSessions`.
All services use these identical instances. Check the native gate before
constructing adapters; missing/stopped gate fails NOT_READY. Require the
complete loaded schema3 snapshot and `store.assertAutomationCustody` before
subscriptions or publication; unavailable storage/custody fails
STORAGE_BLOCKED. No callback or boolean can substitute for either gate.

The composition creates one `TrustedMutationCoordinator`, one
`TrustedMcpAuthority`, one `TrustedAutomationProfileService`, one
`TrustedMcpRouter`, one `HostTrustProbeService` and one `SshTransportPool`.
Foundation and trust writes use the identical coordinator; owner and MCP
catalog adapters use the identical catalog service. All writers still pass
through the same registry/native publication gate before the existing store
queue. Inherited coordinator32, store32, sessions8/MCP4, requests16/session,
catalog128, probe16 and physical transport2 limits remain unchanged. No
second credential store, mutable profile copy or application write queue.

Exactly these 25 owner routes compose through `TrustedOwnerApi`:

| Adapter | Routes |
| --- | --- |
| Foundation | profiles.list/get/create/update/delete; settings.get/update; mutations.get/recent |
| Grants | grants.create/replace/revoke |
| Catalog | automation.profiles.list/get/create/update/compare/validate/archive |
| Trust | servers.trust.get/probe/probeStatus/probeCancel/confirm/revoke |

Expose the identical sessions, authority and router to `TrustedApiServer` for
its existing builtins/MCP handling. The composition itself implements the
owner API; unknown owner methods fail UNSUPPORTED. The catalog MCP backend
supplies the existing seven author tools. Other tool domains retain their
existing UNSUPPORTED behavior until concrete services are installed; no
catalog wire change or feature flag is justified by this component.

## Ownership and construction

Successful creation transfers ownership of the supplied registry to the
composition, including its publication gate. It owns all components it
creates. Store, custody, receipt key, writer mutex and native channel/pipe
workers remain borrowed from the outer runtime. Creation does not open,
close, migrate or replace them, publish discovery or start accepting channels.
The caller awaits successful creation before installing these services.

Keep bounded owner-isolate claims keyed by actual store and registry object
identity, not a caller string. A concurrent/duplicate composition using
either claimed instance fails NOT_READY without subscriptions or effects.
Claim before construction can cross an await. Successful close releases the
store claim only after all owned work and resources have drained; the stopped
registry remains unusable. A fresh live native registry may then compose
against that still-open store. A failed close keeps both claims, denying an
automatic retry with uncertain resources. No persistent lock/record is added;
process recovery still uses existing custody and mutex gates.

On construction failure, do not stop or take ownership of the supplied
registry. Stop and drain every component already created, unsubscribe all
installed listeners and close the newly created pool before returning the
failure. Clean construction rollback releases its claims and permits a later
explicit attempt. If rollback cannot confirm cleanup, retain claims and
return SERVICE_UNAVAILABLE; the caller retains the borrowed resources and
must end that generation rather than force an attachment. Preserve the fixed
NOT_READY/STORAGE_BLOCKED prerequisite failure after successful rollback.

## Owner invocation lifetime

Before parsing/delegating, require the same-registry live owner request and
exact admitted method. Retain the existing prepare-before-initial-proof
contract: the composition cannot read results, prepare credentials, perform
native I/O or write during owner preparation. Delegate immutable capture and
reservation to exactly one existing adapter; execution still requires that
request's actual successful initial proof and original RPC budget.

Wrap prepared invocations so stopping this composition closes every
unexecuted invocation, including grant invocations that have no standalone
adapter close. A closed prepared invocation fails SERVICE_UNAVAILABLE without
starting its delegate. Track prepared interests separately from started
execution futures: closing the caller's interest never cancels or forgets a
running durable effect. Stop/retired native requests retain their ordinary
UNAUTHORIZED/liveness behavior. No caller-supplied role, requester token or
reservation is accepted. The existing channel's bounded live request
interests remain the intake bound; no additional unbounded admission queue.

## Stop and physical resource drain

`close()` publishes one shared completion before synchronous teardown and
returns that exact future for concurrent/reentrant calls and after settlement.
Mark the composition stopped, stop the registry (retiring sessions and new
gate acquisitions), close the router, stop the owner adapters and close all
prepared invocation interests before yielding. A failure in one stop callback
must not skip the others.

Initiate and observe every owned drain, even if another one fails:

- Foundation/trust adapters and their shared coordinator cancel reserved or
  queued interests and wait for actual running commit/readback/claim cleanup.
- Catalog close waits its admitted operations and tracked real native proofs,
  acquisitions and lease completion; router close alone is not that drain.
- Probe close retires challenges and waits actual attempts/claimed writes.
- Authority `closeAndDrain()` waits charged grant-open work and late key
  disposal, including callers already detached or timed out.
- Registry close waits its actual native publication acquisitions/leases.
- Started owner delegate executions remain observed until their actual
  adapter completion. Do not substitute a caller's reply timeout for this.

Start all these drains without waiting for another dependent service first;
then await every completion. Only after those settle close and await the
owned transport pool. No timeout, force release, new key, implicit retry or
successful completion may stand in for an actual resource completion.

Any stop/drain/cleanup failure yields the fixed SERVICE_UNAVAILABLE shared
completion after attempting the other owned cleanup steps; retain claims.
The outer runtime must not treat failed drain as permission to close the
borrowed store/key or release its writer mutex. Successful service drain does
not own or claim complete raw peer I/O cleanup: the outer runtime must also
close its native channels/pipe workers before clearing keys/closing storage
and releasing the writer mutex. This component never forces that teardown.

## Acceptance

Use actual protected schema3 Isar/CurrentUser DPAPI, verified same-build
format3 native roles and real native registry/gate, not synthetic session or
store proofs. Include a retained nonempty historical graph and compare native
IDs/payloads; no schema2 service fallback.

Qualify all 25 supported routes and unsupported/foreign/MCP/incorrect-method
refusals before payload/object access; missing native gate, wrong custody,
duplicate store/registry attach and clean failed-construction retry. Owner
and MCP catalog requests must see the same revisions through production
adapters/router. Current-grant replacement/revoke and target changes must
retire the corresponding old MCP authority under the existing contracts;
settings updates preserve unrelated sessions. Real trust confirm/revoke must
share the foundation receipt/coordinator path, with actual loopback SSH and
zero authentication during probe.

Exercise close before prepared grant execution, reserved foundation/trust
work, a real admitted native write, a held catalog proof/native acquisition,
a running probe and charged late DPAPI grant-open work. Close must remain
pending at each retained actual boundary, keep borrowed storage/key/mutex
owned and usable until supported teardown, then settle only after release.
Verify future identity and no late effects/bindings. A genuine native lease
release failure must fail close, run other cleanup and retain attachment
claims; it must not trigger automatic store teardown. Failed-construction
cleanup uses actual invalid prerequisites/component construction, without a
runtime callback that bypasses proof or returns fabricated cleanup success.

Exercise the composition through the production strict client/server/channel
as well as direct trusted fixtures for internal lifecycle boundaries. Existing
individual component regressions remain required; this acceptance alone
does not close T152 target/transport integration, T154 compiler/read/UI,
installed startup, executor, kernel reboot or source-qualified release.
