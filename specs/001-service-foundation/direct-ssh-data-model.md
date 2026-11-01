# Модель данных прямого SSH

[Контракт](contracts/direct-ssh.md) и [план](plan.md) — действующие источники.

| Сущность | Решение и lifecycle |
| --- | --- |
| Profile/Credential/Trust/Grant/Delegation/Revision | Существующие schema3 записи, IDs и защита сохраняются. Direct admission проверяет текущие revisions/expiry/scope заново. |
| Preflight | Capsule format2 отличает direct backend; прежние поля фиксируют фактический baseline и локальный compiler/registry. Format1 читается неизменённым только как история. |
| Plan/Approval | Существующая schema3 связь, immutable digest5min, one-use exact consent. Old format1 approval не конвертируется. |
| Job/Attempt | Прежний local admission/receipts/events; backend определяется сохранённым preflight format. Step dispatch intent сохраняется до SSH write, unknown держит occupancy. |
| Host owner | Root-only durable data: workspace/job/attempt/plan/host/boot и current step. Один на физический host, между всеми aliases/workspace. |
| Step record | Immutable token/digest + reserved/started/result/stop; прежний token нельзя повторно исполнить. Только verified result/postchecks допускают terminal release. |
| Step permit | Target-boot uptime interval не более5000ms, token, selected-authority digest и target digest. Native-gated durable dispatch — authorization boundary; remote start отдельно проверяет bounded permit. |
| Job.sshDispatch | Optional closed internal field только для format2 plan: latest immutable permit и authorized/sent/completed/unknown. Атомарен с job/event metadata; original rows без поля не переписываются. |
| Dispatch grant snapshot | AuthorizedAt, grantRevision, grantExpiresAt сохраняют issuance отправки без credentials. Digest воспроизводится из job/plan/selected authority и этой snapshot после замены grant; историческая проверка не даёт новых прав. |
| Resource provenance | Root-only resource record связан с exact verified direct install/config step. Parent/unit/package/managed-file proof проверяется заново; отсутствующий или historical executor record не даёт automatic adoption. |
| State-aware qualification | Active требует live SQL/process proof; verified inactive использует offline custody/package/config/empty-cgroup/no-process-listener proof. Новый service start затем обязан пройти live checks; failed/unknown не равны inactive. |
| Database configuration effect | Для capsule2 один compound effect file+syntax+restart+5postchecks, один permit. Provenance/desired публикуются только после его полного успеха; failed/unknown не превращается в промежуточное разрешение restart. |
| Host plan marker | Permanent replay tombstone даже после освобождения owner; quota отказ вместо eviction. |
| Terminal finalization | Отдельная metadata-команда после exact receipts/actual checks/unit+cgroup proof, в том числе при read-scope reconcile. Sync terminal→plan marker→matching owner unlink; managed resources/provenance не меняются. Contract§8/T440/T441 определяет восстановление каждого durable префикса: при owner A повторный полный proof и только оставшиеся journal actions; после полного release historical terminal A читается без сверки с изменёнными resources B, owner B сохраняется. Новых persisted fields нет. |
| No-dispatch cancellation | Durable cancelRequested + sshDispatch=null; exact admission/stop, no step inputs/declared units/cgroups. Cancelled/empty checks/effects:none; same boot until release, historical release preserves B; partial reserve stays unknown. Contract section8/T442. |
| Historical enrollment | Прежний защищённый sidecar сохраняется без изменения байтов; новых mutation routes нет, для direct admission не читается как authority. |

Isar schema3 и storageformat3 не меняются. Новые records используют те же
collections/graph/atomic mutation writer. Добавляется parsing capsule2 с
закрытыми полями, исходная canonical digest normalization не меняется.
History остаётся видимой при отказе нового исполнения; parser не возобновляет
SSH и не вызывает старый helper. Неподдержанные/повреждённые данные блокируют
открытие без reset/fallback/пересчёта исторических digest.

При startup queued без отправки отменяется, отправленные nonterminal jobs
становятся unknown. Любой unresolved format1 job блокирует новые writes
во всём workspace; format2 recovery читает только исходную SSH attempt.
Новые requests не подменяют source grant/selected authority. Events/receipts
и quotas сохраняют прежние правила, terminal результат не удаляет историю.

Trust lifecycle exception T443: unresolved format2 allows existing owner trust
revoke/confirm of the same key only, with unchanged endpoint/credentials and
exact retained trust identity; old connections/control proof retire. Format1 and
other identity changes retain HOST_BUSY. No data/consent/dispatch reset or resume;
fresh current connection and metadata recovery are mandatory (contract section2).
