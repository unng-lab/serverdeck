# Independent spec review: terminal metadata finalization

Date: 2026-11-01. Fresh-context read-only reviewers:
direct_ssh_terminal_spec_review_1 and direct_ssh_terminal_spec_review_2.

Замечаний не найдено — в завершённом повторном review спецификации.

Готовность к реализации: готов — только для решений T440/T441 о terminal
metadata finalization/release и восстановлении её durable префиксов.
Реализация и весь direct SSH migration остаются незавершёнными.

## Scope and first finding

Four files in `.local/direct-ssh-terminal-spec-scope.txt`, compared with originals
in `.local/direct-ssh-terminal-spec-before/`: direct SSH contract, plan,
direct data model and appended tasks. Reviewers read applicable AGENTS.md,
constitution, related001/006/021 requirements and owner/job/native authority/
MCP/reconciliation contracts. The application's current failing full suite was
not represented as passing or as readiness evidence.

First review found one P2 mandatory gap and concluded not ready: the prescribed
terminal→plan marker→owner unlink sequence had no complete retry rule for a
crash between durable writes. The old wording that a retry only reads terminal
forbade finishing pending plan publication or owner removal. T441 records the
required implementation and tests without erasing completed task history.

## Completed fresh review

The second reviewer found the decision closed by explicit contract§8 branches:

- terminal A/pending plan/owner A: full current proof again, finish only plan
  publication and unlink;
- terminal A/terminal plan/owner A: full current proof again, finish only unlink;
- fully released A with absent owner or owner B: validate exact correlated
  durable history and return terminal A without comparing prior values against
  resources changed by B or reinterpreting A because of a subsequent boot;
- contradictory/missing records, incomplete proof or changed boot before release
  retain unknown and occupancy. B is never removed or changed.

The reviewers traced FR-SSH-004/005/008/009/014 → source map/model → contract§8 →
T440/T441 → AC-SSH-03/07/08/10 and specific RAM/static expectations. Read scope
and original-object isolation, owner recovery after grant revocation, current
host/trust/native proof, global lock, crash/lost ACK and local terminal CAS were
considered. The metadata command cannot stage/launch, change managed resources
or provenance, and is unavailable to configuration/state/logs read adapters.
No new credentials, dependency, persisted field or server runtime is introduced.

## Actual evidence and limits

Both reviewers inspected saved link evidence, without rerunning:
`.local/direct-ssh-terminal-spec-links-r1.exit=0` and corrected r2 exit0/log,
1581 OK,0errors,2excluded. Review2 inspected r2 directly. Files were not modified
by reviewers. No product/native/real SSH/systemd/APT/UI/build/container execution
was performed. The application full check remains failing (preflight migration
and old job-driver scenarios); no application review/acceptance is claimed here.
T440/T441 remain unchecked until their source implementation and required tests
are complete and have passed the code review loop.
