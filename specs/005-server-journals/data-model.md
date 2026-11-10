# Data Model —005

## JournalSource

Isar fields: id; unique sourceId(UUID); indexed profileId; positive connectionRevision; kind journal/file; immutable target; name(trimmed1–80); enabled(default true after explicit add); payload(JSON).

Payload: `{version:1,checkpoint:...,entries:[...],partial:bool}`. Invalid version/shape is storage error, never fallback/convert. Journal checkpoint: opaque cursor≤4096bytes. File checkpoint: decimal device:inode≤128bytes, offset≥0, fragment(base64≤16KiB bytes), discardingLongLine(bool), sequence≥0. No saved file handles.

Current file checkpoint also includes fragmentAt(msUTC) whenever fragment is nonempty; prefix expires at the same60min boundary, including disabled sources. Pruning removes its bytes, sets discard=true and partial=true until LF completes the truncated line. Runtime per-source maps and service-discovery maps are pruned when their source/profile is removed; disposal clears remaining state. Это текущая схемаv1, не compatibility branch/backfill.

Entry: id(cursor or sourceId/sequence), receivedAt(msUTC), optional sourceAt(msUTC), optional priority0–7, text≤16KiB UTF-8, truncated(bool). Journal dedupe by cursor, not time/text. File id uses monotonically advancing sequence, atomically checkpointed. Display newest first, stable id tie-break.

Настроенные источники ограничены независимо:16/profile и1024global (включая disabled), проверка внутри add transaction. Профили003 могут достигать1000;64 — только live SSH sessions. Отказ нового источника не удаляет существующие данные. Cursor failure включает transient resetCursor; durable cursor заменяется только успешным fallback batch (пустой success→null) с partial=true; ошибки fallback оставляют resetCursor и старые данные. Журналы всегда обозначены best-effort независимо от успешного seek.

## Validation / lifecycle

Names/path reject NUL/control chars. File path absolute, not root/trailing slash, no `.`/`..` segments,≤1024UTF-8bytes. Spaces/quotes/metacharacters allowed as safely quoted data. Unit ASCII `[A-Za-z0-9_@.:\\-]+\.service`,≤256bytes, no leading hyphen/slash. Exact kind+target unique per profile, not symlink canonicalization.

Runtime source states: loading, ready/empty, partial, paused, disconnected, waiting, unavailable, permissionDenied, storageError, invalidResponse, timeout, outputLimit. Enabled→reading→state; disable/delete/revision change cancels job and increments runtime generation. Restart/re-enable/reconnect resets file EOF (possible gap); journal reloads tail200 without time filter on a new session, then resumes cursor with limit200 and possible gap. Historical partial is sticky until deletion.

Retention uses local high-water now; no backwards-clock resurrection within process, persisted greatest receipt bounds restart clock. Projection sorts receivedAt descending/id descending and retains the union of receivedAt>now−3600000 and the first200 entries per source (receivedAt≤now). Resource caps override the tail. Startup and5s tick purge expiry (≤60s). Each transaction enforces10k/8MiB per profile and50k/32MiB global text; oldest first, affected source partial=true. Metadata is additionally bounded by50k events/cursor4KiB/source1024 and fragment16KiB; no unbounded decode inputs.

Every mutation re-reads profile/source/revision+generation before commit. Batch/checkpoint/pruning atomic; failed write retains old checkpoint. Delete profile repository transaction cascades all sources. Connection-affecting profile save preserves sourceId/kind/target/name/enabled, updates each source.connectionRevision to the new profile revision, resets payload to version1 empty entries/checkpoint with partial=true in the same profile transaction; old callbacks fail revision check. It does not delete configurations. Next permitted session resumes enabled sources with initial journal-tail200/file-EOF semantics, no auto-connect. Rename keeps config and history. Delete source removes history. Trust revoke stops reads but keeps offline hour-plus-tail history.

## Reactive retention and runtime clock

While running, effective UTC is at least the last UTC anchor plus elapsed monotonic time. UTC rollback cannot freeze expiry outside the tail, and frequent reads do not discard sub-millisecond elapsed progress. Restart still seeds from greatest stored receipt; no historical compatibility/backfill path is introduced.

A separate nearest-expiry deadline notifies projections at receipt+3600000 for entries outside the newest200 and file fragments, independently of the5s collection phase, and starts physical pruning. New batches/config changes/purge re-arm it, shutdown cancels it. Normal polling remains the recovery/backstop for storage errors or wall-clock jumps. Entry/detail projections always filter current effective time; failed disk cleanup does not return expired entries outside the tail.
