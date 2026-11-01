# Independent review: direct SSH durable records and bindings

Date: 2026-11-01. Reviewer: direct_ssh_records_review_1 (fresh context, read-only).

Замечаний не найдено.

Готовность к реализации: готов — для пассивного increment и определяющих его решений. Полная миграция direct SSH не завершена.

## Scope

Exact ten-file scope is recorded in `.local/direct-ssh-records-review-scope.txt`: protocol DirectSshDispatch, optional Job metadata/transitions, SDSSH1 codec, canonical bindings, retained graph validation and corresponding RAM tests/fixture. Existing-file changes were compared with the local source baseline. Root AGENTS.md was read; no nested instructions were found.

Reviewed governing artifacts: spec.md, plan.md, tasks.md, direct SSH data model/research and contracts/direct-ssh.md (host record encoding and section 9), with related 006/021 requirements. The requirement/design/contract/task/acceptance chain for FR-SSH-004/006/011/014 and AC-SSH-03/07/11 was checked. No mandatory decision gap was found in this scope.

## Evidence and limits

Actual full check run: `.local/direct-ssh-records-full-r2.exit=0`, corresponding log: 432 files formatted with zero changes; root Flutter analyze/test and four package analyze/test suites passed. Counts: root86, engine635, MCP15, protocol57, Windows8 (801 Dart tests), plus16 RAM bundle groups. Link evidence: `.local/direct-ssh-dispatch-spec-links-r2.exit=0`, 1581 OK /0 errors /2 excluded. Reviewer inspected these saved results and did not rerun them.

Atomic dispatch writer, actual authority gate integration, strict effect sequencing in the driver, host launch/start/stop, recovery and the complete migration remain open implementation work. This review does not close T424/T434/T435 as a whole. No native, real SSH, systemd, APT, installation or release execution was performed or established.
