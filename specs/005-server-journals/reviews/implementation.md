# Реализация005 —2026-11-04

## Реально выполненные проверки

- `dart format --output=none --set-exit-if-changed .`: exit0,377 files,0changes.
- `flutter analyze`: exit0, No issues found.
- `flutter test`: последний повтор exit0,723 tests passed; полный обычный functional/unit suite, лог локально `tmp/journals-flutter-test.log` (не integration и не реальный Isar). Предыдущие проходы:706,713,717,718,719.
- `tools/check-test-boundaries.ps1`: exit0,89 checked Dart files по текущему boundary tool.
- `python tools/check-ssh-vendor.py`: exit0,98 files,4 policy sources, patch/hash/reverse-apply audit. Policy patch пересобран из официального archive с проверенным SHA256; никаких непроверенных upstream bytes не включено.
- `lychee "specs/**/*.md"`: последний повтор exit0,230total,224OK,0errors,6excluded,2redirects; после правок документов повторяется.

Все проверки относятся к общей текущей рабочей копии, включая независимые изменения001–004; не являются доказательством полной интеграции на чистой ОС. Product/VM/real-server/real-Isar/design-screen проверки не запускались.

## Реализация / трассировка

`lib/journals` содержит bounded models/protocol/owner/view и диалог удаления на готовых001. Typed SSH admission и result fences в ConnectionOwner, captureStatus/stderr bounded exec не меняет004 defaults. JournalSource живёт в общем Isar, profile save/reset/delete атомарны с источниками. Runtime владеет сбором независимо от вкладки/трея, shutdown отменяет/дожидается работ. MCP tools не расширены.

FR-501/502/509/511→protocol/view и functional widget tests; FR-503→owner transaction и1024 concurrent admission/draft tests; FR-504→synthetic channel/owner fence tests; FR-505/512/513→runtime composition, repository hooks и lifecycle units; FR-506/510→TTL/clock/caps/fragment expiry tests; FR-507/508→file parser/owner и journal cursor recovery tests; FR-514→обычный unit suite и boundary audit.

Фактические unit locations: T021 recovery — journal_owner_test + journal_lifecycle_test; T022 cap — journal_retention_test + journal_view_test; T023 exact config — journal_owner_test + late revision journal_lifecycle_test. Это не отдельные integration tests.

## Convergence

Первый проход:4 partial/missing findings (1HIGH,3MEDIUM), добавлены T024–T027 без стирания истории. Исправлены inline error/context fences диалога, дополнены функциональные сценарии, cleanup runtime maps, TTL pending file prefix. Повторная source/artifact сверка:14FR,5SC,6constitution principles, все23 исходные и4convergence задачи имеют реализацию/проверки; runtime/shared transport/store решения сопоставлены. Новых actionable gaps не обнаружено. Задача независимого code review T020 остаётся открыта до завершённого отчёта.

## Независимое ревью реализации

logs_code_review_1 completed read-only report:4 findings, readiness не готов. P1 phase-locked004/005 shared slot; P2 stale discovery revision; P2 unit target>80 cannot add as name; P2 overdue queued source shows old status. Findings подтверждены; добавлены T028–T031, исправления требуют повторных обязательных checks и нового независимого review. Проверенные706unit tests не покрывали эти4сценария, поэтому не объявляются достаточной приёмкой.

T028–T031 выполнены: общий per-profile FIFO в ConnectionOwner, revision-bound discovery projection,80rune initial label с полным target, due/waiting projection отдельно от sticky partial. Дополнительная self-review находка T032 — stale controls после A→B — закрыта captured owner/profile guards и functional callback test. Новые deterministic tests проверяют4циклах contention, cancel waiter, late discovery после revision change, длинный unit, очередь16источников и старый Add callback. После fixes все обязательные format/analyze/test713/boundary/vendor/links повторены успешно. Текущий code scope заморожен до нового независимого review; T020 остаётся открыта.

logs_code_review_2 completed report:1P2 finding, package ready, implementation ещё не принята. Refresh до prune переприсваивал новый revision старым service rows. T033 добавлена без удаления выполненной истории; исправление очищает old rows/state перед stamp. Три unit сценария offline/loading/error и functional offline Refresh воспроизводят границу; первые отрицательные тесты выявили старые rows, после исправления targeted20tests и full717tests прошли. Все обязательные format/analyze/boundary/vendor/lychee снова exit0. Требуется fresh independent review финального source scope; до него goal не complete.

Дополнительный self-review: T034 убирает ложный loading после отмены чтения при rename; T035 объединяет контроль cursor на parse/render/storage границах, чтобы malformed control/bidi cursor не отравлял durable checkpoint. Обе регрессии имеют unit сценарии. После последних изменений full719tests, format/analyze/boundary/vendor/lychee прошли; исходники заморожены до нового независимого review. Пользователь подтвердил manual absolute file paths и automatic systemd discovery — это отражено в Clarifications без изменения реализованного поведения.

logs_code_review_3 completed report:1P2 finding, package ready, implementation пока не принята. Record detail держал snapshot payload после TTL/source delete/revision reset. T036 перевела detail на reactive identity lookup без fallback-текста; JournalView теперь явно получает connectionRevision и закрывает старый route при reset. T037 добавила nearest-expiry notification отдельно от polling и monotonic-advancing UTC anchor, чтобы список и открытая деталь обновлялись на границе часа, включая clock rollback. Functional tests открывают detail за1сек до expiry между ticks, удаляют источник и меняют revision; отдельный clock unit проверяет rollback. Full723tests и все обязательные format/analyze/boundary/vendor/lychee прошли. Требуется свежий completed independent review; T020 открыта.

## Финальный результат

logs_code_review_4, fresh fork_turns=none, read-only, завершён: «Замечаний не найдено. Готовность к реализации: готов. Приёмка реализации: допустима в установленном unit/fake/static scope». Reviewer напрямую проверил весь005, affected seams, generated schema/vendor provenance и tests; подтверждённых обязательных пробелов/дефектов/регрессий не осталось. Последние reactive detail/expiry fixes признаны соответствующими контракту. Самостоятельно reviewer checks не перезапускал; использовал приведённые фактические результаты723tests/static checks. Live SSH/Isar/clean-OS интеграция не доказана и не является gate.

T020 закрыта после completed clean report. Итого37/37 задач выполнены, новые задачи добавлялись без удаления выполненной истории. Финальная source/artifact convergence:14FR,5SC,6principles,37tasks; actionable gaps0, tasks.md при clean convergence не дополняется пустой фазой. Исходники после clean review не изменялись; финальная запись статуса/отчёта проверяется lychee.
