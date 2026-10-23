# Implementation Plan: MCP и Ansible

**Feature**: 021-mcp-control | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)
**Status**: Design review3 completed with no findings; ready for staged implementation. Implement started; runtime/acceptance not complete.

## Summary

Persisted remote trust requires explicit schema3 and owner-only challenge/confirmation under the [host trust contract](contracts/host-trust.md). Schema2 components remain exact historical/prototype readers; remote startup uses a separate format3/API1.1/schema3 bundle after protected migration and all service gates, with no implicit trust-table fallback.

The [shared format3 control services](contracts/trusted-services.md) compose the existing 25 owner routes and MCP author catalog over identical storage, registry, authority and backend instances. This component owns registry/service shutdown; outer runtime retains native channels, storage, key and mutex ownership. It is a prerequisite to installed startup, not an activation of readiness or unfinished read/executor domains.

The next connection stage follows [shared trusted connections](contracts/connections.md): one pinned transport per current target tuple, session-owned interests shared by owner/MCP, bounded connect handles, custody/native checks and confirmed-target physical invalidation before ACK. T170–T173 extend the same composition; typed observations/logs and UI remain their existing later work. No second pool or automatic reconnect.

The2→3 job guard uses an initial same-schema owned source preflight before stage creation and before freezing recovery hashes. It validates the full15-collection graph/DPAPI without application writes or credential lookup publication, confirms native close, then either refuses HOST_BUSY or starts protected migration. Journal-bound recovery opens only protected copies. Separate fixed-path source/target capture entries share immutable raw-row preservation checks; native housekeeping before hash capture is not covered by later source byte hashes. Details and acceptance are in the host trust contract and T156.

The staged [SSH transport contract](contracts/ssh-transport.md) qualifies the pinned library, exact host-key verification before authentication and bounded physical connection ownership in T144. Persisted trust/native service integration remains T011 and does not reuse schema2 automation rows implicitly.

Operational schema2 retained graph/reference validation and startup composition follow the [loading contract](contracts/loading.md); pure DTO parsing and migration's empty-automation view do not establish service readiness.

Shared owner/MCP authorable catalog implementation follows the [profile catalog contract](contracts/profile-catalog.md), including origin-isolated receipts, native publication lifetime, immutable revisions and bounded cursor/diff/read semantics.

Добавить stdio MCP bridge к существующему Windows locald. UI сохраняет Local API. Locald единственный владелец Isar/DPAPI/SSH/automation/grants/jobs. Ansible исполняется на управляемом Ubuntu хосте внутри заранее установленного root-owned executor с local connection: Windows не копирует SSH-секреты в WSL и не требует control-node runtime. ИИ создаёт типизированные декларативные профили; compiler переводит их в Ansible JSON playbook, не выполняет присланный произвольный YAML/Jinja/plugin.

## Technical Context

- Language: pinned Flutter 3.47.7/Dart 3.13.5 из tools/foundation-sdk.ps1; существующие Isar 3.3.2/cryptography 2.9.0/win32 6.4.0 сохраняются.
- MCP: JSON-RPC 2.0, stdio, protocol 2025-11-25; собственный ограниченный protocol adapter без vendor SDK. Инициализация принимает также 2025-06-18 с тем же поддержанным tools subset, неизвестной версии отвечает выбранной 2025-11-25, клиент решает совместимость.
- SSH: package dartssh2 4.1.0 (pub.dev metadata verified); exact lock фиксируется отдельной dependency qualification задачей до remote implementation; критерий выбора — pinned Dart compatibility, key/password auth, host-key callback до authentication, cancellation, bounded channels, license. Нельзя считать библиотеку работающей по одному pub get. Эта техническая задача не выбирает новую продуктовую семантику.
- Executor: Ubuntu 24.04 amd64/systemd; Python 3.12, ansible-core2.21.5 venv; точный patch и hashes фиксируются runtime lock при сборке и проверяются handshake. System module interpreter /usr/bin/python3 и python3-apt; control CLI — venv. Нет WSL prerequisite на Windows и автоматического скачивания runtime при apply.
- Storage: новая schema2 того же Isar, обычные metadata и DPAPI client credentials; existing schema1 retained. [Staged migration](contracts/migration.md) validates source, migrates protected copy and atomically publishes closed DB plus recoverable manifest; native collection creation is not an in-place application transaction. Preservation/quotas in [data model](data-model.md).
- Testing: Dart test + existing native package suites, root format/analyze/test; Python unittest executor/compiler; disposable systemd Docker fixture on GitHub Ubuntu runners (or owned VM) acceptance обеих БД. Стандартный MCP wire client и второй независимый SDK client, без vendor reliance.
- Scale: 250 server profiles, 8 sessions суммарно, 2 SSH transports суммарно, 32 mutation queue как 001. Дополнительные budgets — contracts. Никакого backend изменения.

## Constitution Check

| Principle | Before research / after design |
| --- | --- |
| I components/local-first | UI→Local API; AI→MCP bridge→same locald; backend не нужен |
| II explicit consent | Owner issues scoped exact-revision delegation or approves immutable plan; author/read not apply; NetBird protected |
| III secrets/trust | Existing DPAPI; no export to bridge/Ansible; host trust owner-only; same-user OS compromise outside threat model |
| IV bounded observations | Shared read budgets, stale/gaps, no raw log persistence |
| V reliable jobs | Durable immutable plan, local and host admission/receipts, per-effect authority and unknown tombstone |
| VI traceability | [Tasks](tasks.md), contracts and acceptance map; completed001 history retained |
| VII verification | Mandatory checks + fresh independent review; Real systemd Docker/VM evidence not replaced by mocks; container restart is not kernel reboot |
| VIII distribution | Compatible UI/locald/MCP bundle; executor separately provisioned/verified by owner; no publication implied |

Delegation is explicit owner consent to declared targets/effects within exact digest and parameter predicates, satisfying Principle II/FR-036; no implicit approval from model text. UI Local API/Isar ownership unchanged. No constitutional amendment required.

## Project Structure

- packages/serverdeck_mcp/{bin/serverdeck_mcp.dart,lib/src/,test/}: protocol bridge, no Isar/SSH/server-credential dependency; only its own scoped MCP client key through shared Windows custody.
- packages/serverdeck_protocol/lib/{mcp/,automation/}: shared strict DTO/validation/digests.
- packages/serverdeck_locald/lib/{mcp/,automation/,remote/}: policy, profile revisions, plans/jobs, SSH adapters; sole writer.
- packages/serverdeck_locald/lib/storage/: schema2 collections/atomic migration/DPAPI links.
- packages/serverdeck_windows/lib/: bridge verified image role, existing pipe identity/OS custody.
- executor/{serverdeck_executor/,tests/,packaging/,requirements.lock}: root-owned Linux bridge/supervisor/compiler, protocol/locks/receipts/Ansible.
- lib/{automation/,access/,servers/}: UI grants/revisions/approval/jobs/state/logs, existing shell integration.
- tools/{build-mcp.ps1,test-mcp.ps1,test-mcp-vm.ps1}: build/validation only owned synthetic fixtures.

## Boundaries and contracts

[Protocol](contracts/mcp.md) fixes public tools/auth/lifecycle/limits. [Profiles](contracts/profiles.md) fixes authoring grammar/expressiveness. [Executor](contracts/executor.md) fixes Linux runtime and jobs. [Model](data-model.md) fixes persistence/validation. [Quickstart](quickstart.md) defines expected verification evidence.

[Durable records](contracts/records.md) fixes job/approval/desired/event/receipt wire shapes, owner/null origin, bounded safe outcomes and structural transitions; these DTO checks do not replace full plan/reference/live-policy or executor outcome validation.

[Immutable plans](contracts/plans.md) fixes Plan/preflight/descriptor/observation schemas and exact typed program coverage. T002 structural validation precedes complete schema2 startup; trusted compiler/factual/catalog qualification and fresh admission remain T019/T023–T028.

Local API becomes1.1 inside same-build bundle; bootstrap/discovery retain validated framing/peer rules and add role from verified executable identity. UI role has owner management operations, bridge role only mcp.open/invoke/close. MCP transport claims cannot select UI role. Bridge never proxies arbitrary Local API method. Session role is immutable and checked in locald before dispatch.

Native invocation parser/router/context, live catalog source and bounded async service ownership follow [invocations](contracts/invocations.md); T090 implements these for subsequent channel/gateway integration without activating an incomplete product bundle.

## Delivery order and traceability

| Slice | Requirements | Implementation | Acceptance |
| --- | --- | --- | --- |
| Shared auth/store/bundle | FR-MCP-001–004,015,016 | T001–T008 | AC1A/1B, migration/bundle cases |
| US1 state/logs | FR-MCP-002,004,005 | T009–T014 | AC1A/B/C, SC001/002/005 |
| US2 authoring | FR-MCP-006,007 | T015–T020 | AC2A/B/C |
| US3 execution | FR-MCP-003,008–014 | T021–T032 | AC3A/B/C/D, SC003/004 |
| Final acceptance | all,016 | T033–T038 | SC001–006 |

Stages remain separate reviewable increments. 021.1 cannot claim full remote acceptance until 001.2 reads are implemented; 021.3 cannot claim install success until006 requirements pass. Existing001.1 manual gates retain their own status and are not silently marked complete by this feature.

## Complexity Tracking

Host executor is necessary for durable cross-controller physical-host ownership and Ansible on Windows without moving SSH credentials. WSL control-node alternative rejected for additional secret transfer surface and failure to replace durable host admission. No generic code-execution sandbox is claimed: authorable grammar only emits trusted builtin actions on administrator-registered resources.

Design correction1: permission identity `(profileId,revision,bodyDigest)` distinct from content identity. Complete tuple persists in delegation/plan/job and each step authority; same-content new revision/profile denied. T037 adds cross-layer negative cases before dependent implementation closure. Fresh review follows checks.

Design correction2: author-only/no-scope client grants use serverIds[] and are valid before any server exists. Target scopes require explicit existing1..250 targets; no inherited read/apply. T038 defines model/service/actual MCP regression before dependent closure.


Operational API1.1 wire integration follows [channel ownership, dispatch and publication](contracts/operational-channel.md), in addition to handshake/invocations; it preserves pending interest until native publication and rejects queued stale authority. T096 implements this component before actual bootstrap/owner/client product activation.

The shared native [ordinary RPC client](contracts/operational-client.md) owns the post-bootstrap reader/writer, correlation, deadlines and terminal cleanup without callbacks or replay. T103 supplies it for owner/MCP adapters; T104 connects the stdio gateway and later executable/discovery work retains its existing activation gates.

The [native MCP gateway](contracts/gateway.md) fixes method mapping, bounded polling/cancellation, heartbeat and fresh authorization after stdout writer wait. It uses the claimed native client and fixed errors; stdio transport never proxies owner methods or acquires server credentials.

Target identity mutations use the workspace MCP session retirement fence defined in [gateway contract](contracts/gateway.md): owner service holds it through actual commit/rollback and cache invalidation, while protected opens remain blocked. T109 implements the shared registry primitive; original target/credential/trust service integration remains required before remote readiness.

The native synchronization helper, its trusted bootstrap identity and actual acquisition/poison/cleanup lifecycle are defined in [publication gate contract](contracts/publication-gate.md). T113 qualifies this component; T110 still wires it to every product authority/target mutator and gateway publication.

The concrete bridge adapter is LocalMcpGateway.connect(actualProtectedSession) in packages/serverdeck_mcp/lib/src/local_gateway.dart. It owns the claimed client, derived publication gate, bounded invocation/cancel/poll/heartbeat lifetimes and exact standard params/error mapping. Its actual native/stdio and controlled-peer acceptance composition is specified in [gateway contract](contracts/gateway.md); all production tool services, installed discovery and automatic mutator gates remain separate readiness obligations.

The registry's native [target-change fence](contracts/target-fence.md) owns its generation keeper and serializes owner mutation leases while synchronously blocking protected MCP opens. It preserves physical cleanup ownership independently of logical RPC/shutdown deadlines; original service integration remains T109/T110.

The concrete [owner grant write adapter](contracts/owner-grants.md) routes native owner create/replace/revoke through that registry's publication gate before StateStore queue admission, with immutable commands and fresh owner proof. Other owner reads/services, schema2 target writes and installed activation remain original open work.

Operational foundation mutation storage uses explicit StateStore.commitOperationalFoundation / WorkspaceRecords.fromOperationalState in the existing storage library, preserving physicalschema2 and complete retained automation with actual readback; see [loading](contracts/loading.md). Legacy commit/coordinator stays schema1-only pending native owner-service composition T109/T110. Foundation/grant writes share the same total32 admission budget before the existing durable queue. Real commit-time native capacity qualification additionally requires the repository-owned pinned Dart binding source under third_party/isar_community with active-transaction abort guards and actual native-reply-port cleanup; see [native transactions](contracts/native-transactions.md), T122 before closing T121 capacity acceptance. ABI, generator3.3.2, native-source qualification and installed startup gates remain unchanged.

Operational owner foundation composition follows [owner foundation services](contracts/owner-foundation.md): explicit schema2 coordinator, immutable commands, envelope-ID preservation, native gate before queue, target fence and common owner adapter composition. Installed startup and remaining services remain separate gates.
