# Research: 004

## SSH owner / bounded exec

Decision: один MonitoringOwner поверх ConnectionOwner. Только typed collection,
без public exec/нового MCP/нового SSHClient. Альтернатива — агент — отвергнута:
требует установки и выходит за scope. Для старых fake SshConnection оставить
отдельный optional MonitoringSshConnection interface.

Research agent прочитал ssh_transport/connection_owner и vendor client/channel/session.
execute() отдаёт SSHSession после channel-open и exec ACK, receive window 2MiB;
Future.timeout и session.close не отменяют pending open и не ограничивают ранний
вывод. Требуется bounded handle до первого await, cumulative admission hook до
buffering, tombstone pending open и retired-channel guard. На сеанс не больше
одного unresolved monitoring channel. Подробности в [contract](contracts/monitoring.md).

## Linux counters

Decision: aggregate CPU из первых восьми /proc/stat counters, guest/guest_nice
не суммируются повторно. Снижение любого counter сбрасывает baseline. RAM только
MemTotal/MemAvailable; df -Pk /, used/(used+available), без rounded Use%.
Альтернативы top/free и локализованный текст отвергнуты.
Источники: [Linux proc](https://www.kernel.org/doc/html/v6.12/filesystems/proc.html),
[GNU Coreutils manual source, df invocation](https://github.com/coreutils/coreutils/blob/master/doc/coreutils.texi).

## Run classification

Decision: dedicated monitoring.beginRun + validated finishExit. Нет достоверного
crash flag в runtime/store; owner.json перезаписывается. Native boundary читает
один marker под существующим owner lock, атомарно пишет running до auto-admission.
Классификация кэшируется на epoch, retries не перечитывают собственный running.
Missing/clean → auto; malformed/running/read uncertainty → explicit start.
Write failure блокирует auto до успешного retry, без ложного clean.
Альтернатива Isar field отвергнута из-за ненужной миграции. file.flushAtomic
сейчас allowlists только CURRENT и store publication, общий путь не расширяется.

## Clarify outcome

0 новых вопросов. Все продуктовые категории Clear; internal contracts и placement
были Deferred в Plan и определены здесь. Checklist requirements: 16/16 →16/16,
без изменения отметок. Extension hooks отсутствуют: .specify/extensions.yml нет.

GNU rendered-manual URL repeatedly returned HTTP429; reference replaced with
the same upstream manual source (doc/coreutils.texi), verified accessible.
No requirement/formula changed and no link-check status suppressed.

## US4 research / clarify — 2026-11-04

User answer: preserve history across restart. Other categories clear from current
004 plus FR-422–426; no further product question required. Retain existing active
workspace/tray/crash rules; last hour means actual collected samples, not remote backfill.
Decision: single Isar collection with one bounded payload/profile; no extra daemon.
Alternative720k individual rows rejected to simplify bounded per-profile codec/pruning.
Read-only research agent history_storage_research inspected storage/runtime boundaries:
current format2 full schema set requires direct current format3 guard update to avoid
implicit schema conversion. This is our design choice under ConstitutionVI, not a
claim that constitution names version3. Old data rejected intact, never migrated/reset.
Alternative file cache rejected: duplicates store/security/lifecycle ownership.
Reuse C22 with explicit720 capacity rather than averaging hour into120 samples;
keep exact fractional values and explicit segment/gap metadata.

