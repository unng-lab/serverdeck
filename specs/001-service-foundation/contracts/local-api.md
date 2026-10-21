# Local API v1 — 001.1

Normative client/locald interface. [Data model](../data-model.md), [runtime](runtime-storage.md). Только локальный Windows named pipe, не HTTP/TCP. API major1/minor0.

## Framing и limits

Pipe duplex byte mode/overlapped I/O: unsigned 4-byte little-endian length, затем ровно length UTF8 JSON bytes. Request≤256KiB, response≤8MiB. Zero/oversize/invalid frame закрывает канал без input echo. Depth≤16, repeated keys/unknown fields/invalid UTF8 отклоняются. Partial frame deadline5s; CancelIoEx и закрытие handle после completion. Handshake frames≤8KiB. ≤16 pending requests/session, ≤8 sessions, ≤32 queued mutations глобально. RESOURCE_LIMIT не накапливает очередь.

Authenticated request `{v:1,id:UUID,sessionId:string,method:string,params:object}`. Response `{v:1,id:UUID,generation:UUID,result:object}` либо `{v:1,id:UUID,generation:UUID,error:{code:string,boundary:"local",retry:string}}`; result/error взаимоисключающие. Counters/revisions decimal strings, timestamps UTC, tokens base64url без padding. Unknown method→UNSUPPORTED, extra params→VALIDATION. UI связывает ответ с id/generation; stale/чужой ответ не меняет model. RPC deadline5s не отменяет начатую durable transaction. Ordinary error не закрывает канал, auth/framing error закрывает.

## Authentication, grants, revocation

1. После connect обе стороны получают kernel peer PID через GetNamedPipeClientProcessId/GetNamedPipeServerProcessId, открывают process handle с PROCESS_QUERY_LIMITED_INFORMATION и token через OpenProcessToken(TOKEN_QUERY), проверяют TokenUser SID и image path/hash по dev manifest. Handle удерживается до окончания handshake; peer должен оставаться живым, PID/image/creation time проверяются повторно перед grant. Любая ошибка native query закрывает канал, без принятия supplied PID и без privilege elevation. ImpersonateNamedPipeClient/RevertToSelf не используются: thread identity никогда не меняется, поэтому порядок чтения сообщения и Dart worker thread affinity не влияют на SID check. Pipe DACL/remote rejection, peer identity и HMAC проверяются вместе; PID не самостоятельное доказательство.
2. После успешной peer check locald создаёт serverNonce32bytes и посылает публичный `hello:{product:"serverdeck-next",apiMajor:1,apiMinor:0,workspaceSlot:"default",generation,serverNonce}`. UI сверяет descriptor/manifest/peer и посылает bounded `authenticate:{clientNonce:32bytes,clientBuildId,requestedCapabilities:[...],proof}`. До его чтения/проверки и повторной peer check не выдаются session/grants и не обрабатываются ordinary requests.
3. Proof HMACSHA256 bootstrapToken по UTF8 `client\n1\ndefault\ngeneration\nserverNonce\nclientNonce\nclientBuildId\nrequestedCapabilities`, последний элемент comma-joined sorted unique capabilities, nonce base64url. Ответ `authenticated:{sessionId:random32bytes,capabilities:[...],idleLeaseSeconds:60,proof}`: HMAC по той же строке с первым словом `server`, затем `\nsessionId\n` и comma-joined sorted granted capabilities. Deadline5s, nonce one-use, constant-time comparison; никакого журналирования token/proof/nonce. Re-auth на канале запрещён.
4. Allowlist: `readiness.read`, `profiles.read`, `profiles.write`, `settings.read`, `settings.write`, `mutations.read`. Обычный UI запрашивает все; approved test read-only client может запросить subset. Grant не превышает запрос; отсутствующий cap→FORBIDDEN. Нет SSH/executor/export caps. Unapproved image не становится доверенным из-за possession token.
5. Session привязана к pipe/generation, не переносится на новый канал. Heartbeat20s/idle lease60s; authenticated request продлевает. Disconnect/expiry освобождает session и не начатые запросы, не удаляет receipts и не отменяет уже начатую transaction. При рестарте новый generation/bootstrapToken, старые grants недействительны, необходим новый handshake.

BootstrapToken — отдельный CurrentUser DPAPI secret, доступный UI; не root key БД. Это защита от чужого/случайного клиента в заданной модели угроз, не от полностью скомпрометированного текущего пользователя.

## Methods и schemas

Управляющие disconnect/close не зависят от quota3 ordinary native worker commands: они должны отменить pending read/write/drain даже при заполненной quota. Это относится и к epoch-bound operational peer disconnect: он допускает очистку текущего соединения после отказа проверки личности, но не может закрыть заменившее его соединение; клиентский peer не получает server disconnect. Повторный disconnect разделяет один completion; новые ordinary commands до его окончания отклоняются, успешное завершение допускает повторный accept того же slot. Неуспешный teardown не трактуется как успешно освобождённый endpoint.

Для session.close transport после write ждёт consumption outbound buffer до5s, затем disconnect; abandoned/non-reading peer по timeout закрывается без гарантии доставки. Native worker использует FilePipeLocalInformation/WriteQuotaAvailable и asynchronous bounded10ms waits, не blocking FlushFileBuffers на owner/worker event loop. Пустой kernel buffer не означает завершение drain, пока имеется принятый write, включая запуск его native I/O: drain ждёт завершения write и consumption его bytes. Drain выполняется только server end, не более одного на slot; close отменяет ожидание, native metadata buffers удерживаются до подтверждённого завершения/cancellation query. Known immediate I/O failure не считается queued только из-за provisional OVERLAPPED.Internal; retained pending buffer освобождается после actual completion. Ни чтение закрытого канала, ни отсутствующий/нечитающий клиент не дают неограниченного ожидания RPC. Владение slot и его reuse сохраняются у service owner.

Accepted-connection transport связывает один ServerHandshake и ApiServer с одной SessionRegistry и уникальным channel identity; владелец предоставляет callbacks owned native PipeWorker read/write/disconnect и verified manifest peer check. Он читает ровно header/payload, сохраняя coalesced bytes в kernel pipe, использует общий deadline5s для handshake и абсолютный deadline5s от первого фрагмента ordinary frame. Между frames допускается idle ожидание до lease60s; lifecycle владеет expiry/shutdown и закрытием ресурсов. Одновременно остаются не более16 dispatch/reply операций, включая ожидание единственного writer; дальнейшее чтение получает backpressure. Ошибка framing/auth/I/O отзывает session и отменяет/drains native read через disconnect без echo; running durable mutations завершаются через coordinator, не отменяются. Logical session.close пишет reply прежде physical disconnect. Slot accept/reuse, bootstrap/watchdog и связывание lifecycle с transport остаются ответственностью owner composition T026–T028.

Dispatcher принимает уже собранный bounded frame на authenticated channel. Strict JSON/envelope failures не имеют безопасной корреляции: transport закрывает channel без input echo; session/channel mismatch также закрывает channel. Structural envelope validation не разбирает бизнес-значения; method capability проверяется перед semantic params validation и backend lookup. Unknown method проверяет session, затем UNSUPPORTED без business parsing. Ordinary ошибки возвращаются безопасным correlated response с текущей generation; pending slot освобождается finally. `session.close` отзывает logical session/detaches requesters и возвращает `{closed:true}` с close-after-reply disposition: transport пишет ответ и disconnects канал. Readiness после обнаруженного coordinator/storage failure не сообщает ready: STORAGE_BLOCKED становится storage-blocked/reason STORAGE_BLOCKED; ordinary/status queries не возвращают пустую модель/not-found. Полная transport интеграция остаётся обязанностью T027–T029, внутренний dispatcher не открывает endpoint сам.

Кроме readiness/session методы доступны только ready. Grant проверяется до разбора приватных бизнес-параметров. Limits/types в data-model. Все listed поля обязательны, кроме прямо отмеченных create defaults. Это replace-document, не PATCH.

| Method / cap | Params | Result |
| --- | --- | --- |
| readiness.get / readiness.read | `{}` | `{state,reason:null|code,product,apiMajor:1,apiMinor:0,workspaceSlot:"default",workspaceId:null|UUID,generation,storageSchema:1,features:{profiles:true,ssh:false,jobs:false,backend:false},clientPlatform:"windows-x64"}`; ready всегда имеет проверенный non-null workspaceId |
| session.ping / authenticated | `{}` | `{leaseSeconds:60}` |
| session.close / authenticated | `{}` | `{closed:true}`, затем disconnect |
| profiles.list / profiles.read | `{}` | `{storeRevision,profiles:[ProfileView]}`, sorted name/id, без pagination при250 |
| profiles.get / profiles.read | `{profileId:UUID}` | `{storeRevision,profile:ProfileView}` или NOT_FOUND |
| profiles.create / profiles.write | `{profileId:UUID,name,address,port:22,sshUser,tags:[],credential:CredentialAction}` | MutationResult |
| profiles.update / profiles.write | `{profileId,expectedRevision,name,address,port,sshUser,tags,credential:CredentialAction}` | MutationResult |
| profiles.delete / profiles.write | `{profileId,expectedRevision}` | MutationResult, deleted true |
| settings.get / settings.read | `{}` | `{storeRevision,settings:{revision,theme,reduceMotion,selectedProfileId}}` |
| settings.update / settings.write | `{expectedRevision,theme,reduceMotion,selectedProfileId}` | MutationResult |
| mutations.get / mutations.read | `{requestId:UUID}` | `{state:"queued"|"running"|"committed"|"not-found",result:null|MutationResult}` |
| mutations.recent / mutations.read | `{limit:integer1..100,default20}` | `{receipts:[{requestId,operation,profileId,result,committedAt}],truncated:boolean}`, latest first |

ProfileView: Profile fields кроме credentialRef, плюс `credential:{kind:"none"|"password"|"privateKey",configured:boolean}`. No blob/password/key/passphrase/digest. CredentialAction union: `{action:"keep"}` только update; `{action:"remove"}`; `{action:"replace",kind:"password",password}`; `{action:"replace",kind:"privateKey",privateKey,passphrase:null|string}`. Omitted credential при create значит remove; port22/tags[] defaults только create. MutationResult `{entityId:null|UUID,entityRevision:null|decimal,storeRevision:decimal,deleted:boolean}`; settings entityId null, delete entityRevision — последняя удалённая revision. Profile IDs/revision/link validation по model.

## Повторы, конкуренция, два окна

Request id — immutable identity mutation. UI создаёт его до отправки и сохраняет в RAM при timeout/reconnect; новый id означает новое явное действие. Same id/digest возвращает original result; другой input даёт IDEMPOTENCY_CONFLICT. Inflight duplicate присоединяется к одной queued/running операции. CAS mismatch даёт REVISION_CONFLICT/reload, без last-write-wins. Existing profileId с другим requestId даёт ALREADY_EXISTS; delete missing с другим id — NOT_FOUND.

При потерянном reply UI показывает неподтверждённое сохранение, запрашивает mutations.get тем же id: committed→reread entity/list/settings; queued/running→ждать, не новый id; not-found в любом готовом поколении (включая прежний живой owner)→разрешён retry **того же** immutable id/input. Это не разрешает новый requestId или изменение формы как повтор прежней операции. Если UI crash потерял id, сначала list/recent, никакого автоматического восстановления формы как save. Новое действие после проверки состояния пользователь начинает явно. Deliberately разные requests не объявляются одним intent.

`not-found` означает: в точке status read нет committed receipt и зарегистрированного inflight запроса. Это не утверждение, что старый frame не придёт позже. Обработка полного authenticated mutation frame выполняет pure validation/canonical digest и атомарно регистрирует id в inflight до первого async/native ожидания/queue dispatch. Receipt/inflight lookup и status read сериализованы одним coordinator; поздний original frame и повтор объединяются тем же id/digest. Queued операция без оставшихся requester sessions может быть отменена до начала: она не имеет эффекта/receipt, её inflight entry удаляется, status возвращает not-found и позволяет тот же retry. При живом duplicate requester queued операция сохраняется. Running entry не удаляется из-за disconnect и существует до commit либо завершённого no-effect failure; commit+receipt видны вместе. Если исход commit неизвестен из-за storage error, не возвращать not-found: служба storage-blocked, query отклонён до integrity/reopen. Лишь в ready отсутствие receipt/inflight позволяет этот retry.

Для status query envelope id — новый UUID этого read, params.requestId — исходный mutation id. Не переиспользовать mutation id как идентификатор status frame: поздний mutation reply и status reply имеют разные корреляции. Read IDs не persist и не занимают mutation receipt quota.

Read — атомарный snapshot. UI сравнивает storeRevision и не применяет старый поверх нового. Poll list/settings каждые2s при открытом ready окне, после mutation/конфликта — сразу. Ответ не затирает form draft; конфликт требует явного reload/cancel. Full event stream не входит001.1.

## Errors

Allowlist: UNSUPPORTED, UNAUTHORIZED, FORBIDDEN, INCOMPATIBLE, NOT_READY, STORAGE_BLOCKED, VALIDATION, NOT_FOUND, ALREADY_EXISTS, REVISION_CONFLICT, IDEMPOTENCY_CONFLICT, RESOURCE_LIMIT, TIMEOUT, SERVICE_UNAVAILABLE, INTERNAL. Retry `none|retry-same-request|reload|reconnect|manual-recovery`. Validation дополнительно `{field:allowlistedName}`, без value. Unknown method даёт UNSUPPORTED с boundary local/retry none, без разбора приватных params и эффектов; router regression проверяет этот ответ после authentication. UI локализует code, не exception text/input/path/SID/secret/stack. DPAPI/decode/native buffers не возвращаются.

Diagnostics: только timestamp, random requestId/generation, code, stage, duration. Нет имён/адресов/user/tags/credentialrefs/payload. Export method отсутствует. Readiness states в runtime contract; reason safe code, а не plaintext native exception.

## Compatibility

001.1 UI/locald требуют одинаковый dev buildId/hash manifest и API1.0. Несовпадение→incompatible, данные/процессы не заменяются. Future minor policy/migrations оформляются следующим Plan; неизвестная backward compatibility не обещается. Нет unsafe-pipe fallback/kill/reset для исправления версии.

## Extension021 — 2026-10-21

В bundle021 API1.1 добавляет verified-image role owner/mcp, mcp.open/invoke/close и owner-only grants/delegations/approvals. Идентичность роли не выбирается клиентским requestedCapabilities. Старые методы/основная framing semantics сохраняются; API1.0 не используется как fallback. См. [нормативное расширение](../../021-mcp-control/contracts/mcp.md). Это описание будущего upgrade, не утверждение уже изменённого runtime.
