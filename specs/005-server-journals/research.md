# Research —005

## SSH

Decision: existing bounded exec with opt-in stderr/nonzero result. Same single slot,5s and64KiB combined cap, late-open cancellation/close. Typed closed requests only. Rationale: generic SFTP lacks bounded lifecycle; separate daemon outside constitution. Existing seams: ConnectionOwner.beginMonitoring, StrictSshTransport.collectMonitoring, DomainRepository.

## Journal

Decision: finite `journalctl --no-pager --output=json --output-fields=__CURSOR,__REALTIME_TIMESTAMP,MESSAGE,PRIORITY,_SYSTEMD_UNIT --unit=<unit> --lines=200`, optional `--after-cursor=<cursor>`. No `--all`: large/nonstring/null MESSAGE is explicitly unavailable. Tail200 may skip older entries, marked partial when200 returned. Reconnect/vacuum always possible gap. On output cap, next tick metadata-only newest cursor (`--lines=1`, no MESSAGE), persist skip+partial then resume. Opaque cursors, no gapless promise.

Discovery: `LC_ALL=C SYSTEMD_COLORS=0 systemctl --no-pager --no-legend --plain --full list-units --all --type=service`. Currently loaded system services only, not all installed files/uninstantiated templates.

Primary docs consulted by read-only research agent: [journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html), [cursor semantics](https://www.freedesktop.org/software/systemd/man/latest/sd_journal_seek_cursor.html), [systemctl](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html). JSON types vary; `--output-fields` requires236.

Review closure: failed cursor read transitions to no-cursor tail200 fallback on next5s tick; successful fallback atomically persists cursor/entries/partial, empty fallback clears cursor, failed fallback keeps retrying without old cursor. Successful seek still does not prove continuity; all journal sources explicitly show bounded best-effort coverage. Independent total source cap1024 is an admission policy, not derived from live sessions64 or profiles1000.

## Files

Decision: fixed POSIX script, quoted path, read-only FD, GNU stat device/inode/size via `/proc/self/fd/3`, bounded dd offset/chunk16KiB. First read snapshots EOF, no historical bytes. Identity change/shrink/reconnect resets to EOF with warning. Reopen each poll; copy-truncate-regrow/same-inode overwrite may be undetectable, always mark file continuity best effort. Allow symlinks; identity follows actual opened target. No sandbox beyond account rights; regular-file checks before and after open. Racing FIFO may block until deadline, cancellation bounds client wait.

Sources: [GNU coreutils upstream manual — stat/dd](https://github.com/coreutils/coreutils/blob/master/doc/coreutils.texi). Alternatives: SFTP v3 lacks stable inode ([primary draft](https://datatracker.ietf.org/doc/html/draft-ietf-secsh-filexfer-02)); no second unbounded subsystem.

## Storage

Decision: Isar JournalSource config+payload; atomic checkpoint/history/caps. Same local account directory protection002, no auto-redaction/export. Alternatives: memory-only fails user's restart requirement, separate DB adds owner. Never write payload/paths to diagnostics.
