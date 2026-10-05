# Implementation Plan: Desktop installation and updates

**Branch**: feature/app-distribution | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)

## Summary

Package the existing local-first client and sidecar for Windows/macOS first and Ubuntu second. Check stable GitHub releases using a small versioned manifest. Download, verify and open a native installer only after explicit user actions.

## Technical Context

**Language/Version**: Flutter 3.47.0 / Dart 3.13.0; PowerShell, Bash, Python 3 for release tooling.
**Primary Dependencies**: existing Flutter and Isar Community 3.3.2; crypto 3.0.7, path 1.9.1; WiX Toolset 7 on Windows; hdiutil on macOS; dpkg-deb on Ubuntu.
**Storage**: update preference in existing locald settings; temporary verified package outside installation/data folders.
**Testing**: Flutter unit/widget/native Windows tests, locald tests, Python release-tool tests, isolated installer smoke, CI native packaging on each OS.
**Target Platform**: Windows 10/11 x64, macOS 12+ x64/arm64, Ubuntu Desktop 24.04 amd64.
**Project Type**: desktop app and local sidecar.
**Performance Goals**: check timeout 25 seconds; metadata <=256 KiB; package <=1 GiB, total download timeout 30 minutes.
**Constraints**: HTTPS trusted GitHub URLs only; no telemetry or host data in requests; no automatic replacement, downgrade, prerelease, or remote writes. Native builds need corresponding hosts.
**Scale/Scope**: one stable release stream, four OS/architecture packages, one updater UI.

## Constitution Check

Pre-research and post-design: PASS. Distribution has no SSH host writes. Data/secret custody remains outside packages. UI only reports verified download, never successful installation. Existing job authority unchanged. Use current ABI and library layout for sidecar. Mac/Linux credential support remains a documented pre-existing limitation. No claim of native platform validation without execution.

## Project Structure

Documentation: spec.md, research.md, data-model.md, contracts/updates.md, quickstart.md, tasks.md and verification.md in this directory.

Source: lib/data/app_updates.dart, lib/ui/app_updates.dart, lib/ui/app.dart, lib/main.dart; packages/serverdeck_locald/lib/src/{discovery,store,server}.dart; macos/ and linux/ Flutter runners; tools/windows_installer.py; tools/package-{windows.ps1,macos.sh,linux.sh}; tools/release_manifest.py; .github/workflows/desktop-release.yml; test/app_updates_test.dart, test/app_updates_widget_test.dart, tools/test_release_manifest.py, tools/test-installer.ps1.

**Structure Decision**: reuse the app shell and locald preferences. Native OS tools create standard packages; updater delegates installation to them. No custom binary replacement or new cloud service.

## Delivery and release gates

Build packages on native runners and collect a manifest using pubspec.yaml as the sole version source. A tag/manual workflow may create a draft release; publishing the draft remains a maintainer action. Supply Windows signing and macOS Developer ID/notarization for public distribution, validate on clean accounts, then publish. Repository contains working local packaging without demanding signing secrets for tests.

## Android extension

Add Android Flutter runner, APK signing from ignored key.properties, Android SDK >=24, INTERNET and loopback cleartext policy. Use path_provider for app-private directory, run LocaldServer in process (no desktop helper), skip chmod inside Android sandbox and load bundled libisar.so by soname. PackageInfo supplies actual installed version on all platforms. Android updater uses official flutter_rustore_update 10.5.3, separate check/download/completeUpdateFlexible, lifecycle recheck, SDK state stream, and url_launcher for official package-name store page. No GitHub APK update source. Check on startup/six-hour timer only if opted in. Native runtime and moderation-dependent store acceptance need real device/emulator evidence.

New source: lib/data/mobile_locald.dart, lib/data/rustore_updates.dart, android/ runner/signing configuration, tools/package-android.ps1, test/rustore_updates_test.dart, integration_test/android_storage_test.dart. Desktop update interface remains independently testable. Mobile viewport preserves existing desktop screens in an explicitly scrollable workspace, while header/navigation/update controls remain accessible; full mobile screen redesign is outside this distribution increment.
