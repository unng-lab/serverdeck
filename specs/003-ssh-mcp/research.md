# Исследование: локальный MCP-доступ

Дата: 2026-11-02. Решение применяется к [спеке 003](spec.md), нормативная модель —
[mcp-access](mcp-access.md). Пользователь просил проработать вход с своего компьютера,
токен/Windows Pipe и защиту, сохранив одно поставляемое приложение.

## Варианты

| Вариант | Преимущества | Ограничения и решение |
| --- | --- | --- |
| Streamable HTTP на loopback + bearer | Стандартный MCP transport, клиенты подключаются по URL | Loopback сам не удостоверяет Windows-пользователя. Нужны секрет, Origin/Host-защита и отдельное решение идентичности локального endpoint. В 003 не используется. |
| Только Windows Named Pipe | DACL и Windows token позволяют ограничить локального пользователя/сессию | Это не штатный транспорт большинства MCP-клиентов; один SID не даёт отдельного отзыва для клиента. Без stdio-моста и разрешения недостаточно. |
| Stdio того же EXE → защищённый Named Pipe → основной экземпляр | Совместимость стандартного stdio MCP, Windows-ограничения и отдельные отзываемые разрешения; нет сетевого порта и отдельного дистрибутива | Нужен транспортный процесс того же EXE. Выбран: он не владеет базой, SSH, треем или domain operations. |

## Вывод

Выбран третий вариант: локальный Named Pipe и per-client capability, которую
штатный stdio-мост получает из DPAPI-защищённого пользовательского blob. Пользователь
подтверждает разрешение в UI, затем использует готовые command/args без ручной передачи
секрета. Браузерная авторизация/OAuth для этого локального stdio-подключения не нужна.
Выбранная модель — проектное решение, не требование стандарта MCP.

Не обещается изоляция вредоносных процессов под тем же Windows-пользователем;
DACL и DPAPI защищают границу пользователя ОС, а не создают sandbox клиента.

## Первичные источники

- [MCP transports 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports):
  стандартные stdio и HTTP, запуск stdio-сервера клиентом, чистый stdout.
- [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization):
  HTTP authorization и альтернативные правила для stdio/других transports.
- [Microsoft: Named Pipe security](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights):
  явный DACL, опасность default доступа, ограничения logon SID.
- [Microsoft: CreateNamedPipeW](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-createnamedpipew):
  first-instance flag и отклонение remote clients.
- [Microsoft: server process identity](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid):
  получение PID server end средствами Windows.
- [Microsoft: impersonation](https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-impersonatenamedpipeclient):
  проверка ошибки идентификации и возврат исходного контекста.
- [Microsoft: DPAPI CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata):
  защита CurrentUser; machine scope не подходит для секрета одного пользователя.


## R301 — библиотека SSH и строгая политика

**Decision**: vendor dartssh2 4.1.0, archive SHA256
`39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51`, сохранить лицензию
и небольшой policy patch: raw host blob callback, rekey-change notification,
chosen-method-only и управляемый handshake timer. [Точный контракт](contracts/ssh.md).
**Rationale**: pure Dart, OpenSSH encrypted Ed25519/RSA; verification await до auth.
Upstream callback не даёт raw blob, fingerprint уже encoded SHA256 string.
Начальная очередь upstream допускает none в некоторых absent/null credential путях;
это не неизбежный fallback после обычной ошибки пароля, но строгий adapter не
должен зависеть от таких скрытых путей. Policy patch делает поведение явным.
**Alternatives**: внешний ssh.exe запрещён поставкой/скрытыми auth settings;
полностью новая SSH-реализация не нужна. Upstream без patch не даёт нужный raw hook.

По исходникам проверены callback order/algorithms/rekey и constructor timers.
В отдельном temp research package успешно импортированы настоящие encrypted
Ed25519/RSA2048 fixtures, отказ wrong passphrase и unencrypted round-trip.
Живой SSH-сеанс приложения не тестировался. Источники:
[dartssh2-4.1.0](https://pub.dev/packages/dartssh2/versions/4.1.0),
[immutable archive](https://pub.dev/api/archives/dartssh2-4.1.0.tar.gz).

## R302 — запись и миграция

**Decision**: общий формат2 с DPAPI ciphertext внутри той же Isar txn, не внешний
vault с двухфазной неопределённой записью. CURRENT preflight до open, migration на копии.
**Rationale**: атомарные profile/credentials/trust/receipt mutations и безопасный downgrade
guard. [Контракт002](../002-desktop-runtime/contracts/storage.md).
**Alternatives**: secret path-only, sidecar plaintext и отдельная база MCP отвергнуты.

## R303 — один owner и wire contract

**Decision**: typed AppOperations + строго allowlisted13tools с локальными JSON schemas,
версионные fences, bounded owner FIFO. Windows broker проверяет реальные peer identities,
Dart owner проверяет canonical grant каждый раз. Endpoint security не передаётся
самодекларации client JSON. [Operations](contracts/operations.md), [IPC](contracts/ipc.md).
**Rationale**: нет второй модели данных/полномочий; запрет delete проверяется и в domain,
и в опубликованном router. **Alternatives**: generic exec/shell/delete admin endpoint
не нужны; сетевой MCP сервер не выбран.
