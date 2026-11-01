# Независимое ревью direct SSH primitives и compiled plans

**Дата**: 2026-11-01. Это завершённые первые increments, не весь переход.

## Transport/read-only slice

Точный scope: engine `remote/direct_ssh.dart`, `direct_ssh_transport.dart`,
`ssh_transport.dart`, `ssh_io.dart`; tests `remote/direct_ssh_test.dart`,
`direct_ssh_transport_test.dart`. Reviewed source не менялся во время каждого
separate read-only subagent task с fork_turns=none.

| Review | Findings и исправления |
| --- | --- |
| direct_ssh_transport_review_1 | 4P2: bounded numeric evidence, command stdout caps, inspection deadline, terminal error после partial rows; T428–T431 |
| direct_ssh_transport_review_2 | Прежние4закрыты; missing sudo/id bootstrap prerequisite, T432 |
| direct_ssh_transport_review_3 | Bootstrap закрыт; observation framing/native tool prerequisite classification, T433 |
| direct_ssh_transport_review_4 | Замечаний не найдено; primitive готов для продолжения реализации |

Исправления включают immutable закрытый tool catalog с generated upfront guards,
POSIX builtin error printf, inspector10s/probe64KiB/observation128KiB, bounded
numeric parsing до BigInt и strict partial-error framing. Unit clock/byte ports
подтверждают логическое timeout/cancel с удержанием slot до physical settlement.
Shell payload и реальные SSH/sudo не выполнялись.

## Model/compiler slice

`direct_ssh_program_review_1` проверил пять файлов: protocol
`direct_ssh_runtime.dart`, `automation/plan_records.dart`,
`test/direct_ssh_plan_test.dart`; engine `automation/compiler.dart`,
`test/automation/direct_ssh_program_test.dart`. Замечаний не найдено; готовность
этих DTO/compiler решений установлена. Исторические capsule1/program/JSON/digests
сохранены; capsule2 и compound5checks не являются permission/remote attestation.
Runtime activation и dispatch/provenance пока не реализованы этим срезом.

## Фактические проверки

После последнего исправления `tools/test-unit.ps1` завершён exit0:
`.local/direct-ssh-transport-full-r4.log/.exit`,425formatted/0changed,
root Flutter и четыре package analysis clean; root86+engine628+MCP15+
protocol54+Windows8=791Dart tests,16bundle RAM groups. Предыдущие red/failure
журналы сохранены; только этот текущий результат считается green данного scope.

Lychee `.local/direct-ssh-transport-links-r4.log/.exit` exit0:
1583total/1581OK/0errors/2excluded/1redirect. Formatter сообщает unresolved
include в отдельном `work/isar-encryption-implementation`; reviewed scope не
меняет этот worktree и не выдаёт warning за проверку его зависимостей.

Ни один review не устанавливает готовность whole migration или выпуска.
Старые services пока используют прежний executor и будут переведены T406/T417.
Открыты controller, host records/ownership, authority dispatch, install/provenance,
cancel/reconcile, preservation, UI/MCP/bundle/docs и финальный Converge/review.
Native/FS/SSH/shell/systemd/APT/UI/container/build/install/release не проверялись.
