# Runtime / global updates wiring

Completed T013/T015/T016/T029. FeatureRuntime owns the UpdateOwner/native port;
RuntimeView starts it only after runtime admission, including storage retry.
Global settings use shared DeckTabs for updates/MCP in one OwnedSettingsRoute.
Native stop/drain are epoch-checked cleanup calls; cancel/drained before creation
do not create the service. Worker drain preserves owner authority. Signed offer
metadata is projected without transport URLs, hashes or filesystem paths.

## Checks actually run

- `dart format --output=none --set-exit-if-changed .`: 387 files, 0 changes.
- `flutter analyze`: no issues, 3.1s.
- `flutter test`: 761 passed, approximately13s.
- `tools/check-test-boundaries.ps1`: passed, 94 Dart files.
- `tools/test-release.ps1`: 17/17 native units, 9.51s.
- `flutter build windows --release`: exit0, 20.8s.
- `lychee "specs/**/*.md"`: 274 total, 268 OK, 0 errors, 6 excluded,
  2 redirects.

An earlier full test run was interrupted while the new MCP/settings fixture
stalled in teardown. Its fake-async cleanup now runs before leaving the widget
test, with a pump to drain stream-close microtasks; isolated and final full tests
passed. Interrupted runs are not counted as successful evidence.

## Independent review

Fresh read-only `review_006_runtime_wiring`, fork_turns=none: no findings;
ready within T013/T015/T016/T029. Review covered Dart owner/lifecycle/settings,
native channel/factory, startup readiness, exact args/epoch validation, privacy,
signed data projection, unit fixtures and related specification/plan contracts.

Bootstrap pending activation, helper handoff, fresh apply/consumption and uninstall
remain unfinished T018–024/T028. In particular, factory commit binding does not
replace the bootstrap's required full canonical byte verification before host.
Final feature verification/review/convergence are still T025–027. No product,
native database, live GitHub, integration or layout acceptance checks were run;
this evidence does not prove installation on a clean Windows OS.
