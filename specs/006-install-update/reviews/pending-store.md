# Atomic pending store — T050 / T051

Date: 2026-11-04. Pending persistence component; service/channel/apply wiring remains open.

## Design and implementation

The installation contract now defines two fixed pending slots and one atomic active
consent pointer. This replaces the earlier single setup/catalog pair before any pending
producer was wired into the application. It preserves an existing ready update while
a replacement is prepared, without copying a third setup or holding maintenance during
network IO. SDPENDING001 records bind SID/UUID/slot/version, app/setup identities and
the exact signed catalog hash/verification time. Full Release reconstruction comes from
that original envelope; it does not substitute for fresh network validation at apply.

`native/include/pending_update.h`, `native/install/pending_update.cpp` implement bounded
codecs, maintenance-protected reads, inactive-slot reclaim, streamed preparation,
resource-validator invocation and consent-last publication. The mandatory synchronous
commit callback is the future service's cancellation/generation/ready-snapshot gate.
GUI-owner-only download authority and worker drain before owner release remain explicit
caller obligations, not responsibilities silently delegated to arbitrary UI paths.

Files adds only fixed slot names, a separate `.download` staging family and StreamDownload.
Short preferences/metadata writes continue through `.stage`. Download publication uses
create-only rename; an unexpected target appearing during streaming is preserved. Nested
parents are created individually with the existing security checks. Cleanup covers both
bounded staging families while retaining unknown bytes on ownership failure.

## Independent review loop

All reviewers were fresh `fork_turns=none`, read AGENTS/artifacts/source directly,
did not modify files and did not declare the whole feature complete.

1. `review_pending_design`: amendment has no unresolved mandatory decisions; ready to
   implement T050. Code had not yet been changed at that point.
2. `review_pending_store`: one confirmed regression. Executor checked the new download
   staging area only during post-commit cleanup, allowing malformed staging to turn an
   initially valid installation into a journal-blocked state. T051 records the fix.
3. `review_pending_store_fresh`: «Замечаний не найдено». Apply/Repair now validate/reclaim
   both stages before any new mutation. Four fixtures cover malformed owner/unowned
   payload × apply/repair and preserve exact canonical files, metadata/proof/registration,
   journal absence and unknown bytes. No unresolved confirmed findings in this scope.

## Actual validation

- Native unit gate exit0:16/16 targets passed,10.80s. Pending fixtures generate temporary
  P256 catalogs and fake HTTP/setup-validation ports, use only synthetic temp files,
  and model interruption by throwing a non-std fixture value. They exercise owner/setup/
  catalog/verified/committed checkpoints, old/new readiness, replacement/retry, active
  cleanup refusal, preferences during streaming, cancellation during body/before commit,
  expired/mismatched catalogs, unexpected-target preservation and data sentinels.
- Initial pending test failed with STORAGE_IO:3 because slot directories introduced a
  second nesting level; secure parent creation was corrected before successful gates.
- Windows host release compilation exit0 after T051,5.8s; previous build of the new store
  and staging source also passed,21.8s.
- Lychee after design/fix tasks:259total253OK0errors6excluded2redirects.
- No Dart source changed in this milestone; previous754 Flutter tests and format/analyze
  results retain their earlier scope and were not rerun or presented as new evidence.

No real network, product/Explorer launch, registry change, integration/e2e/VM/process-kill
test, publication or deployment occurred. These unit/static/build checks do not prove
installation/update integration on a clean OS. T017/T013/T015/T028, bootstrap handoff,
consumption/tombstone, uninstall and final verification remain open with original scope.
