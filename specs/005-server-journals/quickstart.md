# Проверка005

Только unit/fake inputs, без запуска продукта/реальных серверов/Isar/VM/integration или feature design checks.

1. `flutter test test/journals`: discovery, source CRUD, safe unit/path quoting, journal JSON variants/repeats, file fragments/rotation/truncation, expiry/caps/restart/storage errors, late result/revision fences.
2. `flutter test test/connections`: synthetic channels, stderr/nonzero opt-in, shared slot, cancellation/late-open/close; reject MCP/obsolete sessions.
3. Functional widgets: A/B context, add/rename/toggle/delete/retry, empty/offline/error history, inert text, pagination. No geometry assertions.
4. `dart format --output=none --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `tools/check-test-boundaries.ps1`.
5. `lychee "specs/**/*.md"`; независимое ревью пакета до реализации и fresh ревью кода после checks, цикл fixes/checks/review.

Ожидания: [SC-501–505](spec.md#measurable-outcomes), [контракт](contracts/journals.md). Unit результаты не доказывают работу всей связки на чистой ОС. Реальные результаты записываются после запуска проверок.

## Service navigation unit cases

Проверить ensureService reuse/create/concurrent/quota/stale revision на fake store,
initialService selection/search/error/manual/context lifecycle на JournalView
с JournalHarness. Существующий paused source остаётся paused, никаких auto-connect
или discovery. Acceptance — FR-516/AC-516 и008 AC-818.
