# ServerDeck MCP

This package is a library loaded by the same `serverdeck.exe` in
`--mcp-stdio --grant-id <UUID>` mode. It has no standalone executable or bin
entry. The main desktop app owns the engine, workspace, tray and local endpoint.
The stdio connector cannot create that Host, open storage, acquire owner rights
or start the desktop app. The app must already be running, including in its tray.
If it is absent, startup emits only bounded safe stderr diagnostics and exits
nonzero; there is no MCP server response or empty-catalog fallback.

Owner-generated configuration has an absolute verified app command and exactly
`["--mcp-stdio", "--grant-id", "<UUID>"]` as args. The old executable/root mode
is rejected. Current endpoint/runtime proof and the protected grant authenticate
MCP-only authority; a shared executable path or argv cannot confer owner rights.
Credentials are distinct from SSH secrets and remain protected by OS custody.

The bridge depends on shared protocol and current Windows connection/custody
primitives. It imports no storage adapter or SSH library and owns no domain
engine. Window close leaves the main app running in its tray; Exit shuts down
its local endpoint. Accepted remote jobs do not become cancelled on disconnect.

See the [current embedded contract](../../specs/021-mcp-control/contracts/embedded-host.md),
[build/client instructions](../../docs/development/mcp.md),
[wire contract](../../specs/021-mcp-control/contracts/mcp.md) and
[implementation tasks](../../specs/001-service-foundation/tasks.md).
Source and unit/static evidence do not establish native or release qualification.
