# Quickstart — Windows fixture milestone

From H:\projects\unng\serverdeck:
```powershell
uvx --from specify-cli==1.1.0 specify version
$env:SPECIFY_FEATURE_DIRECTORY='specs/001-server-management-client'
& .specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireSpec -RequireTasks -IncludeTasks
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test/windows_smoke_test.dart -d windows
flutter test integration_test/local_storage_test.dart -d windows
Push-Location packages/serverdeck_locald
dart pub get
dart test
dart analyze
Pop-Location
lychee "specs/**/*.md"
& tools/build-windows.ps1
& tools/test-locald-process.ps1
& build/windows/x64/runner/Release/serverdeck.exe
```
The default UI uses generated demo observations only. Separate read-only SSH/OS
custody adapters are tested on disposable localhost but not wired into this UI.
No package executor, live service actions or backend are enabled.
The complete build script compiles the Dart locald sidecar and bundles Isar Core.
Flutter starts/reuses locald via authenticated loopback API. Demo profiles persist
under %LOCALAPPDATA%/ServerDeck/demo, isolated from future production profiles;
synthetic journal/software/metric observations remain fixtures. Restart the app
to reconnect after a locald crash. Do not retry a failed write automatically.
For development flutter run, build the sidecar first and set
SERVERDECK_LOCALD_EXECUTABLE to its absolute Release path. A plain Flutter build
does not package the sidecar; never distribute only serverdeck.exe.
Switch servers, inspect software/state/version, open journal search/priority/unit/
time/details, pause/resume simulation, inspect stale metrics and a disabled install
preview. Test data is not evidence of a real connection or successful install.

M1 prerequisites: disposable SSH host enrollment, native OS custody and safe adapter
tests before any real read. M2 prerequisites: pinned image build, strict privilege
helper and disposable Ubuntu 24.04 systemd fixture explicitly provisioned for tests.
No instruction here authorizes production installations or NetBird changes.
