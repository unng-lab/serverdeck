# Current storage contract — format2

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

Manifest publicationVersion1/logical format2 — текущий контракт. Формат1 и автоматическое copy/migrate/backfill не поддерживаются по principleVI constitution2.0.0. Неизвестный формат отклоняется до StoreBackend.open; originalCURRENT/source tree не изменяются и не заменяются пустойБД. Модуль store_manifest.dart владеет текущим manifest/preflight/publication guards; StoreBackend не имеет copyStore API. Fresh initialization и retry собственной непубликованной staging остаются обычным recovery текущей операции, не старымформатом.

## Unit test boundary

WorkspaceStore получает StoreBackend для initialize/open native Isar. Production
IsarStoreBackend сохраняет все параметры этого контракта; unit backend подставляет
in-memory Isar interface и проверяет вызовы/порядок/ошибки owner, без загрузки DLL.
Файловые guards проверяются на временных synthetic trees. Fake txn rollback не
является доказательством native durability; real-engine crash tests исключены
из обязательных проверок по решению пользователя, требования к данным сохраняются.

## Совместимые дополнения и версия формата — 2026-11-04

FR-221: currentStorageFormat=2; isCompatibleStorageFormat принимает только integer2.
AppSettings.logicalFormat и CURRENT.formatVersion проверяются одной политикой;
publicationVersion1, UUID/path/reparse/security/content проверки сохраняются.
Новые и существующие базы используют2. Нет переименования каталога, переписывания CURRENT или logicalFormat и копирования базы.
Отсутствие новой коллекции MonitoringHistoryRecord/JournalSource означает пустой
новый набор данных, а не повреждение существующих профилей/credentials/trust.
Их добавляет текущий schema set через штатный Isar open. Старые коллекции не
переименовываются, не удаляются и не меняют представление. Отдельных миграций нет.

FR-222: повышение версии допускается только с указанием конкретного несовместимого
изменения и сценария чтения/записи. Для нового поля нужен определённый результат
чтения отсутствующего значения; initializer без обоснования недостаточен. Изменение
типа/имени хранения/обязательных ограничений/смысла требует оценки сохранения данных.

Ошибка версии/повреждения не приводит к reset, конвертации или автоматическому retry
через пустую базу. Прежние schemas, API adapters и migration/backfill не добавляются.

AC-221: fake backend для CURRENT2 и AppSettings2 открывает тот же storeId,
сохраняет версии, theme/revisions/security и CURRENT bytes, не публикует замену.
AC-222: неподдерживаемый/unknown формат, повреждённый manifest/path/settings продолжают явно
отклоняться; unsupported manifest не вызывает backend.open или публикацию.
Unit fixtures проверяют adapter contract, а не реальную native durability.
Основание штатных schema additions: [Isar data migration](https://isar.dev/recipes/data_migration.html).

## Monitoring marker and first publication

The fixed `data/monitoring-run-v1.json` belongs to native monitoring and is
published before database startup. Missing CURRENT permits first publication when
this is the only file (and stores is absent/empty). Only an ordinary non-link file
of at most128bytes with the exact native version1 running/clean encoding is
recognized. Storage preserves its bytes. The same rule applies when the live owner
resumes its own pending UUID. Other files/directories and unrelated unpublished
stores still block; selected-store validation, format2, existing data and manifests
are unchanged. Synthetic tests cover both states, malformed/oversized/name/type
lookalikes, an unrelated orphan and retries before/after rename/CURRENT publication.
