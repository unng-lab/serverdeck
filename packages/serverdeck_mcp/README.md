# ServerDeck MCP

Standard stdio MCP transport to the existing locald. This package is under
implementation; its package manifest alone does not provide an executable MCP
server or authorize access to any server.

The bridge uses the shared protocol and Windows IPC/custody primitives. It must
not import locald, Isar or an SSH library. Client grant credentials are distinct
from server SSH credentials and remain in protected OS custody.

See the [design](../../specs/021-mcp-control/plan.md),
[wire contract](../../specs/021-mcp-control/contracts/mcp.md) and
[implementation tasks](../../specs/021-mcp-control/tasks.md).
