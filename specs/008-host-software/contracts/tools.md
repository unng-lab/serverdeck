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

### Компактная карточка ПО — 2026-11-10

По уточнению пользователя используется готовая таблица C06 `DeckCollection`
с adaptive layout и текущей порцией записей. Колонки: «Название», «Версия»,
«Служба», «Хост». В Хост — исходный `username@host:port` и C10 «Другой хост
профиля» при currentTarget=false. Неизвестные version/service — «Не указана».
Полные значения переносятся; встроенный узкий вариант C06 сохраняет колонки
как подписанные поля. Отдельные карточки/аккордеоны ПО не используются.
Сортировка/checkbox selection не добавляются: существующий порядок и paging
сохраняются, выбранный softwareId передаётся в selectedIds для обозначения строки.

Действие C02 «Подробности» в строке выбирает запись; повторное нажатие закрывает
сведения. Только одна запись выбрана за раз, выбор другой заменяет предыдущую.
Ниже таблицы одна область C09/C18/C28 с полными названием, версией, исходным
selectable адресом, службой, selectable списками «Данные»/«Конфиги» (путь на строку,
пусто — «Нет сведений»), «Изменено» UTC с прежним fallback и C02/DeckActions:
«Изменить карточку», «Удалить карточку», «История карточки», «Открыть консоль».
В области есть «Закрыть подробности». Подробности не открывают новую загрузку.

Сохраняются callbacks и ограничения: pending блокирует изменение/удаление/историю;
консоль определяется currentTarget и прежним callback. Другая цель запрещает
изменение и консоль с доступным объяснением, но не удаление/историю. Сохранение
или удаление меняет только локальный учёт; conflict/recovery остаются прежними.
Выбор строки не выполняет эти действия. Enter/Space активируют C02 «Подробности»;
доступны имя кнопки и selected semantics строки C06.

Локальный selectedSoftwareId сохраняется при refresh для оставшейся записи и
показывает новые значения. Профиль/страница/фильтр ПО сбрасывают выбор,
исчезнувшая запись закрывается; ошибка загрузки сама по себе выбор не очищает.
Новые строки не выбираются автоматически. Перезапуск начинает без выбора,
UI-состояние не пишется в store и не связано с раскрытием событий.
Общие API C06/C02/C09/C18/C28/C10, темы/каталоги001 не меняются; новых runtime,
MCP/schema/version/storage полей или зависимостей нет. Геометрия C06 принадлежит
001, feature acceptance проверяет данные/действия AC-814/815.

### Компактное событие истории — 2026-11-10

Для истории хоста и карточки используется готовый список C07 `DeckListItem`
с compact=true: title — тип и имя, description — превью, statusLabel — автор,
время и сообщённый outcome, trailing C02 «Подробности события». Отдельной внешней
карточки C09 и C19 нет. Изначально подробности закрыты; в сводке доступны:

- Тип: created → «Карточка создана», updated → «Карточка изменена»,
  deleted → «Карточка удалена», note → «Сообщение»; рядом softwareName snapshot,
  при null — «Хост». Тип и имя не сокращаются, переносятся по ширине.
- Автор: «Пользователь» для ui, «MCP: <clientId>» для mcp; не подставлять
  текущего пользователя или новое имя удалённой карточки.
- Время createdAt в UTC существующим `_time`, с прежним fallback `<millis> ms UTC`.
- Только если outcome не null: «Сообщённый исход: <outcome>» (success/failed/unknown).
  Это текст автора, без индикатора проверенного состояния службы.
- Превью summary: серии whitespace (`\s+`, включая переводы строк/табуляцию)
  заменить одним пробелом, trim; до160 Unicode code points включительно оставить
  весь текст, при длине161 и более взять первые159 и добавить «…» (итог160,
  включая многоточие). Пустой результат — «Без текста».
  Превью использует готовую однострочную description C07 с ellipsis; полное содержимое
  всегда доступно в подробностях. Storage/MCP не нормализуют и не сокращают summary.

Нажатие строки или C02 «Подробности события» открывает/скрывает область C18
сразу после соответствующей строки. В подробностях последовательно показать: «Событие»
(`<kind> · <softwareName или Хост>`), «Цель» (`username@host:port`),
необязательные «Действие», «Сообщённый исход», непустые «Изменённые поля»
(исходные имена через запятую), «Источник», «Время события UTC», «Сообщение».
Цель и полное summary selectable; summary отображается в точности, включая
переводы строк/Unicode, с естественной высотой. Здесь не используется C20
DeckLogMessage с фиксированной областью текста; общий C20 не меняется.
Текст только отображается: не исполняется, не трактуется как Markdown/команда,
не копируется автоматически и не дополняется credentials/terminal transcript.

Раскрытие хранится локально по eventId, независимо от раскрытия карточек ПО.
Несколько событий могут быть открыты одновременно. Refresh сохраняет оставшиеся
id, новые события закрыты; исчезнувшие из выдачи/retention id забываются.
Профиль (включая endpoint/owner), страница истории и смена фильтра история
хоста/карточки сбрасывают события. Фильтр/страница списка ПО сами по себе
события не сбрасывают, если контекст истории не изменился. Если существующий
refresh возвращает историю на первую страницу, это смена страницы со сбросом.
После перезапуска всё закрыто; сохранения UI-состояния в store нет.

Enter/Space и pointer активируют строку C07 или C02; доступны имя «Подробности
события» и expanded/collapsed semantic state на действии. Выбранное состояние
C07 соответствует открытым подробностям.
Раскрытие/сворачивание не создаёт сетевых/доменных вызовов и событий журнала.
Сортировка, paging, ошибки/loading/empty, retention10000, форма заметки и
история после удаления карточки сохраняют действующие контракты.
Компоненты/темы/каталоги001, модели, зависимости, runtime и MCP registry не меняются.
