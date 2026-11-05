# Validation guide — 006

## Prerequisites and commands

Windows x64, pinned Flutter/Dart, MSVC/CMake/Python per002. Developer build needs no
source or signing secret. Publishable build additionally needs update policy and
operator P256 key per [release contract](contracts/releases.md), not user runtime inputs.
Production distribution uses only [GitHub Releases](contracts/github-releases.md):
latest API and setup/catalog assets of unng-lab/serverdeck. Descriptions/changelog
remain in the release. No separate update server or end-user GitHub credentials.
Operator preparation: [release artifacts and signing](release-preparation.md).
No command below publishes/deploys or runs installed product.

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
./tools/check-test-boundaries.ps1
python -m unittest discover -s tools/tests -p 'test_*.py'
./tools/test-release.ps1
lychee "specs/**/*.md"
./tools/build-release.ps1
```

`test-release.ps1` runs native unit-labeled fixtures, not historical integration helpers.
Build should emit full developer ServerDeckSetup.exe, exact embedded ServerDeck.exe,
matching resource hashes, x64/asInvoker and OS-only bootstrap imports. Developer missing
policy is explicitly UPDATE_NOT_CONFIGURED, not a configured production release.

## Unit acceptance

- US1: fresh/equal/newer/older/cancel, permissions/space, registration failure/retry.
- US2: catalog signature/key/version/privacy, legacy1 expiry versus production2
  static metadata, GitHub API/assets/target validation, persisted24h schedule/manual check.
- US3: exact consent/revoke/change/offline/cancel/late replies and late ACK without
  parent permit, synthetic handoff failures,
  ReplaceFile partial errors and recovery before host/store callback.
- US4: owner-running refusal, bounded partial removal/retry, retained data/secrets/MCP path.
- UI texts/actions/state only, no layout/golden/overflow checks.

Ports for network/process/registry/shortcuts are fake; native file tests use synthetic
temporary trees and data sentinels. No application/Explorer/session launch, live Isar,
VM/e2e/smoke/process-kill or screen design gate. Results support isolated behavior and
static composition, not actual installation/integration on clean Windows.
