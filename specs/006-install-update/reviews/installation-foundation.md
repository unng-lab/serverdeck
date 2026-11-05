# Installation foundation milestone — T005/T006/T033–035

**Date**: 2026-11-04. Foundation only; full installation/update remains incomplete.

## Implemented and checked

`native/include/installation.h`, `native/install/installation.cpp`,
`native/tests/installation_test.cpp`, native CMake source/unit wiring. Bounded typed
metadata/journal/recovery codecs, canonical SID/version/identity validation, pure
recovery classification, Known Folders paths, maintenance→owner HANDLE leases,
allowlisted file IO/streaming hashing/copy/publish and bounded staging lifecycle.

Test-first: initial installation_test target failed because installation.h was absent.
Then implementation and synthetic/native adapter checks were added. Tests use owned
temporary trees, real isolated file APIs and synthetic records; no app launch,
real registration, store or process-kill. Data/foreign-file sentinels are checked.

## Independent review/fix loop

1. `review_006_install_foundation`: UUID temp siblings had no bounded orphan policy.
   Fixed via a single protected, lease-serialized .stage slot and ownership record;
   known orphan/retry/uninstall/foreign/reparse fixtures, tracked T033.
2. `review_006_install_foundation_fresh`: oversized/reparse owner/payload returned
   STORAGE_IO instead of RECOVERY_REQUIRED. Explicit structural classification added,
   exact-code and unchanged-bytes fixtures; true read sharing error remains STORAGE_IO.
   Tracked T034. An intermediate extended-prefix ancestor walk failed a unit check;
   normalized prefixes and reran the complete native gate successfully.
3. `review_006_install_foundation_ready`: .stage.lock reparse needed the same early
   classification. Added pre-Acquire checks for write/cleanup and no-deletion junction
   fixture, tracked T035.
4. `review_006_install_foundation_final`: «Замечаний не найдено»; implemented foundation
   ready to continue, T033–035 closed by actual source and tests. No overall feature
   completion or clean-OS integration claim. All reviews read-only/fork_turns=none.

## Actual final checks for this scope

- `./tools/test-release.ps1`: exit0, /W4 /WX native build,12/12 unit tests passed.
- `lychee "specs/**/*.md"`: exit0,258total252OK0errors6excluded2redirects.
  One earlier run had two external systemd URL timeouts; a normal repeat passed.
- No Flutter code changed by this milestone, no Flutter checks claimed.

T007 host/build wiring, full transaction executor/recovery execution, registry/shortcuts,
setup, network, handoff and UI are still open. T006 completes foundational fixtures;
story-specific fault/recovery tests remain T021/T024 and are not implied by this report.
