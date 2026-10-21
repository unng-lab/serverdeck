# ServerDeck executor

The executor is under implementation. It is a separately provisioned, root-owned
Ubuntu 24.04 amd64/systemd component. No working privileged entry point or system
service is installed by this directory.

`requirements.lock` pins the Python 3.12 Linux wheel closure for Ansible. Install
with `pip --require-hashes` only into the administrator-prepared executor venv;
runtime installation must never be triggered by an MCP read, plan or apply.
Dependency resolution does not qualify a working executor or installation recipe.

The intended [runtime/protocol](../specs/021-mcp-control/contracts/executor.md)
and [authorable profile grammar](../specs/021-mcp-control/contracts/profiles.md)
are normative. Package installation, root custody, the transaction gate and real
Docker fixture executor/recipe acceptance are still pending in [Tasks](../specs/021-mcp-control/tasks.md).
