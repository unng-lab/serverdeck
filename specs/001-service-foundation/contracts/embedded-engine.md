# Engine and Host Contract v1

## Public boundary

`packages/serverdeck_engine/lib/engine.dart` экспортирует EngineHost, EngineGateway,
EngineCapabilities и безопасные DTO serverdeck_protocol. UI получает `openOwner()`
только через host-owned UI binding; внешнего owner-token API нет. Gateway сохраняет
async `call(method, params, requestId)` и полный каталог нынешних typed owner/MCP
методов с прежними DTO, bounded operation handles и error categories. Общего
`watch(topic,cursor)` и нового event stream нет. Профили/настройки используют
атомарный snapshot и polling2s из [Local API](local-api.md); наблюдения используют
typed start/status/cancel и текущие cursors/limits из
[observations](../../021-mcp-control/contracts/observations.md). Jobs/events сохраняют
методы/sequence/cursors021. Ни каталог тем, ни delta buffers, ни новые cursor
семантики не добавляются. Cancellation response interest не отменяет job.
Baseline методов — existing owner_api/router и contracts001/021; call возвращает
прежний typed ответ без SQL/raw SSH/произвольного shell. Secrets не попадают
в snapshots/логи. UI не конструирует trusted/session DTO для получения полномочий.

EngineHost: `start(platformPorts) -> Ready | WorkspaceBusy | StartingFailure`,
`openOwner(uiBinding) -> EngineGateway`, `suspend()`, `resume()`,
`shutdown(reason) -> Closed | CloseBlocked`. Повторный shutdown возвращает ту же
операцию; повторный start не создаёт store. Ready только после lease, runtime
verification, vault/store recovery, session authority и services. До Ready UI
видит безопасную readiness, domain commands закрыты.

## Platform ports and authority

- WorkspaceLease: acquire(slot, ownerIdentity), held/release. Эксклюзивен между
  процессами/isolates; release только после подтверждённого native/store close.
- SecureVault: protect/unprotect/accessStatus/dispose, opaque secret buffers;
  Windows сохраняет DPAPI entropy/SID нынешнего KeyCustody. locked/denied/corrupt
  не равны missing. Нет fallback/автоматической замены ключа.
- ProtectedFiles: restrictive permissions, no-link traversal, read/write/atomic
  replace, проверка места. Ошибки не удаляют старые данные.
  Root — verified private-data ancestor (Windows LocalAppData); domain использует
  фиксированный product/workspace layout. kind/fileSize/stream children — только
  один уровень, links/other entities запрещены; bounded consumer прерывает обход.
  promotePath replace=false не перезаписывает destination, replace=true сохраняет
  прежний atomic retained-file rename без delete-first/retry/fallback.
- NativeStoreRuntime: pinned ABI initialize/revalidate, без самостоятельного store.
  DLL живёт до завершения процесса; native DB handles закрывает store/Host до lease,
  adapter не выгружает библиотеку и не освобождает writer reservation.
- VerifiedRuntime: app bundle/native libs/executor metadata и verified peer.
  App image заменяет locald.exe; manifest не заменяет retained process identity.
- VerifiedExecutorRelease: нейтральный artifact port descriptor/revalidate;
  Windows выдаёт private binding проверенного manifest/hash. Это не JSON factory,
  не native session и не разрешение на effect; admission/target proof отдельны.
- HostAuthority: runtime-private factory, привязана к lease/generation/UI binding,
  не сериализуется и не имеет публичного owner constructor. attachMcp принимает
  verifiedPeer/grantProof, проверяет challenge/grant. Флаг role из RPC не источник прав.
- EngineClock: monotonic deadlines и UTC timestamps; test clock только в тестовом root.

Vault возвращает mutable buffers с исключительным владением caller. ManagedVault
закрывает intake синхронно при dispose, ждёт physical completion/cleanup уже
принятых операций, затирает late output и возвращает fixed safe error. Windows
availability — ephemeral roundtrip, не восстановление persisted receipt/credential
key: unavailable/corrupt старые blobs по-прежнему блокируют открытие без reset.
WindowsWorkspaceLease содержит настоящий MutexLease; busy attempt не открывает БД
и всё равно закрывается Host. Прежний mutex namespace сохранён. Worker exit закрывает
isHeld; release/CloseBlocked определяются реальным completion, не только bool.

## Ownership, limits and concurrency

Один host/writer на workspace. Повторный процесс сообщает о занятом экземпляре;
при доступном verified activation channel просит показать окно, иначе объясняет
конфликт, не открывая БД. Activation не несёт domain commands/owner credential.
Platform lease сообщает неизменяемый `acquired` — результат именно этой попытки
захвата. `false` означает подтверждённую занятость; ошибка провайдера выбрасывается,
а потеря уже захваченного lease не меняет `acquired=true`. Host возвращает
`HostStartResult.workspaceBusy` только для связанной с текущим owner/default
workspace попытки `acquired=false, isHeld=false`, полученной до исходного startup
deadline и до shutdown. Readiness остаётся `storageBlocked`, без workspaceId,
включённых features, owner sessions, store/services/sampler или MCP publication.
Несогласованное evidence, чужой owner/slot, потеря lease, timeout и остановка не
выдаются за подтверждённый конфликт. Результат start кешируется для этой incarnation:
освобождение workspace другим процессом не разрешает её повторный startup.
Busy не доказывает physical close: Host по-прежнему владеет attempt/vault/runtime
до завершения общего cleanup; ошибка cleanup сохраняет CloseBlocked.
Private worker status передаёт outcome как `phase=busy`, с обязательными
`reason=STORAGE_BLOCKED` и readiness `storageBlocked` без workspaceId/features.
Остальные поля и версии не меняются. Controller сохраняет полученный до deadline
startup outcome даже после автоматического cleanup, отдельно от текущего
status/isClosed; это не даёт owner capability и не скрывает CloseBlocked.
Bootstrap не подключает owner client, не запускает polling и не предлагает retry
в этой incarnation. Окно объясняет конфликт на момент запуска и предлагает
использовать уже запущенный ServerDeck; если он уже завершён — закрыть окно и
запустить приложение снова. Verified activation channel сейчас не предоставлен:
используется разрешённый explicit busy fallback без нового IPC/автозапуска.
Если конфликт получен после раннего скрытия окна, окно вновь показывается.
Закрытие подтверждённого contender завершает только его процесс через общий
shutdown/CloseBlocked/Wait/Force путь, а не оставляет дополнительный экземпляр
в трее. У него нет принятых jobs, поэтому предупреждение о remote jobs владельца
не запрашивается; cleanup failure всё равно требует явного решения Wait/Force/Stay.
Окна одного процесса получают разные owner sessions одного движка. Windows
удерживает прежний mutex namespace, включая old locald.

Baseline001/021 не увеличивается: 250 профилей, 2 SSH transports, connect15s,
base read30s, startup30s. Engine gateway: 64 pending requests/session, 256 суммарно;
без места RESOURCE_LIMIT, без неограниченной очереди. Domain read deadline30s,
executor request сохраняет5s; более строгие per-method limits остаются. Существующие
history retention/sampling settings/defaults001/021 сохраняются, не сбрасываются.
Identity цели для sampler — существующая profile/connection/access/trust binding:
`(workspace, profileId, connectionRevision, accessRevision, trustRevision, readKind)`.
Один shared refresh/sampler этой identity обслуживает UI/MCP через тот же registry,
как нынешний RemoteReadService._SharedRefresh/_refreshes[profile]. Повторные start/
status/poll не создают второй collector. Разные profiles/principals не объединяются
в новый глобальный alias cache: результаты разных access scopes не смешиваются.
Методические operation handles/cursors сохраняют нынешние per-client bounds.

Мутации сериализуются текущим coordinator/CAS. Один writer на remote identity,
включая aliases через executor host identity/occupancy. Grant проверяется на admission
и перед эффектом; owner approval/delegation не обходятся из in-process UI.

## Event fence and recovery

Каждый call/operation handle привязан к generation UUID и connection/access/trust revisions,
MCP также к grant revision. Shutdown/suspend/revoke/target mutation закрывают
admission до отмены I/O. Late response старого fence отбрасывается; pending mutation
может оставаться unknown, без replay. Существующие job/event sequence/cursors сохраняют свои области и правила021;
profile/settings snapshots отслеживаются по storeRevision, без нового event stream.
Новое generation требует заново получить snapshot/handles и stale markers.
requestId не разрешает повтор
apply; mutationId/attemptId сохраняют текущие правила.

## Lifecycle

| Событие | Движок/наблюдения | MCP/jobs |
| --- | --- | --- |
| Desktop окно открыто | один host, активные subscriptions | доступ при grant |
| Последнее окно закрыто | тот же процесс в tray/menu bar; UI interests снимаются, jobs/MCP interests живы | доступен, accepted jobs наблюдаются |
| Tray недоступен/исчез | окно остаётся/восстанавливается; «Выйти»/«Остаться», молча скрываться нельзя | права неизменны |
| Явный «Выход» | сразу закрыть admission; unsubscribe/flush/SSH/DB/vault/IPC close, затем lease | SERVICE_UNAVAILABLE; remote job не объявляется отменённым |
| Network loss | observations stale, transport lost, ключ не принимается заново автоматически | unknown после submit; status/reconcile после явного подключения |
| Desktop sleep/mobile suspend | новых эффектов нет, sampler/transport останавливаются; intent всегда persisted до I/O | observer detached, фон не обещан |
| Resume | recheck capabilities/vault/lease/revisions, новый observation fence; явный SSH connect | read-only status/reconcile без submit replay |
| Crash/force-stop | callback не предполагается; OS освобождает lease, start восстанавливает store | in-flight unknown, remote occupancy сохраняется |

### Same-registry admission pause

`EngineSessions.pauseAdmission()` синхронно закрывает внешнюю регистрацию и
отзывает текущие owner/MCP session records через существующие detach callbacks.
Запросы теряют response interest, но их physical proof/settled ownership и
занятые pending slots сохраняются до действительного завершения. Это не отмена
удалённого job, не закрытие store/lease и не доказательство остановки sampler/SSH.
Привилегированные локальные authority cleanup writes сохраняют свой существующий
gate, чтобы завершить уже принятую работу и записать uncertain outcome; внешние
requests по отозванным session records больше не проходят revalidation.

Каждая pause создаёт новый непрозрачный `SessionAdmissionPause`, принадлежащий
одному registry. `resumeAdmission(pause)` потребляет только текущий same-registry
token один раз. Повторная pause инвалидирует предыдущий token. Permanent stop
и ошибка detach запрещают resume. Token не сериализуется, не является credential,
не выдаётся через owner/MCP API и не создаёт нового runtime/session authority.
Пока выполняется хотя бы одна синхронная retirement frame, resume всегда запрещён
с `NOT_READY`, включая вызов из вложенного detach callback. Вложенная pause может
обновить epoch; внешняя pause по завершении возвращает самый новый текущий token,
чтобы её caller не получил устаревший fence. Только после выхода всех retirement
frames и необходимых проверок Host этот token допускает resume. Необработанная
ошибка callback остаётся неуспешным retirement и окончательно блокирует registry.

Owner issuance захватывает admission epoch до async proof и сверяет его также
после expiry callbacks при регистрации. MCP peer захватывает epoch при создании;
весь последующий handshake/proof привязан к нему. Поэтому pause/resume внутри
await или callback не оживляет старую регистрацию. После resume нужны новые
session records/handshake; старые requests/cursors/contexts не восстанавливаются.
Host обязан до вызова resumeAdmission завершить свой physical suspend и
перепроверить vault/runtime/lease/capabilities/revisions в той же incarnation.
Сам token этого не доказывает. Связь с Host/services/desktop events и их deadline/
observation fence относится к оставшейся реализации T321; отдельно проверенная
session boundary не означает, что suspend/resume приложения уже реализован.

### Shared SSH pool physical pause

`SshTransportPool.suspend()` немедленно закрывает reserve/connect/probe intake и
возвращает непрозрачный `SshPoolPause` этой же физической операции. Повторный
suspend до resume возвращает тот же handle. Все уже принятые transport operations
останавливаются и остаются в pool до их existing physical `settled`, включая
socket/client/read/executor/key-worker cleanup. Занятые custody reservations
pool не освобождает за их владельцев: он ждёт, пока владельцы завершат свою работу
и закроют reservation. Поэтому service suspend обязан параллельно остановить
владельцев reservations; нельзя ждать pool до начала их cleanup.

`pause.settled` не имеет нового собственного deadline: Host использует исходный
lifecycle budget, сохраняя physical ownership после logical timeout. Истечение
observer timeout не возвращает слоты, не открывает intake и не создаёт другой pool.
`resume(pause)` принимает только текущий same-pool handle после полного drain,
без active transports/reservations. Foreign/stale/reused handle, pending/error
drain и permanent close дают fixed `SERVICE_UNAVAILABLE`; permanent close выигрывает
гонку с late suspend completion. После успешного resume остаётся прежний limit2.
Старые reservations/operations не оживают, trust/credentials не переиспользуются:
нужно новое явное connect с существующими проверками доверия. Pool самостоятельно
не revalidate Host, не переподключается, не запускает sampler и не повторяет jobs.

RAM-приёмка этого компонента проверяет actual pool и только in-memory reservations:
частичный drain двух слотов, late custody handoff, intake rejection до I/O,
logical timeout, handle identity и close race. Она не проверяет настоящий SSH,
socket/key-worker cleanup или сервисную композицию; service/Host binding остаётся
обязательным продолжением T321, а не заменяется этой отдельной границей.

### Same-composition service suspension

`TrustedControlServices.suspend()` сначала регистрирует текущий непрозрачный
`ControlServicesPause`, отзывает внешние owner/MCP records через admission pause
и закрывает intake общего SSH pool. Затем запускает все remote cleanup paths
до ожидания любого из них: trust probes/claims, connections/custody, shared reads/
refreshes/executors и job observers. `sessions.drainRetiredAdmissions()` ждёт
действительного завершения pending owner issuance, request proofs и MCP proof
chains; поздние фазы остаются во владении registry. Prepared invocations закрываются,
уже executing invocations остаются наблюдаемыми до завершения их effect futures.
Повторный suspend возвращает тот же handle, `pause.settled` — physical drain этой
операции без нового собственного таймера. Logical timeout Host не снимает ownership.

Сервисы не пересоздаются. Connections освобождают старые interests/entries после
settled; read cursors/cache/log rings инвалидируются, managed observations отмечаются
stale; executor inspections и job cursors удаляются. Subscriptions, cursor key,
store, custody, grants/trust и session authority сохраняются. Job stop снимает
наблюдение/opening, не отправляет remote cancel и не повторяет submit. Уже принятая
мутация может передать driver после первого stop; job drain повторно останавливает
и ждёт таких drivers после окончания operations. Privileged local cleanup writes
сохраняют существующий authority gate для фиксации uncertain outcome.

`resume(pause)` принимает только текущий same-composition handle после успешного
drain. Foreign/stale/reused/pending/failed pause и permanent close не допускают
восстановление. Host до вызова выполняет свой обязательный runtime/vault/lease/
capability/revision recheck. Composition читает текущий store snapshot, восстанавливает
локальные service gates и pool и открывает новые session records последними.
Она не делает SSH connect, recover/replay, не восстанавливает старые handles.
Ошибка snapshot/provider/fence во время частичного восстановления синхронно
закрывает pool intake и registry и начинает общий permanent close сервисов;
отмена ошибки или повторный resume не делает такой экземпляр пригодным.
Permanent close выигрывает гонку с незавершённым suspend.

RAM-приёмка использует настоящую service composition и gateway поверх validated
schema3 snapshot с RAM StateStore/runtime/publication ports. Проверяются свежие
settings/read/job routes, неизменный snapshot и identity компонентов, retirement
старых handles, late proof, logical timeout, custody drain/local cleanup gate,
foreign/stale handles, close race и неуспешное частичное восстановление. Пустой
remote graph гарантирует отсутствие SSH I/O; accepted remote job execution,
реальные socket/crypto/native failures и full schema parity этой приёмкой не
проверены и сохраняют свои задачи. Host/worker/desktop binding и полный observation
fence/revalidation остаются открытой частью T321; эта композиция не выбирает
readiness, не публикует endpoint и не подтверждает resume всего приложения.

`StateStore.assertAutomationCustody` — обычный метод repository interface с тем же
телом native-store/key-binding проверки, перенесённым из extension без копии.
Production по-прежнему использует только store, открытый actual root; RAM adapter
существует в task unit tests. Wire/UI не выбирают repository/provider и не получают
никакого способа обойти Host/native authority.

### Host pause and owned resume

`EngineHost.suspend() -> HostPause` закрывает owner/domain admission синхронно,
регистрирует physical ownership до callouts, отзывает текущие и pending UI
bindings и закрывает их gateways. Readiness при прежнем ready становится recovering,
без workspaceId/features; `isSuspended` означает логический admission fence, а
не доказанный physical drain. Host сохраняет generation, store, services, vault,
native runtime и writer lease. `pause.settled` включает service suspension,
gateway dispatch drains, pending owner work и реальные retained HostAuthority proofs.
Revocation logical reply не считается завершением старого identity proof.
Повторная pause без начатого resume возвращает тот же handle. До вызова start
suspend даёт NOT_READY и ничего не запускает; worker хранит более ранний power
intent и применяет его сразу после начала обычного start, до ожидания его reply.
Общий EngineSessions получает обязательный pure Host-owned `admissionBlocked`
predicate, проверяемый до owner/native proof, регистрации и current-session/domain
admission. Его проверка не заменяет ни один native authority proof. Host pause
закрывает этот внешний fence сразу, даже когда physical service pause ждёт старый
resume. Восстановление внутреннего session pause token не обходит внешний fence;
ему не требуется менять или подменять этот token. Изолированные RAM registries
задают явную root policy; optional default/legacy registry пути нет.

Pause во время startup ждёт готовности настоящих services и ставит checkpoint
перед readiness/publication. MCP activation обязана вызвать перед readiness check
и discovery write supplied Host `beforePublish` barrier после своего bind await;
pause во время этого await не превращается в activation failure. Ready и начало
publication ждут resume. Уже принятый publication I/O остаётся owned, не отменяется
задним числом, а domain admission всё равно закрыт. Исходный startup30s включает
ожидание pause и elapsed sleep, не перезапускается resume. Shutdown будит checkpoint
для cleanup, не разрешая Ready. Resume во время startup лишь снимает текущую pause:
окончательную готовность caller получает через прежний start future, не новый start.
Окончательный start reply публикуется внутри owned startup work после финального
pause/deadline recheck, без await или provider call между проверкой и commit.
Async completion/timeout observer не выставляет Ready. Pause, попавшая после
последнего initialization checkpoint, всё ещё удерживает тот же start future;
monotonic budget, истёкший в этом промежутке, даёт StartingFailure/TIMEOUT.
`beforePublish` возвращает sync current-guard для захваченного Host epoch/deadline,
а не только завершённый Future. Pool проверяет guard после await и ещё раз после
чтения readiness, непосредственно перед принятием discovery I/O, без async gap.
Superseded guard повторяет ожидание актуального Host barrier в том же startup
budget и pool; это не failure. При current guard настоящие identity/readiness
ошибки остаются terminal. Guard — root-owned admission check, не authority DTO.

`resume(pause, deadline<=30s)` принимает текущий same-Host handle; повторный вызов
в текущем resume разделяет его исходную операцию и budget. Host ждёт physical pause,
проверяет genuine runtime/lease (proof<=5s с оставшимся budget), доступ vault,
retained store runtime, текущие snapshot/revisions и selected executor capability,
постоянный workspace identity, затем повторный runtime proof. Только после этого
восстанавливает services и открывает admission. Native/store proof не заменяется
булевым DTO. Полная immutable capability snapshot/matrix остаётся T326 и должна
быть связана с этой точкой до закрытия всей T321. Ни новый worker, ни reset данных,
ни SSH reconnect/job replay не являются способом завершить resume.

Logical timeout resume или проверка monotonic deadline запрещает поздний Ready,
фиксирует safe failure и начинает общий shutdown. Каждый provider future остаётся
owned независимо от observer timeout; close ждёт lifecycle work и прежний actual
cleanup до vault/lease release. Исходный exit10s и explicit Wait/Force/Stay сохраняются.
Locked vault даёт STORAGE_BLOCKED; смена lease/workspace binding — UNAUTHORIZED;
private provider diagnostics не публикуются. Foreign/consumed handle даёт NOT_READY.

Новый suspend во время resume создаёт новый Host epoch, сохраняет старый physical
work и не разрешает старому resume открыть gate. Новый service pause ждёт старые
lifecycle phases, затем использует ту же composition; старый результат NOT_READY
не становится ошибкой нового epoch. Повторный suspend, включая callback после
provider restoration, не оставляет Ready gap. При этом независимая настоящая
runtime failure по-прежнему отзывает Host authority и не допускает восстановление.

RAM-приёмка Host проверяет начальный/повторный/foreign pause, startup publication,
исходные startup/resume deadlines, late owner/proof, superseded/reentrant resume,
shutdown до servicesReady и во время physical suspension/revalidation, vault/lease/
workspace/native-provider/snapshot/restore failures и single-open invariants.
Используются actual Host/authority/session/gateway/MCP publication policy с RAM
resources/metadata ports. Это не реальный native/store/tray acceptance. Worker/
controller phases, desktop power delivery/lost-callback handling и full capability
matrix остаются открытой частью T321/T326; Host component не объявляет их готовыми.

При explicit exit с unresolved job UI предупреждает о возможном продолжении
удалённой работы; это не cancel. Shutdown дренирует до10s. Если native/store close
не завершён, CloseBlocked: нет ready/reopen/release lease в процессе; UI предлагает
продолжить ожидание либо завершить весь процесс. Force-stop равен crash, не reopen.
Application lifetime принадлежит tray, daemon idle-grace при нуле сессий удаляется.
Автозапуск boot/login не добавляется.

## Полноценный desktop tray — уточнение пользователя 2026-10-30

App executable единственный: `serverdeck.exe`. Движок и MCP libraries входят в
app, отдельные locald.exe/mcp.exe не поставляются. Это не требование статически
включить Flutter/Isar runtime libraries в PE: прежние native prerequisites сохраняются.
MCP stdio mode описан [в021](../../021-mcp-control/contracts/embedded-host.md).

Tray/menu bar содержит «Открыть ServerDeck», «Серверы», «Настройки», неактивные
индикаторы readiness движка и количества активных MCP sessions, разделитель,
«Выход». Двойной левый click открывает/активирует окно; контекстный menu доступен
мышью и клавиатурой. Servers/Settings показывают соответствующий существующий
раздел того же окна. Status обновляется из текущего host, без secrets/host/grant
names. Нет скрытых remote actions или изменения permissions из tray.

Tray создаётся до разрешения скрыть последнее окно; его creation/recreation failure
оставляет/возвращает окно. Повторное открытие не создаёт второй engine или store.
Exit использует единую shutdown ветку с предупреждением unresolved jobs,
CloseBlocked и запретом false cancel. Tray lifetime не зависит от наличия MCP.
Мобильные hosts не имитируют desktop tray.


## Repository platform binding

Engine/storage owns the sole StateStore and Workspace plus transaction parts;
engine/mcp/grants owns the parsed owner command and shared service primitive.
They have no Windows/locald imports and accept ProtectedFiles, WorkspaceLease and
NativeStoreRuntime directly. Provider root/owner/default-slot and key bindings
are rechecked across async file/native work. The runtime revalidates before and
after native transactions and snapshot readback; a failed postcommit proof blocks
admission without claiming rollback. Native close remains possible when runtime
proof has failed and is required before releasing reservation/lease.

The sole creation stage uses streamed exact-four-file inventory. An existing
stage's non-accepted native layout is refused before Isar.open. Structural checks
are not semantic row preflight: the latter remains required by embedded-migration
before writable opening. No new migration, reset, fallback or format3 runtime
adapter is introduced. The standalone locald entry/bootstrap/idle lifecycle is
removed; assembling EngineHost and replacing old UI/bootstrap/build bindings is
still mandatory. Removing the old executable alone is not a runnable single-exe
app or completed cutover.


## Target-change ordering in engine

`engine/hosting/target_changes.dart` owns mutation publication ordering via the
neutral PublicationGate port, with no Windows/native peer/session DTO imports.
It is internal composition, not an authentication or RPC interface. The registry
supplies isStopping, retireMcp(affected profiles or all), and fail-closed stop
callbacks. Registry/Host authorization, CAS and target validation still precede
effects; a target lease alone grants no owner/MCP rights.

Normal begin reserves its fence synchronously, acquires the native gate and
retires MCP sessions before returning the opaque lease. Reconciled begin defers
retirement to the existing committed delta; affected IDs are UUIDs, at most250,
captured immutably. Empty affected sets do nothing. Release is idempotent and
occurs after actual mutation/invalidation, not response timeout. Registry stop
does not prohibit the already-owned lease's final retirement/physical release.

The previous native limit16 is enforced across target interests and authority
work together. Logical acquisition timeout replies promptly but retains its
physical charge/fence until that acquisition's own settled future completes; it
does not wait on unrelated acquisitions or poll a global count. A late acquired
lease cannot transfer mutation ownership after deadline or shutdown. Failure of
retirement or physical release closes intake/publication permanently and cannot
produce a successful close. Cleanup errors never authorize writer-lease release.

Authority effects retain the gate through actual effect and release, including
after caller timeout. Logical failure can precede physical drain, while close
waits all owned effects, acquisitions and releases; repeated close returns the
same operation. Observer failure prevents effect execution and still drains its
physical work. No store/workspace lease is released by this component.

The existing Windows gate/acquisition/lease implementations directly implement
the three engine port interfaces; no format/runtime adapter or forwarding
facade is added. EngineSessions consumes this sole engine ordering implementation. The old locald target_changes implementation and its obsolete
registry test hook are removed. Session/native peer migration, Host composition,
legacy cleanup and the complete single-executable cutover remain mandatory.


## Retired local API branches

The former standalone schema1 API auth/channel/server/session/diagnostic files
and operational/schema2 server/channel/owner-foundation path are removed from
locald source. The corresponding handshake, sessions, MCP context/authority,
owner adapters, catalog/router entries and private cross-format factories are
removed rather than routed to the target implementation. Migration/native owner
service test hooks with no remaining current-task consumers are also removed.
No wire format selector, alias or forwarding adapter replaces these branches.

The retained domain services share EngineSessions with Host-bound owner capability
and verified MCP endpoint admission, grant challenge/custody, request/operation
limits, target retirement, history and late-response checks. Current protocol message/version types used by that target
remain unchanged; deleting schema1/2 implementations does not renumber the
closed target handshake or business DTO fields. This deletion alone does not
implement in-process owner admission or the embedded MCP bridge. Portable session
authority, Host assembly, UI/MCP/tray cutover and removal of the remaining legacy
Windows/bootstrap/build paths remain mandatory under T255–T276.


## Portable session registry and local owner admission

`engine/hosting/sessions.dart` and its parts own the sole EngineSessions registry.
All40remaining locald domain/typed service sources are moved directly into engine;
there are no source files or forwarding exports in the former locald/lib tree.
Engine imports no Flutter, Windows, dart:io or dart:ffi. Old package configuration
and ignored generated caches are not executable service composition and still
require final cleanup; this extraction does not claim whole-app cutover.

EngineSessions.withAuthority accepts an initialized HostAuthority, borrows its
publication gate and permits one registry per authority generation. OwnerSession
has a private constructor and is issued only after validateOwner of the exact
opaque OwnerCapability. Repeated issuance shares pending work/current handle;
foreign authority, detached capability, expired/closed session or shutdown cannot
produce a live owner handle. A second registry for the same authority is refused.
Owner handles reserve/admit only their exact record; public string-based reserve/
begin are MCP-only, even when a caller knows an owner's channel/session ID.
No JSON factory, role field, bootstrap HMAC or executable argument creates owner.

McpServerHandshake always binds a private MCP peer and uses the unchanged closed
handshake fields/transcript/HMAC. Requested owner capability is refused. The
platform composition supplies VerifiedMcpChannel (retained owner/appRoot/buildId,
revalidate, bounded I/O, drain/disconnect); it exposes no role selector. Each proof
checks Host runtime before/after channel proof and rechecks exact identity metadata
across awaits. The port observes actual physical proof completion, including late
work; it is not a deserialized wire object. The native Windows endpoint adapter
and format4 discovery/bridge composition remain mandatory T256/T265/T266.
McpApiServer/McpServerChannel contain no owner preparation/dispatch route.

Existing stricter limits remain:8total sessions including4MCP maximum,60s lease,
16pending/session,5s request/handshake proof budgets. A separate256aggregate cap
counts all owned requests, including disconnected records with unsettled proofs;
active8×16 alone is not enough to bound late work.64/session must not relax16. Startup/runtime proofs retain
HostAuthority's256physical work bound. A completed response interest retains its
session charge until all actual proof work settles. stop closes admission and
request interest synchronously; close drains per-request physical proofs and the
shared target/authority work. Neither registry nor channel releases workspace
lease/store ownership. Detached records and old generations cannot publish later.

HostAuthority.validateRuntime provides liveness only, not permissions. Both runtime
and owner validation expose the actual proof future to internal drain observers.
Owner async connection/read/probe contexts retain these physical futures through
timeout/detach. Observer failure cannot issue authority; runtime proof failures
retire the host generation. Owner configuration uses its Host runtime root/build
and VerifiedAppConfiguration, whose Windows implementation is the real retained
EmbeddedBuildBundle; no Windows path/verifier import enters engine. Configuration
is same-executable MCP command data, not a grant or execution permission.

ControlServices continues same-store/registry identity claims, custody binding,
job recovery before activation, shared SSH pool, typed owner APIs and MCP router.
The UI in-process gateway, concrete EngineHost, native adapters and tray are still
required; moving these services alone does not make the current UI runnable.


Before new owner capacity is computed, expiry removes all elapsed60s records.
Expiry callback exceptions return a fixed safe Future failure; callback-triggered
stop is rechecked before issuance. Mixed live/expired/pending records retain the
same total8bound; a full expired pool cannot block replacement indefinitely.

All request-owned identity proofs use one physical tracking primitive, including
initial grant open, owner root/configuration helper and detached terminal-open
permit. The helper establishes proof ownership only; each caller retains its own
live/admission or narrowly scoped terminal guards. Composite and underlying proof
futures remain charged until actual completion. Grant-open cap4 also covers the
worker/key cleanup, final binding phase and late helper proofs after logical
timeout/disconnect. The terminal permit does not use ordinary live-record
revalidate and cannot become a general post-detach publication capability.
VerifiedMcpChannel disconnect confirms cancellation/completion of prior proof/I/O
before native endpoint reuse; timeout is not that physical barrier.


MCP runtime→channel→runtime proof is one owned physical chain. Before starting
any phase, the private MCP peer registers a physical-completion future both with
its registry and the operation observer. That future waits the logical phase
runner and a fixed-point drain of every observed underlying proof. Therefore
existing actor snapshot drains retain phases started after a short caller timeout,
including a channel proof whose logical error precedes physical completion.
Logical phase results remain timely; they are not reported as physical/native
failures. Actual physical proof errors still reach the operation observer.

The registry separately bounds owned MCP proof chains at256 and drains them even
when a handshake/publication caller has no operation observer. No new chain is
accepted after stop; stopped chains cannot start another phase. Bootstrap response
verification enters the same private peer path, not a direct untracked channel
proof. This is physical lifetime bookkeeping only and grants no permissions.
Owner proofs remain single-phase HostAuthority-owned, with context/request drains
retaining their actual proof futures. No additional event stream or schema field
is introduced.


## In-process owner gateway

`hosting/in_process_gateway.dart` implements EngineGateway with the same async
call(method, params, requestId) catalog, through the actual TrustedOwnerApi
dispatcher and an already-issued OwnerSession. The composition root binds these
objects; no UI-provided role/session DTO or token creates a gateway. There is no
transport, reconnect, automatic retry, SQL/raw shell route or new watch stream.
The former unused TrustedOwnerDispatch shortcut is removed; typed adapters still
prepare bounded commands and execute only after owner admission.

The gateway reserves session/global interest before payload/service lookup. It
captures requestId and detached params synchronously before awaited proof; typed
prepare precedes initial admission just as in the former server, then effect
execution requires successful fresh proof. Domain routes require current Ready
before preparation, execution and publication. Readiness/ping/close preserve their
current DTOs; readiness generation must match the owner generation. A final proof
and live/readiness guard precede delivery, so revoked/closed/stopping generations
cannot publish late domain results.

The original5s request budget includes input capture/preparation. A caller timeout
ends response interest, not an accepted mutation/job. The gateway retains actual
dispatch, invocation cleanup and request physical proof drain; close rejects new
calls immediately, detaches only its owner session and waits owned work. Close
is idempotent. Cleanup failure retires this gateway and prevents successful close;
workspace/session-registry/service teardown remains Host-owned. No workspace lease
is released by a gateway and no accepted remote job is declared cancelled.

Input/output use the existing noncanonical JSON projection: finite metric numbers,
Unicode text and distinct normalized/decomposed keys are preserved. Whole former
message byte/depth limits remain256KiB request/8MiB response, including metadata.
Request size accounting uses a constant43char nonce placeholder, never serializes
an owner credential; it is validation only, not a compatibility handshake. Output
is detached/deeply immutable before the final await. Typed domain DTO projection
remains in the existing services, including catalog results; no replacement DTO
schema is invented by the gateway. Invalid output returns INTERNAL.

EngineCallFailure exposes only the validated existing public code/field/retry
shape. Validation, conflict, readiness, timeout and SSH categories preserve their
meaning without exception source/input/provider diagnostics. requestId alone does
not authorize replay: durable mutationId/receipts/CAS retain their existing rules.
Concrete EngineHost and UI gateway client binding remain mandatory next steps;
this component alone does not make the application runnable.


## Host startup and explicit-exit resource ownership

`hosting/engine_host.dart` owns one generation and the actual acquired lease
attempt, including a busy attempt. `EnginePlatform` contains trusted root-supplied
runtime/files/vault/native-runtime objects and lease acquisition; it is not wire
configuration. `HostResources` is engine resource composition, not an OS database
port. Its normal `WorkspaceHostResources` opens the existing Workspace and
TrustedControlServices with the same custody/receipt key/session registry. RAM
implementations are confined to unit tests; there is no fake native open or
production test mode. Optional verified executor/bundle are supplied to the normal
resource composition by the application root.

start returns one shared operation with Ready/StartingFailure. The30s default
budget covers lease, authority/runtime verification, vault availability, target3
workspace recovery, services/job recovery and final runtime proof. Trusted roots
may choose a stricter positive budget, never more than30s. Ready needs a valid
workspace UUID and completed recovery. Busy lease, wrong owner, unavailable vault,
incompatible data or any startup timeout cannot enter Ready or open owner APIs.
Startup errors expose only fixed safe categories. Repeating start returns its
original result, even after shutdown; this is historical completion, never a new
store or permission. Current readiness/admission remain authoritative.

The root passes object-identity UI bindings to openOwner. Pending opens for one
binding share work; two windows get separate private owner sessions on the same
services/store, within the existing8total-session limit. detachOwner revokes that
binding, closes its response interests and retains their actual cleanup for Host
drain. It leaves the Host alive. Late issuance after detach/exit cannot publish.
Observed lease loss or stopped authority retires Ready and starts shutdown.

shutdown closes admission synchronously and returns one operation. It drains
actual startup (including late acquired resources), owner opens/gateways, services,
registry/authority proofs and publication work, then closes workspace and vault.
Only confirmed closure with no retained native reservation permits lease close.
A failed partial service cleanup is remembered by resource composition: there is
no later successful store/lease close that conceals it. Callback cleanup failures
are collected; they cannot strand shutdown or permit store release.

The shutdown budget is10s by default (a trusted root may use a stricter positive
budget). Its timeout yields CloseBlocked and keeps admission permanently closed.
If resources finish after CloseBlocked, the Host still retains its lease. The
existing UI action “continue waiting” calls waitForClose on that same cleanup,
allowing release only after successful physical drain. A cleanup failure remains
CloseBlocked, without retry/reopen/replay. Repeating shutdown returns its original
operation/result; waitForClose shares the final physical-close operation. If lease
release itself has already begun after confirmed drain, timeout does not restart
or cancel that single release; its actual completion determines final closure.
Force-stop remains whole-process crash, never an in-process restart.

This core implements startup/local-owner/explicit-exit ownership only. Concrete
Windows retained runtime/endpoint composition, native MCP publication, capabilities,
UI bootstrap/tray and suspend/resume observation fencing are still mandatory in
T256–T261/T265/T269/T274–T276; the current UI has not been connected to this Host.
The isolated lifecycle tests do not establish native/whole-app readiness.


Logical gateway retirement, direct close, session.close or expiry does not prove
physical cleanup. Before replacing a same-binding gateway or pruning any closed
owner slot, Host transfers that gateway to its retained drain and revokes the old
UI capability. The replacement receives a fresh capability. Old cleanup failure
stays sticky for Host shutdown even after the old slot has disappeared; old active
dispatch remains charged until actual completion. Eight occupied UI bindings can
therefore replace a retired slot without leaking authority capacity or resources.


Host reserves the shared pending owner future and its physical ownership before
runtime proof or retirement cleanup callouts. For retired slots, all old map
entries/capabilities are removed/revoked as one synchronous batch before any
old gateway.close callback runs. A callback can reenter openOwner or shutdown:
same-binding callers share the reserved future, another binding cannot be revoked
by the old batch, and shutdown cannot issue a late gateway. No non-reentrancy
restriction is imposed on platform proof or internal detach callbacks.


The same ownership-before-callout rule applies to start itself: its shared result,
physical startup completion and timeout/readiness observers are registered before
_initialize invokes acquireLease or any other provider. A synchronous shutdown
from that provider waits the registered physical future, including late acquisition
success/failure; it cannot dispose vault or report Closed while acquisition is
pending. Lease release after confirmed drain begins without an avoidable event-loop
yield when release permission already exists; otherwise explicit waiting remains
the permission barrier after CloseBlocked.


## Windows Host runtime and sole publication kernel

WindowsVerifiedRuntime implements VerifiedRuntime directly in engine_platform.dart.
It requires the genuine bundle4 EmbeddedBuildBundle and its retained current-app
VerifiedApplicationPeer, rejects testOnly and accepts only a genuinely acquired
WindowsWorkspaceLease from the existing private native factory. Owner/defaultslot,
held lease/object identity, captured root/build and exact current process/bundle are
rechecked. The first lease stays bound for that runtime lifetime; proof failures
retire it. One generation gets one shared gate future; physical ownership is
registered before native gate creation. A different generation is refused, not
an in-process restart. The root retains the borrowed self identity through Host
shutdown; the runtime never closes a writer lease or unloads the native core.

The sole WindowsPublicationGate is now in publication_gate.dart, independent of
pipe_worker/old bundle selectors/filename roles and without native test hooks.
It directly implements the existing neutral gate/acquisition/lease ports, owns
its own retained current-process identity plus owner-only kernel event and mutex
keeper, and uses the existing bounded MutexLease workers. Its factory is an
internal native synchronization primitive: a trusted composition root supplies
the current-process verification policy. It is not a process/role/owner authority
issuer or wire factory. WindowsVerifiedRuntime supplies actual bundle4/current
process/held-writer-lease checks before and after gate proof. Gate also checks
actual SID/PID and retained identity around that policy; no JSON bool/role grants
access. MCP/root peer admission and grant checks remain separately mandatory.

PublicationIdentity extracts the existing SHA256 domain/SID/root/generation naming
into pure engine code. The kernel namespace stays unchanged, not a new protocol
or descriptor schema. Metadata retains4096/32767 bounds and canonical UUIDv4;
NUL/CR/LF and malformed Unicode are refused rather than creating ambiguous or
replacement-character names. Valid Unicode is not normalized. Native canonical
root/current-owner validation remains the Windows adapter's responsibility.

Native open returns an owned failed gate on partial initialization failure so
HostAuthority can retain and drain its resources rather than lose the cleanup.
It is closed to admission immediately; close failure stays fatal/CloseBlocked.
Acquisition still bounds16actual attempts+leases and5s; logical timeout retains
its settled work, late leases close physically, worker loss/abandonment/uncertain
release poison the generation. Close drains actual acquisitions and owner-released
leases before closing process/kernel handles. RetainedProcessIdentity.close now
returns a cached checked CloseHandle result; the gate consumes it and collects all
handle-close failures. Duplicate close does not retry an uncertain native handle.

Old IPC peer code's already-existing legacy policy selection stays outside the
native kernel, using the same single implementation while those old roots await
removal. No new schema3 runtime adapter, old-class alias or forwarding gate was
added. The old gate part file is deleted; MCP gate/lease references use the actual
new implementation and reject a closed creation result. These bindings do not
make the legacy bootstrap/MCP client usable with bundle4. T256/T265/T266/T274/T276
still require the MCP-only native endpoint, root/bridge/UI/tray cutover and removal
of old selectors. RAM naming and existing consumer units do not qualify native
Win32/ACL/process/worker behavior or establish runnable application readiness.


Windows namespace binding first applies explicit Windows path normalization and
lowercase spelling, as in021/publication-gate.md, then calls the byte-exact pure
PublicationIdentity. One actual copy opened as C:\App or c:\app must share the
same mutex/poison event. publication_binding.dart owns this pure adapter policy;
valid raw Unicode byte behavior of the engine helper itself remains unchanged.

## Engine worker and UI proxy composition

Normal desktop application mode creates exactly one trusted engine worker isolate
per workspace inside the app process. MCP stdio mode is connection-only and creates
no EngineHost/domain worker/store; its native I/O helpers grant no owner authority. That worker creates and owns Host, sole store/coordinator,
vault/runtime/self handles/gate/session capabilities and service pool through
physical shutdown. Existing native pipe/mutex workers are subordinate I/O owners,
never another engine/store. Native hashing/verification/file work runs outside
Flutter UI isolate; an async signature alone does not make native work nonblocking.
The root retains borrowed self identity until Host/store/gate/vault have drained.

The UI uses an EngineGateway proxy on private Dart ports. Trusted app bootstrap
passes the private control/reply endpoints directly at spawn, without a named
IsolateNameServer/OS owner endpoint. Worker-local UI binding objects are created
only by this trusted root path, one per window; only then does worker call
Host.openOwner. The UI receives a bound proxy/channel, never OwnerCapability,
owner session credential, authority object or a JSON role/token/session DTO.
Ordinary call messages cannot openOwner, select another binding or carry a role
that grants authority. Binding/channel handles are process-private VM objects,
not serializable credentials or CLI/environment configuration. Additional window
attachment uses the same trusted root control path and the same worker/Host.
MCP still uses the separate MCP-only native endpoint and grant admission.

Worker domain dispatch and root lifecycle control use one private admission mailbox.
Trusted control is distinguished by spawn-owned process-private VM capability,
never a caller JSON role/string. Per-window proxy endpoints are bound by the root
and cannot issue root control. Native MCP dispatch forwards only its verified
connection/request context, not arbitrary root envelopes. Mailbox arrival order
serializes the shutdown barrier with domain admission: work already accepted is
retained, while calls behind the stop barrier cannot begin new admission/effects.
Root closes UI proxy intake before posting the one shutdown barrier and retires
outward MCP intake; ordinary-slot saturation cannot prevent posting control.

Proxy calls preserve call(method, params, requestId) and safe result/error DTOs.
Private envelopes carry method/params, requestId/generation, original monotonic
deadline and reply correlation; worker
binds them to its existing gateway, not to caller-claimed permissions. Detached
input, whole256KiB request/8MiB response bounds and typed catalog stay as specified.
No watch stream or reconnect/replay is added. UI and worker use the Dart VM's
shared monotonic Timeline.now microsecond clock (SDK developer/timeline.dart),
not UTC, to retain the original5s request budget including proxy/transport queue.
An expired queued request cannot gain a fresh5s admission window. Per-method
stricter limits remain. The worker adapter passes only the remaining original
budget to admission; native physical work remains separately owned after timeout.

The proxy retains at most16owned request slots per UI binding, including timed-out
response interests until the worker acknowledges their physical settlement.
Worker/session256aggregate and8total sessions remain unchanged. No unbounded local
retry/queue is permitted; no capacity returns merely on caller timeout. Reserved
close/shutdown control does not compete for ordinary request slots. Worker returns
only safe fixed failures, never raw exceptions/native diagnostics/stack traces or
secrets. UI discards late old-generation/detached replies before presentation.
Worker completion acknowledgement is the reuse barrier, not message-send success.

Window detach closes that proxy's admission immediately and asks the same worker
to detach/close its gateway; actual drain stays worker-owned. Host/tray/MCP/jobs
remain alive. Explicit exit first closes outward UI/MCP admission at the root,
then forwards shutdown to that worker; commands already accepted stay owned and
are not reported cancelled. Worker closes domain admission before its teardown.
The10s close budget starts at root request and includes queue/ack time, not a
fresh10s after delivery. Root may report Closed only after same-generation worker
acknowledgement of physical Host/store/gate/vault/lease closure. A timeout, missing
ack or worker failure is CloseBlocked, never implicit release/reopen. A late
closure ack is physical evidence only, not Ready or permission to reopen.
Explicit continue-waiting attaches to the same operation/waitForClose; no second
Host/worker/store or mutation replay. Actual release already begun after confirmed
drain is not retried/cancelled by a lost/late reply.

Worker exit/error alone cannot prove native DB/mutex/subordinate workers closed
while the process still lives. The root permanently retires its proxies/publication
and offers continued wait or whole-process termination, without spawning another
engine worker in that process. Only process restart may recover that lost worker's
workspace normally. Whole-process crash uses the existing recovery/unknown rules.
Suspend/resume uses the same worker with the required observation/admission fence;
it never substitutes a new worker or replays apply. Root/proxy/subordinate workers
are application-internal composition, not a second daemon/executable.

T258 implements this Root/proxy/binding/budget/settlement protocol; T261 tests it
with RAM channel/clock/lifecycle adapters, including worker loss and late close
ack. T265/T274 bind MCP-only endpoint/headless entry through the same root policy;
T259/T275 bind tray/suspend/exit. Those implementations remain open. This decision
does not claim the current UI has been connected or native/UI tests were run.


The root's original30s startup budget includes worker spawn and native bootstrap,
not a fresh30s after them. Worker control and physical startup ownership are
registered before native provider callouts. Expired/cancelled bootstrap cannot
publish late Ready or discovery; late resources still belong to that worker's
same cleanup. Root/proxy implementation must plumb these original deadlines and
barriers; the existing direct gateway/Host core alone does not provide a cross-
isolate proxy or that root protocol.


## Bound worker gateway transport implementation

InProcessGateway.beginCall is an internal trusted-root entry returning separate
EngineInvocation.result and .settled. Ordinary EngineGateway.call retains its
existing API. result may timeout while actual dispatch/proof/cleanup continues;
settled covers those physical futures and propagates cleanup failure. Gateway
registers actual work before input/prepare/provider callouts, so reentrant close
cannot capture an empty drain. Final revalidate captures remaining budget before
starting the proof future, preventing an expired argument evaluation from leaving
an unobserved rejected future.

OwnerSession.reserve accepts an optional absolute expiresAt in its registry clock
domain. It can only shorten the existing5s deadline; expired queued work cannot
prepare/execute and an enlarged budget is rejected. VmEngineClock uses raw
Timeline.now as a shared process epoch, not a per-isolate Stopwatch zero. The
Windows worker root must use it for Host/session construction; proxy defaults to
the same VM clock. This change does not alter MCP wire fields or deadlines.

WorkerGatewayProxy/GatewayWorkerBinding and concrete DartGatewayChannel implement
the bound window call/reply/settlement transport. The trusted root alone constructs
a binding from an already-issued InProcessGateway plus Host.detachOwner callback,
and routes its process-private VM capability before calling handle. No attach,
Host creation, role selection, owner credential or storage factory exists in the
ordinary binding protocol. DartGatewayChannel posts [VM binding, frame] to the
private mailbox and owns only that window's reply port; no global port lookup,
external owner endpoint or reconnection is added.

Private closed fields are:

| Kind | Fields after kind |
| --- | --- |
| call | generation, sequence, id, method, expiresAt, body |
| close | generation |
| result | generation, sequence, id, body |
| error | generation, sequence, id, error, retired |
| settled | generation, sequence, id, ok |
| closed | generation, ok |

sequence is positive signed-int64, strictly increases per binding and never wraps;
id is the original UUIDv4 requestId, not permission/replay authority. expiresAt is
VM monotonic microseconds. Call body is detached JSON params; result body is the
existing bounded v/id/generation/result projection. Error uses only the validated
TrustedLocalError shape; retired reports logical binding retirement, not physical
closure. Unknown fields/kinds, wrong generation/correlation, duplicate replies and
unconfirmed settlement retire the channel. No JSON field can mint its VM binding.
The nonce placeholder remains size accounting only inside shared input capture,
never transmitted as a session/owner credential. Whole256KiB/8MiB limits, finite
numbers and non-normalized Unicode text/keys are preserved; result trees are
immutable and owned transport byte buffers are wiped on success/failure/discard.

Proxy retains16owned slots through caller timeout or completed reply until worker
settlement acknowledgement; worker also bounds16active calls. Request budget covers
capture, both queues and delivery. Worker checks deadline/current binding/readiness
before emitting domain results; proxy checks the original deadline on receipt even
if its timer callback was delayed. A session.close reply is only the narrow already-
proved terminal closed:true result, then that proxy begins its ordinary close.

Close control has reserved admission, closes UI interest synchronously and awaits
worker detach plus every accepted invocation/cleanup before closed:ok=true.
Repeated close shares one operation. Failed cleanup/delivery yields no successful
close. Uncertain call or reply send is not retried or resent as another reply;
accepted work remains owned and is not replayed/cancelled by response timeout.
Failure retires the proxy and best-effort withdraws that same worker binding before
closing the reply path; no acknowledgement is inferred from sending close. It
retains unconfirmed tokens and safe failure, never declaring store/lease release.
Root's authoritative worker-loss signal retires DartGatewayChannel, not an ordinary
observation timeout. Only trusted same-generation physical close acknowledgement
can complete a normal window close; application lease/shutdown stays Host-owned.

This implements the bound data transport, not the trusted root attach/control
mailbox, Windows worker startup/platform composition, UI LocalApiClient replacement,
MCP publication, tray or suspend/resume. T258/T261/T273 remain open for those
bindings and full RAM acceptance. No actual isolate/native/UI dispatch or platform
qualification is claimed by these RAM transport tests.


### Trusted worker root and Windows bootstrap increment

EngineWorkerRoot owns the one private ReceivePort admission order. Only the
spawn-provided dart:isolate Capability admits root controls; protocol Capability
DTOs and window routes cannot attach owners or control lifecycle. Control frames
are closed maps with positive strictly increasing signed-int64 sequence, kind,
and operation fields: readiness(no fields), attach(binding VM capability, replies
SendPort, expiresAt), detach(binding), shutdown(expiresAt), waitClose(no fields).
Control reply contains kind=reply, sequence, operation and exactly result or safe
error code. Startup sends mailbox(SendPort) then started(status). Status has phase,
reason and nullable existing readiness DTO. No credentials or owner tokens cross.
Eight window slots include pending/retiring bindings; repeated pending binding
requires the same reply route. Sixteen ordinary control futures are owned before
provider callouts, plus one shutdown, one waitClose and up to eight distinct
reserved detach controls. A replayed control is rejected without provider effects.
Root control and ordinary bound gateway frames share one mailbox; unknown routes
are discarded with mutable byte wiping. Normal window close retires its slot after
actual detach/settlement; Host remains alive. Failed physical cleanup retains slot.

Absolute shared VM monotonic deadlines include bootstrap and queued delivery:
startup at most30s, attach5s, shutdown10s. Shutdown synchronously stops root attach/
call admission and owns partial bootstrap, pending owner opens and accepted work.
A managed Host automatic failure drains resources but holds lease pending root's
original exit decision; no fresh shutdown deadline overwrites a queued UI exit.
An expired root exit holds the same lease until explicit waitClose. Runtime
metadata disposal occurs after store/vault and before lease; a failed disposal
holds lease permanently. WindowsEngineBootstrap derives current executable bundle4,
SID, LOCALAPPDATA, retained current process, vault, native runtime and genuine
writer lease inside the worker. Partial allocations stay owned through close.
Windows worker entry installs its mailbox before startup; stdio never invokes it.
Closed response is same-generation physical acknowledgement only: worker retains
mailbox until root controller returns ackClosed with that response's sequence.
Worker exit alone remains no evidence of native cleanup and permits no restart.

Acceptance for this increment is RAM unit coverage of startup/recovery ordering,
VM route rejection and discard wiping, eight slots/normal close, pending attachment
identity, detach/late proof, shared original deadlines, late startup/exit lease
holding, metadata disposal ordering/failure and closed acknowledgement. Actual
Isolate.spawn/controller, UI LocalApiClient cutover, MCP publication and tray remain
open under T258/T261/T265/T274/T275. These tests do not execute native/FS/process/
SSH/isolate/UI/design code or establish platform/runtime qualification.


### Worker controller and concrete VM connection

EngineWorkerController is the Flutter root's single worker-incarnation owner;
DartWorkerConnection installs control/error/exit listeners before Isolate.spawn,
provides the spawn-private VM capability and private reply port, and binds each
window's fresh VM capability to its own reply port. Windows desktopEngineController
caches this incarnation, including failed/closed state. No named port discovery,
owner credential DTO, Isolate.kill, automatic replacement or retry is exposed.
DartGatewayChannel's binding type is explicitly the dart:isolate Capability, not
the protocol permission enum. Its disposed observation only prunes local reply
ports; it grants no Host/store/native closure authority.

Controller start shares one30s operation. Original absolute Timeline deadlines
include VM spawn, bootstrap, both queues and receipt. Delayed started replies
cannot revive Ready after the deadline or after stop/loss. Start after stop/loss
returns current status, never an old Ready snapshot. Controller validates closed
status/control envelopes, expected sequence/operation, fixed errors and a pinned
Host generation. Unknown/duplicate replies or uncertain control send permanently
retire this controller without resending effects. Actual connection error/exit
is authoritative loss; it closes all window interest and yields CloseBlocked,
never inferred native closure. Only a validated closed response records physical
closure before ackClosed permits normal worker exit on its separate event port.

At most8UI window entries include pending/retiring work. Opening the same active
UI object shares one future; new attachment mints a fresh VM capability. Attach
uses5s including its queued reply; a failed/expired attach posts reserved detach
without replay. Pending attachments have no proxy-close acknowledgement dependency
before a gateway exists. Established detach stops the proxy synchronously, posts
reserved root detach and awaits actual proxy close. Only then is its reply channel
released. Remaining proof work is still Host-owned. Closed UI object reuse requires
its previous detach to settle before another attachment. Window close keeps Host
and tray alive.16ordinary pending controls remain charged after observation
expiration until actual reply; shutdown/waitClose and8detach controls are reserved.
Before mailbox delivery the concrete connection retains at most26ordinary/reserved
control frames plus one coalesced power intent, as defined below.

Explicit exit closes every existing proxy's admission before posting one root
shutdown with the original10s end. It shares the same future and does not reset
that end after late startup. Exit before start still creates one observed worker
lifecycle and immediately applies its stop barrier. Logical timeout yields
CloseBlocked; late physical reply is acknowledged but does not rewrite the expired
observer's result. Explicit waitClose attaches to that same Root and may confirm
its physical closure. No in-process worker/store recovery follows any failure.

T258/T261 acceptance for this part uses the actual Root/Host/gateway stack with
RAM connection/reply ports, queued controls/replies and monotonic timers: shared
startup/attachment, safe result projection,8slots/fresh binding, pending detach,
queued5s expiry,16timed-out control retention with reserved exit, startup30s,
exit-before-start, loss without restart, original10s with explicit wait, late
physical ACK and uncertain-send/no-retry or bad-correlation failure. Concrete
Isolate.spawn, native runtime, UI/design, FS/SSH/process and platform qualification
are not executed by these units. UI cutover, native MCP publication/bridge, tray
and broad lifecycle acceptance remain open under the existing tasks.


Physical close is recorded and acknowledged exactly once per worker incarnation.
Its first validated response settles all already-created shutdown/waitClose
observers of that same Root before ACK permits the separate onExit stream event.
An observer whose original deadline already expired keeps its timeout result.
Bounded correlations remain to absorb an already queued second valid close reply;
no second ACK and no delivery of that second reply is required for completion.
ACK uncertainty is never retried and cannot revoke already-proved native closure.
RAM acceptance must use a strict one-ACK connection, both reply orders, and exit
closing the control stream after the first response without delivering the second.


### UI owner cutover to the embedded worker

The normal FoundationApp now creates DesktopEngineHost in its Flutter root isolate.
This host borrows desktopEngineController's single cached incarnation and creates
one private window binding. BootstrapController observes that worker's start and
format3 readiness before polling; its original30s monotonic presentation budget
also covers attach/readiness queues. Explicit retry may request another attachment
of the same live Host after prior detach, never another worker/store or mutation
replay. Loss leaves unavailable presentation until explicit action; no old native
bootstrap/recovery loop, child process launch, DPAPI owner discovery or token export
remains in lib/. The four old local_api_client/native_client_transport/
native_bootstrap_host/trusted_native_bootstrap_host source files are removed,
not wrapped or re-exported.

EngineClient is the permanent presentation session over an issued EngineGateway.
It supplies request UUIDs, captures existing typed format3 result DTOs and exposes
logical retirement via gateway.retired. This future signals loss of response
interest immediately; it is not physical native closure. Worker loss, explicit
proxy close and core gateway retirement complete it once. close() still awaits
physical settlement. Automation/server/software consumers use this bound session
without Windows owner clients; they retain existing typed commands, operation
cancel/status interest, IDs, limits, unknown outcomes, CAS and explicit receipts.
No widget layout or design test is added.

EngineApiClient owns window attachment, heartbeat20s, existing profiles/settings
snapshot polling2s, generation/epoch publication fences, immutable coherent
revision snapshots, mutation intent/receipt identity and source byte ownership.
Its only transport is the gateway issued through the private Root. Read params
are captured before attachment await; MutationIntent retains detached bytes until
explicit dispose. A lost response never retries a mutation. Receipt lookup uses
the original request UUID; revisionConflict may refresh a current snapshot without
replaying the effect. Detach retires UI data/interest immediately and waits actual
window cleanup separately. Stale replies/errors/epochs cannot restore private UI.
The only success allowed across logical retirement is the previously-proved narrow
terminal session.close result. Future Root failure never grants a new Host.

Desktop window/client disposal detaches only that window. Explicit app-exit request
starts Root shutdown before waiting UI cleanup; only HostCloseResult.closed allows
AppExitResponse.exit. CloseBlocked cancels exit and retains resources; no broad
catch converts failure into successful app exit. This supplies the engine boundary
for T259/T275's still-pending tray/hide/continue-waiting/fallback controls. It does
not claim final close-to-tray UX, secondary activation, MCP publication/stdio bridge
or Windows/runtime qualification.

RAM acceptance for this cutover covers shared window attachment, typed format3
readiness before polling, immutable/coherent/nondecreasing snapshot revisions,
detached inputs and stable mutation IDs, timeout/no-retry/explicit receipt lookup,
retirement before physical close, late read/snapshot/error fencing, existing poll/
heartbeat intervals, failed/late startup and loss without automatic restart.
Actual gateway/proxy RAM tests separately prove logical retired before physical
settlement and unknown close after transport loss. No native/isolate/FS/SSH/process/
UI/design execution or build/install is part of these tests.


Only explicit EngineApiClient.connect() can initiate UI owner attachment. Reads,
mutations and snapshot continuations use an existing current session or await an
already-started explicit connection; absence/retirement fails safely without
opening another. Snapshot epoch/session ownership is checked before its second
settings read as well as before publication. A queued poll callback rechecks
polling interest before starting another refresh. RAM regression must retire the
session after the first typed snapshot read, delay physical detach, and prove no
second read/new attachment before explicit retry. Completing detach alone does
not reconnect; explicit connect may then create exactly one new owner session.


### Windows tray, window interest and app-exit binding

Normal desktop main mounts DesktopApplication, whose DesktopLifetime remains
alive when no FoundationApp window subtree is mounted. Hiding removes the window
subtree and its client/response interests; reopening mounts a fresh UI binding to
the same cached worker/Host. The native HWND and Flutter engine remain the same.
Local navigation section is remembered; Servers/Settings issue a fresh navigation
request to the existing shell even when that section was previously requested.
No store, worker or remote effect is created by tray/window restoration itself.

Windows FlutterWindow owns the single native notification icon and private
serverdeck/desktop MethodChannel, inline in serverdeck.exe. NIM_ADD plus
NOTIFYICON_VERSION_4 succeeds before hide is allowed. WM_CLOSE is intercepted
before default destruction; left/double/keyboard activation opens the window and
WM_CONTEXTMENU displays the keyboard/mouse popup. Popup contains Open, Servers,
Settings, disabled readiness and MCP count, separators and Exit. Only fixed phase
labels and integer0..4 are exposed, never jobs/targets/grant names/credentials.
TaskbarCreated recreates the icon; failure immediately restores HWND and emits
trayUnavailable, success emits trayAvailable without automatically hiding it.
Native hide rechecks icon presence; failure keeps/restores a visible usable window.
RegisterWindowMessage failure cannot enable hide. A missing tray presents explicit
Exit/Stay. Custom native dialogs default to Stay and cancellation/failure is Stay.
They use system Common Controls6 (manifest binding, comctl32 link), already present
in the Windows10/11 supported OS; no new external process/runtime installer.

Desktop status is a reserved-root VM control kind desktopStatus with no extra
fields beyond kind/sequence; its ordinary16control slots retain original5s budget.
Result closed fields are status(existingWorkerStatus), mcpSessions integer0..4,
unresolvedJobs null or integer0..250. Host expires current MCP sessions before
counting logical active admissions. Unresolved count is from the validated cached
schema3 automation snapshot: every job except succeeded/failed/cancelled, including
unknown, counts unresolved. Before store availability count is null. No names or
execution permission are projected. UI uses a single sequential2s status poll;
failed observation shows unavailable/unknown rather than stale Ready. Status
polling can neither attach owner nor replace a worker/store.

Window operations share one bounded coalescing pump: the latest restore intent
wins over a pending hide, tray-loss invalidates pending initialization success,
and late hide cannot remove a restored window/client. Obsolete close does not
prompt Exit after a newer open. Fallback on absent tray stays usable. Independent
Root status/exit is reachable even with no UI session or full ordinary call slots.

Exit is committed after its explicit native confirmation. Its count is an
informational snapshot; the warning always states that accepted remote work is
not cancelled, including work admitted between sampling and the stop barrier.
Stay before commitment keeps Host live. After commitment the one Root shutdown
immediately closes UI intake and uses the original10s budget; only its physical
Closed authorizes normal finishExit/native window destruction. Presentation
cleanup is not awaited ahead of Host shutdown. CloseBlocked restores the window
and offers Continue waiting / Finish process / Stay. Wait observes the same
waitForClose without blocking another explicit Force/Exit action. Repeated Wait
shares one observation; repeated Exit during a prompt shares that operation.
Whole-process Force uses explicit user choice with crash semantics, never claims
Closed/cancel/reopen and does not replay mutations/jobs. Stay after CloseBlocked
keeps the retired incarnation and lease; subsequent window-close still reaches
this same blocked-exit control even without a tray. Physical completion and Force
race through one finish operation. Native finish failure leaves exit retryable.

Microsoft API references for source-level binding:
[notification API](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw),
[custom dialogs](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-taskdialogindirect).
These API sources do not establish runtime acceptance.

T259/T275 RAM criteria include hide only after icon success, Host lifetime across
zero windows, no engine replacement, section restoration, absent/failing/recreated
tray, late hide/open and initialization races, fallback Stay/Exit, unresolved-job
warning, committed shutdown/CloseBlocked, nonblocking same-operation Wait and
explicit Force, duplicate Exit/finish, and private bounded desktop status. Native
C++ source is reviewed statically; this change does not execute/build the runner,
real tray/dialog/isolate/SSH/FS/process or widget/design acceptance. Suspend/resume,
secondary activation, MCP publication/stdio entry and broader parity remain open.


### Embedded Windows MCP pipe producer

EmbeddedPipeListener/EmbeddedPipeChannel replace the role-based old pipe binding
for new Host/stdio composition. A listener attempt is owned synchronously before
ready; one listener accepts exactly one peer, and a slot may be rebound only after
its confirmed physical close. No old-channel epoch or native handle is reused.
Each dedicated worker derives actual current executable root/SID, verifies bundle4
and retained current-process identity, restricts name to the actual owner's eight
embedded-v1 endpoints, and verifies the connected process against the same app
image/build/SID/root. Client additionally pins the descriptor's positive32bit
server PID; no argv/DTO/filename can issue an owner role. This channel only supplies
the MCP port; Host still validates its lease/runtime and grants before effects.
No store, writer lease, desktop process or locald is opened by this producer.

Private per-worker commands are accept(server once), proof, read, write, drain,
close/ackClose. Only VM endpoints cross isolates; handles stay in their native
owner.16ordinary commands retain capacity until actual replies; close has reserved
admission. Original shared Timeline budgets cover the queue: proof/write/drain≤5s, idle
read≤60s, partial frame≤5s supplied by the existing frame owner. Metadata proof
checks its original5s budget before/after native validation. No operation resets
its budget after delivery. Read chunks≤65536, whole writes≤8MiB+4; encoded byte
copies are wiped after physical write, discarded input and returned read transfer.
Proof observer receives actual work before caller observation can time out. Worker
loss alone never proves cleanup and never authorizes rebinding or lease release.
Close first retires intake, owns partial startup, cancels/settles all accepted
native I/O, checks pipe/peer/self/event-handle closure, then returns a physical ACK.
The worker remains alive until private ackClose, avoiding exit/reply-port races.
Failed handle cleanup stays sticky, including creation failures; no second close
of an unconfirmed handle or endpoint reuse is allowed. Root must retain its lease
on unconfirmed closure. Native publication-gate factory uses genuine retained self
plus this connected peer's before/after proof; the gate is synchronization only.

Low-level NativePipe accepts embedded-v1 names only. Output drain uses the end's
actual quota: server OutboundQuota, client InboundQuota; pending writes cannot be
reported consumed. Invalid pipe state/end/quota fails closed. This is based on
[MS-FSCC FilePipeLocalInformation](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/de9abdc7-b974-4ec3-a4dc-42853777f412).
Pure RAM units cover exact namespace/foreignSID/oldname rejection, queued original
budgets, descriptorPID bounds and asymmetric quota/invalid states. Native worker,
handle closure and actual IPC are static-source/analysis scope only, not runtime
qualification. Host endpoint publication, new client handshake/gateway/stdio entry,
old role-based bindings and standalone-bin removal remain open under T256/T265/
T268/T274/T276; this increment does not make MCP runnable.

MCP never starts ServerDeck. If no app is available, the attempted connector reports
its own connection/startup error and exits; there is no reply from an absent
service. The normal app, including its tray lifetime, is the only Host/store owner.
The same requirement applies to grantless unconfigured stdio, which must retain
verified app liveness rather than serving autonomously. Existing MCP bootstrap's
child-launch fallback is removed now; remaining legacy bundle/session wiring must
be replaced before the new entry is considered complete. No compatibility bridge
or new feature specification is introduced.


### Host-owned MCP endpoint pool and readiness handoff

McpEndpointPool owns eight one-peer listener attempts for exactly the same
McpApiServer/registry/generation/workspace as its Host. A listener object is owned
before awaiting ready. The native EmbeddedPipeListener implements this neutral
port; it creates no second Host/store. bind reserves all slots and verifies every
listener's readiness without publishing discovery or admitting peers. activate
requires Host Ready, matching generation/workspace and the publication check;
only after actual discovery publish completes does it enable accept loops.
Registry8total/4MCP sessions and existing pending limits remain unchanged.

EnginePlatform.mcpPublication is an optional platform composition factory returning
an owned, unbound pool. It must not allocate I/O resources before returning that
pool; its descriptor/metadata computation remains startup-owned. Host creates the
MCP API through WorkspaceHostResources from its actual same-registry services,
router and authority after recovery; an unactivated API or another returned API
object is rejected before binding. All services, writer/runtime and native listeners
are ready before Host marks its internal readiness Ready and advertises discovery.
The parent/UI startup acknowledgement still waits publication/readback, original
startup budget and final runtime proof. MCP feature is false until publication
succeeds and immediately false at stop. An adapter without this factory does not
claim MCP availability. No caller DTO, argv or discovery token creates owner rights.

Each slot uses the actual McpServerHandshake and McpServerChannel with the shared
server. Bad authentication/protocol/disconnection affects that peer only; rebind
is allowed after both channel and listener confirm physical close. Accepted bytes,
requests/proofs/publications remain owned after timeout. A physical close failure
is sticky, prevents reuse and fails the pool/Host. A replacement listener/metadata
failure stops admission; a logical failure alone is not mistaken for an unclosed
handle. Channel identifiers increase without wrapping. Token copies passed to
handshake are wiped immediately after capture; the descriptor stays alive until
all late work and removal settle, then its token is wiped.

stop synchronously closes intake, disables publication and asks every current
listener/channel to close, including partially created attempts. Creation is
recorded before provider callouts, so reentrant stop cannot lose a late listener.
close owns late bind and late publish, waits their real completion, then removes
only this descriptor. A late write cannot resurrect discovery after removal.
It joins all listener/channel/run work before success. Discovery failure still
attempts every native close. Host starts pool stop at the same shutdown barrier
as session revocation, and joins pool close alongside services/registry/authority
before store/vault/runtime metadata and writer lease. Its existing10s timeout and
explicit waiting retain the lease while publication/cleanup is unconfirmed.

RAM criteria use the actual pool/handshake/channel and registry, fake listener/I/O/
discovery ports: eight bind-before-publish slots; recovery denial; reentrant stop;
partial bind/close ownership; late publish/remove ordering; bad peer isolation and
rebind-after-physical-close; failed close/no-rebind; late accept/no handshake; fixed
incompatibility; Host startup acknowledgement/readiness features; same registry;
late-publication CloseBlocked/lease; unactivated or mismatched API rejection.
These units never execute a native pipe, Isar or filesystem. Windows discovery
owner (protected atomic publish/readback/compare-and-remove) and its concrete
Windows bootstrap factory are still mandatory under T265; without that binding,
current Windows Host deliberately advertises MCP=false. Full client/stdin/stdio
entry and old-source removal remain open; this pool is not a compatibility facade
or a claim that MCP now runs independently of the app.


Late accept after a successful listener close still transfers an independently owned peer to the pool. Listener close success cannot prove that this later peer or a late constructed channel has closed. Their actual close failures remain sticky in pool.close; Host must retain its lease and report CloseBlocked. No handshake starts after stop, including reentrant constructor callbacks. T304 covers pool and Host RAM regression criteria.


### Concrete Windows MCP publication binding (T305)

Normal WindowsEngineBootstrap now supplies its Host mcpPublication factory.
It borrows the exact retained self/bundle4/runtime, vault, protected files and
actual writer lease acquired for that Host. Factory creates no I/O before
returning the owned pool; descriptor uses actual PID, build, Host generation
and recovered workspace. No separate writer/store, new process, argv owner
role or legacy transport is involved. Eight EmbeddedPipeListener attempts bind
before activation. The live publication guard checks actual retained image/SID,
held lease and runtime, then Ready plus matching generation/workspace. Pool
admission and parent ready acknowledgement still await completed publication.

ProtectedMcpDiscovery owns one descriptor identity and one publish/remove
attempt, registered before provider callbacks. McpDiscoveryFile is a fixed-name
protected file port, with read, atomic replace, retained-object compare/remove
and physical close. Windows binds only LocalAppData/ServerDeckNext/v1/runtime/
embedded-v1.discovery. The existing protected product parent must exist;
runtime directory is created owner-only if absent. Every operation checks the
retained owner/lease, safe local paths and protected parent. Reads reject
reparses/nonregular files, enforce handle ACL and bound wrapped bytes to16384.
Clear descriptor remains8192, custody entropy/format2 are unchanged. Existing
format2 metadata of a different valid build may be inspected as data under the
writer lease and replaced. Legacy/future versions return INCOMPATIBLE;
corrupt/denied metadata returns STORAGE_BLOCKED. These failures do not overwrite
or remove the previous file. Former discovery filenames are never accessed.

Publish validates stale bytes, protects its own descriptor, retains exact
wrapped bytes BEFORE replacement, atomically writes, reads back the exact
ciphertext and unprotects/compares the complete canonical descriptor. Every
await is followed by the live guard before success; all transient buffers and
loaded tokens are wiped. Publish failure after a possible commit still owns
removal. Remove stops new publication, waits its real completion, then removes
only exact retained ciphertext. Missing/different content stays untouched.
Cleanup can run after Ready loss while the same genuine owner/lease is held;
it does not require Ready and cannot publish a new file. File close drains all
issued work. Any unconfirmed native CloseHandle stays sticky in this adapter,
including failed reads before a write or an unexpected native I/O isolate RemoteError; pool close fails and Host retains lease.
No timeout converts native/file work into successful physical completion.

The native writer uses CREATE_NEW on a random16byte .pending name with explicit
owner-only ACL, writes/flushes, then FileRenameInfoEx REPLACE_IF_EXISTS plus
POSIX_SEMANTICS on that SAME retained object. If writing/rename fails, it marks
only the newly created retained object for deletion before closing, including
partial writes; it never deletes a colliding name. Native compare/remove opens
one regular protected object with GENERIC_READ|DELETE and READ sharing only,
compares at most16384bytes, then FileDispositionInfoEx DELETE|POSIX_SEMANTICS and
checked CloseHandle. No pathname delete race, delete-first gap, readonly bypass,
elevated permissions, compatibility fallback or retry is allowed. Unsupported
native semantics fail closed. See [Microsoft file disposition semantics](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/2e860264-018a-47b3-8555-565a13b35a45).

RAM acceptance covers normal write/readback/wipe, different-build stale data,
legacy/corrupt/oversized preservation, absent Ready, proof loss after commit,
readback corruption, write-then-failure, late write versus close, exact removal
versus different bytes, sticky removal/physical-close failure and descriptor
identity isolation. Unit ports execute no native/file/Isar/process/isolate I/O.
The Windows implementation and composition are statically checked; actual
DPAPI/ACL/rename/disposition/pipe execution is unqualified. Remaining client,
headless stdio entry, old binding removal and broad T265/T274/T276 stay open.


### MCP-only client ownership foundation (T306)

Engine mcp/client.dart is the single new portable client implementation for the
embedded endpoint. Its bootstrap/grant/RPC parts belong to the same library;
there are no owner operations, schema switches, old image-role adapters or raw
transport callbacks. The trusted root obtains VerifiedMcpChannel from the new
native connector and verifies descriptor PID there. Client captures actual peer
owner/root/build and checks them on use against its captured binding. Descriptor
supplies matching owner/build, Host generation, recovered workspace and a copied
bootstrap token; it is not authority and can be closed by its owner afterwards.
Construct and retain McpClient BEFORE awaiting authenticate. Constructor creates
no native object/process/store/writer or new connection.

Authenticate is single-use and always requests only mcp, rejecting owner hello,
wrong build/generation/API and bad server HMAC. It preserves the exact API1.1
bootstrap transcripts with token32 and constant-time proof comparison. The
original bootstrap budget is at most5s, including provider work, framing and
proofs; CPU/queued work does not renew it. Token copies and mutable frame buffers
are wiped. Provider actual work is registered before callouts, with observed
native proof futures retained separately from a logical timeout. Only successful
bootstrap starts one ordinary reader. There is no reconnect or automatic retry.

Before grant, public call permits readiness.get, session.ping, session.close and
mcp.close; mcp.invoke requires a successfully verified grant. Owner/unknown
methods and raw mcp.open are rejected locally without bytes. One openGrant takes
McpCredentialFiles bound to the actual owner and descriptor workspace, performs
readForBridge without creation/repair, sends the existing mcp.open transcript,
verifies server proof/binding/expiry and closes its temporary key in finally.
It may run only with no ordinary call pending; public calls are rejected while
it runs. Another grant attempt cannot emit a second open. Timeout, malformed
proof or policy failure stops the connection; late credential/native work
remains owned and cannot issue open or publish grant after retirement.

RPC generates UUID request IDs internally; callers cannot replay old envelope
IDs. Request capture includes the entire256KiB envelope, retains exact Unicode
wire text and charges one of16pending slots before collection/encode callouts.
A serialized writer checks native identity and the original5s deadline before
I/O. Responses are bounded8MiB, closed-envelope validated and correlated by both
ID and generation. A response before issue, unknown ID or wrong generation is
terminal. Reply cannot release its pending charge or caller result before the
actual write ACK and final native proof. Readiness also validates recovered
workspace; ping/close/MCP operation result shapes are checked. Results are
recursively immutable. Fixed safe exceptions retain local/remote/transport
origin and existing retry advice; the client never performs that retry itself.
The reader uses idle60s and partial-frame5s absolute deadlines.

Close registers its shared completion before disconnect, stops admission and
rejects pending RPCs synchronously, then waits actual disconnect and every
registered provider/read/write/reader/grant work item. A physical disconnect
failure remains failed on repeated close. Logical timeouts never report physical
completion or permit another connection; late results are discarded and keys
closed. No client close can terminate the main app or cancel durable remote jobs.

RAM unit acceptance covers actual bootstrap/grant transcript MACs with scripted
peer and fake in-memory file/protection ports, owner/MAC rejection, retained
proofs, original deadlines,16pending/serialized write ACK, correlation/generation,
workspace/identity mismatch, read-only grant files, one grant attempt, queued
input capture, malformed result, late credential read and sticky physical close.
No native, process, isolate, real filesystem, Host/database, SSH or UI/design is
started by these cases. Windows bootstrap/gateway migration to this client,
stdio/headless entry and removal of the old client files remain required by
T265/T274/T276. This foundation does not claim working end-to-end MCP.


T307 final-delivery boundary: recursively capture the immutable response BEFORE releasing its pending slot or cancelling its timer. Recheck the original deadline after capture and then current pending ownership immediately before completion. captureMcpResult charges this CPU work to the original EngineClock deadline; it grants no authority and never publishes. Deterministic RAM regression advances a fake clock while reading a nested input collection, proving that capture crossing5s fails instead of returning data.


### Windows MCP client/gateway cutover (T308)

McpProcessBootstrap now creates only WindowsMcpConnector and the new portable
McpClient. Both configured and unconfigured modes require the actual already
running ServerDeck. WindowsMcpConnector is owned synchronously before any connect
work. It derives root from Platform.resolvedExecutable and owner/LocalAppData
from the actual OS, verifies the exact production bundle4/serverdeck.exe/current
process identity, and reads only the protected fixed embedded-v1.discovery.
No caller app-root, owner role, process launch, writer lease, Isar/domain Host,
old filename or schema fallback exists. Missing runtime/file/usable endpoints
is local SERVICE_UNAVAILABLE. Incompatible metadata remains untouched. Existing
paths must be protected directories/regular file, safe/owner-only, wrapped read
at most16KiB. Discovery is unprotected with the same managed CurrentUser vault
and expected actual build. All transient bytes are wiped; descriptor token is
closed as soon as McpClient captures its independent copy.

Connect owns one original5s budget covering verification/discovery, up to8ordered
endpoint attempts, native ready and MCP authentication. Each failed attempt must
physically close before another slot is tried; there is no retry after bootstrap
or effect. EmbeddedPipeChannel.connecting returns an owned native attempt before
ready, including failed/late creation. The expected descriptor server PID is
verified natively; both processes retain same-image/SID/build checks. A logical
timeout stops further attempts and begins close; actual connect/proof/file work
remains owned. Unknown native I/O loss/unconfirmed reader close, failed identity
factory or failed gate creation cannot report a clean connector close. Close
interrupts client/channel first, waits late connect/gate work, then drains client,
channel, gate, vault and retained metadata. It never releases a writer lease or
terminates the main app, since this connector owns neither.

Process bootstrap has a30s startup ceiling, requires Ready with MCP available,
performs exactly one protected read-only grant proof if grant-id is present,
then opens the native generation-bound publication gate and attaches the sole
LocalMcpGateway. No standalone unconfigured gateway constructor remains. The
gateway takes this actual client/gate pair, checks generation/closed state and
uses the EngineClock port (normal monotonic+UTC, no CLI override). Empty tools
or FORBIDDEN without grant require that same live client; no mcp.open/invoke is
sent in this mode. Configured tools preserve existing invoke/poll/cancel, live
policy session.ping under native publication fencing,20s heartbeat,16tool
interests, and exact cancellation of request interest only, never durable jobs.

McpClient.retired and gateway.retired report logical loss independently of their
physical close futures. Stdio observes retirement even when stdin is idle,
stops with terminal status and rejects later output. Every otherwise unguarded
fixed/builtin response (including initialize/ping/protocol errors) obtains a
fixed publication interest when its serialized writer turn begins. It holds the
same native gate and performs client.verifyLive with the remaining5s budget,
then synchronously checks current lifetime before issuing stdout. Fixed data
contains no domain result and requires native liveness rather than grant-policy
ping; configured domain data still requires the full policy ping and expiry.
At most16tool interests plus one active fixed writer guard are retained. Native
lease release waits actual guard and stdout flush settlement, including after
logical retirement; no timeout turns a live flush into physical completion.

McpServer checks gateway lifetime at queue/guard/issue boundaries. EOF normally
closes only this bridge; physical gateway-close failure or bounded cleanup
failure returns nonzero so entry cannot join the same uncertain cleanup twice.
The reusable entry function runMcpStdio(grantId) is ready for the single exe's
Dart --mcp-stdio branch; it bounds fixed diagnostics to stderr and returns an
exit status. Nonzero requires terminating only that owned connector process.
The separate package bin/mcp.dart and ten replaced Windows bootstrap/build/
operational-client/old pipe-worker source files are removed, with no alias or
compatibility facade. Other unused runtime/artifact cleanup remains T276.

RAM acceptance exercises unconfigured live binding/empty list/forbidden call,
logical retirement before physical close, configured catalog with gate+policy
ping, cancel-interest without jobs cancellation, remote unavailable versus
terminal transport/no replay, protected builtin/list publication, idle stdio
termination on app loss, failed fresh proof/no output, actual-flush-before-lease
release and terminal status on EOF cleanup failure. Fake peer/file/protection/
gate and memory streams are used, with actual client/DTO/HMAC/gateway/stdio
policy code. No OS/native pipe/DPAPI/ACL/realFS/Host/Isar/isolate/process/SSH/UI/
design/build/run dispatch is executed. The normal lib/main.dart mode selection
and headless Windows runner are still required by T274; this cutover does not
claim that the single exe's MCP command is runnable or platform-qualified yet.


T309 protected-file cleanup propagation: WindowsProtectedFiles keeps its public
safe STORAGE_BLOCKED result, but reports a PHYSICAL_CLOSE_UNCONFIRMED native
file failure or unexpected I/O RemoteError to the trusted runtime composition.
This notification grants no authority and cannot be configured by CLI/DTO.
Both actual WindowsEngineBootstrap and WindowsMcpConnector latch it permanently.
The desktop metadata-disposal hook fails after store/vault drain so EngineHost
keeps CloseBlocked/writer lease; the stdio connector cannot report clean close.
New-file/empty-file writer, copy target, retained snapshot and replacement
primitives check CloseHandle and preserve this internal failure marker after
wiping/freeing buffers. It cannot disappear during safe exception conversion.
Existing RAM Host metadata-close ordering/failure tests cover the lease-boundary
policy; actual marker production/Win32 close and adapter callbacks are checked
statically only, without native qualification. This also covers late credential
file reads owned by the new client during stdio startup.


T310 closes the first mcp_cutover_review P2: every locally synthesized fixed RPC
failure and overload invocation now owns real native gate/proof callbacks; no
_immediate/no-op guard or _fixed early-return is permitted. Data-free fixed
failures skip grant-policy ping/expiry, but never live native identity/lifetime.
Original-domain operation interests still cannot publish after stdio cancellation.
The existing gateway.md exceptions are updated in place. RAM regressions check
actual acquisition/proof on remote SERVICE_UNAVAILABLE and overload at16pending,
including failed fresh proof before read-side retirement is observed.

T311 closes the second P2: native pipe worker records failed self-identity factory
as sticky cleanup uncertainty, even when no RetainedProcessIdentity was returned.
Its close cannot send a successful physical ACK or allow slot reuse/next endpoint.
WindowsMcpConnector retains that failed channel and propagates close failure.
This conservative rule does not assert a native handle leak happened; it denies
clean-close when partial factory cleanup cannot be proved. Actual Win32 identity
factory/CloseHandle failure is checked statically, not native-injected in tests.


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


T312 fixed-fallback guard: a failed domain guard or final validation may precede
any native proof/lease (for example grant expiry while queued). Before issuing
the fixed fallback, stdio waits actual original guard settlement and releases
that publication, since no stdout was issued. Only after confirmed release does
it create a separate gateway.protect interest and obtain a fresh gate+verifyLive
for fallback. This avoids reacquiring a gate still owned by the failed original.
All stages share the original writer5s budget; timeout cannot start a replacement
and original late ownership remains in finally. New fallback guard/proof failure
stops without output; no recursive fallback or effect retry. Fallback lease
remains held through actual flush. RAM regression queues a second domain reply
behind a real memory flush future, advances only fake UTC to grant expiry and
checks guarded FORBIDDEN for live proof versus no second output for failed proof.


T312 also checks a policy-ping failure AFTER the original lease is acquired. The RAM gate rejects recursive/concurrent acquisition, so a healthy fixed fallback proves confirmed original release before replacement acquisition. No private domain bytes are emitted, and the replacement lease settles after stdout.


## T313 — private stdio carrier boundary (2026-10-30)

The MCP library no longer uses dart:io stdin/stdout/stderr. Its required
McpStdioPort is owned by the same executable's stdio composition; no standalone
entry, alternate executable or direct-stdio compatibility fallback is supplied.
ChannelMcpStdioPort calls PlatformDispatcher directly with StandardMethodCodec,
without WidgetsBinding, ServicesBinding, runApp, tray, plugins or domain Host.
The existing application entry remains unchanged in this bounded increment:
T274 must still bind the native carrier and select the headless branch. This
increment does not make --mcp-stdio runnable and does not qualify native I/O.

The private channel is serverdeck/mcp_stdio. It is not an MCP tool or public IPC
endpoint. It accepts no caller handle/path/role/root. Exact methods and replies:

| Method | Argument | Success reply | Physical meaning |
| --- | --- | --- | --- |
| attach | integer1 | integer1 | carrier version1, once per owned connector |
| read | null | Uint8List, length0..65536 | one actual inherited-stdin read; empty means EOF |
| write | Uint8List, length1..8388609 | true | every byte actually written to original inherited stdout |
| diagnostic | ASCII MCP:CODE plus LF, CODE matches [A-Z][A-Z0-9_]{0,63} | true | separate inherited stderr, best effort |
| close | null | true | cancellation and physical drain of all carrier I/O/handles confirmed |

False/malformed/error replies are failures. Dart exposes only STDIO_UNAVAILABLE,
never raw platform errors. Attach requires an integer version, not double/string.
One read and one write may be pending independently. The output bound is8MiB
plus the framing LF. A write claims its slot and snapshots bytes before awaiting
attach. The snapshot remains owned until actual native settlement, then is wiped.
Timeout/cancellation above this layer must not release the gateway publication
lease while actual write is still pending. The existing stdio writer owns its
original5s budget; the entry returns nonzero for uncertain cleanup so the future
headless caller can terminate only its own connector process.

Input is one-subscription, pull-based, with at most one pending read while
paused. Cancellation drops observation and prevents further pulls; it does not
claim that the outstanding native read finished. Close is sent immediately,
not queued after possibly blocked input/output. It waits native confirmation and
all already-owned attach/read/write/diagnostic futures. A failed close is cached
and cannot become successful through retry. Pending writes may fail due to native
cancellation; physical completion and successful byte publication are distinct.
Diagnostics accept only fixed codes, at most32 over the incarnation, with one
pending operation and no unbounded queue. The server/entry diagnostic wait is1s;
normal successful shutdown closes the carrier within5s after confirmed gateway
and connector cleanup. Nonzero shutdown must not join uncertain I/O again.

T274 native implementation obligations: capture private duplicates of original
stdio before any SDK output; quarantine SDK/logger stdout/stderr before Flutter
DLL initialization (including transitive plugin imports); never call the SDK's
CONOUT$ resync in MCP mode. Blocking ReadFile/WriteFile must run off the platform
thread with bounded admission; return channel replies on the platform thread.
close ACK requires actual completion/cancellation and confirmed handle disposal,
not logical interest cancellation. Main must parse argv before UI initialization,
use a viewless engine/message pump, bind only this carrier, and never initialize
application Host/store/tray/plugins in stdio mode. These are existing T274
requirements made concrete at this boundary, not a separate service or process.

Acceptance for this Dart boundary is RAM scripted-call units: strict attach,
read pause/resume/EOF/malformed data, cancel versus physical drain, write snapshot/
ACK/slot/size/error wiping, close while attach/read/write is outstanding, sticky
close failure, and fixed bounded separate diagnostics. They inject the invocation
function and do not dispatch native platform messages or create any UI binding.
Native implementation and whole single-executable readiness remain open.


## T274/T315 — same-executable Windows headless binding (2026-10-30)

The source entry is now bound: Windows main parses argv before console/COM/UI
initialization and accepts only empty application argv, --mcp-stdio, or
--mcp-stdio --grant-id plus one canonical lowercase v4 UUID. Failed argument
conversion is distinct from empty argv. Unknown/legacy/root/owner/repeated flags
fail locally, without echo and without a UI/Host fallback. Dart revalidates using
the same grammar before either side effect. Empty argv alone installs UI runtime
diagnostics and runs DesktopApplication. MCP invokes only runDesktopMcp, awaits
the private carrier version1 readiness (5s), then the existing connection-only
bootstrap. It never creates a domain EngineHost, app store, tray, view or plugin
registry. The Flutter VM engine is a library runtime for this same executable's
short-lived connector, not a second domain service. A missing main application
still yields only local startup failure; no main app is launched.

Native McpStdio owns duplicates of inherited stdio before the first SDK call.
Stdin and stdout must be valid Windows pipe handles. Both synchronous and
overlapped pipe handles are accepted, using NtQueryInformationFile's
FileModeInformation16 to select the appropriate ReadFile/WriteFile form. Valid
stderr is duplicated separately; absent stderr or the same underlying object as
stdout is replaced by an owned NUL diagnostic handle. Character stderr uses
synchronous writes. Diagnostics remain fixed ASCII, <=64code characters plus
MCP: and LF, one pending and32 total. No caller-supplied handles/paths/roles.

The runner and every generated runner plugin import are delay-loaded, so a
plugin's transitive Flutter import cannot initialize SDK stdio prematurely.
Only this connector sets process/CRT standard streams to NUL. Before delayed SDK
CRT initialization, it neutralizes the already-consumed CRT startup inheritance
count in its own process; this is necessary for normal Node/libuv clients, not
an old-version compatibility path. Accepted current UCRT/libuv table ABI is a
32bit count followed by count flags and count pointer-sized handles, count<=2048
and within cbReserved2; zero/no table also works. The count is read, zeroed and
read back through checked current-process Read/WriteProcessMemory. Original byte
handles have already been duplicated and remain unchanged. Unknown/truncated or
unwritable startup metadata fails closed. A preloaded Flutter DLL fails closed.
The SDK is explicitly loaded from the executable's directory after quarantine;
SDK loader/error dialogs are suppressed only in the connector process. It never
calls CONOUT$ resync, AttachConsole, AllocConsole or RegisterPlugins.

The supported native source target remains Windows10 x64 and the pinned Flutter/
Dart runtime. The carrier creates one Win32 worker per input/output/diagnostic,
each with one private event and a stable retained thread HANDLE. No blocking pipe
I/O runs on Dart or the platform thread. Writes handle partial completion in
<=64KiB chunks; an ACK means the entire frame was physically written. Overlapped
I/O buffers/events remain alive through GetOverlappedResult. Read replies contain
only the actually read bytes, EOF is empty, and native buffers are wiped after
platform-thread method reply encoding. No write replay or observation retry.
Method completions run only on the platform thread, with slots charged through
reply. Platform event pumping obeys Flutter ProcessMessages' deadline, wakes on
native completions and dispatches messages without creating a FlutterView/window.

Close stops admission, sends CancelIoEx plus CancelSynchronousIo to its own
workers, then waits for actual I/O settlement, checked I/O/event close, signaled
thread exit and checked thread HANDLE close. Cancel return is never a completion
ACK. A race where cancellation precedes kernel issue remains physically owned;
no false drain: native close watchdog terminates only this connector after its
original5s. A separate native watchdog covers capture/SDK/bootstrap startup30s,
then is disarmed by the first server input read after successful bootstrap.
It re-arms on close and is itself signaled/closed before a clean close ACK.
Unconfirmed CloseHandle latches failure and prevents successful close/exit.

Additional private channel method finish takes integer0..255 and never replies:
it terminates only GetCurrentProcess via TerminateProcess, bypassing DLL/CRT
detach locks on uncertain writes. Zero is permitted only after confirmed clean
carrier I/O close and checked disposal of the retained wake/NUL control handles;
otherwise the owned process exits nonzero. SDK/library process-lifetime memory
is reclaimed by the OS. A normal EOF first completes gateway/connector cleanup,
then carrier close, then finish0. A nonzero result never joins uncertain I/O or
cleanup again and cannot terminate the main desktop process or cancel its jobs.
An unexpected WM_QUIT, SDK load/run error or watchdog expiry is owned exit1.
Dart's MCP zone drops print and maps uncaught async faults to nonzero exit,
without forwarding exception text. The native channel is private trusted code,
not an externally callable MCP method. If native finish is unavailable, Dart
falls back to nonzero exit. Invalid native argv exits nonzero before SDK loading;
the pure Dart dispatcher returns64 if independently invoked with invalid argv.

RAM acceptance: existing argv/EOF/publication/physical-close cases plus six new
production-dispatch/owned-zone cases check branch isolation, forwarded grant,
late terminal code, no rejoin/retry, failed factory and suppressed print/uncaught
async faults. Native static /Zs checking parses the changed C++ with MSVC17 flags
and pinned SDK headers, generating no object/binary and running no app/I/O. This
is not Win32 I/O/CRT inheritance, loader, GPU, lifecycle or installed-command
qualification. Unit/static evidence does not prove runtime success. Production
bundle/scripts T271, wider T253-T276 acceptance and final review remain open.


## T271/T316 — embedded build entry and metadata (2026-10-30)

run-serverdeck.ps1 is the sole source build entry. Removed build-locald.ps1,
build-mcp.ps1 and run-foundation.ps1 are not retained as aliases. Resolve pinned
root plus engine/MCP/protocol/Windows lockfiles with enforcement; regenerate
engine records, then one Flutter Windows build --no-pub. There is no standalone
Dart exe compilation. Only after selected Isar/notices and executor descriptor
are prepared does the script write compact UTF8/no-BOM manifest4, within16KiB.
No execution/build/install/deploy is performed by this source-change task.

New-EmbeddedBundleManifest is the shared pure RAM composition used by this
actual entry. It validates exact current five lock paths, canonical lowercase
commit/digests, Debug/Release, absolute bounded appRoot, exact app/Isar hashes
and optional executor hash. No legacy executable/lock or unknown artifact field.
The build entry generates executor metadata and always supplies its hash.
BuildId is commit+configuration+SHA256 of ordinal-sorted path:hash LF transcript,
without trailing LF. Output is an owned copy of scalar hash values and fixed
format4/product/API1.1/schema3/testOnly=false fields; callers cannot mutate it by
changing their input collections. UTF8 serialized byte bound is checked before
writing. EmbeddedBuildManifest remains the runtime parser, not a new wire format.

Before any build output write, reject reparse paths and stale layouts containing
old separate exe; recheck absence after Flutter build. Never relabel/delete/
migrate those outputs or kill processes. Build does not touch workspace data,
change target schema or create compatibility fallback. Native ABI source points
at engine package_config; notices inventory covers root+all four current packages;
source snapshot/review scope no longer requires deleted locald metadata or build
alias. Source-bound old approvals do not become current automatically. Existing
native input/receipt guards stay strict; current-source native qualification and
remaining legacy qualification validator cleanup are not claimed by this step.

Acceptance is eight RAM-only PowerShell manifest cases wired into full test-unit:
normal Debug/Release, optional executor, lock order invariance/change binding,
missing/legacy lock rejection, unknown/legacy/case-mismatched artifact rejection,
noncanonical digests/configuration/commit, invalid/oversize root and detached
input-map mutation. PowerShell AST parse checks script syntax without executing
build/native/collector/activation paths. Actual notices collection, Native ABI,
qualified provider/activation, packaging and installed runtime remain unexecuted;
T276/final convergence must account for legacy qualifier code independently.


T317 confirmed review fix: build-output validation includes layout ancestors,
existing descendant entries and explicit app/Isar/executor/manifest/notices paths,
both before build and after Flutter. Immediately before Python executor output
and File.WriteAllText manifest output, the exact destination is checked again by
Assert-NativeIsarPlainPath. Existing file/directory reparse entries therefore
fail before being followed by those writers, rather than merely validating the
parent directory. These checks use the existing plain-path policy. They are not
an atomic adversarial-filesystem guarantee or a Native/realFS test result.
Static acceptance inspects the actual producer destination variables and guard
calls before each write, plus AST parse and independent review; no FS fixtures
or source-string golden tests substitute for physical behavior qualification.


## T276/T318 — retire unused protocol compatibility code (2026-10-31)

Only EmbeddedBuildManifest remains; removed the unused format1/2/3 bundle
constructors and their _OperationalBuildFields, without aliases/deprecation
facades. Removed the orphan protocol FramedReader/ChunkReader file; actual
embedded pipe/client frame parsing and original physical ownership are unchanged.
Removed unused API1.0 hello/auth/authenticated DTOs and validators, schema1
readiness projection/common-parser branch, old response/error envelope parser,
unused ApiRequest convenience DTO, enum Capability role-less metadata and unused
ApiMethod capability/requiresReady payloads. ApiMethod names/isMutation remain
because actual profile/settings/receipt services use them. Removed unused old
version/global namespace/startup/daemon grace constants; current quota/deadline
constants remain. Dart isolate Capability is unrelated and remains private.

Target format3 readiness and response/errors go through TrustedReadiness,
validateTrustedResponseEnvelope/TrustedLocalError and captureTrustedMethodResult.
Shared profile/settings/mutation projections and LocalError category/retry data
are still used by target services, not a compatibility parser. Exact schema3
storage/credentials/enrollment and internal format1 wrappers/format2 sidecars
that belong to schema3 are not old workspace formats and are not changed.

Only obsolete import hide clauses were removed in UI/profile/settings and two
engine worker libraries; UI design/body behavior and generated schema records
are untouched. No runtime provider/proof/role fallback introduced. Existing021
bundle contract is updated in place to remove obsolete normative parser/filename
role requirements. Completed historical tasks/evidence remain preserved.

Acceptance adds5RAM target boundary cases: typed ready3 capture, no schema1/2 or
API1.0 readiness parser, shared strict settings/revision immutable capture,
format3 trust-error retry/envelope checks, and closed request shape forbidding
caller role/capability/owner/root metadata. Existing full units cover target
bundle4/schema3/discovery2/authentication/current DTOs and all retained service
semantics. Source declaration/caller inspection plus full analyze establishes
retired symbols have no remaining production caller; no source-golden tests or
new native/FS/process/UI/design fixtures. T271/T276 other legacy/qualifier cleanup
and final convergence remain open; this is a bounded source cut, not full goal.


## T319 — native compatibility metadata follows current bundle (2026-10-31)

The retained native-bundle gate now requires format4 and verifies actual app/
Isar/optional executor hashes, exact current source five-lock build identity and
absence of separate old exe. Sixteen required phases include engine and MCP,
not deleted locald analysis/tests. Historical shortened runtime evidence is no
longer accepted even for outdated source. Native evidence/ABI/hash/current-source/
independent review/activation checks remain mandatory and are not satisfied by
RAM metadata tests. Exact interface/limits are amended in
[native artifact](native-artifact.md). Pure RAM composer and retained-metadata
validator share current lock names and reject invalid Unicode, type/case/schema/
root/DLL/source binding; eight added unit cases bring the PS suite to16groups.
No build/provider/receipt/activation or Native/FStest is executed or qualified.
Remaining Native qualification producer/procedure cleanup and broad T271/T276
acceptance stay open; no new feature package or backwards-compatible branch.

## T321/T343–T345 — private worker power intent (2026-10-31)

Power is a private VM control of the existing desktop worker, not an MCP method,
an external API, a persisted job or an independent service. MCP requires the
running ServerDeck application, including its tray lifetime. When the application
is absent, its same-executable stdio connector can only fail locally to stderr
with a nonzero exit; no server response or application autostart is possible.

The spawn capability authenticates the closed frame
`{kind: power, epoch: int, suspended: bool, expiresAt: int}`. Epoch and absolute
monotonic microsecond deadline are positive signed63-bit values. Epoch increases
per controller incarnation; overflow retires the controller. Root ignores older
or duplicate epochs, rejects deadlines over30s ahead, and still applies an expired
suspend fence. Resume has the original at-most30s deadline; expiration starts
common shutdown. Malformed authenticated power controls fail closed. No ordinary
sequence/correlation slot is consumed, including when all16ordinary slots wait
for physical replies. Shutdown/waitClose retain their reserved controls.

Controller immediately masks readiness, stops old owner proxies and retains their
actual detach futures. One microtask flush coalesces same-turn intents to the
latest epoch. Before mailbox delivery the connection retains only one power
intent alongside its existing26control limit. It delivers power, then the private
closed `{kind: begin}` frame, then queued controls. The normal worker entry accepts
begin only once with the spawn capability; it starts Root with the original boot
deadline. Constructing the mailbox or recording early power opens no workspace
and does not start Host. Power alone never spawns a worker or an application.

Root applies the recorded fence synchronously after the ordinary Host.start call
begins, before awaiting it. Each newer intent fences the same Host immediately on
receipt, including a resume without a preceding suspend callback. It retires old
window bindings; one owned pump observes physical pause/window closure and the
latest intent. No pending resume can open a superseding epoch. Early resume may
release the original startup checkpoint, but the pump does not wait on the start
reply and block a newer suspend. Original startup retains its30s budget and busy
classification; startup completion emits Ready only for the latest restored epoch.
Shutdown releases paused startup for cleanup and retains all physical ownership.

Root reports the closed frame `{kind: power, epoch: int, status: WorkerStatus}`.
The new phases are suspending, suspended and resuming, with NOT_READY and either
no readiness yet or recovering readiness with the pinned generation and no
workspace/features. Controller discards older epoch acknowledgements; it admits
Ready only after current Root success and actual old owner detaches. Older
desktopStatus/readiness/attach replies settle their original charged controls
with NOT_READY and cannot overwrite current status. The final initial started
reply cannot downgrade a stronger current power Ready acknowledgement. Fresh
owners use new bindings on the same worker; mutations are never replayed.

Resume's absolute deadline has its own single cancellable Root observer from
receipt through pause/window drain, Host restore and any remaining startup.
Superseding power, successful current Ready or shutdown cancels that observer.
Expiry initiates common shutdown even while physical drain is pending; pending
operations and the workspace lease remain owned until actual cleanup completes.
Deferred Ready cannot overwrite a subsequently accepted terminal status of the
same epoch. Its pinned generation is validated synchronously on receipt, before
waiting for parent detaches; asynchronous acceptance failures retire the
controller through its existing fail-closed path rather than escaping as an
unhandled Future.

Public refreshReadiness and refreshDesktopStatus return the controller's accepted
WorkerStatus at their own continuation, after validating the original Root reply.
They cannot expose raw Root Ready while parent detach is pending, or an earlier
Ready when a newer intent arrived between reply delivery and public continuation.
Desktop counts retain the validated metadata snapshot; status/generation/workspace
admission follows the controller barrier. Correlation slots still settle only on
their actual replies; this projection does not cancel or replay any control.

The Host/pool publication guard accepts discovery I/O before invoking its
asynchronous protected writer. The writer revalidates runtime, owner, lease,
generation and activated-server identity after awaits. A later pause does not
invalidate already accepted I/O merely because readiness became recovering.
Pending publication remains owned and its admission is still fenced by Host.
This introduces no alternate proof or compatibility path.

Acceptance uses actual controller/Root/Host classes with RAM bootstrap, clock,
resource and reply ports: strict frames, bounded1000-intent coalescing, full16slot
quota, early startup/busy/expired resume, superseded physical restore, old replies,
fresh owners and shutdown during early pause. Native/isolate/UI/FS/SSH/process
execution is excluded. Desktop power event wiring, native phase projection,
fresh UI attachment and the complete T326 capability matrix remain open under
T321; this bounded worker implementation does not establish platform readiness.

## T321/T349–T350 — Windows desktop power binding (2026-10-31)

The normal Windows FlutterWindow observes WM_POWERBROADCAST before forwarding
the message to Flutter/plugins. PBT_APMSUSPEND posts the private desktop action
suspend; PBT_APMRESUMEAUTOMATIC posts resume even if the suspend callback was
missed. PBT_APMRESUMESUSPEND is subsequent user activity and does not trigger a
second restore. Processed power messages return TRUE if Flutter did not handle
them. These callbacks only enqueue intents; they do not wait for cleanup, veto
sleep, launch another engine or promise that Windows will deliver every callback.
See [WM_POWERBROADCAST](https://learn.microsoft.com/en-us/windows/win32/power/wm-powerbroadcast)
and [automatic resume](https://learn.microsoft.com/en-us/windows/win32/power/pbt-apmresumeautomatic).

Before Dart desktop initialize, Native retains one latest optional power intent,
replacing earlier events. Dart subscribes to desktop actions before requesting
initialize. The native handler marks the channel ready and flushes its pending
intent before replying to initialize; ordinary engine start therefore sees early
intent through the existing Root/controller queue. Later actions are forwarded
immediately on the same private method channel. Native has no engine/store/MCP
authority. Its status allowlist now includes suspending/suspended/resuming with
the same existing bounded MCP session count; tray/menu/close/Exit stay unchanged.

DesktopLifetime sends each action directly to DesktopEngineControl.setSuspended
without waiting for an earlier physical restore. It invalidates the private
window epoch on each intent while preserving visibility and remembered section.
The existing DesktopApplication FoundationApp key disposes old presentation
models/clients; old controller owner interests are already synchronously retired.
Hidden windows stay hidden and do not create an owner during restore. A visible
window may display its existing unavailable/startup presentation; it receives no
private Ready data while the controller gate is closed.

One status sample is physically owned at a time. Power bursts request one more
sample; a response from an older power revision cannot update the tray or finish
UI recovery. One pending2s poll timer is retained. After a current requested
resume is sampled Ready, DesktopLifetime increments the window epoch once more
and clears that recovery request. A fresh FoundationApp/BootstrapController then
gets a new owner/client/snapshot on the same worker; it never reuses cursors or
replays mutations. A newer suspend before Ready supersedes that restoration.
Power callbacks after confirmed Exit initiation or final process closure are
ignored, preserving the common shutdown/CloseBlocked ownership path.

DesktopEngineHost.start awaits the one controller start but returns the current
accepted controller status, so an initial historical resuming reply cannot block
a fresh post-restore client. A confirmed busy startup remains the durable busy
explanation after automatic contender cleanup. This is presentation startup
projection only and does not retry or replace a worker.

Acceptance consists of RAM policy units for early initialize, visible/hidden
epoch invalidation and fresh restoration, stale/burst status ordering, one sample
owner/timer, Exit races, current post-start projection and durable busy. C++ power
dispatch/early buffering/phase allowlist are checked by source review and MSVC
syntax-only /Zs. No native power delivery, UI/design/widget execution, isolate,
process, filesystem or platform qualification is claimed. Full T321 remains open
until T326 capabilities and resume binding are implemented and reviewed.

## T322/T356 — sampler parity RAM I/O boundary

T322 acceptance exercises the real RemoteReadService, TrustedConnectionService,
owner read adapter and MCP read adapter/router with actual contexts. It must not
substitute an echo service, forge a TrustedOwnerReadContext/TrustedMcpContext,
register a role from metadata, open Isar, run sockets/SSH peers, spawn the key
parser isolate or launch a native executor. The following internal I/O extraction
provides the required RAM seam without changing domain methods or wire schemas.

### One actual pool and one I/O provider

Keep SshTransportPool, reservations, SshLease, SshAttempt, typed fixed read and
executor policy as the real implementation. Extract socket/key-worker/SSHClient
construction and its owned disposal from _SshOperation into a native I/O provider
in the same ssh_transport library, with one implementation of that native logic.
There is no legacy path, compatibility wrapper or alternate transport registry.
SshTransportPool receives one engine-owned I/O factory at construction; the normal
composition selects the native provider, tests explicitly supply a RAM provider.
It is not configurable by a wire parameter, environment, profile, grant or role.
TrustedControlServices may receive this dependency at its engine-only composition
boundary and must use the same pool for connections, probes, reads and executors.

The I/O boundary consists of factory, attempt, client and byte-session interfaces:

| Boundary | Contract |
| --- | --- |
| Factory start | synchronously returns an owned attempt for validated SshEndpoint, opaque SshCredential or probe, existing remaining connect budget and host-pin verifier callback |
| Attempt | result Future of a client; settled Future for all owned key/socket/client creation and disposal; idempotent synchronous cancel that does not manufacture settled |
| Client | done Future, execute of the engine's already selected fixed command yielding a byte-session, idempotent close Future |
| Byte-session | Uint8List stdout/stderr streams, stdin byte sink, done Future, nullable exitCode and idempotent synchronous close |

Names and private wrapper classes are implementation details. Byte-session
execute is only an internal engine/provider interface: no public owner/MCP tool
receives a client, command selector, script or path. The existing closed
SshReadRequest selects commands and quotas; the fixed sudo executor path/framing
is unchanged. RAM sessions feed controlled bytes and completion/error events
through the same real read capture/parser, never manufacture SshReadOutput or
ConnectionReadValue success DTOs in place of that policy.

The pool owns admission and original15s connect timer, at most2transports including
reservations, verified host pin, result publication, all read/executor work and
the physical release of the slot. The native provider reports the observed pin
through the verifier callback. The pool compares it with the required immutable
pin and never publishes a connected SshLease unless that callback accepted it and
the current budget is live. The native provider must not offer a password before
the callback accepted; existing one-use password and key parsing/KDF restrictions
remain. A provider that returns a client without verification cannot manufacture
a usable lease. Probe intentionally rejects authentication, publishes only a
valid observed pin after actual provider drain, and never becomes a connection.

The native provider retains existing ownership of late key-worker/TCP creation,
SSH authentication, sink/client/socket completion and safe error mapping. Its
remaining deadline cannot restart the pool's original timer. A stop during a
factory call must cancel the returned late attempt and still await its settled
future. A late client is closed and drained, never published. Pool suspend/close
await that physical work plus read/executor drains; logical timeout/cancel cannot
release either of the two slots. Preserve4channels per lease and original read30s,
executor open/request5s, fixed output/response bounds and shutdown behavior.
No source branch bypasses these guards for a RAM provider.

### Repository key handle and time seams

Keep StateStore and its actual schema3 validation/custody behavior. The existing
owned McpGrantKey return handle becomes an interface with grant, McpClientKey and
close, implemented by the existing private native-store holder. The holder's
normal open/disposal logic is retained once; no public constructor mints an
authorized context or a native proof. A RAM StateStore supplies validated current
grant records and actual McpCredentialCustody/HMAC key handles under this same
repository return contract. It must not fake successful grant authorization,
_Sessions internals or parser/private state with noSuchMethod. Unexpected
repository/native effects fail the unit immediately; reads and declared ownership
cleanup are accounted. No StateStore write/private transaction API is exposed or
rewritten merely to enable these read tests.

Owner contexts come through actual HostAuthority/EngineSessions and admitted
owner gateway calls with RAM proof ports. MCP contexts come through the actual
bootstrap/grant-open/HMAC protocol with RAM verified-channel/proof ports and
current grant authority. Current scopes, server allowlist, grant revisions and
revocation are rechecked by the real policies before and after I/O. Key close and
late proof ownership remain real; a key handle is not a parsed permission grant.

RemoteReadService accepts an engine-owned EngineClock for cache/cursor/history
time and observation receipt timestamps; normal composition uses SystemEngineClock.
RemoteReadOwnerApi uses that same clock for its60s handle retention. Parsers accept
the supplied receipt time while preserving independent remote observedAt values;
CPU/source deltas still follow actual parsed data. This seam cannot be set over
IPC and does not change native proof deadlines, session leases, wall-clock grant
expiry, operation cancellation or default intervals. Timer/deadline ownership
stays in the current operation classes; no shorter production test defaults.
RAM tests distinguish the cache clock from authority/session clocks when isolating
an expiry boundary, rather than treating expired authentication as cursor proof.

### Existing semantics and acceptance matrix

State refresh is one aggregate collector for system/metrics/packages/units for a
current connected profile identity; same authorized UI/MCP interests join it.
Each waiter retains its own original budget, authority and response interest.
Cancelling/revoking one waiter cannot publish its result or extend the collector's
original budget. Remaining currently authorized waiters may continue; loss of
the final waiter stops interest but the old physical group occupies its slot
until drain. A changed profile/access/trust/connection identity retires old work
and cursors. No late old result populates a current cache. The existing cache
identity includes the full current target binding; no global alias/principal cache
or watch/topic API is introduced.

Journal/log filters and cursors are separate read kinds, never state-cache data.
Configuration/recipes remain typed executor-backed reads with their existing
scope and resource rules; absent enrollment must remain EXECUTOR_UNAVAILABLE,
not synthetic success. Owner and MCP call the same services and preserve their
different method permissions. Tests of read-kind separation need not implement
a new generic collector for every method or silently merge differently authorized
logs/configurations. Preserve source-error/partial/stale observations, no secret
or raw logs in Isar, and the existing result sanitizers.

Preserve and separately verify the following existing policies:

| Policy | Required RAM evidence through actual classes |
| --- | --- |
| List/settings snapshot poll2s | EngineApiClient scheduled callback through real owner gateway/foundation/coordinator over RAM StateStore, coherent current snapshot, no duplicate target refresh; no UI/widget execution |
| Target state refresh minimum5s | healthy concurrent owners/MCP share exactly one fixed-source sequence; fresh cache suppresses physical repeats; expiry permits a new collector |
| Typed owner start/status/cancel | stable per-principal operation ID, repeated status does not restart I/O, cancel affects only that interest, foreign IDs denied |
| MCP request/poll/cancel | same actual operation/read service and current scopes; source-level read handle and router correlation remain distinct, no remote effect replay |
| Target/authority isolation | distinct profiles and identity revisions never reuse old results/cursors; read does not acquire logs/plan/apply privileges; revoke and session detach retire only their interests before output |
| Transport and work bounds | actual pool two-slot limit and late drain retention; four channels/lease; read work48 total/16 per actor; owner read handles16 and60s retention |
| State cache | refresh reuse5s; inventory5min, metrics stale15s, history120points/10min, fitted per-target parts1536KiB, aggregate64MiB; boundary/over-bound states remain stale/unknown/truncated rather than false success |
| Cursors and logs | HMAC/principal/filter/identity/readKind binding,5min expiry,128cursors/8MiB cursor budget; journal ring500 and64MiB aggregate, bounded source output/capture and current-scope checks |
| Failure/late completion | connect verification failure or timeout, partial source error, final-interest cancellation, revoke/target retirement and suspend/close hold real pool/group/read/proof ownership until settled |

The poll2s policy is the existing Local API list/settings snapshot cycle. It does
not replace target5s minimum sampling, owner-operation status500ms or MCP bridge
read polling250ms. Existing method deadlines and retention remain unchanged;
tests use scheduled/clock seams and RAM byte events, not wall-clock SSH fixtures.
Large-bound tests remain finite RAM fixtures; no reduced production quota is
introduced to make a passing test cheaper. Typed validation, source code review
and all mandatory full checks plus independent code review are required. Passing
these units is not native SSH, crypto-provider, key-isolate, executor, OS transport
or release qualification.

An authority handoff within an existing state group may retry the affected fixed
source after the old actor is cancelled/revoked, under a remaining currently
authorized waiter and the same original group budget. The cancelled read remains
physically owned and charged until settled, including its channel/proof drain;
no old actor output is published and no second group is admitted in its place.
This preserves existing _buildRefresh retry semantics rather than treating a
new authorized source attempt as an automatic replay of a remote mutation.

### T361 — provider failed-drain semantics

Successful attempt/client/session completion confirms its declared physical drain.
A failed settled/done/close Future, or synchronous throw from cleanup, is not a
closure proof. The generic boundary observes owned completion Futures immediately
on receipt and captures synchronous cleanup errors. It reports only the fixed
SERVICE_UNAVAILABLE category through public operation completion, seals pool
intake and keeps the failed operation/physical slot charged. The failed pause
cannot authorize resume; a later successful callback does not clear this terminal
failure or create a replacement pool. Normal result/authentication failures still
use their existing safe codes when physical cleanup itself succeeds.

Known failed drain completes public settled with that error rather than leaving
it pending behind an escaped run Future. This error does not authorize teardown
of the store/runtime/writer lease. The operation still owns its late client,
provider and channel work; cleanup attempts and observers for all other owned
resources continue even when one cancel/close throws. A pending remainder remains
owned until its own completion. Read/executor cleanup errors similarly retain
their unconfirmed channel, fail public completion and retire the parent lease.
The connection registry treats an errored lease completion as target retirement,
so it cannot keep advertising the failed lease as connected or publish its late
response. Whole Host shutdown retains its existing failure/CloseBlocked policy.

RAM regression acceptance includes provider settled error, throwing cancel/client
close/byte-session close, another healthy connection stopped during the same
drain, probe suppression after failed drain, retained charged slot/intake fence
and rejection of resume. No raw provider exception or claimed native closure is
returned. The normal native provider retains its prior library close/done error
normalization; this defines safe semantics for failures of the new general I/O
boundary, not qualification of an actual native close failure.

T362 clarifies the same ownership rule for byte-sessions: register observation
of session.done immediately when execute returns its session, before waiting for
stdin.close or stream completion. A known session cleanup failure immediately
fails that read's settled or executor channel's done with SERVICE_UNAVAILABLE,
even while a remaining stdin/stream/provider Future stays pending. Remaining
physical work keeps its owned observers and charged channel/transport; the error
does not cancel the obligation to drain or permit resume. A successful complete
drain, in contrast, drops retained provider/client handles as well as releasing
the slot, so a closed public lease does not retain native authentication state
through the provider's completed result Future.
## T323/T369–T373 — transactional storage dependency (2026-10-31)

This section refines FR-SVC-EMB-07/14/15, AC-SVC-EMB-07 and
SC-SVC-EMB-03 inside this existing feature. Full24-tool permission parity must
exercise actual router, domain services and StateStore writes. Existing scripted
gateway tests and read-only repository doubles cannot establish mutation parity.
The extraction below preserves schema3 and the one writer; it does not introduce
a second repository, domain implementation, compatibility mode or wire API.

### Responsibility and composition

`packages/serverdeck_engine/lib/storage/workspace_storage.dart` defines an
engine-owned Dart persistence port. `isar_storage.dart` implements it using the
existing pinned Isar SDK, record schemas and native byte preflight. StateStore
owns its storage handle and remains the sole domain writer. Production root uses
the Isar provider unconditionally. Provider injection is a trusted same-isolate
composition dependency of StateStore.open, never argv, preferences, RPC, grant,
owner request or a recovery choice. There is no RAM fallback on native failure.
The RAM provider lives only in engine test/support and is not a release input.

StateStore retains admission, common ownership checks, queue32, idempotency,
HMAC/receipts, typed commands, policy checks, CAS, row identity allocation,
snapshot validation, authority publication and conservative unknown outcomes.
The provider knows ordinary rows and transaction mechanics only. It cannot
grant a permission, synthesize a domain response or publish a snapshot/lookup.
Current credential files, metadata enrollment and KeyCustody ports remain in
their existing owners. Fresh workspace creation remains the existing isolated
Workspace path; this dependency serves adoption and writes of an existing store.

### Fixed row and transaction interface

Use an enum with exactly the existing16 collection identities: StoredWorkspace,
StoredSettings, StoredProfile, StoredCredential, StoredReceipt, StoredHostTrust,
StoredMcpGrant, StoredDelegation, StoredAutomationProfile,
StoredAutomationRevision, StoredAutomationPlan, StoredAutomationApproval,
StoredAutomationJob, StoredDesiredState, StoredAutomationEvent and
StoredAutomationReceipt. The mapping to persisted names is fixed in source.
No caller-defined collection, path, query, schema or SQL is accepted. StoredRow
retains its nativeId, exact payload string and nullable entityId; returned rows
and lists are detached and immutable. Domain validation still parses the payload.

An owned WorkspaceStorage implements the existing WorkspaceRowSource for
snapshot reads and adds writeTransaction, close and capacity-failure
classification. writeTransaction takes one asynchronous callback receiving a
WorkspaceWriteTransaction. That transaction exposes only get(collection,id),
getByEntityId(collection,entityId), put(collection,row) returning the written
native ID, and delete(collection,id) returning whether the row existed. Lookups
return StoredRow or null. Explicit IDs are in1..9223372036854775807; no implicit
auto-increment, replace-by-unique-key or silent ID reassignment is permitted.
Singleton workspace/settings rows use ID1 and no entityId; all other families
require entityId and retain their existing case-sensitive unique entity indexes.
Duplicate entity keys at different IDs abort, rather than overwrite another row.
The storage port reports invalid shape/ID/collection and duplicate-key failures
as STORAGE_BLOCKED. Empty strings and JSON business validity remain subject to
the unchanged snapshot/domain validators, not an alternative provider policy.

The transaction is active only within its callback; escaped references reject
calls after callback settlement, close or abort. All submitted operations must
settle before commit; a callback may not start unawaited row operations. An
operation failure aborts the transaction even if caught by its callback. Nested
transactions are rejected with STORAGE_BLOCKED. Concurrent transactions observe
one committed view; read callbacks see all16 families from one transaction,
never a partially published write. Write callback error preserves its original
typed error for StateStore policy classification, and no row is committed.
Provider close seals new transactions, waits for admitted work and returns true
only after its actual owned handle has closed. False/throw is not a drain proof.

Snapshot reads retain the existing count/read contract and bounds1..51251 for
read limit, each family's lower existing caps, and64MiB aggregate payload cap.
There is no new queue, timeout, retry or resource budget: the existing StateStore
FIFO/tail, combined32 admission, enclosing request budgets and shutdown deadline
remain authoritative. Native open keeps name workspace, maxSizeMiB64,
relaxedDurability false and inspector false. Native conversion to/from the
existing16 Isar record classes occurs only in its adapter.

### One checked open and owned failure path

There is one StateStore.open algorithm for both trusted providers. It always
reserves the existing process-wide writer slot and performs the current checks:
live default-slot lease, exact owner/root, NativeStoreRuntime initialize and
revalidate, KeyCustody binding, owner-only ancestor directories, no adjacent
creation/upgrade stages, signed manifest (4096bytes), matching key wrapper
(16384bytes), bounded workspace.isar read (64MiB) and protected existing lock.
Their current ordering and error distinctions remain intact. These common
checks are not optional provider booleans and cannot be replaced by a supplied
WorkspaceSnapshot or by assigning StateStore private fields.

WorkspaceStorageProvider supplies a read-only preflight row source for the
captured bytes and exact directory, plus a per-open attempt object. StateStore
itself runs inspectWorkspaceSnapshot on that source, reads/validates enrollment
metadata, rechecks owner/runtime, then invokes the attempt's open. It then runs
the same inspector on the opened handle, requires exact pre/post row equality
(including native IDs and payload bytes), recovers lookups only after equality,
rechecks live ownership, and transfers the owned handle to StateStore. No
provider result is authority or substitutes for those semantic/custody checks.

The production preflight source is the existing NativeWorkspaceRows parser for
pinned schema3/MDBX bytes. Factor its current common semantic/enrollment checks
from preflightWorkspace without weakening that public entry. RAM test storage
may use a deterministic test-only byte encoding for its supplied row snapshot;
the RAM ProtectedFiles provides that same encoded input. It must decode captured
bytes, not ignore them and return an unrelated prebuilt graph. The test encoding
does not enter runtime readers, fixtures for native execution, or the on-disk
format contract. Such tests prove semantic/domain/open sequencing only, not
native DB byte compatibility or durability.

Provider rejects an already registered handle before open. The Native attempt
also retains the current second Isar.getInstance check immediately before open.
Before invoking a potentially owning native open, mark the attempt uncertain.
Its cleanup after a failed open may close only its returned handle or an SDK
registered handle attributable to this attempt's exact directory, never an
instance that predated this attempt. A throwing open with no attributable handle
is still uncertain. cleanup returns true only when no owning open was attempted
or a positive close was observed for the attributable handle; false/throw retains
the attempt and process reservation. Both normal StateStore.close and failed
open preserve the existing CloseBlocked/key/lease retention; there is no reset,
force-release, test-only constructor or second open after unknown close. Common
checks failing before an owning open release only the reservation they acquired.
Each attempt/handle cleanup is memoized and is not executed twice.

### Write, rollback and publication evidence

Replace direct IsarCollection access in foundation_writes,
automation_profile_writes, automation_plan_writes, owner_grant_writes,
automation_delta and automation_store_view with this single owned dependency.
All actual callbacks, explicit CAS checks, receipt digest/canonical request
checks, credential staging, readback, recovered lookups and publication ordering
remain in StateStore and the existing domain services. A put's returned ID must
still equal the requested ID. Preserve unchanged row IDs and exact payloads.

Runtime/owner proof is revalidated before and after writes as currently. Success
requires actual committed readback and the existing full graph/custody validation
before publication. Policy is checked at the existing before-effect boundaries;
grant expiry/revoke/allowlist changes do not acquire a new authority path.

Capacity classification is only a candidate for aborted-transaction readback.
The Native adapter recognizes exactly the two current pinned Isar3.3.2 messages
from native_failure.dart. The RAM provider may classify its own explicit capacity
fault; it cannot classify arbitrary exceptions or policy failures as capacity.
StateStore still returns RESOURCE_LIMIT only after the existing actual readback
proves the complete prior snapshot unchanged. Unknown commit, readback mismatch,
failed runtime proof, partial or failed close remain STORAGE_BLOCKED/CloseBlocked
with occupancy retained. No provider flag claims rollback or domain success.

### Acceptance and trace

| Requirement | Decision and implementation task | Required RAM/static evidence |
| --- | --- | --- |
| FR-SVC-EMB-07 / T323 actual writes | Fixed storage dependency T370/T371 | Actual StateStore.open and each mutation family, real receipts/HMAC/CAS and readback; unexpected calls fail |
| FR-SVC-EMB-14 target data | Same16 schemas and semantic gate T370–T372 | ID/payload preservation, incompatible/invalid graph, mismatch pre/post and wrong custody rejected before publication |
| Single writer and failure ownership | Checked open/attempt and scoped transactions T370–T372 | FIFO32 unchanged, rollback, duplicate indexes, escaped transaction, callback failure, unknown open/close retaining reservation |
| AC-SVC-EMB-07 / SC-SVC-EMB-03 | Actual24-tool matrix T373, aggregate T323 | Positive and denied paths of each catalog tool; scopes/target allowlist, expiry/revoke, owner forgery, validation, IDs, fixed safe errors, proof-to-effect/publication fences |

T372 RAM adapter tests exercise isolation, atomic rollback, uniqueness and
lifetime, plus actual StateStore cases using real fixture KeyCustody/lease/
ProtectedFiles/runtime ports. They must assert the resulting committed rows and
receipts, not a handler echo or a fake StateStore writer. Native adapter review
and static checks verify all16 class/index/ID mappings and exact pinned options;
no Native/Isar/FS/SSH/process execution is permitted. T373 uses actual MCP auth,
router and services, shared actual StateStore and authorized byte transport ports
for remote operations. A failed pre-effect auth case must prove no write/SSH
admission. Successful remote cases exercise the real framing/parser and command
policy; a scripted domain-success service is insufficient. Every catalog entry
must map to its own assertions. Existing T324/T325/T331 acceptance remains open
and cannot be closed from a24-tool matrix alone.

Mandatory full unit/static checks, links, and completed independent review apply
before acceptance. This design amendment itself requires link checks and a
completed independent read-only review before T370 implementation handoff.


### Plan receipt ordering — T378

A plan is compiled before its persistence admission instant. Its retained
`plan.create` receipt MUST have `createdAt >= plan.createdAt`; equal instants
remain valid. Equality alone is not required. Require exactly one creation
receipt for each retained plan, with the exact plan request ID, plan ID/digest
and origin/object grant identity. Earlier, conflicting and duplicate creation
receipts are STORAGE_BLOCKED. Keep current grant/target checks at admission,
plan lifetime checks, transactional writes and complete readback unchanged.
Acceptance uses actual StateStore RAM persistence at a later clock instant,
checked reopen/replay and malformed receipt graph rejection. This does not
qualify native storage or remote executor effects.


## Local job observation and recovery — T384

This completes the required decisions for T324/T331. It adds no new wire
protocol or version: existing format3 successful-result data gains observation
beside job in jobs_get/owner jobs.get and in each jobs_list/owner jobs.list row.
The existing generic result data object permits it. Inputs, methods, envelope,
AutomationJobRecord, mutation ACK/receipts and executor wire remain unchanged.
Existing jobs_events history remains durable history and does not gain observer
state. Runtime observation is neither a remote outcome nor an authority producer.

### Closed view and lifecycle

Every returned job has exactly one observation view with exactly generation,
attemptId,state,lastSequence,observedAt as defined in data-model.md. The current
engine generation and the job's hostAttemptId must match; normal read/origin/
allowed-target proof runs before exposing it. Field omission, extra fields,
invalid IDs/time/sequence/state or mismatched job attempt/generation are invalid
current-engine data, never a reason to fall back to an older view format.

TrustedJobService owns LocalJobObservations under automation/job_observations.dart.
The protocol DTO under automation/job_observation.dart validates data only. The
service uses the factory's existing read EngineClock (SystemEngineClock in normal
composition); changing that clock for RAM tests does not change grant authority,
write timestamps or existing driver/RPC deadlines. Freshness is strictly age<5s
in the engine monotonic domain, equality is stale; UTC observedAt records local
receipt after successful status/proof validation and is informational only.

No sample/opening-only/ended driver means detached. A valid nonterminal status
from a current active observer means attached until5s. A live observer with an
aged sample, or a sample invalidated by target identity change, means stale.
Driver stop, detach, close, suspend or accepted terminal/unknown status detaches
observation without erasing the last sequence/time or pretending to cancel root
work. Identity invalidation takes precedence as stale when a sample exists.
A newer valid sample under an explicitly authorized fresh driver can attach
again. Reading a view never opens SSH, schedules work, reconnects, submits,
reconciles, cancels or authorizes a step.

Bind callbacks to the service instance/generation, job/attempt/host, actual
session target tuple/registry and one private observer token. Replace/retire
invalidates the token; foreign/old callbacks cannot change the current sample.
The native/session/target/grant/store checks remain the only write authority;
no attached/stale flag permits or prohibits a server mutation. A projection is
a snapshot at preparation time and includes its last accepted receipt time.

The entry cap is the existing1250 retained jobs with one current token per job.
No unbounded per-poll callback/history cache. Do not evict current ordering facts;
a new entry beyond the cap returns RESOURCE_LIMIT. Prune only jobs absent from
the validated graph. Samples contain no challenges, credentials, secrets, free
text, shell, playbook body or reusable permission. The comparison facts for
same-sequence progress (state,step,epoch,failure/check results) are bounded by
existing32effects/checks and structural response limits. No new hash/receipt
pipeline; use structural comparison, not a persisted evidence digest.

### Remote sequence and terminal evidence

Retain the last accepted remote sequence/step/epoch in runtime for the current
attempt. Validate status against the actual enrolled session and immutable plan;
all three counters are nondecreasing, including across explicit same-generation
observer replacement. Same-sequence unchanged progress is a repeat observation;
conflicting state/step/epoch/failure/check facts at that sequence are incompatible.
Event windows/challenge material are not copied into the public overlay. Foreign
attempts, reversed progress and old target/generation callbacks cannot publish
terminal metadata or clear occupancy. Normal actor/target proof after the remote
await remains mandatory; the overlay cannot substitute for that proof.

A submit ACK is correlated admission, not completion. Its bounded nonnegative
sequence supplies a lower bound for the next status, not a local terminal edge.
Reconcile ACK requires exact attemptId, a valid existing executor state, boolean
childrenStopped and sequence0..int64max. Retain a floor at least both its sequence
and any prior accepted runtime status. Only childrenStopped=true allows a later
correlated, nonbackwards structurally valid terminal status (including all
required success postchecks) to publish terminal state. An ACK alone never does.
If childrenStopped=false, retain/publish unknown and occupancy even if a later
standalone reply claims terminal; another explicit authorized reconcile may
establish fresh stopped-child evidence. A pending/unknown status likewise keeps
occupancy; reconciliation never sends submit or authorize_step.

Cancel intent/ACK does not prove terminal. Only an accepted correlated terminal
status with the existing021 checks releases occupancy. Repeated or conflicting
late terminal cannot mutate an already terminal job/outcome; compare-and-swap
and current actual driver ownership remain mandatory. Once a valid terminal is
committed, a distinct approved plan on the same server/host can admit; do not
retain an observer-only lock indefinitely. Keep existing per-plan idempotency:
replaying/aliasing an admitted plan never starts another attempt.

### Recovery, owner projection and acceptance

Factory recovery uses only the checked current store, before routes publish.
Queued is safe unsent intent because running is durable before any submit bytes:
recover queued as cancelled/effects none. Recover running/cancel-requested/
reconciling as unknown/uncertain, preserving job/attempt/plan/authority IDs and
occupancy. Unknown/terminal need no duplicate transition. Recovery opens no
executor/SSH and restores no approval, challenge, selected-authority validity or
step permission. New generation observation is detached with null sample/floors.
Missing attempt/host, unavailable executor, changed trust or malformed replies
retain unknown occupancy; restoring access requires explicit current-authorized
connect and reconcile/cancel of the same retained attempt, never auto-apply.

AutomationController stores observation separately from job/outcome for selected
and listed jobs, checks current reply generation and matching attempt before
installing it, and retains existing response-interest epoch fencing. Engine
client loss detaches its displayed observation without changing remote job
state. Read failure marks a retained sample stale, no sample detached. The
existing jobs view displays this separate state/last receipt alongside the
remote result; observation labels do not grant authority, enable automatic
retry or reinterpret succeeded as unknown. Keep existing explicit control flows
and input bounds. Controller/policy unit tests only; no widget/layout/design or
native UI tests in this task.

Acceptance must use both pure model/DTO/controller units and the actual factory,
StateStore RAM provider, owner/MCP actors and framed byte peer. Cover fresh/5s
boundary/UTC jump, identity/old token/generation rejection and bounded entries;
queued/running/unknown/reconciling/terminal checked reopen without remote I/O;
loss of submit ACK, detach/suspend/close/revoke, unavailable or missing attempt,
reversed/foreign/late status, cancel intent and pending reconciliation, false
childrenStopped despite terminal status, valid stopped terminal/postchecks,
same-host admission after verified release, and no restored permits/resubmit.
Do not close T324/T331 from DTO/model tests alone. Full checks/links and completed
independent review/fix loop precede aggregate acceptance. No Native/Isar bytes,
real SSH/Python executor/process/engine-isolate/UI/build/release qualification.


## Accepted job control handoff — T391

This refines T389/T387 using the existing001/021 command and state graph. All
format3 tools/methods/ACKs, schema3 job/receipt IDs, original grant/authorityRef
and executor messages stay unchanged. There is no queue for apply/submit and no
new local service or background execution guarantee. Window close to tray does
not retire this component; app Exit/shutdown and suspend do.

### Admission, serialization and pending ownership

TrustedJobService owns JobControlContinuations in automation/job_controls.dart.
The component coordinates data/lifetimes, never supplies native authority.
Existing actual owner/MCP actors, queued StateStore writer, publication gate,
qualified enrollment and root session retain their responsibilities.

One workspace-local FIFO mutex covers cancel/reconcile admission through actual
metadata/replay readback and slot registration, plus activation/expiry metadata
work. Reserve its bounded interest before any new control metadata effect.
Waiting consumes the original invocation budget; a cancelled or expired waiter
that has not begun native work performs no write. An entered native operation
keeps the mutex/ownership charge through physical proof/gate/readback settlement,
even after its logical response is suppressed. Do not release the mutex merely
because the reply timed out. Neither this mutex nor a publication lease is held
while waiting for an old driver to drain or while the new driver runs root I/O.
The existing apply path is not enqueued in this coordinator.

For each nonterminal job retain at most one pending cancel slot and one pending
reconcile slot, under current generation/epoch and immutable job/attempt IDs.
Capture the already verified actual actor and immutable existing command, not
credentials or a wire role. Latest successfully registered current invocation
replaces only the same-kind pending slot. Repeated aliases do not add callbacks
or a list of requests; if a newer actor dies, do not resurrect an older slot.
An accepted control's stable ACK still means durable intent, not remote outcome.

Register new and replayed control invocations only after actual receipt/state
verification with current scope/origin/target proof. The same-ID explicit replay
may register a fresh currently authorized control invocation, including when an
older cycle ended unknown. Its mutation ACK, original job/attempt and permanent
receipt stay identical. It cannot submit again or restore an old permit.
Polling an existing operation ID does not register work or renew a deadline.

The original budget is30s from JobOperation admission/start, including mutex,
publication/storage and prior-driver waiting. Store its absolute monotonic end
once for that invocation using the existing engine clock. No handoff, pump,
retry or operation poll restarts this budget. A separate new explicit invocation
is independently authorized and may replace the pending slot with its own
start/end. Wall-clock jumps do not extend eligibility. Existing RPC/proof caps
still apply, and the active apply driver's2h limit is unchanged.

### Pump and physical completion

There is one coalesced service pump and one earliest-deadline timer, not one
listener/timer per replay. Each actual driver has one completion notification.
That notification may wake the pump only after actual opening/session, protected
proof and cleanup futures have settled positively; observer detach or logical
result alone is insufficient. Unknown/failed physical cleanup seals further
root activation and preserves existing failure/CloseBlocked ownership semantics.
Stale driver completion only removes its identical map entry and cannot replace
or stop a newer driver or recreate a pruned control.

Under the coordinator mutex, the pump prunes absent/terminal jobs, removes expired
or retired tickets and examines current durable state and driver ownership. It
does not await an existing driver: keep the slots/timer and return, relying on
its one completion notification. A ready job gets at most one new driver. Root
I/O begins only outside the coordinator mutex and after prerequisite native
publication/replay/readback work has completed positively. Install the chosen
current driver once before exposing a gap to another activation. If retired or
expired before run starts, complete it as a no-I/O uncertain continuation rather
than leaving an unstarted owned driver indefinitely.

Before activation, recheck generation/epoch, current actor/session/grant and
origin/target, remaining deadline and existing receipt correlation under the
actual publication gate. Open only the current explicitly connected, trusted,
qualified enrolled host for the same attempt. Revalidate after async preparation
and before every root dispatch; cap control proof/request budgets by the original
remaining time and existing per-call caps. Never start another dispatch after
deadline. A physical request admitted before the logical cutoff remains charged
to actual settlement; it cannot be declared cancelled or undone by timeout.

A pending reconcile may find unknown after the prior observer closed its own
cycle. Verify that same accepted command/receipt with current authorization, then
rearm unknown→reconciling/outcome null through the existing queued progress writer
and CAS before root I/O. This is continuation of an already verified explicit
intent: no new permanent receipt, request ID, apply, approval consumption or step
authority. Preserve immutable job identities and T390 retry predicates. If the
job is already reconciling, no duplicate rearm event; if terminal, drop pending
work without root requests. Failure to regain current proof never restores the
old actor or selected execution permission.

### Cancel versus reconcile, coalescing and fairness

Kinds keep separate actors and method restrictions. Cancel requires current
apply/target control scope (or actual owner); reconcile requires current read
scope (or owner). A reconcile actor never sends cancel or authorize_step, and
no control actor sends submit. Do not borrow the other slot's stronger context.

If both kinds are pending, one cancel activation may precede the pending
reconcile. After that attempt, give that reconcile a turn even if another cancel
alias arrived; no starvation by repeated stop intents. Across ready jobs use
FIFO/round-robin readiness, at most one activation per job per pump pass. Coalesce
repeated wakeups while queued/running rather than adding another pump interest.

A current apply driver may already observe the durable cancelRequested flag.
Keep a pending cancel as fallback until that driver has a valid correlated stop
ACK, or finishes without one. A validated stop ACK for the immutable attempt can
satisfy coalesced pending cancels without a second root request; it is not stopped
child or terminal proof. Validate the existing two-field cancel ACK's attempt
and closed existing executor state enum. Unknown ACK outcome does not set this
fact; an explicit fallback may resend only the same stable cancel request ID.

A standalone cancel continuation sends the stable stop intent and at most one
status query within its original remaining budget, then drains. It never sends
a step permit. For unknown/reconciling local jobs it preserves that state graph;
unknown still requires a separate explicit reconciliation for terminal. For a
nonterminal current result without sufficient completion proof, preserve/publish
unknown rather than polling indefinitely and blocking a pending reconcile. Do
not shorten or roll back the remote atomic step, or turn observer loss into stop.
The ongoing apply driver's existing1s polling/cancel handling otherwise remains.

A reconcile continuation performs the existing observational root method and
at most the following status query under T386: childrenStopped=true, correlated
sequence floor and required postchecks before terminal. Pending/unknown/missing/
malformed/false stopped proof ends unknown/occupied, without automatic repetition.
Another accepted explicit ticket can activate next, or a user can invoke again.
After a verified terminal, discard pending controls and permit the existing
admission policy for a distinct authorized plan; no observer lock remains.

### Expiry, loss, sealing and bounds

Timers only wake the same serialized pump. Cleanup/activation rechecks private
ticket identity and epoch under the mutex; a replaced ticket's late timeout
cannot erase or act for the newer one. Expired, revoked, detached or incompatible
actors perform no new root I/O. If no live pending reconcile and no active
reconcile driver owns a reconciling phase, conservatively transition it to
unknown/uncertain through the existing queued CAS writer. An active reconcile
owns its cycle until drain; expiring a waiting alias must not overwrite it.
Terminal outcomes are immutable. If cleanup/readback cannot be established,
retain occupied/blocked state and actual failure/ownership; never claim release.

Seal before suspend/close drain: retire epoch, cancel the single timer, reject
unstarted admissions and prevent activation. Drop pending contexts without
sending root cancel/reconcile as a side effect of local exit. Charge entered
native admissions/pumps and any late accepted registration through real
settlement; a registration completing under the sealed epoch must leave no new
root work and conservatively finish pending local uncertainty. Wait all owned
coordinator/native/driver futures before positive pause/close. Resume uses the
same service/store but fresh explicit invocations only; reopen/new generation
reconstructs no tickets or stop-ACK permissions from receipts. Physical uncertainty
continues to block generation replacement exactly as before.

Resource limits: at most250 nonterminal entries, at most500 pending actor slots,
at most33 mutex interests including the one coalesced pump and existing32 job
operations, one service timer, one completion wakeup per actual driver. Reserve
capacity before a metadata effect; RESOURCE_LIMIT cannot silently discard an
accepted ticket. Prune terminal/absent entries and their cached stop facts, not
active ordering/evidence. Time scheduling is a normal internal clock/Timer port
with the standard Timer in production and manual RAM scheduling in units; no
public configuration, runtime prerequisite, package or native hook is introduced.

### Acceptance boundary

T393 must exercise actual factory/store/owner or HMAC MCP/root byte ports with
an explicit physical-close latch: local unknown accepted while old stdin/channel
cleanup is still charged, control ACK and durable reconciling, zero new root calls
until positive drain, then one current authorized reconciliation and no resubmit
or permit. Model-only slot tests do not close T389.

Cover concurrent same-kind replacement/retired timer, both-kind actor separation
and one-cancel fairness, original30s wait expiry with a still-live grant, scope
revocation and target/enrollment change while pending, terminal before dispatch,
false stopped proof, callback/generation retirement, suspend/exit with pending
native work, mutex/slot bounds and no new root action on local loss. Verify fresh
proof, exact job/attempt/authority IDs, metadata CAS/readback, event/receipt
identity and absence of duplicate submit/step effects. Keep pure scheduling and
actual metadata/driver evidence separate. Full checks, links and independent
review/fix loop are required; no Native/Python/Isar/realFS/SSH/process/engine-isolate/
UI/design/build/install/release readiness is established by these RAM assertions.
