# Research: установка и обновление

## R7 — GitHub Releases (уточнение пользователя, 2026-11-04)

**Decision**: единственный источник — GitHub Releases публичного origin
`unng-lab/serverdeck`; latest API выбирает stable release, setup и signed catalog
размещаются в assets, описание/changelog — body/вложения того же релиза.
**Rationale**: пользователь исключил отдельный сервер. Static protocol2 без expiry
не требует weekly republishing; fresh latest/target API и signed catalog перед
apply проверяют доступность/отзыв. Подпись продолжает защищать publisher identity.
**Contract**: [GitHub production source](contracts/github-releases.md).
**Sources**: [GitHub Releases REST](https://docs.github.com/en/rest/releases/releases),
[GitHub assets REST](https://docs.github.com/en/rest/releases/assets).
**Limit**: наличие реализации legacy direct source не доказывает выполнение
GitHub adapter; это отдельные незавершённые T055–T057.

## R1 — Полный native установщик

**Decision**: `/MT` setup с полным application RCDATA, стандартными Windows dialogs.
**Rationale**: переиспользует single-EXE runtime, не скачивает framework/dependencies.
**Alternatives**: portable отклонён пользователем; online bootstrap нарушает offline;
Inno допустим, но добавляет toolchain и другой maintenance lifecycle к готовым adapters.

## R2 — Authority

**Decision**: cross-session no-share `owner.lock` сохранить, добавить maintenance lock;
порядок всегда maintenance → owner. Файл без удерживаемого HANDLE не authority.
**Rationale**: существующий Local mutex не охватывает разные logon sessions.
**Alternatives**: PID marker/Global mutex не заменяют атомарный file lease.

## R3 — Замена image

**Decision**: transient setup с непрерывной передачей leases заменяет EXE после выхода
bootstrap до host. Prepare/flush verified backup, journal, same-volume ReplaceFile.
Ошибки классифицируются по фактическим хешам кандидатов, не только API return code.
**Rationale**: Windows ограничивает удаление mapped executable; rename-old-then-new
оставляет окно отсутствующего canonical EXE. Backup только для file recovery до host,
не откат данных после открытия новой версией.
**Alternatives**: force-kill/постоянная service недопустимы.
**Sources**: [ReplaceFileW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew),
[Executable images](https://learn.microsoft.com/en-us/windows-hardware/drivers/ifs/executable-images).

## R4 — Trust

**Decision**: bounded signed catalog ECDSA P256/SHA256; built-in keys; fresh signed
network catalog before apply, absent/changed target revokes consented artifact.
**Rationale**: TLS+хеш из того же ответа не удостоверяет publisher и совместимость.
Root rotation через overlapping built-in keys; compromised root требует independently
trusted installer. Конкретные production inputs — среда сборки, не runtime secrets.
**Alternatives**: unsigned feed/произвольный UI URL исключены.
**Sources**: [BCryptVerifySignature](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptverifysignature),
[WinHTTP timeouts](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpsettimeouts).

## R5 — Удаление

**Decision**: retained setup копирует себя в marked OS temp directory, helper удаляет
только canonical install files. Его mapped temp image может остаться до обычной
очистки temp ОС, что явно разрешено FR-614; службы/tasks/shell deletion не требуются.
**Rationale**: нельзя обещать self-delete mapped image, silent orphan app или admin reboot.

## R6 — Проверки

**Decision**: synthetic unit ports и temporary-file native tests, build/resource/import
audit; не запускать продукт или live Isar из тестов. Это не доказательство интеграции
на чистой ОС и не отложенный VM/e2e/smoke gate.
