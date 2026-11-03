# Historical integration tooling — superseded 2026-11-03

**Этот документ — история, не действующие инструкции и не отложенная приёмка.**
Пользователь исключил все интеграционные/VM/process-kill прогоны: только юнит-тесты.
Ни одна прежняя формулировка «обязательно», «остаётся открытым» или команда ниже
не вводит действующего gate. Не выполнять эти команды в рамках 002.
Актуальные проверки: [quickstart](quickstart.md). build-vm-test-kit.ps1 остановлен;
прочие утилиты сохранены как исторический source/evidence.

---

# VM verification kit — runtime002

Это developer verification artifact, отдельно от единственного поставляемого
`ServerDeck.exe`. Он пока запускает native synthetic contract tests; полный
GUI/fault smoke runner и clean offline VM приёмка T025/T026 остаются открытыми.
Набор не является установщиком и не объявляет release acceptance пройденной.

## Подготовка на development machine

```powershell
./tools/build-vm-test-kit.ps1
```

Команда собирает продукт, выполняет локальные native/EXE checks и создаёт
`output/vm-test-kit/<product-sha256>/`. `product/ServerDeck.exe` — проверяемый EXE;
`verification/` содержит шесть `/MT` contract fixtures, `release_observer.exe`,
`release_lifecycle.exe` и отдельный Dart AOT `store_durability.exe` с private
Isar/VC DLL. Native CTest/runner по-прежнему запускает только восемь native self-tests.
В platform fixture включён только
нужный C++ codec/reply code pinned Flutter; engine imports удалены linker `/OPT:REF`.
Каждый helper проходит PE import/delay-import audit на отсутствие внешнего runtime.
В комплект входят SHA256 manifest, build identities и Flutter wrapper license.
`-ReuseCandidate` повторно упаковывает существующий `output/release/ServerDeck.exe`
без нового product build; native build/tests, EXE probes и transport checks всё равно
выполняются. Этот режим проверяет выбранный candidate, не соответствие его исходникам.
`build-identities.json` набора извлекается из `build=` manifest внутри этого EXE
через release probe, связанный с его SHA256. Соседний development sidecar
`output/release-evidence/identities.json` не является authority для reuse.
Developer regression check после создания набора: `./tools/test-vm-kit-reuse.ps1`.
Он сохраняет failed capture для invalid PID без запуска продукта, подставляет
заведомо чужой development identities sidecar, повторно упаковывает тот же candidate
и проверяет embedded identities/evidence. Sidecar восстанавливается byte-for-byte
в finally. Это проверка tooling, не VM acceptance.

`output/release/ServerDeck.exe` остаётся единственным продуктовым deliverable.
Тестовый набор не добавляет приложению зависимости и не устанавливает ничего на VM.

## Запуск скопированного набора

В корне набора на development Windows допустимо выполнить:

```powershell
powershell -NoProfile -File ./run-native.ps1
```

Это локальная проверка переносимости fixtures. Отчёт `native-results.json`
содержит product/manifest/fixture SHA256, actual exit codes, stdout/stderr и scope.
Поле `fullVmAcceptance` остаётся false даже при всех успешных fixtures.

На disposable clean offline Windows10/11x64:

```powershell
powershell -NoProfile -File ./run-native.ps1 -RequireCleanVm
```

Preflight требует обычную не повышенную учётную запись `ServerDeckSmoke` или
`ServerDeckSmoke-<suffix>`/`ServerDeckSmoke_<suffix>`, подтверждённую VM, workstation
Windows10/11 x64, отсутствие default network route, development tools/SSH client,
system-wide VC DLLs/VS tooling и предыдущего каталога ServerDeck в LocalAppData.
VM образ подготавливается отдельно; это условия тестового fixture, не установки
продукта. Preflight ничего не исправляет, не устанавливает и не удаляет.

Если условия не выполнены, записывается `blockedByVmPrerequisites`, exit2 и ни один
fixture не запускается. Непроверенное окружение не может дать clean-VM pass.
Fixture timeout15s — failed result; runner завершает только свой дочерний fixture.
Имя учётной записи берётся из текущего Windows token identity, не из изменяемого
`USERNAME`. Observer и lifecycle helper запускают `--self-test`; всего восемь
native проверок набора. Self-tests не запускают GUI продукта.

## Read-only evidence реального процесса

`capture-process.ps1` не запускает и не закрывает приложение, не отправляет UI
input и не читает Isar. После запуска проверяемого EXE вручную:

```powershell
powershell -NoProfile -File ./capture-process.ps1 -ProductProcessId 1234
```

Для EXE, перемещённого в readonly каталог, передать его абсолютный `-ExePath`.
SHA256 должен совпадать с product manifest. Snapshot содержит actual image path,
SID текущего пользователя, Windows session, process creation time, loaded DLL paths
и состояния top-level HWND (visible/minimized/class). Эти факты позволяют сравнить
до/после close/restore/duplicate запусков: тот же PID **и creationTime**, тот же
owner image и модули в нём. Observer отказывает при другом image path/user,
недоступном или завершившемся процессе; не выдаёт пустой успешный snapshot.
Window titles и данные domain/store не собираются. Modules/windows перечисляются
последовательно; snapshot не является атомарным снимком lifecycle перехода.

Каждый capture пишет новый файл, UTC interval, helper/product/manifest SHA256,
exit/stderr/timeout и facts. Timeout15s завершает только дочерний observer, не продукт.
Существующее evidence не перезаписывается. Наличие snapshot не доказывает доступность
трея, готовность Isar, успех activation acknowledgement или сохранность транзакций:
для этих критериев нужны отдельные наблюдения/fixtures в полном T025 runner.
`fullVmAcceptance=false` сохраняется при любом исходе capture. Локальный capture
на development host также допустим как проверка самого инструмента.
Default output — соседний каталог `<kit-directory>-evidence/process-<GUID>.json`,
вне собираемого набора. Его содержимое сохраняется при повторной упаковке того же SHA.
Для другого места передать `-EvidencePath`; parent directory создаётся при необходимости.
`tools/test-process-observer.ps1` проверяет capture на synthetic kit с test shell
вместо продукта: JSON/identity, отказ перезаписи evidence, invalid PID и hash mismatch.
Это не запуск GUI ServerDeck и не его acceptance. Build kit выполняет эту проверку
после native/release checks.

## Portable transaction durability fixture

```powershell
# Local synthetic test: no GUI product or its Known Folder data is opened.
powershell -NoProfile -File ./run-durability.ps1
# On the prescribed fresh offline VM; refuse an unsuitable environment.
powershell -NoProfile -File ./run-durability.ps1 -RequireCleanVm
```

Builder AOT-компилирует fixture pinned Dart3.13.5 из текущих WorkspaceStore,
AppSettings/generated schema и сохраняет hashes исходников/lock/exe в
`durability-build.json`. SDK и dependency lock обязаны совпадать с embedded build
identities выбранного candidate. Это source fixture, не отдельный GUI build и не
доказательство идентичности всего исходного дерева старому candidate при reuse.
Runtime runner не вызывает Dart/Flutter SDK, а запускает exe напрямую.

`test-release.ps1` извлекает libisar.dll, vcruntime140.dll и Isar licenses из actual
embedded payload, сверяет SHA с его manifest и сохраняет verification runtime
отдельно от bootstrap audit. Kit включает эти же bytes; `--verify-tree` проверяет
PE import/delay-import closure всех supplied helpers/DLL без поиска или копирования
внешних dependencies. У AOT exe проверены только OS imports; Isar использует private
VC runtime, не system-wide VC install. Live observer перед kill обязан подтвердить
фактические module paths и hashes обеих private DLL из kit, иначе fixture failed.
Включены Flutter/Dart/Isar licenses; product deliverable остаётся single EXE.

Два независимых nonce-owned scratch roots `ServerDeckDurability-<UUID>` создаются
в коротком system temp path, независимо от глубины evidence directory. Они никогда
не совпадают с Known Folder LocalAppData/ServerDeck. Existing/nonempty root нельзя
инициализировать заново; marker version/nonce/ready проверяются перед open, ссылки
отклоняются. Synthetic first-publication callback подготавливает новый store, но
не заявляется тестом native publication/ACL; это отдельные GUI/native gates.

В обоих случаях используется настоящий WorkspaceStore write gate и Isar
`relaxedDurability:false`. Writer меняет theme/settingsRevision/dataRevision в одной
txn. `write-uncommitted` пишет nonce/PID phase marker после putSync внутри callback
и удерживает его; `write-committed` публикует marker только после await завершённого
lease. Sync marker/sleep внутри первого callback — намеренный fault barrier, не
рекомендуемая production transaction работа. Parent проверяет marker и живой PID,
снимает module facts и завершает только созданный им process handle. Writer hold
ограничен60s, barrier/init/verify timeout30s, cleanup wait5s.
Обычное истечение writer hold/error exit1 не считается crash pass: требуется
ожидаемый Windows Process.Kill exit status -1, фактически проверяемый на PS7/PS5.

Новый process повторно открывает store: uncommitted обязан дать целый tuple
dark/1/1, committed — light/2/2; проверяются также неизменённые logical format,
profiles revision, mcp=false и createdAt. LastSuccessfulOpenAt закономерно меняется
при open и не используется как payload acceptance. Неверный nonce, repeated init,
противоположный verify phase, relative library и GUI profile root должны быть
отклонены; все scratch file hashes/каталоги после отказов сравниваются с исходными.
Stdout native Isar может содержать диагностическую версию; единственный tagged JSON
ответ `SERVERDECK_DURABILITY_V1` обязателен для init/verify, произвольный stdout не pass.

Отчёт `durability-results.json` сохраняет environment/manifest/product/source hashes,
phase/PID, actual kill/exit, loaded private runtime, init/verify values и negative
guard results. Короткие scratch roots и evidence сохраняются, автоматического
reset/delete нет. Local pass не является clean VM pass; даже RequireCleanVm success
сохраняет fullVmAcceptance=false: GUI shutdown, OS power loss, native publication,
capabilities и обе Windows VM остаются самостоятельными acceptance requirements.

## Real EXE lifecycle driver (partial T025)

Только на чистой disposable offline VM с указанной выше ordinary test account,
в разблокированном interactive desktop:

```powershell
powershell -NoProfile -File ./run-lifecycle.ps1
```

Entry point сначала выполняет свежий `run-native -RequireCleanVm` и проверяет весь
hash-bound kit. При несоответствии пишет `blockedByVmPrerequisites`, exit2,
`driverStarted=false`; product process не создаётся. Default evidence directory —
`<kit>-evidence/lifecycle-<GUID>/`, уже существующий directory не перезаписывается.
Driver дополнительно сам проверяет token account prefix/elevation, unlocked
Default desktop и отсутствие прежнего Known Folder LocalAppData/ServerDeck.
Он не получает PID установленного приложения и не использует environment-подмену
каталога данных. На текущем development profile запуск продукта им запрещён.

Включены девять сценариев: actual read/execute-only EXE directory (DACL и отказ
записи проверены), cold visible ready с CURRENT/owner lock и host/Flutter/Isar DLL
в original child PID; WM_CLOSE сохраняет owner/текущий store; пункт actual native
popup «Открыть»; system SC_CLOSE и callback double-click; два concurrent duplicates
создаются suspended под job до resume, проверяется наблюдённый overlap обеих live
handles, затем они завершаются с прежним owner/descriptor/store; minimized → Open; пункт «Выход»
завершает процесс/удаляет descriptor/освобождает lock; warm reopen сохраняет CURRENT.
Window readiness и menu labels проверяются через Windows UI Automation по text/action,
без geometry/design assertions. Наличие tray icon проверяет Shell_NotifyIconGetRect;
полученный rect не используется как layout evidence. Callback popup/double-click
и SC_CLOSE посылаются в реальный HWND как native integration input; физические
жесты мышью/клавиатурой и перезапуск Explorer этим не доказаны.

Каждый шаг немедленно flush-ит started/passed/failed в `driver.jsonl`. Wrapper
сохраняет environment/product/manifest SHA, driver exit/stdout/stderr, journal events
в `lifecycle-results.json` и требует все девять passed + completed. Startup timeout30s,
menu timeout5s, обычный exit wait10s, watchdog всего driver180s. Созданные driver
процессы назначаются job до resume; close job при ошибке/timeout завершает только
эти children. Такой forced cleanup всегда failure, никогда graceful Exit pass.
Readonly copy, профиль и evidence сохраняются; для следующего clean run восстановить
VM snapshot. Driver не удаляет/не сбрасывает пользовательский профиль.

Даже `lifecycleScenariosPassed` сохраняет `fullVmAcceptance=false`: draft/synthetic
capabilities, txn durability, startup errors/crash, Explorer/OS ending, alternate
logon, ACL/disk faults и clean runs обеих ОС остаются обязательными T025/T026.
До фактического GUI запуска этот driver считается подготовленным tooling, его
реальная UIA/menu работоспособность ещё не установлена.
Development negative check: `./tools/test-lifecycle-entry.ps1` проверяет native
account guard и default PS7/PS5 entrypoints: exit2 без driver/product запуска на
неподходящем хосте. На dedicated ServerDeckSmoke account этот negative test отказывает.
Synthetic lifecycle self-test дополнительно создаёт два собственных `--fixture-wait`
children без GUI/профиля и проверяет overlap/завершение при закрытии job. Отсутствие
наблюдённого overlap в actual duplicate сценарии не даёт passed.

## Recovery suite (partial T025)

На новом clean VM snapshot вместо default suite:

```powershell
powershell -NoProfile -File ./run-lifecycle.ps1 -Suite recovery
```

Тот же entrypoint/guard выполняет девять lifecycle сценариев и шесть дополнительных:

- `owned-crash-reopen-store-identity`: принудительно завершить только собственный
  ready child (exit91), вновь открыть тот же CURRENT, получить новый owner descriptor.
  Это store identity/reopen, не проверка all-or-nothing domain transaction.
- `corrupt-cache-quarantine-and-reopen`: при остановленных children изменить byte
  `data/icudtl.dat` только в проверенном managed runtime; actual EXE должен сохранить
  повреждённый cache в новой quarantine и восстановить исходный file SHA без смены CURRENT.
- `interrupted-extraction-and-reopen`: сохранить unloaded ready cache через rename,
  запустить EXE и прервать его только после наблюдения нового `.staging-UUID`;
  после termination staging должен остаться, ready directory отсутствовать. Если
  стадия не наблюдалась или publication успела завершиться, сценарий НЕ проходит.
  Следующий launch обязан использовать заново опубликованный правильный runtime,
  сохранить store identity и оставить interrupted evidence. Poll1ms, deadline30s;
  промах timing fixture не является доказательством дефекта продукта и не даёт pass.
- `future-current-block-and-retry`, `invalid-current-block-and-retry`,
  `missing-current-block-and-retry`: сохранить исходную metadata вне `data/`,
  подставить future format2147483647 / invalid JSON либо убрать CURRENT через rename.
  Проверить видимую `Данные недоступны`, ожидаемый failure code, действие `Повторить`,
  отсутствие ready status и сохранение всех data file hashes/каталогов без нового store.
  Восстановить исходный CURRENT, вызвать Retry в том же HWND/PID и снова открыть
  тот же store. Backup metadata остаётся в тестовом профиле, данные не удаляются.

File mutation разрешена только после `AssertStopped` для всех созданных children,
кроме явного восстановления CURRENT в живом storageBlocked owner для проверки Retry.
Пути runtime привязаны к Known Folder root, 64hex payloadId и проверены на reparse.
Hash snapshot исключает изменяемый fixture CURRENT, но включает все остальные
файлы и каталоги `data/`, в том числе неожиданный staging/new store. Ограничения
fixture: ≤1024 entries, ≤64MiB/file и ≤256MiB total — только fresh empty workspace,
не средство проверки произвольных пользовательских баз. Mutator и hash invariants
проверяются native self-test на synthetic temp tree без запуска GUI продукта.

Для recovery wrapper требует все 15 passed + completed; watchdog540s. Повреждённый
или оборванный journal сохраняется как failed с `journalError`; отсутствие данных
не превращается в pass. Hash-bound `lifecycle-journal.ps1` валидирует JSON object
envelope, header/suite/limited scope, event type, acceptance scenario/elapsed и
completed marker; ошибки parse/schema перехватываются до сохранения failure report.
`tools/test-lifecycle-journal.ps1` проверяет lifecycle/recovery complete/incomplete/
failed streams, syntax и malformed schema (включая passed без scenario) на PS7/PS5,
без GUI или профиля. Builder выполняет этот тест перед упаковкой.
Статус `lifecycleAndRecoveryScenariosPassed` остаётся
`fullVmAcceptance=false`. Это пока подготовленный code path; actual positive VM run
не выполнен. Negative entry check проверяет обе suite в PS7/PS5 и оба native mode.

## Shell suite и tray liveness (partial T025)

Только из самостоятельной interactive PowerShell на отдельном clean VM snapshot:

```powershell
powershell -NoProfile -File ./run-lifecycle.ps1 -Suite shell
```

Suite включает base9 и три дополнительных сценария. Он действительно завершает
desktop Explorer тестовой учётной записи и восстанавливает shell, поэтому нельзя
использовать его на рабочем пользовательском desktop. Existing строгий preflight
дополнен native WMI VM-model check, unlocked Default desktop и запретом driver в
внешнем job: новый Explorer должен переживать завершение driver/controller job.
`--probe-vm` — отдельный read-only native guard probe без запуска GUI/Explorer.

`explorer-restart-preserves-owner` скрывает созданное окно, получает actual desktop
GetShellWindow process handle и проверяет exact Windows/explorer.exe path, SID,
session и process creation identity. Только этот verified handle может быть
terminated (exit92). Поддерживается auto shell restart; если новый desktop shell
не появился за1500ms, запускается exact system Explorer на winsta0/default, вне
product job, без command shell/PATH resolution. New PID/creation и та же identity
проверяются в пределах20s. Product должен сохранить HWND/PID/descriptor/CURRENT,
вернуть visible ready и зарегистрированный tray с работающим popup Open/Exit.

`session-query-native-shutdown` отправляет созданному HWND WM_QUERYENDSESSION и
требует TRUE/exit0/descriptor+lock release; `session-confirmed-native-shutdown`
отдельно проверяет WM_ENDSESSION(TRUE), close/reopen того же CURRENT. Это реальные
native-message integration paths выбранного контракта, не Windows logoff, не
отмена logoff и не OS power-loss test.

Shell watchdog300s; destructive restart не начинается, если native baseline уже
занял120s. Обычный C++ unwind пытается восстановить отсутствующий Explorer. Force
kill driver/VM во время restart не обещает desktop cleanup: оператор восстанавливает
disposable snapshot. Ошибка identity/restart не даёт pass; никакие другие user/session
processes не закрываются. На текущем host выполнялись только synthetic self-tests,
read-only VM probe и negative entry checks; actual shell suite не выполнялась.

FR-209 теперь также реализован HWND monitor nominal500ms и probe перед обоими hide
entrypoints, без ожидания TaskbarCreated/Dart. Используется identity-only
[Shell_NotifyIcon NIM_MODIFY](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw),
не geometry check. Synthetic platform tests покрывают stale registration, repeated
loss, retry/close/RPC, чужой timer ID, monitor startup failure и worker rollback.
Parser требует shell header scope и все12 passed+completed; полнота VM по-прежнему false.

## Оставшаяся приёмка

Native fixtures не запускают настоящий GUI продукта. Сценарии [quickstart](quickstart.md)
с Explorer/OS ending, readonly EXE, alternate logon, disk/ACL failures, настоящим
tray Open/Exit и VM crash/recovery должны выполняться отдельно в T025/T026.
Требуются обе поддерживаемые версии Windows. Успех набора не закрывает эти задачи.


## Native ACL failure suite (partial T025)

На отдельном disposable clean VM snapshot с тестовой учётной записью:

```powershell
powershell -NoProfile -File ./run-lifecycle.ps1 -Suite acl
```

Suite включает base9 и два сценария `startup-acl-cancel-preserves-data` и
`startup-acl-retry-same-pid`. Native VM/account/unlocked-desktop guards действуют
до изменений; fixture работает только с собственным fresh profile после завершения
всех созданных product processes. Watchdog300s. Driver сохраняет заранее открытый
READ_CONTROL/WRITE_DAC handle и исходную DACL root. Временная protected root DACL
запрещает OWNER RIGHTS WRITE_DAC, создание файлов и подкаталогов, сохраняя чтение,
traverse и доступ к существующим дочерним данным. Обычные права владельца иначе
позволили бы bootstrap самостоятельно исправить DACL и не воспроизвели бы отказ.
[OWNER RIGHTS SID S-1-3-4](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-identifiers)
определяет эти implicit owner rights.

Actual EXE должен показать native access-error MessageBox с Retry/Cancel до
появления Flutter HWND и загрузки host/Flutter/Isar DLL. Проверяются освобождённый
owner lock, unchanged hashes содержимого data tree и CURRENT. UI Automation
вызывает кнопки по native IDRETRY/IDCANCEL, независимо от языка Windows.
Cancel требует exit1, неизменных данных и успешного reopen того же CURRENT после
восстановления доступа. Retry сначала восстанавливает DACL через retained handle,
затем требует ready того же process handle/PID, private modules и owner lock.
Оба сценария заканчиваются штатным tray Exit. DACL восстанавливается явно и при
обычном C++ unwind; принудительное завершение driver не гарантирует cleanup —
оператор возвращает disposable snapshot. Реальный пользовательский профиль не
является допустимой целью.

Self-test временного synthetic каталога проверяет фактический access denied,
отказ native SecureDirectory repair, неизменные bytes и восстановление без admin.
Это проверка механизма fixture, не positive GUI acceptance. Journal требует ACL
scope и все11 passed+completed; fullVmAcceptance=false. Actual ACL GUI suite на
текущем host не выполнялась; T025/T026 остаются открытыми.
