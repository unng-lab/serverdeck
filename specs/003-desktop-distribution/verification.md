# Verification: installation and updates

Updated 2026-10-06. Evidence below comes from the isolated feature/app-distribution checkout. Planned native/store checks are separate release gates.

## Executed

- `dart format --output=none --set-exit-if-changed .`: passed, no changes.
- `flutter analyze`: passed, no issues.
- `flutter test`: 34 passed, including 14 updater/phone tests. A controlled unresolved request times out after 25 seconds; a late response cannot overwrite a successful retry. Corrupted/truncated/oversized packages cannot open an installer.
- In packages/serverdeck_locald: `dart analyze` passed; ordinary `dart test` passed all 17 tests, including concurrent preference patches, persistence after reopen and authenticated graceful stop. Native Isar tests share their existing test file to avoid process-global library instance collisions between test isolates.
- `flutter test integration_test/windows_smoke_test.dart -d windows`: 2 passed (native credential fixture and five-view fixture navigation).
- `tools/build-windows.ps1` and `tools/package-windows.ps1 -SkipBuild`: passed. Complete release bundle includes native locald, Isar and app-local VC runtime.
- `tools/test-installer.ps1`: passed. Installed a synthetic older MSI version 0.0.0+0 with the current payload in an isolated temporary path, upgraded to current MSI, repaired it, reopened bundled locald and verified settings after each step, gracefully stopped it and uninstalled. Isar data and sentinel survived. This proves installer upgrade behavior; it is not an end-to-end update from a previously published app. Repeated successfully with the pinned CI compiler WiX 4.0.6. Latest logs: local temporary directory serverdeck-installer-c49762b8f6f94bf796174eb326d2837e.
- `tools/package-android.ps1 -LocalTest`: passed; universal release APK with local debug signing, explicitly named LOCAL-TEST. AGP 8.11.1 / Gradle 8.14.3 / Kotlin 2.2.20 is compatible with the pinned Flutter SDK and RuStore plugin; Flutter warns that future SDKs will require newer tooling.
- `flutter test integration_test/android_storage_test.dart -d emulator-5554`: passed on Android API 36.1 emulator; private Isar and authenticated loopback settings survive service close/reopen and partial patches.
- Installed and started LOCAL-TEST release APK on that emulator; activity launch succeeded, process remained alive and Flutter/AndroidRuntime error logs were empty during the startup check.
- `python tools/test_release_manifest.py`: passed (version, exact hash/size, empty package and missing-platform rejection).
- `lychee "specs/**/*.md"`: passed, 40 links, 0 errors.

## CI and release gates

PR workflow builds Windows x64, Mac Intel/Apple Silicon, Ubuntu amd64 and unsigned Android review APK on native GitHub runners. CI status is reported on the PR, never inferred from the workflow file. Executed CI evidence: run 37376807949 built unsigned Android APK, Ubuntu DEB and Mac arm64 DMG; run 37377157058 also passed compiled Linux locald/Isar/API persistence smoke. Later native runs and Intel Mac results are visible in PR checks.

Not executed locally:

- Native Mac x64/arm64 and Ubuntu packaging/install/upgrade/uninstall: require corresponding hosts. Native CI builds complement, but do not replace, clean-account installation checks.
- Developer ID/notarization/Gatekeeper and Windows Authenticode acceptance: require maintainer signing identities.
- RuStore console enrollment/moderation and an update between two production-signed versions: require console app, matching package/signature, increasing versionCode and authenticated RuStore device. Local adapter tests and emulator storage tests do not claim real store acceptance.

No stable GitHub release or RuStore app was published. MSI and LOCAL-TEST APK are local review artifacts, not production-signed releases.

## Tool availability

Automatic approval review rejected the attempted Inno compiler bootstrap as blocked by policy; it was not installed. Packaging instead uses the already installed WiX 7, whose build and isolated installer checks succeeded. Fresh CI WiX 7 required separate OSMF EULA acceptance; CI instead pins WiX 4.0.6, independently compiled and smoke-tested locally. No new-term acceptance is automated.

Portable packaged-sidecar smoke: `python tools/test_locald_bundle.py build/windows/x64/runner/Release/serverdeck_locald.exe` passed locally. Equivalent native Mac/Linux CI steps exercise the compiled helper without Dart or Flutter runtime commands.
