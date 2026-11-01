# Independent specification review: no-dispatch cancellation

Reviewer: `direct_ssh_undispatched_spec_review_1`, fresh task without inherited
conversation; read-only review completed 2026-11-01.

Замечаний не найдено.

Готовность к реализации: готов — только дополнение T442; это не вывод о готовности
всей direct SSH реализации или о выполнении T442.

Scope: contract section8 no-dispatch cancellation, data-model added row, plan T442
section and tasks Phase56/T442. Compared all4files against before copies; read
AGENTS.md, constitution4.4.0, spec.md, full direct contract and embedded-engine
cancel/reconcile rules. Requirement→decision→contract→task→acceptance chain traced
for FR-SSH-004/005/007/008/009/014 and AC-SSH-03/07/08/10.

Reviewed durable local cancel/null dispatch, exact admission/stop, empty step
inputs, absent declared units/cgroups, custody/boot proof, scope isolation,
terminal ordering/prefixes/history/ownerB, partial-reserve refusal, deadline and
unchanged schema/dependencies. No mandatory missing decision confirmed.

Evidence inspected: `.local/direct-ssh-undispatched-spec-links-r2.exit=0`, log:
1581OK/0errors/2excluded. Reviewer did not rerun checks. Application WIP, known
engine failures, native/Linux/SSH/systemd execution and whole goal readiness were
outside this specification-only review. T442 remains open until implementation,
mandatory checks and fresh independent code review.

Technical research during implementation: [systemd v255 show_one source](https://github.com/systemd/systemd/blob/v255/src/systemctl/systemctl-show.c#L1964)
returns property data for not-found/inactive in show mode; status/help use other
exit behavior. This source inspection is not Linux runtime validation.
