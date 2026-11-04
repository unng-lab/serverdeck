# Implementation Plan: 004 — Базовый мониторинг серверов

**Branch**: `main` (не создавалась новая ветка) | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

## Summary

MonitoringOwner планирует сбор трёх метрик Linux через существующий ConnectionOwner.
Текущие CPU/RAM/диск отображаются готовыми C21 в списке, 5 секунд / порог 90%.
Новые SSH-владельцы, MCP методы и отдельные сервисы не вводятся.

## Technical Context

- Dart ≥3.13.5 / Flutter из pubspec, Windows C++17, существующий vendored dartssh2.
- Isar community 3.4.1 без миграции: измерения только в памяти.
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
| lib/monitoring/monitoring_view.dart | C21/C10/C11/C18 composition |
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
