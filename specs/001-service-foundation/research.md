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


## Поправка встроенного host — исследование 2026-10-30

Read-only audit основного checkout и layout003; native/SSH/container/UI не запускались.
Отдельный исследователь без истории подтвердил следующие реальные границы:

| Источник кода | Факт | Решение |
| --- | --- | --- |
| root pubspec.yaml, lib/app.dart/bootstrap/ | UI зависит от Windows и безусловного TrustedNativeBootstrapHost | in-process gateway вместо обязательного daemon bootstrap |
| locald/bootstrap/trusted_services.dart | reusable root не владеет discovery/store, требует hasNativePublicationGate | сохранить композицию, выделить host authority, не подставлять true |
| api/operational_sessions.dart, operational_auth.dart | native gate требует genuine TrustedPipePeer/locald role | private owner capability и verified MCP session, не role DTO |
| storage/workspace.dart, state_store.dart, key_custody.dart | Windows mutex/SID/ACL/protection imports | нейтральные ports, прежний Windows encoding |
| bootstrap/native_runtime.dart, trusted_entry.dart | Isar load проверяет locald.exe/Windows x64 ABI | verified app identity в runtime и bundle согласованно |
| MCP/bootstrap.dart | bridge может запускать locald | connection-only bridge, закрытое app даёт отказ |
| storage/migration_journal.dart, workspace_migration.dart | trusted schema3 и recovery1→2→3 уже существуют | schema3 adoption на месте, не новый importer |
| automation/jobs.dart, remote/ssh_executor.dart | recovery nonterminal в unknown; close channel не cancel remote effect | observer отдельно, no replay apply |
| executor/jobs.py, runner.py, journal.py | durable admission/commitment и systemd-run | reuse conservative lifecycle; crash устойчивость реально не проверена |

Пути locald выше относительно packages/serverdeck_locald/lib/, executor относительно
executor/serverdeck_executor/. Источники означают просмотр кода, не выполненные tests.

Decision: embedded domain library и platform ports; rationale — выбранный пользователем
один app с reuse логики. Отклонены постоянный daemon, отдельная MCP БД, wholesale rewrite,
обязательное облако и Web TCP fallback. Пользователь отдельно выбрал tray при close,
explicit exit завершает. Schema3 не меняется ради hosting boundary. Mobile baseline
foregroundOnly, отдельные платформенные поставки; официальные источники и ограничения
в [matrix](contracts/embedded-platforms.md). Backend не менялся, 003 не модифицировался.


## Pinned native semantic preflight — implementation evidence 2026-10-30

Existing requirement: inspect schema3 semantic rows/custody before writable open,
without a legacy migrator, private writable-copy bootstrap or new storage format.
Implementation reads the required bounded native layout in pure Dart and feeds
the existing logical graph/custody loader; Isar is not initialized by the reader.
Source recipe `native/isar-3.3.2/recipe.json` pins Isar4c2cd02d and MDBX924581bd.
Archive SHA256 and exact extracted bytes were checked for object/id.rs,
object/isar_object.rs, schema/collection_schema.rs, schema/schema_manager.rs,
index/index_key.rs, index/index_key_builder.rs, index/mod.rs and MDBX
layout-dxb.h, pnl.h, meta.c, options.h. These define ID sign-bit/little-endian,
u16/u24 String fields, index hash byte order and default descending32bit free PNL.
The already pinned pure Dart xxh3:1.2.0 is now direct runtime dependency; a literal
upstream hello vector validates the index encoding independently of fixture hash.
No source modification/build/native dispatch or claim of positive native
qualification was made. Other ABI/layouts fail closed. Read-only preflight,
post-open exact row equality and only-then lookup recovery are separate phases.
## T323 actual mutation tests: persistence boundary — 2026-10-31

Decision: extract the fixed transactional row dependency of the existing
StateStore, with the production pinned Isar adapter and a test/support-only RAM
provider. The existing checked open algorithm remains common; preflight bytes
become a provider row source followed by the actual semantic/custody inspector.
See the [contract](contracts/embedded-engine.md#t323t369t373--transactional-storage-dependency-2026-10-31).

Rationale: source inspection found direct IsarCollection reads/writes in
foundation_writes, automation_profile_writes, automation_plan_writes,
owner_grant_writes and automation_delta, and IsarRowSource reloads in
automation_store_view. Existing RAM read repositories cannot exercise actual
mutation CAS/receipt/readback. Both native byte parsing and actual post-open
semantic validation already exist and must be preserved as distinct checks.

Alternatives considered: fake StateStore private fields/writer methods or
scripted successful handlers would not prove actual domain transactions;
unchecked attach/fromSnapshot constructors would bypass owner/open custody;
running native Isar/realFS would violate the authorized unit-only scope. A new
storage format, database replacement or runtime memory fallback is unnecessary
and outside this extraction. No external technology research or dependency
upgrade is needed: the adapter uses only the current SDK and record classes.

This records a design decision, not successful implementation or executed tests.


### T384 observation/recovery decision record

Decision: local observation is runtime data beside the durable job, projected
through existing jobs_get/jobs_list and owner jobs.get/jobs.list result data.
The existing format3 result schema already accepts a data object. The immutable
job record and executor wire are unchanged. A separate transport/method or a
persisted observer state would confuse local reachability with remote outcome;
neither is introduced. Consumers require the new observation field from the
current embedded engine; no old-engine fallback is supplied.

Decision: a sample becomes attached only after validated current-session status;
use the existing EngineClock, a5s monotonic freshness threshold and read-time
classification. No background timer, socket, query or write is started by reading
the overlay. Five seconds matches the existing proof/RPC budget and is distinct
from the1s driver poll; it is never permission or a new operation deadline.
Stop/terminal status detaches the observer while preserving the last sample.
Identity invalidation or an aged active sample is stale, without changing job
state. New generation/reopen starts detached without remote sequence or permits.

Decision: reuse retained-job cap1250, one runtime entry and at most one current
opaque observer binding per job. Do not evict active samples to erase ordering.
No root challenge, credential, key, grant secret, plan body or raw remote text is
retained in this projection. Store only the bounded identity, sequence/time and
small state/step/epoch/check comparison facts needed to reject reversed status.

Source finding: jobs.dart currently accepts a reconcile result's boolean type
but does not require childrenStopped=true, and resets its subsequent status
sequence floor to0. A structurally terminal later reply can therefore release
local occupancy despite missing stopped-child proof or older evidence. T386
must use the existing021 evidence rather than treating intent/ACK as completion.
No Python/native execution was performed to establish this source finding.


### T391 accepted-control continuation decisions

Source evidence: _drive returns false when _drivers already owns a job; current
completion removes that entry but does not activate the already accepted control.
An accepted unknown→reconciling can therefore outlive the old driver without an
observer. Do not interpret false as cancellation, terminal proof or a new submit.

Decision: serialize only control metadata/registration/activation bookkeeping
with one local FIFO mutex. Existing metadata is already one writer; a second
root execution queue or persistent scheduler would add authority and lifecycle
that this task does not authorize. The mutex is released before root I/O and is
never held while waiting for the prior driver, so a new intent can be durable
while that driver physically drains.

Decision: two coalesced slots per active job preserve separate cancel/apply-scope
and reconcile/read-scope actors. A read actor must never inherit the cancel
method. Latest successfully registered invocation per kind replaces an older
pending one, without falling back to that old actor. Same-ID explicit replay is
a fresh authorized observation invocation with its own original30s budget;
polling an operation handle is not and cannot extend it. Neither restarts apply.

Decision: cancel control is one stop intent plus at most one status query. Unknown
still needs explicit reconciliation for terminal. An existing live apply driver
may deliver the durable cancel flag using its own current proof; its correlated
stop ACK can satisfy pending cancellation without a second root stop request.
Pending reconcile gets a turn after at most one preceding cancel activation;
continued aliases cannot starve it. A completed reconcile with uncertain outcome
is not automatically repeated.

Decision: dispatcher revalidates the stored receipt/current actor and rearms
unknown→reconciling through the existing queued progress writer if needed before
a previously accepted reconcile can run. This adds no receipt, request or permit.
An older reconcile may finish its own cycle as unknown before another pending
one activates; private tickets are not permanent phase authority. T390 still
prevents old apply/cancel from overwriting reconciling, and all terminal acceptance
still requires T386 current stopped-child/status/postcheck proof.
