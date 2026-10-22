# Research decisions — 021

**Date**: 2026-10-21. Research only; no runtime acceptance claimed. Spec Kit Plan delegated read-only technical research to ansible_research; conclusions below incorporated into contracts.

## MCP transport

Decision: standard stdio JSON-RPC MCP 2025-11-25, compatibility subset2025-06-18, tools discovery/calls only. Rationale: independent local clients without public ingress or vendor SDK. Alternative Streamable HTTP would require network authorization, origins and lifecycle beyond first scope. [Transports](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx), [tools](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/server/tools.mdx), [lifecycle](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/lifecycle.mdx).

## Ansible placement

Decision: root-owned target supervisor compiles typed profile to Ansible with local connection. Windows locald alone uses SSH/DPAPI; no WSL required. Rationale: durable physical-host ownership and no private SSH material crossing to another control environment. Alternative WSL is technically possible, adds credential/transport lifecycle and does not remove host lock/receipt requirements. [Installation prerequisites](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html), [local connection](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/local_connection.html).

Decision: ansible-core2.21.5 on Python3.12 venv, modules explicit /usr/bin/python3 with preinstalled python3-apt. Pin exists on [PyPI](https://pypi.org/pypi/ansible-core/2.21.5/json); [support matrix](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html) covers this Python baseline. Packaging must resolve and hash-lock transitive wheels before executor implementation; checks compare actual runtime lock digest, not a loose version range.

## Authoring and execution boundary

Decision: AI authors declarative typed service/config_file/install_recipe AST, not raw Ansible YAML. Resources are root-registered IDs with immutable paths/unit/schema; no arbitrary file or unit. Rationale: even copy+systemd module allowlists permit cron/unit/loader modifications or NetBird dependencies. No claim of arbitrary playbook sandbox. Profile changes never auto-activate old delegation.

Decision: server compiles trusted JSON playbook per typed effect, clean environment, fixed config/plugin paths/cwd. No templating values/Jinja, roles/imports, callbacks, shell, arbitrary command/probe. Rationale: Ansible configuration/plugins and templated strings are executable surfaces. [Configuration](https://docs.ansible.com/projects/ansible/latest/reference_appendices/config.html).

## Planning, revocation, recovery

Decision: read-only preflight probes, never execute untrusted --check as plan. Ansible check mode is a simulation with unsupported/forced execution cases, not a security boundary. [Check mode](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html).

Decision: durable occupied writer tombstone and per-step launch commitment; kernel flock supplements, never replaces it. Reboot, timeout and MCP loss do not clear unknown. Each next effect needs live fresh authorization from locald; loss of authority pauses/fails future steps without replaying current one. Already committed step may finish, exact cancellation boundary documented.

Decision: apt module disallows cache refresh, dependency auto-install, downgrade, autoremove, unauthenticated/held package changes. Validate existing apt lists and python3-apt before calling apt: module may otherwise perform preparation. [Apt behavior](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/apt_module.html). Dependency snapshot/transaction and post-check, not flags alone, enforce unrelated-package and NetBird constraints.

## Host identity and threat boundary

Decision: one root-owned install UUID/state namespace per host OS, bound to checked SSH fingerprint; duplicate profiles share it. No raw machine-id output, no alternate per-profile spool/chroot namespace. [systemd machine-id](https://github.com/systemd/systemd/blob/main/man/machine-id.xml) warns against publishing raw identifier. Root/full same-user compromise remains outside boundary; product never claims to firewall all independent SSH clients.

## Existing implementation evidence

001 is not complete remote functionality: current API handles readiness/profile/settings mutations; SSH/jobs and installation require new implementation. Existing completed task/check evidence preserved; it does not qualify MCP or executor. Backend repo currently has only README and is unnecessary for this local feature.

## Apt lock race correction

The supervisor must not hold an outer native package-manager lock while Ansible apt starts. Apt owns native frontend locking; a packaged root-owned Pre-Install-Pkgs protocol3 transaction gate validates the approved snapshot/actions/archive hashes before dpkg. Unqualified Pre-Invoke/config fragments are excluded. [APT config contract](https://manpages.debian.org/bookworm/apt/apt.conf.5.en.html), [APT2.8 hook sequence](https://raw.githubusercontent.com/Debian/apt/2.8.0/apt-pkg/deb/dpkgpm.cc). Actual Ubuntu build ordering still requires runtime qualification. Signed maintainer scripts/triggers are qualified declared recipe effects; unrelated installed package version/membership changes remain forbidden. External root bypassing native locks is outside guarantee.
