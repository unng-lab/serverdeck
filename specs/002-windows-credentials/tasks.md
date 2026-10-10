# Tasks: Windows credential custody

[Spec](spec.md), [plan](plan.md), [contract](contracts/credentials.md).

## Setup

- [x] T001 Зафиксировать ffi/win32 и Windows harness в `pubspec.yaml`, `windows/`.

## US1 — Save, read, replace

- [x] T002 [US1] Реализовать SshCredential и current-user native adapter в `lib/data/credentials.dart` (FR-001/002; AC-01..03/06): password passphrase отсутствует/null, String отклоняется; key String/null сохраняется точно.
- [x] T003 [US1] Проверить exact password/SSH-key/Unicode/passphrase roundtrip и overwrite в `integration_test/credentials_windows_test.dart` (SC-001).

## US2 — Delete and safe failures

- [x] T004 [US2] Реализовать delete, missing, size/reference/platform refusal, safe parsing и освобождение buffers в `lib/data/credentials.dart` (FR-003/004/005).
- [x] T005 [US2] Проверить redaction, invalid references, oversized и malformed payload в `test/credentials_test.dart`, `integration_test/credentials_windows_test.dart` (AC-04..07; SC-002), включая native password absent/null/String passphrase fixture.

- [x] T007 [US2] Добавить controlled CredRead/CredWrite/CredDelete refusals через test-only native boundary в lib/data/credentials.dart и integration_test/credentials_windows_test.dart. Проверить FR-004/005 → AC-08/09/10 → SC-002: read failure отличается от null; write/delete failure сохраняет real native credential; сообщение без material/passphrase, одна API попытка, no retry/plaintext fallback. Injection не считается доказательством реального OS permission denial.

## US3 — Concurrent callers

- [x] T008 [US3] Зафиксировать FR-006/AC-11/SC-003 в contract и adapter docs; добавить 	est/fixtures/credential_worker.dart и native cases в integration_test/credentials_windows_test.dart: два процесса, оба порядка write/write и write/delete, ранее подготовленный write после delete, overlapping calls; допустимое полное значение либо отсутствие. Failure retention tests T007 выполняются без конкурирующих изменений.

## Verification

- [x] T006 Format/analyze/test, Windows native suite и link check; результаты `docs/verification.md`.

## Dependencies

T001 → T002 → T003; T004 → T005; T004 → T007; T002 → T008; T003/T005/T007/T008 → T006.
Unit и native tests можно запускать независимо после реализации adapter.
