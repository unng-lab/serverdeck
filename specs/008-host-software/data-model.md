# Модель данных

Две additive-коллекции в существующей Isar, storage format2. Один DomainRepository.
IDs UUIDv4 lowercase; revision и UTC timestamps — safe JSON integer; revision≥1.
Все строки — корректный Unicode без NUL. Поля не исполняются как команды.

## SoftwareCardRecord

| Поле | Правило |
|---|---|
| id | Внутренний Isar auto ID |
| softwareId | Уникальный business ID |
| profileId | Индекс существующего профиля |
| endpointId, host, port, username | Снимок цели из профиля при создании; endpointId по существующим правилам 003 |
| name | Trim,1..100 символов |
| version, service | null или trim-строка≤256 символов |
| dataPaths, configPaths | Каждый список≤16 уникальных абсолютных POSIX-путей,≤1024 UTF8 bytes на путь, без CR/LF/NUL; literal, без чтения/нормализации файлов |
| revision | +1 на изменение |
| createdAt, updatedAt | Назначает owner |

Полная публичная карточка≤32KiB canonical JSON UTF8. Оба списка могут быть пустыми.
Имена не уникальны. Сохранение заменяет все пять пользовательских полей целиком.
Автор не передаёт target, revision или timestamps внутри card.

CardView={softwareId,profileId,target:{endpointId,host,port,username},currentTarget,
name,version,service,dataPaths,configPaths,revision,createdAt,updatedAt}.
currentTarget вычисляется сравнением endpointId с текущим профилем, не хранится.
Список профиля возвращает все его карточки с исходной целью, включая currentTarget=false.
UI отмечает такой хост и не предлагает открыть его конфиг в текущей консоли профиля.
Изменение карточки другой цели даёт CONFLICT; локальное удаление разрешено.
Новая карточка получает текущую цель. Смена адреса не переписывает существующие строки.

## SoftwareEventRecord

| Поле | Правило |
|---|---|
| id, eventId | Внутренний auto ID; уникальный business UUID |
| profileId, endpointId, host, port, username | Профиль и снимок цели события |
| softwareId, softwareName | Nullable; индекс softwareId, снимок имени для истории после удаления |
| kind | created / updated / deleted / note |
| action | Для note: install / update / remove / configure / analyze / status / other; иначе null |
| summary | Для note1..2048 UTF8 bytes; для CRUD фиксированный текст по kind |
| outcome | Для note success / failed / unknown; для CRUD null; сообщено автором |
| changedFields | Для updated: изменённые имена из name/version/service/dataPaths/configPaths; для остальных[] |
| actorKind, clientId | ui/mcp; clientId только для MCP, из доверенного actor |
| createdAt | Назначает owner; индекс для eviction/выдачи |

EventView возвращает эти публичные поля, кроме внутреннего id. Нет raw command,
stdin, output, credentials, config content или ссылок, которые дают права на файлы.
Журнал хранит последние10000 событий всего store; при добавлении удаляются самые
старые по (createdAt,eventId). UI сообщает этот предел. Карточки не вытесняются:
максимум10000/store и1000/profile, новая запись сверх лимита RESOURCE_EXHAUSTED.

## Транзакции и связи

Save/delete/note: текущая авторизация actor → existing receipt → при отсутствии
receipt проверка профиля и карточки → expectedRevision/currentTarget → новый эффект.
Committed replay не требует существования профиля/карточки и не восстанавливает их;
отзыв доступа блокирует replay. Для нового save:
изменение карточки + событие + существующая MutationReceipt + AppSettings.dataRevision
и AppSettings.profilesListRevision (общий inventory snapshot профилей/ПО)
в одной транзакции. Create выдаёт UUID owner; update сохраняет softwareId/target/createdAt.
При неизменных пользовательских полях save всё равно создаёт новую редакцию и событие updated.
Delete: тот же порядок; физически удаляет карточку, добавляет deleted с именем/целью;
MutationValue.revision=предыдущая+1. Записи истории не удаляются вместе с карточкой.
Удаление профиля каскадно удаляет обе коллекции по profileId; нет remote cleanup.

Используется существующий ReceiptBook003: metadata-result, окно24h, прежняя квота
и политика очистки; новые методы enum — saveSoftware/deleteSoftware/addSoftwareNote.
Повтор в окне возвращает прежний MutationValue до stale/notFound-проверок, не
дублируя событие. После истечения окна create может создать новую запись:
клиент сверяет software.list, прежде чем повторять потерянное создание.
Для удалённого shell действуют только правила повторов консоли007.

Курсор использует snapshotRevision=profilesListRevision. Этот существующий счётчик
продвигается каждым новым software-эффектом и профильными изменениями, включая
удаление/смену endpoint. Replay его не меняет. Global dataRevision остаётся общей
метадатой ответа; проверки auth-clock не инвалидируют страницы inventory.

История note с softwareId принимает только существующую карточку того же профиля
и текущей цели; без softwareId относится к текущему хосту профиля. История удалённой
карточки читается по индексу softwareId без требования существования карточки.
Список событий всегда ограничен profileId; индексирование не допускает полного scan для карточки.
