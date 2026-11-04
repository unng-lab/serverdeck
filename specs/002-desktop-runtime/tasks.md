# Tasks: 002 — приложение, Isar, restore и трей

**Input**: [plan](plan.md), [spec](spec.md), [contracts](contracts/runtime.md).
**Политика 2026-11-03:** только юнит-тесты. VM/integration/process-kill задачи
T018/T019/T025/T026 отменены прежним scope и заменены T040–T042 ниже.
Старые checked задачи и описания VM-инструментов сохранены как история выполненной
работы, не предписывают новые прогоны. Отмена не означает успешный VM run.

Отметки отражают выполненную работу; незакрытые задачи и release gates остаются обязательными. Использовать готовые C ID001.
Тесты только функциональные/native/protocol/recovery, без design acceptance экранов.

## Phase 1 — Setup

- [X] T001 Закрепить Isar trio3.4.1/build_runner2.16.2, JIT generation в `pubspec.yaml`, `pubspec.lock`, `tools/generate-models.ps1`; сохранить Flutter3.47.7/Dart3.13.5 (R202).
- [X] T002 Создать native build graph `/MT` bootstrap и `/MD` host, C ABI v1 в `native/CMakeLists.txt`, `native/include/serverdeck_host.h`, `windows/runner/CMakeLists.txt` по packaging/runtime contracts (FR-201–202).

## Phase 2 — Foundational

- [X] T003 Определить typed native/platform adapter и capability interface в `lib/runtime/native_platform.dart`, `lib/runtime/capability.dart`, `windows/runner/platform_channel.cpp`; реализовать аргументы/ошибки/epoch/seq/snapshot и ограниченный буфер events (FR-205–213).
- [X] T004 Создать Isar AppSettings/schema1 и единственный store owner с durable txn в `lib/storage/records.dart`, `lib/storage/workspace_store.dart`, `lib/storage/migrations.dart`; DPAPI native protect/unprotect и write leases по storage contract (FR-203–204, FR-210).

## Phase 3 — US1 Запуск готового приложения

**Goal**: один EXE открывает одно приложение и сохранённые данные offline.
**Independent acceptance**: AC-201–204, SC-201–202/206; второе приложение не создаётся.

- [X] T005 [US1] Добавить функциональные startup/store tests в `test/runtime/startup_test.dart`, `test/storage/store_recovery_test.dart`: lock, invalid/future/missing CURRENT, crash around publication, no silent empty data (FR-203–205).
- [X] T006 [US1] Реализовать native bootstrap args/payload verification/atomic extraction/DLL loading в `native/bootstrap/main.cpp`, `native/bootstrap/payload.cpp` по manifest/bounds/import contract, без Flutter в stdio-ветке (FR-201–202).
- [X] T007 [US1] Реализовать build manifest/raw RCDATA/import closure и app-local CRT packaging в `tools/build-release.ps1`, `tools/package-release.py`, `windows/runner/host_main.cpp`; ABI RunMainV1 в original PID/main thread (FR-201–202).
- [X] T008 [US1] Реализовать межсессионный owner.lock/activation peer identity и duplicate handling в `native/bootstrap/instance.cpp`, `windows/runner/activation.cpp`; same logon restore, other logon отказ, shutdown ack (FR-205).
- [X] T009 [US1] Реализовать CURRENT preflight, initial publication и migration extension seam в `lib/storage/migrations.dart`, `windows/runner/platform_channel.cpp`; подтвердить full schema/no auto reset (FR-203–204).
- [X] T010 [US1] Собрать GUI composition root и storage error/retry с C01/C02/C10/C11/C12/C17 в `lib/main.dart`, `lib/app.dart`, `lib/runtime/runtime_view.dart`; ready только после open result, каталог001 не становится вторым релизным приложением (FR-204, FR-206, FR-214).

## Phase 4 — US2 Закрыть и восстановить окно

**Goal**: close/Alt+F4 скрывают, tray возвращает тот же экземпляр и draft.
**Independent acceptance**: AC-205–207, SC-203–204 на synthetic capability и controllers.

- [X] T011 [P] [US2] Добавить функциональные close/restore/draft/synthetic owner tests в `test/runtime/window_lifecycle_test.dart`; никакой геометрии/screenshot (FR-206–207, FR-209).
- [X] T012 [US2] Реализовать native tray Open/Exit, WM_CLOSE, WM_SIZE и Explorer restart recovery в `windows/runner/tray.cpp`, `windows/runner/window.cpp`; trayLost показывает окно без ожидания Dart (FR-206–209).
- [X] T013 [US2] Реализовать runtime coordinator epoch/seq/state и C02/C11 retry tray wiring в `lib/runtime/runtime_coordinator.dart`, `lib/runtime/runtime_view.dart`; hidden не dispose владельцев/черновиков (FR-206–207, FR-209, FR-214).

## Phase 5 — US3 Полное завершение

**Goal**: только tray Exit закрывает owner, операции/Isar безопасно завершаются.
**Independent acceptance**: AC-208–210, SC-205–206, OS-ending/crash separately.

- [X] T014 [US3] Добавить admission/drain/retry/late event tests в `test/runtime/shutdown_test.dart`, `test/storage/write_lease_test.dart` с отказами каждой стадии (FR-208, FR-210–212).
- [X] T015 [US3] Реализовать единственный shutdown pipeline/10s deadline/blocked retry в `lib/runtime/runtime_coordinator.dart`, `lib/storage/workspace_store.dart`; не закрывать Isar при активной txn, не запускать повтор записи (FR-208, FR-210–211).
- [X] T016 [US3] Реализовать OS session ending и native finishExit только после shutdownComplete в `windows/runner/window.cpp`, `windows/runner/platform_channel.cpp`; снять tray/descriptor/lock, bridge-only self-exit exception (FR-208, FR-212–213).

## Phase 6 — Cross-cutting verification

- [X] T017 Добавить native ABI/manifest/path/ACL/duplicate/seq tests в `native/tests/runtime_contract_test.cpp`, `native/tests/payload_test.cpp` с CTest, включая stdio no-host/no-DB branch (FR-201–205, FR-209, FR-213).
- ~~T018 Создать release smoke runner и CI `tools/test-release.ps1`, `.github/workflows/release.yml`: clean offline VM, noVC install, readonly EXE, corrupt cache/disk/ACL/crash; сохранять реальные evidence, не screenshot (FR-201–214, SC-201–206).~~ **Отменена 2026-11-03:** прежний integration/VM scope; вместо него T040–T042.
- ~~T019 Выполнить обязательные format/analyze/flutter test/boundary, native/release checks, lychee и clean independent review; записать реальные scope/exit/results в `specs/002-desktop-runtime/reviews/implementation.md`, не помечать пройденным невыполненный VM gate (FR-214).~~ **Отменена 2026-11-03:** прежний integration/VM scope; вместо него T040–T042.

## Dependencies / parallel opportunities

T001–004 → US1 T005–010 → US2 T011–013 → US3 T014–016 → T017 → T040–T042.
T011 после T003/T004 может выполняться параллельно с native US1 работой; T017 test
fixtures отдельно от production payload implementations после contracts seam.
US1 tests можно писать до US2/US3, но shipping release требует всего runtime lifecycle.
MVP runtime: US1+US2+US3 без настоящего SSH/MCP, с synthetic capability; 003 начинается
после актуального финального unit gate T042. Не переносить обязательный single-file/exit safety в «когда-нибудь потом».

## Traceability

| Requirement | Contract | Implementation / test tasks | Acceptance |
| --- | --- | --- | --- |
| FR-201 | packaging | T002,T006,T007,T017,T040–T042 | AC-201,SC-201 |
| FR-202 | packaging | T006,T007,T017,T040–T042 | AC-201,SC-206 |
| FR-203 | storage/data-model | T001,T004,T009,T005,T040–T042 | AC-201/203,SC-201 |
| FR-204 | storage | T004,T009,T010,T005 | AC-204,SC-206 |
| FR-205 | runtime singleton | T003,T008,T005,T017 | AC-202,SC-202 |
| FR-206 | runtime window | T010,T012,T013,T011 | AC-205/206,SC-203 |
| FR-207 | runtime/data-model | T013,T011 | AC-205/206,SC-203 |
| FR-208 | runtime shutdown | T012,T015,T016,T014 | AC-208/209,SC-205 |
| FR-209 | runtime window | T012,T013,T011,T017 | AC-207,SC-204 |
| FR-210 | runtime/storage | T004,T015,T014,T040–T042 | AC-208/209,SC-205 |
| FR-211 | runtime shutdown | T015,T014 | SC-205 |
| FR-212 | runtime/storage | T016,T014,T040–T042 | AC-210,SC-206 |
| FR-213 | runtime/003 IPC seam | T003,T016,T017 | AC-205/208,SC-206 |
| FR-214 | plan/001 contracts | T010,T013,T042 | SC-203/205; functional only |

## Phase 7 — Independent review fixes, 2026-11-03

- [X] T020 Исправить повтор первой публикации после transient failure до rename и между rename/CURRENT: хранить identity своей незавершённой попытки, продолжать её без ослабления guard неизвестных orphans; добавить regression tests (FR-204/AC-204, review P1).
- [X] T021 Обеспечить stop/cancel/close/drain всех независимых capabilities при отказе одной, сохранять результаты стадий для retry и запрещать close store/exit до их успеха; проверить минимум двух synthetic owners и deadline (FR-210–211, review P1).
- [X] T022 Подключить существующий brand mark001 как native icon resource вместо stock Windows icon; проверить resource linkage без design acceptance экрана (FR-214, review P2).
- [X] T023 Разделить startup/runtime host failures в ABI и native диагностике: ранний отказ после освобождения ресурсов ведёт в retry/cancel, поздний не перезапускает engine; проверить synthetic failing host (FR-202, packaging contract, repeat review P2).

## Phase 8: Convergence

- [X] T024 Расширить `native/tests/` и functional platform fixtures по T017: structural manifest length/offset/overflow/case-alias negatives, effective user-only ACL/reparse rejection, stale/duplicate/gapped events и startup exit latch; проверить реальный no-host/no-DB bridge branch. Existing ABI/path/duplicate/payload checks сохранить (FR-201–205, FR-209, FR-213; partial).
- ~~T025 Дополнить `tools/test-release.ps1` и native VM smoke helper сценариями GUI/tray close/restore/Exit, Explorer/OS ending, readonly EXE, concurrent/other-logon launch, disk/ACL failures и crash recovery на disposable user data; CI/evidence должны явно отделять local checks от full VM run (T018, SC-201–206; partial).~~ **Отменена 2026-11-03:** прежний integration/VM scope; вместо него T040–T042.
- ~~T026 Выполнить T024/T025 и фактическую clean offline Windows10/11x64 VM приёмку без VC/VS/Flutter/SSH prerequisites, сохранить environment/hash/exit/results; повторить обязательные проверки и fresh independent review, закрыть T017–T019 только по evidence. Текущий Hyper-V access denied и отсутствие VM не считаются passed (SC-201–206, T019, Constitution III–V; partial).~~ **Отменена 2026-11-03:** прежний integration/VM scope; вместо него T040–T042.

## Phase 9 — Native lifetime review fixes

- [X] T027 Гарантировать уничтожение PlatformChannel до engine/messenger при любом завершении host, включая отказ message pump с живым HWND; добавить проверку lifetime order без design acceptance (FR-202/FR-211, review P2).
- [X] T028 Обеспечить RAII/rollback всех ресурсов частичного PlatformChannel startup (event handles, callback, icon, worker); включить внутренние C++ exceptions, не пропуская их через host ABI; проверить отказы каждого CreateEvent/worker startup (FR-202, T023, review P2).
- [X] T029 Закрепить user-only ACL также для существующих/восстановленных descendants под owner lock; защитить no-sharing owner.lock через его HANDLE; проверить explicit permissive child DACL без изменения данных и reparse traversal (FR-204, storage contract, self-audit).
- [X] T030 Показывать понятную native причину отказа активации другой logon session, занятого owner, disk/payload/host startup вместо внутренних identifiers; сохранить retry/cancel и exit codes (FR-202/FR-205, runtime contract, self-audit).
- [X] T031 Не отменять hide/minimize раннего native close при first-frame callback; coalesce повторные startup open/close без потери exit latch, сохранить проверку переполнения на alternating events (FR-206–209, runtime contract, self-audit).

## Phase 10 — VM verification preparation

- [X] T032 Подготовить standalone `/MT` native fixtures без Flutter/VC runtime dependency и переносимый SHA-bound test kit; preflight чистой offline Windows10/11x64 должен блокировать неподходящую среду и никогда не заявлять full GUI/VM acceptance по native-only scope. Выполнить локальный запуск скопированного набора, negative preflight и independent review (T025/FR-201–202, partial preparation).

## Phase 11 — Local installation text correction

- [X] T033 Исправить испорченные русские native строки, обнаруженные пользователем в меню трея: единая UTF-8 source charset для MSVC host/bootstrap/tests и resource source; проверить Unicode code points fixtures и фактической host DLL, mandatory checks/review и текст меню обновлённой установленной копии без design acceptance (FR-208/FR-214).

## Phase 12 — Process evidence for VM smoke

- [X] T034 Подготовить read-only `/MT` release observer и hash-bound capture tool для реального product PID: image/SID/session/creation identity, HWND lifecycle facts и loaded modules; добавить переносимый self-test и negative probes, проверить локально и независимо. Не объявлять GUI/VM acceptance по snapshot; T025/T026 требуют полных сценариев и фактических VM (FR-201/202/205–209, partial T025).

## Phase 13 — Real EXE lifecycle driver

- [X] T035 Реализовать `/MT` lifecycle driver и fail-closed VM entrypoint для actual EXE: readonly directory, cold ready/original PID, close/system-close, registered tray/menu Open/Exit, concurrent duplicates, minimize/restore и warm store identity. Проверить synthetic self-test, запрет current-user GUI run, copied kit/PS5 preflight и independent review; отдельно сохранить pending actual VM/Explorer/OS/fault/data-durability acceptance в T025/T026 (FR-201–209, partial T025).

## Phase 14 — Real EXE recovery driver

- [X] T036 Расширить VM driver recovery suite: crash собственного owner/reopen, corrupt cache quarantine, kill при наблюдённом unpublished extraction staging, future/invalid/missing CURRENT с unchanged data hashes и retry того же owner/store. Проверить fixture mutators/hash invariants, оба защищённых режима в PS5/PS7 и independent review. Positive VM run и остальные fault/Explorer/OS/txn gates остаются T025/T026 (FR-202/204–205/213, partial T025).

## Phase 15 — Portable transaction durability fixture

- [X] T037 Подготовить AOT WorkspaceStore fixture без SDK на runtime path: actual candidate Isar/private CRT из embedded manifest, same-source generated schema и write gate, nonce-owned short scratch roots, observed inside-txn/after-commit barriers и kill только собственного writer. Проверить old/new theme+revision tuple, private loaded DLL paths/hash, local PS7/PS5, strict VM refusal, CLI root/nonce/reset guards и mandatory checks/review. Synthetic first publication и data fixture не заменяют actual GUI/native publication/VM gates T025/T026 (FR-204/210/213, partial T025).

## Phase 16 — Native tray liveness and shell integration

- [X] T038 Исправить cached tray availability при потере Explorer: native probe перед hide и HWND monitor, восстановление без Dart, timer ownership/startup rollback и synthetic regression. Подготовить guarded shell VM suite с actual Explorer restart/same-owner recovery и native query/confirmed session-ending paths, hashes/evidence/PS5/PS7 parser/guards; выполнить mandatory checks/review. Actual shell/OS/Windows VM acceptance остаётся T025/T026 (FR-209/212/214, partial T025).







## Phase 17 — Native access failure recovery fixture

- [X] T039 Подготовить guarded ACL VM suite: настоящий отказ native startup до owner/engine, Cancel без изменений данных и Retry того же PID после восстановления DACL; retained WRITE_DAC handle, synthetic temporary-root denial/restore self-test, journal/PS5/PS7 guards и independent review. Positive VM GUI run и остальные fault gates остаются T025/T026 (FR-202/204/213, partial T025).

## Phase 18 — Unit-only policy correction

- [X] T040 Закрепить правило пользователя «только юнит-тесты» в AGENTS/constitution и пакете002; отменить VM/integration gates без ложной отметки passed и потери истории. Сохранить продуктовые FR201–214 и AC/SC, проверить согласованность и ссылки.
- [X] T041 Изолировать WorkspaceStore через StoreBackend, заменить real-Isar тесты на fake-backend unit tests, вывести process-kill fixture из test/. Исключить historical integration helpers из native default CTest/CI; boundary check должен запрещать real Isar/process integration. Проверить сборку, unit gates и независимое ревью (FR203–204/210–211).
- [X] T042 Выполнить финальную проверку spec→plan→contract→implementation→unit criteria для всех FR201–214/AC201–210/SC201–206: format/analyze/flutter test/boundary,6 native unit, build/static import/manifest audit, lychee и clean independent review. Записать реальные результаты и ограничения; отсутствие VM не блокер, integration pass не заявлять.


## Phase 19 — Bootstrap application icon (2026-11-04)

- [X] T043 Встроить существующий брендовый IDI_APP_ICON101 в запускаемый bootstrap EXE, а не только host DLL: WindowClassRegistrar загружает ресурс process module. Один RC template используется продуктом и isolated native resource unit; проверить group/default/small icon availability, bootstrap build/static audit и independent review. Не менять логотип или дизайн экранов (FR209/214, assets001, user-reported missing taskbar icon).


## Current-only storage — 2026-11-04
- [X] T044 Удалить format1→2 migration/copyStore API/state/helper из lib/storage/workspace_store.dart/migrations.dart; current manifest/preflight module store_manifest.dart принимаеттолькоformat2, imports/callers обновитьнапрямую. Заменитьobsolete migration units current-format rejection/no-write-before-open/fresh/current recovery units иfakebackend. Userdata нестирать; currentpublicationrecoveryсохранить. Checks/freshreview вместе003/T052–066 (ConstitutionVI).

T044 acceptance уточнено review: fresh CURRENT содержит publicationVersion1 и formatVersion2; inputformat1 иunknownformat отвергаются до backend.open илюбыхwrites.


## Server workspace runtime composition
- [X] T045 Обновить lib/runtime/runtime_view.dart до server workspace003/C17 API001:
  readiness/retry/tray recovery, отдельный MCP settings dialog изsidebar и explicit
  monitoring activation во всех server tabs/overlay pause. Unit runtime scenarios,
  checks/fresh joint review без launch/process/VM tests (FR-220/AC-220/SC-220).

- [X] T046 Исправить missing MaterialIcons glyphs: отключить icon tree shaking
  в tools/build-release.ps1, добавить static full-font equality audit до packaging
  и isolated Python units в обычный unit runner. Собрать и проверить payload assets,
  без release smoke/VM; обязательное независимое ревью вместе001/R016,003/T082.
