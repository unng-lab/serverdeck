# Implementation Plan: 004 — Базовый мониторинг серверов


**Branch**: `main` (не создавалась новая ветка) | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

## Summary

MonitoringOwner планирует сбор трёх метрик Linux через существующий ConnectionOwner.
Текущие CPU/RAM/диск отображаются готовыми C21 в списке, 5 секунд / порог 90%.
Новые SSH-владельцы, MCP методы и отдельные сервисы не вводятся.

## Technical Context

- Dart ≥3.13.5 / Flutter из pubspec, Windows C++17, существующий vendored dartssh2.
- Isar community 3.4.1, текущий format2 без миграции; history persists, freshness runtime-only.
- Служебный native marker запуска хранится отдельно от Isar, без секретов.
- Target Windows 10/11 x64; Linux server: POSIX sh, uname, cat, df -Pk, /proc.
- Максимум 4 сбора и 4 auto attempts, 5s deadline, 65536 bytes stdout+stderr,
  15s stale. Прежний лимит профилей 1000 и живых SSH 64 из 003 сохраняется.
- Tests: только unit/fake functional widgets, in-memory vendor protocol bytes,
  native adapter fixtures с synthetic inputs/temp files; без real Isar/SSH/GUI/VM.

## Constitution Check

До/после проектирования: PASS по принятым решениям; фактические проверки
реализации записаны в [implementation review](reviews/implementation.md).

| Принцип | Решение |
| --- | --- |
| C01–C30 | C01/02/04/07/09/10/11/12/18/21, существующий shell C17 |
| Дизайн экранов не тестируется | Только значения, severity, callbacks и lifecycle |
| Unit only | Fake dependencies, без integration/e2e и product launch |
| Один EXE / один владелец | Embedded SSH, ноль новых служб/пакетов |
| Трей / exit | Сбор отменяется на hide, SSH сохраняется, exit drains |
| Crash recovery | Durable running marker до auto-admission |

## Project Structure

Документы: [research](research.md), [data model](data-model.md),
[contract](contracts/monitoring.md), [validation](quickstart.md), [tasks](tasks.md).

| Место | Ответственность |
| --- | --- |
| lib/monitoring/monitoring_models.dart | Metrics, CPU baseline, state, presentation |
| lib/monitoring/monitoring_job.dart | Typed cancellation/result handle без raw output |
| lib/monitoring/linux_metrics.dart | Константная команда, strict parser |
| lib/monitoring/monitoring_port.dart | Internal canonical liveness/auto-admission/collection capability |
| lib/monitoring/monitoring_owner.dart | Fair queues, deadlines, freshness, auto attempts |
| lib/monitoring/monitoring_view.dart | C21/C10/C11 composition; no UI time log |
| lib/connections/connection_owner.dart | Owner-only admission, session/version fences |
| lib/connections/ssh_transport.dart | Typed monitoring-only capability |
| third_party/dartssh2/lib/src/ssh_client.dart, ssh_channel.dart | Cancellable bounded channel operation |
| lib/runtime/feature_runtime.dart | Единственная MonitoringOwner capability |
| lib/runtime/runtime_view.dart, lib/profiles/profile_view.dart | Activation и metric display |
| lib/profiles/profile_controller.dart | Manual actions notifications |
| lib/runtime/native_platform.dart, lib/main.dart | Run classification before admission |
| windows/runner/platform_channel.cpp, native/include/monitoring_run.h | Durable marker / pure classification |
| test/monitoring/, test/connections/, native/tests/ | Unit fixtures |

## Design Decisions

Полный контракт описывает APIs, grammar и cancellation. MonitoringOwner использует
AppOperations с UiActor для перечня/auto connect, не ProfileController._action,
иначе глобальный UI pending сериализует подключения. Свежая revision до connect.
ConnectionOwner остаётся владельцем SSH; current canonical OwnerActor установленного сеанса revalidated; отзыв MCP grant
не прекращает установленный SSH и UI monitoring. Pending attempts сохраняют
первоначальный actor и запрет продолжения после отзыва до promotion. Monitoring port не входит в AppOperations/MCP.

RuntimeView передаёт active = servers selected && window != trayHidden &&
acceptsOperations. Minimize не добавляет нового условия остановки.
Reconcile на activation и 1s tick, coalesced; stale async reconcile fenced epoch.
Отдельный native marker не меняет logicalFormat/credentials/profile schema.

## Complexity Tracking

Отклонений от конституции нет. Узкий vendor patch обязателен для cancellation
до exec ACK и ограничения раннего вывода. Обычный execute/run не подходит.


## Компактное представление2026-11-04
MonitoringReadings.compact + C21compact/C07trailing в profile_view; убрать _time и timestamp/age widgets, не модель времени. Подробные metric notices находятся внутри модального003. Изменение общегоDeckMetric выполняетсяв001/R014, componentunits отдельно. No newpackage/schema/service. После кода — функциональныетестыmonitoring/profiles сfakes, без screendesignchecks; independentreview иcurrentSpecKit analyze/converge004.


## Server workspace monitoring presentation
MonitoringReadings compact всегда icon+value/C14 tooltip, aggregate connection and
freshness используют C10 iconOnly с разными символами. Public model state остаётся
единственным источником 15s/90% semantics. Sidebar status берётся из current public
connection/trust/monitoring projections, never widget timer inference of successful SSH.
Runtime activation относится ко всей server workspace, global MCP overlay pauses.
Detailed safe source reasons переходят из details modal в рабочую область003.

## US4 — Hour history

FR-422–426/AC-419–422. MonitoringOwner owns bounded history and writes through
MonitoringHistoryStore implemented by WorkspaceDomainRepository, same WorkspaceStore.
Required capability (also on unit fakes), no optional production memory fallback.
lib/monitoring/monitoring_history.dart: typed points/strict codec,720 rows/profile,
192KiB UTF8 payload/profile,1h TTL. At1000 profiles≤192MiB payload. Existing≤64 SSH.
MonitoringHistoryRecord collection: unique profileId,connectionRevision,payload JSON.
Format2 remains current for additive schema without metadata conversion; unsupported formats are
rejected before DB open. Additive Isar collections do not change format version. Update002/003
current storage contracts/models/guards and generated schema directly, preserving
historical completed task/review evidence. No external runtime/new release dependency.

Per profile read once/revision; writes coalesce (one in flight/profile), serialized
by store. Commit condition rechecks profile existence/revision and owner lease.
Previously valid queued samples may persist after disconnect, but not after owner
retirement/revision/delete; accepted point belongs to its original historical segment.
Profile delete/revision edit atomically deletes history. Shutdown drains admitted writes.
History load is allowed while startupBlocked and never restores SSH/live readings.
Load failure/corrupt blocks overwrite; pending live rows stay bounded, retry reloads
and merges unique (time,segment) rows. Write failure retains dirty history for retry.
Prune on read/write and active minute tick; no background process while app closed.
UTC TTL excludes future points and ages≥1h; in-process monotonic age also bounds TTL.
Clock rollback starts a new segment; same-time points replace previous point in segment.
New session/resume/restart changes segment. Errors append nulls, never cached stale values.

Extend shared C22 in scope001: maxPoints1..720(default120),periodLabel,
finite num0..100,breakBefore. Existing default10min is unchanged; feature passes720
and «Последний час». C22 consumes ISO UTC receivedAt and nullable CPU/RAM/disk;
text alternative gives time/percent. No polling or persistence in widget.
C16 fifth tab between jobs/settings, C11 safe storage error/C02 retry.
Unit fake storage/clock/source functional checks, shared component units separately001;
no feature layout/integration/real Isar/product-launch gates.


History projection,error and retry require the connectionRevision of the selected profile details. A cached entry at another revision returns no points/error and cannot retry, even while reconciliation waits/fails (FR-425,T035).

## Page-sized resource history

FR-427/428,AC-423/424: MonitoringHistoryPanel передаёт fullSize:true,windowEnd из
MonitoringOwner.historyUtcNow,quality known/incomplete/empty по nullableточкам.
Используется C22/001R019. Schema/TTL/collector не менять. Не запускать приложение
или ComputerUse без отдельного запроса пользователя. Старое представление найдено
в DeckHistory: compact width270–300 и plot25. Путь данных — Linux collector→
MonitoringOwner→Isar history→C22. Никаких новых runtime dependencies.
