# Current storage contract — format3

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

## Current store open

Manifest publicationVersion1/logical format3 — единственный текущий контракт. Формат1 и автоматическое copy/migrate/backfill не поддерживаются по principleVI constitution1.4.0. Неизвестный формат отклоняется до StoreBackend.open; originalCURRENT/source tree не изменяются и не заменяются пустойБД. Модуль store_manifest.dart владеет текущим manifest/preflight/publication guards; StoreBackend не имеет copyStore API. Fresh initialization и retry собственной непубликованной staging остаются обычным recovery текущей операции, не старымформатом.

## Unit test boundary

WorkspaceStore получает StoreBackend для initialize/open native Isar. Production
IsarStoreBackend сохраняет все параметры этого контракта; unit backend подставляет
in-memory Isar interface и проверяет вызовы/порядок/ошибки owner, без загрузки DLL.
Файловые guards проверяются на временных synthetic trees. Fake txn rollback не
является доказательством native durability; real-engine crash tests исключены
из обязательных проверок по решению пользователя, требования к данным сохраняются.
