# Independent acceptance clients

wire_client.py uses Python stdlib JSON-RPC and process IO. sdk_client.py uses
the official MCP Python SDK2.0.0 with its independent negotiation, transport and
schema implementation. Neither imports the ServerDeck server/protocol package.
`launch.py wire|sdk` is the fixed loader for Python `-I`: it adds only this
actor directory to imports, then runs the selected client. The private UI-side
controller is `integration_test/support/mcp_actor.dart`; it validates actual
initialization, serial response IDs and bounded messages, scans decoded results
and stderr for secret markers, and requires EOF/zero exit for a clean close.
Its forced actor-kill path is a failed case, never proof of subtree cleanup.
The hash lock is specifically Windows amd64/Python3.12 test tooling, not a
runtime dependency of mcp.exe. Prepare it in a private test venv with
--require-hashes; do not install these dependencies into the application.

The parent fixture supplies one JSON configuration line on stdin: absolute
command, args and optional secret markers. Command must be the actual mcp.exe
inside an owned .local/mcp-acceptance-<32hex>/application bundle, with matching
fixture.json identity and LOCALAPPDATA pointing to its separate profile.
Saved workspaces, other commands and reparse paths are refused.

After actual initialization, the actor emits ready/client/protocolVersion. Each
following control line has id, method and params; supported methods are
tools/list, tools/call and ping. Replies travel only over the private parent
pipe. Marker scanning precedes forwarding; raw diagnostics are drained/scanned
with bounded memory and never echoed or saved as public proof. Parent EOF closes
the actor's MCP process; no job-cancel or effect retry is synthesized.

The production MCP bridge connects an existing locald or tries a safe detached
cold launch. A host Job Object may forbid breakaway: in that case start the
normal UI/locald independently before connecting the SDK host. The bridge
refuses an unsafe inherited daemon instead of allowing SDK shutdown to kill a
service borrowed by another client.

These actors have not yet been executed against the current native bundle.
`tools/run-mcp-scenario.ps1` and `integration_test/mcp_test.dart` now connect
them to an actual owner UI and owned Docker executor. This source scenario
includes author-only empty workspace, two grants/clients, real SSH pin and
executor confirmation, scoped reads/logs, shared revisions, immutable plan,
owner approval, real job/events, admission replay, exact revision delegation,
desired-state comparison, SDK-close isolation and revocation. Its successful
core proof remains fullAcceptance=false; it cannot close the separate recipe,
crash/recovery, migration or native qualification gates.
They are components of T189, not a substitute for its complete owner/Docker/
recipe/failure/recovery acceptance harness or passing evidence.
