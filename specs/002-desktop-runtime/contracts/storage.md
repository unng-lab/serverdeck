# Storage contract v1/v2

## Каталоги и authority

Known Folder LocalAppData: `ServerDeck/data/CURRENT.json`, `data/stores/<uuid>/`,
`ServerDeck/runtime/<payloadId>/`, `ServerDeck/owner.lock`, `ServerDeck/owner.json`.
Весь корень — ACL текущего пользователя и системного обслуживания, без прав записи
другим пользователям. Reject reparse points по пути данных/runtime/metadata;
не follow symlinks/junctions при создании/замене/очистке. Ошибка — STORAGE_IO, не reset.
Рабочая директория и путь EXE не участвуют в выборе data root.

Единственный WorkspaceStore в основном Dart composition root; Native никогда
не открывает Isar. MCP bridge читает только предусмотренные protected credential
blobs и owner descriptor, не Isar. Методы store доступны только domain owners,
не UI widgets или MCP router напрямую.

## Транзакции и secrets

Isar.open: named `serverdeck`, explicit absolute directory, `relaxedDurability:false`,
inspector disabled в release; native library инициализируется абсолютным путём из
проверенного runtime manifest, без download. Все write операции — один writer gate,
одна Isar writeTxn без network/file-picker/DPAPI-await внутри. Protect/decode входы
до gate; повторная проверка версий/authorization и commit admission внутри gate.
В txn secret bytes уже DPAPI-encrypted. Metadata+credential+trust+receipt changes
одной операции находятся в одной txn, внешнего credential vault на критическом пути нет.

Перед ответом success writeTxn завершена. При exception/OS termination recovery
показывает либо целиком прежний либо целиком новый набор; не угадывает по UI-state.
DPAPI failure ничего не пишет. Uint8List plaintext живёт только во время обработки,
по возможности очищается после использования; GC/runtime не дают гарантии стирания
всех копий, поэтому такая гарантия не заявляется. Secrets не попадают в diagnostics.

## Store open / format migration

CURRENT.json UTF-8: `{publicationVersion:1,formatVersion:1|2,storeId,relativeDirectory}`.
Строгая валидация UUID, relativeDirectory только `stores/<storeId>`, reject absolute/
traversal/case alias/reparse. CURRENT missing допускает создание только если data
каталог не содержит существующих store; неоднозначный orphan — ошибка восстановления,
не новый пустой workspace. Invalid/future format — INCOMPATIBLE_STORE без открытия Isar.

Новая установка создаёт staging store, пишет AppSettings в txn, закрывает и flush
файлы, публикует каталог и CURRENT через native same-volume atomic replace с flush.
До публикации store не считается рабочим. Initial failure leaves existing data unchanged.

Native allowlist для первой публикации: `file.flushAtomic` с path
`data/publish/<storeId>` и bytes CURRENT. Native flush всех файлов
`data/staging-<storeId>`, rename в `data/stores/<storeId>`, затем atomic CURRENT.
`data/CURRENT.json` — отдельный allowlisted metadata path для последующих публикаций.
Произвольные пути не принимаются; версия/поля CURRENT проверяются Dart preflight.
При transient failure живой owner сохраняет storeId своей начальной публикации и
продолжает только её. Native publication идемпотентно принимает либо staging, либо
уже переименованный destination, но не оба. Потеря ack после CURRENT проверяется
обычным preflight того же storeId. Любой посторонний orphan остаётся ошибкой.
После process restart in-memory identity потеряна; неизвестные unpublished stores
не принимаются автоматически и не удаляются.

002 поддерживает logical format 1. 003 требует format 2: под owner lock закрыть
store, скопировать весь format1 directory в новый staging UUID, открыть копию полным
schema set2 и мигрировать AppSettings.logicalFormat=2 в txn. После close/flush
проверить reopen/read invariants, затем atomic replace CURRENT. Старый каталог
сохранён; ошибка не меняет CURRENT, не стирает источник. Runtime2 открывает только
CURRENT format2; старый бинарник002 отказывает до открытия format2. Автоматического
fallback к old store после публикации нет: он потерял бы новые записи. GC/migration
назад не входит в эти пакеты. Для уже format2 повторная миграция не выполняется.

Все validation/repair failures видны пользователю с retry; при fatal data error
read/write/MCP admission blocked, не возвращается пустой success. Read retry повторно
открывает тот же выбранный store, не ищет «подходящую» другую версию.

Любое несовместимое изменение schema set требует нового logical format до open.
Смешивание старой структуры и новой metadata под тем же format запрещено.


## Unit test boundary

WorkspaceStore получает StoreBackend для initialize/open native Isar. Production
IsarStoreBackend сохраняет все параметры этого контракта; unit backend подставляет
in-memory Isar interface и проверяет вызовы/порядок/ошибки owner, без загрузки DLL.
Файловые guards проверяются на временных synthetic trees. Fake txn rollback не
является доказательством native durability; real-engine crash tests исключены
из обязательных проверок по решению пользователя, требования к данным сохраняются.
