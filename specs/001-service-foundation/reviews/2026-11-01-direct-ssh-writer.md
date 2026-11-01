# Independent review: atomic direct SSH dispatch writer

Date: 2026-11-01. Reviewers use fresh context and do not edit files.

## Round 1 — direct_ssh_writer_review_1

Найдено 1 замечание, которое стоит исправить.

Готовность к реализации: не готов — повторная проверка policy отсутствует перед завершением native transaction.

Scope: four files in `.local/direct-ssh-writer-review-scope.txt` plus their governing contract/dependencies and the saved records-review report. The new method is a driver-only local intent writer; actual native/session gate acquisition, driver integration and remote execution remain open work.

P1: `_commitTrustedDelta` checked writer policy before transaction and at entry, then awaited native reads/puts and ended with `_grantLive` alone. Grant/delegation/permit/proof could expire during a held put while job and event still committed. Required closure: revalidate after the final asynchronous row operation inside the same transaction; failure must roll back all rows. Contract bounded permit and section9, FR-SSH-004/006/011, AC-SSH-03/07/11; remediation T436.

Evidence inspected by reviewer: `.local/direct-ssh-writer-full-r1.exit=0`, format434/0changes, 813Dart tests+16RAM groups and analyses passed. Link check `.local/direct-ssh-records-review-links.exit=0`,1581OK/0errors/2excluded. Reviewer did not rerun tests or create a reproduction. Subsequent held-write regressions reproduced all four success-on-expiry failures in `.local/direct-ssh-writer-commit-red.log` before the fix.

Fix: writer policy now repeats inside transaction after the last awaited get/put, before transaction completion. Round1 is retained as a non-clean historical result; closure is recorded in round2 below.

No native/SSH/systemd/APT/install/build execution is claimed. The complete migration remains unfinished.

## Round 2 — direct_ssh_writer_review_2

Замечаний не найдено.

Готовность к реализации: готов — только для локального durable writer и определяющих его решений, не для полной миграции.

Fresh read-only review inspected the five-file scope (now including automation_delta.dart), exact baseline changes, governing artifacts and transaction dependencies. It confirmed the final policy check after all awaited row operations, rollback of job+event together, published snapshot restoration after confirmed rollback and conservative blocking for uncertain storage outcomes. Generic delta callers (authority mutations, job admission/control and progress) were also checked for compatibility. No unresolved confirmed finding or mandatory decision gap was found in this scope. T436 is closed.

Evidence inspected, not rerun by reviewer: `.local/direct-ssh-writer-full-r2.exit=0`,434files/0format changes, root86+engine651+MCP15+protocol57+Windows8=817Dart tests,16RAM bundle groups and successful analyses. `.local/direct-ssh-writer-links-r2.exit=0`,1581OK/0errors/2excluded. Four held-put failures in the prior red log were confirmed. Native/session gate acquisition, baseline proof, through-first-SSH gating, dispatch advancement and verified host results remain open driver implementation tasks; T424/T434/T435 are not closed as a whole.
