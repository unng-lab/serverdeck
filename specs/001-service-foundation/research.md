# Research — 001.1

2026-10-10; [scope](plan.md). Design, не выполненная сборка/приёмка.

## SDK/dependencies

**Decision**: Flutter3.47.7 stable/Dart3.13.5, Windowsx64; commit/hash в Plan, сверены с [official release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json). Pins: Isar Community core/generator/native libs3.3.2, build_runner2.10.5, cryptography2.9.0, win326.4.0, ffi2.2.0.

**Rationale**: публичный stable archive вместо локального Flutter3.47.0 user-branch/Dart3.13.0. [Generator3.3.2](https://pub.dev/packages/isar_community_generator/versions/3.3.2) и [build_runner2.10.5](https://pub.dev/packages/build_runner/versions/2.10.5) совместимы по analyzer≥8<11/build4 manifests; latest build_runner2.16.2 несовместим. Solver/build остаются W01, не выполнены этим исследованием.

**Alternatives**: старый upstream Isar и latest без pin не выбраны; [Community v3](https://pub.dev/packages/isar_community/versions/3.3.2) сохраняет Isar baseline/Windows.

**Test compatibility**: test1.31.1/path1.9.1 exact pins. [Flutter3.47.7 flutter_test](https://raw.githubusercontent.com/flutter/flutter/3.47.7/packages/flutter_test/pubspec.yaml) использует test_api0.7.12/matcher0.12.20; [test1.31.1 metadata](https://pub.dev/api/packages/test/versions/1.31.1) совпадает по test_api и допускает analyzer≥8<14. Пересечение с generator/build_runner — ≥8<11. Latest test1.33.0 требует другой test_api/analyzer, не используется. Это manifest check, не solver proof.

## Storage/crypto

**Decision**: обычные отдельные записи Isar для профилей, настроек, метаданных доступа и результатов операций. Пароль, приватный ключ и passphrase внутри CredentialRecord защищаются напрямую [DPAPI CurrentUser](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata); AES-GCM рабочего пространства и root key не используются. Receipt HMAC key защищается DPAPI отдельно и служит только защите digest от перебора секретов.

**Rationale**: уточнение пользователя 2026-10-11 требует защищать все секреты доступа средствами ОС и сохранять обычные данные без шифрования приложения. Отдельные bounded rows исключают переписывание всего пространства и переполнение uint24 указателей большой единой записи Isar. Поиск работает по метаданным; атомарные ссылки и receipt сохраняются одной durable transaction. `relaxedDurability:false`, `inspector:false`; native schema validation до изменяющего open обязательна по runtime contract.

**Alternatives**: единый AEAD aggregate был ошибочным расширением scope и заменён. Не используются собственное шифрование паролей, двойное шифрование credential blob или шифрование метаданных. Открытое сохранение секрета при отказе DPAPI запрещено. Технический keyed digest сохраняется: простой SHA256 пароля в receipt позволял бы проверять догадки по копии базы.

## Windows custody/IPC

**Decision**: owner SID ACL, DPAPI CurrentUser/UI_FORBIDDEN без LOCAL_MACHINE, отдельный bootstrapToken не DB key. [DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata). Named pipe с remote rejection/first-instance/ограниченными rights, OS peer identity и challengeHMAC: [pipe security](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights), [CreateNamedPipe](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipea).

**Rationale**: нет TCP listener/firewall. Default pipe ACL непригоден; GENERIC_WRITE может разрешить создание server instance. PID не самостоятельное authentication evidence. Native adapter использует win32; отсутствующие bindings — typed dart:ffi lookup системных DLL. Cancelable I/O workers.

**Alternatives**: loopback HTTP добавляет свой auth/origin surface; MethodChannel-only непригоден standalone Dartlocald; customC++DLL лишняя поставка. DPAPI не защищает от fully compromised same-user/admin; это исключено из угроз.

**Peer SID decision after review**: использовать kernel pipe peer PID → retained process handle → [OpenProcessToken(TOKEN_QUERY)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openprocesstoken) → TokenUser, совместно с ACL/image/HMAC и повторной проверкой живого process перед grant. Impersonation не нужна; она связывалась бы с последним прочитанным frame и требовала бы thread affinity/безусловного revert. Без смены thread identity не возникает этот lifecycle в Dart workers. Failure native query закрывает канал, debug privilege не включается. Это design решение, не выполненная native проверка.

## Runtime/licenses

**Decision**: AOT locald, явно bundled libisar.dll и absolute-path loading, no runtime download. [Isar Windows packaging](https://raw.githubusercontent.com/isar-community/isar-community/3.3.2/packages/isar_community_flutter_libs/windows/CMakeLists.txt).

**Rationale**: locald не Flutter plugin process. VC++ prerequisite и Flutter runtime входят в объявленный dev layout; offline runtime отличается от dependency acquisition.

**Licenses**: [cryptography](https://pub.dev/packages/cryptography/versions/2.9.0)/Dart Isar Apache2.0, [win32](https://pub.dev/packages/win32/versions/6.4.0) BSD3Clause; [native mdbx_sys](https://raw.githubusercontent.com/isar-community/isar-community/3.3.2/packages/mdbx_sys/Cargo.toml) MPL2.0. Notices по actual resolved sources и доступ к corresponding native sources по [MPL FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). Noto сохраняет OFL. Лицензия ServerDeck не назначается; explicit choice обязателен до public release, не блокирует private development.

**Limitations**: manifests/docs исследованы read-only отдельным агентом; solver/compilation/native protection/reboot/performance не выполнялись. Все имеют будущие W/Q gates, а не fake evidence.

## T230 — installed Flutter runtime error surfaces

Inspected pinned Flutter3.47.7 source: packages/flutter/lib/src/foundation/assertions.dart has FlutterError.onError=presentError; dumpErrorToConsole reads exception diagnostics in debug and exception.toString/stack in release. packages/flutter/lib/src/widgets/framework.dart defaultErrorWidget builder stringifies exception in debug. UI main currently installs no safe boundary. These source facts establish a fallback path that may expose private values in a framework failure; no actual user-secret leak or injected compiled fault has been claimed. Chosen fix: normalize the entire error payload before any prior observer, use fixed categories/no raw fields, own safe ErrorWidget, and return handled from platform hook to avoid original VM fallback. Existing test/framework observers remain usable with sanitized events; callback failures themselves become fixed safe faults. No new package or persisted entity needed. Runtime proof follows in T231, not this research record.

## Native source build — T232, 2026-10-12

Decision: build a new Windows x64 DLL from Isar source4c2cd02d4e5c17b7edca89d141d1729ddc1698ff and libmdbx924581bdc8a1e217139c1d286c1ffb0ef0f9d14d, with frozen Cargo.lock and isolated pinned toolchains. See [contract](contracts/native-artifact.md) and [recipe](../../native/isar-3.3.2/recipe.json).

Rationale: upstream Windows build lacks a committed Cargo.lock and uses an unlocked resolution. Its MDBX build script deletes then clones a floating tag on each build, so pre-seeding or Cargo --locked alone does not pin the C source. A minimal recorded patch must use verified local source. ffi/build.rs reads ISAR_VERSION during build-script compilation; set3.3.2 before compilation. Rust path packages declare0.0.0, distinct from Dart bindingVersion.

Alternatives considered: retaining the published asset without its resolved graph does not meet native notice coverage; resolving today cannot prove yesterday's DLL provenance. No source behavior/schema change is needed to produce a new artifact with its own complete provenance.

Actual research evidence: standalone Rust/Cargo1.88.0 version commands succeeded; checked official distribution archives and PyPI libclang18.1.1 wheel were extracted locally without global installation. New cargo generate-lockfile and metadata --locked for Windows x64 succeeded with67packages, exact lockSHA90065515cd9feae9f8d7b21f09e506bd87e32dccc1252a2c1627ad627f7ad260. These are preparation/resolution results, not a DLL build or compatibility test. Installed VS17.14.36811.4/VCTools14.44.35207 and registry-located WindowsSDK10.0.26100.0 are build prerequisites. New source/native licenses, runtime linked material and corresponding sources still require collection/qualification.
