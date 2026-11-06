# Tasks: Установка и обновление ServerDeck

**Input**: [spec](spec.md), [plan](plan.md), [research](research.md), [data model](data-model.md), [contracts](contracts/installation.md).
Только unit/fake/native temporary-file tests и static/build checks. Checkbox не означает автоматически всю feature acceptance.

## Phase 1: Setup

- [X] T001 Согласовать installer→installed EXE в `.specify/memory/constitution.md`, `specs/002-desktop-runtime/spec.md`, `specs/002-desktop-runtime/contracts/packaging.md`; сохранить чужие storage changes/history (FR-601).
- [X] T002 Подготовить research/design/contracts/quickstart и reviewer checklist в `specs/006-install-update/` с exact trust/limits/recovery (FR-601–617).
- [X] T003 Выполнить read-only analyze, lychee и independent design review по `specs/006-install-update/{spec,plan,tasks}.md`; исправить findings до кода; отчёт `reviews/design.md`.

## Phase 2: Foundational

- [X] T004 Реализовать bounded version/catalog/policy codecs и P256 verification в `native/include/release_catalog.h`, `native/install/release_catalog.cpp`: четыре version0..65535 no-leading-zero, metadata128KiB, releases≤32, keys≤3, hosts≤8, notes16KiB, signature64, expiry7days/skew300s (FR-606,608–609,616).
- [X] T005 [P] Реализовать metadata/journal/lease/recovery model в `native/include/installation.h`, `native/install/installation.cpp`: metadata8KiB, app/setup1GiB, Known Folders/SID/reparse, lock maintenance→owner, manifest-owned targets (FR-603–604,611–615).
- [X] T006 Добавить codec/trust fixtures в `native/tests/release_catalog_test.cpp`, file/lease/failure-injection в `native/tests/installation_test.cpp`; synthetic ports/temp files, без продукта/реальной регистрации (T004–005).
- [X] T007 Подключить library/units в `native/CMakeLists.txt`, `windows/runner/CMakeLists.txt`; `/MT` для bootstrap/setup, CTest unit label, historical integration off (FR-601).

## Phase 3: US1 — Установка (P1 / MVP)

**Independent Test**: synthetic install tree, fake registry/shortcut, no setup launch.

- [X] T008 [US1] Реализовать full setup resource, confirmation/cancel/fresh/equal/newer/older в `native/installer/main.cpp`, `native/install/installation.cpp`; offline/no admin/no portable/duplicates (AC-601–604; FR-601–604).
- [X] T009 [US1] Реализовать HKCU/Start menu adapters, fixed paths, disk candidate+backup+setup+64MiB, registration rollback/retry в `native/install/installation.cpp` (AC-603–604; SC-601).
- [X] T010 [US1] Добавить packager и resource/hash/version/size/policy units в `tools/package-installer.py`, `tools/tests/test_package_installer.py`; app/setup≤1GiB, manifest8KiB, malformed inputs fail closed (FR-601,604).
- [X] T011 [US1] Расширить `tools/build-release.ps1`, `.github/workflows/release.yml`: full setup, embedded final app, developer/publishable profiles/immutable policy, static x64/asInvoker/import audits и evidence; без publishing (FR-601; SC-601).

## Phase 4: US2 — Обнаружение и согласие (P1)

**Independent Test**: fake clock/source/storage/platform, normal/empty/trust/error states.

- [X] T012 [US2] Реализовать native update service/WinHTTP port в `native/include/update_service.h`, `native/install/update_service.cpp`: background worker, snapshot mutex/generation, policy-only network, no credentials/cookies/ID, catalog30s/no redirects, latest compatible selection (FR-605–606,608–610,616).
- [X] T013 [US2] Реализовать `updates.*` epoch/args validation и worker lifecycle в `windows/runner/platform_channel.{cpp,h}`, `lib/runtime/native_platform.dart`; без shell/path/URL interfaces (FR-605–610,616).
- [X] T014 [US2] Реализовать `lib/updates/{update_owner,update_view}.dart`: persisted24h schedule, manual bypass/disable, C14 exact consent/Позже, различимые current/error/unconfigured states (AC-605–607; SC-602; FR-617).
- [X] T015 [US2] Подключить global Обновления без selected server к `lib/runtime/{feature_runtime,runtime_view}.dart` через OwnedSettingsRoute; capability lifecycle без tray bypass/auto SSH (FR-605,611,617).
- [X] T016 [US2] Добавить native source/channel/scheduler/UI units в `native/tests/update_service_test.cpp`, `test/updates/{update_owner,update_view}_test.dart`: clock rollback/stale epoch/privacy/failures, ноль downloads без consent (AC-605–607; SC-602).

## Phase 5: US3 — Подготовка и применение (P1)

**Independent Test**: synthetic download/handoff и temporary-file transaction recovery.

- [X] T017 [US3] Реализовать consent-bound download/hash/cancel/pending в `native/install/update_service.cpp`: chunk64KiB, HTTPS443 allowlist, redirects≤3, setup1GiB, header30s/idle60s/wall30min, no resume/hidden retry, disk size+64MiB (AC-608,610; FR-607–610).
- [X] T018 [US3] Реализовать bootstrap pending/owner activation и transient setup handoff в `native/bootstrap/main.cpp`, `native/installer/main.cpp`, `native/install/installation.cpp`: HANDLE allowlist, ack3s/parent10s, continuous leases, no force kill/host-before-commit (AC-609,611; FR-611–612).
- [X] T019 [US3] Реализовать fresh signed revalidation/revoke/identity/ABI/format непосредственно до apply в `native/install/update_service.cpp`; offline/error сохраняют полную old version, consent не переносится (AC-609–612; FR-608–613).
- [X] T020 [US3] Реализовать candidate/verified backup/journal/atomic replace/recovery по hashes, ReplaceFile1175/1176/1177, registration rollback/commit-before-host в `native/install/installation.cpp` (AC-610–612; SC-603–604).
- [X] T021 [US3] Добавить synthetic handoff/process/fault-stage/cancel/late/revoke units в `native/tests/{installation,update_service}_test.cpp`; data sentinel неизменен, продукт/VM/process-kill не запускать (AC-608–612; SC-602–604).
- [X] T022 [US3] Добавить `tools/sign-update-catalog.ps1` и synthetic-key byte verification checks в `tools/tests/test_package_installer.py`; private key/path не логировать/встраивать (FR-608,616).

## Phase 6: US4 — Удаление (P2)

**Independent Test**: owned temp tree/data sentinels, fake process/registration.

- [X] T023 [US4] Реализовать retained setup uninstall/marked temp copy/deterministic target/handle handoff/partial retry в `native/installer/main.cpp`, `native/install/installation.cpp`; owner-running→tray instruction, no data deletion/foreign files/self-delete promise (AC-613–615; FR-614–615).
- [X] T024 [US4] Добавить uninstall/reinstall/active-owner/partial/reparse/SID/foreign-files/MCP path units в `native/tests/installation_test.cpp`; тот же data root без migration/reset (AC-613–615; SC-605).

## Phase 7: Verification and convergence

- [X] T025 Выполнить checks из `specs/006-install-update/quickstart.md`: format/analyze/flutter test/boundaries/Python/native units/full setup build+static audits/lychee; evidence `reviews/verification.md`.
- [X] T026 После checks провести independent implementation review по AGENTS без истории; confirmed fixes новыми append-only tasks, rerun checks/fresh review до чистого результата; отчёт `reviews/implementation.md`.
- [X] T027 Выполнить speckit-converge по actual code/spec/plan/tasks после implementation; remaining work append-only, clean result не меняет history; FR/AC/SC completion audit в `reviews/completion.md`.

## Dependencies and strategy

T001–003 до кода; T004||T005, затем T006/007. US1 после foundation; US2 независимо
от рабочего installer через fake port; US3 после US1+US2; US4 использует US1 ports,
не зависит от сети. Примеры параллельности разных файлов: T004||T005; T010 после
resource contract параллельно T009; Dart T014 после T013 независимо от WinHTTP T012.
MVP — US1, но цель включает все4 story и Phase7. Completed history сохраняется;
review fixes/convergence только append. Task counts: setup3, foundation4, US1=4,
US2=5, US3=6, US4=2, final3; total27.

## Phase 8: Design review closure (before implementation)

- [X] T028 Закрыть R1 в `native/install/installation.cpp`, `native/bootstrap/main.cpp`, `native/tests/{installation,update_service}_test.cpp`: durable pending consumption/tombstone до host, target≤installed и manual supersede, interrupted commit/recovery, identity-bound cleanup после helper exit, deferOnce без offline retry loop; критерии T018–021 дополняются, история сохраняется (FR-612, AC-609–611; SC-603).
- [X] T029 Закрыть R2 в `native/include/update_service.h`, `windows/runner/platform_channel.cpp`, `lib/updates/{update_owner,update_view}.dart`, `test/updates/{update_owner,update_view}_test.dart`: обязательные signed publishedUTC/setupSize/platform/ABI/storeFormat/compatibility у offer, `total?` только download length; добавить data/text assertions к T013/014/016 (FR-606,617; AC-605).

T028/T029 выполняются вместе с соответствующими T018–021/T013–016, до final Phase7.
Они добавлены по independent design review; первые27 задач не удалены/не перенумерованы.

- [X] T030 Закрыть fresh-review R1 в `native/install/installation.cpp`, `native/installer/main.cpp`, `native/tests/installation_test.cpp`: independent recovery image+SID/hash metadata+Start menu repair action до destructive replacement, immutable during transaction, --repair recovery до marker/version compare; synthetic canonical-missing/journal+backup scenario и refresh-interruption case, no host/DB before recovered full files (FR-612; AC-610; SC-603). Выполнить вместе с T008–009/T020–021/T023–024, до final checks.

- [X] T031 Закрыть review R1 про manual check в `lib/updates/update_owner.dart`, `native/install/update_service.cpp`, `test/updates/update_owner_test.dart`: при enabled=false выполнить manual check независимо от24h, не менять enabled и не ставить background timer; дополнить T014/T016 этой проверкой (FR-605; AC-607).

- [X] T032 Закрыть catalog-code review R1 в `native/install/release_catalog.cpp`, `native/tests/release_catalog_test.cpp`: отвергать Windows-compatible IPv4 aliases (включая 0x7f.0.0.1) в policy/URL без DNS-запросов; rerun native units и fresh independent review (FR-608,616).

- [X] T033 Закрыть install-foundation review R1 в `native/install/installation.cpp`, `native/tests/installation_test.cpp`, `contracts/installation.md`: bounded fixed staging slot с SID/target/size owner marker и exclusive lease, reclaim known interrupted writes/retry/uninstall; unknown/foreign/reparse отказ без удаления, no wildcard tmp cleanup; rerun native units/lychee и fresh independent review (FR-604,612,614).

- [X] T034 Закрыть fresh foundation review R1 в `native/install/installation.cpp`, `native/tests/installation_test.cpp`: oversized owner/payload и reparse staging → точный RECOVERY_REQUIRED без изменения файлов, реальная access/read ошибка остаётся STORAGE_IO; rerun native units и fresh independent review (FR-604,612,614).

- [X] T035 Закрыть slot-lock review R1 в `native/install/installation.cpp`, `native/tests/installation_test.cpp`: reparse `.stage.lock` отклоняется с RECOVERY_REQUIRED до Acquire и при cleanup/write; synthetic junction/no-deletion fixture, rerun checks/fresh review (FR-604,612,614).

- [X] T036 Закрыть packager review R1 в `tools/package-installer.py`, `tools/tests/test_package_installer.py`: полностью цифровые dotted hosts (в том числе invalid IPv4 вроде999.999) отвергаются в endpoint/downloadHosts, как в native validator; rerun Python units/fresh independent review (FR-608,616).

- [X] T037 Закрыть executor review R1 в `native/install/install_executor.cpp`, `native/installer/main.cpp`, `native/tests/install_executor_test.cpp`: явный repair проверенной установленной записи журналирует регистрацию, переживает частично записанный основной ярлык и повтор; не применяет старую embedded recovery version (FR-612; AC-610).

- [X] T038 Закрыть executor review R2 в `native/install/install_executor.cpp`, `native/tests/install_executor_test.cpp`: равная версия с другой app/setup identity → SOURCE_CHANGED до recovery/registration mutations; fixtures обоих конфликтов (FR-608; AC-604).

- [X] T039 Закрыть fresh executor review R1: explicit repair проверяет recovery SID/full hash/embedded resources до журнала регистрации, missing/corrupt assets → явный отказ, без ложного успеха; допускается целый предыдущий recovery setup без изменения работающего image. Native fixtures и fresh independent review (FR-612; AC-610).

- [X] T040 Закрыть signer review R1 в `tools/sign-update-catalog.ps1`, `tools/tests/test_sign_update_catalog.py`: case-sensitive абсолютные границы keyId, uppercase/terminal LF/length/charset → отказ без изменения каталога; rerun units/fresh review (FR-608,616).

- [X] T041 Закрыть final signer review R1: payload допускает общий предел131072, итоговый envelope проверяется отдельно; допустимый near-limit catalog подписывается, envelope overflow сохраняет существующий output; rerun units/lychee/fresh independent review (FR-608,616).

- [X] T042 Закрыть update-service review R1: несовместимый каталог с состоянием failed/RELEASE_INCOMPATIBLE сохраняет предыдущий lastSuccess в памяти и preferences; unit с различающимися T1/T2, rerun checks/fresh review (FR-605–606).

- [X] T043 Закрыть owner review R1: cancel/setEnabled(false) не теряются при задержанном command-refresh; сериализовать admission отдельно от snapshot ожидания, tests manual cancel/automatic disable и stale-reply fence; rerun Flutter gates/lychee/fresh review (FR-605,610).

- [X] T044 Закрыть fresh owner review R1: подтверждённый enabled/defer немедленно меняет scheduling authority, отменяет старый timer и fences pre-ack reads; delayed-refresh timer regression без нового background check, manual check сохраняется; rerun Flutter gates/lychee/fresh review (FR-605,607).

- [X] T045 Закрыть найденную при подключении UI гонку: accepted check сразу убирает прежний offer до delayed refresh; accepted download/cancel сразу меняют локальную фазу с read fence. Queued download старого offer после check ack не передаётся native; stale-dialog consent отбрасывается. Unit/widget regressions и mandatory review (FR-607–610; AC-606,608).

- [X] T046 Закрыть UI review R1: accepted check сразу сохраняет локальный lastAttempt, чтобы cancel до delayed snapshot не создавал automatic retry с нулевым интервалом; enabled=true, null/due previous attempt regressions (FR-605).

- [X] T047 Закрыть UI review R2: false check admission не проецирует checking; delayed/error snapshot unit сохраняет неактивную фазу и известную причину unconfigured (FR-605–606).

- [X] T048 Закрыть выявленную при разборе очереди consent гонку: UpdateOwner принимает confirmed offer projection и сверяет её identity внутри queued admission; одноимённая версия с обновлёнными данными не наследует старое UI согласие. Blocking setting + refreshed offer regression (FR-607–609).

- [X] T049 Подготовить streaming transport для T017 в `native/include/artifact_transfer.h`, `native/install/{artifact_transfer,update_service}.cpp`, `native/tests/artifact_transfer_test.cpp`: exact size/SHA256, chunk64KiB, allowlisted HTTPS redirects≤3 (включая relative), header30s/idle60s/wall30min, cancel и bounded observed progress; native units/host build/independent review. Готовность pending/store/service wiring по-прежнему T017, T049 её не заменяет.

- [X] T050 Реализовать atomic pending store в `native/include/pending_update.h`, `native/install/pending_update.cpp`, `native/tests/pending_update_test.cpp` и Files adapter: два bounded slot0/1, SDPENDING001 pointer/owner codec, original catalog reconstruction, separate download stage, maintenance-protected read/publish/reclaim. Interruption/cancel/replacement preserves previous ready slot; only pointer switch grants ready. Проверить design amendment, unit/build/links и independent review; supplements T017/T028 без стирания истории.

- [X] T051 Закрыть pending-store review R1: Apply/Repair проверяют обе staging-области до новых мутаций; invalid download owner/unowned payload → RECOVERY_REQUIRED с сохранением прежних canonical/metadata/proof/registration, без нового journal и без удаления неизвестных bytes. Native fixtures, rerun checks/fresh review (FR-604,612).

- [X] T052 Подключить PendingPersistence/ArtifactTransport к UpdateService: async restore, exact-consent download, progress/verifying, mutex-arbitrated cancel/ready commit, retained preparedVersion/preparedCode при новых проверках/замене, no hidden retry; known same-version/changed-byte refusal и nonblocking TryDrain. Synthetic service ports, mandatory checks/fresh review. Полный channel/runtime/UI mapping остаётся T013/T015/T029; supplements T017.

- [X] T053 Закрыть download-service review R1: durable consent rename сообщает publication до fallible marker cleanup, committed/ready фиксируются под тем же mutex до выхода callback, write-then-throw не даёт ложный CANCELLED или зависший verifying. Native file/store fault и service concurrent-cancel units; rerun checks/fresh review (FR-607–612).

- [X] T054 Закрыть fresh download-service review R1: Dart cancel ack не означает CANCELLED; при native already-ready/no-op cancel UI сохраняет фазу до authoritative snapshot. Delayed/error read unit/widget regressions, mandatory Flutter checks/lychee/fresh review (FR-610–612).

## GitHub Releases amendment — сохраняет выполненную legacy историю

- [X] T055 Реализовать protocol2 static signed catalog в native codec/pending и signer tools по [GitHub contract](contracts/github-releases.md); legacy1 units сохраняются. Production source допускает только2; отсутствие релизов >7days не ломает restore/check. Unit fixtures/signing tests, applicable checks/review (FR-618; AC-616).
- [X] T056 Реализовать GitHubReleaseSource/HTTP port в native/include/github_releases.h, native/install/github_releases.cpp: latest/tag API, bounded JSON/assets, digest/size/signature, canonical repo/tag URLs, shared30s deadline, redirect/cancel/HTTP errors; подключить default source в update_service/runtime. FetchFor проверяет exact old consent через fresh target API. Synthetic units для всей цепочки нормальных/ошибочных/граничных случаев; checks/review (FR-608–610,616,618; AC-616).
- [X] T057 Обновить publishable policy validation/packager/build guide на GitHub-only endpoint/hosts и выпуск setup+protocol2 catalog/body/changelog в одном GitHub Release. Без публикации/real network tests; fixtures неверного источника/asset set и regression units. Lychee, mandatory checks, fresh independent review и converge (FR-618; AC-616).

- [X] T058 Закрыть GitHub adapter review R1: абсолютный catalog cap128KiB отделить от API expected size; большая/меньшая bounded замена → SOURCE_CHANGED, overflow cap → INVALID_CATALOG. Synthetic replacement fixtures, rerun native/host/links и fresh independent review (FR-608,618; AC-616).

- [X] T059 Подготовить startup boundary T018: Executor::PrepareStartup восстанавливает journal и проверяет staging/canonical app+setup/commit/resources до GUI owner publication; AcquireOwnerFromLease переносит уже удерживаемый owner HANDLE без gap, activation-only путь не приобретает новую authority. Synthetic interrupted-state/damage/lease transfer units, native/build/links и независимое review. Это foundation, не завершение bootstrap pending/process handoff T018–021/T028 (FR-611–613; AC-609–612).

- [X] T060 Реализовать typed maintenance handoff adapters в native/include/maintenance_handoff.h и native/install/maintenance_handoff.cpp, Lease::Adopt: exact4 HANDLE argv, File/type/access/path/exclusive proof, parent identity/ancestry, Event readiness, explicit inheritance list и ограниченные ожидания без kill. Synthetic launch/wait ports и kernel-object unit fixtures, build/links/fresh review; entry point wiring/pending consumption остаются T018–021/T028 (FR-611–613; AC-609–612).

- [X] T061 Закрыть handoff review R1: доказывать запрет READ/WRITE/DELETE sharing раздельными ReOpenFile-пробами exact file object; не принимать partial-share HANDLE по combined RW denial. Все7 nonzero share masks и AcceptTransfer/unsignaled-ack regression, rerun native/build/links и fresh independent review (FR-611–613; AC-611).

- [X] T062 Реализовать pending lifecycle adapters в native/install/pending_lifecycle.cpp, PendingStore и UpdateService: bounded retirement/defer codecs, target≤installed reconciliation, durable tombstone before detach, identity-bound delayed cleanup, invocation latch before consumed write, startup failure notice with retained prepared version. Synthetic interruption/locked-file/replacement/SID/codec/notice units, native/build/links/fresh review. Bootstrap/helper invocation остаётся T018/T028 (FR-612; AC-609–612).

- [X] T063 Подключить native/bootstrap/main.cpp и native/installer/main.cpp к startup_update/build_identity: canonical preflight before owner/host, fixed GUI path, mapped build version resource/audit/relaunch, selected pending handoff, fresh apply, deferOnce fallback, durable consumption/retirement и cache-failure isolation. Synthetic flow units (including registered/committed interruption), Python build-resource fixtures, full build/checks/fresh review; закрывает wiring T018/T019/T021/T028 (FR-608–613; AC-609–612).

- [X] T064 Закрыть найденную при wiring late-ACK гонку: пятый read-only parent-permit Event, no modify/DACL rights или alias с ready; child ждёт разрешение до parent exit и не применяет после timeout/fallback parent. Точные5 HANDLE argv, late-ready/no-permit/parent-died/unit rights regressions, checks/fresh independent review; supersedes four-handle prototype T060 without erasing history (FR-611–612; AC-611).

- [X] T065 Читать build identity/trust resources установленного файла через физический read-only mapping и bounded PE/resource parser, без loader cache/исполнения imports. Проверить реальный ресурс unit executable и синтетические malformed headers/tree/RVA/limits; build/native/links/fresh review. После recovery заменённый canonical файл должен проверяться независимо от уже отображённого старого процесса (FR-611–612; AC-610–612).

- [X] T066 Закрыть startup review R1: ошибка записи/consumption deferral после failed parent handoff не блокирует проверенный старый GUI; invocation latch предотвращает повтор helper даже при cache IO. Helper сохраняет durable-defer-before-relaunch правило. Synthetic locked defer file и write-then-throw checkpoint, rerun native/build/links и fresh independent review (FR-611–612; AC-611).


- [X] T067 Завершить T023/T024: SDREMOVE001 ticket связывает marked temp helper с исходным commit hash и UUID removal journal; initial retained setup → five-handle handoff с фиксированным parent identity; explicit retry использует только Known Folder cache без target argv. Partial сохраняет регистрацию retry до удаления owned элементов; прежний ticket не удаляет одинаковую переустановку с новым commit proof. Native/cache/registration units, build/links/fresh review (FR-614–615; AC-613–615).

- [X] T068 Закрыть uninstall review R1: полный installer/--repair распознаёт оставшийся remove journal даже после удаления Windows registration, проверяет exact UUID cache/target/SID/physical setup hash/resources и запускает fixed marked retry после release leases. Synthetic interruption сразу после successful registration.Remove, ordinary resolver→resume→reinstall; native/build/links/fresh review (FR-614; AC-615).

## Phase 9: Convergence

- [X] T069 Показать статус повторной проверки/применения/восстановления в transient update helper до Flutter/DB; typed reporter в startup_update, bounded native status presentation без business owner/quit/restart callback. Synthetic reporter sequence success/offline/failure, static setup resource/import build, links и fresh review по FR-610 (partial, HIGH; convergence F1).

## Phase 10: Installer adapter corrections

- [X] T070 Исправить HKCU string read в native/install/install_registration.cpp: учитывать фактический UTF-16 byte count второго RegGetValueW; synthetic read seam/fixtures в native/include/install_registration.h и native/tests/install_executor_test.cpp покрывают oversized probe и malformed/grown/error results (FR-603/604; AC-603/604).
- [X] T071 Исправить принятие inherited lease в native/install/maintenance_handoff.cpp: сравнить fixed expected lock с HANDLE по volume/file ID при Windows packaged LocalCache redirection, сохранив reparse/rights/zero-size/exclusive-sharing/parent/permit проверки; synthetic hard-link alias и existing negative cases в native/tests/maintenance_handoff_test.cpp (FR-611/614; AC-611/613).
- [X] T072 Выполнить native unit/build/link checks и independent read-only review исправлений адаптеров, устранить подтверждённые findings; evidence в reviews/installer-adapters.md. Пользовательская локальная диагностика не заменяет unit gate и не вводит integration/e2e gates.

## Phase 12: Enable shipped GitHub updates

- [X] T073 Закрепить постоянную public GitHub policy/реальный P256 root; private key вне repo с user/SYSTEM ACL, init переиспользует ключ и запрещает silent rotation/missing-key replacement; synthetic bootstrap/key-scope tests (FR-608/616/618/619).
- [X] T074 Сделать publishable стандартным профилем build-release и workflow, developer только explicit; включить public policy в app/setup, поднять build0.1.0+2 для установки поверх unconfigured0.1.0+1 (FR-601/607/618/619; AC-617).
- [X] T075 Подготовить audited payload/signing command: exact final setup/app/policy identity, matching signing key, UTF8 notes, verified previous catalog/immutable records/version increase/bounds; сформировать локальные setup+signed catalog без private upload/publication (FR-608/618/619; AC-617).
- [X] T076 Выполнить Python/native/Flutter/build/resource/link checks и independent review/fixloop поставки, проверить фактический publishable artifact с enabled GitHub policy; обновить evidence и завершение amendment (AC-617).
