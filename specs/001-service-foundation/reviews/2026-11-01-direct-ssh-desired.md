# Independent review: compound desired state

Date: 2026-11-01. Reviewer: direct_ssh_desired_review_1, fresh context, read-only.

Замечаний не найдено.

Готовность к реализации: готов — для ограниченного инкремента публикации,
восстановления и сравнения desired state. Вся T425 и миграция direct SSH
остаются незавершёнными.

## Scope and result

Five files in `.local/direct-ssh-compound-desired-review-scope.txt`; four existing
files compared with originals in `.local/direct-ssh-compound-desired-before/`,
one new test file. Applicable AGENTS.md and related compiler/protocol/managed
observation/job admission sources plus001/006/021 artifacts were inspected.

- `automation/configuration.dart`: compound settings use file comparison;
  service intent includes compound activation. The last ordered service action
  determines final state; enabled intent is independent. Historical two-effect
  plans are compared without rewriting their bytes or digests.
- `storage/automation_job_progress.dart`: successful compound publication includes
  both settings and service desired rows in the same transaction, only after all
  declared checks pass.
- `automation/snapshot.dart`: retained graph validates the same resource set and
  retains succeeded-job/immutable-plan/identity checks.
- `test/support/actual_plan_fixture.dart`: optional structural parameters and
  baselines preserve previous defaults.
- `test/automation/direct_ssh_desired_test.dart`:14 RAM cases cover both products,
  direct and historical formats, missing each mandatory check, one-transaction
  publication, reopen, matched/drift/stale/denied comparison, failed/unknown
  preservation and explicit stop after configuration.

The reviewer traced AC-SSH-12/FR-SSH → direct contract/model → T425 → compound
compiler/protocol → atomic publication/retained graph → RAM acceptance scenarios.
No missing mandatory product or architecture decision was found for this scope.
No new authority, credentials lifecycle, wire protocol, runtime prerequisite or
schema3 migration is introduced. Structural storage input is not evidence of
actual host postchecks or authorization; those remain the admission/driver's duty.

## Actual evidence and limits

Reviewer inspected logs without rerunning:
`.local/direct-ssh-compound-desired-full-r1.exit=0`, format443files/0changes,
successful analyses,86 Flutter+695 engine+15 MCP+57 protocol+8 Windows =861 Dart
tests and16 RAM bundle groups. `.local/direct-ssh-compound-desired-links-r1.exit=0`,
1581 OK/0errors/2excluded. Formatter's resolution warnings for historical
`work/isar-encryption-implementation` do not establish analysis of that directory.

Meaningful red evidence: `direct-ssh-compound-desired-red` failed for missing
service desired rows in both products; `direct-ssh-compound-comparison-red`
failed with missing compound comparison; `direct-ssh-compound-order-red` failed
four final-stop comparisons before the ordered-state fix. These logs and exit1
files are under `.local/`.

No real SSH/SQL/systemd/APT, native storage, UI/build/container execution was
performed or inferred from RAM tests. Actual direct plan/job/worker/provenance
integration remains open, including the remaining work in T425. This review
closes only the bounded desired-state increment.
