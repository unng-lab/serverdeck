# Independent review: direct configuration observations

Date: 2026-11-01. Fresh-context read-only reviewer: direct_ssh_observations_review_1.

Найдено 1 замечание, которое стоит исправить.

Готовность к реализации: готов — спецификация определяет решения для этого
инкремента. Приёмка кода остаётся открытой до исправления и нового review.
Полная миграция direct SSH не завершена.

## Scope

Twelve files listed in `.local/direct-ssh-observations-review-scope.txt`: direct
command/compiler, new public observation parser, actual owner/MCP configuration
read routes, byte-level RAM peer and corresponding integration/regression tests.
Eight existing files were compared with `.local/direct-ssh-observations-before/`;
four files are new. Related connection/session/authorization/observation DTO and
comparison sources, package001 spec/plan/model/contract/tasks and006/021 consumers
were inspected. Raw observations do not establish DB provenance or write authority.
T423/T427 and plan/job/catalog/worker integration remain open.

## Finding and fix evidence

P2: `reads.dart` always runs identity inspection before resource reads, but
`direct_ssh.dart` required write-only tools in that inspection. Missing
systemd-run/flock/sync/awk blocked all configuration reads; missing sha256sum
also blocked service reads. Contract§2 requires a missing prerequisite to block
only its dependent operation. Requirements FR-SSH-003/AC-SSH-01/02 and tasks
T405/T406 already define the intended behavior; this is a code defect.

Recorded additional task T439 preserves completed task history. The fix limits
identity guards to base64/id/cat/uname, leaving dependent observation and host
metadata guards intact. Added actual MCP RAM regression supplies absent executable
facts at the SSH byte boundary and examines emitted guards: unrelated write tools
must not prevent any of the five reads; missing sha256sum blocks file reads only,
missing systemctl blocks service reads only, and missing base64 blocks inspection.
The addressed test failed before the production fix, alongside a static identity
dependency test (`.local/direct-ssh-observations-prerequisites-red.exit=1`).

## Checks and limits

First reviewer read evidence without running it: full-r2 exit0, format442/0changes,
successful analyses,845 Dart tests and16 RAM bundle groups; links-r1 exit0,
1581 OK/0errors/2excluded. These passing suites did not cover the finding.
Earlier red evidence covers missing implementation, actual route migration and
freshness recalculation after the final native proof.

Review and tests do not establish actual native authority, SSH/filesystem
durability, systemd/APT or DB installation. No real shell/server/product/native/UI/
build/container execution is claimed. This first report is not a clean acceptance;
the fresh review following T439 is recorded below when completed.

## Completed fresh review after the fix

Reviewer: direct_ssh_observations_review_2, fresh context, read-only.

Замечаний не найдено.

Готовность к реализации: готов — для ограниченного инкремента прямого чтения
конфигурации. Проверенная реализация соответствует решениям пакета; полная
миграция остаётся незавершённой.

Reviewed scope: all twelve source/test files again, plus appended T439 and this
report (fourteen files in `.local/direct-ssh-observations-review2-scope.txt`).
The reviewer independently read source/spec artifacts and evidence and found the
previous prerequisite issue closed with dependent command guards preserved.

Requirement/design/contract/task/acceptance links, fixed five-resource commands,
bounded literal parsers/DTO, actor/current-target fences, async cancellation and
physical settlement, cache retirement, and freshness after final native proof
were checked. Reads do not create enrollment, desired state or storage commits.
Public raw facts remain separate from DB qualification/write authority.

Actual final evidence inspected, not rerun by the reviewer:
`.local/direct-ssh-observations-full-r3.exit=0`, format442/0changes, successful
analyses,86 Flutter+681 engine+15 MCP+57 protocol+8 Windows =847 Dart tests and16 RAM
bundle groups; `.local/direct-ssh-observations-links-r3.exit=0`,1581 OK/0errors/
2excluded. Red prerequisite evidence showed two failures before the fix.
No runtime/native/server proof is inferred. T423/T427 and actual plan/job/catalog/
worker integration and complete legacy removal remain open. T439 is completed;
the broader T405/T406 tasks are not closed by this bounded increment.
