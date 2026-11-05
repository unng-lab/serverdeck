# Validation guide: 004

From repo root, with existing Dart/Flutter/lychee and Windows C++ toolchain:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
./tools/check-test-boundaries.ps1
lychee "specs/**/*.md"
```

No real server/Isar/product launch. Parser fixtures CPU reset/guest/RAM missing/df
reserved blocks; fake-clock scheduler fairness/timeout/stale; auto all/new MCP
profiles/prompt slots/manual stop/no retries; trust/session/generation/late fences;
activation/tray/shutdown; native marker classification/retries/write failures;
vendor in-memory pending-open/ACK/oversized/early output cancellation.
Functional widgets assert data/text/callbacks, no layout/colors/goldens.
Native CMake/CTest unit targets only, not historical lifecycle/process-kill tools.
All applicable checks and clean AGENTS independent review required. Units/static
checks do not prove clean-OS integration. [Contract](contracts/monitoring.md).

## US4 hour history units

Fake clock/source/storage:720 cap and exact1h boundary, UTC rollback/future rows,
partial/all-source failure, reconnect/resume/restart segments,rename/revision/delete,
late load/commit fencing,failed/corrupt load inhibits overwrite,write failure/retry,
owner shutdown drain. New owner over same fake repository restores past samples but
no live readings/SSH. Functional widget selects Monitoring tab/server and checks
C22 point values/empty/retry callbacks, never positions/colors/overflow.
Run shared001 component units after changing C22; no captures unless explicit opt-in.
Current format2 unit fixtures open the same store and preserve metadata/settings/security; unsupported versions are rejected before DB open without replacement.

