# Платформы и текущие возможности

Нормативный [platform contract](../../specs/001-service-foundation/contracts/embedded-platforms.md)
разделяет переносимый Dart engine и реальные host adapters. Сейчас реализован
Windows host; это не утверждение квалификации установленного комплекта.
Изменение platform enum или build flag не добавляет поддержку другой ОС.

| Платформа | Текущий статус | Background policy | Требования будущей поставки |
| --- | --- | --- | --- |
| Windows | host реализован; возможности положительны только после текущей проверки | desktopWhileRunning | текущий verified bundle, подходящая Isar DLL, private workspace/lease, SID/ACL/DPAPI, доступный vault |
| Linux | unsupported | unsupported | отдельный host, native storage/lock, secret vault и desktop integration |
| macOS | unsupported | unsupported | отдельный host, native storage/lock, Keychain/app identity и desktop integration |
| Android | unsupported | foregroundOnly | отдельный sandbox storage/Keystore host; постоянный background/FGS не включён |
| iOS/iPadOS | unsupported | foregroundOnly | отдельный sandbox storage/Keychain host; внешний stdio MCP не предусмотрен |
| Web | unsupported | unsupported | локальная поставка отсутствует; нет direct TCP/SSH или native vault fallback |

Будущие adapters не реализуются в этой задаче. Optional remote node для Web не
реализован и не является backend-зависимостью Windows-приложения.

## Runtime snapshot

`EngineCapabilities` — immutable snapshot с закрытыми полями platform,
storageReady, vaultStatus, directSsh, localMcpBridge, trayAvailable,
backgroundPolicy и reasonCodes. Vault имеет состояния available/locked/unavailable.
До текущей успешной проверки, при suspend, restore, stop или утрате proof
положительные storage/SSH/MCP flags сняты. Физически открытый store сам по себе
не означает storageReady. Не-Windows строки не выполняют Windows fallback и
имеют reason `PREREQUISITE_UNAVAILABLE`.

Безопасные reasonCodes: NOT_READY, TIMEOUT, STORAGE_BLOCKED, INCOMPATIBLE,
PREREQUISITE_UNAVAILABLE, UNAUTHORIZED, RESOURCE_LIMIT, SERVICE_UNAVAILABLE.
Они не содержат paths, credentials или текст исключений. Locked/unavailable vault
после probe блокирует core как STORAGE_BLOCKED; неизвестный текущий proof —
NOT_READY. Snapshot описывает наблюдённый результат проверки, а не непрерывный
OS watcher: тихое изменение provider не считается мгновенно обнаруженным.

Windows core требует usable storage, available vault и отсутствие blockers.
Optional SSH/MCP/tray absence не делает исправный core ошибочным. directSsh не
означает открытое соединение или доступ к цели; localMcpBridge не означает выданный
grant. Flags не заменяют authority, permissions, lease, trust или проверку actor.
Tray flag задаётся фактической desktop integration, а не worker предположением.

## Окно, трей и MCP

Закрытие окна оставляет ServerDeck в трее; меню возвращает окно, разделы «Серверы»
и «Настройки», показывает безопасный статус и содержит «Выход». Недоступный tray
не оставляет приложение скрытым без возврата. «Выход» выполняет общий shutdown
движка/MCP. Accepted remote jobs не отменяются закрытием окна или потерей клиента.

`serverdeck.exe --mcp-stdio` — connection-only режим того же файла для MCP-клиента.
Он не создаёт desktop host, store, окно или tray и не запускает приложение.
Независимая локальная служба не требуется. Пока основное приложение работает в
трее, MCP может подключаться с действующим grant. После «Выход» ответов MCP нет:
соединитель пишет только безопасную диагностику stderr и завершается nonzero.
`SERVICE_UNAVAILABLE` при отсутствии app — локальная диагностика подключения,
а не ответ неработающего MCP-сервера. Детали — в [инструкции MCP](mcp.md).

Suspend немедленно закрывает admission и снимает свежесть наблюдений, затем
дожидается локального physical drain. Resume использует тот же worker/store и
проверяет runtime, vault, lease, текущие revisions и capabilities. Старые owner
bindings/observations не оживают; SSH автоматически не подключается, remote
submit/cancel не выполняются. Требуются свежие bindings и явные действия по
действующим правам. Неопределённое закрытие не обходится новым worker.

## Проверки и ограничения

T269/T326 и T321 подтверждены static/RAM проверками и независимыми reviews:
шесть platform rows, lifecycle invalidation, deadlines и текущая публикация
capabilities. [Tasks001](../../specs/001-service-foundation/tasks.md) сохраняет
точный scope и результаты. Настоящие OS power events, tray, DPAPI/Isar/SSH,
isolate/native dispatch, UI remount, build/install/release здесь не проверялись.
