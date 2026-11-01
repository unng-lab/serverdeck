# Разработка ServerDeck

Действует embedded-поправка существующих001/002/021. Один `serverdeck.exe`
содержит desktop-приложение, переносимый Dart engine и stdio-коннектор MCP.
Закрытие окна оставляет приложение в трее; «Выход» завершает app и локальный MCP.
Удалённые принятые задания сохраняют lifecycle executor.

## Среда и SDK

PowerShell7.4+, Windows11 x64, Visual Studio2022 Build Tools с Desktop development
with C++, Windows SDK и VC++2015–2022 x64 runtime. Flutter3.47.7/Dart3.13.5,
framework revision `abaf9c523780a608bd46686fd5e53740a07077f8`;
SHA256 SDK archive `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`.
SDK находится в `.local/sdk/3.47.7/flutter` либо в `SERVERDECK_FLUTTER_ROOT`.
`tools/foundation-sdk.ps1` проверяет закреплённую identity и не устанавливает SDK.
Python3.12 нужен только build tool для executor descriptor; это не установка
исполнителя. Runtime prerequisites и границы платформ — в
[контракте](../../specs/001-service-foundation/contracts/embedded-platforms.md).

## Сборка и ручной запуск

Ниже описание build entry, а не выполненная проверка текущей задачи.
В текущей задаче не запускать сборку, приложение или native dispatch.

```powershell
./tools/run-serverdeck.ps1 -Configuration Debug -BuildOnly -Python python
```

Команда закрепляет зависимости root и четырёх пакетов engine/MCP/protocol/Windows
через `--enforce-lockfile`, генерирует прежние Isar records внутри engine,
вызывает только Flutter Windows build с `--no-pub`, копирует выбранную pinned
native-библиотеку/notices и создаёт executor descriptor и manifest4.
Результат — `build/windows/x64/runner/Debug`, Release выбирается параметром.
Без `-BuildOnly` тот же script запускает приложение; автоматического завершения
чужих процессов нет. Старые отдельные build entry удалены, aliases не оставлены.

Manifest4/API1.1/workspaceSchema3 связывает `serverdeck.exe`, `libisar.dll` и
`executor-release.json`. Build identity включает ровно пять текущих lockfiles:
root, serverdeck_engine, serverdeck_mcp, serverdeck_protocol, serverdeck_windows.
Flutter DLL/data, assets/fonts/plugin runtime и notices остаются рядом;
один exe без runtime-каталога не является всей поставкой. Reparse output и
layout с прежними отдельными exe отвергаются; script не удаляет/мигрирует старый
каталог и не меняет существующую установку или пользовательские данные.

Selected native input, receipt/source binding и notices guards сохраняются.
Старые receipt/evidence не квалифицируют новые исходники. Частный pinned SDK
native cache остаётся лишь существующим development input; выбор Release сам
по себе не означает native/distribution qualification, signing или installer.
Текущая задача не выполняет native qualification/activation/publish.

## Обязательные проверки

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
./tools/test-unit.ps1
lychee "specs/**/*.md"
```

Runner выполняет repository format, Flutter analyze/test, текущие PowerShell
RAM unit-кейсы manifest/native metadata policy и полные текущие Dart package unit suites.
Тесты этой задачи используют RAM/fakes; UI/widget/design, realFS, Isar, native
pipes/DPAPI, процессы, SSH, containers и integration не запускаются. Сначала
полный набор; адресные повторы — после его падения. Старые harness/fixtures
удалены, пропуски не считаются pass. После изменений необходим независимый
read-only review/fix loop по AGENTS.md. Исторические native журналы сохранены в
[foundation verification](foundation-verification.md), текущий статус — в
[tasks001](../../specs/001-service-foundation/tasks.md) и
[embedded evidence](embedded-engine-verification.md).

## Данные и MCP

Только целевые schema3/format3 данные, без upgrade/rollback/compatibility facade.
Несовместимые metadata остаются неизменными. Store/writer принадлежат единственному
app engine worker. UI и MCP не открывают отдельный domain store. Пока app живёт
в трее, MCP работает; после «Выход» коннектор выдаёт лишь локальную ошибку связи
и завершается. Конфигурация MCP описана в [инструкции](mcp.md).
