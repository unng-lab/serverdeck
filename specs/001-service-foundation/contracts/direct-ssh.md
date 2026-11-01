# Прямое SSH-выполнение — действующий контракт 2026-11-01

[Требования](../spec.md) · [План](../plan.md) · [Задачи](../tasks.md) ·
[Установка](../../006-software-installation/spec.md) · [MCP](../../021-mcp-control/spec.md)

## 1. Приоритет, компоненты и границы

Контракт заменяет executor/Ansible/enrollment решения существующих 001/006/021.
Embedded engine в `packages/serverdeck_engine/lib/remote/` владеет типизированным
SSH-адаптером, compiler/preflight и наблюдением. `automation/` сохраняет владельца
планов, согласий, делегаций, заданий и событий. UI и MCP обращаются к нему через
существующие авторизованные gateways. Ни UI, ни MCP не получают командную строку,
SSH handle, credentials, путь исполняемого файла или SQL как расширяемый ввод.

На сервере нет устанавливаемых ServerDeck программ, systemd daemon, supervisor,
bridge, socket/API, venv, Ansible, Python-пакетов или enrollment. Приложение
передаёт только скомпилированные одноразовые `/bin/sh` команды, запускает
штатные transient units и сохраняет ограниченные данные восстановления.
Загрузка прежнего executor в память/временный каталог не считается переходом.
Рецепты находятся в verified app bundle, не в изменяемом remote registry.

## 2. Среда, SSH, полномочия

Чтение использует прежние SSH pin/credentials/revisions, pool2 и shared budgets.
Первая цель изменений: Ubuntu24.04 amd64, systemd с system manager/cgroup,
OpenSSH exec, `/bin/sh`, coreutils (base64, sha256sum, stat, sync, timeout),
util-linux flock, systemctl/systemd-run. APT/dpkg/apt-cache/gpgv нужны установке;
psql/runuser либо clickhouse-client — соответствующим SQL postchecks.
Отсутствующая утилита/возможность блокирует только зависимую операцию.
Проверка версии ОС/утилит выполняется read-only, без скачивания/установки.

Системные команды выполняются root либо `sudo -n -- /bin/sh -s` без TTY.
Приложение не запрашивает отдельный sudo-пароль, не использует SSH-пароль как
sudo-пароль, не меняет sudoers. Проверка прав — ограниченная read-only команда;
отказ означает FORBIDDEN, отсутствие prerequisite — PREREQUISITE_UNAVAILABLE.
При revoke/expiry/trust/target change новые dispatch запрещены синхронно.
Согласие/делегация проверяются локально перед каждым разрешением шага; root на
сервере не является разрешением приложения. Durable authorized dispatch под
native authority gate — единственная граница авторизации текущего шага. Отзыв,
истечение authority либо смена trust/target после неё запрещают новые dispatch,
но не отзывают уже переданный ограниченный permit текущего шага. Worker может
начать этот единственный шаг до permit expiry; начатый шаг может закончиться.
UI явно различает «разрешён/отправлен» и фактический «начат»; отсутствие start ACK
не означает, что отзыв успел предотвратить текущий шаг.

### Trust revocation during a direct attempt (T443)

An unresolved direct format2 job must not prevent owner SSH trust revocation.
The existing foundation identity guard permits only this narrow exception: an
actual existing `servers.trust.revoke` or `servers.trust.confirm` mutation for
the same profile, with unchanged endpoint/address/port/user/connectionRevision,
credentialRef/credentialRevision and credential bytes. Ignore only ordinary
profile display fields/revision/updatedAt and trustRevision when comparing this
exception. Existing trust row must remain present with identical workspace,
profile, connectionRevision, SSH key and createdAt. Only its existing bounded
revision/status/updatedAt and profile trustRevision change under the existing
validated owner mutation/receipt transaction. Revoke writes revoked; confirm
writes trusted and still requires the current owner-issued, live exact-key probe
challenge. Same-key repeated revoke/confirm follows the existing mutation/replay
rules. A new key, missing row, credential/endpoint edit, foreign operation/receipt
or inconsistent tuple remains HOST_BUSY; other validation errors retain their
existing code. An unresolved format1 job retains the historical identity guard
and workspace write block; it gains no direct recovery authority.

Successful trust mutation retires old SSH attachments/pending controls and
invalidates cached proof through the existing target-change lifecycle. It
neither kills a committed remote worker nor clears occupancy/history, grants,
selected consent, dispatch or attempt IDs. After explicit same-key confirmation,
only a new explicit connection and currently authorized cancel/reconcile may
recover the original same-host attempt. Inspect must still match retained hostId
and exact receipts. No automatic resume/reconnect or managed write is authorized;
a prior plan remains stale for a new effect because its target/trust revisions
changed. Arbitrary key rotation or retargeting during occupancy is outside this
exception. Schemas, wire methods, dependencies and deadlines remain unchanged.

Acceptance: revoke with an unknown/admitted direct job succeeds and prevents a
pending control from dispatching; revoked trust denies connection; fresh owner
probe/same-key confirmation plus explicit connection/reconcile recovers the same
attempt without another effect. Wrong key, endpoint/credential change, foreign
receipt and retained format1 refuse without modifying history. Replayed mutation
IDs are byte/idempotent, with no implicit authority restoration. FR-SSH-004/006/
007/008/009/011, AC-SSH-03/07/08/10/11.

## 3. Типизированные команды и транспорт

Внутренний command catalog закрыт: probe, read observation, list exact recipes,
preflight reads, reserve attempt, stage/launch one effect, read receipt/status,
record stop, reconcile reads, publish proven terminal/release.
Команды строятся только compiler-ом из проверенных AST/resource/recipe descriptors.
Имена units/пути служебных записей выводятся из engine-generated UUIDv4 и step ID;
caller не выбирает пути, shell, аргументы системной команды или unit namespace.
Публичные MCP tools/input schemas/scopes сохраняются.

AST format1 и его поддержанные `service`, `config_file`, `install_recipe` шаги
сохраняются как конкретная ограниченная схема, не глобальный каталог приложений.
Сервисные ресурсы первых DB-рецептов: postgresql@16-main.service и
clickhouse-server.service; конфигурационные ресурсы: /etc/motd,
/etc/postgresql/16/main/conf.d/serverdeck.conf и
/etc/clickhouse-server/config.d/serverdeck.xml. Renderer задаёт exact bytes;
configuration body кодируется данными через stdin/base64 и не становится shell.
Нет eval, caller YAML/playbook/plugins, shell snippets или произвольных SQL.

Для direct capsule2 source `config_file` ресурса БД компилируется в один
логический compound effect `database_configuration`, включающий запись,
проверку syntax, restart и postchecks. Все эти действия явно показываются
в immutable плане и покрываются одним permit. Самостоятельного следующего
restart effect и отложенного settings check для format2 нет. Это тот же
поддержанный source AST, не произвольная последовательность shell-команд.
Compound install recipe аналогично является одним логическим effect.

Один SSH channel обслуживает одну конечную команду, stdin закрывается после
полной передачи. Stdout содержит только bounded машиночитаемую проекцию; stderr
дренируется без публикации. Чтение/metadata имеют deadline30s, privileged
control/probe10s, launch ACK10s; polling1s только при текущем интересе, без
автоматического reconnect. Физическая работа/cleanup учитываются до settlement.
Не более4channels/transport; shared pool2, native mutation queue32 сохраняются.
Stdout8MiB максимум, observation128KiB, command/input256KiB, events4KiB.
Превышение, malformed/partial output или потерянный exit — явный отказ/unknown,
не успешная пустота. Секреты не входят в scripts/argv/receipt/event/diagnostics.

## 4. Идентичность и план

SSH host key остаётся единственным пользовательским подтверждением удалённого
доверия. Физическая identity получается из read-only /etc/machine-id и boot ID;
machine-id не публикуется. `hostId` — детерминированный UUIDv4 из HMAC-SHA256
(key: UTF8 `ServerDeck/direct-ssh/host/v1`, message: canonical machine-id без LF)
с выставленными version/variant битами; bootIdHash — SHA256 boot ID.
Ошибочные/пустые/небезопасные источники блокируют изменения. Хостовые lock/owner
общие для всех SSH users/workspace/aliases и не зависят от профиля или host key.
Клонированный machine-id не даёт доступа к другой цели: SSH trust/target также
проверяются; одинаковый ID консервативно блокирует второй локальный writer.

Новый preflight capsule имеет `format:2`; format1 сохраняется только как история.
Существующие поля target/profile/input/baseObservations/recipes/package digests
сохраняют смысл. `runtimeVersion` теперь `direct-ssh/1`, `runtimeLockDigest` —
SHA256 canonical fixed prerequisite descriptor, `compilerDigest` — SHA256
canonical direct compiler/renderer contract revision1, `registryDigest` — SHA256
canonical fixed resource/recipe registry revision1. Это identity локальной
реализации, не remote attestation. Их значения задаёт trusted composition,
не JSON или ответ цели. Host observations получаются из фактических SSH reads.

Plan immutable5min, observations15s; target/access/trust/grant/authority и
фактические исходные значения повторно проверяются непосредственно перед
host reservation/эффектом. Расхождение — PLAN_STALE/TRUST_CHANGED, без изменения
плана или сохранённых исходных наблюдений. Source profile revision сохраняется.
После restart старый неисполненный план не возобновляется автоматически;
отсутствующий ephemeral preflight cache требует нового плана.

## 5. Установка и конфигурация

006 устанавливает приложения через поддержанные способы и рецепты.
[Область приложений](../../006-software-installation/contracts/application-scope.md)
имеет приоритет над прежним ограничением двумя программами. Дальнейшие APT/DB
правила относятся к первым конкретным рецептам PostgreSQL16/ClickHouse.
Другой поддержанный способ использует собственную схему и postchecks;
эта поправка не добавляет новый способ исполнения. APT-каталог предлагает
конкретные версии из уже настроенных APT sources, не `latest`. Отсутствующий
репозиторий/ключ/актуальный signed index даёт недоступность с инструкцией
администратору; read/plan не добавляют ключи/sources, не запускают apt update.
Фиксируются dependency closure1..256 пакетов, exact name/arch/version/SHA256,
signed index digests и signing fingerprints. Доверие подтверждают штатные
APT/gpgv с existing keyrings; hash одного произвольного файла не доказывает trust.
Внимание к pinning/held packages/смешанным источникам/удалению или обновлению
соседних пакетов обязательно; такая транзакция блокируется, а не расширяет план.

Исходные paths/config/data/product packages должны отсутствовать для fresh
install. Существующая установка — иной сценарий007, не скрытый repair/adoption.
Разрешён только точный подтверждённый transaction set. APT запускается с
noninteractive/no-remove/no-upgrade запретами, проверкой подписей и штатными
dpkg locks; нельзя считать отдельный flock эквивалентом package-manager lock.
Установка не убивает apt/dpkg и не выполняет автоматический rollback.
Старт БД контролируется рецептом, без сторонних hooks/plugins из профиля.

Для подавления package maintainer autostart recipe использует стандартный
policy-rc.d deny101 guard, а не установленный ServerDeck executable. Точный путь
`/usr/sbin/policy-rc.d` и временный эффект guard входят в подтверждаемый план.
Absent path либо exact root-owned0755 bytes `#!/bin/sh\nexit 101\n` допустимы;
другой existing policy/symlink/hardlink блокирует recipe без перезаписи.
Одноразовый native APT pre-install hook после проверки exact transaction под
APT frontend lock exclusive-создаёт отсутствующий guard и записывает его
attempt ownership; reused guard помечается как external и не удаляется.
Fixed DPkg post-invoke hook, пока действует та же frontend lock, удаляет только
созданный этой попыткой exact неизменённый guard. Hooks находятся в private
attempt input, не устанавливаются в систему и не выбираются caller-ом.
Поддержан только qualified package-script вариант, соблюдающий этот guard;
неизвестный maintainer autostart path делает candidate недоступным.
После APT/guard cleanup recipe проверяет, что БД не запущена, пишет initial
loopback/auth/settings, валидирует их и лишь затем запускает службу.
Crash/сбой cleanup/изменённый guard не разрешают его удалить вслепую: unknown,
сохранение owner и safe instruction оператору проверить оставшийся guard.
Read-only reconcile не удаляет policy, не repair-ит dpkg и не запускает БД.

Initial settings входят в recipe digest: PostgreSQL max_connections100,
shared_buffers128MiB; ClickHouse max_connections4096,
max_server_memory_usage1024MiB. Прежние typed bounds сохраняются; preflight
проверяет память и возможность применить настройки. Недостаточные ресурсы
блокируют план. Loopback-only bind/auth, package/version/service/SQL1/effective
settings и ownership служебных файлов проверяются до успеха. Неограниченный
доступ к БД и секреты пользователя рецептом не создаются.

Для existing managed config перед записью проверяются отсутствие symlink,
root custody, исходный fingerprint и parent/include structure. Новый файл
создаётся atomically через root-owned sibling temp с mode0644 (motd/ClickHouse)
либо0640 root:postgres (PostgreSQL), sync и atomic rename. Пользовательские
файлы вне declared resource не меняются. DB configuration выполняется одним
compound effect под одним permit: запись → native syntax check → restart →
effective/settings, health и остальные postchecks, как определено ниже в DB
activation. Отдельного следующего restart effect или нового permit между
записью и activation нет.

NetBird package family `netbird`/`netbird-*`, служба, конфигурация и state
сохраняются. До/после эффекта сравниваются private fingerprints установленного
package set и root-owned NetBird config/unit/state в прежних bounded roots.
Raw values/keys/environment не возвращаются UI/MCP. Неподтверждённая сохранность
или меняющийся baseline блокируют успех; функции отключения NetBird нет.

### Durable resource qualification

Fixed app registry описывает допустимые ресурсы и алгоритмы, но сам по себе
не доказывает владение конкретной установленной БД. Источник qualified ownership —
root-owned data `resources/<resourceId>` и связанный успешный direct step record
той же machine identity. Для PostgreSQL/ClickHouse пара service/settings публикуется
только после всех package/version/SQL/effective/loopback/ownership postchecks
первой direct fresh installation. System.motd — встроенный отдельный non-DB
ресурс: его текущая read-only observation/root custody является baseline;
он не даёт права управлять БД.

Resource record связывает hostId/resourceId, product/version/recipeDigest,
registryDigest/compilerDigest, origin install attemptId/stepId/stepDigest,
last confirmed configuration attemptId/stepId, unitParentDigest и managedFileDigest.
UnitParentDigest охватывает canonical systemd fragment/drop-ins/exec/environment,
root file attributes, parent/include configuration, auth configuration и
дополнительные sibling config files; managed file исключён из parent digest и
проверяется своим digest. Применяются bounded parent/probe правила прежних
qualified recipes, без доверия к произвольному existing root-owned файлу.
Raw private parents/auth/env не публикуются; только fingerprints и allowed values.

Перед config/service планом и каждым эффектом читаются resource records,
исходный successful install step и последняя confirmed config step, проверяются
их exact tuple/digests/host, текущие package versions, unit/parent structure,
managed bytes и state-aware probes, определённые ниже. Missing/orphan/foreign/corrupt record,
другая версия, compiler/registry или внешний baseline change дают
QUALIFICATION_REQUIRED/PLAN_STALE без изменения записей. Reboot сохраняет
provenance, но требует новых фактических process/boot observations и SQL только
для фактически active службы.

Для active БД обязательны actual unit/process/cgroup/socket ownership и native
SQL/effective-settings prechecks. Для подтверждённой inactive службы достаточны
сохранившиеся install/config provenance, exact packages/unit/parent/managed bytes,
systemctl ActiveState=inactive/MainPID=0/ControlPID=0, пустой owned cgroup и
отсутствие живого product процесса/постороннего listener на принадлежащих БД
ports. Последняя проверка использует fixed bounded /proc/ss probes; отсутствие
доступа или необходимой утилиты — отказ, не доказательство остановки.
Здесь live SQL не выполняется и его ожидаемая недоступность не объявляется error.
Read-only process enumeration ограничена4096pids; превышение/неполнота блокируют
изменение. `ss` — prerequisite service/process proof обеих БД.

Из inactive разрешены service started/restarted с обязательными version/service/
SQL/effective-settings postchecks после запуска; stopped подтверждает inactive
без запуска и без SQL. Compound database_configuration требует active baseline;
из inactive его план blocked/PREFLIGHT_FAILED с действием «сначала запустите
службу отдельным согласованным планом». Никакого implicit start из просмотра нет.
Failed, activating/deactivating/reloading, отсутствующий unit, неизвестные PID/
cgroup/ports или изменённый offline baseline не считаются inactive и блокируют
новый effect с явной причиной. Такое исключение не выполняет automatic repair.
После отдельного successful stop, app restart и нового start plan путь остаётся
доступен с тем же ownership, без нового adoption. Правило AST о единственном
упоминании ресурса сохраняется: [stop,start] одного ресурса в одном профиле
остаётся VALIDATION; поддержанный цикл здесь — последовательные jobs/plans.

Для атомарной видимости writer под host lock сначала sync-сохраняет обе
resource records со ссылкой на новый step result, затем публикует final succeeded
step record последним. Только exact referenced succeeded record делает новую
provenance действительной. Crash между этими записями оставляет непригодные
references/unknown, не qualified installation. Успешная config step аналогично
обновляет managedFileDigest/last-config reference перед final result; service-only
step проверяет ownership, но не переписывает parent baseline. Подмена baseline
не исправляется переподписыванием record. Исторические references не удаляются.

После app restart записи загружаются через read-only SSH и валидируются заново;
локальное DesiredState без host proof не заменяет их. Existing/historical
executor installations не получают automatic direct ownership. Наблюдение и
history доступны, изменения блокируются до отдельного explicit adoption007;
реализация007 не добавляется в эту поправку и не нужна новой fresh installation.

### DB configuration activation: один логический эффект

Exact effect shape для capsule2: `{id,sourceStepId,kind:"database_configuration",
resourceId,values,renderedDigest,serviceResourceId,baselineServiceFingerprint}`.
ResourceId — postgresql.settings/clickhouse.settings, serviceResourceId —
соответствующий fixed service. Check shapes сохраняют closed standard fields:
file_digest, settings на settings resource; service_state(active),
service_restarted(baselineFingerprint), sql(expected1) на service resource,
все с effectId данного compound effect. Максимум32effects/32checks сохраняется.
Source motd config_file остаётся одним file effect без restart.
Historical capsule1 сохраняет прежнюю двухэффектную модель без исполнения.

Worker до start проверяет прежнюю confirmed provenance и actual baseline.
Затем под одним уже выданным permit выполняет atomic file replace, native syntax
check, restart и все5checks. Результат/provenance публикуется только после них;
между write и activation нет нового authorization/permit или следующего worker.
Cancel/revoke после dispatch относится к уже разрешённому compound effect:
он может завершить activation, но следующий source step не разрешается.
Никакой скрытый restart не добавляется read-only reconcile.

Crash между write и restart либо потерянный результат дают unknown с сохранённым
owner. Reconcile читает тот же compound receipt и все фактические postchecks:
все подтверждены и worker stopped → succeeded; proven stopped с failed syntax/
activation/effective check → failed с частичными effects; недостающий proof →
unknown. Ни файл, ни restart не повторяются. Failed/unknown compound не обновляет
confirmed desired state и не создаёт successful configuration provenance.
Старые подтверждённые references сохраняются как история; если managed bytes
теперь расходятся, последующие config/service writes этой БД блокируются с
объяснением частичного изменения до восстановления подтверждённого baseline
оператором или будущего explicit adoption007. Автоматического repair/rollback нет.
Подтверждённый failed job освобождает host owner, но не снимает qualification
отказ этого ресурса. Проверки обеих БД покрывают normal, interruption между
файлом/activation, failed restart и reconciliation без повторных effects.

## 6. Host-wide ownership и служебные данные

Корень данных `/var/lib/serverdeck/ssh-v1` root:root0700; lock — один постоянный
inode `writer.lock` root:root0600 в этом корне. Все ancestry/file components
проверяются на root custody, отсутствие symlink/hardlink и group/other write;
небезопасный существующий путь отвергается без исправления/замены.
Корень/lock создаются только при первом explicit apply, никогда при read/plan.
`flock -n` сериализует reserve/start/cancel/terminal transitions; lock никогда
не удаляется/пересоздаётся. Конкурентный вызов получает HOST_BUSY без ожидания.

В корне durable `owner` связывает attemptId/jobId/workspaceId/planDigest/hostId/
bootIdHash; он остаётся между шагами и после process loss/reboot. В `attempts/UUID/`
сохраняются exact immutable admission и per-step start/result records. Файлы
root:root0600, atomic temp+rename+sync; quota1250attempts/64MiB total, без
автоматического удаления receipts. При quota отказ до нового admission.
Occupancy не истекает по TTL, не снимается из-за отсутствия процесса/SSH.
Любой orphan/partial/corrupt/foreign owner сохраняется и блокирует новую запись.

Reserve сравнивает exact immutable tuple; повтор того же plan/attempt возвращает
прежний результат, несовпадение конфликтует. Host plan marker запрещает повтор
того же plan с новым attempt даже после terminal release. Локальный job/receipt
тоже фиксируется до reserve; одинаковые публичные request IDs не создают jobs.
Host reservation не выдаёт прав выполнить шаг: каждый шаг отдельно fenced.

## 7. Шаг, launch и отмена

Локальный coordinator сохраняет step dispatch intent до первого SSH write.
Под host lock stage записывает immutable step token/digest, boot и статус
reserved. Скомпилированный script передаётся в приватный root-owned файл
этой попытки; он выполняет только один эффект и postchecks. Это временный
вход задания, не устанавливаемый helper. Unit name выводится из attempt/step;
systemd-run запускает Type=oneshot, RemainAfterExit=yes, Restart=no,
KillMode=control-group с null stdin и без публикации stdout/stderr; worker не
зависит от SSH channel. Завершившийся oneshot сохраняет unit для проверки
receipt, состояния unit и отсутствия дочерних процессов перед terminal release.

Worker первым берёт тот же host lock и проверяет owner/boot/step token,
отсутствие stop/уже committed start; только затем sync-фиксирует start до эффекта.
Сериализация start/stop определяет фактическое начало: поздний worker после stop
не выполняет эффект. Это не новая выдача authority: её граница — local durable
dispatch, описанный в разделе2. systemd-run ACK подтверждает launch, не успех команды.
Потерянный ACK не разрешает новый launch с новым token; читаются старые записи.
Повтор существующего unit/token никогда не повторяет committed effect.

### Bounded one-step permit

Перед каждым dispatch engine получает свежие bootIdHash/uptimeMs через read-only
probe (`/proc/uptime`, fixed awk). Под native publication/authority gate он
повторно проверяет actor, exact selected approval/delegation, captured target,
cancel и baseline и сохраняет intent с UUIDv4 token и immutable permit.
Budget=min(5000ms, remaining grant/delegation authority lifetime). Owner approval
допускает5000ms; истёкший plan не отменяет уже admitted job, но selected authority
проверяется по текущим правилам. Probe round-trip/local elapsed вычитаются из
budget; если budget<=0, новых bytes launch не отправляется.

Permit содержит issuedUptimeMs и expiresUptimeMs на clock целевого boot,
SHA256 canonical target tuple и SHA256 canonical selected authority reference
(kind/id/revision/profile tuple/exact params/grant revision/expiry без secrets).
Worker под lock до committed start проверяет exact permit/owner/token/boot,
issued<=currentUptime<=expires и expires-issued<=5000; wall clock rollback не
продлевает разрешение. Стандартный awk — prerequisite прямого execution.
Worker не обращается к app за новыми правами и не продлевает permit.

Revoke/expiry/trust change до durable dispatch запрещает его; после dispatch
уже выданный permit может начать текущий шаг лишь до этой границы времени.
Cancel доставляет stop fence, если связь доступна; winner start/stop определяется
host lock. При потере SSH отзыв не обещает мгновенно доставить stop. После
permit expiry delayed worker пишет stopped/no effect, не запускает команду.
Следующий эффект/новый token после revoke/restart/lost ACK автоматически не выдаётся.
Expired permit/rejected start может закрыться только через proof исходной попытки;
новый план не обходит unknown. Проверки охватывают изменения authority до dispatch,
после dispatch до expiry, задержку за expiry, loss SSH и late start после stop.

Lock удерживается worker-ом до эффекта/postchecks и durable результата. Локальный
cancel intent принимается немедленно; удалённый stop marker записывается при
доступной границе lock. Занятый lock не даёт права kill или объявления отмены.
Уже committed шаг заканчивается; локальный coordinator не отправляет следующий.
После любого detach/restart следующий шаг требует явного пользовательского
действия и текущих прав. Автоматического продолжения удалённого playbook нет.

Result связывает исходный token, tuple, boot, exact exit и bounded check results.
Успех записывается только после всех declared postchecks. Exit0 без postchecks,
ошибка sync/rename/parse, reboot или пропавшая запись дают unknown.
Step output/config не хранится в receipt. Terminal publication/release разрешены
под lock только после доказанного завершения/отсутствия активного cgroup и
согласованных результатов всех committed шагов. Скрипты можно удалить после
такой terminal записи; orphan/active/unknown входы автоматически не удаляются.

Каждый script задаёт PATH=/usr/sbin:/usr/bin:/sbin:/bin, LC_ALL=C, umask077,
использует абсолютные пути executable и не читает caller shell startup/env.
Проверка lock/owner выполняется повторно после каждого await/нового channel.
Для позднего reserve после отмены stop фиксирует permanent attempt/plan tombstone
даже до появления owner; delayed reserve не может воссоздать отменённую попытку.
Предыдущие успешно выполненные шаги обновляют expected baseline только через
свои проверенные receipts; неизвестное расхождение не объявляется собственным эффектом.

### Host record encoding v1

Данные не исполняются и не source-ятся shell-ом. Каждый record — UTF8 ASCII
lines с LF, первая строка `SDSSH1`, вторая — kind; далее фиксированный порядок
строк без пустых/дополнительных полей. UUIDv4/digests/uint/enum проверяются до
использования. Максимум16KiB/record. Неизвестный формат/лишняя строка — отказ.

- `owner`: workspaceId, jobId, attemptId, planDigest, hostId, bootIdHash.
- `admission`: те же6полей; immutable `attempts/<attemptId>/admission`.
- `plan`: planDigest, attemptId, terminal enum(pending/succeeded/failed/cancelled/unknown);
  permanent `plans/<planDigest>`, не удаляется при освобождении owner.
- `step`: attemptId, planDigest, stepId, stepDigest, token(UUIDv4), bootIdHash,
  issuedUptimeMs, expiresUptimeMs, authorityBindingDigest, targetBindingDigest,
  state(reserved/started/succeeded/failed/stopped/unknown), exitCode(0..255 либо `unknown`),
  checkDigest(SHA256 canonical bounded actual checks либо `unknown`).
- `stop`: attemptId, planDigest; permanent stop fence до любого позднего launch.
- `policy`: attemptId, planDigest, ownership(created/reused), fixedBytesDigest;
  immutable record guard lifecycle, не разрешение на overwrite foreign policy.
- `terminal`: workspaceId, jobId, attemptId, planDigest, hostId, bootIdHash,
  state(succeeded/failed/cancelled), checksDigest.
- `resource` (DB-specific record, не общий реестр приложений): hostId, resourceId,
  product(postgresql16/clickhouse), exact version,
  recipeDigest, registryDigest, compilerDigest, installAttemptId, installStepId,
  installStepDigest, lastConfigAttemptId, lastConfigStepId, unitParentDigest,
  managedFileDigest. ResourceId входит в fixed5-name catalog; DB records не
  содержат system.motd. Recipe version использует existing bounded printable
  version grammar без LF; остальные поля — UUID/identifier/digest.

Names и immutable contents сверяются локально; проверяемый result содержит
вывод только фиксированных probes и record values, без raw command output.
ChecksDigest сверяется с independently recomputed factual checks. Изменяемые
step/plan records заменяются atomically под lock; immutable admission/stop
создаются exclusive. Duplicate с иными bytes конфликтует. Отсутствие step/result
при существующем intent никогда не подтверждает отсутствие effects.

## 8. Состояния и восстановление

Локально queued → running → succeeded/failed/cancelled/unknown;
cancel-requested/reconciling сохраняют прежний смысл и occupancy.
До любой отправки подтверждённая отмена имеет effects:none. После start и
подтверждённого безопасного окончания остановка следующих шагов даёт частичный
результат; фактическая failure не переименовывается в успешную отмену.
После возможной отправки без correlated result — unknown, даже если файла нет.

Reconcile использует текущие owner/grant/trust/target proof, тот же hostId и
attempt tuple, читает immutable admission/start/result, systemd unit/cgroup,
boot и повторяет только factual postchecks. Он никогда не stage/launch/apply.
Смена boot, отсутствие точного admission, повреждение или неустановленная
остановка сохраняют unknown/owner. Нет кнопки «сбросить»/force unlock/повтора.
Доказанный terminal сохраняется локально до разрешения новой записи. Потеря
ACK release восстанавливается чтением terminal marker, а не новым эффектом.

Завершение reconcile может journal-ить доказанный terminal и release только в
служебном namespace `ssh-v1`; это отдельная закрытая metadata-команда с текущими
read scope/object/target/native proof, а не разрешение управляемого эффекта.
Команда повторно под host lock проверяет exact admission/intent/start/result,
все фактические declared postchecks и остановку transient unit/cgroup, затем
публикует terminal/plan marker и удаляет только matching owner. Эти же проверки
обязательны после обычного apply/cancel. Она не stage/launch, не пишет managed
files, не вызывает службы/SQL/APT с изменениями и не меняет resource provenance.
Read-adapters configuration/state/logs не получают эту команду. Owner method
matrix разрешает её только jobs.apply/cancel/reconcile; MCP read разрешает
только metadata finalization своей доступной попытки. Повреждённый/чужой tuple,
неполные checks, active/неустановленный cgroup или reboot оставляют owner и unknown.
Terminal сначала sync-публикуется, затем terminal plan marker; owner удаляется
последним с sync родителя. Для повторного вызова под тем же lock определены
следующие durable префиксы; terminal не переписывается, managed effects не
повторяются:

- Terminal отсутствует, plan pending, owner A: полный proof выше и обычная
  последовательность publication/release.
- Terminal A существует, plan pending, owner A: проверить exact terminal tuple,
  state/checksDigest и снова весь admission/start/result/actual checks/unit+cgroup/
  same-boot proof; заменить только pending plan на соответствующий terminal
  marker, затем удалить только matching owner A.
- Terminal A и соответствующий terminal plan существуют, owner A: повторить
  тот же полный proof, markers не менять; удалить только matching owner A.
- Terminal A и соответствующий terminal plan существуют, owner отсутствует либо
  уже B: release A завершён; проверить root custody, immutable admission и exact
  correlation всех сохранённых A receipts/check data/terminal/plan, вернуть
  исторический terminal A без изменений и без проверки прежних managed values
  против состояния B. Credentials/current object/hostId/trust/native proof всё
  ещё обязательны. Смена boot сама по себе не отменяет этот уже завершённый
  durable terminal; он не разрешает новое исполнение. Owner B не меняется.

Terminal с pending plan при отсутствующем/foreign owner, terminal plan без
terminal record, несовпадающие state/checksDigest/tuple или иные противоречивые
записи — unknown, без repair/release/локального terminal publication. При owner A
с недостающим proof либо сменой boot незавершённый release также остаётся
unknown. Локальное terminal publication/снятие occupancy допускается только
после подтверждённого полного metadata release (первого либо доведённого повтором)
или exact полностью завершённой исторической ветви. Потеря ACK и отсутствие
owner сами по себе такого доказательства не дают.

### Отмена admitted attempt до первого dispatch

Для direct job с durable `cancelRequested=true` и `sshDispatch=null` writer
запрещает поздний permit. При exact admission metadata-команда может доказать
cancelled с checks=[], effects=none, safeCode=CANCELLED. Это отдельный typed
no-dispatch вариант T440 с той же jobs.apply/cancel/reconcile actor/object/native/
current-target matrix. Read-scope reconcile не создаёт stop fence; exact permanent
stop этой attempt/plan должен быть ранее установлен apply-scope cancel.

Под permanent host lock повторяются exact admission/owner/plan/stop и проверяется
отсутствие любого child в `attempts/<attemptId>/steps`. Каталог может отсутствовать;
существующий обязан иметь private root custody. Intent/input/result неизвестного
шага, symlink, повреждение или неполный inventory дают unknown. Для каждого
declared effect retained plan fixed unit имеет имя
`serverdeck-ssh-<attemptId без дефисов>-<stepId>.service`: systemctl show обязан
подтвердить LoadState=not-found, ActiveState=inactive, SubState=dead,
MainPID=ControlPID=0 и пустые ControlGroup/FragmentPath. Другие properties не
запрашиваются; неуспешный probe или иные значения дают unknown. Cgroup
`/sys/fs/cgroup/system.slice/<unit>` обязан отсутствовать без symlink. Same-boot
proof обязателен до полного release. Managed values/packages не проверяются:
permit не выдан и никакой effect не начался. ChecksDigest — canonical digest
пустого массива; outcome не выдумывает declared postchecks.

Затем действуют sync terminal→plan→matching owner unlink и четыре durable
префикса выше. Fully released historical cancelled проверяет admission/stop,
exact terminal/plan и отсутствие step inputs; текущий boot/units/resources не
переоцениваются, owner B сохраняется. Отсутствующий admission, stop без admission,
partial reserve, неожиданный terminal/checksDigest или local dispatch не null
не исправляются: unknown/occupancy без synthetic admission/cleanup/force unlock.
Новой схемы, setting или зависимости нет; metadata deadline10s сохраняется.
Acceptance: reserve→cancel до permit; missing stop/admission, foreign owner,
child/symlink/worker и reboot до release отказывают. Crash после каждого marker,
lost ACK и свежий read-scope reconcile восстанавливают только metadata без launch.

Events монотонны1..int64max, не более10000/job/4KiB; drop count явный,
terminal/unknown/cancel state сохраняются даже после исчерпания progress quota.
Существующие local quotas250active/1000terminal/10000mutation receipts сохраняются.

## 9. Хранение, совместимость, API/UI и поставка

Isar schema3/storageformat3 и существующие collection names не меняются.
Job JSON для direct format2 плана допускает дополнительное закрытое поле
`sshDispatch` (null до первого шага либо объект): `{format:1,stepId,stepDigest,
token,bootIdHash,issuedUptimeMs,expiresUptimeMs,authorityBindingDigest,
targetBindingDigest,authorizedAt,grantRevision,grantExpiresAt,state}`,
где state=authorized/sent/completed/unknown. AuthorizedAt — exact UTC milliseconds,
grantRevision — positive int1..2147483647, grantExpiresAt — exact UTC milliseconds;
оба grant поля null ровно для owner-origin job (job.grantId=null).
Grant snapshot фиксирует только ревизию/срок, не secret или новую authority.
UUID/digest/bounds соответствуют host step permit; поле internal, не caller input.
Оно пишется в том же атомарном local job/event transaction, что фиксирует
authorized dispatch. Неизменные identity поля нельзя менять; новый permit для
следующего step допускается только после доказанного результата предыдущего.
Старая запись без поля сохраняется без добавления null/recanonicalization.
Graph validator разрешает поле только для plan.preflight.format2 и сверяет
effect/plan/target/authority bindings. Неопределённый commit блокирует dispatch.
Metadata/event quota не позволяет пропустить этот durable intent ради эффекта.

AuthorityBindingDigest — SHA256 canonical JSON с точными полями:
`{authorityRef:{kind,id,revision},profileKey:{profileId,revision,bodyDigest},
exactParams,grantId,grantRevision,grantExpiresAt,authorityExpiresAt}`.
AuthorityExpiresAt берётся из retained approval/delegation, остальные данные —
из immutable job/plan и persisted grant snapshot. TargetBindingDigest — SHA256
canonical `{workspaceId,serverId,targetRevision,connectionRevision,accessRevision,
trustRevision}` с targetRevision=plan.serverRevision. StepDigest — SHA256 canonical
точного compiled effect. BootIdHash совпадает с preflight этого плана.

AuthorizedAt не раньше job.createdAt и не позже job.updatedAt. Grant snapshot
expiry и delegation expiry должны быть позже AuthorizedAt; permit duration
не превышает их remaining lifetime и5000ms. Consumed approval expiry участвует
в identity digest, но не обрывает уже admitted job. При чтении истории snapshot
сверяется с issuance receipt указанной grant revision и её временем; если это
ещё текущая issuance, также с её expiry/policy. Равные timestamp соседних grant
revisions не устанавливают их порядок: конкретную issuance задаёт сохранённая
revision. Более новая replacement/revoke не переопределяет прежнюю snapshot.
Issuance receipt должен иметь ровно snapshot.grantRevision и operation
grant.create либо grant.replace; grant.revoke не выдаёт новую issuance.
Точные исторические границы: issuance.createdAt <= authorizedAt; при следующей
grant mutation authorizedAt <= nextMutation.createdAt; для delegation при
revokedAt != null также authorizedAt <= delegation.revokedAt. Нарушение любой
границы блокирует graph. Равенство допустимо во всех трёх сравнениях: timestamp
не различает порядок транзакций внутри одной миллисекунды; snapshot revision
выбирает конкретную issuance, а actual native gate определяет допустимость
новой отправки. «Текущая issuance» для сравнения expiry/policy — последняя
create/replace, даже если за ней следует revoke с новой mutation revision.
Historical graph validation не разрешает новый dispatch: native writer заново
проверяет actual actor, текущие revision/expiry/scope и exact selected authority
под общим gate и атомарно фиксирует snapshot, permit и event до SSH write.
Поля snapshot и все identity поля permit неизменны при смене его state.
Новый token разрешён только следующему declared effect после confirmed completed;
unknown не разрешает переиздание. Missing field или malformed snapshot не
восстанавливаются из текущего grant. Старые jobs без sshDispatch не переписываются.
Парсер capsule принимает исторический format1 без изменения JSON/digests,
а новый direct format2 — с перечисленной local identity. Новый plan/apply/control
принимает только format2 и exact direct identity; format1 не конвертируется.
Существующие профили, credentials, trust, grants, revisions, receipts, desired
state и history сохраняются. Чтение legacy metadata не запускает legacy runtime.

Старые active executor attempts остаются unknown/occupied после recovery;
direct adapter не выдаёт собственные записи за их доказательство. Автоматического
переноса/повтора/очистки нет. UI объясняет, что результат прежней попытки не
подтверждён новым способом исполнения. Поскольку прежний executor UUID нельзя
надёжно сопоставить новому hostId, любое такое незавершённое format1 задание
блокирует новые SSH writes всего workspace с UNKNOWN_OUTCOME и ссылкой на job.
Чтение, история и построение blocked plans остаются доступны. Это исключает
обход через новый профиль/alias; автоматического снятия такой блокировки нет.
Исторический enrollment sidecar сохраняется неизменным при обновлении, не нужен
новому admission, не даёт полномочий и не показывается как prerequisite.

Owner API удаляет executor inspect/confirm/revoke routes; UI убирает карточку
подготовки/подтверждения исполнителя. Capability называется direct SSH execution
и показывает actual prerequisites/permissions. Существующие MCP tool names/scopes
сохраняются; новые capsule format2/document semantics требуют same-build clients.
Никакого сетевого endpoint/protocol на сервере нет. Старые owner routes получают
UNSUPPORTED; новый engine не делает fallback к helper при отказе SSH.

Windows bundle остаётся format4 и содержит app/native libs/данные recipes;
executor-release.json не создаётся/не требуется и не является authority.
Удаляются server packaging/daemon/bridge/Ansible lock и инструменты их сборки
после переноса используемых typed domain checks; пользовательские серверные
файлы и данные установленного приложения этой задачей не удаляются.

## 10. Проверки и готовность

Текущая задача выполняет только static/unit проверки с RAM ports/clocks/stores.
Нужны positive и negative AC-SSH-01–12, отдельно loss before/after dispatch,
late worker после stop, quota/corruption/symlink refusal, alias/workspace race,
native-lock collision, stale observation/revoke, exact versions и оба SQL checks.
Ни один fake response не подаётся как реальная установка или OS proof.
Обязательны root format/analyze/test, все затронутые package unit suites,
lychee specs, Analyze/Converge и независимый AGENTS.md review/fix loop.
Build/install/native/реальные SSH/systemd/APT не запускать в текущем scope;
их неподтверждённость явно сообщать отдельно от завершённости реализации.
