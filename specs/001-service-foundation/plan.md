# Implementation Plan: 001.1 — Исполняемый сервис и защищённые профили

## Действующий план прямого SSH — 2026-11-01

Эта поправка реализует FR-SSH-001–015 [спецификации](spec.md) и имеет приоритет
над прежними executor/Ansible/enrollment/release решениями этого плана.
[Контракт](contracts/direct-ssh.md) фиксирует среду, transport, state machine,
полномочия, host artifacts и переход данных. [Исследование](direct-ssh-research.md),
[модель](direct-ssh-data-model.md), [проверки](direct-ssh-quickstart.md).
Текущая ветка/feature остаётся 001; связанные требования006/021 обновляются на месте.

### Technical Context

Flutter3.47.7/Dart3.13.5, dartssh2 и cryptography из существующих locks;
Windows embedded engine и schema3 Isar. Сервер Ubuntu24.04 amd64/systemd,
stock shell/coreutils/flock/APT; Python/Ansible и серверные ServerDeck binaries
не входят в prerequisite. Новые зависимости не добавляются. Проверки static/unit
на RAM ports; реальные SSH/FS/systemd/APT/native/UI/build запрещены текущим scope.
Лимиты: прежние250profiles/8sessions/2SSH/32mutation queue,4channels/transport,
30s metadata/10s control/1s polling/2h logical job observation; worker может
закончить уже начатую пакетную транзакцию после logical timeout, не запускает
следующий шаг и остаётся occupied до подтверждения. Нет timeout kill apt/dpkg.

### Architecture and source map

| Решение | Место реализации | Требования / приёмка |
| --- | --- | --- |
| Закрытые команды, quoting/data stdin, bounded transport | engine `remote/direct_ssh*.dart`, `ssh_transport.dart`, `ssh_io.dart`, `ssh_native_io.dart` | FR-SSH-001/002/003/014/015; AC-SSH-01/02/03 |
| Локальный compiler/preflight/catalog вместо remote RPC | engine `automation/compiler.dart`, `plans.dart`, `remote/reads.dart`; protocol `automation/plan_records.dart` | FR-SSH-004/010; AC-SSH-04/06 |
| Host owner/token/step receipt/transient unit | engine `remote/direct_ssh*.dart`; `automation/jobs.dart`, `job_session.dart` | FR-SSH-005/006/007/008/009; AC-SSH-05/07/08/09/10 |
| Отдельное terminal metadata journaling/release при read-scope reconcile, без stage/launch/resource writes | engine `remote/direct_ssh_jobs.dart`, direct command/owner method matrix, `automation/jobs.dart`; contract§8/T440 | FR-SSH-004/005/008/009; AC-SSH-03/07/08/10 |
| Сохранение schema3 и запрет legacy admission | protocol `automation/plan_records.dart`; engine `automation/snapshot.dart`, `jobs.dart`, `storage/workspace_snapshot.dart`, `executor_enrollments.dart` | FR-SSH-011; AC-SSH-11 |
| Удаление enrollment API/UI prerequisite | engine `api/owner_executor.dart`, `hosting/control_services.dart`, `remote/executor*.dart`; UI `lib/servers/`, `lib/automation/` | FR-SSH-012; AC-SSH-01/02 |
| Поставка без серверного runtime/release | protocol `build_manifest.dart`; Windows `embedded_build_bundle.dart`, `engine_worker.dart`; build tools и `executor/` | FR-SSH-013; AC-SSH-01/11 |
| Документация, unit checks, links, review, converge | root/package tests, `docs/development/`, README и specs001/006/021 | SC-SSH-01–04 |

`RemoteExecutorService`/`ConnectionExecutorWork`/`SshExecutorChannel` заменяются
прямым engine-private controller. Повторное использование domain records, compiler
и policy checks не сохраняет старую remote protocol/bridge реализацию.
Только historical DTO parser остаётся там, где нужен существующим данным.
Typed command factories не принимают caller script/path; service revalidates
authority непосредственно перед dispatch и после await до publication.

### Implementation phases

1. Закрепить requirements/contract/model/traceability, качество и clean spec review.
2. Реализовать закрытый SSH transport и identity/prerequisite/read adapters;
   проверить negative parsing, bounds, cancellation и physical drain в RAM.
3. Перенести catalogue/preflight/compiler и immutable format2 планы локально,
   запретить историческое admission; сохранить source/profile authority.
4. Перенести durable jobs на host reservation/per-step dispatch/receipt/reconcile,
   сохранить local coordinator/dedup/revoke/current target gates и quotas.
5. Убрать executor API/UI/build/runtime code, сохранить historical data readers;
   обновить release inputs, документацию и suite fixtures на новый путь.
6. Выполнить mandatory full checks, независимое code review/fix loop и Converge;
   закрывать только подтверждённые задачи текущей поправки, не старую историю.

### Constitution Check

I: один embedded engine, нет server agent; II: чтение отдельно от exact consent;
III: прежняя custody/trust, нет sudo-secret; IV: bounds и честный unknown;
V: immutable inputs, host-wide durable owner, dispatch fences и factual postchecks;
VI: FR/decision/contract/task/AC; VII: static/unit + links + independent review;
VIII: убрать executor release prerequisite без публикации/сборки реального продукта.
Нарушений, требующих исключения из конституции, не предусмотрено.

**Последнее указание пользователя — unit only**: все прежние собственные тесты,
fixtures и harness удаляются; пишутся только unit-тесты под эту задачу. Дизайн,
widget/visual/integration/native/реальные SSH/container проверки сейчас не выполняются.
Исторические результаты ниже остаются историей, не текущим gate. Изменение не
разрешает потерять функции, данные, права или проверки целевого поведения в новых units.

**Уточнение2026-10-30, без обратной совместимости**: действующий
[контракт](contracts/embedded-migration.md) исключает legacy runtime/API/bootstrap,
upgrade1/2, rollback к старым сборкам и переходные оболочки. Старый код удаляется
в этой же задаче после переноса используемой логики, а не остаётся «на переход».
Поддерживается только целевой schema3; несовместимые файлы не изменяются.

**Действующая поправка 2026-10-30**: [engine](contracts/embedded-engine.md),
[adoption/return](contracts/embedded-migration.md), [platforms](contracts/embedded-platforms.md).
Встроенный engine заменяет отдельный locald; реализация T253–T272. Прежние
hosting/native acceptance решения ниже — исторический контекст, не разрешение
на daemon/запрещённые проверки. Новая feature-спецификация не создаётся.

**Feature**: `001-service-foundation` | **Stage**: `001.1` | **Date**: 2026-10-10
**Git branch**: `feature/brandbook-design` (существующий checkout, ветка не создавалась).
**Spec Kit context**: `001-service-foundation`, разрешён через `.specify/feature.json`, не имя Git-ветки.
**Input**: [Spec](spec.md), только требования и AC этапа 001.1.
**Status**: Implement 001.1 продолжается: production bootstrap/авторизация, typed Isar storage с DPAPI secrets, Local API и UI профилей/настроек реализованы и проверены в принятых задачах. [Evidence](../../docs/development/foundation-verification.md) содержит фактический scope. Полная Q01–Q12 приёмка, compiled failpoint harness и CI acceptance ещё не завершены; clean intermediate review не означает готовность этапа.

## Summary

Создать с нуля Windows-приложение: Flutter UI запускает/обнаруживает один Dart locald текущего пользователя, авторизуется через локальный named pipe и получает готовность. locald единолично открывает Isar, защищает данные до первой записи и выполняет CRUD профилей, credentials и настроек. Два окна видят одну модель, потерянный ответ не создаёт второго эффекта, после рестарта подтверждённый профиль сохраняется. Пустота не подменяется demo.

001.1 не реализует SSH, наблюдения, host trust UI, серверные планы/задания, executor, backend, installer/updater. Разделы ПО/журналов/заданий есть с объяснением недоступности. Старые worktrees/бинарники не зависимости. 001.2/001.3 остаются Specify; этот Plan не делает всю001 готовой.

## Technical Context

**Language/Version**: Flutter3.47.7 stable / bundled Dart3.13.5; framework `abaf9c523780a608bd46686fd5e53740a07077f8`. SDK archive SHA256 `c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`.
**Primary Dependencies**: `isar_community`, `isar_community_generator`, `isar_community_flutter_libs` 3.3.2; `cryptography` 2.9.0; `win32` 6.4.0; `ffi` 2.2.0; `build_runner` 2.10.5; `test` 1.31.1; `path` 1.9.1. Exact direct pins и transitive resolutions закрепляются lockfiles при реализации. Solver, generator, реальные Isar schemas и scoped native runtime проверены с pinned SDK в принятых задачах; полная Q01–Q12 приёмка остаётся открытой. Latest build_runner/test несовместимы с generator. Root Flutter зависит от shared protocol/Windows adapter, cryptography (bootstrap HMAC), native libs и SDK flutter_test/integration_test. Pure Dart locald зависит от shared protocol/Windows adapter, Isar core, cryptography и path; generator/build_runner/test — dev dependencies, Flutter plugin package ему не нужен. Windows adapter зависит от win32/ffi/path, test — dev dependency; protocol — DTO/validation без Isar, test — dev dependency. Все listed third-party versions выше сохраняются.
**Storage**: отдельные обычные записи Isar: StoredWorkspace, StoredProfile, StoredCredential, StoredSettings, StoredReceipt; `relaxedDurability:false`, `inspector:false`. Только секреты доступа защищаются DPAPI CurrentUser. Технический receipt HMAC key также защищён DPAPI и не шифрует данные базы. [Data model](data-model.md), [custody](contracts/runtime-storage.md).
**Testing**: Flutter SDK flutter_test/integration_test; test 1.31.1 для Dart packages; native Windows harness, [матрица](quickstart.md).
**Target Platform**: Windows11x64, ordinary user с загруженным profile. Другие платформы не заявлены.
**Project Type**: desktop UI + отдельный локальный Dart process, без backend.
**Performance Goals**: startup ready/error≤30s; RPC deadline5s, UI не блокируется native I/O; 250 profiles, два окна.
**Constraints**: offline runtime после сборки; no runtime downloads/LAN/old namespace/plaintext fallback; UI не открывает Isar/receipt key. Pipe I/O в worker isolates с overlapped cancellation.
**Scale/Scope**: ≤8 UI sessions, ≤32 queued mutations, ≤250 profiles, ≤10 000 durable receipts, Isar64MiB, request≤256KiB, response≤8MiB. Нет единого JSON-агрегата и лимита16MiB на всё пространство. Profile JSON≤16KiB, credential JSON≤512KiB, settings/receipt/workspace JSON≤4KiB; private key≤64KiB. Превышение отклоняется без очистки данных/receipts; чтения остаются доступны после отклонённой записи по квоте.

## Constitution Check

До Phase0 и повторно после Phase1: нарушений конституции3.0.1 нет.

| Gate | Решение |
| --- | --- |
| I компоненты/local-first | UI→LocalAPI→Dart locald→Isar; backend отсутствует |
| II минимум прав | Нет remote effects или SSH approval; NetBird не изменяется |
| III приватность | DPAPI секретов доступа, ACL файлов до первой записи; обычные метаданные без шифрования приложения; fail closed и явная модель угроз |
| IV достоверность/лимиты | Empty/no demo, readiness/error contract, bounded frames/queues/deadlines |
| V конкуренция/совместимость | Mutex/single writer, CAS/receipts, API/store v1, incompatible вместо reset |
| VI полнота | Design/contract/work unit/AC mapping ниже раскрыт в Tasks; независимое ревью полноты обязательно перед Implement |
| VII checks/review | lychee и independent review документов; Flutter/Dart/native checks после кода |
| VIII воспроизводимость/лицензии | Stable SDK/exact pins/locks/bundled DLL/notices; собственная лицензия проекта до public release, Plan её не назначает |

## Phase 0 — Research

Implementation detail T051: shared protocol pins `unorm_dart 0.3.3` for Unicode NFC and codepoint canonicalization. Existing exact pins are retained. Pub metadata and installed source/license were checked; MIT notice must be bundled by T045. Root/locald receive this dependency transitively, not an additional storage component.

[Research](research.md) закрывает SDK, generator, crypto, IPC, OS custody, durable initialization и native composition. Исследование manifests/docs не является выполненным solver/build/native acceptance. Обязательных продуктовых вопросов001.1 не осталось.

## Phase 1 — Design and Contracts

- [Data model](data-model.md): поля, ограничения, ревизии, atomic receipt transaction.
- [Local API](contracts/local-api.md): framing/auth/grants/operations/errors/concurrency/recovery.
- [Runtime/storage](contracts/runtime-storage.md): discovery/owner/custody/initialization/shutdown/build.
- [UI contract](contracts/ui-validation.md): оболочка, формы, недоступность, AC.
- [Quickstart](quickstart.md): будущие runnable entrypoints и acceptance matrix, без утверждения запуска.

### Последовательность будущих единиц реализации

Это design breakdown W01–W07, раскрытый в [Tasks](tasks.md) конкретными файлами и проверками только001.1; не completed history.

| ID | Результат/место | Требования001.1 | Контракт | Приёмка |
| --- | --- | --- | --- | --- |
| W01 | Новый Flutter root/Dart packages, SDK/locks/native bundle/run script/CI | FR-SVC-001, FR-SVC-002, FR-SVC-017, FR-SVC-019 | runtime-storage build | AC-SVC-1A; Q01/Q02 |
| W02 | Windows adapter SID/DACL/DPAPI/mutex/pipe cancellation/secure paths | FR-SVC-003, FR-SVC-004, FR-SVC-006 | runtime-storage; local-api auth | AC-SVC-1B/BOOT; Q03/Q04/Q06 |
| W03 | Initialize/open/schema/durability, DPAPI credentials, fail closed | FR-121, FR-122, FR-SVC-007 | data-model; runtime-storage integrity | AC-SVC-1A/1B/BOOT; Q05/Q06/Q08 |
| W04 | Profiles/credentials/settings CRUD, validation/CAS/receipts/quotas | FR-007, FR-002-LOCAL-01, FR-002-LOCAL-02, FR-002-LOCAL-03, FR-SVC-015 | data-model; local-api operations | AC-SVC-1C; AC-002-1A/1C; Q07/Q09/Q10 |
| W05 | Authenticated readiness/sessions/safe errors | FR-SVC-005, FR-SVC-016, FR-123 | local-api lifecycle/errors | AC-SVC-BOOT; AC-002-1B; Q03/Q06/Q11 |
| W06 | Five-section UI/themes/keyboard/target/settings/forms | FR-001, FR-002, FR-012, FR-014, FR-SVC-018 | ui-validation | AC-SVC-1A/1C; AC-002-1A/B/C; Q01/Q09/Q12 |
| W07 | Tests/harness/CI/native acceptance evidence whole001.1 | Все требования выше | quickstart/all contracts | Все семь AC; Q01–Q12 |

W01→W02→W03→W04/W05→W06→W07. Tests создаются с соответствующим модулем, W07 собирает evidence, не откладывает защиту. Все семь AC: AC-SVC-1A/B/C/BOOT, AC-002-1A/B/C. До их приёмки этап не мерджится. SC-SVC-001/004/005/008 и применимые SC-002-LOCAL-01–04 оцениваются только в scope001.1; SSH user-study/fixture jobs outcomes не закрываются здесь.

Уточнение пользователя2026-10-11: отложены только конкретные операции/checks, отклонённые системой защиты; разрешённые storage/native реализации, проверки и fresh review продолжаются. Отказ не обходить другим инструментом или runner; exact rejected operation и её незакрытый gate фиксируются в evidence. Историческое откладывание всего блока больше не действует. Независимая подготовка W06 тем/ассетов T087 допустима после W01: только Flutter presentation resources и unavailable scaffold, без locald/storage вызовов и признака ready. Brandbook1.1 с сохранёнными tokens/palette1.0 используется неизменным; legacy session-local/dark-initial guidance из INTEGRATION.md не заменяет действующий default system и будущую service-owned persistence T036. Полная W06 integration по-прежнему требует W03/W04/W05/T031, никакие обязательные зависимости или stage acceptance не отмечаются пройденными этой подготовкой.

## Project Structure

T089 после W01 готовит offline deterministic notices preview для T045: full installed source texts и pinned native notices, config/lock/version checks, fail before output replacement. Preview явно incomplete-native-chain и не подключается к distribution build; финальный native audit/complete bundle остаются T045. Runtime/service code и отложенные проверки не используются.

Следующая независимая подготовка T088 после T087 — только pre-ready presentation из UI contract: typed safe states/reasons/retry callback, без readiness timer/private model/native calls. UI bootstrap T031 остаётся владельцем реальной попытки/deadline и обязательной зависимостью полной T034; component tests не заменяют Q12/full001.1 acceptance.

### Documentation (this feature)

```text
specs/001-service-foundation/
  spec.md
  plan.md
  research.md
  data-model.md
  quickstart.md
  contracts/{local-api,runtime-storage,ui-validation}.md
  checklists/requirements.md
  tasks.md  # только001.1; completed history и открытая очередь продолжения
```

### Source Code (target layout; implementation in progress)

```text
lib/{main.dart,app.dart,bootstrap/,profiles/,settings/,shell/,theme/}
windows/  # новый standard Flutter runner
packages/serverdeck_protocol/lib/  # DTO/validation/version, без Isar/secrets
packages/serverdeck_windows/lib/   # native primitives, без business model
packages/serverdeck_locald/bin/locald.dart
packages/serverdeck_locald/lib/{bootstrap/,api/,storage/,profiles/,credentials/}
packages/serverdeck_locald/test/
test/{contract/,widget/,security/}
integration_test/foundation_test.dart
tools/{run-serverdeck.ps1,embedded-bundle.ps1,test-unit.ps1}
.github/workflows/foundation.yml
docs/brandbook/  # существующий вход, не переписывается
assets/brand/   # существующие assets
```

**Structure Decision**: root Flutter, standalone AOT locald, shared protocol DTO, Windows OS adapter. Только locald зависит от Isar; UI держит ephemeral credential input, не receipt key. Native ABI — системные Win32 DLL через win32/typed dart:ffi, без custom C++ DLL. Worker isolates не пишут БД: coordinator и storage owner у locald.

## Complexity Tracking

Исключений конституции нет. Protocol/Windows packages нужны для межкомпонентной границы, не дополнительные сервисы/БД.

## Handoff

После clean review полного пакета Spec/Plan/Tasks — Implement только001.1. Создание Tasks не означает готовность к запуску/merge/production: нужны код/checks/native acceptance/fresh code review. 001.2 потребует отдельного следующего Plan с совместимым расширением новых данных/контрактов.

Shared bootstrap allocation T144/T142: protocol owns DiscoveryNamespace/DiscoveryDescriptor and uses exact cryptography2.9.0 for canonical namespace SHA256; Windows adapter depends on protocol by path and owns DiscoveryCustody and verifyBuildBundle without Isar. Locald re-exports the shared interfaces for existing call sites; initializeNativeRuntime remains locald-only. UI uses shared interfaces, never imports locald storage/native loader. Existing SDK and all other exact pins remain unchanged; OS custody/framing/build contracts are unchanged.

T154 form implementation: Windows adapter uses built-in Normaliz.dll IdnToAscii with STD3 flag2, without allow-unassigned/raw-punycode/email flags, bounded input253scalars/output253characters; ordinary IPs bypass IDN conversion and shared validator remains authoritative. No new third-party dependency. Explicit key picker uses GetOpenFileNameW off the Flutter isolate, file/path-exists/no-change-directory/do-not-add-recent flags; only selected file is read with65537-byte oversize probe, strict UTF8 and owned byte wipe, path is not returned to UI or API. UI formats tags as one per line so valid commas within a tag are preserved. Form draft/credential state remains mounted offstage without focus while service is non-ready; existing secrets never populate UI. These are implementation details of T035, not additional product features or completed full acceptance.

Implementation detail T158: effective reduced motion is OS accessibility disableAnimations OR current service-owned reduceMotion. FoundationApp uses MediaQuery.fromView to observe OS changes, copies brand themes only for motion policy and disables theme interpolation. Expansion, owned dialog routes and compact drawer open/close finish without large transitions; reduced dropdown choices use an explicit static modal because the pinned Flutter dropdown route duration is fixed. Selection/cancel/focus/typing/status/RPC timers remain live; no blanket TickerMode freezing. Button interpolation/ripples are suppressed; short native field/control feedback remains available. This is reduction of large motion, not a claim to remove every cursor/control feedback. Private selection options in the static popup observe readiness and suppress stale selection outside ready. Full UX/acceptance remains governed by original T033–T037/T042.
Implementation detail T159: FoundationApp owns StartupRecovery, which waits for the first coherent ready model then reads mutations.recent(limit20) once per readiness epoch. New profile/settings actions wait for this read; failed read has explicit retry rather than automatic resubmission. The toolbar opens shared-space committed history, not an assertion of a particular lost client's outcome: request IDs, operation, profile ID, commit UTC/store revision, truncation, no names/secrets/inputs reconstructed. A receipt newer than current model triggers reread; publication waits for model storeRevision at least the maximum receipt revision with a5s wait bound and safe timeout. Readiness epoch/generation/disposal guard callbacks, clear private history and cancel owned timers. API RPC deadlines remain5s. Manual refresh updates history only; empty/truncated receipts never prove a lost request had no effect, and no mutation intent is synthesized after restart. Normal reopen evidence is distinct from required crash/two-window acceptance.
Implementation detail T160: FormKeyboard owns a focus scope and an Escape-close action so closure remains available when submitting/unknown state disables the input holding focus. SubmitOnEnter is local to editable single-line profile/credential fields, handles Enter/numpadEnter; IME done shares the guarded save. Multiline tags/revealed key retain newline, dropdowns and buttons retain normal activation, so opening a selector does not implicitly submit. Initial name autofocus, Tab/ShiftTab traversal and route focus restoration are verified independently of complete Q12. Actual readiness/idle/picker/model/form guards prohibit late/repeated sends; closing after submission abandons presentation only, never undoes the service mutation.
Implementation detail T161: a pending key picker is bound to the readiness epoch at its explicit launch. CredentialInput revokes results/errors when disabled; ProfileForm supplies an authoritative ready/epoch reader, so a loss/recovery cycle that occurs before the next widget frame still retires the result. An outstanding native dialog retains its single-picker busy ownership until completion, even after input retirement; finishing retires busy without publishing the stale key or error. Current safe failure permits explicit retry, never automatic retry. Synthetic Windows keyboard events do not themselves generate platform text edits; widget evidence for revealed multiline input distinguishes Enter no-submit from injected platform newline retention. Actual native picker/physical input acceptance remains required.

Implementation detail T165: FoundationApp observes the native application exit request and awaits its owned bootstrap/client/native host closure before returning AppExitResponse.exit to the engine. Recovery/model are retired first; dispose and repeated exit share one close future. The observer is removed on widget disposal. A transport close failure does not prevent the window from closing and does not establish a clean service shutdown. This closes the existing normal-window lifecycle obligation; it does not cancel durable server mutations or terminate the shared owner while another session exists.

Implementation acceptance detail T163/T164: the FoundationAcceptance target compiles the two-window integration entry, which calls unchanged production app.main. An acceptance-only Windows test helper launches the same verified UI image as a distinct hidden process with an allowlisted environment and fixed observer role, no inherited handles; retained kernel handle owns only that child. The normal main entry does not inspect this role. Unique owned .local/foundation-ui-GUID/profile fixture is mandatory; no production profile is used or deleted. Two actors coordinate with atomic safe markers containing only PID/generation metadata. Production API/model paths perform all reads/writes, not a mocked repository. After stale CAS and explicit reload, the observer requests WM_CLOSE only for its own process's FLUTTER_RUNNER_WIN32_WINDOW. The observer is positioned after ready at100/80,1100×700 so both Windows views remain partly visible and occlusion does not suspend driver frames. Native actor-ready and process-exit waits use wall-clock polling independent of Flutter frames, bounded30s. Primary observes exit0 via retained kernel handle, then commits another update with the original owner PID/generation. After the last UI session is released, a90s test bound covers the existing60s lease/2s grace; service timing is unchanged. The first flutter drive must finish before a second drive launches a fresh UI process using the same fixture. It verifies a different UI PID/new owner generation, persisted final name and exactly three committed receipts without an automatic mutation. The script requires stage and final scenario proofs, preventing a different cached integration target from being mistaken for this scenario. Earlier widget disposal/recreation evidence does not prove native process close/reopen. Native-close evidence remains distinct from pending abrupt-crash/lost-reply/three-window/concurrent-start/offline/reboot/other-user acceptance.

Implementation acceptance detail T166: -ThreeWindows sets an acceptance-only concurrent-three scenario; normal main remains unaware of roles/scenario. Primary launches the same verified observer image before calling app.main; observer publishes its engine-entry marker before app.main and waits for primary's start barrier. Primary proves no discovery exists in the fresh fixture before releasing the barrier. Both then call production app.main; both ready clients must report empty current model and the same owner PID/generation before the first create. After real stale CAS/reload, a third verified witness image reports current committed name and the same owner while primary and observer are live. Observer closes natively; primary commits the last name, witness must receive that current model before it closes natively too. Primary still reports the original owner. Existing last-session/fresh-driver-reopen assertions verify three effects only. Distinct observer/witness positions preserve Windows frame delivery. Kernel handles belong only to created children and cleanup attempts/close cover both even if one cleanup fails. Scenario-specific final proof prevents accepting a default two-window run as concurrent-three. This is normal Q02 evidence; abrupt crash/lost-reply and other fullstage gates remain open.

Implementation acceptance detail T167: CrashObserver selects a distinct crash-observer test scenario and is rejected together with ThreeWindows before building. Observer first commits the accepted real update, then opens an unsent form draft. Primary holds its own new unsent draft after the earlier CAS/reload. Only the retained handle returned by the verified observer CreateProcess is terminated with code73; process exit is bounded30s and the shared service is never terminated by this probe. Primary proves its RAM draft remains, reports original live owner PID/generation, and launches a new recovered UI image. Recovered client calls production app.main, reads current committed name and two committed history summaries; no unsent observer field is restored and no additional mutation occurs. It then observes the primary's explicit third commit and closes normally. A fresh final drive reads three receipts. Ordinary UI/native main do not interpret this scenario. This distinguishes known committed outcome plus discarded unsent input from still-required unknown inflight/lost-reply and reboot acceptance.

T167 test diagnostics: actors without inherited console handles publish only fixture markers; stdout proof is printed by the primary driver after validating the recovered-history marker. Crash-path form cancellation uses explicit buttons and asserts the dialog closed after a new native window has taken focus. Acceptance-only diagnostics preserve the original FlutterError handler, record first error kind/library/stack and role/phase/known synthetic name flags in the owned fixture, then restore the handler; no credential/token/input dump is emitted.

T167 diagnostic file names use a validated closed role set (primary/observer/witness/recovered/reopen), never an arbitrary environment value; role validation occurs before actor test execution. Proof/error markers remain inside the owned synthetic fixture.

Implementation acceptance detail T168: compiled synthetic client-loss mode uses the production LocalApiClient and verified NativeClientTransport against the normal compiled owner while a separate held compiled peer keeps the owner alive. An acceptance-only wrapper removes one complete response frame for a selected mutation id, or holds one selected outgoing request and releases identical original after explicit retry. No production flag or failpoint is introduced. The real RPC timeout remains5s; a30s child acceptance budget covers both losses. Status/replay/current readback/recent receipt checks establish stable generation, one effect and changed-input conflict. This does not establish widget recovery UX or owner crash/reboot acceptance.
Implementation detail T169: form-level controlled-client tests exercise status/retry/readback through actual form actions and retained RAM drafts; committed receipt alone cannot produce final success before current coherent snapshot. Retry permission is revoked across readiness loss; closing a pending status request disposes presentation without undoing a sent operation or restoring the prior intent. Flutter obscured maxLines1 editors remove LF before application validation; therefore the hidden PEM field is read-only, shows an explicit instruction to reveal for manual editing or choose a file, and only the explicitly revealed multiline editor accepts manual text. Re-hiding does not transform the raw controller value; file selection may remain hidden. Password/passphrase remain single-line per their no-control-character validation. Secret lifetime and native acceptance gates are unchanged.
Acceptance fixture correction T170: T169 starts with two valid commits (profile create then settings selection/theme/reduced motion). The explicit operation commits at storeRevision3; a distinct optional external profile/settings edit commits at4 for RAM-draft retention. Delete receipt retains profile revision1 and advances settings revision when clearing selection. Credential replacement readback advances credential revision and reports the selected kind; settings-only mutation does not edit profiles. These are controlled widget fixtures, not new runtime revision rules.
Acceptance detail T171: a separate LossAcceptance Flutter integration entry composes the existing production app, bootstrap and native owner launcher with a test-only verified endpoint connector and frame-loss decorator. Normal production entries do not import controls; the observer and fresh reopen use unchanged app.main. Two real UI processes retain one owner throughout reply loss, request hold/not-found, explicit retry and late identical original; current revision and compact history verify one effect for each explicit save. The primary test composition explicitly retires both its injected client/controller and the launcher host client/monitor. A unique fixture, independent first/fresh drive and exact loss scenario proofs prevent accepting another cached target. Tests never kill a service; only the retained verified observer handle may be cleaned up. Production RPC/lease timings stay unchanged; this adds UI/native transport evidence, not owner-crash or physical input acceptance.
T173 acceptance uses a separate CredentialAcceptance UI test entrypoint with unchanged production app.main/owner. Eight fresh drives share a unique owned synthetic LOCALAPPDATA fixture while retaining canonical SID/mutex/pipe identity. Each stage validates the preceding persisted profile/settings projection at a new owner generation, performs explicit UI mutations/cancellations, checks revisions/unique receipts, releases all sessions and records metadata-only proof after discovery removal. Scope is UI credential lifecycle/keep/cancel/selection/delete/current readback, not native picker/physical input or complete DB secret/binding/crash scan acceptance. Normal builds have no credential stage controls.
T174 Q10 acceptance adds client-sessions mode to the compiled console peer used by bootstrap_native_test. One held authenticated parent peer plus seven actual production clients occupy the normal eight pipe slots; the ninth connection fails unavailable, existing sessions remain readable, and explicit closure permits bounded fixture-only reconnect in the same generation with unchanged data. All clients are owned before connect and closed even on failure; no alternate namespace, owner hooks or production session/deadline changes. This does not establish complete Q10 acceptance.

T177 native harness composition: test entry is a separate AOT executable, compiled only by build-locald -TestBuild with immutable fixture-root and current owner SID defines. Whitelist root is a fresh .local/native-acceptance-GUID created and protected by the harness; test output is its exact test-bundle. It verifies its own testOnly=true bundle and retained process image before any workspace operation. Workspace probes use a separate copied/verified normal-bundle (testOnly=false), so production Workspace/StateStore/native loader and normal executable require no test hooks or manifest overrides. The first scenario reuses workspace_child through the compiled test entry, including actual native staging/corruption/preservation probes; VM initialization kill tests remain distinct. Runtime root overrides, a wrong test manifest, foreign executable path and reuse of a completed fixture fail closed. Normal executable test flags must fail before data access with both values of the edited manifest testOnly flag. The harness owns each launched Process instance/handle, bounds it to180s and drains retained child cleanup before disposal; it never discovers a PID to kill. Fixtures/logs are preserved. Default All remains incomplete and fails; explicit WorkspaceLifecycle is a partial owned-file fixture scenario, not a claim of full disposable OS/native acceptance.
T178 cleanup correction: kill/drain is enclosed in try and Process.Dispose in unconditional finally, including Kill/Wait exceptions and unconfirmed termination. Error remains fail closed; disposal of the parent's retained handle does not assert child termination. The separate deterministic cleanup checker models six branches without inducing an OS denial or killing any process; actual compiled scenario still verifies the successful native lifecycle independently.
T179 CoreStorage composition extends the existing separate AOT entry with eight fixed enum routes to unchanged shared native probes. Each case has an isolated protected subdirectory and its own process; a protected CREATE_NEW claim under the compiled root is written before any case work and retained even after failure. Concurrent/repeated attempts cannot reset a case. The single root/SID whitelist and manifest/image checks remain mandatory for every process. No user-supplied repository mode or path reaches shared helpers. CoreStorage runs workspace, repository, credential snapshots, coordinator mutations, controlled-session API router, real same-process native pipe channel, lifecycle with controlled clock and real store/mutex, and quota boundaries. Resource case inherits its existing360s fixture budget, others180s; production limits are unchanged. Markers are required exactly once, stdout admits only each case's fixed safe markers/pinned banner and repository's bounded capacity counters. Default All still rejects incomplete full acceptance. This does not establish cross-user/auth-failure/fullnormalservice/compiledinit-commitcrash/UI/manual/fullQ acceptance.
T180 CommitRecovery uses the existing separate compiled test entry and unchanged state_store_crash_child. Eight fixed phase routes represent four writer/verifier pairs: before/after commit, controlled native-handle invalidation and controlled DPAPI availability. Verifier paths are derived from the fixed writer name under the compile-time root; prior writer claim and case directory are required, verification has its own exclusive claim and cannot initialize a missing case. Hard-crash stdout boundary is flushed inside an uncommitted native row transaction or after StateStore.commit respectively. Harness observes the boundary within30s, verifies the retained launched image and live process, terminates that exact child, confirms exit within10s, then starts a new verified AOT process. Before state/rows/receipt0 and after1 are checked by the native helper; confirmed credential unwrap works. Native/DPAPI fault paths are test-only controlled seams, not real OS refusal. Production entry/storage have no new hooks. The native before branch tests transaction atomicity, not a coordinator/API crash point; full initialization/reply/reboot/other-user/manual gates remain open. Crash output accepts only fixed unique boundary/native banner, normal/error/reuse guards remain mandatory.

T181 initialization recovery instruments the actual Workspace.open sequence with nine compile-time guarded boundaries: protected staging creation, key flush, manifest flush, native files creation, both initial rows written inside an uncommitted transaction, durable initial transaction, before promotion, after promotion, active store opened before return. SERVERDECK_TEST_INITIALIZATION_PROBES defaults false and is enabled only by build-locald -TestBuild together with its immutable fixture-root/SID whitelist. Normal compilation removes guarded calls; handler installation/invocation rejects when disabled, no normal entry flag or manifest field enables it. Test builds without an installed handler continue normally. The acceptance entry installs one handler for one fixed boundary in one fresh process; its flushed marker is followed by a never-completing future, and the retained-child crash driver terminates that process. No runtime storage/API hook is exposed to the UI.

InitializationRecovery executes nine fixed writer/verifier pairs in separate protected case directories. A protected boundary record stores only format1, fixed case name and SHA256 identities of present receipt-key/manifest; no clear secret or wrapper bytes. Writer checks directory shape/file count and owner ACL before publishing its boundary. Verifier requires this existing record and exact shape before Workspace.open. First five partial stages must fail STORAGE_BLOCKED and preserve file inventory/key+manifest identities without promotion; last four must open a validated initial-empty state, complete promotion when needed and retain key/manifest identity. Native DB/lock bytes are not asserted immutable across native reopen; no claim of full file marker scans. Writer/verifier exclusive claims, normal/test negative guards, boundary30s/exit10s/phase180s budgets and strict markers apply as in T180. VM debugger tests remain an independent normal-compilation regression; compiled uncommitted point follows both initial row writes whereas that VM breakpoint precedes the settings row write. This scope proves actual initialization recovery without reboot/other-user, API reply crash or full All acceptance.

T182 strengthens inventory checks to exact names and file types (0 files; receipt-key.dpapi; key+workspace.manifest.json; those two plus workspace.isar/workspace.isar-lck). A separate fixed negative case init-native-files-inventory-replaced stops before native open, then the driver renames its owned empty workspace.isar to unexpected.isar. Count remains4; verifier must fail before Workspace.open with TEST_SCENARIO_FAILED/empty stdout and preserve the replacement bytes. Both failed phases remain single-use. The nine ordinary successful pairs are unchanged; accepted metadata separately requires inventoryReplacementRejected=true. First pre-fix evidence does not prove this stronger acceptance.

T183 SecretMarkers covers native persistence within Q05, without changing production code. build-locald -TestBuild embeds the bounded4096byte synthetic markers.json as a base64 compile-time define; normal entry does not import marker helpers or accept runtime fixture input. Separate fixed writer/verifier phases share one protected single-use case. Writer uses actual Workspace, real CurrentUser DPAPI observed by an acceptance-only delegating provider, coordinator and ApiServer with a controlled authenticated session. It saves password and PEM/passphrase profiles plus settings (3commits), scans case files before protection and after commits/close, and checks response schemas/no secret fields or markers. The observer copies the generated receipt-key marker, verifies protected outputs and delegates all protection/unprotection to real DPAPI; it neither persists nor prints clear buffers.

Fresh verifier requires existing workspace files, reads native profile/settings payloads without receipt-key decryption to establish readable ordinary metadata, closes native store, then opens actual Workspace and checks unchanged3receipts/2profiles/2credentials and exact secret roundtrip through DPAPI. File scanning covers all owned case files including native DB/index/lock/key/manifest and any extra case files; UTF8/UTF16LE/base64 forms, PEM body/decoded body and generated receipt-key bytes. Scanner reads64KiB chunks with longest-pattern overlap, copies inputs and clears owned patterns on close. Safe code only on leak; strict parent stdout/stderr allowlist admits no private text. Synthetic source/test executable inputs deliberately contain fixture data and are excluded, as are other-user/global OS Temp/pagefile/dumps. Controlled router is not full normal-owner/UI/auth/diagnostic acceptance; original Q05/T040/All gates remain open. Root diagnostic tests independently exercise the existing formatter; no new runtime diagnostic sink is claimed.

T184 acceptance-helper cleanup preserves the runtime ownership policy: failure in the post-unprotect observer clears the obtained clear buffer before rethrow; scanner/input cleanup is unconditional. A failed/unconfirmed direct metadata native close or retained Workspace/StateStore reservation prevents fixture lease release. The failed process is handled by the retained parent deadline/cleanup path and cannot publish final success. Actual native close refusals are not induced or claimed by this increment; normal compiled success and source-level failure control flow are evaluated separately.

T185 requires exact owner-only ACL on existing active directory and all four files before direct metadata native open. A separate fixed negative case secret-markers-unsafe-acl writes the same synthetic data, then the driver adds a BUILTIN Users Read ACE only to its owned workspace.isar. Fresh verifier must fail before native initialization/open with generic safe error and empty stdout; DB bytes remain unchanged and both phases single-use. Accepted proof separately requires unsafeAclRejected=true. This controlled permission fixture is not cross-user or OS-denial acceptance; files remain preserved, no global permissions change.

The attempted Set-Acl operation was denied by the OS for missing SeSecurityPrivilege; T185 negative remains open/deferred and is not retried through another tool/runner. SecretMarkers now executes only the available positive persistence/reopen checks and explicitly records unsafeAclRejected=false. The separate SecretMarkersUnsafeAcl route requires an explicitly prepared disposable environment; only a successful future negative run could record true. It is not executed as an automatic fallback or as a bypass of the denial. Guards already implemented in the verifier remain active for positive runs; no whole Q05/Q06 acceptance is claimed.

T186 closes the first review's two acceptance gaps: scan immediately after the settings commit (all three commits, before later reads/close); outer cleanup scope starts before input validation/marker preparation/SID/hash/mutex acquisition. The obtained lease is nullable and disposed even when not acquired; an actually held lease still cannot be released after unconfirmed native close/reservation. Patterns/input cleanup remains unconditional. T185's denied operation is outside this correction and remains deferred/open.

T187 addresses the aggregate UI review: the controller disposes its owned canonical request bytes before notifying succeeded, retaining only safe immutable method/id for result presentation. Unknown and retryable states retain the original payload; failed/conflict/reset/disposal semantics remain unchanged. Initial Material/Cupertino/widget localizations use ru-RU from the pinned Flutter SDK; no language preference is added. Custom compact navigation tooltip is Russian. History retains explicit UTC timestamps. The root lockfile adds SDK flutter_localizations and its resolved intl0.20.3 dependency. Tests inspect live-versus-retired intent behavior with a closed actual LocalApiClient (no transport), plus Russian framework/custom labels with an English platform locale and both motion modes. These widget regressions do not replace physical/native acceptance.
T188 fixes a reproduced reader/publication conflict. Windows adapter paths.dart provides ProtectedSnapshotReader: retained non-inheritable read handle with share7, bounded copied64KiB chunks, single-use read and explicit idempotent successful close. security.dart validates retained handle OWNER+DACL via GetKernelObjectSecurity, reusing the same exact SDDL validator as pathname checks; only READ_CONTROL is requested, no SACL privileges. ReplaceFile-path promotion uses FileRenameInfoEx flags3 and an owner-verified regular source handle (DELETE|READ_CONTROL), absolute UTF16 target name, no delete-first gap/fallback or permission change. Non-replacing directory promotion is unchanged. Deterministic regression keeps the old reader open during actual protected replacement, verifies old/new bytes and no pending file, including a Unicode destination. Multi-chunk nonzero/exact-bound test guards buffer copying and cleanup. This is a production concurrency fix, not a test-only permission relaxation. Rebuild and full compiled credential journey, mandatory root checks, Windows suite, relevant locald discovery/bootstrap/storage checks and fresh independent review are required before closure. The original failed-step underlying OS error remains unavailable; regression proves the defect and fix without claiming an exact recovered syscall trace.
T189 adds a separate UnknownInflightAcceptance test target/script. Its primary/reopen actors use unchanged production app.main; a verified same-image observer composes production FoundationApp/bootstrap with acceptance-only LossClient and drops one actual committed profiles.update reply. The parent signals send after arming, then observes the child submitting/requestId/replyDropped and uses only its retained own process handle for exit73. Its monotonic send-to-observed-exit bound is4s, less than unchanged5s RPC deadline, proving the UI died while awaiting the result. No status/retry/normal close occurs in that child. The live normal client verifies store2/exact-one matching receipt, same generation, performs store3 update; a new process/new owner verifies3effects/recent and no auto-save. Safe proof includes child PID and elapsed milliseconds. This covers committed effect with inflight UI loss, not unknown native transaction state, pre-enqueue cancellation, owner crash, physical/offline/reboot. No test controls enter normal application/locald entrypoints. Failed termination is not retried in cleanup; owned handle still closes, failure remains failure. Build selector rejects multiple acceptance targets before SDK/build; wrapper requires scenario-specific proofs so cached unrelated binaries cannot pass.
T191 strengthens the existing compiled bootstrap owner-crash run: an acceptance-only LossTransport around production LocalApiClient drops the committed create reply. The console emits a pre-send marker and awaits an explicit parent send signal before mutate; parent starts its stopwatch before sending that signal, owns the launched locald Process handle, observes dropped-reply/pending readiness and kills only that child. Both kill admission and actual observed exit must occur before4s, below unchanged5s RPC deadline. The pending call must fail SERVICE_UNAVAILABLE, with no status/retry/success. Existing abandoned mutex, unchanged stale discovery, new generation/token and same workspace checks remain. Fresh verified peer reads revision1/profile and committed receipt, with exactly one matching requestId in recent. This strengthens console native coverage; UI owner recovery, before-commit crash and reboot remain separate gates.
T192 closes the observer startup race: before observer launch, bounded25s protected discovery must identify the newly launched owner PID and a new generation under the verified build. Publication requires mutex ownership. Missing publication polls; an existing invalid descriptor fails. This barrier lies outside the pending interval and does not change production deadlines.

T193 adds tools/test-foundation-available.ps1, a fixed sequential dispatcher of eleven existing acceptance phases: CoreStorage (includes WorkspaceLifecycle), CommitRecovery, InitializationRecovery, SecretMarkers, production-client bootstrap owner-loss, and six UI suites (two/three-window, observer crash, loss, credentials, unknown-inflight). Child scripts rebuild and enforce their own proofs; no cached binary/argument overrides or retries are exposed. Output stays in a new ignored local run directory; parent emits safe fixed phase markers. Result records passed/failed, completed names, elapsed times and explicit fullAcceptance=false/exclusions. It is a runnable aggregate of available coverage, not full All/native/manual/CI completion. First failure stops the remaining phases; fixtures/logs are preserved. ListOnly inventories the fixed scope without SDK/build.
T194 joins the previously separate native channel and coordinator queue probes. An acceptance-only GateProtection delays actual CurrentUser protection of a synthetic password, keeping one mutation running before commit; production API clients use verified native pipes and real ServerChannel sessions against the actual Isar coordinator. Closing the sole queued requester must revoke its session, cancel queued work without receipt/effect and permit explicit same-id retry on a surviving connection. A second live duplicate prevents cancellation; disconnecting all requesters of the running mutation does not abort its durable commit. Status/recent and store revisions verify four single effects, same generation and no false not-found for running work. New fixed proof markers are mandatory in compiled CoreStorage channel mode. Controlled ready view and same-image test peers are fixture composition, not normal-owner/actual UI window/fullQ acceptance. No production scheduling hook is introduced.
T195 makes T194 transport loss abrupt: retain each actual NativeClientTransport before returning its endpoint and close that handle directly in both disconnect rounds. No graceful session.close precedes EOF, so ServerChannel error/close must revoke the session before coordinator cancellation/survival can satisfy status and receipt assertions. Cleanup retains normal client retirement after the scenario.

T196 extends the native channel fixture with authenticated malformed peers. Only actual transport sends are controlled: zero and request-length262145 headers must close before payload, while partial header/body receive a second incomplete fragment after3s and still disconnect within4.5–7s from the earlier first send under unchanged5s partial deadline. Per-channel server write byte counters captured after grant prove no additional echo/error write attempt; serving completion/session count prove revoke, unchanged store revision plus surviving client profiles read prove no effect/continued availability/same generation. Four peers fit the fixture's eight native names including the final pending-accept cleanup slot. New fixed marker is enforced in compiled CoreStorage. These are controlled ready/self-image peers, not normal-owner/fullQ10/all codec boundaries.
T197 strengthens invalid-length proof with fixture read observation after grant: exactly four received header bytes and zero attempted payload reads. The server callback observes completed byte counts, allowing fragmented header reads without assuming one kernel read; a read starting after four bytes is a payload attempt. No production hook or extra response-time requirement is introduced.

T198 wires the existing fixed eleven-phase available dispatcher into foundation.yml after serial checks/Release build and before the intentional incomplete full-acceptance gate. Windows Server2022 is a CI build/native-test environment with VS2022, not Windows11/manual acceptance; runtime bundle checks currently require Windows x64. Job budget120min accommodates serial full package suites and per-phase bounded native/UI runs. Dispatcher preserves ignored raw logs and emits only safe phase/result metadata; workflow has no artifact upload or release step. Existing full gate remains failing until its actual requirements are proved. Static workflow validation and prior local suite evidence do not establish a hosted workflow run.
T199 extends the existing actual native channel fixture with eight admitted production-client sessions, a ninth unadmitted handshake (hello only, no grant/error), unchanged durable state and continued reads for all admitted peers. Native handle loss and awaited server completion reclaim exactly one slot; a replacement reaches eight again and reads remain available. All extra peers are detached before idle-accept cleanup with a dynamically unique slot name. This proves the existing eight-session bound through real native transport, not a normal owner/fullQ10 matrix. No production code/limits or privileges change. Compiled CoreStorage requires the fixed session-limit proof marker.

T200 proves the existing global32queued bound through the channel fixture. Three admitted native clients distribute32unique creates behind one protection-gated running create, remaining below each16pending limit. Separate observer checks all statuses and live reads; overflow returns RESOURCE_LIMIT/not-found without durable state. Gate release produces33unique durable effects/receipts, and explicit same-request overflow retry succeeds as effect34. Worker detach and idle cleanup remain bounded. Existing GateProtection is acceptance-only; production deadlines/limits remain unchanged. This is channel composition evidence, not normal owner/fullQ10.

T209 extends the existing actual native channel fixture for T201: production clients with a wrong bootstrap proof, a different syntactically valid build ID or an incorrect expected server image hash cannot obtain a grant. Server writes at most hello, no session/durable effect remains. An authenticated read-only client reads profiles, receives FORBIDDEN for create without receipt/effect and reads again. Native detach returns count0 before unchanged legitimate mutations. All configurable inputs are acceptance helper arguments, not new product controls. The fixed compiled marker proves only these cases; full process/token/foreign-user/remote/replay/runtime/corruption matrix remains under T201.

T210 composes real native identity-query failure with the existing accepted channel fixture. A Windows acceptance helper invokes production OpenProcess path using an invalid nonzero DWORD PID, and production processUserSid/OpenProcessToken using null process handle. It requires original safe IDENTITY_UNAVAILABLE and unchanged process SID before returning that original exception. After actual kernel peer verification, the channel's acceptance callback propagates it at initial or repeated verification. Separate confirmation/count assertions distinguish probe defects from intended rejection; nohello or hello-only/no grant/session/effect, followed by legitimate baseline. No production API/hooks or native privileges change. These invalid-input cases do not prove a genuine pipe-peer access-denied failure, foreign-user denial or unchanged thread token; whole T201 remains open.

T211 validates replay and channel-bound sessions using an acceptance-only ClientTransport wrapper delegating actual native peer checks/read/write/close. Capture a valid first authentication frame from an admitted production client that stays alive; replay it byte-for-byte on a fresh pipe with an observed different server nonce. Require completed substituted write, hello only/no grant, one peer check and unchanged surviving session/state. On another admitted channel, replace only sessionId of a valid create envelope with the original live client's grant; require no ordinary reply/session/effect, continued original read and native detach. Owned capture/substitute byte buffers are wiped after native completion/fixture cleanup, never logged or persisted. This does not change production controls or prove full foreign-user/remote/prerequisite/corruption matrix.

T212 exercises the actual server-side PipeWorker.verifyPeer and retained kernel identity comparator with mismatched expected SID, absolute image path and hash at initial/repeated handshake. Acceptance inputs change expectations only, not caller identity/ACL/privileges or product configuration. Six cases confirm original native-worker IDENTITY_UNAVAILABLE before recording a proof, exact attempted/successful checks and zero/hello-only writes, no grant/session/effect and following legitimate baseline. A different valid well-known SID is selected independently of the current owner. This is a same-user mismatch test, not evidence of a real foreign OS user or remote connection. Full T201 remains open.

T213 adds a fixed normal compiled prerequisite driver, rebuilding Debug and verifying the three manifest-bound source files. Each owned fresh bundle/profile has an unchanged synthetic marker. Missing native DLL and hash-consistent malformed DLL exercise verification/loader refusal; format2 and executable-hash mismatch exercise compatibility refusal. Four actual normal-entry exits require safe exact error/no stdout, no private namespace and unchanged profile inventory within30s. Positive control uses the normal UI and locald, both retained beyond startup deadline, then closes only its launched UI and awaits natural locald exit0/workspace files. An unauthenticated bare owner timing out is not a healthy control. No test flags, ACL/privilege changes, cleanup or upload; raw logs stay ignored. Proof fullAcceptance=false and excludes missingVC/otherplatform/foreignuser/fullQ04.

T214 extends the fixed available dispatcher to twelve phases by inserting T213 normal-prerequisites after compiled-secret-markers and before bootstrap owner-loss. Existing eleven-phase T193/T198 entries remain historical. Current instructions reflect twelve phases. Serial rebuilding and strict child proofs, first-failure stop, ignored raw logs, safe parent phase markers and fullAcceptance=false remain unchanged. Actual twelve-phase aggregate evidence is required for closure; static validation or prior eleven-phase success is not substituted. FullAll/T201/CI/manual remain open.

T215 extends the compiled WorkspaceLifecycle fixture with four missing identity/corruption negatives after genuine creation/close. A real CurrentUserDPAPI receipt wrapper for different valid IDs is successfully unprotected for its own IDs before being substituted; manifest workspace/key IDs are independently changed; a native DB is damaged. Each original workspace refuses open with STORAGE_BLOCKED and exact file inventory/bytes remain unchanged, without new staging/reset/key. Four fixed case markers follow all assertions and are required by the compiled driver. Existing healthy reopen/other negatives remain. This is native workspace composition, not the whole normal-UI/credential/DPAPIavailability/foreign-user/unsafeACL matrix.

T221 adds compiled-api-commit-recovery immediately after compiled-commit-recovery in the fixed available dispatcher. Current scope is thirteen phases; earlier T193/T198 eleven-phase and T214 twelve-phase evidence stays historical. Each phase rebuilds and enforces its own strict proof, including T220 writer/fresh-verifier cases. Serial execution, first-failure stop, private local logs and fullAcceptance=false remain; the new source requires an actual current thirteen-phase result. Full All, hosted CI, manual acceptance and exact deferred operations remain open.

### T230 — UI runtime diagnostic privacy boundary

F230 extends existing W05/W06/W07 privacy enforcement per FR-123/FR-SVC-016/SC-SVC-004 and Constitution III. No data model, protocol, dependency, migration or backend change. `lib/main.dart` installs `lib/diagnostics/ui_runtime_diagnostics.dart` before runApp; the helper owns only FlutterError.onError, PlatformDispatcher.instance.onError and ErrorWidget.builder. It creates fixed typed UI faults and sanitized details, never deriving text from exception/stack/context/library/collector. Existing observers receive sanitized data; normal domain/readiness/uncertain-mutation behavior is unchanged. Exact callbacks/idempotence/reentrancy/error-widget/fallback rules and acceptance are in [runtime diagnostics](contracts/runtime-diagnostics.md). Debug and release use the same safe categories and fixed user action. No remote service status or automatic retry/reset is inferred from a framework error. Research records installed pinnedSDK evidence; T231 implements after document review. Constitution check post-design: I/III/IV/V/VI/VII/VIII preserved, no additional rights or public artifacts.

## T232/T233 — source-built native artifact

T250 changes only Rust distribution encoding to the official pinned1.88.0
Windows x64 TAR.GZ inputs. The toolchain version/commit and extracted bytes
remain fixed; compare the complete toolchain digest and license payloads against
the previous XZ preparation. See the native-artifact contract for the bounded
TAR route, no fallback and new recipe-bound artifact requirements.

Constitution VIII and T045/T207 require resolved native dependency/license coverage. The old release DLL graph remains unestablished. Build a new same-version artifact using [native-artifact contract](contracts/native-artifact.md), [research](research.md) and checked recipe/lock; qualify it before replacing the current provider. This is a build-input change, not a storage/API migration or new product capability. Components, pinning, artifact custody, qualification, notices, failure preservation and activation are defined in that contract. T232 covers design; T233 covers implementation and evidence. All stage/manual/CI gates remain separate and open. Constitution gates: source/hash/lock/license coverage must pass before activation; independent review and current checks are mandatory. No release publication or project-license decision follows from this design.

## Extension021 — 2026-10-21

[Plan021](../021-mcp-control/plan.md) и [Tasks021](../021-mcp-control/tasks.md) добавляют MCP роль, API1.1, schema2 preservation migration и необходимую реализацию чтений/jobs. Этот Plan остаётся историческим/действующим scope001.1, его completed evidence не квалифицирует расширение. При запуске Spec Kit001 явно выбирать feature_directory001; текущий feature context указывает021. Не включать мост автоматизации в owner UI capabilities по умолчанию.


## Действующий план поправки: встроенный движок

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-30 | **Constitution**: 4.3.0
**Git context**: существующая feature/mcp-control, грязный checkout; ветка не переключалась.
По прямому указанию пользователя меняется прежняя 001, новый feature не создаётся.

### Summary

Извлечь рабочую логику locald в serverdeck_engine, убрать UI→daemon IPC,
сохранить защищённый IPC для необязательного stdio MCP. Один процесс приложения;
один engine worker isolate владеет Host/store/runtime; Flutter UI использует внутренний Dart-port gateway. Блокирующая FFI/hash/file work не выполняется в UI isolate. Второго store/engine нет.
Windows bundle format4 со storage schema3 первым, остальные платформы позже.

### Technical Context

- Flutter/Dart: текущий SDK >=3.13.5 <4, зависимости/lock сохраняются.
- isar_community3.3.2 с override third_party/isar_community, generated records и
  ABI сохраняются; native library поставляется с app.
- dartssh2 4.1.0, cryptography2.9.0: существующий transport pool вне браузера.
  Pin4.1.0 совпадает с engine pubspec и root/engine lockfiles; upgrade не требуется.
- Windows: win32 6.4.0/ffi2.2.0, DPAPI/SID/ACL, mutex/pipes, retained process
  identity и verified bundle. Это реальные blockers portability.
- Удалённый Python/systemd executor021 остаётся отдельным компонентом на цели,
  нужен только уже требующим его функциям. Это не daemon клиента; wire не меняется.
- Разрешены static/unit/widget; runtime release/platform qualification не установлены.
- Лимиты, interfaces и версии: [engine](contracts/embedded-engine.md), [MCP/jobs](../021-mcp-control/contracts/embedded-host.md).

### Constitution Check

I/III/V/VII: 4.3.0 меняет обязательный daemon и уточняет сохранение текущего ServerDeckNext.
Flutter/Dart/Isar, OS protection, trust и отсутствие backend сохраняются.
VII: только static/unit/widget; не выдавать их за native acceptance. VI: цепочка
FR→contract→task→AC в [tasks](tasks.md). VIII: runtime/notices/bundle обязательны,
релиз не разрешён. После design: все Windows решения в контрактах; будущие
платформы отделены и не блокируют extraction/Windows.

### Project Structure and Ownership

| Место | Ответственность и перенос |
| --- | --- |
| packages/serverdeck_engine/lib/ | Чистый Dart: profiles/automation/remote/mcp/storage из locald, public engine.dart |
| packages/serverdeck_engine/lib/platform/ports.dart | Lease/vault/files/runtime/verified identity/clock и runtime-owned authority |
| packages/serverdeck_engine/lib/hosting/ | engine_host.dart, lifecycle.dart, in_process_gateway.dart, capability_snapshot.dart |
| packages/serverdeck_windows/lib/ | Windows ports, DPAPI/SID/ACL/mutex/pipes; app image вместо locald.exe |
| lib/bootstrap/ | EmbeddedEngineHost/EngineGateway вместо обязательного NativeBootstrapHost IPC; сохранить DTO/controllers |
| lib/platform/ и lib/shell/ | tray/menu и widget lifecycle без БД/SSH/доменной логики |
| packages/serverdeck_mcp/ | прежние stdio/tool schemas, connection-only bootstrap в режиме --mcp-stdio |
| packages/serverdeck_locald/ | удаляется целиком после переноса используемой логики; никаких re-export/compatibility оболочек |
| packages/serverdeck_platform_{linux,macos,android,ios}/ | последующие платформенные поставки, не fallback текущего Windows этапа |
| executor/ | без нового протокола, unknown сохраняется |

### Phases and Delivery

1. **001.E1 Extraction**: ports, reuse services, unit parity, in-process gateway.
   Старый root/entry удаляются; переходная оболочка и два runtime запрещены.
2. **001.E2 Windows adoption**: app host/tray/ownership, schema3 adoption,
   MCP app IPC, bundle/prerequisites/return instructions и разрешённые checks.
   Не менять/устанавливать поставку003 и не публиковать релиз.
3. **001.E3 Portability boundary**: capability contracts/fakes принимаются здесь;
   реальные Linux/macOS/mobile adapters — отдельные последующие поставки по
   [matrix](contracts/embedded-platforms.md). Заглушка не означает поддержку платформы.

### Reuse and Change Boundaries

TrustedControlServices.create требует native publication gate; нельзя подставить
true. HostAuthority создаётся только настоящим host под lease; OwnerSession —
через UI binding, MCP session — после verified IPC proof+grant. Отделить services
от pipe authentication с сохранением gate ordering и revocation fences.

StateStore/Workspace/KeyCustody привязаны к SID/Windows; перенести interfaces,
сохранив Windows blob encoding/entropy. Смена процесса не требует schema4.
Поддерживаемый source и return заданы [migration](contracts/embedded-migration.md).

Отклонены: обязательный locald (против решения пользователя), отдельная MCP БД
(два источника истины), обязательное облако, wholesale rewrite и Web TCP fallback.

### Validation and Limits

[Quickstart](quickstart.md) задаёт команды и сценарии. Native app/DPAPI/Isar/tray
и реальные remote faults не проверяются здесь. Готовность спецификации к реализации
не равна readiness выпуска. Изменения только в документах; implementation Tasks
не отмечать выполненными на основании текущего аудита.

### Дополнение того же плана: один binary и полноценный tray

Отдельного mcp.exe нет. packages/serverdeck_mcp остаётся библиотекой, entry
включается в serverdeck.exe через mode dispatch до runApp. Windows runner в stdio
mode создаёт headless Flutter engine и сохраняет inherited std handles, без
console attach/window/tray. MCP role не следует из image/argv: общий app image
на внешнем endpoint даёт только MCP grant-auth path; owner остаётся внутренним.
Контракт и tests T274/T275 дополняют T265/T268/T271 и существующий tray T259.
Tray menu перечислен в embedded-engine contract; это управление существующим
app/sections/status/exit, без новых remote операций. Native runner/tray behaviour
не запускать для проверки в текущем scope. Static/unit/widget evidence не заменяет
реальную OS acceptance. Новая feature-спецификация не создаётся.

### Artifact verification как prerequisite Windows extraction

Manifest4/app identity часть T265 готовится вместе с T255/T256 до создания Host:
иначе native runtime port зависел бы от прежнего locald role. Это shared foundation,
не досрочное включение IPC. Полные discovery/handshake/MCP host изменения T265,
bridge T266 и publication gate по-прежнему следуют после доверенного T257.
Native DLL инициализирует только composition root до первого обращения к store,
с verified format4 bundle и proof именно текущего процесса из ТОГО ЖЕ bundle.
Нет downgrade/fallback к format3; old loader удаляется в T276 до финальной приёмки.
Native DLL process lifetime не равен lifetime DB handle: adapter не владеет DB/lease.
Готовность OS runtime не выводится из unit parser/static evidence.


### Обязательная Windows worker/UI граница

Windows root создаёт ровно один engine worker isolate на workspace в том же
процессе. Только его private entry создаёт EngineHost/platform ports/store/vault/
retained runtime identities/publication gate и owner capabilities. Root сохраняет
их там до physical drain. Native pipe/mutex workers остаются subordinate I/O
workers, не вторым domain engine/store. Flutter isolate владеет presentation,
tray/window lifetime и внутренним gateway proxy, не открывает storage/SSH и не
вызывает native bundle revalidation/hash. Future.sync не считается offload.

Порядок trusted bootstrap, UI binding, bounds/deadlines и CloseBlocked worker
protocol закреплён в [engine contract](contracts/embedded-engine.md#engine-worker-and-ui-proxy-composition).
Это обязательный prerequisite T258/T261/T265/T274/T275, не новая feature и не
внешний owner IPC. Root/controller/private gateway реализованы в engine hosting,
Windows composition и DesktopEngineHost. Их текущие bounded startup/shutdown,
publication, suspend/resume, owner retirement и fresh binding проверены static/
RAM units и независимыми component/aggregate reviews (T321, T324/T331).
Это не квалификация настоящего isolate/OS IPC/FFI/UI/runtime: native adapters,
доставка power events и release prerequisites требуют отдельной платформенной
проверки, которая в текущем разрешённом scope не выполняется.
### T323 storage dependency refinement — 2026-10-31

The actual24-tool mutation matrix requires the real StateStore, not scripted
repository responses. Apply the fixed transactional persistence port in the
[existing engine contract](contracts/embedded-engine.md#t323t369t373--transactional-storage-dependency-2026-10-31).
Production remains Isar/schema3; only test/support supplies RAM storage. Common
open/custody/semantic checks, one writer, CAS, receipts, publication and unknown
outcomes stay in StateStore. Creation, native runtime proof and protected files
retain their current responsibilities. No new feature, domain facade, runtime
mode, dependency pin or persisted entity is introduced.

Sequence: T369 design review → T370 port/Isar adapter → T371 StateStore extraction
→ T372 actual-store RAM evidence → T373 actual24-tool matrix → aggregate T323.
The applicable Constitution I–VII checks remain satisfied by one engine/writer,
private authority, unchanged target data, bounded queues, explicit contracts and
the required full checks/review loop. RAM tests do not qualify native execution
or release readiness. T324/T325/T331 and remaining final audit tasks retain their
own acceptance. Do not close an implementation task based on this plan amendment.


### T324/T331 local observation and recovery refinement — T384

Implement the existing LocalJobObservation requirement through the existing
engine and existing format3 successful-result data. The detailed normative
contract is in contracts/embedded-engine.md, section Local job observation and
recovery. No new feature, executable, transport, method, protocol version,
persistent collection or schema4. AutomationJobRecord, stable mutation ACKs,
request IDs and executor requests/responses stay unchanged.

Components: protocol automation/job_observation.dart supplies the closed public
observation DTO; engine automation/job_observations.dart owns bounded runtime
samples and opaque callback bindings; TrustedJobService/jobs.dart records only
verified current-session status and projects observations beside jobs; existing
control-services factory supplies its existing read EngineClock. Flutter's
AutomationController captures observations separately from job/outcome and the
existing jobs section displays the independent observation state. No widget or
design tests are introduced; controller/model/domain acceptance is RAM unit only.

Dependencies/order: T384 specification readiness review, then T385 runtime model
and projections, T386 terminal reconciliation fencing, T387 actual recovery and
occupancy matrix, T388 controller projection and functional display. T324/T331
remain open until aggregate checks and completed independent code review. One
writer, private authority, no permission restoration, schema3 preservation,
bounded memory, no new pins/prerequisites and no native qualification satisfy
the applicable Constitution I–VII gates. This amendment records decisions, not
implementation or readiness evidence for code.


T390 implementation refinement: automation/job_progress.dart owns the existing
TrustedJobService driver's data-only read/CAS retry loop. Production callbacks
read the same guarded snapshot and call StateStore.publishTrustedJobProgress
with expected durable sequence; no alternate writer or domain-success adapter.
The originating driver mode comes only from the private actual driver, and its
mode/phase predicate is re-evaluated on every read and CAS retry. The existing
native/session/target/root proof remains outside this metadata helper. RAM race
units use that same loop and actual StateStore with commit/read latches, not
invented tool ACKs. This refines T386 publication safety; T389 handoff readiness
and T387/T388/T324/T331 acceptance remain separately open.


### T389 control handoff refinement — T391

The existing boolean _drive refusal while a prior driver remains charged cannot
fulfil an accepted control by itself. Add automation/job_controls.dart as the
TrustedJobService-owned bounded control coordinator. It owns only serialization,
private pending tickets, deadline/timer bookkeeping and pump correlation; jobs.dart
still owns actual actor proof, store mutations and Root/SSH driver dispatch.
No new service, executable, wire, persistent entity or permission producer.

Use one workspace-local FIFO control metadata mutex, shared by cancel/reconcile
admission+registration and by activation/expiry cleanup. Do not hold it while
waiting for an old driver's physical drain or while a new driver performs root
I/O. Existing apply admission remains immediate and HOST_BUSY, never queued.
Retain at most one pending cancel and one pending reconcile per nonterminal job,
with one coalesced pump and one earliest-deadline timer per service. Components,
ordering, original30s invocation budget, scope and lifecycle are normative in
contracts/embedded-engine.md, section Accepted job control handoff.

T391 is specification readiness for T392 implementation and T393 actual RAM
handoff matrix, completing the T389 slice of T387. T386/T390 terminal/CAS gates
are retained. T387's other recovery/occupancy cases, T388 controller/display and
T324/T331 aggregate acceptance remain separate. Existing EngineClock and standard
Timer/time-scheduling adapter suffice; no new package pin, runtime prerequisite,
public setting, schema migration or compatibility path. Constitution I–VII
remain satisfied by one engine/writer, private authority, bounded resources and
explicit physical quiescence. Design readiness is not implementation evidence.


### T329 current-source plan reconciliation — 2026-10-31

Embedded implementation uses the existing exact dartssh2 4.1.0 pin, confirmed in
engine pubspec and both root/engine lockfiles. No dependency resolution or upgrade
is required by this correction. Current constitution version4.3.0 is unrelated to this pin.

Engine worker Root/controller/gateway, Windows desktop composition, same-worker
power lifecycle and current capability projection exist in the source. T321 and
T324/T331 are accepted in their static/RAM scope; T325 separately proves complete
nonempty target-schema3 retention through actual loaders and declared RAM ports.
The earlier foundation plan sections and completed task history remain historical;
the embedded change and current contracts take precedence over their locald model.
Remaining legacy cleanup T327, current user/developer docs T328 and final whole-
feature Analyze/Converge/evidence T330 remain open. Component acceptance does not
establish native/platform/build/install/release readiness or whole-goal completion.

### Direct SSH no-dispatch cancellation (T442)

Reserved direct attempt cancellation uses a typed metadata command with durable
local cancel/no dispatch, exact admission/stop/owner/plan, absence of all step
inputs and declared units/cgroups under host lock. Same boot until release; all
terminal prefixes and historical branch follow contract section8. Existing
actor/object/native matrix and10s deadline remain. No partial-reserve repair.
Writer must refuse late authorization after cancellation; no schema change.

### Direct SSH same-key trust lifecycle (T443)

Extend the existing foundation identity guard only for exact same-profile owner
trust revoke/confirm with unchanged key, endpoint/connection and credentials,
retaining all data and active format1 guards. Existing target-change coordinator
retires connections/pending control. Fresh probe/confirm and explicit connection/
reconcile recover the same attempt; no previous plan/authority is revived. Native
owner/probe/receipt and ten-second metadata limits remain unchanged. Static/RAM
positive and negative acceptance is specified in direct contract section2.

## UI-компоненты и приёмка (003.4)

[UI-раздел спецификации](spec.md) обязателен для следующих UI-задач этого пакета; [общий контракт](../003-design-system/contracts/feature-adoption.md) задаёт интеграцию. Presentation остаётся в существующих feature adapters `lib/`, переиспользует `lib/ui/deck_components.dart`, `BrandTheme` и допустимые стандартные Material controls. Catalog/demo owners не импортируются в runtime.

Для каждой композиции зафиксировать C ID/вариант, существующий owner/controller и его данные/callbacks, применимые состояния, границу identity/readiness и критерий AC-UI-001-01–03. Сохранение sort/query/selection/draft при theme/resize локально; смена цели/отзыв/утрата готовности обрабатываются действующим owner. Permission/retry/recovery/store/SSH и их лимиты остаются в сервисных контрактах, без новых UI-side owners.

Если существующего варианта недостаточно, сначала расширить каталог/контракт 003 с проверкой reuse, затем подключить его. Этим дополнением не создаются новые endpoints, схемы/миграции, зависимости или runtime actions. Новые поля передаются через действующие модели только в рамках предметных требований пакета. Текущий ограниченный validation gate сохраняется; UI/native qualification выполняется только в соответствующем разрешённом этапе, его pending-статус не означает прохождение проверки.
