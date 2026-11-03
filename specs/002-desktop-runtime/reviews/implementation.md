# Current acceptance policy — 2026-11-03

Пользователь подтвердил только юнит-тесты; прежние integration/VM gates отменены,
не объявлены passed. Прежние записи ниже — неизменная история, их выводы о pending VM
не определяют текущую готовность. Актуальный итог: [unit-only-final](unit-only-final.md), T040–T042 закрыты.
Product requirements сохраняются; unit/static checks не доказывают actual integration.

---

# Implementation evidence — 2026-11-03

## Состояние

Работа продолжается. Пакет прошёл независимое read-only ревью перед реализацией:
замечаний не найдено, готовность к началу реализации подтверждена. Это не release approval.
Constitution/spec/plan/tasks уже существовали; контекст Spec Kit переключён на 002.
Чек-лист требований: 12/12 checked. Анализ traceability: 14 FR, 19 задач, все FR
имеют задачи (таблица tasks.md); подтверждённых продуктовых вопросов до начала кода нет.

Реализованы root composition, Isar format1, owner/write leases, coordinator,
Win32 host/platform/tray, bootstrap/singleton/payload, локальная сборка single EXE.
Задачи с отсутствующими проверками и release gates остаются открытыми.
Ни один GUI/clean-VM сценарий пока не объявляется пройденным.

## Фактически выполненные проверки

| Команда | Результат / scope |
| --- | --- |
| flutter --version | Flutter3.47.7, Dart3.13.5 |
| flutter pub get --enforce-lockfile | exit0, зафиксированные Isar3.4.1/build_runner2.16.2 |
| tools/generate-models.ps1 | exit0; повторная генерация не изменила SHA256 records.g.dart; JIT, предупреждение об игнорировании устаревшего delete-conflicting-outputs |
| tools/test-unit.ps1 | exit0: boundary (7 Dart files), dart format --output=none --set-exit-if-changed ., flutter analyze (0 issues), flutter test (20 tests) |
| tools/test-design-components.ps1 | exit0:112 passed,1 opt-in capture skipped; только компоненты001, включая synthetic C17 owner inputs |
| tools/build-release.ps1 | exit0: host DLL + /MT bootstrap, manifest, app-local CRT, PE import/delay-import audit |
| tools/test-release.ps1 | exit0: native CTest3/3; 5 stateless EXE/payload probes, включая corruption quarantine; не GUI/VM приёмка |
| lychee "specs/**/*.md" | exit0:128 total,122 OK,6 excluded,0 errors |

Проверенный EXE перед первым ревью реализации: SHA256
`864f4670a63b709625fa8e770bdef0ca303782ebc830b7f560f690f3001b58de`.
Сборка и подробные локальные результаты находятся в ignored output/release-evidence;
они относятся к этому digest и не являются опубликованным релизом.

## Ограничения / остаток

- Чистые offline Windows10/11 VM, настоящий GUI lifecycle/Explorer/OS ending,
  readonly EXE, disk-full/denied ACL и crash/recovery сценарии ещё не выполнялись.
- Get-VM отказал текущей учётной записи в доступе к Hyper-V. Пользователю отправлен
  запрос на доступную disposable VM; реальная пользовательская база не использовалась.
- CI workflow добавлен, но удалённый CI run не запускался.
- Независимое ревью реализации завершено после исправлений; converge выявил остаток.
  Полная приёмка T019 остаётся открытой из-за GUI/VM gates.
- Расширение C17 оформлено отдельной R012 в scope001; компонентные проверки и
  завершённое чистое независимое ревью подтверждены ниже, R012 закрыта.

Результаты нельзя переносить на другой EXE без повторной сборки/проверки.

## Первый implementation review и исправления

Завершённое read-only ревью нашло три замечания: P1 first-publication retry,
P1 short-circuit shutdown остальных capabilities, P2 stock tray icon вместо001.
Пакет признан готовым к реализации; реализация/VM gates не признаны завершёнными.
Исправления записаны отдельными T020–T022, без удаления выполненной истории задач.

- Pending initial publication сохраняет identity внутри живого owner; retry
  продолжает staging/destination, orphan guard для посторонних каталогов сохранён.
  Проверены failure до rename, после rename, после CURRENT до ack и чужой orphan.
- stop/cancel/close/drain/dispose запускаются у всех независимых capabilities;
  ошибочные/неоконченные стадии сохраняются для retry. Проверены два synthetic
  owners, отказ каждой стадии и timeout без повторения уже успешных стадий.
- `app_icon.ico` содержит исходный PNG `assets/brand/logos/mark-dark.png` без
  изменения изображения, в ICO container. Native tray загружает ресурс host DLL.
  Release probe сравнивает bytes RT_ICON фактической упакованной DLL с asset001.

Проверки после исправлений:

| Команда | Фактический результат |
| --- | --- |
| tools/test-unit.ps1 | exit0: boundary11files, format0changes, analyze0issues, flutter test39passed |
| flutter test test/storage/crash_recovery_test.dart test/runtime/runtime_view_test.dart | exit0:4passed; kill отдельного Isar writer после commit/внутри txn и functional retry actions |
| tools/build-release.ps1 | exit0, host/bootstrap/import audits |
| tools/test-release.ps1 | exit0, CTest3/3,6localprobes, включая native brand icon resource |
| lychee "specs/**/*.md" | exit0,128total122OK6excluded0errors после contract updates |

Проверенный после исправлений EXE SHA256:
`02adac5065da0029754c56683ab4a448936043632807569cbf525c92291491c6`.
Clean offline VM по-прежнему не выполнена. Повторное независимое ревью запрашивается
после проверок; этот текст сам по себе не означает чистого результата review loop.

## Второй implementation review и T023

Read-only reviewer подтвердил закрытие T020–T022 и нашёл P2: ненулевой return host
до появления UI обходил native startup retry/cancel. T023 закрепляет ABI return codes:
до message pump — native startup error после освобождения host/owner, после pump —
диагностика без restart engine. Native ABI test вызывает synthetic failing host и
различает startup/runtime/unknown outcomes. Полный GUI failure scenario не заявлен.

После T023: tools/test-unit.ps1 exit0 (format/analyze/boundary11files/39functional),
build-release exit0, test-release exit0 (CTest3/3 +6localprobes), lychee exit0
(128total122OK6excluded0errors). Проверенный EXE SHA256
`0ef80d4227c17ef85615193593527604207f8834070e7c6f3267f05f7bb2b034`.

## Convergence pass

Проверены 14 FR,10 AC,6 SC,6 sequencing decisions Plan и5 принципов конституции.
Результат `tasks_appended`: три HIGH partial gaps — native boundary/ACL/event coverage,
full GUI/failure smoke runner и actual clean offline VM/evidence/final review.
Они добавлены append-only как T024–T026 в Phase8; прежняя история сохранена.
Результат НЕ `converged`. Mandatory hooks отсутствуют (.specify/extensions.yml нет).

## Третий implementation review и native lifetime/coverage pass

Read-only reviewer нашёл два P2: обратный порядок platform/engine destruction при
abnormal host return и отсутствие rollback частичного PlatformChannel constructor.
T027/T028 исправляют эти сценарии. RuntimeOwners гарантирует release borrowed
platform callbacks до engine при normal/partial/fault unwind. Native synthetic pump
failure test проверяет эту production ownership abstraction без запуска GUI.
Event handles стали RAII, thread creation и callback/tray registration имеют rollback;
fault fixture отказывает на каждом из трёх CreateEvent и при worker startup.
Внутренние C++ exceptions включены; RunMain не пропускает их через ABI.

T024/T017 дополнены: malformed structured manifest (bounds/offset/overflow/case
alias/UTF8/file limit/hash/future format), ACL/atomic failure/junction rejection,
native encoded epoch/events/buffer/snapshot/exit latch, DPAPI round-trip/wrong-purpose,
duplicate/gapped Dart events. Native fault tests работают с synthetic inputs и
borrowed fake messenger, не с пользовательскими данными и не с layout экрана.

Self-audit T029: root ACL не заменяет protected explicit child DACL восстановленного
файла. SecureTree под owner lock закрепляет policy для descendants; owner.lock —
через его открытый HANDLE. Fixture с Everyone-write child ACL проверена реально.
T030 даёт понятную native причину вместо внутренних identifiers. T031 сохраняет
native hide/minimize при first-frame callback и coalesces одинаковые startup events.

Последние фактические результаты: tools/test-unit.ps1 exit0 (format0changes,
analyze0issues,40functional,boundary11files); build-release exit0; test-release exit0
(bootstrap/security/lifetime CTest5/5 + native platform CTest1/1 +6localEXEprobes);
lychee exit0 (128total122OK6excluded0errors). Ошибка компиляции native test и слишком
широкий HANDLE count assertion после process-wide DPAPI caches были исправлены до
этого успешного запуска; результаты старых binaries не использованы как новый pass.

Проверенный EXE SHA256:
`96d900a30858ab4c3592dafd85db2fd2d6175dab436e306b5d14fab8507ea03f`.
Остаются full GUI/fault VM runner и actual clean offline VM acceptance (T018/T019,
T025/T026); native/unit evidence их не заменяет. Новое fresh independent review
после этого pass ещё необходимо; завершение реализации/выпуска не заявлено.

## Завершённый четвёртый independent review

Read-only reviewer: «Замечаний не найдено»; «Готовность к реализации: готов» для
продолжения remaining tasks. Проверены governance, пакет002/контракты/traceability,
C17/R012, все актуальные Dart/native/platform/build/probe/test artifacts. Закрытие
T020–T023/T027–T031 подтверждено исходниками; новых обязательных продуктовых или
архитектурных пробелов не установлено. Reviewer не запускал проверки повторно,
учёл переданное фактическое evidence; это статическое независимое ревью.

Текущий остаток: T018/T019/T025/T026 — полный GUI/fault runner, настоящая clean
offline Windows10/11 VM приёмка и окончательная верификация. Native/unit code pass
не означает завершённость релиза. Контекст Spec Kit и цель002 остаются активными.
Hyper-V недоступен текущей учётной записи; доступный disposable VM target запрошен
у пользователя и пока не предоставлен. Никакие GUI/VM gates не помечены passed.

## Продолжение: переносимые fixtures и локальная установка

T032: platform fixture перенесён в общий `/MT` native graph. Из pinned Flutter
wrapper собраны codec/reply implementations с function/data section elimination;
PE audit фактического helper не содержит engine/Flutter/VC DLL imports. Все шесть
native fixtures теперь запускаются из отдельной копии verification kit без DLL
рядом. Product distribution остаётся одним EXE, verification kit — developer artifact.

`tools/build-vm-test-kit.ps1` успешно выполнил build-release/test-release и создал
SHA-bound kit. Копированный run-native выполнил 6/6 fixtures, exit0; explicit
RequireCleanVm на текущем physical development host вернул exit2 до fixture запуска.
В отчётах `fullVmAcceptance=false`; GUI/VM acceptance не подменена этим запуском.
tools/test-unit.ps1: exit0,format0changes,analyze0issues,40functional,boundary11files.
lychee после добавления VM guide: exit0,130total124OK6excluded0errors.
Новый candidate SHA256 `9304501e9d35d9203ab5b5a1a1d4223e3c8d7992f3477d9896a910a669ecc18d`;
kit manifest SHA256 `eb04daaba2e3d23ce6cbdbe0ee0dba3ecdba5e9a31a3b764096b38d31494f38b`.

Пользователь отдельно попросил установить ServerDeck на текущем компьютере.
Проверенный на тот момент EXE SHA256
`6710d6623646b5b1a2326094717c45827237a31dab4249a17752301997e78e90`
скопирован в `%LOCALAPPDATA%/Programs/ServerDeck/ServerDeck.exe`, проверен после
копирования, добавлен пользовательский Start Menu shortcut. Установленный EXE
запущен; accessibility tree реального окна содержит «Приложение готово» и «Данные
открыты». Это warm local host observation, не clean offline VM evidence. Последующие
dev rebuilds не заменяли пользовательскую установленную копию.

T032 завершила отдельное read-only independent review: «Замечаний не найдено»;
пакет готов к продолжению реализации remaining tasks. Reviewer прочитал новые
build/runner/spec artifacts и реальное local/negative-preflight evidence, отдельно
сверил candidate/kit manifest SHA256; повторно тесты не запускал. T032 закрыта.
T018/T019/T025/T026 остаются открытыми; clean offline VM/GUI/CI не проверены.

## T033 — исправление кодировки native меню

Пользователь обнаружил mojibake в пунктах трея установленной копии. UTF-8 C++
wide literals ранее читались через MSVC system ACP. Для host/bootstrap/fixtures
закреплён `/utf-8`, для generated payload RC — `code_page(65001)`. Menu labels
вынесены в `runtime_text.h`; static_assert сравнивает их с universal escapes,
release probe проверяет UTF-16 code points в фактически вложенной host DLL.

2026-11-03: tools/test-unit.ps1 exit0 (format48files0changes, analyze0issues,
40functional tests, boundary11files). build-release exit0; финальный test-release
exit0: CTest6/6 и EXE probes7/7. lychee exit0:130total124OK6excluded0errors.
При первом запуске probes output EXE был нечитаемым для loader (WinError1392,
нулевые bytes в PE header; SHA1468c62c7a36734f28bd692516d1ecb1f58ec452e336e1567367e6b95795eb38).
Повреждённая копия сохранена в output/release-evidence/ServerDeck-before-file-refresh.exe.
Свежая копия фактического bootstrap build прошла все probes; причина повреждения
первой output copy не установлена. Финальный SHA256 продукта и установленной копии:
`bb7a3164912b6516bad9d101a9d0bbb56a55528d44a8c80a8569db05c7cabd7b`.

Независимый read-only reviewer review_utf8_002: замечаний не найдено, T033 готова
в пределах её scope; сверены артефакты, generated compile options, saved results
и финальный SHA, без повторного запуска тестов. После review установленный EXE
заменён при отсутствии процесса, прежняя копия сохранена отдельно. Новый EXE
запущен, accessibility реального окна: «Приложение готово», «Данные открыты».
Пользователь непосредственно проверил меню и подтвердил: оба пункта «Открыть»
и «Выход» читаются правильно. Это functional text observation локальной установки,
не design acceptance и не clean offline VM acceptance. T033 завершена.
T018/T019/T025/T026 остаются открытыми, цель002 не завершена.

## T034 — read-only процессное evidence для VM smoke

Добавлены `/MT` release_observer.exe и hash-bound capture-process.ps1. Helper
проверяет actual process image/current-user SID/живой HANDLE, собирает session,
PID+creation FILETIME, module paths и top-level HWND class/visible/minimized.
Он не отправляет input, не открывает Isar и не завершает продукт. Capture timeout15s
завершает только дочерний helper. Evidence содержит UTC interval и hashes, не
перезаписывает прошлый capture и всегда сохраняет fullVmAcceptance=false.
Snapshot последовательный, не атомарный; сам по себе не доказывает GUI/DB/tray readiness.

Native CTest7/7 (новый observer --self-test), actual EXE probes7/7, OS-only import
closure audit всех7 helpers — exit0. Synthetic transport checks: PS7 и Windows
PowerShell5 exit0 (identity/JSON, immutable output, default evidence outside kit,
invalid PID и helper checksum mismatch). Полный build-vm-test-kit прошёл; продукт
SHA256 `69192cfaf3f1e934af214b41ed6852d1b8c3c58b4f39c70c7a09921adcfdc925`.
Финальный manifest SHA256
`639c44d0785cdf706e0b53ff98c242edeb2d48a097ee4fae064acbe3ffd87ef6`.

Независимый review_observer_002 обнаружил конфликт default capture reports и
повторной упаковки того же hash-directory. Исправлено: default capture evidence
пишется в соседний <kit>-evidence, guard неожиданных файлов kit не ослаблен.
Следующий fresh reviewer review_observer_002_2 выявил PS5 default run-native Path
binding failure и mismatch sidecar build identities при reuse старого EXE после
неуспешной новой сборки. Defaults перенесены в script body; build-identities набора
теперь извлекаются из actual embedded manifest через SHA-bound release probe.

Проверены реальные regressions: WindowsPowerShell5 документированный default
run-native exit0,7fixtures; default RequireCleanVm exit2,zero fixtures,report written.
Token account identity не зависит от spoofed USERNAME. test-vm-kit-reuse.ps1 exit0:
сгенерирован default invalid-PID capture без запуска продукта, development sidecar
временно заменён заведомо чужими identities, тот же candidate перепакован с верными
embedded identities, prior capture hash сохранён, sidecar восстановлен byte-for-byte.
Отчёты output/release-evidence/{reuse-integration.json,observer-native-ps5-default-pass.json,
observer-native-ps5-default-blocked.json}; build/reuse logs в output/. Последний
lychee: exit0,130total124OK6excluded0errors. Flutter source в T034 не менялся.

Fresh read-only reviewer review_observer_002_3: замечаний не найдено; scope T034
готов. Reviewer прочитал артефакты и реальные отчёты, отдельно сверил19 manifest
entries,zero hash mismatches,source/copy scripts и сохранённый capture hash;
не запускал suites/GUI повторно. T034 завершена как partial preparation T025.
Ранее read-only helper снял факты с установленного старого EXE PID28268 (один PID
с host/Flutter/Isar DLL, hidden main HWND). Это не acceptance нового candidate;
установленный EXE не заменялся данным rebuild. Clean offline VM пока недоступна:
Get-VM вновь вернул authorization denied текущей учётной записи на physical MSI.
T018/T019/T025/T026 и общая цель002 остаются открытыми.

## T035 — подготовлен real EXE lifecycle driver

В VM kit добавлены `/MT` release_lifecycle.exe и run-lifecycle.ps1. Девять сценариев:
readonly EXE directory с DACL/реальным отказом записи; visible cold ready через UIA,
CURRENT/owner lock и host/Flutter/Isar modules в original PID; WM_CLOSE сохраняет
owner/store; native popup Open; SC_CLOSE/double-click callback; overlapping
concurrent duplicates; minimize/Open; tray Exit с release descriptor/lock; warm
reopen с тем же CURRENT. Это подготовленный integration driver, не выполненная
положительная GUI приёмка. Callback/system-command injection не доказывает физические
жесты или Explorer/OS recovery, txn durability и draft/synthetic capability state.

Перед product launch wrapper выполняет свежий strict clean VM preflight. Native
дополнительно требует token ServerDeckSmoke account, non-elevated unlocked Default
desktop и отсутствующий профиль из read-only Known Folder query. Нет PID attach
к пользовательскому установленному EXE, environment-redirect LocalAppData, reset или
удаления профиля. Собственные children назначаются kill-on-close job до resume;
ошибка/timeout не может быть graceful Exit pass. Driver watchdog180s; fullVmAcceptance
всегда false. CI добавлен только negative development entry check, не VM pass.

Реальные проверки: test-vm-kit-reuse.ps1 exit0 — native CTest8/8, EXE probes7/7,
OS-only import audit8helpers, observer transport/reuse provenance и сохранность
предыдущего capture. test-lifecycle-entry.ps1 exit0 — direct native guard отверг
текущую учётную запись до journal/work, default wrappers PS7/PS5 дали exit2,
driverStarted=false/zero events. Логи output/lifecycle-reuse-check.log,
lifecycle-kit-build.log; evidence output/lifecycle-entry-test-67f2cbf2-c04d-4224-962f-0789b380abe8.
Для PS5 child negative test ограничивает PSModulePath штатными OS modules, чтобы
.NET Process.Start не наследовал несовместимые PS7 binary modules; это только
окружение test child, не изменение системной конфигурации.
Lychee exit0:130total124OK6excluded0errors. Flutter application code не менялся.

Первый независимый reviewer review_lifecycle_002_1 обнаружил ложный concurrency pass:
последовательные Launch могли не пересечься. Исправлено без сужения сценария: оба
процесса создаются suspended до resume, требуется наблюдённый live overlap и запись
обоих PID; отсутствие overlap не даёт passed. Synthetic self-test создаёт два своих
--fixture-wait console-less children и проверяет overlap/фактическое завершение обоих
на закрытии job. Child ownership выделено до CreateProcess для безопасности allocation
failure до job assignment. Mandatory native/release/negative/link checks повторены.

Fresh read-only review_lifecycle_002_2: замечаний не найдено; T035 готова в scope
подготовки tooling. Проверены исходники/пакет/отчёты, самостоятельно suites не
перезапускались. Positive UIA/menu/lifecycle run не проверен. T035 закрыта именно
как подготовка; T018/T019/T025/T026 остаются открытыми до полного fault runner и
реальной clean offline Win10/11 приёмки.
CandidateSHA256 остаётся `69192cfaf3f1e934af214b41ed6852d1b8c3c58b4f39c70c7a09921adcfdc925`;
финальный kit manifestSHA256
`c6b36b572a2a668b76757a06f8f574987906aad0f64c951a929fb02c7e21d442`.
Установленный пользовательский EXE этим проходом не заменялся и не запускался.

## T036 — подготовлена recovery suite реального EXE

run-lifecycle -Suite recovery расширяет девять lifecycle сценариев шестью: owned
ready child crash exit91/reopen с тем же CURRENT и новым descriptor; byte corruption
unloaded icudtl с actual EXE quarantine/restored SHA; kill только собственного child
при наблюдённом новом unpublished staging и последующий reopen; future/invalid/
missing CURRENT с backup вне data, ожидаемой storageBlocked/error/retry UI, unchanged
hashes всех остальных data files/directories, восстановлением metadata и Retry
в том же HWND/PID/store. Если interruption не поймана до publication — не passed.
Это подготовленные code paths; positive GUI/recovery на VM не выполнялась.

Native mutators работают только в созданном этим проходом профиле dedicated test
account под прежними guards; все children остановлены перед file fault, кроме
намеренного восстановления CURRENT при storageBlocked для Retry. Нет reset/removal
профиля или присоединения к пользовательскому установленному process. Runtime path
привязан к Known Folder root/64hex payloadId/reparse rejection; original metadata,
quarantine, saved cache и interrupted staging сохраняются. Hash fixture ограничен
1024entries/64MiBfile/256MiBtotal для fresh empty workspace. Crash/reopen identity
не объявляется доказательством domain transaction durability. FullVmAcceptance=false.

Actual checks: CTest8/8, включая native self-test будущего CURRENT (other fields
сохранены/wrong input rejected), исключение CURRENT из data map, changed-file и
added-directory detection/restoration, прежние readonly/job invariants. EXE probes7/7,
OS-only PE audits8helpers, observer transport/reuse provenance и сохранность capture —
exit0 через tools/test-vm-kit-reuse.ps1. Both native mode negative guards и четыре
PS7/PS5 lifecycle/recovery wrapper entrypoints — exit1/2 как ожидается, driverStarted=false,
zero GUI events. Evidence output/lifecycle-entry-test-ea4e5b5c-fa22-4229-8626-7ce3a4f30be8;
logs output/recovery-kit-build.log,recovery-reuse-check.log.

Первый independent review_recovery_002_1 выявил failure-report bug: valid JSON passed
без scenario мог прервать wrapper до Save-LifecycleReport. Добавлен hash-bound pure
lifecycle-journal.ps1 с валидацией JSON envelope/header/suite/acceptance fields/footer
и catch parse/schema/read ошибок до сохранения report. tools/test-lifecycle-journal.ps1
проверяет complete/incomplete/failed, syntax и malformed schema для обеих suite;
реально прошёл PS7 и WindowsPowerShell5 exit0. Builder включает этот test и parser
в immutable kit. Mandatory native/release/entry/link checks повторены успешно.
Последний lychee exit0:130total124OK6excluded0errors. Flutter/app runtime code не менялся.

Fresh read-only review_recovery_002_2: замечаний не найдено, scope подготовленного
T036 готов. Reviewer прочитал цепочку требований/код/evidence, сверил script copies
и manifest SHA, самостоятельно выполнил journal tests на PS7 и PS5 exit0; остальные
suites повторно не запускал. T036 закрыта как подготовка, не VM acceptance.
Candidate SHA256 `69192cfaf3f1e934af214b41ed6852d1b8c3c58b4f39c70c7a09921adcfdc925`;
финальный manifest SHA256
`b45023b169b9c98f31e4bfeacec5bdf0764f2a75226f9159ee1308c9e77b2adf`.
Остаются T018/T019/T025/T026: full remaining faults/Explorer/OS/logon/txn/draft и
actual clean offline Win10/11 runs. Установленный пользовательский EXE не затронут.

## T037 — переносимая проверка transaction durability

Добавлены Dart AOT store_durability.exe, build script и run-durability.ps1. Fixture
использует текущие WorkspaceStore/write gate и generated AppSettings schema;
SDK/lock сверены с candidate embedded identities, hashes7sourcefiles сохранены.
Isar/private VC и licenses извлекаются из actual EXE payload с SHA verification.
AOT imports OS-only; весь supplied private runtime прошёл audit_existing closure
без внешнего resolve/copy. Live observer проверяет actual private libisar/vcruntime
module paths и hashes до kill. Product deliverable остаётся single EXE.

Actual local PS7 и WindowsPowerShell5 каждый выполнили два случая: marker после
putSync внутри held txn → kill → dark/1/1; marker после committed lease → kill →
light/2/2. Новый process проверил также immutable fields. Marker привязан к nonce/PID;
подтверждены live writer, Process.Kill и exit -1, normal hold expiry/error exit1 не
проходит. По5 negative commands на случай отвергли existing-root init, wrong nonce,
wrong verify phase, relative library, GUI Known Folder root; scratch file hashes и
каталоги не изменились. Source fixture живёт только в коротких новых temp roots,
не открывает установленный GUI profile. Synthetic first publication не является
native publication/ACL или GUI shutdown acceptance. Raw native Isar stdout отделён
от единственного tagged protocol JSON response.

Mandatory tools/test-unit.ps1 exit0: boundary11files, format49files0changes,
analyze0issues, Flutter40tests. Build/reuse integration exit0: CTest8/8, EXE probes8/8
(добавлена binding runtime bytes), observer/journal checks, AOT OS-only audit,
11PE private closure, sidecar provenance и prior capture preservation. Negative
closure без private vcruntime140.dll вернула unresolved import, несмотря на system
VC текущего host. Strict durability entry PS7/PS5 вернул exit2 до data fixture,
fixtureStarted=false, cases=[]; clean VM pass не заявлен. Lychee exit0:130total124OK6excluded0errors.

Latest local reports: durability-9e793666-fcea-4e80-9fc4-46664421584d (PS7),
durability-eb4182e8-ce89-4205-b5e1-6584ecad44b1 (PS5); strict reports
5e68f883-1e5d-4cce-96af-6055d3a3512a / c6fe49c0-6e91-4a3b-b66b-f4461ed0d352
в sibling kit evidence. Logs output/durability-unit-check.log,durability-kit-build.log,
durability-reuse-check.log,release-evidence/durability-closure-negative.log.
Первый deep-path scratch дал Isar Environment error; fixture DB перенесены в short
temp, failed evidence сохранено через проверенный move вне formatter traversal,
relocation map в output/release-evidence/failed-durability-relocation.json. Первый
probe временно перезаписал общий bootstrap imports report; продукт реально
переаудирован и его6OSimports восстановлены, новые helper audits изолированы.

Independent read-only review_durability_002_1: замечаний не найдено; T037 готова
в своём scope. Reviewer проверил chain/code/evidence, самостоятельно сверил product,
manifest,33manifestfilehashes и7sourcehashes; suites не перезапускал, GUI не запускал.
T037 закрыта. CandidateSHA256
`69192cfaf3f1e934af214b41ed6852d1b8c3c58b4f39c70c7a09921adcfdc925`;
kit manifestSHA256 `cfd422a642df7646e21e23ec9cabb6b15a00f9492099642e65380d1291c2110c`.
FullVmAcceptance=false. T018/T019/T025/T026 остаются открытыми: actual clean Win10/11,
GUI/native publication/ACL, power loss, capabilities и остальные fault scenarios.
Установленный пользовательский EXE и его данные не изменены.

## T038 — native tray liveness и подготовленная shell suite

Исправлен FR-209 gap: cached tray_ мог оставаться true после исчезновения Explorer
до TaskbarCreated. Теперь WM_CLOSE и window.hideToTray предварительно проверяют
регистрацию hWnd/uID через identity-only NIM_MODIFY; HWND monitor nominal500ms
независимо от Dart обнаруживает loss, снимает availability, восстанавливает окно
и emits один trayLost на переход. unavailable ticks не steals focus и не добавляет
icon автоматически; TaskbarCreated/manual retry восстанавливают прежним путём.
Timer выделяется до activation worker, ошибки startup/worker и destructor удаляют
его до освобождения messenger. Synthetic platform tests проверили оба hide пути,
loss/repeated ticks/retry/first-frame authority, foreign timer и rollback/resources.

Подготовлен Suite shell (base9+3): actual verified desktop Explorer restart со
same-owner/window/store/tray recovery, native query и confirmed session-ending
shutdown/reopen. Native дополнительно требует WMI VM model/unjobbed driver,
interactive unlocked test account. External Explorer handle связан с system path,
SID/session/creation; fallback restart использует exact system path вне product
job. Watchdog300s, destructive step не начинается после120s baseline; C++ unwind
пытается восстановить shell, force-killed driver/VM cleanup не обещается. Native
messages не объявляются actual Windows logoff/cancel/power-loss проверкой.
Actual Explorer/GUI shell suite на этом host не выполнялась. Read-only --probe-vm
реально вернул DISPOSABLE_VM_REQUIRED; никакой shell/user process не закрыт.

Mandatory tools/test-unit.ps1 exit0: format49files0changes/analyze0issues,
Flutter40/boundary11. Full build-vm-test-kit exit0, subsequent reuse regression
exit0: CTest8/8, EXE8probes, private11PE closure, AOT/observer/journal/provenance
checks. Journal PS7/PS5 exit0 включая shell header scope. Negative entry exit0:
3native guards +6PS7/PS5 wrappers rejected before driver (actual report
output/lifecycle-entry-test-06874d35-6715-4e2a-a2d5-4af64ac6b3ba). Новый candidate
также прошёл local2AOT durability cases с guards; report durability-25e77300-6779-4ac1-8ee2-cbe0020287c6
в sibling evidence. Lychee exit0:131total125OK6excluded0errors.
Logs output/shell-unit-check.log,shell-kit-build.log,shell-reuse-check.log,
shell-vm-guard-probe.log. Ни feature design acceptance, ни actual GUI run не запускались.

Independent read-only review_shell_002_1: замечаний не найдено; T038 готова в
проверенном scope, chain FR209/212→contract→implementation→checks прослежена.
Reviewer inspected artifacts/evidence, suites не повторял, GUI не запускал.
T038 закрыта. CandidateSHA256
`e83d025d0a466d2f94b95434868f50183b5e5a178fca8c3b10a6b711b58fe639`;
kit manifestSHA256 `f0b92fd97f8e91337aadbc88004b309d3cdb12a526ae7011f4adc4b0893ac831`.
T018/T019/T025/T026 и цель002 остаются открытыми; fullVmAcceptance=false.
Установленный пользовательский EXE не заменялся; его данные/desktop не менялись.


## T039 — Native access failure fixture

Changed tooling scope: native/tests/release_lifecycle.cpp, tools/vm-run-lifecycle.ps1,
vm-lifecycle-journal.ps1, test-lifecycle-journal.ps1, test-lifecycle-entry.ps1;
package tasks/vm-verification/this review log. Product source and installed EXE
unchanged. Added retained-handle OWNER RIGHTS denial/restore fixture, temporary-root
self-test and VM-only startup Cancel/Retry cases. Actual ACL GUI run not performed.

Actual checks: build-vm-test-kit -ReuseCandidate exit0; CTest8/8, EXE8 probes,
observer transport, PS7 journal, AOT build and11PE closure. Reuse integration exit0.
PS5 journal exit0. Negative entry exit0:4 native development-account rejections,
8 PS7/PS5 preflight rejections before driver. Evidence output/lifecycle-entry-test-766ad1c2-fa61-49d5-957b-748a70d05c20/results.json.
Logs output/acl-kit-build.log, acl-reuse-check.log, acl-entry-check.log.
Lychee exit0:132total126OK6excluded0errors (output/acl-links-check.log).
No Flutter source changed in T039; previous T038 mandatory unit results remain
historical evidence, not a new run. No screen design checks or live GUI automation.
Candidate e83d025d0a466d2f94b95434868f50183b5e5a178fca8c3b10a6b711b58fe639;
kit manifest6861e8ca3eb85625840f94fb98b837c04759689bed159c98ce1fac9c1d9a6bbc.
T018/T019/T025/T026 remain open.


Independent read-only review_acl_002_1 completed: замечаний не найдено;
готовность tooling T039 установлена в ограниченном scope. Reviewer independently
reran PS7/PS5 journal tests exit0 and inspected source/contracts/evidence.
Actual positive VM GUI/ACL paths remain unverified. T039 closed after clean review.

User confirmation received in this chat: installed tray menu items «Открыть» and
«Выход» both read correctly. This closes the manual text confirmation for T033;
it does not establish shell/ACL/VM acceptance. Installed EXE/user data untouched
in T039. Goal002 and T018/T019/T025/T026 remain open.


## T040–T042 — Unit-only correction

User explicitly confirmed tests are unit-only, no integrations. AGENTS and
constitution1.3.0 now state that rule; spec/plan/contracts/quickstart/tasks amended.
T018/T019/T025/T026 cancelled, not passed. Old completed task history preserved.
Historical VM document/log paragraphs are non-normative. No actual VM run claimed.

Application change: StoreBackend separates initialize/open from WorkspaceStore;
production IsarStoreBackend retains exact previous native initialization and open
parameters. FakeStoreBackend supplies isolated settings/transaction/close behavior.
Publication and write-lease unit tests no longer load real Isar. Two process-kill
cases and their writer moved to tools/historical-integration as historical source.
Boundary guard rejects process/native-DB integration in test/. Native CMake default
contains6 unit tests; observer/lifecycle helpers excluded. test-release.ps1 runs
only that label, never real EXE probes. Release CI builds and audits EXE, runs6
native unit tests, archives product/evidence. No integration/VM steps. VM kit builder
refuses execution, other historical source utilities are outside current workflow.

Actual checks after code change: tools/test-unit.ps1 exit0, boundary10files,
format50files0changes, flutter analyze0issues, flutter test38passed. Previously40
included2 real-engine/process-kill cases now excluded. Native6/6 exit0, no product
or helper launched (output/unit-only-native.log). Build-release exit0 including
manifest/import closure, candidateSHA256
0816016653be42f582cfa6d13fd9653e58650594227c6f2af92f6afae4a8cf0a
(output/unit-only-build.log). Unit log output/unit-only-check.log. Lychee exit0,
133total127OK6excluded0errors before final audit bookkeeping. Remote GitHub CI not
executed; local exact build/unit commands executed. Installed EXE/user data unchanged.

Current requirement coverage (source inspected; independent assessment pending):

| Requirements / acceptance | Implementation | Unit/static evidence |
| --- | --- | --- |
| FR201–202, AC201, SC201 | native/bootstrap/main,payload; package-release; host ABI | runtime_contract/payload unit; build manifest/import audit |
| FR203–204, AC203–204, SC206 | WorkspaceStore, migrations, security | preflight guards, fake-backend publication retry, native security |
| FR205, AC202, SC202 | instance AcquireOwner/activation; native platform | instance unit, platform synthetic messenger |
| FR206–209, AC205–207, SC203–204 | native tray/window; runtime coordinator/view | window_lifecycle/runtime_view; platform hooks |
| FR208/210–212, AC208–210, SC205–206 | coordinator shutdown, WorkspaceStore gate, native finishExit | shutdown/write_lease; runtime_owners/platform unit |
| FR213 | capability interface, main stdio reserved branch | synthetic capability owners; ABI/dispatch static review |
| FR214 | C01/C02/C10–C14/C17 composition and native brand/text | widget data/actions, boundary guard, resource linkage build |

No full-engine durability, clean-OS integration, Explorer or real logon behavior is
claimed tested. The user excluded those test scopes; product contracts remain.
Analysis/convergence and fresh read-only review must assess this resulting state.


Independent read-only review_unit_only_002_1 completed: замечаний не найдено;
готовность к реализации и завершению002 установлена в user-authorized unit-only
scope. Проверены всеFR201–214/AC201–210/SC201–206 и native/Dart/test/build/CI code.
Reviewer independently inspected CTest inventory and candidateSHA, read logs;
full tests not rerun by reviewer. No unresolved confirmed findings. T040–T042 closed.
Final result and limitations: [unit-only-final](unit-only-final.md).
