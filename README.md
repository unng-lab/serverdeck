# ServerDeck

Самостоятельный Flutter desktop клиент для Linux-серверов. Windows — первая платформа.
Локальная работа через SSH; облачный backend не требуется.

Первый проверяемый этап M0 реализован: пять экранов на синтетических данных —
серверы, ПО/версии и systemd-состояния, журнал, ресурсы, план установки.
Профили сохраняются локально через Dart locald и Isar. Журнал поддерживает поиск,
службу/приоритет/период, поля, явное копирование, паузу и demo-поток с буфером 500.
Неизвестные и устаревшие значения показаны отдельно.

Начата основа M1: pinned read-only SSH, Windows Credential Manager, безопасные
команды и парсеры пакетов/units/CPU/RAM. Транспорт проверен на одноразовом localhost
SSH-контейнере; подключение к реальным серверам в интерфейс ещё не включено.
Начата основа M2: Isar журнал заданий/событий в Dart locald, idempotency, host lock и состояния
cancel/unknown/reconciling; Linux Ansible Core + Runner прошли localhost smoke.
Запуск установок закрыт. Рецепты PostgreSQL/ClickHouse и ограниченный privilege
helper ещё не реализованы и не проверены на systemd VM.

## Запуск

Из checkout проекта:
```powershell
& tools/build-windows.ps1
& build/windows/x64/runner/Release/serverdeck.exe
```
Release: build/windows/x64/runner/Release/serverdeck.exe. При переносе нужна вся
папка Release, включая DLL и data; один exe не является portable-дистрибутивом.
Сборка включает serverdeck_locald.exe и libisar.dll. Flutter работает через Local
API, базой владеет только локальный Dart-сервис. Python нужен лишь внутри будущего
Ansible-контейнера; управление заданиями приложения реализовано на Dart.
Демо-профили: %LOCALAPPDATA%/ServerDeck/demo. Сервис продолжает работать при закрытии
окна; после сбоя сервиса перезапустите приложение для повторного подключения.
Для flutter run сначала соберите sidecar и задайте SERVERDECK_LOCALD_EXECUTABLE
полным путём к serverdeck_locald.exe из Release.

Проверено с Flutter 3.47.0/Dart 3.13.0 и Visual Studio 2022. SDK сообщает user-branch;
точная ревизия и выполненные проверки в [verification](docs/verification.md).
Зависимости зафиксированы в pubspec.lock; пакет приложения не публикуется в pub.dev.

## Проверки

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test/windows_smoke_test.dart -d windows
& tools/test-ssh-fixture.ps1
flutter test integration_test/local_storage_test.dart -d windows
Push-Location packages/serverdeck_locald
dart test
dart analyze
Pop-Location
lychee "specs/**/*.md"
& tools/build-windows.ps1
& tools/test-locald-process.ps1
```
SSH fixture script создаёт собственный контейнер с портом только на 127.0.0.1 и
удаляет его в finally. Он не обращается к существующим серверам. Образ fixture
устанавливает OpenSSH только внутрь одноразового контейнера; этот образ не доказывает
Ubuntu/systemd или реальную установку приложений. Runner smoke — [runner/README](runner/README.md).

## Spec Kit и требования

Официальный specify-cli 1.1.0 установлен через uvx; интеграция Codex находится в
.agents/skills, общие шаблоны/скрипты в .specify. При новом checkout локальный указатель:
```powershell
$env:SPECIFY_FEATURE_DIRECTORY='specs/001-server-management-client'
& .specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireSpec -RequireTasks -IncludeTasks
```
[Spec](specs/001-server-management-client/spec.md),
[plan](specs/001-server-management-client/plan.md),
[tasks](specs/001-server-management-client/tasks.md),
[analysis](specs/001-server-management-client/analysis.md),
[traceability](specs/001-server-management-client/traceability.md),
[research](specs/001-server-management-client/research.md).

## Границы безопасности

Реальные установки/удаления и действия со службами не разрешены этой документацией.
NetBird и его клиенты защищены от любых изменений. Секреты не входят в профили,
Git, синхронизацию или публичные события. Native Windows Credential Manager хранит
секреты локально для текущего пользователя (лимит 2560 байт; большие PEM явно отклоняются).
Неизвестный SSH host key требует отдельного enrollment; изменённый ключ отклоняется.
Sync не должен выдавать разрешение на выполнение.

Исследование поведения Logs привязано к commit
a7bf7f8f0c4d5d37be6a54119eaf70a1248520b9: [источник](docs/logs-research.md).
Код Logs не скопирован; лицензия не установлена. Собственная лицензия проекта ещё
не выбрана. Наличие публичного репозитория не разрешает копировать сторонний код.
