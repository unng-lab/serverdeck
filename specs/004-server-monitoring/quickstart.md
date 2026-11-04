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
