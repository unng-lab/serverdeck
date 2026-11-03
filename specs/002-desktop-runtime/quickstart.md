# Quickstart validation — runtime 002

## Действующая политика

Только юнит-тесты по прямому указанию пользователя от 2026-11-03 и
[конституции III](../../.specify/memory/constitution.md). Интеграционные, VM,
release smoke и process-kill прогоны исключены из завершения и CI.
Свойства продукта сохраняются; unit results не выдаются за реальную интеграцию.
Исторические утилиты и старые результаты описаны в [архиве](vm-verification.md).

## Среда разработки

Windows10/11x64, Flutter3.47.7/Dart3.13.5, VS2022 v143 Desktop C++,
WindowsSDK≥10.0.19041, CMake≥3.28, Python≥3.12, lychee.
Эти инструменты нужны разработчику для сборки, не пользователю готового EXE.

## Обязательные команды

```powershell
flutter pub get --enforce-lockfile
./tools/test-unit.ps1
./tools/build-release.ps1
./tools/test-release.ps1
lychee "specs/**/*.md"
```

`test-unit.ps1` выполняет boundary check,
`dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`.
`test-release.ps1` — compatibility name для6 native unit tests с CTest label unit;
не запускает продукт, EXE probes, observer, lifecycle или VM helpers.
Сборка создаёт один output/release/ServerDeck.exe и статический manifest/import audit.
После изменения schemas используется tools/generate-models.ps1; в этой поправке
schema/format не меняются. Общие компоненты001 не меняются, design suite не запускается.

## Покрытие поведения

| Требования | Юнит-проверка / статический контроль |
| --- | --- |
| FR201–202, AC201 | manifest/bounds/path fixtures; build import closure |
| FR203–204, AC203–204 | preflight metadata guards, fake-backend publication retry |
| FR205, AC202 | isolated singleton adapter and activation codec |
| FR206–209, AC205–207 | fake platform/coordinator, native synthetic hooks |
| FR208/210–212, AC208–210 | admission/write leases, drain, deadline, callback/retry |
| FR213 | reserved mode/ABI contract and synthetic capability owners |
| FR214 | functional text/actions/widget tests using C IDs, no feature design tests |

Изолированные native adapter tests могут использовать OS API и временные данные,
но не реальный GUI/Isar, перезапуск Explorer, завершение product processes или
другие logon sessions. Независимое read-only review обязательно после проверок.
