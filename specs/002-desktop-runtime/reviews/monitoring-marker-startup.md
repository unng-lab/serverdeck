# First startup with native monitoring marker — 2026-11-06

## Cause and correction

The real user data directory contained only native monitoring-run-v1.json and no
CURRENT/store. DesktopWorkspace begins monitoring before opening storage; the
preflight interpreted that owned marker as an unpublished database. Both first
publication and live-owner publication retry now recognize only the exact
ordinary, non-link, bounded native version1 running/clean file. Its bytes are
preserved. Unknown files, malformed/name/type lookalikes, unrelated orphan stores
and selected database validation retain their guards. No migration, reset, format
bump, source-data copy or error-screen suppression is introduced.

## Actual checks

- Targeted recovery/publication units: exit0,16passed (tmp/storage-marker-targeted.log).
- Exact dart format --output=none --set-exit-if-changed .: exit0,387files0changes.
- flutter analyze: exit0,No issues found (tmp/marker-analyze.log).
- flutter test: exit0,767passed (tmp/marker-flutter-test.log).
- tools/check-test-boundaries.ps1: exit0,94files.
- Global lychee: exit0,281total275OK0errors6excluded2redirects (tmp/marker-links.log).
- tools/build-release.ps1: exit0 (tmp/marker-release-build.log).

Independent storage_marker_startup_review (fresh fork_turns=none, read-only): no
findings, ready within T048/T049 scope. Reviewer inspected002/004 chain and actual
analyze/test/link logs. No unresolved confirmed findings. Sources unchanged after
review; task/evidence completion is documentation only.

User-authorized local replacement used ordinary Explorer, retaining user data.
The installed application then opened its normal server screen, showing
«Серверов пока нет», «Добавить сервер» and «Приложение готово» instead of storage
blocked. This is separate local operational evidence; unit tests use synthetic
files/fake backend and do not load real Isar or launch product/Explorer processes.
No clean-OS, integration/e2e or feature-layout acceptance is claimed.

## Patch 0.2.1 prepublication checks — 2026-11-07

User requested committing this existing startup fix and releasing0.2.1. Storage recognizes only the exact native version1 running/clean bounded non-link marker, preserving it and all existing orphan/manifest protections. No store format/schema reset or unrelated application changes.

Current actual checks after version0.2.1:

- dart format --output=none --set-exit-if-changed .: exit0,496files0changes.
- flutter analyze: exit0,no issues.
- flutter test --reporter expanded: exit0,865passed (.local/patch-0.2.1-unit.log).
- tools/check-test-boundaries.ps1 explicit TestRoot: exit0,111Dartfiles.
- lychee specs/**/*.md: exit0,348total342OK0errors6excluded2redirects.
- python tools/check-ssh-vendor.py: exit0,99files/fourpolicy sources; all source hashes plus reverse patch check enforced.
- tools/build-release.ps1 -Profile publishable -UpdatePolicy release/update-policy.json: exit0 (.local/patch-0.2.1-build.log); compiled Windows app/bootstrap/setup and audited release artifacts. Installer SHA256 AD84D919642B0BFD6E1A245AB525021B3659C468884530DCEE8BBE6835C0670F.

The v0.2.0 GitHub build failed on source/provenance mismatch before compilation. This patch refreshes the SSH manifest and complete reproducible policy patch from the exact4.1.0 archive, whose pinned SHA256 was verified. The existing hash/allowlist/LF/reverse-patch checker is unchanged. Existing reviewed library code is unchanged; the manifest now includes owned PTY and current documentation. No release-process tests, product launch, real Isar or integration checks performed. CI publication/signing still pending; a successful local publishable build is not a published release. Fresh independent review follows these checks.

Independent read-only patch reviewer review_patch_021 found one P2: utf8.decode strips BOM, so BOM-prefixed running/clean did not match the exact-byte contract. T051 fixes this with raw byte comparison and both-guard regression cases. Reviewer independently downloaded the exact pinned SSH archive and verified pristine hashes, regenerated patch reproduction/current sources, and existing checker success; no other confirmed findings. Fresh checks/build/review required after the byte-comparison fix.

After T051: raw bytes are compared directly with the two native ASCII encodings, with no UTF8 decoder normalization. Both preflight and pending-publication reject BOM-prefixed running/clean fixtures and preserve their original bytes. Targeted synthetic storage tests:18passed. Rechecks all exit0: format496files0changes; analyze noissues; full unit867passed; boundaries111files; lychee348total342OK0errors6excluded2redirects; SSH provenance99files/fourpolicy sources; full publishable build. Final installer SHA2566693E8962369FF714AAC15F7D1764F44D2EB1A4A6633418D27E921BB8F98842F (.local/patch-0.2.1-build.log). Fresh independent closure review pending; no runtime/process tests or CI signing/publication claimed.

Fresh independent closure reviewer review_patch_021_fixed: no findings, ready within patch0.2.1 prepublication scope. Reviewer independently ran targeted storage18tests and SSH provenance99files/fourpolicy+reversecheck, and compared all patched/added SSH hashes with HEAD (not just working files): match. Full unit867passed and final build SHA confirmed from logs. No confirmed unresolved defects/mandatory gaps. T045/T051 complete; T050 awaits the requested commit/tag and actual CI release publication. No application source changes after these successful checks and this review.

## Published patch 0.2.1 — 2026-11-07

Commit9c1b1f5b2ca0ca06d8ad246afc276d6b5ecd5569 and annotated tagv0.2.1 were pushed atomically toorigin/main/tag. GitHub build run42301317976 completed success; unit run42301317821 completed success. Public stable releasev0.2.1 was published2026-11-07 01:07:55 Europe/Moscow (2026-11-06T22:07:55Z), not draft/prerelease. Confirmed release assets: ServerDeckSetup.exe58430464bytes and serverdeck-update-catalog.txt2111bytes. Release URL: https://github.com/unng-lab/serverdeck/releases/tag/v0.2.1 . Publication used only the tag-triggered workflow; no manual release or tag rewrite. T050 complete. This receipt is documentation only; source and tagged installer remain unchanged. Unrelated parallel008 work was excluded.
