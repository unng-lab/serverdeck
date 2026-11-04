# Data model — runtime 002

## Постоянные записи

Все timestamps — UTC milliseconds int64; UUID — canonical lowercase UUIDv4.
Внутренний Isar Id не является публичным ID. Строки не содержат NUL.

| Record | Поля / инварианты |
| --- | --- |
| AppSettings (Isar id=1) | logicalFormat=3; settingsRevision≥1; dataRevision≥1; profilesListRevision≥1; theme=dark/light (default dark); mcpEnabled=false (зарезервировано); createdAt; lastSuccessfulOpenAt |
| StoreManifest (CURRENT) | formatVersion=3; storeId UUID; relativeDirectory=`stores/<id>`; publicationVersion=1; никакого секрета |
| PayloadManifest (RCDATA) | format=1; hostAbi=1; platform=windows-x64; files path/size/sha256; payloadId=SHA256 canonical manifest bytes |
| RuntimeDescriptor | ownerEpoch UUID; pid; processCreationTime (Windows FILETIME); userSid; logonSid; activation pipe name; actualExePath; protocolVersion=1 |

CURRENT и runtime descriptor — малые native metadata с ACL пользователя; это не
дублированная модель профилей. Descriptor не является доказательством identity:
проверяется фактический процесс peer средствами Windows. [Хранение](contracts/storage.md).

## In-memory owner

RuntimeState: `starting → running | storageBlocked`; любой активный state →
`shuttingDown → terminated | shutdownBlocked`. В storageBlocked запрещены domain
операции, разрешены retryOpen, openWindow и tray exit. Running требует открытой Isar.
После shutdownBlocked нет возврата к running, разрешён повтор tray exit.
WindowState: visible/minimized/trayHidden; переход в trayHidden разрешён только
после подтверждённого доступного native tray. Черновики — память UI, не Isar;
обычное скрытие сохраняет, shutdown/restart отбрасывает.

CapabilityRegistration: уникальный id, stopAdmission(), cancelPending(),
closeSessions(), drain(), dispose(); registered до running, calls идемпотентны.
Stop admission и beginWrite проходят одним coordinator gate. Начатая транзакция
получает lease и завершается/откатывается до store close. Capability failures
не превращаются в успешный shutdown; retry вызывает только незавершённые стадии.

## Не сохраняем

Живые handles, активные соединения, pending confirmations, UI controllers,
положение focus, passphrase и window hidden flag. После полноценного запуска
окно всегда видно и SSH не возобновляются автоматически. Restore в этой спеке —
возврат существующего окна из трея с его in-memory state, не восстановление SSH.

## Форматы и расширение

Приложение использует текущий logical format3 с полным schema set [003](../003-ssh-mcp/data-model.md). Любой другой формат отвергается до открытия Isar. Миграций/old-schema adapters нет; при ошибке данные не удаляются и не заменяются. Schema генерируется из текущих Dart models, generated files проверяются вместе с текущим кодом.

`dataRevision` увеличивается одной txn на каждое durable domain изменение;
`profilesListRevision` — только при CRUD профилей, используется для cursor invalidation.
Live connection state имеет ownerEpoch/attemptGeneration и не требует Isar write на каждый ping.
