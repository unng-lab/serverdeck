# Implementation Plan: 002 — запуск, Isar, restore и трей

**Feature context**: `002-desktop-runtime` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

## Summary

Один поставляемый EXE: нативный `/MT` bootstrap извлекает встроенный manifest-bound
payload и загружает Flutter host DLL в том же PID. Основной Dart composition root
владеет Isar и runtime coordinator; stdio-ветка bootstrap не загружает Flutter.
Пакет 002 даёт runnable приложение с пустым слотом готовых C01–C30; SSH/MCP в 003
подключаются через зафиксированный интерфейс, без нового процесса-владельца.

## Technical Context

- **Language/Version**: Flutter 3.47.7, Dart 3.13.5; C++17, MSVC v143 x64.
- **Primary Dependencies**: isar_community / flutter_libs / generator 3.4.1;
  build_runner 2.16.2 для генерации. Native Win32/DPAPI/BCrypt без tray/window plugins.
  Точные ограничения и проверка resolution: [research](research.md).
- **Storage**: Isar, текущий logical format2; DPAPI CurrentUser bytes внутри транзакций.
  `%LOCALAPPDATA%/ServerDeck/` через Known Folder API, не переменные окружения клиента.
- **Testing**: flutter_test функциональные owner/widget tests; native CTest для
  bootstrap/platform с fake messenger/hooks; StoreBackend fake вместо реальной Isar.
  Только unit scope, без integration/e2e/VM/process-kill и feature design tests.
- **Target Platform**: Windows 10/11 x64, interactive user, без admin/network prerequisites.
- **Project Type**: desktop, один root Flutter package, один native build graph.
- **Performance Goals**: нормальный shutdown ≤10 s; повторный запуск ждёт activation
  acknowledgement ≤3 s; сбой не приводит к второму DB owner.
- **Constraints**: offline single-file delivery, только tray exit, отсутствие служб,
  никакого shell-based запуска команд и DLL search из CWD/PATH.
- **Scale/Scope**: один owner на Windows user; последующие capabilities — через 003.

## Constitution Check

| Принцип | До исследования / после проектирования |
| --- | --- |
| I. C01–C30 | C01/C02/C10–C14/C17, готовый content slot, без копирования компонентов |
| II. Дизайн не тестируем | Только данные/actions/lifecycle, без geometry/golden/matrices |
| III. Функциональные проверки | Изолированные owner/native/state/recovery checks; без integration/VM |
| IV. Один EXE, Flutter + Isar | Bootstrap + внутренние DLL в одном GUI PID; stdio без БД |
| V. Трей | Close/Alt+F4 → hide; exit только native tray command; безопасный drain |

Нарушений не требуется. Внутренние DLL — implementation detail одного дистрибутива,
а не отдельно устанавливаемое приложение. Работоспособность будущей сборки не заявлена.

## Project Structure

### Documentation (this feature)

[research](research.md), [data-model](data-model.md),
[packaging](contracts/packaging.md), [runtime/platform](contracts/runtime.md),
[storage](contracts/storage.md), [quickstart](quickstart.md), [tasks](tasks.md).

### Source Code (repository root)

| Планируемое место | Ответственность |
| --- | --- |
| `native/bootstrap/main.cpp`, `payload.cpp`, `instance.cpp` | args, embedded payload, singleton, dispatch до Flutter |
| `native/include/serverdeck_host.h` | C ABI bootstrap ↔ host DLL |
| `windows/runner/` | Flutter runner, собранный host DLL; tray/window/COM/message loop |
| `windows/runner/platform_channel.cpp` | Win32/DPAPI/platform contract, без domain storage |
| `lib/main.dart`, `lib/app.dart` | только основной GUI composition root, lifecycle wiring |
| `lib/runtime/runtime_coordinator.dart`, `capability.dart` | state machine, generation gate, drain |
| `lib/runtime/native_platform.dart` | typed adapter единственного method channel |
| `lib/storage/records.dart`, `workspace_store.dart`, `store_manifest.dart` | Isar models/owner/txn/format lifecycle |
| `test/runtime/`, `test/storage/` | функциональные проверки synthetic inputs |
| `native/tests/`, `tools/build-release.ps1`, `tools/test-release.ps1` | native unit contracts, сборка EXE и статический аудит imports |

Все перечисленные новые runtime-файлы создаются при реализации; существующие
`lib/ui/`, `lib/theme/` и каталог 001 остаются библиотекой компонентов.

**Implementation mapping 2026-11-03:** native tray/window/activation adapter
сосредоточен в `windows/runner/platform_channel.cpp` вместе с platform method handler;
Flutter/Win32 message routing остаётся в `flutter_window.cpp`/`win32_window.cpp`.
Плановые `tray.cpp`, `window.cpp`, `activation.cpp` — эти же обязанности, без
отдельных translation units. Bootstrap helpers находятся в `native/bootstrap/`
(включая общий security.cpp). `lib/main.dart` содержит retryable DesktopWorkspace
composition wrapper; единственным Isar owner остаётся WorkspaceStore.

## Design and sequencing

1. Native bootstrap/host ABI и platform contract не зависят от Isar.
2. Store owner открывается после singleton; runtime становится running после
   доступного окна/трея и явного результата store open (ошибка даёт recoverable UI).
3. Один FIFO coordinator gate сериализует state transitions/commit admission;
   не держит gate на сетевых/длительных операциях. Capabilities регистрируются до running.
4. Platform events имеют monotonically increasing seq и ownerEpoch; Dart игнорирует
   событие старого epoch. Native является authority факта hide/tray/window, Dart — данных.
5. Shutdown закрывает admission, отменяет capability attempts, drains текущий txn,
   закрывает capabilities и Isar, затем разрешает native DestroyWindow/PostQuitMessage.
6. Format 1 → 2 из 003 использует копию store и atomic CURRENT, а не in-place downgrade.

## Complexity Tracking

Исключений конституции нет. Bootstrap/host DLL необходимы из-за ранних DLL imports
стандартного runner; внешнее приложение-распаковщик отклонено. [Выбор и источники](research.md).


## Unit-only acceptance amendment — 2026-11-03

Уточнение пользователя имеет приоритет над прежними VM-планами. `StoreBackend`
изолирует native Isar initialize/open; production default IsarStoreBackend сохраняет
абсолютный library path, download:false, full schema, relaxedDurability:false,
inspector:false. Юнит FakeStoreBackend моделирует settings/txn/close, не доказывает
поведение движка и crash durability. Файловые preflight/publication tests используют
только свои временные данные; product GUI, реальный DB engine и процессы не запускаются.
Native CTest label unit включает6 adapter/codec tests. Исторические observer/lifecycle
helpers отключены по умолчанию и не входят в unit runner. Packaging проверяется
сборкой и статическим manifest/import audit. VM tooling/evidence — история,
не недостающая приёмка; актуальные команды — в quickstart.


Current-only2026-11-04: убратьStoreBackend.copyStore/_migration*/format1branches; lib/storage/store_manifest.dart принимаеттолькоformat2 ивладеетcurrentpublication/recovery. T044 отменяетпрежниеbackward-compatdecisions поConstitutionVI; userdataнеудаляются.


## Server workspace runtime composition
lib/runtime/runtime_view.dart использует текущий C17 slot API001 и server workspace003.
MCP settings открывает owner-hosted C12; пока route открыта collection004 paused,
после закрытия сохранённый контекст продолжается. Runtime states/status/retry/tray
recovery остаются owner-provided, без legacy navigation adapter. T045/003T072.

## Полный шрифт иконок в выпуске — 2026-11-04

Release build использует `--no-tree-shake-icons`: поставляется полный MaterialIcons
из закреплённого Flutter SDK. Перед упаковкой tools/build-release.ps1 запускает
tools/check-release-font.py, сравнивающий bundled font с SDK font побайтно; missing,
empty или несовпадающий файл останавливает сборку до создания нового payload.
Это статический asset audit, без запуска продукта. Стандартная unit-команда
включает isolated Python units с временными synthetic font bytes для этого audit.
Цена решения — полный font (~1.6MB вместо subset); внешних runtime зависимостей нет.


## Совместимость формата — 2026-11-04

Единая currentStorageFormat/isCompatibleStorageFormat policy в store_manifest.dart
используется manifest decoder, AppSettings default и WorkspaceStore settings guard.
Существующий формат2 проходит текущий путь, decode сохраняет formatVersion, без
перезаписи manifest/settings и без replacement DB. Все прочие integrity/security
checks прежние. Новые коллекции в records/workspaceSchemas добавляются стандартным
Isar open. Политика не означает поддержку старых executable/API или будущих схем.
Unit fake fixtures + format/analyze/flutter test + link checks + independent review;
затем fresh singleEXE build. Реальная база не используется в тестах.
