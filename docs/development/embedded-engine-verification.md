# Embedded engine: фактическая проверка реализации

Существующие001/002-security-storage/021, конституция4.3.0. Актуальный итог —
«Final acceptance record — 2026-11-01» в конце; матрица35требований находится в
«Aggregate audit — 2026-10-31» с итоговым обновлением статусов в новом разделе.
Предыдущие разделы сохраняют историю component increments, counts, blockers и
ограничений; они не описывают текущий итоговый статус. После прямого разрешения
пользователя остатки cleanup перенесены вне репозитория; свежий полный gate и
независимый aggregate review завершены успешно в разрешённом static/RAM scope.
Ничего не устанавливалось и не публиковалось; native/release readiness не заявлена.

## Foundation increment и T253

- Создан serverdeck_engine; UserProtection вынесен из Windows security, прежнее
  определение удалено, потребители импортируют нейтральный port напрямую.
- MCP credential custody перемещён из Windows в engine без изменения secret
  representation/entropy/HMAC/cleanup. Старый source удалён, re-export нет.
- Строгий schema3 WorkspaceManifest перенесён из migration_journal в engine.
  Старое определение удалено. Target workspace теперь отвергает неподдержанный
  manifest/upgrade residue вместо WorkspaceMigration.runTrusted.
- Настоящий DPAPI test вынесен из смешанного unit файла в отдельный native test
  с прежними assertions. Разрешённый runner не загружает этот native файл.
- tools/test-unit.ps1 запускает полный разрешённый root/protocol/Windows/locald/
  MCP/engine scope. Native-only manual workflows отключены, не представлены
  пройденными; их окончательное удаление/замена входит в T276.
- В main checkout исправлены устаревший metadata assert и binding23-log-record
  на точные уже существующие в003 counterparts. Чужой worktree только читался,
  его файлы/процессы/установка не менялись. Поведенческие проверки не ослаблены.

## Фактически выполнено

| Команда/scope | Результат | Ограничение |
| --- | --- | --- |
| dart format --output=none --set-exit-if-changed . | exit0, без изменений | Formatter сообщает старые unresolved include warnings внутри work/, файлов не меняет |
| flutter analyze | exit0, no issues | Static check, не native proof |
| flutter test, полный root suite | 7448passed, 1 прежний opt-in skip | После metadata fix; root не запускает native/integration |
| tools/test-unit.ps1 -DartPackagesOnly после полного failure | exit0 | Явно не повторяет/не засчитывает Flutter test; повторяет root format/analyze и все Dart package unit scopes |
| protocol, весь test/ | 165passed | Pure units |
| Windows, полный разрешённый scope | 5passed | Только pure credential custody tests, без DPAPI/native file |
| locald, 26 reviewed pure test files | 122passed | Native/SSH/process fixtures не выбираются; legacy package ещё подлежит удалению |
| MCP, 5 pure test files | 53passed | Fake/unconfigured branches, без standalone process test |
| engine, весь test/ | 4passed | Boundary и строгий manifest; не доказывает готовность engine host |
| dart analyze для всех пяти пакетов | exit0 | Не runtime qualification |
| PowerShell parser tools/test-unit.ps1; scoped git diff --check | exit0 | Не hosted CI |
| lychee specs/**/*.md перед review | 1584total,1583OK,0errors,1excluded | Проверка ссылок, не семантики поведения |

Локальные полные логи: .local/embedded-unit-current.log,
.local/embedded-package-retry.log. До исправлений полный root suite падал на35
metadata assertions; это не объявлено успехом. При первом package run старые
test snapshots Windows/locald были отвергнуты как InvalidKernel, MCP VM завершилась
с OutOfMemory до попытки остановки подтверждённо своего test process. Guard
отказался посылать сигнал уже изменившейся process identity. Пересозданы только
соответствующие generated .dart_tool/pub/bin/test snapshots; исходники/данные
пользователя не очищались. После полного failure адресный metadata rerun76passed;
затем полный root7448passed и полный Dart retry подтвердили исправления.

Engine unit сначала выявил несовпадение ожидаемого safe code для double-version:
закрытый codec отвергает double до классификации версии. Assertion уточнён до
точных STORAGE_BLOCKED для malformed double и INCOMPATIBLE для unsupported
version; rejection и неизменность исходного input проверяются в обоих случаях.

## Независимое ревью

Completed reviewer `engine_foundation_code_review`, fork_turns=none, read-only:
«Замечаний не найдено»; требования/первый increment готовы для продолжения задач.
Reviewer byte/behavior-compared custody relocation, проверил parser/strict refusal,
импорты/fixtures, unit selection/CI и предоставленные логи. Сам команды не запускал.
Весь dirty diff ему не приписывался. Остаточные transitive native-containing imports
в legacy tests признаны ограничением текущего increment и работой T255/T269/T276,
а не доказательством окончательной изоляции.

Native приложение/DPAPI/Isar/tray/headless runner/SSH/containers/UI automation
не запускались. Backend не менялся. Общая implementation/release readiness
не установлена; T254–T276 остаются открытыми.

## Текущее указание пользователя: сброс старых тестов

Предыдущие таблицы и review относятся к историческому increment. Все прежние
собственные test sources, fixtures, harness и coverage/design pipeline удалены;
сохраняются только unit tests текущей задачи. Native/виджеты/дизайн не запускаются.
15 ignored generated .pyc остаются: автоматическая проверка отклонила их удаление.
Это не исходники тестов и не входы текущего runner. Чужие worktrees и third_party
не изменялись.

Фактический полный `tools/test-unit.ps1` завершился exit0:
- `dart format --output=none --set-exit-if-changed .`: 320 files, 0 changed;
- `flutter analyze`: no issues;
- `flutter test`: 2 unit tests, без widgets;
- engine `dart analyze`: no issues; весь engine `dart test`: 15 passed;
- locald/MCP/protocol/Windows `dart analyze`: no issues; старые tests удалены,
  нового task suite там пока нет, test pass им не приписывается.

Лог: .local/embedded-unit-only-first.log. Новый HostAuthority проверяет binding,
ограничивает owner issuance, не восстанавливает отозванные capabilities и ждёт
физическое завершение поздних proofs/gate при close; сам writer lease не закрывает.
Это ещё не production EngineHost/Windows adapter. Entry-mode parser также пока
не подключён к main dispatch. T254/T274 остаются открытыми.

`lychee "specs/**/*.md"`: exit0,1463total/1462OK/0errors/1excluded.
Исторические ссылки на удалённые тесты преобразованы в текстовые пути, а не в
несуществующие ссылки. CI не запускался. Native и release readiness не установлены.

## Unit reset: независимое review и исправления

`unit_reset_authority_review` (fork_turns=none, read-only) завершён:3 confirmed P2.
1. Поздний отказ физического runtime proof после логического timeout не закрывал
   generation. Исправлено в общем completion handler: любой физический provider
   failure закрывает authority/gate; новая unit проверяет двух owners, поздний
   UNAUTHORIZED и невозможность оживления после восстановления provider.
2. Остаточные checkpoint/environment/MCP acceptance clients удалены вместе с
   соответствующим snapshot root. Нового собственного старого harness не оставлено;
   ignored generated caches не являются тестовыми исходниками.
3. Прежний coverage gate021/T213 явно superseded, без ложного completed marker.
   Текущая процедура — новые units + static checks + independent review.

После исправлений полный tools/test-unit.ps1 exit0: root2passed, engine16passed,
root format0changed/Flutter analysis noissues, analysis всех пяти packages noissues.
У четырёх старых пакетов новых tests пока нет, test pass не заявлен. Лог:
.local/embedded-unit-only-fix.log. Lychee exit0:1462total1461OK0errors1excluded,
.local/embedded-links-unit-fix.log. PowerShell syntax пяти изменённых tools и
scoped git diff --check exit0. Hosted CI/native/build не выполнялись.
Fresh independent review требуется для закрытия T277/T278; общий goal активен.

## Deadline issuance: второе review и исправление

`unit_reset_authority_review_2` завершён: прежние3 findings закрыты; найден1 P2.
В bindOwner отсутствовала монотонная проверка срока перед публикацией capability,
что позволяло успешному синхронно затянувшемуся provider обойти Future.timeout.
Добавлены began/budget и elapsed>=5s refusal до выдачи. Два deterministic units
с управляемыми часами проверяют точную границу5s и6s: новая capability не выдана,
прежний owner остаётся доступен, следующая выдача не наследует просроченную.
T279 хранит finding/исправление отдельно от T278. Третье fresh review обязательно.

## Завершённый fresh review unit reset

`unit_reset_authority_review_3`, fork_turns=none, read-only, completed:
«Замечаний не найдено»; scoped foundation/reset готов для продолжения, без
подтверждённых обязательных пробелов. Reviewer проверил исходники и логи,
сам тесты/CI/native не запускал. Подтверждены все4 исправления предыдущих review.
T277/T278/T279 закрыты; T254–T276 остаются открытыми.

Последний полный прогон .local/embedded-unit-only-deadline.log exit0:
root2 + engine18 =20 units, format320files0changes, Flutter analysis и analysis
всех пяти packages без ошибок. Новых suites в четырёх старых packages пока нет,
их отсутствие не названо test pass. Lychee .local/embedded-links-unit-deadline.log:
1462total1461OK0errors1excluded, exit0. Нового feature package не создавалось.
Главная реализация single-executable engine/MCP/tray ещё продолжается.

## T255: перенос pure domain sources в engine

T254 закрыта после completed unit_reset_authority_review_3 для нейтральных ports и
opaque authority, не для production Host/platform adapters. Следующий increment
переносит8 исходников из locald/lib в engine/lib: automation/{compiler,profile_diff,
job_session}, profiles/validation, remote/{observations,ssh_transport,ssh_reads,
ssh_executor}. Старые файлы удалены, facade/re-export не добавлены. Девять прямых
потребителей теперь импортируют engine; поведение source совпадает с прежними
файлами HEAD при исключении только комментариев. DartSSH2 остаётся pinned4.1.0,
его прямая dependency перенесена из locald в engine. Manifests/locks обновлены.

Добавлены8 новых units текущей задачи: shared2-slot reservation, physical drain
при close, typed endpoint/journal validation, compiler intent/immutable output,
missing baseline/qualification refusals, deterministic/bounded RFC6901 diff и
settings CAS input/closed fields. SSH connect/probe/process/native/UI не запускались.
Parser observations и реальный transport перенесены, их runtime qualification не
выводится из чистых reservation/validation tests.

Первый полный tools/test-unit.ps1 упал: unawaited Future в новом unit и неверно
типизированный пустой Map нового recipe fixture. Исправлены только новые tests,
адресный повтор2files7passed разрешён после full failure. Затем полный runner
exit0 (.local/embedded-domain-extraction-full.log): format323files0changes,
Flutter analysis noissues/root2passed; engine analyze noissues/full26passed;
остальные4 packages analysis noissues, новых tests нет/test pass не приписан.
Lychee .local/embedded-domain-extraction-links.log exit0:
1462total1461OK0errors1excluded. Scoped git diff --check exit0.

T255 остаётся открытой: storage/auth/services ещё в locald. T256–T276 также не
закрыты этим переносом. Ничего не устанавливалось/не публиковалось; backend,
foreign003 worktree, vendor source и generated ignored caches не изменялись.
Нужен completed independent review этого increment перед его завершением.

Completed independent `portable_domain_extraction_review`, fork_turns=none,
read-only:0 findings; scope готов для продолжения T255. Reviewer непосредственно
сопоставил8 sources с HEAD (только4 комментария изменены),9 consumers (только
imports/formatting), прочитал8 новых units, manifests/locks и spec traceability.
Он просмотрел логи, сам checks не перезапускал. Подтверждённых замечаний нет.
Root Flutter + пять packages `pub get --offline --enforce-lockfile` exit0,
.local/embedded-domain-locked-dependencies.log. Полный новый результат28units
(root2/engine26), не runtime/SSH proof. T255 и общая цель остаются активными.

## T255: schema3-only state и metadata graph

Перенесены8 sources: storage/models, storage/host_trust_models и automation/
{snapshot,configuration,authority_commands,job_commands,plan_commands,profile_commands}.
Прежние source files удалены, re-export/facade не добавлен. Models имеют только
WorkspaceState.fromJson/empty schema3; удалены schema1 factory и trusted selectors.
Profile/receipt parsing сохраняет прежние schema3 trust rules. Graph принимает
HostTrustState и единственный schema3 plan parser; loadTrusted/legacy load убраны.
Шесть остальных перенесённых files совпадают по поведению с HEAD (кроме imports).
Двадцать один consumer обновлён напрямую; remaining locald legacy native loaders
тоже проходят target3 state/trust gate, поэтому старый parser недоступен. Сам
locald/auth/store ещё подлежит переносу/удалению T255/T256/T262/T276.

Добавлены9 units: target foundation roundtrip IDs/blobs/settings/receipt history,
input/output immutability, schema1/2/unknown отказ без изменения in-memory input,
wrong owner/orphans/trust/receipt corruption, checked host-trust graph, full10-family
capture before await, grant/receipt refs/native IDs/keys/limits и закрытые commands.
Это semantic RAM-only verification, не physical preflight или full record-family
native roundtrip. T262/T263 остаются открытыми; no runtime sessions minted by loader.

Первый полный прогон до добавления units прошёл прежние26engine+2root. После
добавления9units полный .local/embedded-schema3-extraction-units.log упал на новом
fixture Map<String,Object>, которому test пытался присвоить null. Fixture уточнён
до Map<String,Object?>; targeted schema3_state7passed после full failure.
Полный tools/test-unit.ps1 .local/embedded-schema3-extraction-full.log exit0:
format325files0changes, Flutter analysis noissues/root2passed; engine analysis
noissues/full35passed; other4package analysis noissues, новых tests нет и test pass
не заявлен. Lychee .local/embedded-schema3-extraction-links.log exit0:
1463total1462OK0errors1excluded. Scoped git diff --check exit0. Никаких real
SSH/native/DPAPI/Isar/UI/build/CI операций. Review этого increment требуется.

Completed independent `schema3_domain_extraction_review`, fork_turns=none,
read-only: «Замечаний не найдено», scoped increment готов для продолжения.
Reviewer сравнил8sources сHEAD и21consumer,9units и spec chain, подтвердил
сохранение прежней schema3семантики после удаления schema1/2selectors. Просмотрел
логи37units/static/links, сам checks не перезапускал. Native/adoption/host/tray/
release готовность не установлена. Подтверждённых незакрытых findings нет.
T255/T262/T263/T276 остаются открытыми, главная цель активна.

## T255: receipt/credential custody и mutation preparation

Перенесены6sources из locald/lib в engine/lib: storage/key_custody,
credential_validation, credentials/provider, profiles/service, settings_service,
host_trust. Старые файлы удалены, facade/reexport нет. Schema1 manifest helpers
удалены; create/verifyWorkspaceManifest только exact3. Receipt/credential inner
format1 и прежние entropy/HMAC/zeroing сохранены как часть target3 payload.
ProfileService имеет один prepare(HostTrustState) и PreparedMutation.trust;
внутренний partial result — private record, старый schema1/trusted mode удалён.
Coordinator теперь использует единый preparation API,12consumers перепривязаны.
Native/store/bootstrap/старые coordinator modes ещё pendingT255/T256/T276.

Новые7units используют RAM-only MemoryProtection с entropy matching. Они проверяют
reopen/canonicalHMAC/distinctkeys/close, exactcredentialentropy и IDs, targetmanifest3,
workspace owner gate, clearbuffer cleanup, keep/replace/remove, trust invalidation,
CAS/settings/delete и providerfailure. Receipt addition в setup — лишь данные для
следующей pure preparation, без transaction/authority/native claims.

Первый полный новый run .local/embedded-custody-extraction-units.log упал на
неверном ожидании test: смена только ownerSid у KeyCustody с ТЕМ ЖЕ provider не
означает смену OS-user. Credential entropy исторически не включает SID: OS-user
защищает vault, metadata проверяет validateWorkspaceCredentials/actual owner gates.
Test перенесён на настоящий logical owner gate; crypto/entropy не менялись ради
assertion. Targeted7passed после fullfailure; deleteunit также теперь включает
настоящую предварительную trust row, а не пустой trust map.
Полный tools/test-unit.ps1 .local/embedded-custody-extraction-full.log exit0:
format326files0changes, Flutter analysis noissues/root2passed; engine analysis
noissues/full42passed; other4packageanalysis noissues, tests там отсутствуют и
не засчитаны passed. Lychee .local/embedded-custody-extraction-links.log exit0:
1463total1462OK0errors1excluded; scopedgitdiffcheckexit0. Build/native/SSH/UI/CI
не запускались. T255 остаётся открытой, independentreview increment требуется.

Completed independent `custody_preparation_extraction_review`, fork_turns=none,
read-only:0 findings, scoped increment готов для продолжения T255. Сравнены6sources
сHEAD,12consumers,7новыхunits, coordinator/receipt/validation/trustedcommit цепочка.
Reviewer подтвердил неизменность payload/entropy/HMAC и исходной schema3 semantics,
native vault/owner boundary; логи просмотрел, checks сам не повторял. Native и
полная implementation/release readiness не установлены. T255/T256/T262/T263/T276
остаются открытыми, главная цель активна.

## Bundle4 / Windows runtime foundation T255/T256/T265

Добавлены EmbeddedBuildManifest exact4/schema3 (только app/DLL/optionalexecutor),
Windows EmbeddedBuildBundle и VerifiedApplicationPeer без owner/MCP filename role,
same-exe MCP configuration и private verified executor artifact. Metadata parser
закрывает поля/версии/файлы, сохраняет immutable hashes, rawUnicode/root strings и
16KiB bound. Native verifier сохраняет bounded reads, actualhashes/root/manifest
binding и genuine retained SID/path/hash/process identity; captured binding failure
sticky, нет fallback к3. RetainedProcessIdentity final запрещает foreign Dart fake.
VerifiedExecutorRelease теперь neutral engine port, oldpublic Windows type удалён
без reexport,4 directconsumers обновлены. Legacy implementation private пока pending276.

WindowsNativeStoreRuntime implements NativeStoreRuntime в engine_platform.dart:
точный captured bundle/current process proof, pinned3.3.2/downloadfalse, before/after
proofs, sticky coreidentity/loading/failure. Повторный initialize после failure не
может вернуть прежний successfulfuture. Не открывает DB/не освобождаетlease, DLL
process lifetime. Единственный composition root обязан инициализировать core до
store; старый loader и остальная архитектура удаляются T276 до финальной приёмки.
Windows directdep добавлена на ТОТ ЖЕ repository-owned Isar; Windows/MCP locks
обновлены, vendor не изменён. Root/engine/protocol remain same dependency content.

Новые7protocolunits exactmanifest4: version/schema/types/closedfiles, immutable
capture, build/config/hash/Unicode safeerrors, explicit testOnly, exact16KiB/overflow.
Native verifier/runtime не импортировались в tests, не выполнялись. Никаких SSH/
DPAPI/Isar/process/UI/build/CI native runs. Это foundation, не готовый Host/IPC/bundle.
Полные T255/T256/T265/T271/T276 остаются открытыми. Plan уточняет prerequisite
artifact verification до полного Host/MCP IPC, не меняет пользовательский scope.

Фактический полный tools/test-unit.ps1 .local/embedded-bundle-platform-reviewed-scope.log
exit0: format330files0changes; Flutteranalysis noissues/root2passed; engineanalysis
noissues/full42passed; protocolanalysis noissues/full7passed; Windows/locald/MCP
analysis noissues, новых tests у них нет/testpassнеприписан. Итого51units. Предыдущие
runs также passed; последний повтор после двух исходных уточнений native code
(stickyrepeatinitialize и первоначальные safe error categories) подтверждает finalscope.
Lychee .local/embedded-bundle-platform-final-links.log exit0:
1463total1462OK0errors1excluded. Scopedgitdiffcheckexit0. Lockeddeps root+all5packages
pubget--offline--enforce-lockfile exit0 .local/embedded-bundle-locked-dependencies.log.
Это не native/platform/release qualification. Требуется completed independentreview.

Completed independent `embedded_bundle_runtime_foundation_review`, fork_turns=none,
read-only:0 findings; scoped foundation готов для продолжения. Просмотрены native
verifier/runtime, Isar initialization source API, neutral port,4consumers, locks,
7newunits и requirement/contract/task/acceptance цепочка. Reviewer читал логи,
сам checks не перезапускал и native ничего не исполнял. Подтверждённых незакрытых
findings нет. Actual loaded DLL/platform behavior/Host/IPC/package cutover и final
legacy removal не установлены. T255/T256/T265/T271/T276 и общая цель остаются открыты.

## Storage ports / MCP artifacts extraction T255/T256

ProtectedFiles расширен one-level stream children/kind/fileSize и explicitreplace;
реализован WindowsProtectedFiles с canonical native paths/currentSID/ACL/noreparse/
retainedatomic IO. WindowsWorkspaceLease — private-bound actualacquire attempt с
прежним namespace; Host закрывает и busyattempt. MutexLease final/следитзаexit,
удалены старые wrongthread testflags и relay gate/session injection методы.
ManagedVault обеспечивает ownercheckдо/послеоперации, synchronousintakestop,
physicaldrain иlatewipe/safefailure; Windows factory использует прежний DPAPI.
DPAPIprimitive/secretentropy не менялись. Native factory/lease не вызывались.

McpCredentialFiles перемещён из Windows в engine/credentials без facade. NativeIO
заменён на ProtectedFiles, samepath/lookup/blob/bindings/limits/atomicpublication/
readonlybridge/recovery сохранены. Windows MCP fileprobe удалён.4construction sites
injectednativeadapter; engineartifact imports напрямую, oldsource отсутствует.
Engine directpath1.9.1, lock directness обновлена; новых versions/vendorchanges нет.

Добавлены8units (4vault+4artifacts) с RAM-only providers. Vaultunits проверяют late
resultzeroing/physicaldispose/closedadmission/ownerloss/probe/reentrantclose.
Artifactsunits проверяют inertstage/readonlybridge/publish/revoke/idempotence,
failedatomicrename witholdlookup+pending/explicitrecovery, space/inventory/owner/
directorybudgetrefusal. Это не actualACL/DPAPI/Win32/pathrace qualification.
Первый fullrun .local/embedded-storage-ports-first.log упал на оставшийся старый
native testflag caller в publicationgate. Следующийfull .local/embedded-storage-
ports-units.log: всеunitspassed, но analysisнашёл ещёrelaycaller в sessions и
redundant! в newnativefiles injection. Старая цепочка testhooks удалена, ! исправлен;
не возвращены testoptions радиgreenchecks. Последнийполныйrunnerexit0:
.local/embedded-storage-ports-full.log: format332files0changes, flutteranalyzenoissues/
root2passed, engineanalyzenoissues/full50passed, protocolanalyzenoissues/full7passed,
Windows/locald/MCPanalyzenoissues (testsотсутствуют/no testpassclaimed). Итого59units.
Lychee .local/embedded-storage-ports-links.log exit0:1463total1462OK0errors1excluded.
Root+all5packages pubget--offline--enforce-lockfile exit0 .local/embedded-storage-
ports-locked-deps.log; scopedgitdiffcheckexit0. Ничегоnative/SSH/UI/build/CI не запускалось.
T255/T256/T262/T265/T276 остаютсяopen; нужен completedindependentreview increment.

## Storage ports review/fix loop

`storage_ports_artifacts_review` completed read-only:1 confirmedP2, incrementnotready.
Mutex isHeld следовал составному cleanupFuture, а onExit мог уже наблюдаться при
ещё ожидаемом/потерянном completionstatus5s. Исправлен sticky _WorkerExit.observed
непосредственно в done.first ДО ожидания cleanup; close сохраняет cleanup/error.
Publication gate также отвергает потерянную acquisition и poison-ит generation,
если активный leaseworker исчез без инициированногоclose. Намеренный release не
poison-итздоровуюgeneration. T280 хранит finding и обязательныйfreshreview.

Добавлен consumer-levelunit HostAuthority: observedwriterloss отзывает обоихowners,
закрываетgate/admission и не освобождаетleaseзаresourceowner. NativeonExitdelivery
этимunitнепроверена; mappingпроинспектированвsource, nativeзапрещён.
Полныйtools/test-unit.ps1 .local/embedded-storage-ports-exit-fix.logexit0:
format332files0changes, flutteranalyzenoissues/root2passed; engineanalyzenoissues/
full51passed; protocolanalyzenoissues/full7passed;3otherpackageanalyzenoissues,
testpassимнеприписан. Итого60units. Lychee .local/embedded-storage-ports-exit-fix-
links.log exit0:1463total1462OK0errors1excluded. Lockeddepsуспешныдоfix,
послеfixmanifests/locksнеизменялись. Требуетсяfreshindependentreview.

Completed fresh `storage_ports_artifacts_review_2`, fork_turns=none, read-only:
«Замечаний не найдено»; scoped increment готов для продолжения. Подтверждено
устранение T280, цепочка storage/vault/artifacts/worker/gate,9новыхunits и логи60units.
Reviewer самchecksнеповторял/nativeнеисполнял. T280закрыта; подтверждённыхfindingнеосталось.
T255/T256/T262/T265/T276 иобщаяцельоткрыты, finalcutover/native readiness неустановлены.


### T255/T262: target3 native metadata extraction — 2026-10-30

В engine/storage перемещены records/automation_records/host_trust_records с тремя
неизменёнными generated parts, native_registry/native_schema/native_close/native_failure.
Старые source paths удалены, consumers используют прямые engine imports без facade.
Единственный полный workspaceSchemas содержит16коллекций; WorkspaceRecords.fromState
сохраняет target3 row payloads и IDs. Удалены schema1/2 registry recognizers, selectors
и record constructors. Structural preflight распознаёт только target3 pinned MDBX.
Это проверка каталога/_info/геометрии, НЕ semantic row proof до writable open.
T255/T262/T263/T276 остаются открытыми: legacy store/migration controllers ещё
подлежат удалению, native repository и startup cutover не завершены.

Добавлены8units на literal metadata и synthetic in-memory pages: target registry,
отказ prior subsets, closed property/index/field semantics, corruption precedence,
immutable input, malformed geometry/unsupported format, incomplete meta, reused
catalogue nodes, schema3 singleton rows. Ни DB/FFI/OS/SSH/widget/design, ни build
не запускались. Полные unit/static/link checks и independent review требуются
для приёмки этого increment; результаты фиксируются ниже после выполнения.


Target3 metadata increment проверен: tools/test-unit.ps1 exit0
(.local/embedded-native-schema-full.log): format333files0changes, analyze root и
всех5packages noissues, root2+engine59+protocol7=68units passed. Windows/locald/MCP
тестов нет, test pass им не приписан. Первый полный run выявил только unused import,
он удалён, затем весь runner повторён успешно. Lychee exit0:1463total1462OK0errors
1excluded (.local/embedded-native-schema-links.log); root+5packages locked offline
pubget exit0 (.local/embedded-native-schema-locked-deps.log). Generated parts byte
unchanged против source inventory и HEAD, scoped diffcheck exit0.
Completed independent read-only native_schema_extraction_review:0findings,
перенос готов для продолжения T255/T262. Semantic preflight/native repository,
Host/tray/MCP cutover и удаление всех legacy controllers остаются незавершёнными.
Общая цель не завершена; native/platform/release readiness не заявляется.


### T255/T262/T276: schema3 row capture and upgrade-controller deletion

В engine добавлены workspace_rows/isar_rows/workspace_snapshot: sole schema3,
borrowed coherent16collection read, bounded count+read equality, fixed active/empty
creation paths, protected-files/lease ports, graph/custody/artifact validation и
committed lookup recovery. StoredRow хранит прежние IDs и exact payloads без migration
alias. Все consumers переведены на прямой engine API и IsarRowSource. Bootstrap/store/
discovery используют WorkspaceLease/WindowsWorkspaceLease; native abandoned metadata
сохранено на Windows adapter, engine не использует его как доказательство integrity.

Удалены четыре неиспользуемых runtime source: workspace_migration,
trusted_source_preflight, migration_journal и прежний combined trusted_snapshot;
source2/upgrade-target/preflight/digest branches не перенесены в engine. Удалены
ссылки на reservation несуществующего controller. Legacy foundation parser/helpers
и старые store modes ещё остаются работой T276, не объявляются очищенными целиком.
T255/T256/T257/T262/T263/T276 не закрыты; startup read-only semantic preflight ещё
обязателен и не заменяется loader уже открытого source с lookup recovery.

Новые7units используют RAM-only Files/Protection/RowSource/Lease и target3fixture
нынешней задачи: coherent capture all16, exact IDs/payloads/trust/grant history,
count bounds/incomplete view, singleton/duplicates/schema refusal, invalid rows
каждой из10automation families, writer/owner/custody failures без publication,
empty-stage/path/file gates. Общие данные и RAM doubles вынесены из двух новых
unit suites в test/support без старого harness, native/FS/SSH/UI или design tests.
Полный unit/static/link run и completed independent review обязательны ниже.


Row capture increment завершил проверки: tools/test-unit.ps1 exit0
(.local/embedded-row-source-checked.log), format335files0changes, root и все5packages
analyze noissues; root2+engine66+protocol7=75units passed. Для locald/MCP/Windows
tests отсутствуют и test pass не приписан. Первые полные прогоны нашли ошибки
consumer wiring/types/imports и typo в новом test getter; исправлены, targeted7
прошли, затем полный runner прошёл заново. Lychee exit0:1463total1462OK0errors
1excluded (.local/embedded-row-source-links.log); scoped git diffcheck exit0.
Новых dependencies нет. Completed independent read-only
workspace_snapshot_extraction_review:0findings, increment готов для продолжения
storage extraction. Native/DB/FS/DPAPI/mutex/SSH/UI/build/install не запускались.
T255/T256/T257/T262/T263/T276 и общая цель остаются открытыми; полный native
semantic preflight перед writable open и Host/cutover/tray ещё обязательны.


### T255/T276: single schema3 store and foundation queue

StateStore имеет единственный open/snapshot/commitFoundation/MCP-grant/profile-write
путь schema3; _AutomationFormat и оба nullable snapshot selectors удалены. Workspace
содержит только прежний target3 open/create; удалены schema1 creation/read-key/
commit, schema2 open/views/commit branches, foundation_snapshot/migration_rows/
operational_foundation_writes, неиспользуемый legacy bootstrap и initialization probe.
Сохранён live-job foundation identity fence. Старый LocaldEnvironment удалён,
LocaldArguments пока обслуживает единственный фактический format3 standalone entry.
Из старого native runtime удалены format1/2 loaders и verifier re-export.

MutationCoordinator имеет один schema3 constructor и trust queue; отдельный subclass,
legacy/operational modes и mode flags удалены. Все consumers прямо используют
новые имена без alias/facade. Сохранены custody proof, shared32 admission, HMAC
idempotency, receipt lifetime, native target/gate ownership и claim finish paths.
Typed native adapters/старые router classes пока остаются работой Host/cutover/T276,
не объявляются удалёнными целиком и не являются новым in-process owner interface.

Из native writer в engine/storage/row_plan.dart перенесён pure планировщик
retainRowIdentities: exact bytes при semantic equality, IDs обновляемых rows,
выделение после maximum входного snapshot, int64 overflow с отказом до commit, immutable
sorted result. Caller по-прежнему обязан проверить CAS/graph/custody и выполнить
native transaction/readback; row plan не выдаёт authority и не делает commit.
Четыре новых unit cases проверяют эти invariants, singleton IDs и corrupt/duplicate
raw inputs без DB/Windows/FS/UI. Engine extraction/native readonly semantic preflight
и полная реализация Host ещё не завершены; T255/T256/T257/T262/T263/T276 открыты.

Executor enrollment record.format1 и целевой sidecar.format2 — отдельные документы,
не schema1 workspace. Существующий sidecar.format1 read fallback замечен и остаётся
обязательным удалением/contract update T276; отсутствие legacy целиком не заявляется.
Mandatory full unit/static/link run и independent review increment фиксируются ниже.


### Исправление single_schema_store_review

Completed read-only review нашёл1P2: новый текст обещал глобальный never-reuse
nativeIDs, тогда как прежний schema3 planner использует maximum входного snapshot.
Исправлена область гарантии: surviving rows сохраняют IDs; новые получают ID выше
maximum до этого плана, включая удаляемые им строки; после предшествующего удаления
ID может встретиться вновь. NativeIDs не business identity/API references.
Это correction documentation overclaim, не изменение прежнего allocation и не
основание для нового persisted counter/schema bump. Код и4unit cases не менялись.
Остальных подтверждённых findings в completed review не найдено. Full checks и
fresh independent review обязательны перед принятием increment.


T281 завершена после повторного full runner tools/test-unit.ps1 exit0
(.local/target-only-store-review-fix.log): format332files0changes, root+5packages
analyze noissues, root2+engine70+protocol7=79units passed. Для locald/MCP/Windows
tests отсутствуют и test pass не заявлен. Lychee exit0:1463total1462OK0errors
1excluded (.local/target-only-store-review-fix-links.log); scoped diffcheck exit0.
Completed fresh independent read-only single_schema_store_review_2:0findings,
все42позиции текущего increment проверены; прежний P2 documentation overclaim закрыт.
Код allocation не изменён ради нового требования. Native/runtime/read-onlysemantic
preflight/полныйHost/tray/IPC/release acceptance не установлены. T255/T256/T257/
T262/T263/T276 и общая цель всё ещё открыты; отдельная новая feature не создавалась.


### T255/T276: executor sidecar engine port, exact outer format2

ExecutorEnrollmentStore в engine/storage/executor_enrollments.dart владеет
neutral parser/HMAC/replay/atomic publish/readback через ProtectedFiles,
WorkspaceLease и KeyCustody. Native StateStore содержит один lazily bound instance,
прямые calls через прежний shared32 writer tail; та же queue используется jobs
startup/progress, без alias или второй очереди. Структурированный capsule captures
UUID/method/input/digest и привязан к issuer; это не owner/target authority.
Actual owner adapter по-прежнему удерживает native gate/proof до physical completion.

Удалён outer sidecar.format1 read fallback: принимается только exact format2 с
обязательными receipts. Неподдержанный/foreign/corrupt файл остаётся нетронутым,
ошибка STORAGE_BLOCKED, без conversion/reset/missing fallback. Inner enrollment
record.format1, purpose executor-enrollments-v1 и mutation-v1 HMAC bytes/bindings
не менялись: это собственные форматы целевого payload, не schema1 workspace.
Existing target-format2 bindings/receipts/IDs/digests/createdAt сохраняются;
replay после revoke возвращает historical ACK без восстановления binding/effect.
Существующая запись T178 о readable format1 описывает прежнюю реализацию и больше
не является действующим требованием. Контракт021 executor-enrollment изменён на месте,
obsolete production-migrator/original.isar clauses удалены, новой feature нет.

Read-only absent read не создаёт файл. Missing/unsafe parents, lost owner/lease,
closed key, malformed/cross-workspace metadata и uncertain replacement/readback
закрывают admission и propagates poison к StateStore; lease не освобождается.
NOT_READY при overlapping physical operation не снимается caller timeout, пока
actual work не завершён. При лимите250records/10000receipts/64MiB нет eviction,
existing receipt replay разрешён, новый effect не публикуется.

7новых RAM-only unit cases: confirm/no-change/revoke/restart/stable ACK, immutable
issuer-bound capsule, schema/field refusal unchanged bytes, MAC/key/workspace/
duplicate corruption, capacity/replay, pre/post-commit/readback faults, owner/lease/
path/closed-key loss и timed-out physical read occupancy. Без FS/native/SSH/UI/design.
Native store/Host/MCP/tray cutover/semantic preflight ещё не завершены;
T255/T256/T257/T262/T263/T276 и общая цель остаются открытыми. Применимые full checks
и independent review этого increment фиксируются после фактического выполнения.


Executor enrollment port прошёл full tools/test-unit.ps1 exit0
(.local/executor-enrollment-port-checked.log): format334files0changes, analyze root
и всех5packages noissues, root2+engine77+protocol7=86units passed. Locald/MCP/Windows
tests отсутствуют и test pass не приписан. Первый full run нашёл wiring issues
sharedqueue/extensionfield, исправлены; следующий full выявил неверное fixture
подписания double2.0 строгим signer, заменено rawJSON для негативного теста.
После targeted7passed весь runner повторён успешно. Lychee exit0:1463total1462OK
0errors1excluded (.local/executor-enrollment-port-links.log); exactscopeddiffcheckexit0.
Completed independent read-only executor_enrollment_port_review:0findings;
перенос готов для продолжения T255/T276. Вендор/foreign003 не менялись,
native/FS/DPAPI/mutex/Isar/SSH/UI/Host/tray/IPC/build/install не запускались.
Открытые T255/T256/T257/T262/T263/T276 и общая цель этим не закрыты.


### T255/T256/T276: repository and workspace move into engine

15используемых sources перенесены из locald в engine: StateStore/Workspace,
workspace_creation/foundation_writes, все automation/grant/write/read parts,
executor_metadata_writes и mcp/grants. Старые paths удалены, consumers импортируют
реализацию напрямую. Engine не импортирует Windows/locald/dart:ffi/dart:io.
Storage получает ProtectedFiles/WorkspaceLease/NativeStoreRuntime; fixed default
layout, schema3/format3, 16generatedcollections, transaction flags, shared32tail,
CAS/HMAC/receipts/nativeIDs/opaque credential bindings сохранены.

Native core initialize/revalidate и filesystem операции проходят через существующие
порты. Проверки current owner/slot/root/lease повторяются вокруг async границ.
Native writeTxn и последующий snapshot/readback имеют до/после runtime revalidation;
ошибка после возможного commit блокирует admission, не превращается в ложный
RESOURCE_LIMIT/rollback proof. Close не требует здорового runtime и удерживает
reservation при неподтверждённом native close. Creation inventory streamed/bounded4,
не listSync; существующий stage получает exact native structural preflight до open.
Это НЕ semantic preflight всех rows до writable open: T262/T263 ещё обязательны.

Удалены standalone locald bin, TrustedLocaldBootstrap/entry/LocaldArguments/native
runtime loaders, discovery wrapper/publisher, old idle/grace lifecycle и grant
native test hook/probe. Никакой временный format3 NativeStoreRuntime adapter или
facade не добавлен. Остались legacy native typed services/router/Windows helpers
и UI bootstrap clients/build scripts — их удаление и новый in-process Host/MCP/tray
ещё впереди в этом же scope. Текущий UI ещё не подключён к engine; запуск приложения
после удаления старого entry не заявляется работоспособным до нового Host/cutover.

Locald больше не объявляет directIsar/generator/build_runner, их runtime/dev
ответственность принадлежит engine; offline resolver обновил только locald lock.
Новые6unit cases используют RAM Files/Protection/Lease и stub NativeStoreRuntime;
единственный затронутый Isar API — чистая VM getInstance map. Isar.open/core/DLL/
FS/Windows/DPAPI/SSH/UI не запускались. Проверены preopen runtime failure, retained
reservation при caller timeout/physical pending init, second writer refusal,
unsupported schema/malformed bytes unchanged, owner/slot/lease/path refusal без
keyreset, legacy residue и inert fresh stage при pre-native runtime failure.
Ни positive native adoption, ни полный writer/lifecycle, ни T255/T256/T257/T262/
T263/T276, ни общая цель этим не объявляются выполненными. Full checks/review ниже.


Repository port завершил full tools/test-unit.ps1 exit0
(.local/native-store-port-full.log): format325files0changes, root+5packages analyze
noissues, root2+engine83+protocol7=92units passed. Locald/MCP/Windows tests отсутствуют,
test pass не приписан. Первый fullrun нашёл unused runtime field; поле привязано
к actual native write/readback proof, весь runner повторён успешно. Lychee exit0:
1463total1462OK0errors1excluded (.local/native-store-port-links.log); root+5packages
locked offline pubget exit0 (.local/native-store-port-locked-deps.log); scoped
Gitdiffcheckexit0. Три generated parts побайтово неизменны поSHA256 inventory.
Completed independent read-only native_store_port_review:0findings, все60позиций
scope проверены; reviewer дополнительно сам пересчитал3generatedSHA. Перенос готов
для продолжения T255/T256/T276. Positive native open/adoption, полная semantic
preflight до writable open, новыйHost/UI/MCP/tray/cutover не проверены/не завершены.
Текущий UI после удаления old entry не объявляется запускаемым. Все названные
открытые задачи и главная цель остаются активными, новой feature нет.


### T262: native byte semantic preflight implementation

NativeWorkspaceRows читает exact schema3 pinned MDBX/Isar rows из bounded bytes:
integer IDs, string object offsets/UTF8, branch/overflow/counters/page ownership,
unique entityId hash index, GC/free-list bounds/disjointness. Public metadata-only
wrapper удалён, нет fallback старого schema/native layout. Pure Dart xxh3:1.2.0
добавлен как direct runtime dependency для существующего native index encoding.
Native/recipe archives SHA256 подтверждены, 11прочитанных Rust/C files побайтово
сверены с pinned zip entries; build/vendor sources не изменены и не запускались.

preflightWorkspace проводит полный graph/custody/MCP artifact и executor sidecar
read-only gate ДО Isar.open. После open inspectWorkspaceSnapshot+exact row comparison
предшествуют lookup recovery. Existing creation stage проверяется byte/initial graph
до native open и сравнивается после; freshly absent workspace создаётся как прежде.
Основной readWorkspaceSnapshot после mutations по-прежнему выполняет committed
lookup recovery; новый inspect entry всегда read-only, никакой role/mode от wire.

Новые12units покрывают bounded binary extraction/immutable16families, raw ID/bytes
readback и delayedlookup, numeric branch IDs и independent literal hello XXH3vector,
overflow и malformed pointers/UTF8, hash/id/index mismatch/reusedpage, GC overlap/
range/count, ambiguous equal meta/out-of-range txn, logical badrows beforepublish,
optional/unsupported sidecar и safe provider errors. Literal registry fixture
вынесен из нынешнего native_schema unit suite, не восстановлены прежние тесты.
Все fixtures построены в RAM без native writer/DB/FS/SSH/UI/design.
T262/T263 не закрыты: окончательная Host composition/whole-family positive/fault
acceptance ещё нужны; actual native qualification не выполняется по scope.
Full unit/static/link/locked-deps checks и completed independent review ниже.


Readonly meta review: первый completed independent native_semantic_preflight_review
нашёл3P2 — exact steady signature, geometry и equal-txn clash. Synthetic fixtures
также содержали эти ошибки;104passing units не были подтверждением native validity.
Исправлены reader/fixtures, добавлены3новых RAM-only refusal units. T282–T284
фиксируют findings без стирания предыдущей истории. Следующий полный unit/static/
link прогон и свежий независимый review обязательны, готовность пока не заявляется.


Второй completed independent review native_semantic_meta_fix_review:1P2 page
transaction ancestry. Предыдущие3meta findings исправлены;107passing units не
закрывали этот новый дефект. T285 фиксирует root/tree, branch/child и leaf/overflow
front checks и3новых RAM regressions с unchanged bytes/no writes. Full checks
и fresh completed review после исправления обязательны.


Третий completed independent native_semantic_ancestry_review:1P2 — branch min2
и even upper для non-DUPFIX branch/leaf. T282–T285 подтверждены, T286 добавлена
для нового finding. Reader исправлен;3новых RAM regressions проходят preflight
с unchanged bytes/нулевыми writes. Следующий full runner и fresh review обязательны.


Четвёртый completed native_semantic_page_review:2P2 GC overflow minimum и valid
reserve extent refusal; T287/T288 добавлены, история113unit run сохранена. Reader
теперь учитывает GC dsize>4 и1spare page, включая полную проверку allocated extent.
Inline emptyPNL не запрещён.6new RAM cases покрывают оба fixes и4extent failures.
Первый targeted run с oversized padding/small snapshot упал на прежнем value cap;
fixture исправлен без изменения production cap (2048RAM freepages/8196bytePNL).
Повторный targeted27cases exit0 .local/native-semantic-gc-targeted.log. Full runner,
links и completed fresh independent review должны завершиться перед готовностью.


Readonly semantic preflight loop завершён для bounded increment: completed fresh
independent native_semantic_gc_review —0findings, готов для продолжения T262/T263.
Подтверждены все7P2 fixes T282–T288; история предыдущих reviews сохранена.
Финальный tools/test-unit.ps1 exit0 .local/native-semantic-gc-full.log: format329/
0changes, root+5analyzers clean, root2+engine110+protocol7=119units passed. Locald/
MCP/Windows не имеют нынешних tests, test pass не приписан. Formatter предупреждает
о lint include исключённого nested work checkout; анализ основных packages чистый.
Lychee .local/native-semantic-gc-links.log exit0:1463/1462OK/0errors/1excluded; root+
5lockedoffline --enforce-lockfile pubget exit0, scopeddiffcheckexit0;3generated
schema parts SHA256 неизменны. Source archive hashes и17usedprimaryfiles сверены
побайтово с pinned recipe archives; никаких native/build/vendor изменений нет.

Готов только этот ограниченный increment. T262/T263/Host/UI/MCP/traycutover остаются
незавершёнными, нынешний UI не объявлен запускаемым. Native/Isar/DPAPI/realFS/SSH/
process/UI/integration/build/install не выполнялись; synthetic units+source review
не устанавливают native/platform/release readiness. Общая цель активна.


Target ordering port increment: sole implementation engine/hosting/target_changes,
old locald part deleted, actual Windows gate implements engine ports directly.
10new RAM units exercise timeout vs physical completion,16charge, retirement,
late proofs and close failures. First full source-port runner119units passed;
full runner after10new tests129units passed (root2+engine120+protocol7), all root+
5analyses clean, format330/0changes (.local/target-fence-port-full.log). No native
tests/pass attributed to Windows/locald/MCP. Linkcheck and independent review
are required before this increment is ready. Full goal still active.


Target ordering port: completed independent read-only target_fence_port_review
—0findings, готов для продолжения T255/T256/T257. Reviewer сравнил весь source
scope с .local/target-fence-port-before.json и подтвердил callback-policy parity,
physical charge/drain и ordering≠authority. Applicable checks: full runner exit0
129units (root2+engine120+protocol7),format330/0changes, root+5analysis clean;
lychee1463/1462OK/0errors/1excluded exit0 и scopedgitdiffcheckexit0. Форматтер
предупреждает о lint include исключённого nested work checkout, source analyses
чистые. Без native/FS/SSH/UI/integration/build/install, без нового feature spec.
Готов только этот перенос, общая цель и названные задачи остаются открытыми.


Retired local API branches increment:26existing sources changed,10files deleted,
net1952lines removed. Legacy API1/2 entries and duplicate owner/MCP/catalog/router
compositions removed, no forwarding facades or fallback. Retained native target
path still requires engine session/Host/UI/MCP/tray cutover. Static searches in
lib/packages/tools/.github found no remaining references to deleted entry paths
or retired declaration names; this is not proof whole-codebase legacy removal.

First full .local/session-prune-first.log failed root/locald analysis on one
unused errors import; full suite still executed, its green units were not a green
fullcheck. Fixed import; .local/session-prune-full.log exit0: format320/0changes,
root+5analyses clean, root2+engine120+protocol7=129units passed. Locald/MCP/Windows
no tests/passclaimed; no native/design/integration/FS/SSH/build/install checks.
Preincrement UTF8 source snapshot .local/session-cutover-before.json, scoped
26file inventory .local/session-prune-review-files.json. Linkcheck and completed
independent read-only review are mandatory before readiness of this removal.


Retired API removal reviewed: completed independent read-only
retired_session_branches_review —0findings, готово для продолжения T255/T276.
Все26sources сопоставлены со snapshot и старым import graph, target composition
и native3 authority/limits/late-response checks сохранены. DTO/wire versions
не изменены, aliases/fallback/facades не добавлены. Full runner exit0:
format320/0changes, root+5analyses clean,129unit tests. Lychee exit0
.local/session-prune-links.log1463total1462OK0errors1excluded; scopeddiffcheckexit0.
Нет native/FS/Isar/DPAPI/SSH/process/UI/integration/build/install/release checks.
Готов только этот removal increment; portable session/owner/Host и fullcutover
остаются открытыми, runnable UI не заявлен. Общая цель активна.


Portable sessions/service extraction:40direct moves (.local/engine-sessions-moves.json),
no oldsource facade. Preincrement source/core snapshots .local/engine-sessions-before.json.
HostAuthority capability→private OwnerSession is the sole owner issuer; MCP port,
handshake and wire server cannot register/dispatch owner. All typed services now
reside in engine with preserved store/custody/queue/job recovery and target fences.
9newRAM units exercise actual auth/registry behavior, no filesystem/native I/O.
Successful full .local/engine-sessions-unit-full.log exit0: format322/0changes,
root+5analyses clean, root2+engine129+protocol7=138units passed. Failed earlier
fullruns on unused _begin and import were fixed; failures not claimed green.
Formatter still warns about excluded nested work lintinclude. No tests/passclaimed
for Windows/MCP/locald (oldlib has no source). Whole Host/UI/MCP/tray and native
endpoint/discovery composition remain unbuilt, current UI not claimed runnable.

Automatic approval review rejected guarded recursive deletion of old package/cache
with reason blocked by policy; no equivalent retry. No command in that rejected
exec ran, including proposed config backup and follow-up runner. Thus only actual
engine-sessions-unit-full.log is check evidence. Config/cache cleanup remains open.
Linkcheck and completed fresh independent review required before readiness here.


Первый completed engine_sessions_port_review:2P2. Expiry-beforecapacity и общий
physical helper tracking реализованы; grant-open cap4 сохраняется через финальную
фазу/lateproof, aggregate256 включает disconnected requests.5new RAM units cover
all8expiry/mixedpending/callbackerrors/roothelper-timeout-drain/256retired bound;
это не полная MCP tool/grant/terminal backend приёмка T268. No native store fake
или public signing/testmode constructors не добавлены. Applicable fullrunner и
fresh independent review после fixes обязательны.


Второй completed engine_sessions_fix_review:1P2 late MCP chain after snapshot drain.
T289/T290 fixes подтверждены; T291 tracks private physical-chain handle registered
beforephases, fixed-point physical drain,256registry proof bound and bootstrap
proof routing. Existing actor observers in connections/reads/executor and catalog/
authority/plan/job flows use that common path; actual domain effects unchanged.
New RAM snapshot case starts consumer drain before late channel exists and asserts
no early release even after channel logical failure, no false native-error signal.
No real grant store/terminal backend test claimed. First chain fullrun failed
misplaced test variable, fixed; repeated chain fullrun exit0 with144units.
Final fullcheck/review evidence appended only after actual completion below.


Portable sessions/service extraction reviewed: completed independent read-only
engine_sessions_chain_review —0findings. All88scope paths/40actual moves checked,
T289–T291 confirmed; source isolation, owner vs MCP admission, cap4/16/256/drain,
late chain snapshots, helper proof lifetime and unchanged domain effects reviewed.
Readiness applies only to this extraction. Actual current final fullrunner exit0
.local/engine-sessions-final-full.log: format322/0changes, root+5analyses clean,
root2+engine135+protocol7=144units passed. Lychee final-links exit0:1463total/
1462OK/0errors/1excluded; scopedgitdiffcheckexit0,3generatedparts SHA256 unchanged.
Excluded nested work lint warnings retained, no pass attributed to absent tests.

Actual grant/tool/terminal backend parity remains T268; RAM snapshot regression
uses the common request binding, not a native store or real operation transport.
Host/gateway/UI/MCP bridge/tray and native adapter composition remain open, current
UI not claimed runnable. Native/FS/Isar/DPAPI/SSH/process/UI/integration/build/install
not performed. Automatic review's blocked recursive cache/package cleanup is not
worked around or claimed complete. Main goal remains active.


In-process owner gateway increment: NEW hosting/in_process_gateway.dart and12RAM
unit cases; api/owner_api.dart drops unused direct-dispatch extension and corrects
owner-admission documentation. Baseline for that file in
.local/inprocess-gateway-before.json. No runtime/platform adapters or UI changed.
Actual source code routes typed services after opaque owner admission; capture,
readiness/generation/final-proof guards and physical drain are gateway-owned.
Whole-message budgets/noncanonical Unicode/metrics retained. Source firstfull
failed missing RetryAdvice import, firstnewtest full failed prefix shadowing;
fixed, failures not claimed green. Previous completefull156units passed before
removing unused extension; final full/link checks and independent review required.
No native/integration/FS/SSH/process/UI/design/build/install runs. Dispatcher fake
checks boundary lifetime, not full native/domain parity. Host, UI adapter, tray,
MCP/native composition and blocked legacy cache cleanup remain open; no runnable
app or release readiness claimed.


In-process gateway reviewed: completed independent read-only
inprocess_gateway_review —0findings, ready for continued Host/UI composition.
Actual final runner .local/inprocess-gateway-final-full.log exit0:format324/
0changes, root+5analyses clean, root2+engine147+protocol7=156units passed. Lychee
.local/inprocess-gateway-links.log exit0:1463total1462OK0errors1excluded; scoped
diffcheckexit0. Reviewer compared owner_api baseline and inspected real typed
adapters, proof/readiness/generation/budget/cleanup parity. No test pass claimed
for absent locald/MCP/Windows suites, nested work lint warnings still recorded.
Readiness limited to this gateway; Host/UI/lifecycle/MCP/tray and full domain/
native acceptance remain open. No native/FS/SSH/process/UI/integration/build/
install runs and no change to blocked cleanup status. Main goal remains active.


Host startup/explicit-exit increment:13new RAM-only units exercise the real
EngineHost with fake lifecycle resources, retained identity/gate/lease/vault and
real session/gateway admission. The default resource implementation binds the
actual Workspace and TrustedControlServices; tests never open native storage.
Checks cover late startup/acquisition, one store/two windows, safe readiness,
CloseBlocked/explicit waiting, failed cleanup and detached physical gateway work.
No claim of native Isar/Windows/MCP endpoint/UI/tray/suspend qualification follows.
The UI remains on pending bootstrap cutover. Full checks/review follow below.


First completed engine_host_ownership_review found1P2: replacing/pruning closed
gateways discarded their physical drain and sticky cleanup failure. Fixed both
paths with retained close and old-capability revocation. Four RAM regressions
cover self-retired cleanup error and active late dispatch on each path;17Host
units pass targeted. Final full checks and fresh review are pending below.


Second completed engine_host_fixed_review confirmed the prior fix and found1P2
reentrancy gap: Host registered pending ownership after starting runtime proof or
retirement callbacks. Fixed reservation-before-callout and removal/revocation of
the full old batch before close listeners.3RAM regressions bring Host units to20,
covering runtime proof/detach/shutdown synchronous reentry. Final full checks and
fresh review follow; broad app/native/platform readiness remains unclaimed.


Third completed engine_host_final_review confirmed T292/T293 and found1P2 startup
ownership-before-callout race. Physical startup and observers now precede provider
invocation;2RAM success/failure regressions cover shutdown synchronously from
acquireLease with late acquisition.22Host units pass targeted. No actual native
lease/store/FS operation occurred; final mandatory checks/fresh review follow.


Host final checks .local/engine-host-owned-startup-full.log EXIT0:format327/
0changes, root+5analyses clean; root2+engine169+protocol7=178units pass,22Host RAM
units. Lychee .local/engine-host-owned-startup-links.log EXIT0:1463total1462OK/
0errors/1excluded; scoped diffcheckEXIT0 CRLFwarningonly. No tests pass claimed
for absent locald/MCP/Windows suites or excluded nested work checkout.
Fourth completed independent read-only engine_host_startup_fixed_review found
0findings and confirmed T292–T294; bounded startup/owner/explicit-exit core ready
for continuation. Native/platform/whole-app acceptance remains unestablished:
Windows roots/IPC/MCP/UI/tray/capabilities/suspend-resume are still mandatory.
No new feature/spec, native test, build, installation or old blocked cleanup retry.


Embedded discovery increment: format2 only, Ready workspace/Host generation,
embedded-v1 file/pipes with unchanged exclusive writer mutex; old parser and
withWorkspace deleted. DiscoveryCustody moved directly Windows→engine with exact
new purpose, old Windows file removed and actual readers rebound.14RAM-only new
units cover raw/wrapped bounds, strict versions/identity/token, cleartext wiping,
provider/input/late-close behavior. No native/protected-FS/DPAPI/pipe/process test
or acceptance claim. Old root/IPC/runtime/MCP/UI cutover remains mandatory; full
checks/fresh review recorded below after completion.


First completed independent embedded_discovery_review found1P3 contract/code
precedence mismatch: foreign build was checked after closed fields. Code now
checks build first as contracted; unit adds foreign build+unknown role field.
TaskT295 records closure; final full/link checks and fresh review still required.


Embedded discovery final .local/embedded-discovery-fixed-full.log EXIT0:
format329/0changes, root+5analyses clean, root2+engine175+protocol15=192unitpasses
(14new RAM units). Lychee .local/embedded-discovery-fixed-links.log EXIT0:
1463total1462OK0errors1excluded; scoped diffcheck EXIT0 CRLFwarningonly. Nested
excluded work lint warnings remain; absent Windows/MCP/locald suites have no
claimed testpass. Fresh completed embedded_discovery_fixed_review found0findings,
confirmed T295 and bounded readiness for continuation. Actual publication/native
runtime/IPC/MCP/UI/tray/platform/release acceptance remains unestablished and open.


Windows runtime/gate increment: genuine bundle4/current-app+held Windows lease
runtime and sole standalone native publication implementation. Old part/role/test
hooks removed; legacy policy remains in pending old IPC source, no new runtime
compatibility adapter or gate alias. Partial native opens retain failed owned
cleanup; checked process/kernel handles, settled acquisitions and lease drains
remain Host-owned.4RAM naming cases added; actual Win32/process/ACL/worker/store/
MCP endpoint/UI/tray/native readiness is not established. Default code paths were
not run natively. Full mandatory checks and independent review follow.


First windows_runtime_gate_review found2P2: Windows root case could split kernel
namespace; UI worker placement was optional/underspecified. Fixed pure Windows
normalize/lowercase binding with3RAM cases; made engine-worker/privateUIproxy and
monotonic/settlement/shutdown/loss ownership mandatory in existing plan/contract.
Root/proxy/MCP/tray implementation still pending. Final full/link checks and fresh
review required; no native/process/FS/UI tests added or claimed.


Windows runtime/gate reviewed-full .local/windows-runtime-gate-reviewed-full.log
EXIT0:format333/0changes, root+5analyses clean, root2+engine179+protocol15+Windows3
=199unitpasses. Windows3arepure naming-policy tests without native calls. No test
pass for absent locald/MCP suites or excluded nested checkout; lint warnings
recorded. Lychee .local/windows-runtime-gate-fixed-links.log EXIT0:1464total/
1463OK/0errors/1excluded; scoped diffcheckEXIT0 CRLFwarningsonly.
Fresh completed read-only windows_runtime_gate_fixed_review found0findings and
confirmed T296 naming and T297 required worker/UI decisions. Bounded runtime/gate
ready for further integration only; root/proxy/MCP endpoint/bridge/UI/tray and
legacy removal still open. Native/runtime/platform/release acceptance not claimed.


Bound worker-gateway increment adds result/physical-settled ownership, shortened
absolute request expiry and shared VM clock; private Dart transport/proxy/server
binding with16retained slots, original queue/delivery budgets and physical close.
15RAM-only tests use real owner/session/gateway + fake services/channel/timers;
no native/realFS/SSH/process/engine-isolate/UI/design execution. First full run
caught two test future lints and an unobserved proof future on expired budget;
fixed before targeted15passed. T298 records that code defect. Root spawn/attach/
control, Windows composition and UI/MCP/tray cutover remain open. Final checks and
independent review follow before bounded readiness conclusions.


First completed worker_gateway_review found1P2 early-discard buffer wipe gap.
Both retired-binding and retired-proxy guards now wipe owned mutable input;
2RAM regressions preserve no-effect/idempotent-close behavior.17new tests pass
targeted. T299 records closure; full checks and fresh independent review remain
required. No native/FS/process/SSH/isolate/UI test or runtime qualification added.


Bound worker transport final .local/worker-gateway-fixed-full.log EXIT0:
format336/0changes, root+5analyses clean, root2+engine196+protocol15+Windows3
=216unitpasses,17newRAM cases. No nativecalls inWindows3; absentlocald/MCPsuites
and excludednestedwork checkout have no claimedpass (lintwarnings retained).
Lychee .local/worker-gateway-fixed-links.log EXIT0:1464total1463OK0errors1excluded;
scopeddiffcheckEXIT0 CRLFwarningonly. Fresh completed worker_gateway_fixed_review
found0findings and confirmed T298/T299. Readiness is limited to bound transport;
trusted Rootworker/control/native composition, UI/MCP/tray and full feature remain
unfinished. No real-isolate/native/platform/runtime/build/install qualification.


### T258/T261: trusted worker root and Windows bootstrap

Added private VM-capability root routing, eight owner windows, reserved lifecycle
control, original startup/attach/exit budgets, partial startup ownership, explicit
CloseBlocked waiting, physical closed acknowledgement handshake, and Windows
worker entry/native bootstrap. Host adds runtime-metadata disposal before lease
release and managed automatic failure hold. Root controller/spawn and Flutter UI
cutover are still pending; existing UI remains legacy/not claimed runnable.
13newRAM tests (10root+3Host) exercise these boundaries; first full check found
Dart Capability/protocol enum collision, corrected by hiding protocol enum.
No old tests restored and no widget/design/integration/native tests added.
Full checks and independent review must finish before bounded readiness claim.


Trusted worker root final evidence: .local/worker-root-fixed-full.log EXIT0;
format339files/0changes, rootFlutter+5package analyses clean; root2+engine209+
protocol15+Windows3=229unitpasses, including13newRAMtests. Windows3 remain pure
policy tests; excludednestedwork formatter lint warnings do not imply qualification.
.local/worker-root-links.log EXIT0:1464total1463OK0errors1excluded. Scoped diffcheck
EXIT0, CRLFwarningonly. Completed independent read-only worker_root_review found
0findings and bounded Root/bootstrap readiness for further integration. No native/
FS/SSH/process/isolate/UI/design execution. Actual spawn/controller, UI cutover,
MCP publication, tray/suspend, broad tasks and goal remain open; current app still
uses pending legacy bootstrap and is not claimed runnable. No new feature spec,
compatibility facade, build/install/publish or blocked-cleanup retry.


### T258/T261: worker controller / concrete VM connection

Added EngineWorkerController and DartWorkerConnection, private actual spawn/control/
error/exit paths, retained original budgets/control slots, root-bound window links,
physical close acknowledgement before expected exit, loss without restart, and a
Windows desktop singleton factory. UI still uses old bootstrap; no runnable-app
claim.12newRAMtests exercise actual Root/Host/gateway with fake connection/timers,
not Isolate.spawn/native/UI/design. First full run caught two test errors; addressed
then all12targeted pass. Retired controller start now returns current CloseBlocked,
not old successful startup. Full checks/independent review follow.

- [x] T300 Исправить подтверждённую при concrete VM composition коллизию Capability: DartGatewayChannel.binding использовал protocol permission enum вместо VM capability. Скрыть protocol enum в enclosing gateway library, проверить concrete typed construction, RAM controller scenarios/full checks и независимое review. Не добавлять совместимость или owner DTO.


Worker controller final pre-review checks: .local/worker-controller-final-full.log
EXIT0, format342files/0changes, rootFlutter+5package analyses clean; root2+
engine223+protocol15+Windows3=243unitpasses,14newRAMcontroller cases. Added late
bootstrap/earlier exit deadline and changed generation rejection coverage. An
intermediate full run caught an outdated assertion expecting old Ready afterloss;
updated to require current CloseBlocked, then the complete suite passed. Native
spawn/FS/SSH/process/UI/design/build/install remains unexecuted. Formatter warnings
for excludednestedwork remain recorded; no qualification of that checkout.
Independent read-only review follows; broadgoal and UI/MCP/tray tasks stay open.


- [x] T301 Исправить подтверждённый P2 worker_controller_review: конкурентные shutdown/waitClose могут вернуть2Closed, concrete connection отклоняет второйACK, а observer зависает после_closed guard. Регистрировать physicalClosed/ACK однократно, до ACK завершать всех уже созданных same-root close observers с сохранением истёкших deadlines; второе сообщение не требуется. Добавить strict-ACK RAM regressions для обоих порядков ответов и onExit после первогоACK, затем fullchecks/linkcheck/fresh independent review.

First completed worker_controller_review found1P2 T301. Fixed shared physical-close
settlement before ACK and duplicate acknowledgement; retained bounded correlations
absorb queued close replies, no dependence on delivery after exit. Four new RAM
cases enforce oneACK across both response orders, with/without control-stream exit.
Current total18newcontroller RAM cases. Expired observers preserve their result;
late callbacks cannot overwrite current physicalClosed status. T300/T301 await
fresh completed review. No native/isolate/UI/design acceptance claimed.


Worker controller final reviewed evidence: .local/worker-controller-reviewed-fixed-full.log
EXIT0, format342files/0changes, rootFlutter+5package analyses clean; root2+
engine227+protocol15+Windows3=247unitpasses including18newcontrollerRAMcases.
.local/worker-controller-reviewed-fixed-links.log EXIT0:1464total1463OK0errors1excluded;
scopedgitdiffcheckEXIT0CRLFwarningonly. Fresh completed read-only
worker_controller_fixed_review found0findings and independently confirmed T300/
T301 closure. Bounded controller/VMconnection ready for further integration only;
actualIsolate/native/FS/SSH/process/UI/design/platform/build/install/release not
qualified. Excludednestedwork lint warnings recorded, no suite pass claimed there.
Existing T258/T261 and UI/MCP/tray/suspend/removal tasks and fullgoal stay open.
Current UI legacy bootstrap remains to be replaced; no runnable-app claim.


### T258/T261/T273/T276: UI embedded-engine owner cutover

FoundationApp/bootstrap now use DesktopEngineHost→single EngineWorkerController
and issued EngineClient/EngineApiClient; removed all four old UI IPC/native
bootstrap/child-launch source files. Rebound automation/server/software and profile
consumers without changing their widgets/layout. Bootstrap has one30s monotonic
budget, format3 readiness and no old prepare/ensure/relaunch/backoff path. Engine
Gateway gains logical retired notification separate from physicalclose. Explicit
app exit requires actualRootClosed before UI cleanup/Exit; CloseBlocked cancels.
Final tray/hide/menu/continue-waiting, activation, MCP mode/publication and broader
parity remain open. No feature readiness/runnable/runtime claim yet.
13newpresentation unit cases +3actualgateway/proxyRAM retirement cases exercise
logical behavior only; no design/widget/native/isolate/realFS/SSH/process tests.
First full run found callback defaultname collision/unnecessaryimport; corrected.
Retirement loss test initially expected serverclose success despite lost reply
channel; fixed to require SERVICE_UNAVAILABLE, and3targeted cases pass. Mandatory
complete checks/linkcheck/fresh independent review follow.


- [x] T302 Исправить подтверждённый P2 ui_engine_cutover_review: запоздавший snapshot/read вызывал _connected и мог создать attachment после retirement без explicit retry. Разрешить создание attachment только явному connect; reads/mutations могут ждать уже начатый connect. Проверять epoch/current session перед вторым snapshot read и polling перед queued callback. RAM regression с retirement после первого read, поздним detach, отсутствием скрытого attachment и ровно одним attachment после explicit retry; повторить full/link checks/fresh review.

First completed ui_engine_cutover_review found1P2 T302. Corrected attachment
admission and pre-second-read/queued-poll guards. Two new units cover no attachment
from read/mutate and retirement after first typed snapshot read with delayed
physicaldetach; completingdetach does not reopen, explicitconnect opensone next
session. Existing units now explicitly establish their sessions. Total15newUI
units+3actualgateway retirement units. No additional product decision introduced;
remaining tray/MCP/activation/suspend and broadgoal still open.


UI cutover final reviewed evidence: .local/ui-engine-cutover-fresh-full.log EXIT0,
format342files/0changes; rootFlutter+5package analyses clean; root17+engine230+
protocol15+Windows3=265unitpasses (15newUIlogic+3gateway/proxyRAMretirement).
.local/ui-engine-cutover-fresh-links.log EXIT0:1464total1463OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarnings. Fresh completed independent read-only
ui_engine_cutover_fixed_review found0findings and confirmed T302. Bounded UI
cutover ready for further integration only, no native/isolate/FS/SSH/process/UI/
design/build/install/runtime/release qualification. Excludednestedwork lint
warnings do not imply testing. T258/T261/T273/T276 remain open for complete path/
parity/cleanup reconciliation with remaining tray/MCP/activation/suspend work;
actual UIcomposition uses desktop_engine_host.dart and engine_client.dart plus
portable worker_controller/worker_connection, not the originally planned UI worker
filenames. No new feature spec or compatibility facade introduced.


### T259/T275: actual Windows tray/app lifetime and private desktop status

Added DesktopLifetime policy + native MethodChannel adapter + DesktopApplication
root, same-HWND restoration/section routing and window-subtree detach separate
from the one Host lifetime. Windows runner owns notification icon/menu/keyboard
callbacks, Explorer recreation, hide guard, custom Exit/Stay and CloseBlocked
Wait/Force/Stay dialogs, physical-only normalfinish and explicit whole-processforce.
CommonControls6 manifest and systemlibs/UTF8source options added; no executable,
build/install/deploy/publish or native/UI/design run. Added private bounded
Host→Root desktopStatus counts, no names/secrets or owner attachment. Old app-level
exit observer removed; close-to-tray is root-owned, no AppExit blanket-success.
15newRAM policy units plus2engine desktopstatus units cover these paths. Initial
full run caught an obsolete fallback after a newer Open; coalescing intent now
suppresses it. Root status validates0..4MCP and null/0..250unresolved jobs. Full
checks/linkcheck/independent review still required; suspension/activation/MCP and
fullfeature/native/release readiness remain open.


Tray final pre-review checks: .local/desktop-tray-reviewed-full.log EXIT0;
format347files/0changes, rootFlutter+5package analyses clean, root33+engine232+
protocol15+Windows3=283unitpasses.16newRAM desktop-policy cases+2desktopstatus cases;
one added case prevents physical wait completion destroying a native modal prompt
before it returns. Excludednestedwork formatter lint-resolution warnings remain,
notqualified. Lychee .local/desktop-tray-links.log EXIT0:1466total1465OK0errors1excluded.
Native C++/CMake/manifest source inspected against MicrosoftAPI references and local
Flutter headers only; no C++build/link, native/isolate/tray/dialog/FS/SSH/process/
UI/design/build/install qualification. Fresh independent read-only review follows.


Tray/lifetime final reviewed evidence: .local/desktop-tray-reviewed-full.log EXIT0,
format347files/0changes, rootFlutter+5package analyses clean; root33+engine232+
protocol15+Windows3=283unitpasses incl16newRAM policy+2private desktopstatus units.
.local/desktop-tray-reviewed-links.log EXIT0:1466total1465OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarnings. Completed independent read-only desktop_tray_review
found0findings and bounded tray/lifetime/status readiness for further integration.
Native C++/CMake/manifest inspected statically; build/link/Win32/tray/dialog/isolate/
FS/SSH/process/UI/design/runtime/release acceptance unexecuted. Excludednestedwork
lint warnings remain and that checkout is not qualified. Actual tray lifetime is
now wired in main/DesktopApplication and runner; T259/T275 remain open for final
path/acceptance reconciliation with pending suspend/resume, activation, MCP and
packaging/cleanup. Main goal stays active; no native build/install/deploy/publish.


### T256/T265/T274: genuine embedded MCP pipe ownership foundation

Added EmbeddedPipeListener/Channel with dedicated actual Windows I/O worker,
bundle4/self/peer proof, descriptorPID pin, actualSID embedded8 namespace, one-peer
listener/no handle reuse,16retained slots/original5s budgets and physicalclose ACK.
Publication gate factory uses same actual app/root and peer revalidation. Primitive
NativePipe now rejects old v1 names and propagates sticky close failures for pipe,
peer, event/cancellation handles and partial creation; client drain uses inbound
quota and server outboundquota per MicrosoftFSCC.4newpureWindows units cover these
policies only (no native imports/dispatch). Existing MCP bootstrap no longer owns
or starts any child process; missingdiscovery/availableendpoint is unavailable.
User reconfirmed MCP depends on alreadyrunningServerDeck (includingtray); absence
is a connector-side failure, no response from absent service, no autoHost. This
also applies to unconfigured/no-grant mode; live-app binding/entry remains open.
No new feature/spec created. Broadendpoint/handshake/stdio/legacy cleanup remain
pending; existing old bundledrole/session wiring not claimed runnable.

Finalpre-review .local/embedded-pipe-final-full.log EXIT0: format350files/0changes,
rootFlutter+5package analyses clean; root33+engine232+protocol15+Windows7=
287unitpasses.4newWindows tests pure RAM; no native worker/isolate/IPC/FS/SSH/process/
UI/design/build/install/deploy execution. Excludednestedwork lint warnings recorded,
notqualified. Linkcheck and mandatory independent source review follow.


- [x] T303 Исправить подтверждённый P2 embedded_pipe_review: общий5s producer limit запрещал штатное idle read60s из McpServerChannel. Разделить read≤60s и proof/write/drain≤5s; partialframe остаётся5s у framing owner. Оригинальные absolute deadlines включают очереди. RAM regression handshake5→idle60→partial5, исправить текущий контракт, повторить full/link checks и fresh independent review.

First completed embedded_pipe_review found1P2 T303 idle60 compatibility. Producer
now accepts read≤60s with unchanged absolute deadline; proof/write/drain≤5s and
server frame-owned partial5 remain. One new RAM sequence case covers this existing
server/port contract; no polling workaround or new protocol/compatibility mode.


Embedded pipe final reviewed evidence: .local/embedded-pipe-reviewed-fixed-full.log
EXIT0, format350files/0changes; rootFlutter+5packageanalyses clean; root33+engine232+
protocol15+Windows8=288unitpasses,5newpureWindows policy units. Lychee
.local/embedded-pipe-reviewed-fixed-links.log EXIT0:1467total1466OK0errors1excluded;
scopeddiffcheckEXIT0CRLFwarning. Fresh completed independent read-only
embedded_pipe_fixed_review found0findings and confirmed T303. Foundation ready
for further integration only; no native/isolate/IPC/FFI/FS/SSH/process/UI/design/
build/install/runtime qualification. Excludednestedwork lint warnings recorded,
notqualified. NewMCP endpoint/client/entry/oldbindingremoval and broadgoal remain
open. User clarification preserved: absent ServerDeck gives no service response;
only connector/client can report local connection failure, without starting app.


### T257/T265: actual Host-owned MCP endpoint pool

Added neutral ownedlistener/discovery ports and McpEndpointPool using the existing
McpServerHandshake/McpServerChannel/registry, eight bind-before-publish slots,
Ready-only activation, badpeer isolation, physicalclose-before-rebind, retained
latebind/publish work and stop/remove/descriptorwipe ownership. Native listener
implements the port. Host/WorkspaceHostResources now create same-actual-services
McpApiServer after recovery, require activated/exact API/generation/workspace,
optional platform pool factory, publish-before-parent-ready acknowledgement and
final runtime proof, published-only MCP feature, synchronous stop and physical
pool drain before store/vault/metadata/lease. Windows factory/discovery I/O is
still pending, so Windows MCP feature staysfalse, not a fake/stub available path.
13newRAM units (9pool+4Host) use actual core authority/router/session/handshake
and fake I/O/services without Native/FS/Isar or domain effects. First full checks
found a test await-on-void/unneededimport and an unobserved fake read error in
lateaccept; corrected, then13targeted cases passed. Full checks/linkcheck/fresh
independent review follow. App must already run; no autoHost/child process added.


Endpoint-pool final pre-review checks: .local/mcp-endpoint-pool-final-full.log EXIT0,
format353files/0changes; rootFlutter+5package analyses clean; root33+engine245+
protocol15+Windows8=301unitpasses including13newRAM pool/Host cases. Windows8remain
puremetadata/policy tests, no native dispatch. Existing excludednestedwork lint
warnings remain/notqualified. Native discovery owner/Windows bootstrap factory,
new client/bootstrap/stdio entry, suspend/activation/cleanup and broadgoal open.
Linkcheck and independent review follow before bounded readiness conclusion.


First completed mcp_endpoint_pool_review found one P2: late accept could hide a failed peer disconnect after cached listener close success. T304 records independent peer/channel ownership, sticky physical failure and Host lease retention. Added two RAM regressions for this order; full checks and a fresh independent review remain required.


T304 implementation and fresh independent review completed: mcp_endpoint_pool_fixed_review found no findings and confirmed separate late peer/channel close ownership, sticky physical failure, Host CloseBlocked and lease retention. Full .local/mcp-endpoint-pool-fixed-full.log EXIT0: format353/0changes, root Flutter plus5package analyses clean, root33+engine247+protocol15+Windows8=303RAM unitpasses. No native/runtime qualification. Scoped diff check EXIT0 (CRLF warning only). Link gate remains open: three lychee runs, including --timeout120 --max-retries1, exit2 with1467total1464OK0errors1excluded2timeouts at existing Mozilla MPL FAQ/index links. T304 checkbox remains unchecked until this mandatory gate passes. Windows discovery/factory/client/stdio and broad goal remain open; no end-to-end MCP readiness claimed.


Final link gate recovered: .local/mcp-endpoint-pool-final-record-links.log EXIT0 after completed independent review. Earlier Mozilla timeouts were transient. T304 is complete; broad T257/T265 and Windows/stdio integration remain open.


### T305: concrete Windows MCP publication
Added ProtectedMcpDiscovery policy and fixed native WindowsMcpDiscoveryFile,
normal WindowsEngineBootstrap factory bound to actual retained runtime/lease/
vault/files, original pool/server/registry, PID/generation/workspace. File close
preserves unconfirmed handle failure from protected reads as well as writer/
removal; native read primitive reports that distinction to this concrete owner.
Writer owns CREATE_NEW object through write/flush/rename/failure cleanup and
checked close; removal compares and deletes same retained object. Added13RAM
policy cases only. Full checks, links and independent review required below.
No native dispatch/runtime readiness claimed; client/stdio/cleanup remain open.


T305 final pre-review checks: .local/mcp-publication-final-full.log EXIT0,
format356/0changes, root Flutter plus5package analyses clean; root33+engine260+
protocol15+Windows8=316RAM unitpasses, including13new protected publisher cases.
First full run found generic T? return type and fixture legacy missing buildId;
fixed,13targeted units passed, then full suites passed. Added sticky unexpected
native I/O RemoteError handling and reran full checks successfully. Formatting
initially used wrong package-relative paths; formatted correctly from root
before successful full runs. Linkcheck .local/mcp-publication-final-links.log
EXIT0 (1469total1468OK0errors1excluded). Scoped diff check EXIT0 with CRLFwarning.
Source-empty locald/MCP have no tests and are not counted as passing suites.
Excluded nested work lint warnings are not qualification of that checkout.
No native/isolate/IPC/DPAPI/ACL/FS/Isar/SSH/process/UI/design/build/run/install
checks executed; static source analysis only for Windows implementation. Fresh
independent review is still required; broad client/stdio/cleanup goal remains.


Completed independent read-only mcp_publication_review found0findings and
confirmed bounded T305 readiness. Reviewed actual baseline6changed+3newfiles,
requirements/contracts/implementation/13RAM acceptance cases and supplied logs.
T305 complete. Actual Windows protected file/DPAPI/ACL/rename/disposition/pipes/
CloseHandle/isolate/build/run qualification is not established. Next work is
client/stdio/headless entry and oldbinding removal, not a new spec or a second
service. Whole goal remains active and broad T265/T274/T276 are not complete.


### T306: portable MCP-only client foundation
Added engine mcp/client.dart plus private bootstrap/grant/RPC parts, fixed-role
proof and actual channel/descriptor binding, one protected read-only grant proof,
16pending serialized request writer and one bounded/correlated response reader,
physical work/proof/credential ownership through close and no reconnect/replay.
RAM unit cases use one scripted peer and memory file/protection providers only;
no main Host/database, native/Isar/FS/isolate/process/SSH/UI/design runs. Current
Windows bootstrap/gateway still uses old client source until the next cutover;
no full MCP runtime readiness is claimed. Full checks/linkcheck/review follow.


T306 pre-review evidence: .local/mcp-client-fixed-full.log EXIT0, repository
format361/0changes, root Flutter plus5package analyses clean; root33+engine276+
protocol15+Windows8=332RAM unitpasses including16new client cases. First full
run failed missing host_trust protocol import and lint cleanup; corrected,
14targeted client cases passed, then two additional frame/envelope bound cases
and grant original-budget check were included in the successful final full run.
No source-empty locald/MCP tests are counted as passed. Excluded nested work lint
warnings are not qualification of that checkout. Lychee .local/mcp-client-links.log
EXIT0:1469total1468OK0errors1excluded. Scoped diff check EXIT0 CRLFwarning only.
Client tests use a scripted RAM peer, actual wire DTO/transcript MAC primitives
and fake memory file/protection providers; no Host/store/native/isolate/IPC/FS/
Isar/SSH/process/UI/design/build/run/install checks. Independent review follows;
actual Windows client/stdio cutover and full goal remain open.


First completed mcp_client_review found1P2 final capture after deadline check. T307 records capture-before-final-check/delivery and deterministic nested-collection fake-clock regression. First report was not a clean readiness result; full checks and fresh review required after this fix.


T306/T307 final evidence: .local/mcp-client-reviewed-fixed-full.log EXIT0,
format361/0changes, clean root Flutter and5package analyses, root33+engine277+
protocol15+Windows8=333RAMunitpasses including17client cases. First independent
mcp_client_review found1P2 capture-after-deadline; T307 fixed it and added the
production-helper nested fake-clock boundary regression. Fresh completed
mcp_client_fixed_review found0findings and confirmed bounded foundation readiness.
Lychee .local/mcp-client-reviewed-fixed-links.log EXIT0:1469total1468OK0err1excluded.
No native/Host/Isar/FS/isolate/process/SSH/UI/design/build/install qualification.
Windows bootstrap/gateway migration, stdio/headless entry and old source removal
remain open T265/T274/T276; whole goal stays active, no end-to-end MCP claim.


### T308: Windows MCP connector/gateway cutover
New WindowsMcpConnector derives actual current executable/owner, verifies bundle4,
retains metadata/vault and protected discovery2, owns native connecting attempts
before ready and fixed5s connection work. McpProcessBootstrap now uses it and the
portable client; grantless mode also connects/Ready-checks before gateway. New
reusable entry replaces separate bin/mcp.dart. Old ten Windows build/bootstrap/
operational client/pipe-worker source files deleted; no compatibility adapters.
Client/gateway logical retirement stops idle stdio; all fixed/builtin output
gets native live publication guard, domain output retains grant-policy ping,
actual stdout settlement precedes lease release; EOF cleanup failure is nonzero.
11new RAM unit cases use scripted peer+memory ports/streams, no native dispatch.
First full failed extension import/nullable calls; corrected, targeted first
failed untyped empty map fixtures, corrected, then11targeted cases passed. Full
rerun/linkcheck/independent review required. Main/headless entry and remaining
cleanup still open; no single-exe MCP/native/runtime qualification claimed.


T309 found during source inspection: safe WindowsProtectedFiles error conversion
hid PHYSICAL_CLOSE_UNCONFIRMED from credential reads. Native-only cleanup
notification now latches both desktop/stdio owners; checked writer/copy/replace
CloseHandle failures retain the same internal marker. Existing Host metadata
failure RAM cases exercise final lease-retention policy; native callback/marker
production is only statically checked. Intermediate .local/mcp-cutover-fixed-full.log
EXIT0 preceded this last native lifecycle change, so final rerun is required.


T308/T309 pre-review evidence: .local/mcp-cutover-final-full.log EXIT0, repository
format353/0changes, root Flutter plus5package analyses clean. Root33+engine277+
MCP11+protocol15+Windows8=344RAMunitpasses,11new gateway/stdio cases; source-empty
locald has no testpass claim. First full failed missing extension imports and
nullable publication access, fixed; targeted first failed untyped empty-map
fixtures, fixed, then11targeted cases passed. Intermediate full passed before
final native file cleanup propagation; final full above includes T309 changes.
Lychee .local/mcp-cutover-final-links.log EXIT0:1469total1468OK0errors1excluded.
Scoped diffcheck EXIT0, CRLFwarnings only. Current-source rg has no deleted
Windows client/bootstrap/worker imports; engine's new client_bootstrap part is
unrelated to the deleted Windows file. No Host/store/realFS/native/isolate/pipe/
DPAPI/ACL/Isar/SSH/process/UI/design/build/run/install checks. Native source and
composition are statically checked only; excluded nestedwork notqualified.
Fresh independent review required. Main/headless branch and remaining legacy
artifact/source cleanup stay open; whole goal/end-to-end MCP notcomplete.


First completed mcp_cutover_review found2P2: fixed RPC/overload no-op publication
bypass and native worker identity-factory false clean close. T310 adds real fixed
gate/proof and updates old gateway contract exceptions; two new RAM cases plus
stronger existing remote-error checks exercise failure/acquisition at16pending.
T311 conservatively latches worker factory uncertainty so close fails and the
connector cannot advance endpoints. Native branch is static-only; no Win32
failure injection claim. Full/link checks and a fresh review remain required.


T311 also covers the peer factory: RetainedProcessIdentity.open explicitly
reports PHYSICAL_CLOSE_UNCONFIRMED if its partial process-handle cleanup fails.
NativePipe latches only that uncertainty when opening a peer; an ordinary vanished
peer with confirmed cleanup remains isolated to its connection. Native pipe
worker self-factory failure stays conservatively sticky. Desktop root and its
runtime gate-factory callback retain the explicit uncertainty until final
metadata disposal, so it cannot release a held writer lease without confirmation.
StdIO root already rejects a clean close on failed identity/gate creation. This
is static native lifecycle evidence only, not a native failure-injection pass.
The unused old McpServer.forTesting timeout constructor is removed; current RAM
stdio tests exercise production30/5/35second policy without runtime overrides.


Completed mcp_cutover_fixed_review confirmed T310/T311 fixes but found1P2 queued grant expiry fallback before any gate/proof. T312 records settle/release-before-replacement and a fresh protected fixed fallback with one original writer budget. Added RAM queued-domain/UTC-expiry/healthy-vs-failed-proof regression. Further full/link checks and fresh independent review required; previous report notclean.


T312 final pre-review evidence: .local/mcp-cutover-fallback-final-full.log EXIT0,
format353/0changes, clean root Flutter plus5package analyses; root33+engine277+
MCP15+protocol15+Windows8=348RAMunitpasses. Two added cases cover queued UTC grant
expiry with healthy/failed native proof and policy-ping denial after original
lease acquisition; fake gate refuses recursive/concurrent acquisition, proving
release-before-replacement ordering. No private fallback data or extra domain
request is sent. Earlier .local/mcp-cutover-fallback-fixed-full.log passed347
before this additional gate-ordering case; final log above is authoritative.
Fresh independent review and final links required; no native qualification or
main/headless single-exe readiness claim.


Completed fresh independent read-only mcp_fallback_fixed_review found0findings
and confirmed bounded T308-T312 readiness. Initial review found2P2 T310/T311;
second found1P2 T312, all fixed without erasing history. Final authoritative
.local/mcp-cutover-fallback-final-full.log EXIT0: format353/0changes, clean root
Flutter+5package analyses, root33+engine277+MCP15+protocol15+Windows8=348RAMunits.
.local/mcp-cutover-fallback-final-links.log EXIT0:1469total1468OK0err1excluded.
Review verified exact16changed+3new+11deleted sources/docs against scopedbaseline;
no deletedproductionimports/aliases. No native/Win32/DPAPI/ACL/FS/Host/Isar/isolate/
process/SSH/UI/widget/design/build/install/headless runtime qualification. Excluded
nestedwork and source-emptylocald notqualified. Normal main/headless mode binding
T274 and remaining T276artifact/protocol/sourcecleanup remain mandatory/open;
whole goal is active and single-exe MCP command is not yet declared runnable.


## Aggregate audit — 2026-10-31

Current scope: the embedded amendment of existing001 with related002/021,
T253–T399. This is an implementation/evidence reconciliation, not a new feature,
a native qualification report or a release. Historical T001–T252 native/manual
and001.1 gates are not current execution obligations and are not marked passed.
The later explicit user limit is static plus current-task RAM unit tests only;
no widget/design/UI tests were added or run. No backend/foreign003/worktree/
installed app/process changes, build/install/deploy or commits were performed.

### Current checks and evidence provenance

The latest application change is T396/T397. Its complete run is
`.local/legacy-input-first-full.log` and `.exit=0`, invoked from the repository:

```powershell
$env:SERVERDECK_FLUTTER_ROOT = 'H:/flutter/flutter'
./tools/test-unit.ps1
```

The script actually ran repository `dart format --output=none
--set-exit-if-changed .`, `flutter analyze`, `flutter test`, the16group PS RAM
bundle suite and analyze/full unit suites for the exact current four packages.
Format418/0changed; Flutter and engine/MCP/protocol/Windows analyses clean;
root86+engine606+MCP15+protocol51+Windows8=766Dart cases. Exactly one engine case,
`test/platform_boundary_test.dart`, reads source files and is static; the other
765Dart cases and16PS groups are RAM units. Source-format synthetic Isar bytes do
not open a native DB. SDK/test-runner processes are the ordinary check harness,
not product/process fixtures. No skip or empty-package suite is counted as pass.
The obsolete source-empty locald package is no longer resolved/analyzed/tested.
Formatter warnings about missing lint includes in nested historical `work/`
remain visible; they are not current-package analysis errors or native proof.

This first complete run succeeded; no addressed-only rerun was needed. No
application code has changed during this aggregate documentation audit, so that
run remains the current source evidence, rather than a newly claimed execution.
Earlier red runs/fixes and narrower counts remain in task history.

Six changed PS scripts parsed without errors; pure metadata evaluation yielded
exactly engine/MCP/protocol/Windows and root+four package lock paths
(`.local/legacy-input-static.json`). CI/build use that shared set. The workflow,
Windows build, native runtime and installed command were not executed. Prior
MSVC `/Zs` logs establish syntax only for the runner increments they cover.

Latest pre-audit links were checked with
`lychee "specs/**/*.md" packages/serverdeck_mcp/README.md`:
`.local/legacy-input-accepted-links.log/.exit=0`,1488total/1487OK/0errors/1excluded.
The separate T328 guide check had22/22OK; its combined specs/guides check had
1506total/1505OK/0errors/1excluded. Counts describe their stated inputs, not the
same command. This aggregate doc increment requires its own final link check and
completed independent review; until recorded it is not an accepted final gate.

Logs/baselines/hashes under `.local/` are ignored local evidence, not published
CI artifacts. The durable task history records command, result, scope and review
outcomes. A dirty checkout and source-only evidence do not prove a release build.

### Current-source and corrective-chain map

| Area | Current source / unit evidence | Accepted chain |
| --- | --- | --- |
| Private worker, Root, gateway, host and close ownership | engine hosting worker_root/controller/gateway/connection, engine_host, host_resources, authority, sessions; hosting worker/host units and root desktop_engine_host/owner_snapshot_policy units | T277–T319 foundations; T320/T332; T333–T350; T321 aggregate |
| Same-worker suspend/resume | desktop_lifecycle; native WM_POWERBROADCAST static wiring; worker/Host/services/pool lifecycle units, job reopen/control cases | T333–T350, T321 |
| Shared target sampler and fresh reads | remote read service/pool/clock/cache/queues; shared_reads, read_isolation_bounds, read_aggregate_budget and current actual-router tests | T322 and T357–T368 sampler/IO corrections |
| Actual repository and all24 MCP tools/permissions | StateStore common writer/preflight/custody; actual_state_store/failure_matrix; actual_mcp_setup/router tests and framed RAM executor peer | T323, T369–T383, T396 |
| Correlated jobs/observations/recovery/occupancy | automation jobs/job_session/job_observations/job controls; strict executor jobs DTO; actual router/control/reopen matrices and controller units | T384–T395, T324/T331/T388 aggregate |
| Full retained schema3 graph | full_schema3_retention, workspace_snapshot, store_preopen, actual store and reopen tests | T325 plus storage prerequisite chain |
| Capabilities and honest platform boundary | capability_snapshot and Host/worker/desktop projection; platform_boundary static unit, capability/lifecycle RAM units | T269/T326, T351–T356, T321 |
| Current docs/pins/input set | existing plan/current storage/platform docs; current-packages PS policy, bundle metadata tests, grant config protocol/actual-owner units | T328/T329, T396/T397 |

The ranges describe provenance, not blanket proof from checkboxes. Source and
unit paths named below and the completed independent source/aggregate reviews
were consulted. T398 is still unresolved; the final whole-scope review is not
replaced by earlier component acceptance.

### Requirement → design/contract → implementation/acceptance

All35 stable keys have tasks and normative contracts. “RAM/static evidence”
means the stated implementation is covered in the permitted scope; it never
means real OS/runtime qualification. “Partial” prevents whole-goal completion.

| Key | Design / contract | Current evidence and task chain | Assessment |
| --- | --- | --- | --- |
| FR-SVC-EMB-01 | embedded-engine worker/ownership; embedded-host mode | main/entry_mode, Windows runner static dispatch; worker_root/controller; T257/T258/T274, T320/T321 | RAM/static evidence |
| FR-SVC-EMB-02 | embedded-engine shared authorized domain | control_services, in_process_gateway, StateStore, actual24-tool/owner matrices; T255/T257/T273, T322/T323 | RAM/static evidence |
| FR-SVC-EMB-03 | lease/session/shared sampler limits | engine_host, session_registry, remote shared work/clock;64/session256global with stricter paths retained; T257/T260/T320/T322 | RAM/static evidence |
| FR-SVC-EMB-04 | desktop lifecycle and common shutdown | desktop_lifecycle tests, worker/Host/pool pause units, native menu/power wiring static; T259/T275/T321 | RAM/static evidence |
| FR-SVC-EMB-05 | embedded-migration/schema3 custody | workspace_snapshot/preflight, key custody, full16family retention, revoked-grant/permit reopen; T262/T263/T325/T387 | RAM/static evidence |
| FR-SVC-EMB-06 | exact schema3/refusal/single writer | actual preopen and fault matrix; schemas1/2/99, wrong credential/wrapper, close reservation; T262/T264/T325 | RAM/static evidence |
| FR-SVC-EMB-07 | embedded-host MCP-only endpoint/current exe | client/bootstrap/gateway, protected discovery, strict owner config;24tool permission matrices; T265/T266/T268/T323/T396 | RAM/static evidence |
| FR-SVC-EMB-08 | embedded-host correlated Root control/unknown occupancy | jobs/CAS/control actor reproof and actual ACK-loss/reconcile/reopen tests; T267/T324/T331/T386–T395 | RAM/static evidence |
| FR-SVC-EMB-09 | generation/target/trust/grant/event fence | sessions/target changes/read observations/job observation/controller; late/cancel-interest cases; T260/T273/T322/T324/T388 | RAM/static evidence |
| FR-SVC-EMB-10 | embedded-platforms closed six-row capabilities | capability_snapshot/Host/worker/desktop; all six rows and vault/lifecycle units; T269/T270/T326/T328 | RAM/static evidence |
| FR-SVC-EMB-11 | unsupported Web/no backend fallback | non-Windows capability rows fail before Windows provider use; platform boundary/import scan; T269/T326/T328 | RAM/static evidence |
| FR-SVC-EMB-12 | embedded plan phases and current evidence | plan reconciliation, preserved history and this journal; T255/T270/T271/T272/T329/T330/T399 | Partial: aggregate review open |
| FR-SVC-EMB-13 | constitutionVII/current check scope | exact tools/test-unit and unit.yml;766Dart(1static765RAM)+16PS; no product-native/UI execution; T253/T271/T397 | Permitted check evidence |
| FR-SVC-EMB-14 | schema3-only/no runtime/API compatibility | production imports/entries have no legacy mode; strict schema/data refusal and owner config; T262/T325/T396 | RAM/static evidence; cleanup separate |
| FR-SVC-EMB-15 | remove replaced runtime/helpers/tests | current four input set/manifests fixed; old generated/cache and orphan bytecode remain; T276/T327/T397/T398 | Partial: residue unresolved |
| AC-SVC-EMB-01 | one workspace/Host/sampler; busy fallback | engine_host/worker/controller/sessions actual-service and shared-read units; verified busy policy avoids second writer; T257/T260/T320/T322 | RAM/static evidence |
| AC-SVC-EMB-02 | window/Exit/suspend/crash distinct | desktop_lifecycle, host_lifecycle, worker/SSH service pause and job reopen units; T259/T261/T321/T387 | RAM/static evidence |
| AC-SVC-EMB-03 | safe vault/store/lease failure and owned close | store_preopen/actual_store_failure_matrix, Host and worker CloseBlocked/proof tests; T254/T256/T257/T261 | RAM/static evidence |
| AC-SVC-EMB-04 | exact records/credentials/trust bindings | nonempty16family raw+protectedfile retention and actual semantic reopen; T262/T263/T325 | RAM/static evidence |
| AC-SVC-EMB-05 | same writer namespace blocks old owner | existing Windows mutex/engine_platform binding plus RAM busy/ownership/no-second-store policy; no old locald process or kill path; T256/T262/T320 | RAM/static evidence; no real process test |
| AC-SVC-EMB-06 | reject unsupported format before writer | native-format synthetic parser and actual semantic preflight/store refusal; all input files untouched; safe copy/docs; T264/T325/T328 | RAM/static evidence |
| AC-SVC-EMB-07 |24 tools/permissions/current grant/no owner forgery | actual router authority/current-target matrices and gateway output fences; T268/T323/T377–T383/T396 | RAM/static evidence |
| AC-SVC-EMB-08 | ACK loss/unknown occupancy/correlated recovery | actual framed-peer ACK-loss/unknown/failed-reconcile and CAS races; T324/T331/T386/T387/T390/T392/T393 | RAM/static evidence |
| AC-SVC-EMB-09 | observation independent of effect/permission | detached/stale sibling projection, current generation, idempotent apply receipt, interest-loss control tests; T267/T324/T331/T384–T395 | RAM/static evidence |
| AC-SVC-EMB-10 | engine/UI/unsupported-platform import boundary | platform_boundary source scan and declared platform factory units; engine pure Dart, UI no DB/SSH ownership; T254/T269/T326 | Static plus RAM evidence |
| AC-SVC-EMB-11 | mobile foreground baseline/vault blocks secrets | six-row snapshot + locked/unavailable probe/restore cases; no mobile host delivery; T269/T326/T328 | RAM/static boundary evidence |
| AC-SVC-EMB-12 | Web unsupported; ordinary app no cloud/service | current composition/unsupported rows and docs; no backend/remote-node implementation; T269/T270/T328 | RAM/static boundary evidence |
| AC-SVC-EMB-13 | same executable MCP/no owner IPC/store | entry_mode tests, runner static dispatch, connector/gateway/grant current-owner config regressions; T274/T308–T312/T396 | RAM/static evidence |
| AC-SVC-EMB-14 | full tray/current-window/status/Exit/fallback | desktop_lifecycle tests and native menu/callback/status wiring inspected statically; T259/T275/T349/T350 | RAM/static evidence; no native tray run |
| AC-SVC-EMB-15 | exact current source/build/CI inputs/no facades | shared four package/five lock set, former bundle negative guards, old manifests removed; residual generated code/cache remains; T276/T327/T397/T398 | Partial: residue unresolved |
| SC-SVC-EMB-01 | no daemon/second owner/duplicate sampler | actual shared services/target reads, Host/worker/secondary policy tests; T320/T321/T322 | RAM/static evidence |
| SC-SVC-EMB-02 | no data/trust/secret loss on target reopen/refusal | full nonempty schema3 retention plus preopen/semantic/custody faults; T325 | RAM/static evidence |
| SC-SVC-EMB-03 | all tools positive/denied through engine | catalog24 and actual owner/MCP/Root actor matrices; current config delivered/rejected correctly; T323/T373/T377–T383/T396 | RAM/static evidence |
| SC-SVC-EMB-04 | uncertain outcomes visible/no duplicate effect | controller observation, actual status/reconcile/reopen/handoff/CAS/ACK-loss tests; T324/T331/T388 | RAM/static evidence |
| SC-SVC-EMB-05 | all six rows honest | capability matrix/closed schema/unsupported-start tests and current instructions; T269/T326/T328 | RAM/static boundary evidence |

### Parent-task reconciliation candidates

Existing checkboxes are not changed by this table. These are evidence-backed
candidates for the required independent aggregate assessment, not self-issued
final acceptance. Named paths are actual current decomposition; earlier planned
filenames such as adoption_test/recovery_view/gateway_parity may be covered by
current split files rather than introducing unused compatibility facades.

| Parent task | Current evidence / residual gate |
| --- | --- |
| T253 | Current exact full runner/workflow uses static/RAM only; historical native inputs not selected; accepted source/task chain |
| T254 | engine platform/ports, authority, managed vault and opaque owner capability; current custody/close/session units |
| T255 | actual engine domain/services and common StateStore; original production locald lib has no source entry; T322/T323/T325; generated residue belongs to T398 |
| T256 | Windows engine_platform/engine_worker/security/DPAPI/mutex and pinned Isar adapter; port/custody/static boundaries; no native qualification |
| T257 | EngineHost/in_process_gateway/registry budgets, recovery before Ready and physical CloseBlocked; Host/worker/current factory units |
| T258 | DesktopEngineHost/engine_client/bootstrap_controller, private Root gateway and fresh window owner; actual owner/readiness/snapshot policy units |
| T259 | DesktopLifetime common shutdown10s/fallback/window lifetime, native tray static; desktop/Host lifecycle and T321 |
| T260 | current shared remote reads and target identity plus safe busy instance policy; T320/T322; no activation service was invented |
| T261 | current full Host/worker/actual-service/late reply/power/ownership/close RAM matrices, accepted T321/T324/T331 |
| T262 | actual workspace_creation/preflight/StateStore exact schema3 and same mutex/path/custody; T325 plus preopen tests |
| T263 | full_schema3_retention all16 nonempty plus actual job reopen/permit/revocation; T325/T387 |
| T264 | current storage guide and safe readiness/error copy preserve refusal/busy input; T328 accepted |
| T265 | embedded_build_bundle/embedded_discovery/embedded_pipe, runtime gate and grant authentication/current app role; accepted MCP chain plus T396 |
| T266 | current MCP bootstrap requires live app for configured/unconfigured startup; no launch/reconnect; protected/current grant and writer output fences |
| T267 | actual jobs/CAS/intent/control/observation/reopen; T324/T331/T386–T395 accepted |
| T268 | actual24tool positive/denial and authority/loss matrices plus shared gateway output gates; T323/T324/T331 |
| T269 | six-row capability and static import boundary; T326 accepted |
| T270 | README/current platform guide and honest unsupported future adapters; T328 accepted |
| T271 | current shared four source packages/five locks, format4 single app bundle/native/notices guards; T397 plus earlier manifest/runner units; no build performed |
| T272 | Partial: this journal/link and final whole-scope independent review plus cleanup resolution not complete |
| T273 | current typed reads/operations/cursors/interest cancellation over shared real services; T322/T323 plus owner_snapshot_policy units; no new general watch API |
| T274 | existing accepted current main/mode/headless runner static dispatch and argument/stdio RAM tests |
| T275 | full native tray menu/callbacks/status static and actual DesktopLifetime policy units; T349/T350/T321 accepted; native runtime not tested |
| T276 | Partial: source/bootstrap/manifests/current inputs removed; old .dart_tool generated source/snapshots and removed-runner bytecode still present; T398 |

### Analyze/Converge and remaining boundaries

Analyze examined35 stable FR/AC/SC keys against the current embedded plan and
145task chains T253–T397, with eight governing constitution principles. All35
have task coverage; no new mandatory product/architecture decision was identified
in this reconciliation. This is coverage, not a statement that every requirement
is achieved. The historical client/locald text is explicitly superseded; it is
not an invitation to support both protocols. Accepted T329 corrected the actual
4.1.0 dartssh2 pin; no dependency upgrade was performed.

The12 architecture/validation decisions assessed were: portable domain engine;
one private worker/Host; internal owner capability; grant-only external MCP;
one workspace writer; shared sampler/budgets; physical deadline/close ownership;
OS vault/schema3 preservation; unknown job occupancy/recovery; app/tray/Exit;
format4 verified runtime/notices; six platform rows with scoped static/RAM checks.
Current Converge10 appended only T398/T399 under Phase10: two partial findings
(one HIGH, one MEDIUM), outcome `tasks_appended`, not `converged`. This Implement
pass addresses T399's evidence work; acceptance remains pending aggregate review.
No spec/plan/application source was changed by the Converge stage.

Read-only import/part inventory found232production Dart files reachable from main
plus97 current test/support roots, no missing local URI. This does not prove that
every public symbol is used. Current production scans find former executable/
package names only in explicit refusal guards and negative tests; the old owner
configuration parser found by the caller audit was actually fixed in T396.
Target native-format byte fixtures are current synthetic parser tests with real
callers and no native DB/file/process fixture; they must not be discarded as old
runtime code merely because their filenames include native.

Remaining filesystem inventory:17generated files under the old locald .dart_tool,
including generated Dart source and compiled snapshots, plus22 orphan .pyc files
under tools/executor. These paths are excluded from current four-package build/
unit/CI inputs but still constitute requested cleanup residue. The earlier
automatic approval review rejected broad recursive legacy/native-backup cleanup;
this audit does not retry it through another shell, API or file-by-file equivalent.
The current bounded correction removed only four individually named unused
manifest files; it did not resolve that rejected residual cleanup. No data files,
foreign worktree/process or installed003 artifacts were touched.

Therefore T398/T327/T276 and final aggregate completion remain open. A fresh
whole-scope reviewer must assess this complete matrix/current source and each
candidate parent closure, including any missing mandatory decision or regression.
An inconclusive/interrupted review is not a clean result. Required fixes trigger
applicable checks and another independent review; no current test result proves
native delivery, actual isolate/IPC/FFI/DPAPI/ACL/Isar/SSH, OS sleep/wake/tray/UI,
Python/systemd qualification, hosted CI execution, build/install or release.

Spec Kit artifacts remain in the existing feature. Specify/Clarify and current
constitution/plan/task amendments are recorded in their original files and review
history. The built-in requirements checklist has22checked items; custom
embedded-architecture has12reviewer-owned unchecked quality markers. Their status
is reported as-is: prior continuation approval does not mean final acceptance,
and Implement does not alter their markers. The final reviewer must assess those
criteria as requirements quality rather than infer success from task checkboxes.


### First aggregate review and governance correction

Completed independent embedded_whole_scope_aggregate_review inspected the current
implementation,35requirement matrix,24parents,12quality criteria and389unchanged
source/test/tool hashes. It found two items:known HIGH cleanup T398, and LOW
incorrect current governance pointers. No additional confirmed behavioral defect
or missing mandatory product/architecture decision was identified. This is not a
clean full-goal completion report: the known HIGH cleanup remains unresolved.

Actual `.specify/memory/constitution.md` is Version4.3.0, amended2026-10-30. Its
footer and Sync Impact Report are authoritative; the earlier requested review
scope and current-pointer text incorrectly said4.2.0. Current embedded plan
header/Constitution Check/pin note, this current journal introduction and CHK012
now reference4.3.0. Historical increment/version claims remain as originally
recorded; this paragraph corrects their use as a current governing baseline.
The constitution itself and normative rules were not changed by this correction.

Reviewer found CHK001–CHK011 sufficiently specified and CHK012 sufficient in
mandatory decisions with the version pointer defect above. The12reviewer-owned
markers remain untouched; they are not implementation checkboxes. Parent verdicts
support T255–T271/T273–T275 in permitted static/RAM scope only after this document
fix passes links and fresh review. T272/T276, T327/T330/T398/T399 remain open at
this point. No parent checkbox is changed on the basis of a merely pending review.


### Fresh aggregate review and supported parent closures

Completed embedded_governance_fixed_aggregate_review found only the known HIGH
T398 residue and no new confirmed document/source finding. T400 governance pointer
correction is accepted: current4.3.0, unchanged normative constitution, historical
records preserved, twelve quality markers unchanged. All389source/test/tool hashes
matched. The review explicitly supports recording the18parent closures
T255–T268,T270,T271,T273,T275 in implementation/static/RAM scope. These are now
marked in Tasks001, in addition to already closed T253/T254/T269/T274.

T272/T276 and T327/T330/T398 remain open. The current Matrix assessments still
separate permitted evidence from native qualification. Requirements quality is
sufficient across all12criteria; marker state is preserved as reviewer-owned
history, not used to claim implementation completion. Follow-up Analyze/Converge
and final evidence-record review remain necessary for T399, not a waiver of T398.


### Follow-up Analyze/Converge and final record boundaries

After the fresh review's supported parent closures and T400 correction, follow-up
Analyze read the resulting spec/plan/tasks/current constitution without writing:
35/35semantic requirement coverage,400unique tasks/148current chains, current4.3.0,
unchanged12quality markers,389matching source/test/tool hashes and no new confirmed
mandatory decision/behavioral gap. The fixed current governance pointers are not
confused with historical metadata. This does not turn known cleanup into success.

Follow-up Converge11 inspected that resulting state and appended only Phase11/T401
for the same known partial HIGH CG-12. It changed no prior task/history or app/
spec/plan source. Outcome is tasks_appended, not converged. T401 carries the same
T398 external cleanup boundary; it is not a new product feature or permission to
bypass the earlier rejected operation. No silent reduction of required cleanup
or alternative deletion was attempted.

Current parent tally is22of24 T253–T276 accepted in permitted static/RAM scope;
T272 and T276 remain open. T327/T330/T398/T399/T401 likewise remain open. Although
T399's current journal/matrix/follow-up work is done, its full review/fix closure
cannot be claimed while the HIGH cleanup finding persists. This record preserves
the complete goal, including physical removal of required old-code artifacts.

The final documentation link gate is
`.local/aggregate-final-record-links.log/.exit`; its actual result and the final
independent record review must be read rather than assumed. Source remains the
same389hash inventory covered by the actual418-format/766Dart+16PS full pass;
no repeat application execution is claimed for this docs-only record. Current
workflow/SDK/test-runner execution is distinct from unperformed native/product/
SSH/FS/isolate/UI/build/install/release qualification. No commit was requested.


## Archival resolution and final verification — 2026-11-01

The user explicitly authorized archival when deletion is unavailable. The existing
39-file inventory was revalidated against current paths, missing Python sources,
expected old-package file set, reparse/path boundaries and389unchanged active
source/test/tool hashes. The complete obsolete locald directory and22named orphan
bytecode files were moved, using native PowerShell within one shell, to
`H:/projects/unng/serverdeck-legacy-archive/2026-11-01-f5f10ba8ae434759ab4dbb02d3d3cf15`.
The external archive is not a source tree, compatibility facade or build input.

The external manifest preserves every original relative path, byte length and
SHA256. All39destination hashes match; all39original files and the old locald
package directory are absent. This is reversible user-authorized maintenance,
not a test using real FS/Isar/native product fixtures. No current source, database,
secret/trust binding, runtime/notices guard, foreign003/worktree/process or backend
was changed. The earlier rejected deletion was not retried; the user supplied a
new allowed action. Former blocker statements above describe the preceding state.

Current closure of CG-12/T398/T401/T327/T276 now depends on the fresh full source/
input checks, links and independent aggregate review. Final T272/T330/T399 are
also held until those results and final Analyze/Converge/evidence are established.
The12reviewer-owned quality markers remain untouched; their requirements-quality
assessment is already sufficient, distinct from implementation acceptance.


Fresh post-archive checks actually completed in
`.local/archive-completion-full.log/.exit=0`: format418/0changed, clean Flutter+
four package analyses,86+606+15+51+8=766Dart(one static765RAM)+16PSRAMgroups.
No addressed-only run was needed. The formatter still reports historical nested
work/ lint includes; active analyses succeeded. No empty suite or native/UI/design
case is counted as a pass. Archive verification after the full run still confirms
39matching destination hashes,39absent source paths, absent old package directory
and389unchanged source/test/tool hashes. Links in
`.local/archive-completion-links.log/.exit=0`:1484total1483OK0errors1excluded.
Fresh independent aggregate cleanup/final-readiness review is pending.


## Final acceptance record — 2026-11-01

Completed fresh independent archive_cleanup_final_aggregate_review found no
findings and accepted the existing embedded implementation in its authorized
static/RAM scope. The reviewer read applicable001/002/021/current4.3.0 contracts,
actual archive and current composition/acceptance paths, fresh logs and the35key
matrix. All39archive hashes/lengths matched, all39original paths and old locald
root were absent, and all389active source/test/tool hashes matched. The archive
is external to the client repository and current build/test/runtime/CI inputs.
This closes the previous HIGH CG-12 without erasing its history or waiving the
user's full source-removal goal. The user's new explicit instruction authorized
this reversible archive when deletion was unavailable.

The empty obsolete `packages/serverdeck_mcp/bin` directory was subsequently
archived too, with no contained files; its absence and external empty directory
are verified and recorded by the external manifest. File count remains39 and
all hashes unchanged. No current source changed; the same successful complete
source/test gate and389hash inventory apply. Both obsolete entry directories
named by T276 are now absent.

Final Analyze was actually run read-only on the resulting spec/plan/tasks/current
constitution:35/35semantic requirement coverage,401unique task IDs/149current
chains,0duplicates,0new mandatory-decision/ambiguity/critical findings, current
4.3.0 and unchanged12quality markers. The subsequent final Converge inspected
35requirements,12plan/validation decisions,8constitution principles and149current
task chains:0missing/partial/contradicting/unrequested implementation findings.
Its outcome is `converged`;0tasks appended, Tasks001 bytes unchanged in that
stage. Task status writes afterward are the separate Implement record step.

All35current FR/AC/SC are accepted within the permitted implementation/static/
RAM boundary. The earlier matrix's partial assessments for FR-SVC-EMB-12,
FR-SVC-EMB-15 and AC-SVC-EMB-15 describe2026-10-31 before archival and final checks;
their current assessment is satisfied. Their source/contract/task mappings are
unchanged. Source cleanup, evidence reconciliation and final review now support
T272/T276/T327/T330/T398/T399/T401 closures. All24original embedded parent tasks
and149current tasks T253–T401 are checked. Historical T001–T252 native/manual/
Q01–Q12 gates keep their own status and are not represented as executed here.

The authoritative fresh full command remains
`$env:SERVERDECK_FLUTTER_ROOT='H:/flutter/flutter'; ./tools/test-unit.ps1`:
`.local/archive-completion-full.log/.exit=0`,418formatted/0changed; clean Flutter+
four package analyses;root86+engine606+MCP15+protocol51+Windows8=766Dart cases
(one static source scan,765RAM)+16PSRAMgroups. No addressed run was needed.
Historical nested work/ lint include warnings remain visible; no current analysis
failure, skipped case or empty suite is counted as success. Existing schema3/
trust/grant/job protections and all current runtime/notices/source/receipt guards
remain in the same389hash source state.

Final documentation links are recorded in
`.local/archive-final-record-links.log/.exit`; final independent acceptance-record
review follows this already completed clean source/cleanup review. Those actual
results, source/archive invariants and task status are verified before marking the
whole goal achieved. The final record review is not a new post-line audit of every
symbol or a claim to have rerun checks. `.local/` logs/manifests/hashes are local
ignored evidence; this journal and Tasks001 retain the durable command/scope/
result/review history without publishing archived code or private material.

No native/Win32/stdio/tray/power delivery, DPAPI/ACL/Isar durability, real SSH/
Python/systemd/product-process/isolate/IPC/UI/design, hosted CI, build/install or
release qualification was performed or inferred. These are explicit evidence
limits, not promises of support for future platforms or new pending scope. No
backend/future-node implementation, deployment, foreign003/worktree/process
change, installation, publication or commit occurred. One executable, full tray,
connection-only MCP and schema3-only preservation are accepted as implemented
source with the required current static/RAM verification and independent review.
