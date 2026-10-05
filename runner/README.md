# Runner foundation (not an enabled package executor)

Ansible Core 2.21.4 + Runner 2.4.3 on Python 3.12.12 Linux. Base image digest
and Python transitive hashes pinned. Windows launches Linux Docker; stock native
Windows controller is not supported. No remote daemon or Docker socket is exposed.

```powershell
docker build -t serverdeck-runner:dev runner
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=64m serverdeck-runner:dev
```

The image performs a localhost assert only, never installs anything. It deliberately
has no SSH mount or target inventory. SSH client and package recipes are future
gated dependencies. Do not use this image as an accepted installation executor.

Desktop job coordination belongs to the Dart locald service and its Isar store in
packages/serverdeck_locald/, not this Python container. The old jobs.py prototype
and its tests are replaced by Dart store/API fault tests. The Local API launch
gate still always denies execution. Recovery model tests inject historical state;
they do not install packages. Python remains here only for Ansible's runtime.
Existing prototype SQLite files are neither automatically imported nor deleted.

Still required for T010/T011: actual executor bridge from locald,
remote privilege helper/lock, exact recipe content digests, pinned OpenSSH packages,
credential handoff, detached container supervision, bounded artifacts/redaction,
real read-only postcondition probes and disposable systemd VM failure tests.
The job journal alone is not evidence of distributed recovery or limited root.
