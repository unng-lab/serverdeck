# Verification: Windows Credential Manager

[Specification](../specs/002-windows-credentials/spec.md),
[adapter](../lib/data/credentials.dart),
[native tests](../integration_test/credentials_windows_test.dart).

Windows x64, Flutter 3.47.0 / Dart 3.13.0. Проверки выполнены 2026-10-10.

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | 4 files, zero changes |
| `flutter analyze` | No issues |
| `flutter test` | 3 passed |
| `flutter test integration_test/credentials_windows_test.dart -d windows` | 13 passed; Windows native build succeeded |
| `lychee "specs/**/*.md"` | 24 OK, zero errors |

Native checks: exact password/key/Unicode/passphrase roundtrip through a fresh
adapter, overwrite, missing/delete/idempotent delete, exact 2560-byte boundary,
oversized ASCII/Unicode refusal preserving prior value, malformed JSON/UTF-8/type
with fixed secret-free errors; password accepts absent/null passphrase and
rejects both empty/nonempty String passphrase. Controlled ERROR_ACCESS_DENIED
at the CredRead/CredWrite/CredDelete call boundary yields explicit errors,
exact secret-free diagnostics and one API attempt. Each refusal preserves a
real native credential, confirmed through a fresh default adapter with no concurrent mutations in the failure fixtures. These are
injected failures, not evidence of actual Windows permission denial. The adapter
has no alternate storage path; buffer ownership and cleanup remain in the store.
Unit checks cover safe debug representation and
reference validation. Каждая uniquely named synthetic запись удалена в finally.

AC-11: six native two-process cases passed. The standalone fixture executable
was compiled with Dart, then passed via CREDENTIAL_TEST_WORKER. Both processes
prepared operations before either was allowed to apply. Ordered write/write
in both directions produced the second writer's entire payload; write/delete
produced absence; delete followed by a previously prepared write recreated the
credential. Simultaneously released write/write and delete/write requests
produced allowed complete values/absence. Scheduling of native syscall overlap
is not forced; the contract does not promise FIFO, CAS or delete tombstones.
Each fixture joins its workers and removes its synthetic credential.