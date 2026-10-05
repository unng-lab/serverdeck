# Research: Desktop distribution

## Packaging

Decision: WiX per-user MSI, two architecture-specific macOS DMGs, Ubuntu amd64 DEB.
Rationale: established native installation UX, complete Flutter bundle plus native Dart sidecar, explicit upgrades and no package-manager implementation.
Alternatives: Store-only MSIX/App Store requires accounts; a custom updater adds replacement and rollback complexity; AppImage adds desktop integration work.
Sources: [Flutter Windows](https://docs.flutter.dev/deployment/windows), [Flutter macOS](https://docs.flutter.dev/deployment/macos), [WiX Toolset 7](https://docs.firegiant.com/wix/schema/wxs/package/), [Debian dependencies](https://www.debian.org/doc/debian-policy/ch-sharedlibs.html).

## Sidecar portability

Decision: use Abi.current(), Linux bundle/lib/libisar.so, macOS Contents/Frameworks/libisar.dylib, macOS Application Support data directory; retain an existing legacy data directory.
Rationale: inspected Isar 3.3.2 cache: Linux library x86_64 only; Mac library universal x64/arm64. Dart helper compiled on a matching architecture runner. Existing Windows Credential Manager implementation remains Windows-only; packaging does not claim new SSH support.
Sources: local store.dart, discovery.dart, cached Isar podspec/CMake; [Dart native compilation](https://dart.dev/tools/dart-compile).

## Updates and integrity

Decision: GitHub latest stable release plus serverdeck-update.json metadata; repository-constrained HTTPS URLs, bounded streaming SHA-256 download, exact size verification, separate open-installer action. Redirects revalidated per hop; only GitHub release CDN allowed after a trusted initial URL.
Rationale: stable source matches existing remote; no credentials/host metadata transmitted. Hash verifies transfer against trusted HTTPS metadata, not independent publisher authenticity. Signed installers are a separate release trust control.
Alternatives: arbitrary configured URLs weaken source trust; silently replacing files risks running sidecar/storage damage.
Source: [GitHub releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release).

## Release trust

Decision: local builds may be unsigned for review; public Mac distributions require Developer ID signing/hardened runtime/notarization; Windows public installers should be Authenticode signed. Build workflow creates draft assets, never silently publishes a stable release.
Rationale: signing needs maintainer identities, cannot be truthfully simulated. Installer smoke uses an isolated path and preserves application data.
Sources: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Windows Restart Manager](https://learn.microsoft.com/en-us/windows/win32/msi/using-windows-installer-with-restart-manager).

## Android research extension

Decision: Android in-process locald/Isar, signed universal APK through RuStore, official Flutter update SDK and store page fallback.
Rationale: no supported Android native Dart helper target; Android private sandbox provides directory protection. RuStore handles package verification/installation and requires same package/signature with increasing version code.
Alternatives: arbitrary APK downloading is inconsistent with requested store distribution; requiring a numeric store ID unnecessary (official links accept packageName).
Sources: [RuStore publication](https://www.rustore.ru/help/developers/publishing-and-verifying-apps/app-publication), [Flutter updates SDK](https://www.rustore.ru/help/sdk/updates/flutter/10-5-3), [Store links](https://www.rustore.ru/help/sdk/rustore-deeplinks), [Android executable restrictions](https://developer.android.com/about/versions/10/behavior-changes-10).


Packaging refinement: Windows uses the already available WiX 7 to produce MSI; attempted Inno compiler bootstrap was rejected, so no new compiler was installed. MSI Restart Manager handles files in use; updater stops locald through authenticated service/stop before invoking msiexec. AppVersion includes build; Windows direct installer must also raise major/minor/patch for public release upgrades because MSI comparison ignores the fourth field. No silent app-driven downgrade is offered. Android pins AGP 8.11.1 / Gradle 8.14.3 / Kotlin 2.2.20: official RuStore Flutter 10.5.3 plugin failed on template AGP 9.1 built-in Kotlin. [AGP compatibility](https://developer.android.com/build/releases/agp-8-11-0-release-notes).
