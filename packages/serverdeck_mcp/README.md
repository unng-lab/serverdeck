# ServerDeck MCP

Standard stdio MCP transport to locald. The production entry is `bin/mcp.dart`,
built as `mcp.exe` by `tools/build-mcp.ps1` and included in the format3 bundle by
`tools/run-serverdeck.ps1`. Owner-generated configuration invokes
`mcp.exe --app-root <verified bundle> --grant-id <UUID>`.

Configured startup verifies the actual MCP executable and bundle, discovers or
starts the matching locald, authenticates its native role, waits for authenticated
schema3 readiness and proves its protected client grant before exposing tools.
There is no configured-failure fallback to an empty catalog. With no arguments,
initialization is available but the tool list is empty and calls are forbidden.
Source implementation is not final runtime qualification; full checks remain
pending for the complete feature.

The bridge uses the shared protocol and Windows IPC/custody primitives. It must
not import locald, Isar or an SSH library. Client grant credentials are distinct
from server SSH credentials and remain in protected OS custody.

See the [design](../../specs/021-mcp-control/plan.md),
[build and client setup](../../docs/development/mcp.md),
[wire contract](../../specs/021-mcp-control/contracts/mcp.md) and
[implementation tasks](../../specs/021-mcp-control/tasks.md).
