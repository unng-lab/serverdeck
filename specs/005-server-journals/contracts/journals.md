# Journals Contract —005 v1

## Private capability / authorization

JournalConnectionPort: changes, connection(profileId), beginJournal(UiActor,profileId,sessionId,expectedConnectionRevision,JournalRequest,cancellation)→typed result/cancel job. Only existing OwnerActor session. Same prepare admission/result checks as beginMonitoring: actor, trust, credential, endpoint, session/revision. MCP sessions rejected; no new public AppOperations/tools. Closed requests: Discover, ReadJournal(unit,cursor?,metadataRecovery), ReadFile(path,identity?,offset?). No widget-supplied command strings.

ConnectionOwner tracks≤4 jobs globally,≤1/profile, shared transport slot with004. Deadline includes gate wait,≤5s. Cancel disable/delete/revision/disconnect/shutdown, preserve healthy parent session. Retain channel slot until peer CLOSE. Drain waits tracked work; only safe errors leave parser.

Collector fairness: ConnectionOwner admits monitoring004 and journals005 through one FIFO per profile before their normal gate admission. Each capability retains its existing per-profile/global pending-job caps; queue length≤2 per profile (one request per capability), no parallel protocol channel. The original5s deadline includes queue+gate+read; an expired/cancelled waiter never dispatches when its predecessor completes. FIFO releases after the typed operation settles; protocol tombstone still prevents reuse until peer CLOSE. No cancellation of a healthy parent or active competing read. Deterministic tests model monitoring at0/5/10s taking1s and journal at0.1/5.1/10.1s: both capabilities progress, with journal admitted after release rather than phase-locked rejection.

## Protocol

Commands: [research](../research.md). Render each data argument with POSIX single quote escaping, reject controls/length before rendering. Offset parsed integer≥0. `LC_ALL=C`, no pager/colors. Journal cursor opaque≤4096bytes. Opt-in bounded result exposes exit and stderr internally; old monitoring default remains zero-status only. Nonzero127→unavailable, permission/access-denied stderr→permissionDenied, other failure→unavailable. Exit0 nonempty stderr means partial, never guaranteed complete empty. Unknown transport response→invalidResponse.

Discover parses first whitespace-delimited valid service ID from each row, max500; rejects invalid units. Transport cap returns explicit limit rather than fabricated services. User may retry. Missing systemd does not block files.

Journal: UTF-8 strict JSONL, cursor required, timestamp integer microseconds→milliseconds; priority optional0–7, MESSAGE string or explicit `[сообщение недоступно]`. Reject whole batch on invalid mandatory shape; no checkpoint advance. Output order preserved for cursor, receipt time for display.200 returned events marks possible gap. Output limit sets metadata-recovery mode for next tick: newest1 cursor with no message, persist cursor+partial, resume. Repeated metadata cap remains error with bounded retries.

Cursor recovery: nonzero cursor request (кроме permissionDenied и binary127/unavailable prerequisite) включает `resetCursor` на следующий tick≥5s, без повторения старого cursor. Следующий обычный запрос без cursor запрашивает доступный tail200 без временного фильтра. Успех атомарно заменяет checkpoint последним новым cursor, dedupe+entries+sticky partial; пустой успешный journal сохраняет cursor=null и partial=true и ждёт новых событий. При неуспехе fallback старый durable checkpoint не переписывается, runtime resetCursor остаётся true: последующие bounded попытки без cursor. После restart ошибка старого checkpoint снова включает тот же переход. Частичная/невалидная передача ничего не коммитит. Успешный seek может выбрать ближайшую запись, поэтому у journal всегда есть видимое «Ограниченная история; возможны пропуски», включая exit0; reset/reconnect/output cap дополнительно дают sticky partial. Это не обещание обнаружить каждое vacuum-событие.

File fixed script: `LC_ALL=C; export LC_ALL; p=<quoted>; [ -f "$p" ] || exit 44; [ -r "$p" ] || exit 43; exec 3<"$p" || exit 43; [ -f /proc/self/fd/3 ] || exit 44; stat -Lc '%d:%i %s' /proc/self/fd/3` emits decimal identity/size header+LF. If requested identity absent/different or size<offset, header only: checkpoint EOF, discard fragment, partial. Otherwise `dd bs=1 skip=<offset> count=16384 <&3 2>/dev/null`; propagate stat/dd failures,43 permission,44 unavailable. No tempfiles/remote writes. Client validates header then advances offset by actual body bytes≤16KiB, not requested count. GNU/procfs unavailable is source error, no install.

File decoding byte-oriented per LF; CRLF strips one CR, incomplete UTF-8 remains in fragment. Bad completed UTF-8 replaced+partial. Cap16KiB prefix of long line, discard until LF, emit one truncated event per line. Fragment discard on reset/reconnect marks loss. Strip/replace controls except tab; remove bidi and ESC controls to keep payload inert. Same-size overwrite/fast rotation best effort; file coverage warning always visible.

Незавершённый сохранённый prefix получает fragmentAt при первом байте, а не при каждом продолжении. Startup/tick purge удаляет prefix возрастом≥60мин, оставляет discard-until-LF и sticky partial; завершённая строка после этого помечена усечённой. Контент старой незавершённой строки не хранится бесконечно в checkpoint.

## Storage / concurrency

DomainRead/DomainTransaction gain list/get/put/delete JournalSource. Same synchronous Isar transaction. Owner revalidates profile/source/revision+runtime generation after await and inside transaction; final connection result fence alone insufficient. Failed commit keeps checkpoint, surfaces storageError, retry next tick/user action. Scope source≤16/profile, independent global cap1024 including disabled. Add rechecks both counts and exact duplicate in the single writer transaction: concurrent1024th/1025th admissions yield one success and one «Достигнут предел источников журналов», without evicting sources; form draft remains. Existing003 limit1000profiles remains. Expiry/caps/clock as [data model](../data-model.md).

## UI

Discovery rows/state carry connectionRevision and are hidden immediately when the saved profile revision differs, even before the next collection tick; prune also clears them and their retry deadline. Late old-revision discovery cannot repopulate them. A valid unit target up to256bytes is preserved in full; Add service uses its first80runes as initial display name, editable by Rename. Source status is waiting when enabled/connected, due for polling and not currently admitted; sticky historical partial remains separate from current queue status.

Selected profile's Journals receives injected owner. Refresh services explicit; discovered rows offer Add, no automatic subscriptions. File Add C14 form name/path; source select, rename, enable/disable, delete with local confirmation. Remote deletion never offered. Saved records visible offline. State and persistent partial warning separate from rows. Row shows source, receipt time, original timestamp if available, importance if known and inert text. Newest200 initially, «Показать ещё» adds200 up to available cap. Empty/loading/error/paused/disconnected/waiting states distinct; retry never immediate unbounded loop. Async callbacks tied to profile/source to prevent A→B leakage.

C02 buttons, C03 fields, C04 selection, C06 collection, C07 source list, C08 pagination, C10 status, C11 notices, C12 region states, C13 forms, C14 dialogs, C20 DeckLogMessage for full selected entry, C28 time from001. No new shared components. Feature tests only functional data/actions/semantics. List preview opens selected entry details with C20; its eventTime/observedAt preserve distinct server/receipt UTC times.

## Release / privacy

Connection-affecting save lifecycle: in the existing profile write transaction preserve sourceId/kind/target/name/enabled, update source.connectionRevision, replace payload with `{version:1,checkpoint:{},entries:[],partial:true}`. A late old-revision batch cannot commit. No deletion of source configs for password/endpoint changes; only deleting source/profile removes configs. After permitted new session enabled source uses initial read rules. Rename does not reset payload. Repository cleanup tests must cover exact preserved config, payload reset and rejected old revision commit.

Same single EXE and current workspaceSchemas/manifest; new schema no old fallback/migration or DB deletion. Payload version1 mandatory. Remote logs remain local Isar data protected by same002 directory rules. No automatic secret redaction; no remote contents/path/stderr in diagnostics, MCP, telemetry or exports.

## Reactive record detail

JournalView carries profileId, connectionRevision and owner identity; a context revision/rebind retires owned routes and old callbacks. A full-record dialog stores only sourceId/eventId/receivedAt/revision identity, listens to owner, and resolves the entry from the current allowed projection on every update. Missing/expired/deleted/revision-reset records show an unavailable notice or close; captured historical text is not used as fallback. The nearest-expiry notification updates both rows and an already-open detail between polling ticks. Monotonic progress advances effective UTC during local clock rollback as specified in the data model.

## Service/source name filter (FR-515)

JournalView owns C05 DeckSearch controller and transient `trim().toLowerCase()` query. Field appears before discovered/configured lists even without a selected source. Filter discovered units by full unit name; configured sources by name or target (including file sources), literal `.contains(query)` on lowercased strings. Empty query means all. Filtered-empty lists show «Сервисы не найдены» / «Источники не найдены», distinct from absent underlying data; clear restores rows. Preserve query on discovery refresh and source selection. Profile/connectionRevision/owner change clears query. Resolve selection from the full unfiltered configured-source list, so filtering never deselects the current source. Records always come directly from owner.entries(selectedSourceId), with existing record pagination/detail/TTL untouched; editing query does not reset their page size. No message-text filtering or remote/persisted query. No schema/API/dependency/shared component changes. This supersedes the earlier message-search interpretation, not the completed history in tasks/reviews.

## Tail refinement 2026-11-10

FR-506/507: новая SSH-сессия всегда читает tail200 без cursor/--since, даже при сохранённом checkpoint; последующие запросы после cursor ограничены200. Metadata recovery читает1. UI первоначально показывает200 и не утверждает отсутствие событий за час. Локальный projection и physical prune сохраняют последний час плюс последние200 на источник независимо от возраста; caps выше имеют приоритет. Правила относятся и к file-строкам, но файл по-прежнему начинает с EOF без backfill. Expiry deadline относится только к записям вне хвоста и fragmentAt; удаление/revision reset по-прежнему убирают detail немедленно.

## Переход из списка ПО

Следовать [service-logs008](../../008-host-software/contracts/service-logs.md).
Это внутренний UI/owner контракт, без изменения transport/read protocol/store.
