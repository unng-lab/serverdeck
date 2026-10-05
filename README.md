# ServerDeck

Local-first Flutter desktop client for managing your Linux servers over SSH.

Product brief: [specification](specs/001-server-management-client/spec.md),
[technical plan](specs/001-server-management-client/plan.md),
[tasks](specs/001-server-management-client/tasks.md),
[Logs research](docs/logs-research.md).

The first target is Windows desktop: server inventory, installed-software inventory,
systemd logs, basic hardware activity and reproducible installation jobs for
PostgreSQL and ClickHouse. An optional backend synchronizes metadata; ordinary
server access must work without it or a cloud-provider API.

Status: requirements and proposed design only. No application, runner, backend,
host installation or runtime tests have been implemented. Tool versions and
third-party recipe compatibility still need verification. No real server addresses,
credentials or log contents are included. License selection is pending; public
repository visibility does not grant permission to copy third-party code.
