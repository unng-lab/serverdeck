# Service/source name search — 2026-11-04

## Confirmed scope

User clarification: «По названию systemd-сервиса в Журналах». C05 filters discovered full unit names and configured source name/target (including file sources), before any selection. Query is literal, trimmed, case-insensitive and local-only. Selection/discovery retain it; profile/revision/owner reset it. Selected source, message contents, retention/detail and message pagination are independent of the filter.

T038–T040 describe the earlier completed but rejected message-search interpretation. User correction supersedes that behavior through T041–T043; completed task history is retained. No message-text filtering remains in the implementation.

## Specification readiness

Independent service_search_spec_review, fork_turns=none, read-only: no findings, ready. Checked FR-515/AC-515→plan/contract→tasks and existing C05/owner feasibility. Global lychee before implementation exit0:258total252OK0errors6excluded2redirects. Current constitution is3.0.0; other storage/006 changes outside this scope.

## Actual verification

- Targeted `flutter test test/journals/journal_search_test.dart`: exit0,7functional fake tests. Unit/name/Cyrillic/case/literal/filepath, clear/empty/no-results, source selection and record paging preservation, discovery refresh and server/revision/owner reset/retired callbacks.
- `dart format --output=none --set-exit-if-changed .`: exit0,380files0changes.
- `flutter analyze`: exit0,No issues found.
- `flutter test`: exit0,731passed; log tmp/journal-service-search-all.log. Includes concurrent working-copy changes, not isolated005.
- `tools/check-test-boundaries.ps1`: exit0,90files reported.
- Exact global `lychee "specs/**/*.md"`: retry exit0,258total252OK0errors6excluded2redirects (tmp/journal-service-search-links-retry.log). Prior run had2transient freedesktop.org timeouts, not claimed passed.

Unit/fake/static only; no real SSH/Isar/product/integration/design-screen tests. No shared component/schema/owner/transport changes for this refinement.

## Code review

Independent service_search_code_review (fresh fork_turns=none, read-only) completed: «Замечаний не найдено. Готовность к реализации: готов». Reviewer checked current source/tests/contract/plan/task chain and actual full-test/lychee logs. No unresolved confirmed findings. Corrected service/source search accepted in unit/fake/static scope. T041–T043 complete; application sources unchanged after completed review. Final evidence/status-only documentation edits rechecked with lychee.
