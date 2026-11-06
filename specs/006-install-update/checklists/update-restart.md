# Requirements quality: direct updates and restart

Scope: [spec](../spec.md), [contract](../contracts/platform.md).

- [X] CHK001 Прямой вход и подписи всех стадий определены, версия FR-620 сохранена.
- [X] CHK002 Точное согласие на скачивание отделено от подтверждения закрытия SSH/MCP.
- [X] CHK003 Atomic native acceptance, busy/stale/version/error и повторы определены.
- [X] CHK004 Shutdown/retry/session end/tray exit не обходят сохранение данных.
- [X] CHK005 Непрерывный owner и existing helper обеспечивают ожидание старого процесса.
- [X] CHK006 Failure/retry/cancel после unload не запускают второй Flutter host.
- [X] CHK007 Fresh trust/apply/offline fallback и отсутствие миграций сохранены.
- [X] CHK008 У каждой FR есть решение, задача и functional/synthetic критерий без layout/e2e.

2026-11-06: independent reviewer review_update_restart_design_fresh assessed all8 PASS.
