# Implementation Plan: Консоль сервера

**Branch**: текущая рабочая ветка (resolver feature key 007-server-console)
**Date**: 2026-11-06 | **Spec**: [spec.md](spec.md)

## Summary

Один ConsoleOwner хранит ограниченные терминальные сессии и обслуживает UI/MCP через общие actor/trust fences. Готовый xterm4 engine в терминальном варианте C26; общий SSH получает отдельную bounded PTY capability без второго логина. Настройки оболочек сохраняются в существующем Isar singleton, вывод/leases/replay только в памяти. Решения и alternatives: [research](research.md).

## Technical Context

- Language: Dart >=3.13.5 <4, текущий Flutter SDK, Windows desktop.
- Dependencies: vendored dartssh2 с bounded PTY, vendored xterm4.0.0 MIT, существующие Isar3.4.1/pointycastle4.0.0.
- Storage: один WorkspaceStore/Isar, nullable строка конфигурации в AppSettings; format2 сохраняется.
- Testing: flutter unit/functional widget fakes, синтетические vendor adapter unit; никакого реального SSH/Isar/process/integration.
- Platform: Windows-клиент, Linux SSH server с разрешённым PTY и существующей оболочкой.
- Scope: 4 сессии/server,16 global; scrollback10k/4MiB, raw1MiB,input64KiB; screen/parser/replay caps закреплены контрактами.
- Performance: открытие15s; без сетевого ожидания внутри gate, bounded token processing; нет непрерывного exclusive collection slot.

## Constitution Check

До и после design: PASS. C01–04/C10–14/C16–17 переиспользуются; общий C26 расширяется в001. Feature tests проверяют поведение, не дизайн. Только unit/fakes. Один Flutter/Isar/SSH/MCP owner, офлайн runtime. Трей сохраняет сессии; выход закрывает всё. Additive nullable settings не сбрасывает базу и не повышает format. Релиз/публикация не входят в этот цикл реализации; версия приложения не меняется.

## Project Structure

- lib/console/: models/values, settings owner/view, terminal engine adapter, session/replay owner, console port/view.
- lib/ui/deck_terminal.dart: общий C26 terminal variant; feature owner передаёт engine, ввод и callbacks; никаких SSH или credentials здесь.
- lib/connections/{connection_owner,ssh_transport}.dart: capability и финальный guarded packet boundary.
- lib/domain/{actor,models}.dart: trusted MCP binding и explicit public projections.
- lib/mcp/{router,pipe_adapter,tool_schemas,settings_view}.dart: типизированные console tools, закрытие binding, полномочия.
- lib/runtime/{feature_runtime,runtime_view,application_settings_view}.dart и lib/profiles/profile_view.dart: композиция/навигация.
- lib/storage/{records,records.g,workspace_store}.dart: nullable config и generated schema.
- third_party/{xterm,dartssh2}/: документированные bounded terminal/PTY patches.
- assets/mcp/tools.json и specs/003-ssh-mcp/contracts/mcp-tools.json: единый registry v2,21 tools.
- test/console/, test/mcp/, test/connections/: функциональные fakes и adapter unit.
- test_design/components/: только synthetic C26; scope001 документы/реестр/каталог.

## Architecture and responsibilities

ConsoleSettingsOwner использует repository/gate и UiActor: strict validation, snapshot, atomic save. ConsoleOwner получает settings, actors, gate/state, connection port, monotonic clock/scheduler/newId. Консольная операция проходит gate.prepare/submit с актуальной авторизацией и fence; сетевое открытие/ожидание вне gate, final effects снова guarded.

ConnectionOwner выдаёт только binding текущего connected transport (SSH sessionId, revision, attempt generation, endpoint/trust fences); каждое synchronous invalidate до возврата управления вызывает console cancellation listeners. Rename исключён из fence. Binding остаётся внутренним, wire не получает transport.

ConsoleOwner создаёт один engine до открытия PTY и reservations до первого network effect. Никакого _withCollectionSlot на lifetime. Runtime stopAdmission синхронно закрывает admission/input, cancelPending отменяет opening, closeSessions отменяет каналы, drain ждёт очистку. Widget dispose отсоединяет renderer, не owner. При trust/profile invalidation очищается engine; обычный disconnect сохраняет read-only output.

McpRouter получает optional typed ConsoleOperations наряду с AppOperations; production всегда передаёт owner. McpActor attenuation содержит trusted connection binding/closed predicate, не JSON. McpSession.close и оба pipe close пути закрывают binding синхронно; GrantOwner canonical checks блокируют effects и notifications освобождают leases. Payload никогда не попадает в diagnostics/receipt store.

## Contracts and implementation order

1. [Data model](data-model.md), [terminal](contracts/terminal.md), [SSH](contracts/ssh-console.md), [MCP](contracts/mcp-console.md).
2. Scope001 C26 documentation/renderer + vendor patches и dependencies.
3. Settings/model/engine и bounded SSH adapter.
4. ConsoleOwner и US1, US2, US4, US3 с unit coverage.
5. Registry/router/runtime/UI wiring, все обязательные checks и независимый review.
6. Analyze до implement; после implement — converge, дописать обнаруженные gaps без стирания истории tasks и закрыть их тем же циклом.

## Complexity Tracking

Нарушений конституции нет. Vendor patches необходимы для соблюдения существующих caps/trust/revocation, а не новая терминальная реализация. Подробные задачи: [tasks](tasks.md). Запуск и границы доказательств: [quickstart](quickstart.md).
