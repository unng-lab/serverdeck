# Runtime/platform contract v1

## Native host ABI

`native/include/serverdeck_host.h` определяет custom экспорт DLL
`int WINAPI ServerDeckRunMainV1(const ServerDeckHostArgsV1*)`. Аргументы POD:
uint32 structSize, abiVersion=1; UTF-16 pointers runtimeDirectory,dataRoot,exePath,
ownerEpoch; borrowed HANDLE singletonMutex,activationPipe; uint32 launchMode=0.
Строки доступны на весь вызов; handles закрывает bootstrap после возврата.
DLL не освобождает память bootstrap; нет STL/CRT objects/exceptions через ABI.
Return 0 — нормальное завершение, ненулевой — ошибка запуска/закрытия.
Коды2/3/4/6 — соответственно invalid ABI args/COM/window-engine/platform initialization
до начала message pump: после полного освобождения host/owner ресурсов bootstrap
показывает native retry/cancel. Коды5(message pump failure)/7(runtime exception) и
неизвестные ненулевые коды — error без разрешения повторно создавать engine в этом PID.
При них native показывает ошибку с OK и завершает экземпляр. Начало message pump —
консервативная граница, после которой startup retry уже запрещён.
Flutter engine/COM создаются в RunMain на main thread, никогда в DllMain.
Host передаёт ownerEpoch единственным аргументом Dart entrypoint; initialize
проверяет его до любых данных. Native platform channel создаётся до первого кадра.
Bootstrap остаётся загруженным до конца; host не выгружается при живых callbacks.

## Args и singleton

Без args — GUI. В 002 `--mcp-stdio --client <canonicalUUID>` — reserved bridge:
чистый stderr MCP_UNAVAILABLE, exit 20, без распаковки/host/Isar/активации окна.
003 заменяет реализацию ветки согласно [IPC contract](../../003-ssh-mcp/contracts/ipc.md).
Неизвестные/неполные args: native ошибка и exit 2; без fallback к GUI для bridge args.

На user SID mutex `Local\ServerDeck.Owner.<sha256-userSid>` недостаточен для
единственного owner в разных Windows sessions: дополнительно эксклюзивный handle
без FILE_SHARE_* на `%LOCALAPPDATA%/ServerDeck/owner.lock` является межсессионной
authority. Создание owner/activation descriptor только под этим handle. Lock-file
содержит не секрет, его наличие не означает живого owner; authority — handle lock.
Дубликат читает descriptor, проверяет SID/PID/creationTime и связывается с activation
pipe владельца. Если logon SID отличается, показывает «Приложение работает в другой
сессии Windows» и завершает дубликат; не пытается восстановить чужое окно.
Тот же logon: activate request `{version:1,ownerEpoch,requestId}`; ack до 3 s:
`activated | shuttingDown | storageBlockedActivated`; timeout/error не запускает
второго owner. При старом descriptor и свободном lock новый owner атомарно заменяет
его. В shutdown lock удерживается до окончания и закрытия БД.

## MethodChannel `serverdeck/platform.v1`

Flutter standard codec, только основной процесс. Методы native:

| Call | Args | Result |
| --- | --- | --- |
| initialize | ownerEpoch | userSid,logonSid,exePath,dataRoot,runtimeRoot,trayAvailable |
| window.hideToTray | epoch | hidden bool; false при недоступном tray |
| window.restore | epoch | visible bool |
| tray.retry | epoch | trayAvailable bool |
| runtime.finishExit | epoch, shutdownComplete=true | ack; только после closeActivation и latched tray/OS exit |
| secret.protect / unprotect | Uint8List; purpose string | Uint8List; CurrentUser DPAPI, UI forbidden |
| file.flushAtomic | allowlisted relative metadata path; bytes≤8192 | ack после flush+same-volume replace |
| runtime.closeActivation | epoch | ack |

Нет метода execute/shell/произвольного чтения/записи пути. Purpose — domain label,
не Windows logon credential. Native errors: INVALID_ARGUMENT, STALE_EPOCH,
TRAY_UNAVAILABLE, STORAGE_IO, PROTECTION_UNAVAILABLE, SHUTTING_DOWN; без payload bytes.

Native → Dart event callback `platform.event`: `{version:1,ownerEpoch,seq,type}`,
seq≥1 strict monotonic. Type: closeRequested, trayOpen, trayExit, trayLost,
trayReady, activationRequested, osSessionEnding. Startup snapshot восстанавливает
текущий seq; duplicates игнорируются. Gap вызывает native snapshot query, не
предположение о состоянии. В channel имеется `runtime.snapshot` → текущие epoch,
seq, windowState,trayAvailable,osEnding,exitRequested. Вход runtimeState отражает
состояние coordinator для activation ack; не меняет durable/domain state.
Snapshot сохраняет latched exitRequested даже при переполнении/разрыве seq.
Event buffering до Dart-ready: до 32,
повторяющиеся open/close схлопываются, exit/osEnding не теряются; при переполнении snapshot.

Native подавляет WM_CLOSE по умолчанию; до Dart-ready close скрывает только при
готовом tray. Tray Exit и OS ending latch сохраняются до обработки coordinator.
После trayLost native сразу показывает окно, независимо от Dart responsiveness.
Minimize остаётся стандартным. Системное меню Exit в окне не добавляется.

Native не полагается только на cached trayAvailable: перед WM_CLOSE и
window.hideToTray проверяет зарегистрированный hWnd/uID через Shell_NotifyIcon
NIM_MODIFY с uFlags=0 (без изменения полей). Собственный HWND timer nominal500ms
повторяет проверку, пока tray считается доступным. Отказ probe атомарно снимает
доступность, восстанавливает окно и emits trayLost один раз на переход; повторные
ticks при unavailable не воруют фокус и не добавляют icon автоматически. Это
native message-pump monitoring, не hard real-time latency guarantee. TaskbarCreated
или явный tray.retry восстанавливают регистрацию. Timer обязателен для startup,
его failure идёт по native startup retry/cancel; rollback/normal close удаляют его
до освобождения platform/messenger. Unit-проверки используют synthetic hooks и не доказывают фактический Explorer
restart. Интеграционный VM-прогон не является условием завершения пакета.

## Shutdown protocol

1. Gate закрывает admission и фиксирует shuttingDown, один request независимо от
   повторов. UI disable actions; capability stopAdmission + cancelPending.
2. Close sessions и drain async операций; pending network callbacks fenced epoch.
3. Store.finishWrites ждёт lease текущей txn; не начинает новых. Store.close только
   после исхода txn. При ошибке запись не объявляется подтверждённой.
4. Удалить capability/owner descriptor, закрыть activation; native finishExit
   уничтожает tray/window; host loop возвращает bootstrap, который освобождает lock.

Общий monotonic deadline 10 s. Таймаут — shutdownBlocked, окно visible, native tray
остаётся; Isar закрывается только когда безопасно. Повтор «Выход» продолжает с
первого незавершённого шага. Новые запросы не принимаются; нет force-kill самого себя.
OS session ending использует тот же путь, но ОС может прервать его; не блокировать
Windows. Уже подтверждённая Isar txn не зависит от успешного shutdown.

## Native codecs реализации v1

Activation descriptor `owner.json` — UTF-8 line codec с header `SDOWNER001`, затем
ownerEpoch, decimal PID, decimal FILETIME, userSid, logonSid, activation pipe, exePath;
каждое поле заканчивается LF, файл ≤8192 bytes. Расширение имени не определяет codec.
Activation wire — fixed Windows x64 POD: uint32 version, wchar_t epoch[37],
wchar_t requestId[37]; ack uint32 version/status (1 activated, 2 shuttingDown,
3 storageBlockedActivated). Проверяется фактический pipe peer; descriptor не authority.
Не менять codec без новой protocolVersion; MCP discovery003 имеет отдельный JSON codec.
