# Implementation Plan: Windows Credential Manager

**Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

## Summary

Адаптер OsCredentialStore сохраняет пароль/SSH-ключ/passphrase как generic
credential Windows текущего пользователя. Приложение обращается к доступу по
ссылке; native буферы освобождаются после операции.

## Technical Context

Dart 3.13 / Flutter 3.47; ffi 2.2.0, win32 6.4.0, meta 1.18.3 (test annotation без Flutter runtime в worker). Windows x64.
CredWrite/CredRead/CredDelete/CredFree; UTF-8 JSON со схемой по kind, лимит адаптера 2560 bytes. Test-only native boundary позволяет контролируемо воспроизводить отказы без изменения обработки buffers и ошибок; real native adapter проверяет сохранность исходного доступа.
Проверки: flutter_test и native integration_test с синтетическими credentials.
Windows runner служит harness для native integration.

## Constitution Check

Секреты хранятся средствами OS; диагностика не содержит material/passphrase.
Все проверки используют собственные уникальные fixture references и удаляют их.
Системные отказы не разрешают plaintext fallback. Реальные доступы не используются.

## Project Structure

- `lib/data/credentials.dart`: типы и native adapter.
- `test/credentials_test.dart`: безопасное представление и reference validation.
- `integration_test/credentials_windows_test.dart`: Windows native contract tests.
- `pubspec.yaml`, `windows/`: зависимости и test harness.
- [data-model](data-model.md), [contract](contracts/credentials.md), [validation](quickstart.md), [tasks](tasks.md).

## Validation

Format, flutter analyze/test, native Windows suite, links. Успешное завершение
проверок фиксируется в [verification](../../docs/verification.md).

## Concurrency

Shared account reference допускает конкуренцию по FR-006/AC-11. Runtime lock,
CAS и tombstone не добавляются. Single-owner ordering при необходимости
обеспечивает caller. Два Dart native worker процесса и stdin/stdout barriers
проверяют допустимые результаты в обоих порядках и при overlapping запросах.
