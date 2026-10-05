# Tasks: Desktop installation and updates

**Input**: [spec](spec.md), [plan](plan.md), [research](research.md), [model](data-model.md), [contract](contracts/updates.md).

## Phase 1: Setup

- [x] T001 Add native runners in macos/ and linux/ and direct crypto/path dependencies in pubspec.yaml (FR-001/002).

## Phase 2: Foundation

- [x] T002 Correct current ABI, macOS data location and packaged library resolution in packages/serverdeck_locald/lib/src/store.dart, discovery.dart and bin/locald.dart (FR-002/003).
- [x] T003 Add version/manifest validation tests in test/app_updates_test.dart: stable `major.minor.patch+build`, size 1..1073741824, sha256 exactly 64 lowercase hexadecimal characters (FR-005/008/012).
- [x] T004 Implement trusted bounded release parsing/network/download service in lib/data/app_updates.dart (FR-004/005/007/008).

## Phase 3: US1 Install (P1)

Independent validation: native package generation and isolated Windows installation/reinstallation/uninstallation, with sidecar and data preservation.

- [x] T005 [US1] Add per-user WiX MSI installer and complete runtime packaging in tools/windows_installer.py, tools/package-windows.ps1 and tools/build-windows.ps1 (FR-001/002/003).
- [x] T006 [US1] Add architecture-specific DMG packaging/signing in tools/package-macos.sh and macos/ entitlements (FR-001/002/003).
- [x] T007 [US1] Add Ubuntu DEB packaging/dependencies/menu in tools/package-linux.sh (FR-001/002/003).
- [x] T008 [US1] Implement isolated install/upgrade/uninstall smoke in tools/test-installer.ps1 (FR-003/012, SC-005).

## Phase 4: US2 Discover updates (P1)

Independent validation: widget injection of current/new/error source and persisted opt-out with theme preservation.

- [x] T009 [US2] Test update controls and settings merge in test/app_updates_widget_test.dart and packages/serverdeck_locald/test/locald_test.dart (FR-004/006/007/012).
- [x] T010 [US2] Add persistent updateAutoCheck bool, default true; merge settings patches in packages/serverdeck_locald/lib/src/server.dart (FR-004).
- [x] T011 [US2] Integrate visible updater and six-hour scheduling in lib/ui/app_updates.dart, lib/ui/app.dart and lib/main.dart (FR-004/006/007).

## Phase 5: US3 Update deliberately (P2)

Independent validation: controlled streaming downloads, digest/size corruption, retry, no installer launch before separate action.

- [x] T012 [US3] Add download/reverification/failure tests in test/app_updates_test.dart (FR-008/009/012).
- [x] T013 [US3] Add progress, retry, verified opening and platform instructions in lib/data/app_updates.dart and lib/ui/app_updates.dart (FR-008/009).

## Phase 6: Release and validation

- [x] T014 Add manifest tooling/tests and native draft-release workflow in tools/release_manifest.py, tools/test_release_manifest.py and .github/workflows/desktop-release.yml (FR-010/012).
- [x] T015 Document installation, release/signing and platform limits in docs/distribution.md and README.md (FR-011).
- [x] T016 Run format/analyze/tests, locald checks, Windows native build/UI/installer and lychee; record executed/pending native/signing checks in specs/003-desktop-distribution/verification.md (FR-011/012, SC-001..005).

## Dependencies and implementation strategy

T001 -> T002 -> T003/T004 foundation. US1 packaging follows foundation. US2 follows checker; US3 follows checker and UI. T014 follows package names; T015/T016 close delivery. MVP: complete Windows package plus manual checking, then Mac/Ubuntu recipes, automatic notification and verified downloads. Platform scripts touch separate files and could run independently; implementation stays sequential in this session. External release publication and native Mac/Ubuntu/manual clean-account signing acceptance are recorded as release gates, never marked as locally run.

## Phase 7: Android scope extension

- [x] T017 Add Android runner/dependencies and production signing in android/app/build.gradle.kts and pubspec.yaml (FR-013).
- [x] T018 Implement app-private in-process local storage in lib/data/mobile_locald.dart and lib/main.dart, Android protection branch in packages/serverdeck_locald/lib/src/server.dart (FR-014).
- [x] T019 Test RuStore update/current/cancel/error states in test/rustore_updates_test.dart (FR-015/016).
- [x] T020 Integrate official RuStore adapter in lib/data/rustore_updates.dart and lib/ui/app_updates.dart (FR-015).
- [x] T021 Keep phone navigation/update controls reachable in lib/ui/app.dart and test/app_updates_widget_test.dart (FR-016).
- [x] T022 Add RuStore APK build in tools/package-android.ps1 and .github/workflows/desktop-release.yml; document console/signing gates in docs/distribution.md (FR-013).
- [x] T023 Build Android APK and test in-process storage in integration_test/android_storage_test.dart; record store-dependent checks in specs/003-desktop-distribution/verification.md (FR-014/016, SC-006).

Android extension depends on T017/T018 foundation and T019 before T020; T021 follows updater control, T022 packaging, T023 verification. This extension is user-authorized and updates the planned scope before implementation.
