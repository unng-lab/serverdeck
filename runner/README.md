# Runner foundation (not an enabled package executor)

Ansible Core 2.21.4 + Runner 2.4.3 on Python 3.12.12 Linux. Base image digest
and Python transitive hashes pinned. Windows launches Linux Docker; stock native
Windows controller is not supported. No remote daemon or Docker socket is exposed.

```powershell
python -m unittest discover -s runner/tests -v
docker build -t serverdeck-runner:dev runner
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=64m serverdeck-runner:dev
```

The image performs a localhost assert only, never installs anything. It deliberately
has no SSH mount or target inventory. SSH client and package recipes are future
gated dependencies. Do not use this image as an accepted installation executor.

jobs.py implements SQLite intent/event transactions, input hash, idempotency key,
host writer lock, bounded event resume, cancellation and unknown reconciliation.
Its public launch API always denies execution. Recovery tests inject historical
in-flight fixture state; they do not start a container, SSH session or install.
No raw Ansible logs or credential fields enter its public event schema.

Still required for T010/T011: native desktop bridge, secure owner-only file ACLs,
remote privilege helper/lock, exact recipe content digests, pinned OpenSSH packages,
credential handoff, detached container supervision, bounded artifacts/redaction,
real read-only postcondition probes and disposable systemd VM failure tests.
The job journal alone is not evidence of distributed recovery or limited root.
