# Feature Specification: Desktop installation and updates

**Feature Branch**: feature/app-distribution

**Created**: 2026-10-05

**Status**: Approved for implementation by user request

**Input**: «мне нужно устанавливать, обновлять и сообщать об обновлениях приложения; пройди путь спек кит до реализации». Уточнение: «установка должна быть на windows и мак приоритетно; ubuntu desktop тоже хотелось бы».

## User Scenarios & Testing

### User Story 1 - Install ServerDeck (Priority: P1)

A desktop user installs ServerDeck from one downloadable package, launches it from the usual application menu and later removes the program without losing their profiles.

**Why this priority**: A checkout and development tools must not be required on the user's computer.

**Independent Test**: Install into a clean test account on each supported OS; launch all five views and confirm the local storage service is bundled.

**Acceptance Scenarios**:

1. **Given** Windows x64, **When** the user runs the installer, **Then** the complete application and local service are installed for that user with a Start menu shortcut and uninstall entry.
2. **Given** a supported Mac, **When** the user opens the distribution and copies ServerDeck to Applications, **Then** the app and its local service launch without developer tools.
3. **Given** Ubuntu Desktop x64, **When** the user installs the package through the package manager, **Then** ServerDeck appears in the application menu and includes its runtime files.

### User Story 2 - Learn about a new version (Priority: P1)

The user sees their installed version, can check manually, and receives an in-app indication when a newer stable version is available for their OS and architecture.

**Why this priority**: Users should be able to discover updates without checking a website.

**Independent Test**: Feed controlled releases to the checker; verify new, same, older, unavailable platform, offline and unpublished states.

**Acceptance Scenarios**:

1. **Given** a newer stable compatible release, **When** an automatic or manual check completes, **Then** its version and release notes appear with a download action.
2. **Given** an equal or older release, **When** checked, **Then** no upgrade is offered.
3. **Given** no network or a failed source, **When** checked, **Then** an explicit error appears and the application remains usable.
4. **Given** the user disables automatic checks, **When** the app restarts, **Then** the choice persists and manual checks remain available.

### User Story 3 - Update deliberately (Priority: P2)

The user downloads the compatible package, sees progress, and opens the OS installer after verification. Updating retains profiles and settings.

**Why this priority**: Application replacement must remain a visible user decision.

**Independent Test**: Download a controlled package, corrupt it, simulate failure and repeat; verify only a complete matching package can reach the installer opener.

**Acceptance Scenarios**:

1. **Given** a compatible release, **When** Download is selected, **Then** progress appears and a verified package can be opened using a separate action.
2. **Given** incomplete or mismatched content, **When** download finishes or fails, **Then** installer launch is blocked and retry is possible.
3. **Given** an older installed version and existing profiles, **When** the newer package is installed, **Then** local data remains outside the installation folder.
4. **Given** a running application or local service, **When** replacing the package, **Then** instructions and the Windows installer require application/service closure before replacement; no uncertain update is reported as installed.

### Edge Cases

- No stable releases published yet; release exists but lacks a package for this architecture.
- Invalid metadata, untrusted download address, unexpected redirects, excessive metadata/package sizes, timeouts and full disk.
- Repeated checks/download clicks, navigating away while downloading, closing the app mid-download.
- Mac Intel versus Apple Silicon; unsupported OS or architecture.
- User lacks package-install permission; launch association unavailable; Windows files remain locked.
- Published package is unsigned: signing readiness and signed release validation are distinct from local package tests.

## Requirements

### Functional Requirements

- **FR-001**: Deliver complete installation packages for Windows x64 and macOS Intel/Apple Silicon as primary platforms; Ubuntu Desktop x64 as secondary.
- **FR-002**: Include the local service, storage library, fonts and assets; no development runtime is required after installation.
- **FR-003**: Keep profiles, settings and credentials outside application replacement/uninstall paths.
- **FR-004**: Display installed version and support manual checking, automatic checking at startup and every six hours while running, with a persistent opt-out.
- **FR-005**: Offer only a newer stable version with a package matching the OS/architecture; never automatically downgrade or install prereleases.
- **FR-006**: Show version and notes in an in-app notification; allow continuing work without installing.
- **FR-007**: Distinguish checking, current, available, not published, unsupported, downloading, downloaded and error states.
- **FR-008**: Bound network operations; accept packages only from the project's trusted release source and verify exact size and digest before opening them.
- **FR-009**: Require explicit download and separate installer-open actions; do not replace a running app silently or claim installation based on opening a package.
- **FR-010**: Provide reproducible packaging and release automation with a single version source, platform artifacts and update metadata; release publication is a separate maintainer action.
- **FR-011**: Document platform prerequisites, update instructions, signing requirements and verification actually performed.
- **FR-012**: Cover version ordering, malformed metadata, platform filtering, network failure, digest rejection, user actions and setting preservation with automated tests.

### Key Entities

- **Installed version**: version and build of the running client.
- **Release**: stable version, notes and compatible downloadable packages.
- **Package**: platform, architecture, download address, size and integrity digest.
- **Update preference**: whether automatic checking is enabled.
- **Update session**: current check/download state, progress and verified local package.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A user needs one package and no development tools to install each supported desktop build.
- **SC-002**: A manual check leaves checking state within 30 seconds on a controlled unresponsive source.
- **SC-003**: Every corrupted, incomplete, incompatible and older fixture package is refused in automated validation.
- **SC-004**: All five views remain accessible after a failed check, and opt-out survives restart.
- **SC-005**: Upgrade and uninstall tests retain profiles/settings; verification records distinguish local Windows evidence from macOS/Ubuntu CI and manual evidence.

## Assumptions

- This feature distributes ServerDeck itself, not applications managed over SSH.
- Notifications are inside the running application; background OS notifications when the application is closed are out of scope.
- Public stable releases of this repository are the update source. No releases are published without a maintainer action.
- Windows 10/11 x64, macOS 12+ Intel/Apple Silicon and Ubuntu Desktop 24.04 x64 are initial packaging targets.
- macOS uses an Applications drag-and-drop distribution; Ubuntu uses its package manager. These remain user-controlled updates.
- Existing non-Windows SSH credential storage limitations are documented separately; this feature does not extend remote-server management capabilities.
- Signing identities and notarization accounts are supplied by maintainers for public releases. Native macOS builds require a Mac, Linux builds require Linux.

## Clarifications

### Session 2026-10-05

- Q: Which application is being installed? A: ServerDeck itself, Windows and Mac first, Ubuntu Desktop desired.

## Scope extension: Android / RuStore (2026-10-05)

User added Android devices, distribution through RuStore.

### User Story 4 - Install and update through RuStore (Priority: P2)

Install ServerDeck from RuStore on Android 7+; see update availability in the app and choose to download and install through RuStore. User data stays in private application storage across upgrades.

**Independent Test**: Android APK builds with production signing configured separately; emulator validates local storage and narrow-screen controls; fake RuStore adapter validates status/cancel/error flows. Real update acceptance requires a moderated console app, same package/signature, increased versionCode and authenticated RuStore device.

**Acceptance Scenarios**: (1) RuStore reports an update -> in-app notification and explicit download; (2) downloaded update -> separate install action; (3) RuStore missing/unauthenticated/unpublished -> actionable status and official store page, never GitHub APK sideload; (4) app upgrade -> private profiles/settings retained.

- **FR-013**: Supply Android 7+ APK for RuStore with stable package identity, production-signing configuration and increasing version code from the shared version source.
- **FR-014**: Android uses its private local storage service within the application lifetime; no desktop executable or desktop library layout is required.
- **FR-015**: Android checks, downloads and installs through RuStore with explicit user actions and errors/cancellation handling; provide official store-page fallback without installing arbitrary APKs.
- **FR-016**: Update controls and navigation remain reachable on a 400x800 phone viewport; Android build and store-dependent validation are recorded separately.

**SC-006**: Android APK compiles; narrow-screen widget tests pass; controlled store states never silently install or report completion before store confirmation.

Android notifications remain in-app. Store publication, credentials, review and device enrollment are release prerequisites, not assumed complete. Existing remote credential support on non-Windows platforms is a separate capability.
