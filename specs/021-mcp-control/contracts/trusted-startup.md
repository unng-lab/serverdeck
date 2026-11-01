# Production embedded startup

Действующая поправка существующих001/021: [embedded host](embedded-host.md) и
[основа](../../001-service-foundation/contracts/embedded-engine.md).
Этот раздел заменяет прежний locald/cold-launch startup; старые binary entries,
owner IPC probes и discovery fallback не являются действующими требованиями.
Целевые schema3/format3 wire/credentials/trust/jobs сохраняются без migration.

App получает genuine bundle4, retained current-process identity, SID и private
writer lease, выполняет schema3 preflight/recovery и только затем публикует
Ready-generation MCP endpoints с protected descriptor2 embedded-v1. Единственный
store/writer находится в private app worker; owner capability не выдаётся через
role/CLI/IPC. Bootstrap failure сохраняет ownership до физического cleanup;
CloseBlocked не освобождает lease. Полный порядок и resource bounds определены
embedded contracts; metadata не заменяет retained PID/creation/image proof.

Same-executable --mcp-stdio проверяется до UI/COM/tray/Host. Native carrier
изолирует SDK logs и передаёт только исходные inherited stdio bytes; private
channel readiness5s предшествует connection-only bootstrap. Коннектор проверяет
живое Ready/MCP app, bundle/current peer, discovery/proof, затем optional grant.
Отсутствующее app не запускается: это локальная ошибка подключения, не ответ
сервиса. Grantless доступ также требует живого app; catalog пуст, calls запрещены.
После proof/effect нет reconnect/replay. Внешний MCP wire и каталог021 сохраняются.

Физический write ACK, publication fencing, trusted peer и close/owned-exit
ограничения — в [gateway](gateway.md) и embedded-host. App в трее продолжает
обслуживать MCP, explicit Exit закрывает admission и выполняет общий drain10s.
Незавершённые remote jobs не объявляются отменёнными из-за потери наблюдения.

`tools/run-serverdeck.ps1` разрешает root+четыре package lockfiles и выполняет
только Flutter Windows build; engine generator заменяет прежний locald generator.
Manifest4/API1.1/schema3 связывает serverdeck.exe/libisar.dll и сгенерированный
executor-release.json. Runtime/data/assets/fonts/native notices остаются рядом.
Нет отдельного mcp.exe/locald.exe, build aliases или app-root/owner flags.
Наличие старых exe в layout останавливает build entry, без удаления старой
установки/данных или завершения процессов. Native input/approval/source guards
сохранены; stale approvals не становятся актуальными после смены source.

Проверки текущей задачи — static и RAM units; native/CRT/loader/Win32 I/O,
установленная команда, realFS/Isar/SSH/процессы/UI/design, build/install/deploy
не квалифицированы. Исторические evidence не закрывают новые acceptance gates.
