# Quickstart and validation

1. Run `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`; run `dart test` and `dart analyze` in packages/serverdeck_locald. Check links using `lychee "specs/**/*.md"`.
2. Windows: install WiX Toolset 7, run `tools/package-windows.ps1`; resulting output/dist/ServerDeck-<version>-windows-x64.msi contains Flutter bundle, sidecar, Isar and VC runtime. Run `tools/test-installer.ps1` for isolated install/older-version upgrade/repair/uninstall checks.
3. Mac: on each native architecture run `bash tools/package-macos.sh`; output/dist DMG. Open, copy to Applications, launch. Signing environment and notarization instructions: [distribution guide](../../docs/distribution.md).
4. Ubuntu 24.04 amd64: install Flutter Linux build prerequisites, run `bash tools/package-linux.sh`, then `sudo apt install ./output/dist/ServerDeck-<version>-linux-x64.deb`. Launch from menu, check sidecar and views.
5. Open the app's update control; check manually, disable automatic checks, restart and verify opt-out. Controlled release and corruption scenarios run in test/app_updates_test.dart and test/app_updates_widget_test.dart without production network or installations.
6. Upgrade using a newer package on an isolated account with profiles/settings; confirm preservation. macOS/Ubuntu checks need native hosts; record pending checks separately in [verification](../003-desktop-distribution/verification.md).
7. Release tooling: `python tools/release_manifest.py --assets output/dist --output output/dist/serverdeck-update.json`; workflow assembles native artifacts into a draft release. Review signed packages and native validation before publishing that draft.


8. Android: configure production signing or use tools/package-android.ps1 -LocalTest for review. Run `flutter test integration_test/android_storage_test.dart -d <android-device>`; check real production updates on a RuStore device after console setup.
