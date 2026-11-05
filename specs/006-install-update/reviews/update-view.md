# Update view and restricted Dart platform port

Date: 2026-11-04. Dart milestone; native channel/runtime binding and download,
pending, startup handoff and uninstall remain open. Nothing published/deployed.

## Implemented scope

`lib/updates/update_view.dart` presents current version and verified offer fields:
target, notes, signed setup size, UTC publication, platform and ABI/store compatibility.
It reuses shared components, including C14 consent, C18 compatibility, C23 progress
and C28 timestamps. Observed download length is separate from signed setup size.
Ready instructs user tray exit and a later normal launch; the view has no quit/launch API.
Failure, unconfigured source and proved-current states have distinct text.

Consent captures an immutable offer projection. A changed dialog or queued offer,
including changed metadata with the same version, cannot inherit its confirmation.
Accepted check/download/cancel immediately project their local phase with read fencing;
command-refresh latency does not disable cancel in the view. The owner retains all
in-flight work for shutdown/drain. A nested prompt is closed with OwnedSettingsRoute
retirement in a synthetic global host with no selected server.

`NativeUpdatePort` in `lib/runtime/native_platform.dart` sends only the owner epoch,
version or enabled boolean through the specified six update methods. Malformed
snapshot/admission replies fail rather than becoming false success; native stale-epoch
errors propagate. This is the Dart adapter, not a claim that the C++ channel methods
or actual FeatureRuntime/RuntimeView binding have been implemented.

## Review/fix loop

Fresh reviewers used `fork_turns=none`, read AGENTS/package/source directly, did not
modify files and did not infer full-feature readiness from this slice.

1. `review_update_view_port`: two confirmed findings: cancellation before the attempt
   snapshot could immediately reschedule an automatic check (T046); false check admission
   was shown as active checking (T047). Fixed by projecting local acknowledgement time
   and respecting accepted=false while obtaining the authoritative result. New tests
   cover enabled=true, null/due previous attempt, delayed check/cancel replies and
   false admission with delayed/failed snapshot. No new mandatory product/design gaps.
2. T045 records local phase/old-offer invalidation found during UI implementation.
   T048 records a queue issue found by the primary agent: a setting can delay admission
   while a same-version offer refreshes. Owner now checks the captured offer's identity
   inside the queued action; a blocked-setting regression exercises this exact sequence.
3. `review_update_view_port_fresh`: «Замечаний не найдено». Independently inspected
   T045–048, view/owner/adapter and tests; no unresolved confirmed findings in this slice.

## Actual checks

- Exact formatting gate:385files0changes.
- `flutter analyze`: no issues,3.9s.
- Full `flutter test`:754passed, exit0; update subset23tests. Fakes cover commands,
  schedule/rollback, cancellation/late replies, C14 decline/confirm, changed same-version
  offer, queued consent, metadata, error distinctions, unknown length, ready instruction,
  typed channel arguments and owned-route retirement. Functional text/state/actions only.
- Boundary audit:93Dartfilespassed. No feature design/layout/golden checks.
- Lychee:258total252OK0errors6excluded2redirects.

Native source was unchanged in this milestone; its previous14/14 unit result remains
scoped to that source. No product, network, Explorer, real registry, VM/e2e or clean-OS
installation test was run. Source artifacts and fakes do not prove actual platform
integration. T013/T015/T016/T017–019/T021/T023–029 retain their unfinished scope.
