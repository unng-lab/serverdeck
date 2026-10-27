# Разработка и проверка 001.1

Для текущей сборки общего комплекта UI/locald/MCP и подключения ИИ используйте
[инструкцию MCP](mcp.md). Ниже сохранены процедуры и ограничения приёмки 001.1;
их исторические результаты не подтверждают текущий пакет 021.

Все команды ниже выполняются из корня репозитория в PowerShell 7.4+. Это новая
реализация; команды прежнего приложения не заменяют её сборку и приёмку.
Полный статус находится в [Tasks](../../specs/001-service-foundation/tasks.md)
и [evidence](foundation-verification.md). Установка для конечных пользователей,
SSH, задания и public release ещё не приняты.

## Среда и SDK

Целевая среда — Windows 11 x64. Для сборки нужны Visual Studio 2022 Build Tools
с Desktop development with C++, Windows SDK и VC++ 2015–2022 x64 runtime.
Используется Flutter 3.47.7 с bundled Dart 3.13.5, framework revision
`abaf9c523780a608bd46686fd5e53740a07077f8`. SHA256 Windows SDK archive:
`c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4`.
Архив и загрузку следует сверять с [Plan](../../specs/001-service-foundation/plan.md).

Разместите SDK в `.local/sdk/3.47.7/flutter` либо задайте абсолютный путь
`SERVERDECK_FLUTTER_ROOT`. `foundation-sdk.ps1` проверяет все три значения
идентичности SDK и останавливает команды при несовпадении. Он не устанавливает SDK.

```powershell
. ./tools/foundation-sdk.ps1
Invoke-FoundationCommand $FoundationFlutter @('doctor', '-v')
```

Первое получение зависимостей требует сети. Root и три Dart packages имеют
закреплённые lockfiles; скрипты сборки используют `--enforce-lockfile`.
После сборки runtime не скачивает компоненты. Отдельная проверка работы при
заблокированной сети Q01 пока остаётся открытой.

## Сборка и ручной запуск

```powershell
./tools/run-foundation.ps1 -Configuration Debug -BuildOnly
```

Скрипт собирает обычный Flutter entrypoint, AOT `locald.exe`, копирует pinned
`libisar.dll` и создаёт `foundation.manifest.json` с build identity и SHA256.
Остальная Flutter Windows поставка сохраняется рядом. Результат находится в
`build/windows/x64/runner/Debug`; Release выбирается тем же параметром.
Нельзя переносить один exe без bundle или править manifest для обхода проверки.

Для ручного опыта используйте отдельного тестового пользователя Windows
с синтетическими профилями. Из его checkout:

```powershell
./tools/run-foundation.ps1 -Configuration Debug
```

Без `-BuildOnly` команда также запускает UI. Клиент сам запускает или находит
совместимый locald; вручную запускать службу не нужно. Данные этого пользователя
создаются в `%LOCALAPPDATA%\ServerDeckNext\v1\workspaces\default`, discovery —
в `%LOCALAPPDATA%\ServerDeckNext\v1\runtime\default.discovery`.
Этот запуск не создаёт временный fixture и сохраняет данные между запусками.
Обычные метаданные хранятся в Isar; ключи, пароли и passphrase защищены DPAPI
CurrentUser. UI не открывает базу и не получает сохранённые секреты из API.

Второе окно того же пользователя подключается к одному owner. Закрытие одного
окна оставляет другое работоспособным. Последняя закрытая сессия позволяет
службе завершиться после предусмотренного контрактом grace period; lease
аварийно исчезнувшего клиента составляет 60 секунд. Не удаляйте файлы runtime
для ускорения завершения и не завершайте процесс по найденному PID.

## Обязательные проверки

Проверки и сборки запускаются последовательно: параллельные native suites и
Flutter build могут мешать друг другу через общий owner и package configuration.

```powershell
. ./tools/foundation-sdk.ps1
Invoke-FoundationCommand $FoundationFlutter @('pub', 'get', '--enforce-lockfile')
Invoke-FoundationCommand $FoundationDart @('format', '--output=none', '--set-exit-if-changed', '.')
Invoke-FoundationCommand $FoundationFlutter @('analyze')
Invoke-FoundationCommand $FoundationFlutter @('test')
foreach ($name in @('serverdeck_protocol', 'serverdeck_windows', 'serverdeck_locald')) {
    Push-Location (Join-Path packages $name)
    try {
        Invoke-FoundationCommand $FoundationDart @('pub', 'get', '--enforce-lockfile')
        Invoke-FoundationCommand $FoundationDart @('analyze')
        Invoke-FoundationCommand $FoundationDart @('test', '--concurrency=1')
    } finally { Pop-Location }
}
lychee 'specs/**/*.md'
if ($LASTEXITCODE -ne 0) { throw 'Specification links failed.' }
```

Команды packages включают native тесты и требуют Windows. Root widget tests
не заменяют реальные Windows UI сценарии. Полные suites могут занять несколько
минут. Успех отдельного набора не закрывает всю матрицу Q01–Q12.

## Исполняемые UI сценарии

```powershell
./tools/test-foundation-ui.ps1
./tools/test-foundation-ui.ps1 -ThreeWindows
./tools/test-foundation-ui.ps1 -CrashObserver
./tools/test-foundation-loss-ui.ps1
./tools/test-foundation-credentials-ui.ps1
./tools/test-foundation-inflight-ui.ps1
```

Первый сценарий проверяет два UI, общий owner, stale CAS, explicit reload,
native закрытие второго окна, сохранение в оставшемся и отдельный свежий процесс.
`-ThreeWindows` добавляет барьер concurrent starts и третий живой UI.
`-CrashObserver` завершает принадлежащий harness observer после подтверждённого
commit и проверяет восстановление нового UI без автоматического сохранения
несохранённого черновика. Это не kill во время неизвестного commit.
Loss script проверяет потерю reply после commit и request до enqueue через
test-only transport decorator, explicit status/retry, late original и один эффект
при другом живом окне. Служба и её обычные authentication/storage paths остаются
настоящими; отдельный test entrypoint не является production UI.
Credential script выполняет десять отдельных drives. Первые восемь: create без секрета, replace
паролем, remove, replace приватным ключом с passphrase, keep при изменении имени,
выбор активного профиля, удаление выбранного и reopen пустого состояния. Между
commit проверяются persisted metadata и новый owner generation; отмена форм
не создаёт эффекта. Затем 249 synthetic profiles создаются через настоящий Local API,
250-й сохраняется через UI. Неверные поля и валидный 251-й профиль отклоняются
без изменения результата profilesList/revision; draft после отказа сохраняется.
Последний drive открывает 250 профилей с той же revision и digest результата.
После каждого drive удаление discovery предшествует сканированию всех файлов
продуктового namespace на access-secret и фактический технический ключ; test oracle
читает исходный DPAPI wrapper и не открывает/не изменяет Isar. Проверяются также
оставшиеся runtime/temp файлы внутри namespace. Другие temp директории и parent
логи не входят в этот файловый scan.
Это synthetic UI input, не physical keyboard или native
file-picker acceptance и не полный scan DB/index/logs на секреты.

Каждый скрипт по умолчанию пересобирает нужный Debug acceptance target, копирует
bundle в новый `.local/foundation-ui-<GUID>/application bundle`, создаёт synthetic
profile и восстанавливает переменные окружения после выполнения. Fixture остаётся
в игнорируемой `.local` для диагностики. Скрипты не удаляют runtime рекурсивно.
Перенаправление LOCALAPPDATA изолирует файлы fixture, но не создаёт другого
OS пользователя и не меняет canonical named mutex/pipe identity текущего SID.
Запускайте сценарии без другого работающего ServerDeck этого же пользователя.

`-ThreeWindows` и `-CrashObserver` несовместимы. `-SkipBuild` допустим только
для уже собранного соответствующего target; чужой cached target должен провалить
проверку stage/final proof даже при успешном собственном Flutter drive.
Флаги `-BootstrapAcceptance`, `-FoundationAcceptance`, `-LossAcceptance`,
`-CredentialAcceptance`, `-UnknownInflightAcceptance` у
`run-foundation.ps1` взаимно исключаются. После acceptance build обычный ручной
запуск требует повторной сборки без этих флагов.

Не запускайте `flutter test integration_test/foundation_test.dart -d windows`
как замену harness: он не готовит fixture и bundle. Действующие scripts используют
`flutter drive` с `test_driver/integration_test.dart` и собранным exe.

## Compiled native сценарии

```powershell
./tools/test-foundation-native.ps1 -Scenario WorkspaceLifecycle
./tools/test-foundation-native.ps1 -Scenario CoreStorage
./tools/test-foundation-native.ps1 -Scenario CommitRecovery
./tools/test-foundation-native.ps1 -Scenario ApiCommitRecovery
./tools/test-foundation-native.ps1 -Scenario InitializationRecovery
./tools/test-foundation-native.ps1 -Scenario SecretMarkers
```

Команда сначала собирает ordinary Debug bundle, затем отдельный AOT test entry.
Его fixture root и текущий SID закрепляются при сборке; runtime override не
поддерживается. Новый protected `.local/native-acceptance-<GUID>` содержит
раздельные normal/test bundles и synthetic workspace cases. Entry проверяет
собственный testOnly manifest/image и normal bundle до storage operations.
Normal entrypoint не импортирует controls и отвергает test flags независимо
от отредактированного manifest. Scenario использует production Workspace,
DPAPI и Isar для creation/reopen/staging/corruption/preservation probes;
проверяет отрицательные случаи и не сбрасывает использованный fixture.
Owned child имеет retained handle и deadline180s; PID lookup/recursive cleanup
не используется. Fixtures и safe stdout/stderr сохраняются для диагностики.

`CoreStorage` использует ту же сборку для восьми отдельных AOT processes:
workspace, repository, credential snapshots, mutations, API router, native
channel, service lifecycle и resource limits. Case directories изолированы;
protected exclusive claim до операций сохраняется даже после failure и
запрещает повторный/concurrent запуск. После каждого positive proof проверяется
reject reuse, final metadata записывается только после всех восьми successes.
Только resource-limits имеет fixture budget360s, остальные180s; runtime limits
сервиса не меняются. Snapshot credential case не является полным UI/API journey;
router использует controlled session, lifecycle — controlled clock при actual
store/mutex, channel — реальную pipe/auth/kernel peer проверку в одном process.
Проверки full normal owner/cross-user/failure matrix остаются отдельными gates.

`CommitRecovery` завершает owned AOT writer на двух flushed boundaries: внутри
uncommitted native row transaction и после durable StateStore.commit. На marker
отводится30s, retained image/lifetime проверяется до kill, exit подтверждается
в10s. Новый AOT verifier открывает existing case и проверяет state/row/receipt0
либо1 вместе с credential unwrap. Также проверяются controlled native-handle
failure и DPAPI availability seam; это не реальные OS отказ/смена пользователя.
Writer/verifier имеют отдельные одноразовые protected claims, отсутствующий
writer case не создаётся verifier. Повтор фаз не сбрасывает данные.

`ApiCommitRecovery` отдельно проверяет production LocalApiClient → native pipe →
ServerChannel/ApiServer → MutationCoordinator/StateStore. Управляемая test-only
задержка останавливает writer до commit либо после durable commit перед доставкой
reply. После kill только retained verified child новый verifier требует ноль эффектов
до commit либо ровно один original effect/receipt/credential после него, с рабочим
CurrentUser DPAPI unwrap. Это controlled ready/self-image peers; normal UI,
перезагрузка и полная Q08 здесь не проверяются.

`InitializationRecovery` останавливает actual Workspace.open на девяти стадиях
создания и открытия рабочей области. Первые пять partial stages должны остаться
STORAGE_BLOCKED без promotion, последние четыре — открыть проверенное initial-empty
состояние и завершить promotion, если она ещё не произошла. Protected boundary
record содержит только фиксированное имя и hashes key/manifest. Проверяются
inventory, ACL и сохранность этих identities; byte invariance DB/lock после
native reopen и полный secret-marker scan остаются отдельными проверками.
Instrumentation guarded compile-time define: только отдельный TestBuild включает
его, обычная сборка удаляет вызовы и не допускает установки handler. Runtime flags
и manifest не включают точки остановки. Kill/verification/reuse guards прежние.
Inventory требует точных имён и file types. Отдельный controlled negative case
переименовывает owned synthetic workspace.isar в unexpected.isar с сохранением
count4: verifier должен отвергнуть его до native open, не изменяя replacement.
Failed phases остаются single-use; этот negative записывается отдельно от9successes.

`SecretMarkers` проверяет native persistence части Q05: две credential kinds и
settings сохраняются через actual coordinator/router/Workspace/CurrentUser DPAPI.
Fresh process читает ordinary native metadata и раскрывает все access secrets.
Сканируются owned case files и API responses; strict output allowlist исключает
private diagnostics. Marker oracle встроен только TestBuild, phases single-use.
Source/test binaries с fixture inputs и чужой OS Temp не входят в scan; controlled
session не заменяет normal owner/UI/auth и полную приёмку Q05.
Exact owner-only ACL проверяется до direct native чтения. Unsafe ACL negative
выделен в SecretMarkersUnsafeAcl для prepared disposable среды: Set-Acl отклонён
ОС из-за отсутствующей SeSecurityPrivilege и оставлен открытым без обхода.
Обычный SecretMarkers сохраняет unsafeAclRejected=false и не выдаётся за этот gate.

Это partial owned filesystem fixture, не другой OS пользователь или VM.
API before-commit/after-commit-before-reply probes доступны отдельно; остальные
незакрытые Q gates перечислены в Tasks. Default `All` остаётся fail closed.
Команды не заменяют full
native acceptance или независимое ревью.

## Ошибки и незавершённая приёмка

При недоступности locald UI убирает приватные данные и предлагает допустимое
явное действие. Storage blocked требует разобраться с доступом/целостностью
хранилища; incompatible — с совместимостью сборки или схемы. Timeout не доказывает
отсутствие commit: используйте проверку результата, а повтор — только когда UI
его разрешил. Не заменяйте storage пустой базой и не создавайте новые ключи для
«восстановления» повреждённого пространства.

При записи evidence сохраняйте команду, exit code, scope, безопасные категории
ошибок и подтверждённые assertions. Не публикуйте пароли, ключи, passphrase,
DPAPI/discovery содержимое, VM service auth URI и private dumps. Используйте
синтетические данные; review и проверки не требуют загрузки обычных private файлов.

`tools/test-foundation-native.ps1 -DisposableEnvironment` (default `All`)
намеренно завершается ошибкой. Автоматический полный harness T043 ещё
предстоит завершить. `.github/workflows/foundation.yml`
выполняет checks/build и available14phase dispatcher на Windows Server 2022 с job budget120min; содержит intentional
failure незавершённой приёмки; его нельзя считать зелёным доказательством T044
или Windows 11 acceptance. Документ не добавляет выполненных прогонов CI.

Открыты full Q01–Q12, остальные normal-owner/crash/resource критерии, reboot/other-user,
physical input/key picker и остальные gates из Tasks. Для destructive crash,
reboot и смены пользователя подготовьте одноразовую Windows 11 x64 VM или
выделенного тестового пользователя; сохраняйте отдельное native evidence.
Конкретные операции и проверки, отклонённые системой, остаются открытыми и
не повторяются через другой инструмент или runner. Все остальные доступные
работы продолжаются. Независимое ревью по AGENTS.md обязательно после checks;
только полный доказанный набор критериев разрешает закрыть 001.1.

### Неподтверждённая mutation и авария UI — T189

```powershell
./tools/test-foundation-inflight-ui.ps1
```

Отдельный UnknownInflightAcceptance target проверяет два реальных UI процесса и normal locald. Observer отправляет update и подавляет его reply только acceptance transport; parent завершает свой verified retained child до обычного RPC deadline. Другой живой клиент проверяет один receipt/effect и продолжает mutation. Новый UI/owner читает результат и3receipts без auto-save. Metadata-only proofs содержат killElapsedMs<4000; product RPC5s не меняется. Это committed effect при inflight UI crash, не before-enqueue/running-commit/owner crash, physical/offline/reboot или полная001.1 приёмка. Normal entry не имеет этих controls; `-SkipBuild` принимает только binary с правильными scenario proofs.

## Последовательный автоматический прогон

```powershell
./tools/test-foundation-available.ps1 -ListOnly
./tools/test-foundation-available.ps1
./tools/test-foundation-prerequisites.ps1
```

Dispatcher запускает 14 фиксированных фаз: CoreStorage, CommitRecovery,
ApiCommitRecovery, InitializationRecovery, SecretMarkers, normal prerequisites,
bootstrap owner-loss и семь UI сценариев, включая normal-owner recovery T235. Каждый wrapper пересобирает нужный
target; CoreStorage включает WorkspaceLifecycle. Сценарий credentials теперь
содержит десять drives. Dispatcher останавливается при первом failure, сохраняет
раздельные ignored logs и metadata-only result.json с `fullAcceptance=false`.
`-ListOnly` не требует SDK и не запускает проверок. Отдельная команда prerequisites
проверяет missing/invalid DLL, manifest format/hash и normal UI/locald positive
control; она не доказывает missing VC runtime/other platform/foreign user.

Исторический полный прогон 13 фаз T221 предшествует изменениям T222–T228.
После T221 CoreStorage и десять credential drives были проверены отдельно;
они сами по себе не объявляются новым aggregate run. Исторический T229 фиксирует отдельный
частичный прогон всех 13 фаз после T222–T228; результат и ограничения —
в [журнале проверки](foundation-verification.md). Отложенное live-чтение native files
в незавершённой initialization transaction T227 теперь отдельно указано в
`result.json.excluded`; partial marker не означает clean scan. Deferred unsafe ACL,
reboot/other-user/physical-offline/fullQ и реальный CI не входят в dispatcher.
Исправляйте функциональные failures перед новым прогоном; system-denied операции
не повторяйте и не переносите на runner.

На версии `68b1658` завершён более поздний локальный qualification: root и три
package suites, Debug/Release, все 14 доступных фаз и отдельный compiled
runtime-diagnostics. Receipt проверен с `-RequireCurrentSource` до следующего
изменения исходников; обычные Debug/Release bundles восстановлены и повторно
проверены по хешам. Это доказательство именно указанной версии и локальной
совместимости, без activation, full acceptance или hosted CI acceptance.

На опубликованной версии `60d8d3d` запуск GitHub Actions
[38635056439](https://github.com/unng-lab/serverdeck/actions/runs/38635056439)
успешно завершил cold source build и текущий native qualifier: root/три package
suites, Debug/Release, 14 доступных native/UI фаз и отдельную compiled
runtime-diagnostics. Это подтверждает hosted scope T244/T245 и исправления T252.
Итоговый job имеет статус failure только на шаге `Acceptance remains incomplete`:
полная Q01–Q12/Windows 11 приёмка остаётся открытой. Artifact не активирован и
не готов к распространению. Проверяемые identities и ограничения сохранены в
[журнале проверки](foundation-verification.md#hosted-compatibility-2026-10-15).

## Подготовка одноразовой среды для оставшейся приёмки

Используйте заранее подготовленную Windows 11 x64 VM с двумя отдельными
тестовыми пользователями и восстановимым чистым snapshot. В ней должны быть
PowerShell 7.4+, перечисленные build prerequisites, проверенный SDK и уже полученные
locked dependencies. Не размещайте реальные credentials/серверные данные.
Зафиксируйте OS edition/build, runtime/SDK/build identity и пользователя каждого
прогона. Перенаправленный LOCALAPPDATA не заменяет отдельный SID.

Для Q01 подготовьте возможность полностью отключить runtime networking в этой
VM после сборки и отдельно подтвердить отключение; затем выполняйте normal UI
CRUD/reopen. Для Q08 после подтверждённого сохранения нужна настоящая перезагрузка
этой VM и повторное чтение тех же данных; process restart не заменяет reboot.
Для wrong-user проверки сохраните исходное пространство пользователя A и
проверьте предусмотренный отказ пользователя B при доступе к нему, без копирования
открытых секретов или изменения исходных ACL. Для Q12 требуется интерактивная
сессия: физические keyboard/focus/picker, обе темы, четыре viewport и text scale200%.
Наличие подготовленной среды не является результатом проверки.

Текущий checkout не предоставляет автоматизацию создания VM, reboot или смены
пользователя. Отклонённые Hyper-V/unsafe-ACL/cleanup операции остаются отдельными
открытыми gates; эти инструкции не разрешают их повторение или обход. GitHub
windows-2022 runner не заменяет Windows 11 и интерактивную manual приёмку.

Для выбранного source-built native DLL задачи T045/T207 завершены: provenance,
resolved native dependency graph и полный комплект из 199 bundled notice files
проверены при qualification и в обычных Debug/Release сборках после activation.
Результаты и границы проверки приведены в [журнале приёмки](foundation-verification.md)
(T233 и T236). `distributionReady=false` сохраняется: public release и полная
приёмка 001.1 имеют отдельные незавершённые gates. Точный статус лицензий —
в [third-party notices](third-party-notices.md).

### UI runtime diagnostics acceptance (T231)

Production `lib/main.dart` installs a privacy guard before `runApp`: framework errors and root-isolate unhandled errors reach observers only as fixed categories with an empty stack and fixed context. The last-resort ErrorWidget shows a fixed restart/result-check message; no automatic save, retry or reset occurs. Regular service/domain error views keep their existing behavior.

Run `./tools/test-foundation-runtime-diagnostics.ps1` for the separate compiled Debug fault target. It checks synthetic exception/stack/context/library/collector inputs, observer and console output, real build-failure fallback rendering and an exact proof marker; the driver rejects markers in its captured output and has a120second drive timeout. Source fixture literals/binaries are test inputs, not runtime plaintext surfaces. This target does not start a repository or locald; use `./tools/test-foundation-credentials-ui.ps1` for the production-entry ten-step storage/UI regression. Integration scenarios restore their original runtime hooks before test-binding invariant checks, including on failure. No fault-injection controls enter the normal entry. Debug fault acceptance alone is not a Release runtime/manual/fullQ05 proof; the broader T204 and 001.1 gates stay open.
