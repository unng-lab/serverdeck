# Независимый review/fix loop спецификаций direct SSH

**Дата**: 2026-11-01. **Scope**: поправки001/006/021, constitution4.4.0,
direct spec/plan/contract/model/research/quickstart/tasks/checklist и consumer
priority banners. Точный manifest67paths: `.local/direct-ssh-spec-scope.txt`.

Четыре separate read-only subagent tasks запускались с fork_turns=none,
прямым чтением AGENTS.md/artifacts, без изменения reviewed files во время review.

| Review | Результат | Закрытие |
| --- | --- | --- |
| direct_ssh_spec_review_1 | 2mandatory findings, не готов | Bounded step permit/native durable dispatch; durable qualified resource provenance; T422–T424 |
| direct_ssh_spec_review_2 | 1mandatory finding, не готов | Capsule2 compound DB configuration вместо разрыва file/restart/deferred checks; T425 |
| direct_ssh_spec_review_3 | 1mandatory finding, не готов | State-aware inactive qualification, отдельный start после stop/app restart; T427 |
| direct_ssh_spec_review_4 | Замечаний не найдено; готов к реализации | Все16CHK оценены выполненными в отчёте; markers reviewer-owned checklist не менялись |

Дополнительно основной агент закрепил transient policy-rc.d guard/native APT
hook ordering и crash-residue семантику, T426. Reviewer4 проверил эти interactions
в составе whole package. Repeated same-resource stop/start AST не добавлен:
существующая grammar его запрещает; поддержаны отдельные jobs/plans.

После каждого исправления выполнен lychee. Последний использованный reviewer4
результат `.local/direct-ssh-spec-links-r4.log/.exit`: exit0,1583total/1581OK/
0errors/2excluded/1redirect. Baseline `tools/test-unit.ps1` до application changes
завершён exit0; это не доказательство direct реализации. Последующий TDD red run
из-за ещё отсутствовавшего primitive source/format зафиксирован отдельно и не
выдавался за успешный code check. После добавления primitive6адресных units
прошли; полный code gate ещё предстоит.

Read-only Analyze:15FR-SSH,13AC-SSH,4SC-SSH;427unique001taskIDs без duplicates,
требование/решение/контракт/task/AC связаны и поддержаны reviewer4. Scope/authority/
data/lifecycle/dependencies/limits/acceptance clarification coverage — Clear;
новых продуктовых вопросов не потребовалось. Старые completed task history и
native gates не обнулены и не объявлены закрытыми этой поправкой.

Готовность относится только к специфицированному заданию. Код ещё требует
Implement/checks/review/Converge. SSH/FS/systemd/APT/package maintainer/native/UI/
container/build/install/release не проверялись; runtime qualification не заявлена.
