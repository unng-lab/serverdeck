# Proposed technical plan

This design is proposed, not an accepted implementation or runtime proof.

Flutter desktop UI with independent inventory/logs/metrics/jobs repositories.
Windows local SQLite stores non-secret profiles, observations and durable job
journal; OS credential store holds secret references. SSH transport has mandatory
known-host verification and bounded sessions. No dependency on remote sync for
normal local operations. Exact Flutter/Dart/plugins/runner versions to be pinned.

Use Ansible Core + Ansible Runner for installation, not Terraform SSH provisioners.
Ansible apt and systemd_service already manage packages and units and support
check mode. Check mode is a prediction, not proof of the eventual install or a
transactional rollback. Recipes remain versioned application-specific content;
PostgreSQL/ClickHouse upstream compatibility must be investigated separately.

Windows executes a pinned Linux runner container with SSH access and ephemeral
credential mounts. Docker runtime is an explicit installation prerequisite; report
it clearly and permit a later WSL adapter. The desktop starts a local sidecar/runner
and consumes structured Ansible events. No AWX/Semaphore/Terrakube server required.
Local IPC must be authenticated/device-scoped; no listening remote write endpoint.

Job inputs contain host identity, OS, selected version, recipe digest, parameters,
preflight findings and explicit write approval. Durable owner-local exclusive
host lock, idempotency key and child-process reconciliation precede reruns. Closing
the UI does not prove a job stopped. A remote process may survive interruption:
inspect package manager/unit/probe evidence before allowing another writer.

Inventory adapters: dpkg/package metadata, all relevant systemd unit/instance
states; explicit binary detectors for custom tools; optional Docker and Kubernetes
read-only adapters later. Software is not equated with running processes. Unit
and deployment mapping carries evidence/confidence and last observed time.

Logs: first journald JSON, then optional Docker logs. Cursor/boot identity and
bounded stream buffers expose gaps/duplicates; pause display and pause transport
are distinct. Limit visible open streams. Metrics use host/system APIs over SSH;
CPU requires sampled deltas; avoid claiming instantaneous ps lifetime values are
interval utilization. Do not silently cache stale metrics as healthy.

Optional backend synchronizes only authenticated user-scoped non-secret data.
Backend technology is undecided; define contract/conflict semantics first.
Observation uploads/raw logs require explicit user choice; credentials stay local.
Sync is not a distributed job executor. Job writes belong to one executing device.

Testing: Flutter model/widget + Windows UI fixture tests; SSH key/command-injection
negatives, partial inventory/log faults, stale metrics; disposable Ubuntu installs,
check-mode/no-op, existing-data preservation, failed probe, duplicate/restart/cancel
and concurrent writers; offline/sync conflict and secret-exclusion tests.

Official sources:
- https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/apt_module.html
- https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/systemd_service_module.html
- https://docs.ansible.com/projects/runner/en/stable/execution_environments/
- https://docs.ansible.com/projects/runner/en/latest/python_interface/

No exact version, upstream recipe, install, probe or test is claimed verified.
