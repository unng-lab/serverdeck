# Validation guide: Консоль сервера

## Prerequisites

Текущий Flutter/Dart из PATH, зависимости через flutter pub get; vendored dartssh2/xterm входят в workspace и runtime. Для тестов не нужны сервер, SSH credentials, открытый терминал, внешний процесс или реальная Isar. Production сервер должен поддерживать PTY и выбранную оболочку; unit не доказывают установку/интеграцию на чистой ОС.

## Required commands

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
& ./tools/check-test-boundaries.ps1 -TestRoot (Join-Path $PWD 'test')
flutter test test_design/components
lychee "specs/**/*.md"
```

Shared design command применим из-за изменения C26 в scope001; не запускает feature-layout acceptance. Captures explicit opt-in, здесь не нужны. Не использовать integration/e2e, smoke, VM, process-kill или historical tools как gates.

## Functional coverage

- US1 AC701–704: fake current connection, явное открытие, basic VT/UTF8 fragment input/output, failures/trust/generation; нет network от чтения.
- US2 AC705–709: null settings default, atomic save/validation/conflict/failure, profile snapshot survives CRUD; synthetic generated-schema audit доказывает nullable read, без открытия Isar.
- US4 AC715–722: MCP21tools, shared screen/history, lease takeover/busy/expiry/EOF, oldgrant denial/cache denial, retries without second packet, current/final history and stale cursor/caps.
- US3 AC710–714: switch/detach/tray, close one channel, normal disconnect keeps finaltext, trust clears, shutdown and cancelledlateopen, no restore afterrestart.
- Vendor units: pending PTY open/request timeouts, retiredslotcap, remote window delay+lease revoke, rekey/queue races, pre-encryption cancellation and no cipher advance, immutable sink; no live process.
- Shared C26 synthetic inputs only in test_design/components; functional feature tests assert text/actions/semantics with fakes, no coordinates/sizes/colors/goldens/overflow matrices.

## Evidence

Сохранять реальные outputs/check exit codes в reviews/evidence.md после прогонов; не объявлять непрогнанные проверки прошедшими. После успешных applicable checks выполнить independent read-only reviewer через collaboration.spawn_agent(fork_turns="none") по AGENTS.md; исправлять подтверждённое и повторять checks+fresh review. После implement выполнить converge, не переписывая завершённые task history. Публикация релиза не часть acceptance этой функции.
