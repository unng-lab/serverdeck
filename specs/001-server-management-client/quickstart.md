# Quickstart — Windows fixture milestone

From H:\projects\unng\serverdeck:
```powershell
uvx --from specify-cli==1.1.0 specify version
$env:SPECIFY_FEATURE_DIRECTORY='specs/001-server-management-client'
& .specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireSpec -RequireTasks -IncludeTasks
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter test integration_test/windows_smoke_test.dart -d windows
flutter build windows --release
flutter run -d windows
```
The default UI uses generated demo observations only. Separate read-only SSH/OS
custody adapters are tested on disposable localhost but not wired into this UI.
No package executor, live service actions or backend are enabled.
Switch servers, inspect software/state/version, open journal search/priority/unit/
time/details, pause/resume simulation, inspect stale metrics and a disabled install
preview. Test data is not evidence of a real connection or successful install.

M1 prerequisites: disposable SSH host enrollment, native OS custody and safe adapter
tests before any real read. M2 prerequisites: pinned image build, strict privilege
helper and disposable Ubuntu 24.04 systemd fixture explicitly provisioned for tests.
No instruction here authorizes production installations or NetBird changes.
