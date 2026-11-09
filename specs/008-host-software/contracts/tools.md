# MCP и общий owner

Протокол MCP2025-11-25, существующий EXE/pipe/actor/gate003. Registry contractVersion3:
21 существующий tool без изменения +6 ниже =27. Реестр фиксирован на сессию.
Обе копии assets/mcp/tools.json и specs/003-ssh-mcp/contracts/mcp-tools.json идентичны.
Точные JSON Schema2020-12 создаются при реализации этих шести tool, без регистрации заглушек.

## Shell и конфиги

Используются существующие console.profiles/list/open/read/acquire/release/write/close
из [007](../../007-server-console/contracts/mcp-console.md), без новых exec/file tool.
Консоль открывает канал существующего подключённого SSH transport. Ввод, lease,
confirmedMultiline, operationSequence, ownerEpoch, generation и ошибки берутся из007.
Это транспортный контракт консоли, без отдельного разрешения установки ПО.

ИИ использует обычные команды ОС для конфигов и перезапуска служб. Приложение
не разбирает файл и не составляет команды. Нет автоматических connect, sudo,
вставки credentials, повторной отправки и обещания отката. Ответ write — отправка
ввода, не exit status команды. Живая история/пределы/очистка остаются по007.

## Общие формы

Доменные ответы003: {ok:true,value,meta:{dataRevision,ownerEpoch}} либо
{ok:false,error:{code,field?,retryable,messageKey}}. Ошибки не включают входные данные.
Actor, clientId автора, времена и target не принимаются из JSON.
Неизвестные/дублирующиеся поля и неверные типы отклоняются; числа без coercion.
card={name,version,service,dataPaths,configPaths}: все пять полей обязательны,
version/service могут быть null; это full replacement, не patch.
CardView/EventView и пределы — [модель](../data-model.md).

| Tool | Вход | value |
|---|---|---|
| software.list | profileId,limit?,cursor? | {items:[CardView],nextCursor} |
| software.get | softwareId | CardView |
| software.save | profileId,softwareId?,expectedRevision?,mutationId,card | MutationValue |
| software.delete | profileId,softwareId,expectedRevision,mutationId | MutationValue |
| software.history.list | profileId,softwareId?,limit?,cursor? | {items:[EventView],nextCursor} |
| software.history.add | profileId,softwareId?,mutationId,action,summary,outcome | MutationValue(eventId,revision1) |

Save create omits softwareId/expectedRevision together; update supplies both.
MutationValue={entityId,revision,replayed}; local delete requires no remote confirmation.
Expected revision1..safeJSON. mutationId follows003: printable ASCII1..128.
UI uses the same owner and validation, with a native UiActor.
MCP uses existing valid grant, including existing grants; no softwareControl flag,
scopes, per-operation approval, plan, stage or job protocol is added.
Current auth is checked before lookup/replay, at transaction boundary and response,
using existing DomainCommandGate. For save/delete/note, committed receipt lookup
precedes profile/entity/revision/target checks; replay returns only the previous
MutationValue even after profile deletion and does not recreate records.
Without a matching receipt, perform those checks before the new effect.
No credentials or grants are returned by these tools.

## Pagination и ошибки

limit default25,1..100. Lists order cards by (createdAt,softwareId) ascending, events by
(createdAt,eventId) descending. Cursor — bounded≤512 canonical base64url JSON
{v:1,kind,profileId,softwareId:null|string,snapshotRevision,offset}; captures exact
method/filter (history softwareId versus null). Check current auth/profile first,
then cursor; wrong kind/filter/malformed => INVALID_ARGUMENT, changed snapshotRevision
=> CONFLICT. snapshotRevision uses the existing AppSettings.profilesListRevision, shared by
profile and software inventory changes. Software mutations advance this counter
atomically with dataRevision; profile changes already advance it. Auth-clock/grant
bookkeeping does not change the inventory snapshot. meta.dataRevision remains the
global revision. Cursor is an offset, not an authority token; no cursor HMAC service.
Неактуальная цель карточки не блокирует её чтение или чтение журнала.

Полный JSON-RPC response с text+structuredContent≤1MiB. Уменьшать фактическое число
items до вместимого, nextCursor сдвигать на реально выданное число; не усекать поля.
Одиночная карточка≤32KiB; одиночное событие≤8KiB включая цель/автора. Empty list
returns items:[],nextCursor:null. В пределах одного запроса читается согласованный snapshot.

Используются INVALID_ARGUMENT,PROFILE_NOT_FOUND,CONFLICT,RESOURCE_EXHAUSTED,
AUTH_REQUIRED,ACCESS_REVOKED,GRANT_EXPIRED,STORAGE_UNAVAILABLE,SHUTTING_DOWN003.
Добавляется только SOFTWARE_NOT_FOUND. Несуществующая карточка/чужой profileId
для save/delete/note дают SOFTWARE_NOT_FOUND, не меняют данные. Changed endpoint
при update/note карточки даёт CONFLICT. Delete не удаляет журнал и не вызывает SSH.

## Интерфейс

Вкладка ПО: список/поиск по текущей странице, форма пяти полей, локальное удаление,
история профиля/карточки и переход в существующую консоль. Поиск не скрывает
существование других страниц: он явно обозначен как фильтр показанной страницы.
Для старой цели видны host/port/username и пометка; console shortcut disabled.
Notes отображаются как сообщения автора, исход — сообщённый им.
Кнопка анализа готовит текст задания с profileId/хостом и введённым списком ПО,
копирование выполняется только по явному нажатию. UI не запускает ИИ и shell-команды.
Предложения обсуждаются во внешнем клиенте; сохранение — software.save без special discovery RPC.
