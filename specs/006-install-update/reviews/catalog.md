# Catalog/trust foundation review — T004 / T032

**Date**: 2026-11-04. Partial implementation milestone; full feature is NOT complete.

## Implemented scope

`native/include/release_catalog.h`, `native/install/release_catalog.cpp`,
`native/tests/release_catalog_test.cpp`, native CMake library/link/unit wiring.
Canonical numeric versions, bounded policy/catalog parser, actual Windows CNG P256
verification, time/size/URL/host constraints, numeric latest-compatible selection,
exact consent identity, revoked/changed release outcomes. No source/network/app
integration, setup, file transaction, UI or production source claimed in this milestone.

## Independent review loop

- `review_006_catalog_code` (fork_turns=none/read-only): one confirmed P2 — Host
  accepted alternate IPv4 spelling `0x7f.0.0.1`. Reviewer demonstrated Windows
  numeric interpretation with local synthetic URL/IP API calls, without network.
- Fix: AI_NUMERICHOST classification, shared by policy and URL validation; no DNS
  request. Added hexadecimal/octal alias regression fixtures. Tracked append-only T032.
- `review_006_catalog_fresh` (fork_turns=none/read-only), full narrow code and related
  contracts inspected: «Замечаний не найдено». T004 matches contracts; prior finding
  closed; ready to continue other implementation tasks. Whole feature remains open.

## Actual checks after latest code fix

- `./tools/test-release.ps1`: exit0; /W4 /WX native build;11/11 unit tests passed,
  including release_catalog. No historical integration/product/VM/process-kill run.
- `lychee "specs/**/*.md"`: exit0;258total252OK0errors6excluded2redirects.
- Flutter code was not changed by this milestone; format/analyze/flutter tests not run
  or claimed. Concurrent dirty storage/monitoring/journal changes not part of this scope.

T006 retains its installation-test work, T007 retains host/build graph work; neither
is marked complete merely because the catalog fixture is connected and green.
