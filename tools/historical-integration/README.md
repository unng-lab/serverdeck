# Historical integration fixtures

Excluded from `flutter test` and current acceptance by the user's unit-only rule
(2026-11-03). These files used a real Isar DLL and process termination. They are
preserved as source history, not runnable unit tests or deferred completion gates.
Root `tools/vm-*`, durability/observer/lifecycle tooling and old evidence have the
same historical status. `build-vm-test-kit.ps1` is retired and refuses execution.
