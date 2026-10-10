# ServerDeck: Windows credentials

Хранение паролей, приватных SSH-ключей и passphrase через Windows Credential
Manager текущего пользователя.

- [Спецификация](specs/002-windows-credentials/spec.md)
- [План](specs/002-windows-credentials/plan.md)
- [Контракт](specs/002-windows-credentials/contracts/credentials.md)
- [Проверки](specs/002-windows-credentials/quickstart.md)
- [Результаты](docs/verification.md)

`lib/data/credentials.dart` предоставляет `OsCredentialStore.read/write/delete`.
В приложении используется неприватная reference; payload хранится в системном
credential blob. Лимит адаптера — 2560 UTF-8 bytes включая JSON. Превышение лимита
отклоняется до изменения сохранённого доступа.

```powershell
flutter pub get
flutter analyze
flutter test
New-Item -ItemType Directory .local -Force | Out-Null
dart compile exe test/fixtures/credential_worker.dart -o .local/credential_worker.exe
$worker = (Resolve-Path .local/credential_worker.exe).Path
flutter test integration_test/credentials_windows_test.dart -d windows "--dart-define=CREDENTIAL_TEST_WORKER=$worker"
```

Windows runner используется для запуска native integration tests.

Одна reference общая для текущей Windows account. Параллельные write/delete
не имеют FIFO/CAS гарантии; write после delete может создать запись снова.
Порядок и границы гарантий описаны в контракте.
