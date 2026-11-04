# Research — runtime 002

Дата 2026-11-02. Все решения ниже обязательны для Plan; runtime продукта ещё не реализован.

## R201 — один EXE без второго GUI-процесса

**Decision**: `/MT` bootstrap + встроенный raw RCDATA bundle; load internal host DLL
через штатный LoadLibraryEx на original main thread. `/MD` host использует app-local
VC DLL. DartProject получает absolute extracted data path.
**Rationale**: обычный runner импортирует flutter_windows.dll до main; распаковывать
из Dart поздно. Самораспаковщик с CreateProcess дал бы второй GUI owner.
**Alternatives**: installer/MSIX, внешний launcher, manual PE mapping, static Flutter
engine — не требуются/не соответствуют выбранной поставке. Полный [контракт](contracts/packaging.md).

Локально прочитаны headers Flutter3.47.7 DartProject/FlutterViewController: API absolute
paths доступны. Это подтверждение интерфейса, не выполненная сборка single EXE.
Источники: [Flutter Windows](https://docs.flutter.dev/platform-integration/windows/building),
[DartProject](https://api.flutter.dev/windows-embedder/classflutter_1_1_dart_project.html),
[CRT boundaries](https://learn.microsoft.com/en-us/cpp/c-runtime-library/potential-errors-passing-crt-objects-across-dll-boundaries),
[LoadLibraryEx](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-loadlibraryexw),
[UCRT](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment?view=vs-2019).

## R202 — Isar и генератор

**Decision**: isar_community, isar_community_flutter_libs и isar_community_generator
строго 3.4.1; build_runner 2.16.2. Генерация:
`dart run build_runner build --delete-conflicting-outputs --force-jit`.
**Rationale**: generator3.4.1 совместим с analyzer≥8<15/build4. build_runner2.17.1
требует build5; 2.17.0 не разрешилась resolver. JIT — необходимый обход воспроизведённого
Windows AOT crash генератора, не исключение исходников из analyzer.
**Alternatives**: старый Isar3.3.2/isolated generator/manual schemas не нужны.

Исследователь в отдельном temp package под Flutter3.47.7/Dart3.13.5 успешно выполнил
pub resolution, генерацию с --force-jit и Isar native open/write/read/close. DLL x64
SHA256 `a4c33ed6c3a11460a6d1378b39b57ef8e1b6a05bfed81062a0c8081e9e290711`.
Это scope dependency probe, не mandatory checks нового приложения.
Источники: [Isar3.4.1](https://pub.dev/packages/isar_community/versions/3.4.1),
[generator](https://pub.dev/api/packages/isar_community_generator),
[build_runner](https://pub.dev/api/packages/build_runner).

## R203 — durable store и миграции

**Decision**: relaxedDurability=false; absolute native DLL initialization,
`download:false`, inspector=false. Перед Isar.open проверять CURRENT logical format.
Только текущий format3; другие версии отвергаются доDBopen, без migration/copy/backfill поConstitutionVI.
**Rationale**: Isar default relaxedDurability=true не подходит подтверждённым записям;
Isar автоматически меняет схему при open, поэтому guard внутри DB может быть слишком
поздним. Нельзя открывать только metadata schema и удалять неизвестные коллекции.
**Alternatives**: in-place unchecked open, silent empty store и auto downgrade отвергнуты.
Источник: [Isar migration](https://isar-community.dev/v3/recipes/data_migration.html).

## R204 — native platform вместо отдельных framework plugins

**Decision**: Win32 message loop/tray, Windows token/pipe/DPAPI через один C++ platform
adapter. Basic C++ native tests и typed Dart adapter, без Python/Node в runtime.
**Rationale**: эти API уже требуются для singleton/bootstrap и IPC003; отдельные tray,
window и vault процессы/модели не нужны. DPAPI protect до Isar txn сохраняет atomicity.
Источник: [DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).

## Проверка реализации — уточнение 2026-11-03

Пользователь подтвердил только юнит-тесты. Прежние clean-VM/crash/OS smoke планы
не являются задачами или условиями завершения. Native adapters проверяются
изолированно, WorkspaceStore — через подставной StoreBackend. Сборка и статический
CRT/import/manifest audit остаются. Юнит-проверки подтверждают логику компонентов,
а не реальную интеграцию Flutter/Isar/Explorer на чистой ОС.
