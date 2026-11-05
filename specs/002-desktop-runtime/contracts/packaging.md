# Single-EXE release contract v1

> Уточнение 2026-11-04: этот контракт описывает внутренний самодостаточный
> `ServerDeck.exe`, а не пользовательский скачиваемый артефакт. Внешняя поставка
> теперь — полный `ServerDeckSetup.exe` согласно
> [контракту установки 006](../../006-install-update/contracts/installation.md).
> Build graph ниже синхронизирован с установщиком; прежняя evidence относится
> только к внутреннему EXE. Требования runtime extraction/import closure сохраняются.

## Build graph

1. Pinned Flutter Release AOT assemble и native plugin graph создают standard data
   bundle. Runner адаптирован как `serverdeck_host.dll`, с собственным ABI
   [RunMainV1](runtime.md), `/MD`; generated plugin registrant сохранён.
2. Собрать runtime tree: host DLL, flutter_windows.dll, native Isar DLL, native/plugin
   dependencies, `data/app.so`, `data/icudtl.dat`, полное `data/flutter_assets/`, licenses.
3. Добавить app-local x64 VC runtime из разрешённого Redist выбранного MSVC toolset:
   msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll и реально импортируемые non-OS DLL.
   Полный PE import+delay-import closure аудируется; DLL не скачиваются при запуске.
4. Сформировать manifest и RCDATA payload, встроить в `/MT` bootstrap ServerDeck.exe.
   Встроить SERVERDECK_BUILD_V1 с `SDBUILD001\n<canonical version>\n` (ASCII LF,
   ≤128bytes); версия берётся из pubspec и проверяется упаковщиком против setup.
   Bootstrap imports только штатные Windows DLL. Обнаруженная bootstrap import
   flutter_windows/Isar/vcruntime/MSVCP — build failure.
5. Встроить окончательный ServerDeck.exe в полный ServerDeckSetup.exe по006;
   пользователю отдаётся установщик из GitHub Releases. Перед extraction/host load
   установленный bootstrap выполняет canonical/pending preflight по006. В CI остаются manifest,
   SBOM/licenses, import audit и exact toolchain identities; это не файлы установки.

Build prerequisites: Flutter3.47.7/Dart3.13.5 из `.flutter-version`, Windowsx64,
VS2022 BuildTools Desktop C++ v143, Windows SDK≥10.0.19041, CMake≥3.28, Python≥3.12
для сборки manifest. Exact installed compiler/SDK/CMake versions и hashes входят в
release build metadata; release нельзя пересобирать незаметно другим toolset.
Production Windows10/11 x64 не требует VS, Dart, Python или VC installer; UCRT — ОС.

## Manifest и bounds

RCDATA `SERVERDECK_PAYLOAD_V1`: header magic SDPKG001, uint32 format1, uint64
manifestLength, uint64 payloadLength, manifest UTF-8 bytes, concatenated raw files.
Без компрессии и внешнего decompressor. Manifest lists deterministic ordinal-sorted
relative paths, sizes/offsets, SHA256, hostAbi=1, platform=windows-x64, build identities.
PayloadId — SHA256 точных manifest bytes; root path derived only from this digest.
Никаких timestamps в release path ID. Embedded manifest is authoritative.

Точный manifest codec реализации: UTF-8 LF, первые строки `SDMF001`, `hostAbi=1`,
`platform=windows-x64`, `build=<base64 compact JSON identities>`. Далее строки
`file<TAB>size<TAB>offset<TAB>sha256<TAB>relativePath<LF>`, ordinal UTF-16 order.
Offsets непрерывны от 0; hashes lowercase hex; manifest завершается LF.
RCDATA identifier — некавыченный `SERVERDECK_PAYLOAD_V1` в RC source.
Native использует extended-length absolute paths, включая временную распаковку:
ограничение относительного пути не означает, что весь путь помещается в MAX_PATH.

Limits: manifest≤4 MiB, ≤10000 files, total extracted≤2 GiB, each path≤180 UTF-16
code units relative; individual length/offset overflow rejected. Запрещены absolute
paths, `..`, `.`, ADS `:`, empty segments, trailing dots/spaces, reserved device names,
backslash ambiguity, case-insensitive duplicates и reparse points. Before extraction
нужен свободный объём total+64 MiB. Файлы не извлекаются вне managed root.

## Extraction / loading

Под owner lock и extraction lock для payloadId писать уникальный sibling staging
на том же томе; проверять length/hash каждого файла, FlushFileBuffers, close,
публиковать каталог rename. Ready marker не заменяет verification. При повторном
использовании сверять весь embedded manifest. Corrupt cache переименовать в quarantine
и извлечь заново; если нельзя — native error/retry. Не брать другую версию payload.
Нельзя писать поверх загруженного runtime, удалять old cache автоматически или
восстанавливать cache из внешнего непроверенного соседнего каталога.

`SetDefaultDllDirectories(SYSTEM32|USER_DIRS)`, AddDllDirectory только verified runtime,
absolute LoadLibraryEx host с DLL_LOAD_DIR|SYSTEM32|USER_DIRS. CWD/PATH/EXE-directory
не являются DLL search sources. Isar initialization получает absolute native library
path из manifest; никакого automatic download/system lookup. DartProject получает
absolute data directory. Исходный main thread вызывает RunMainV1 и остаётся тем же PID.

При ранней ошибке до Flutter — native MessageBox с retry/cancel startup, без секретов;
cancel завершает только не запустившийся экземпляр. После running пользовательский
exit только tray. SHA256 detects corruption относительно исходного EXE, не удостоверяет
его издателя; Authenticode signing допустим, online revocation не startup prerequisite.
Не обещается защита от замены EXE/кэша вредоносным процессом того же пользователя.

## Build and unit acceptance

Сборка проверяет embedded manifest, payload hashes и статическую import closure,
включая app-local CRT и отсутствие Flutter/Isar/VC imports у bootstrap.
Native unit fixtures проверяют codec/bounds/path/ACL/singleton adapter на
синтетических входах и своих временных данных. Продуктовые свойства single-file,
offline и ordinary-user сохраняются, но фактический запуск на чистой ОС не
объявляется доказанным статическим аудитом или юнит-тестами.
По правилу пользователя интеграционные/VM/release-smoke/process-kill прогоны
исключены из обязательной приёмки и не блокируют завершение 002.
