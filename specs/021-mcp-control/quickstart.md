# Quickstart and acceptance — embedded021

Действующая поправка в существующих001/002/021. Один serverdeck.exe содержит
app/tray и stdio mode; отдельные locald/mcp binary, cold launch и compatibility
fallback удалены. Состояние и история задач сохранены в [tasks021](tasks.md) и
[tasks001](../001-service-foundation/tasks.md). Старые native evidence не являются
проверкой новой связки. Scope текущей задачи — только static и RAM units.

## Prerequisites

Pinned SDK/toolchain/native/notices описаны в
[foundation](../../docs/development/foundation.md); конфигурация клиента — в
[MCP guide](../../docs/development/mcp.md). Source build entry:
`tools/run-serverdeck.ps1 -Configuration Debug|Release -BuildOnly`.
В этой задаче не выполнять build/launch/install/deploy, native dispatch,
realFS/Isar/процессы/SSH/containers/UI/widget/design проверки.

## Local checks after implementation

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
./tools/test-unit.ps1
lychee "specs/**/*.md"
```

Полный runner содержит только текущие RAM unit suites; package tests не
подменяются выбранными green cases. Адресный повтор разрешён после full failure.
MCP RAM suites используют scripted peer/streams/gates и реальные DTO/router/
publication policy, но не выполняют actual Windows pipes, store или executor.
C++ допускает /Zs static syntax/type check без object/link/app dispatch.
После checks нужен независимый read-only review/fix loop AGENTS.md.

## Owner setup and independent clients

Это контракт пользовательского сценария, не выполняемый native тест данной задачи.
Main app заранее запущено, включая состояние в трее. Владелец выдаёт отдельный
ограниченный grant каждому клиенту. Конфигурация содержит абсолютный путь
serverdeck.exe и args --mcp-stdio --grant-id UUID, без app-root/owner role/секретов.
Grantless --mcp-stdio тоже требует живого app и даёт только пустой catalog.
Без main app коннектор сообщает локальную ошибку связи и завершается; сервис
ничего не возвращает и не запускается ради ошибки. Explicit Exit закрывает
локальное admission; detach не отменяет уже принятые remote jobs.

## US1 — common reads

RAM acceptance: тот же зарегистрированный catalog021, scopes/allowed server,
fixed errors без утечки DTO, initialized/builtin/list/call publication через
действительный current-app guard. Expiry/revoke/peer loss/retired session не
публикуют private результат, overload ограничен, cancelled interest не replay.
Native write ownership сохраняется до actual ACK; logical timeout не освобождает
publication lease. Контракт: [gateway](contracts/gateway.md), [host](contracts/embedded-host.md).

## US2 — author profiles

RAM acceptance: typed schema/scope validation, optimistic CAS/revisions,
immutable plan inputs, original request UUID и receipt lookup без повторного
эффекта. Право авторства не выдаёт owner delegation/apply; owner authority нельзя
получить через caller role/DTO. Существующие protocol/tools не переименовываются.

## US3 — execution and recovery

RAM acceptance: durable intent до submit; lost ACK -> unknown, accepted не
completion, missing attempt не освобождает occupancy. Detached/stale — overlay,
не schema4. Query/reconcile того же attempt через прежние trust/enrollment/grant
checks, без автоматического повторного apply. Expired grant не блокирует owner
recovery. Sequence/terminal monotonicity и явный cancel сохраняются.
Эти units не подтверждают реальный SSH/systemd/executor/reboot/network сценарий.

## Hosted automation and handoff

`.github/workflows/unit.yml` разрешает pinned dependency resolution и static/RAM
unit runner. Старые native workflows/harness не исполняются и не заменяются
новыми live сценариями. Не публиковать secrets/credentials/VM auth data.
Записывать actual checks/exit codes и limits в существующие tasks/evidence.
Native/platform/release readiness и общая feature completion оцениваются отдельно;
содержимое script или старый зелёный журнал не является новым выполненным check.
