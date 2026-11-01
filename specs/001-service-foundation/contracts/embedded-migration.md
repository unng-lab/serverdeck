# Целевое хранилище и отказ от legacy — поправка той же001

**Direct SSH amendment 2026-11-01**: [действующий контракт](direct-ssh.md). Новое выполнение использует прямой SSH без устанавливаемого executor/Ansible/enrollment. Прежние описания этих компонентов ниже относятся только к historical format1; они не разрешают его исполнение или fallback. Остальные правила данных, прав и лимитов сохраняются. При конфликте в исполнительной архитектуре действует поправка.

Действующее решение пользователя2026-10-30: никакой обратной совместимости,
никаких переходных runtime/обёрток или старого кода в результате этой задачи.
Этот контракт заменяет прежний план adoption/return; завершённые review reports
сохраняют историю своих редакций и не устанавливают готовность этой новой правки.

## Единственный поддерживаемый путь

Один app executable с engine и MCP mode; [engine](embedded-engine.md),
[021 MCP](../../021-mcp-control/contracts/embedded-host.md). Старый locald/bootstrap/
Local API client transport и standalone mcp entry отсутствуют. Не распознавать
старые discovery/bundle/API протоколы, не запускать legacy, не делать fallback.
Внешний MCP сохраняет функции/права продукта, но старые локальные клиенты не поддерживаются.

Целевой store — schema3/format3 с нынешними foundation/host-trust/automation
record families, IDs/revisions/credentials/trust/enrollment/history/settings.
Его layout и DPAPI bindings сохраняются, потому что смена process owner не требует
нового storage format. Это прямое открытие целевого формата, не compatibility layer.
Нейтральный `engine/storage/models.dart` имеет один `WorkspaceState.fromJson`
и `empty` для schema3; отдельных legacy/trusted режимов или schema1 view нет.
`engine/automation/snapshot.dart` принимает только проверенный `HostTrustState`,
всегда разбирает plans по schema3 и захватывает все десять коллекций до async
проверок. Исторические profiles/credentials/receipts, trust counters и ссылки
проверяются без изменения IDs/blobs/revisions. Этот логический parser не открывает
файлы/Isar, не выдаёт sessions/grants/permissions и не заменяет native preflight.
`engine/storage/key_custody.dart` сохраняет существующие receipt/credential
wrappers, canonical HMAC и точные entropy bytes. Их внутренние format/version1
остаются частью целевого schema3 payload, а не поддержкой schema1 workspace.
Защита OS-user принадлежит vault provider; persisted owner SID проверяется
workspace/custody gate до использования blobs. Смена только поля SID в объекте
custody не считается сменой OS-user proof. Manifest helpers принимают только3.
Подготовка profile/settings/trust mutation имеет один schema3 путь с обязательным
HostTrustState и PreparedMutation.trust; она не авторизует и не фиксирует запись.
Иные схемы/версии, в том числе1/2, отклоняются до writable open. Их migration
parsers/upgrade chains/journals и rollback/downgrade routines не входят в новый engine.
Возврат к старым binary не поддерживается и не рекламируется. Нет snapshot restore
поверх новых данных, plaintext bridge или импорта сервиса до ServerDeckNext.

## Ownership, safe open and failure

Путь `%LOCALAPPDATA%/ServerDeckNext/v1/workspaces/default` и детерминированная
блокировка writer сохраняются для единственного существующего workspace. Namespace
lock — защита от второго writer, не поддержка протокола старого процесса.
Занятый lock → отказ WORKSPACE_IN_USE, без подключения к legacy endpoint/kill/stop.

1. Verify app/native runtime/owner/path/ACL, acquire writer lease.
2. Read-only проверить exact target schema3/manifest/semantic rows/custody bindings.
   Неизвестный формат, legacy migration residue или несогласованные файлы дают
   INCOMPATIBLE/STORAGE_BLOCKED по безопасной категории, без изменения файлов.
3. Открыть один store с прежними ID/revisions/secret wrappers/trust; нет key rotation
   ради новой архитектуры. Missing/locked/corrupt vault не равен new workspace.
4. Новый workspace создаётся только при доказанном отсутствии прежних файлов,
   в атомарном target-schema3 initialization staging. Legacy upgrade staging не
   принимается как новый initialization. Runtime sessions/challenges/одноразовые
   permits после restart не воскресают, история согласий остаётся историей.
5. Local recovery до Ready: отправленные nonterminal attempts unknown, без replay;
   cached observations stale. Ready не требует сети и не подтверждает host key.
6. Только Ready публикует новый app discovery. Close failure удерживает reservation/
   lease до завершения процесса. Некорректный format/key не создаёт пустую замену.

Полностью сохранять foundation/host_trust/automation rows и protected artifacts,
MCP grants/expiry/revocation/files, controller/executor identity. Не публиковать
секреты/приватные значения. Несовместимые данные остаются нетронутыми, автоматического
удаления/сброса/замены нет. Приложение объясняет неподдержанный формат; это не обещание
переноса старого формата и не основание оставлять старый код.

## Удаление старой архитектуры в этой же задаче

После переноса используемой доменной логики удалить packages/serverdeck_locald,
его bin/bootstrap/services оболочки; standalone MCP bin/build paths; устаревшие
UI bootstrap/IPC clients; protocol parsers/manifests/roles и Windows helpers,
нужные только заменённым режимам. Не оставлять re-export facades/deprecated modes.
Сохранить только helpers, которые используются целевым engine/MCP/platform adapter.
Удалить tests/fixtures/scripts/workflows только для удалённых возможностей;
проверки сохранённого поведения перенести на новый owner, не ослабляя assertions.
История остаётся в Git/документах завершённых задач, не в production compatibility code.
Чужой003 worktree/процессы/установка не меняются.

AC-SVC-EMB-04/05/06: target-schema3 record/blob roundtrip, wrong owner/vault/lease/
close faults и отказ схем1/2/unknown/legacy residue без записи. AC-SVC-EMB-15:
в целевых source/test/build/workflow inputs нет старого runtime/compatibility entry/
переходной оболочки; сохранённые функции покрыты unit tests нового engine.
Native/DPAPI/Isar/real SSH acceptance в текущем scope не выполняется.


## Schema3 row capture boundary

`engine/storage/workspace_rows.dart` содержит неизменяемый StoredRow
(nativeId/entityId/exact payload) и borrowed WorkspaceRowSource. Source не открывает
и не закрывает DB/lease, не выдаёт authority; count/read внутри readTransaction
обязаны видеть одну committed view. Read ограничен cap+1, negative count или
несовпадение количества с полным bounded read дают STORAGE_BLOCKED. Native Isar
adapter читает существующий handle с теми же16 generated collections, без init/open.
Максимальный limit51251 покрывает desired: (250profiles+10000deleted-profile receipts)
×5+1; остальные коллекции ограничены прежними caps, не новым общим51251quota.

`workspace_snapshot.dart` проверяет только schema3, существующий default или
строго пустой default.creating, owner/lease/defaultslot/path/ACL, singleton IDs,
дубликаты, byte/count bounds, foundation/trust/automation graph, credential bindings.
Все16коллекций захватываются одной read transaction до async custody checks.
Возвращаемая WorkspaceSnapshot сохраняет raw IDs/payloads; это не живая authority.
После полной проверки обычный loader сверяет MCP artifacts и восстанавливает lookup
из committed grants. Creation loader принимает только исходный пустой graph.
Этот loader работает с уже открытым borrowed source и может публиковать lookup;
он НЕ заменяет read-only semantic preflight ДО writable open из шагов safe open.
Read-only gate реализован отдельно в `storage/preflight.dart` и описан ниже;
полная приёмка T262 также требует Host composition и проверок сохранности T263.

Старые WorkspaceMigration, source2 preflight, upgrade snapshots/digests и migration
journal удалены из runtime. Наличие legacy residue по-прежнему приводит к отказу,
а не к очистке или продолжению upgrade. Прочие старые store/bootstrap modes
подлежат удалению T276; target capture не содержит их selectors или facade.


## Единственный repository/queue path

StateStore больше не выбирает schema1/2/3 через entry/mode/format boolean: open
принимает только target3, snapshot содержит все16коллекций, foundation commit —
HostTrustState. MCP grants/catalog writes используют тот же store и тот же shared32
queue. MutationCoordinator имеет один constructor с обязательным custody binding,
сохраняет receipts/HMAC/claim lifecycle; старых legacy/operational subclasses нет.
Старые native adapters не дают дополнительных прав из-за имени метода store:
они по-прежнему обязаны проверить реальную session/target/publication gate.
Удалены schema1 creation/commit/read-key и schema2 snapshot/commit helpers.

Нейтральный retainRowIdentities планирует rows только после caller graph/CAS/custody
проверок. Неизменённые JSON docs сохраняют прежние exact bytes и native IDs;
обновляемые сохраняют IDs, новые получают следующий ID после старого maximum,
включая удаляемые этим планом строки. Переполнение int64 отклоняется.
Эта гарантия относится к входному snapshot, не к вечному high-water mark: после
удаления строки в прежнем commit её native ID может встретиться у новой entity.
Native ID не является business identity и не используется для ссылок или Local API.
Все unrelated collections, commit atomicity/capacity abort proof и readback остаются
обязанностью repository. Наличие плана не является разрешением на запись.


## Read-only native semantic gate before writable open

`engine/storage/native_schema.dart` теперь имеет один NativeWorkspaceRows reader
для exact schema3, не отдельный metadata-only public entry. Он копирует bounded
snapshot≤64MiB, проверяет pinned MDBX meta/geometry/catalogue/_info и извлекает все16
collection trees без native calls. Полные/неполные meta transactions различаются;
повторяющиеся complete positive transaction IDs отклоняются как meta clash
даже при одинаковом GC/main view; normal pinned native open их не допускает. Полный
transaction вне supported positive int63 диапазона отклоняется, не выбирается как
предлог fallback. Steady signature выбранного meta обязана быть UINT64_MAX (Dart VM -1);
0/1 и прочие значения не допускаются. Geometry lower/upper/now проверяется
по pinned x64 bounds:3≤lower≤now≤upper≤0x80000000, first_unallocated≤now;
никакая native correction или fallback после gate не допускается. Capacity upper
может быть больше текущей длины файла и used pages, это не другой формат.
Node spans, branch ordering, referenced-page uniqueness,
overflow extents и tree counters проверяются с ограниченными depth/count/value.
Committed non-DUPFIX pages требуют чётного upper; branch содержит минимум2nodes,
leaf минимум1node. Пустые деревья представлены descriptor без root, не empty page.
Transaction ancestry повторяет pinned readonly path: root page.txnid≤tree.mod_txnid
(если mod_txnid=0, пределом служит snapshot transaction); branch child и overflow
не новее содержащей parent page/leaf. Все page txn также≤selected transaction.
Этот gate применяется до native open, не заменяется post-open readback.

Формат взят из закреплённых recipe source archives: Isar commit
4c2cd02d4e5c17b7edca89d141d1729ddc1698ff, MDBX commit
924581bdc8a1e217139c1d286c1ffb0ef0f9d14d, ABI3.3.2 little-endian64bit.
Isar native ID — little-endian uint64 с перевёрнутым sign bit; только positive
int63 IDs допустимы для product rows. Native object имеет u16 static size и u24
String offsets/lengths:5bytes singleton или8bytes entityId+payload. Bounds,
non-overlap и strict UTF8 проверяются до передачи данных native reader.
Unique case-sensitive entityId index проверяется против XXH3(seed0) raw UTF8
big-endian64 key и native ID value. xxh3 Dart1.2.0 pinned direct dependency;
это часть существующего формата индекса, не новый receipt/hash framework.
GC tree проверяется по pinned descending32bit PNL: диапазон/порядок/уникальность,
отсутствие пересечения free pages с live catalogue/info/collection/index/GC pages.
GC N_BIG value строго больше4bytes (native FREE_DBI minimum); inline empty PNL
count0/value4 допустим. GC overflow может удерживать одну reserve page сверх
ceil((valueBytes+20)/pageSize) по pinned FREE_DBI overwrite rule; весь allocated
extent, включая reserve page, проверяется на range/uniqueness/counters и отсутствие
free-list пересечения. Прочие trees сохраняют exact minimal extent. Это свойства
того же pinned target layout, не migration или совместимость с другим форматом.
Это bounded decoder нужного формата, не поддержка других MDBX/Isar layouts.

Все прежние row-family caps и payload bounds сохраняются. Для raw desired reader
верхняя граница51250rows выводится из250live profiles+10000delete receipts ×5;
логический loader затем применяет точный knownServers bound. Metadata trees имеют
защитный bound1024entries; unknown oversized/corrupt input не открывается native.
Snapshot source immutable/detached, не удерживает DB/lease и не выдаёт authority.

`preflightWorkspace` перед writable Isar.open вызывает NativeWorkspaceRows,
`inspectWorkspaceSnapshot` (вся graph/credentials/trust/grants/history/custody/
MCP inventory validation БЕЗ publish), затем read-only executor sidecar validator.
Отсутствующий sidecar не создаётся; неподдержанный/неподлинный блокирует открытие.
Существующий creation stage проходит тот же native byte/initial-empty-graph gate
до open; только freshly proven absent workspace допускает первоначальное создание.
После open повторный read-only capture должен совпасть по всем native/business IDs
и exact payload strings с preflight. Лишь затем recoverWorkspaceLookups проверяет
все referenced grants до первого publish. Reader/owner/key/path errors возвращают
fixed safe category без reset/conversion или публикации lookup.

Реальные MDBX/Isar/DPAPI операции этим unit scope не квалифицируются. Остальные
Host/cutover/positive record-family/fault acceptance задачи остаются обязательными;
наличие read-only gate не является их завершением или разрешением обойти Host.
