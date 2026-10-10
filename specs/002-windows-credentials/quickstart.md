# Validation: Windows credentials

[Spec](spec.md), [tasks](tasks.md).

Windows x64 с установленными Flutter 3.47 / Dart 3.13 и Windows build tools.

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
New-Item -ItemType Directory .local -Force | Out-Null
dart compile exe test/fixtures/credential_worker.dart -o .local/credential_worker.exe
$worker = (Resolve-Path .local/credential_worker.exe).Path
flutter test integration_test/credentials_windows_test.dart -d windows "--dart-define=CREDENTIAL_TEST_WORKER=$worker"
lychee "specs/**/*.md"
```

Native fixture проверяет password absent/null passphrase и отказ String passphrase, SSH-key/UTF-8/passphrase, overwrite, missing,
delete, oversized payload и malformed JSON/UTF-8. Уникальные синтетические записи
удаляются в finally. Unit tests проверяют безопасное представление и references.
Результаты: [verification](../../docs/verification.md).

Controlled API отказ read/write/delete (AC-08..10) выполняется через call boundary,
с проверкой real native сохранённого credential и безопасной диагностики.

AC-11 запускает два Dart worker процесса (dart должен быть в PATH) по общей
reference: оба подготовлены перед применением; проверяются оба порядка и
overlapping write/write, write/delete. Синтетическая reference удаляется в finally.
