# External MCP contract — 2025-11-25, stdio

External client runs same `ServerDeck.exe --mcp-stdio --client <uuid>`; handshake
inside pipe is invisible. MCP initialization follows protocol2025-11-25 only;
unsupported version returns the supported version in initialize result, client may
close; requests carrying incompatible expectations do not invoke tools.

## Lifecycle / allowlist

initialize → server `{protocolVersion:"2025-11-25",serverInfo:{name:"ServerDeck",version:<release>},
capabilities:{tools:{listChanged:false}}}`; client notifications/initialized, then
ping/tools/list/tools/call. Unknown methods: JSON-RPC -32601. Invalid arguments:
-32602 with bounded field path, no echoed values. Request id — non-null string (0..128 code units) или integer безопасного JSON
диапазона ±9007199254740991. Null/fractional/bool IDs не являются MCP requests и
отклоняются до domain dispatch; notification не имеет id и не получает response.
ID запроса не переиспользуется отправителем в пределах одной MCP-сессии, включая
уже завершённые requests. Router хранит seenIds до закрытия сессии; одинаковые
строка "1" и число1 различаются; numeric1 и1.0 обозначают один integer ID. Duplicate request ID: -32600 INVALID_REQUEST,
никакого нового domain эффекта; это не retry через mutationId. Parse/invalid-envelope
error с нечитаемым ID может не содержать id в error response. Корректные ответы
всегда сопоставлены с исходным валидным ID. Сессия ограничена10000 requests; следующий
новый request отклоняется до effects с -32000 SESSION_LIMIT и соединение закрывается,
после чего клиент может открыть новую сессию с новым initialize. MutationId и24h
дедупликация независимы от session/request IDs. Invalid JSON -32700; oversized line helper
closes. No HTTP/OAuth/resources/prompts/sampling/roots/generic-exec/delete/token-admin APIs.
Server never asks client to execute commands or reveal its environment.

Tool registry authoritative: [mcp-tools.json](mcp-tools.json). Router rejects unknown
names and extra keys; inputSchema produced with local $defs bundled in each schema,
never unresolved refs to server filesystem/network. Shared operations/result semantics
in [operations](operations.md). Registry contractVersion2 publishes the original13 tools
with unchanged signatures plus8 [shared console tools](../../007-server-console/contracts/mcp-console.md), total21; no hidden generic dispatcher.

Tool calls return `content:[{type:"text",text:<JSON of structured result>}]`,
`structuredContent:<same JSON>` and `isError:!ok`. Domain error is structured error,
not success text. Full public output schema in JSON registry. No password/privatekey/
passphrase/token/protectedblob in results/errors. Successful mutation returns
`{entityId,revision,replayed}`, not raw storage data; read current entity separately.
Calls require completed initialize and current grant authorization even on cache hit.

`notifications/cancelled` affects only matching active noncommitted call from same
channel; no cross-channel request-id guessing. Operation-level cancelConnection can
manage current attempt by explicit attemptId through authorized tool as spec permits.
Pipe/stdio disconnect isn't implicit cancellation or transaction rollback for the original13 operations.
For console operations, disconnect synchronously invalidates the transport's input lease,
queued input and pending opening; an established console remains alive. Console mutations
use the memory-only sequence ledger defined in007 rather than persisted mutation receipts.

## Async domain journeys

Connect returns quickly with ConnectionView; get polls current state (no background
connection creation). needTrust gives exact current challenge; acceptTrust allows
same first-key verified handshake, replace/retain ends attempt and requires new
explicit connect. needPassphrase gives nonce/attempt; providePassphrase resumes only
that pending parse/auth. No mandatory UI opening for MCP input/trust decision.
Profile deletion remains UI-only even if client invents `profiles.delete` or patch
fields that resemble delete/reset. Boolean confirmed must literally true.

## Compatibility and response limits

Max100profiles/page; complete serialized JSON-RPC replies, including both text content
and structuredContent, are≤1MiB; error text≤256chars. Console history is a bounded
plain-text projection of authorized remote output, which can include server-echoed secrets;
it never returns protected credential-store objects. Console mutations return the explicit
ActionView from007 rather than the original MutationValue shape.
Key bytes base64 input≤decoded1MiB; request frames≤2MiB. Connect state/challenge keys
are bounded; public hostkey blob not required, fingerprint/type enough for UI/MCP.
No dynamic discovery changes during session; unsupported optional MCP capability
not advertised. App release version separate from MCP protocol and internal IPC1.


## Совместимость со стандартом

Tool definitions и tools/list проверяются не только собственными schemas, но и
[официальной JSON Schema MCP2025-11-25](https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/2025-11-25/schema/2025-11-25/schema.json).
Корень inputSchema и outputSchema каждого Tool имеет `type:"object"`; ветви oneOf
дополнительно задают доменный result. Правила IDs —
[официальные Requests](https://modelcontextprotocol.io/specification/2025-11-25/basic#requests).
