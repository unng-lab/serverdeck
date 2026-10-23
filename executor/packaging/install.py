#!/usr/bin/python3 -I
"""Explicit administrator provisioning; never called by MCP or a read/apply."""

import argparse
import hashlib
import os
import pwd
import re
import stat
import subprocess
import sys
from pathlib import Path
from uuid import uuid4

SOURCE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SOURCE))

from serverdeck_executor import RUNTIME_VERSION
from serverdeck_executor.codec import Rejected, decode, digest, fields, require, uuid
from serverdeck_executor.journal import Journal, _file, _write_all, atomic_document, secure_directory
from serverdeck_executor.probes import PROBE_ENV, regular_file, command, package_snapshot
from serverdeck_executor.apt import APT_CONFIG, validate_catalog
from serverdeck_executor.apt_gate import NO_START

CONFIG = Path("/etc/serverdeck-executor")
CODE = Path("/usr/lib/serverdeck-executor")
SPOOL = Path("/var/lib/serverdeck-executor")
VENV = Path("/opt/serverdeck-executor/venv")


def fixed_command(arguments):
    result = subprocess.run(arguments, env=PROBE_ENV, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    require(result.returncode == 0, "EXECUTOR_UNAVAILABLE")


def install_file(source, target, mode):
    data = source.read_bytes()
    # Fixed packaged paths only; caller arguments never select a destination.
    parent = target.parent
    info = parent.lstat()
    require(info.st_uid == 0 and not info.st_mode & 0o022 and not parent.is_symlink(), "EXECUTOR_UNAVAILABLE")
    secure_directory(parent, mode=stat.S_IMODE(info.st_mode))
    temporary = parent / (target.name + ".serverdeck-pending")
    descriptor = _file(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        _write_all(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary, target)
    descriptor = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uid", required=True, type=int)
    parser.add_argument("--controller-id", required=True)
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--recipe-catalog", type=Path,
                        help="Root-owned pinned catalog to qualify and publish; no update/download/install")
    parser.add_argument("--prepare-apt-no-start", action="store_true",
                        help="Prepare isolated APT configuration and an absent policy-rc.d that denies automatic service starts; never overwrite another policy")
    args = parser.parse_args()
    require(os.geteuid() == 0 and sys.platform == "linux" and sys.version_info[:2] == (3, 12), "FORBIDDEN")
    candidate_catalog = None
    if args.recipe_catalog is not None:
        candidate_catalog = validate_catalog(decode(
            regular_file(args.recipe_catalog, maximum=512 * 1024)[0], 512 * 1024))
    require(0 < args.uid <= 4294967294)
    controller, workspace = uuid(args.controller_id), uuid(args.workspace_id)
    account = pwd.getpwuid(args.uid)
    require(re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}\$?", account.pw_name), "VALIDATION")
    # Administrator prepares this exact venv with --require-hashes first. The
    # installer never downloads dependencies or modifies package-manager state.
    require((VENV / "bin/python").exists() and (VENV / "bin/ansible-playbook").exists(), "EXECUTOR_UNAVAILABLE")
    fixed_command([str(VENV / "bin/python"), "-I", "-c",
                   "import sys, ansible.release; assert sys.version_info[:2] == (3, 12); assert ansible.release.__version__ == '2.21.5'"])
    fixed_command([str(VENV / "bin/python"), "-I", "-m", "pip", "check"])
    for executable in ("/usr/bin/systemctl", "/usr/bin/systemd-run", "/usr/bin/dpkg-query",
                       "/usr/bin/apt-get", "/usr/sbin/visudo", "/usr/bin/sudo"):
        require(Path(executable).is_file(), "EXECUTOR_UNAVAILABLE")
    active = subprocess.run(["/usr/bin/systemctl", "is-active", "--quiet", "serverdeck-executor.service"],
                            env=PROBE_ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    require(active.returncode != 0, "HOST_BUSY")
    secure_directory(CONFIG)
    secure_directory(SPOOL)
    host_path = CONFIG / "host.json"
    if host_path.exists() or host_path.is_symlink():
        data, attributes = regular_file(host_path)
        require(attributes["mode"] == 0o600)
        host = decode(data)
        fields(host, {"format", "hostId"})
        require(host["format"] == 1)
        uuid(host["hostId"])
    else:
        # Never invent a new host namespace over retained receipt evidence.
        require(not any(SPOOL.iterdir()), "RECOVERY_REQUIRED")
        host = {"format": 1, "hostId": str(uuid4())}
        atomic_document(CONFIG, "host.json", host)
    journal = Journal(SPOOL, host["hostId"])
    try:
        require(journal.state["occupied"] is None, "HOST_BUSY")
        enrollment = {"format": 1, "controllers": []}
        if (CONFIG / "enrollment.json").exists():
            enrollment = decode(regular_file(CONFIG / "enrollment.json")[0])
            fields(enrollment, {"format", "controllers"})
            require(enrollment["format"] == 1 and type(enrollment["controllers"]) is list)
        row = {"uid": args.uid, "controllerId": controller, "workspaceId": workspace}
        if row not in enrollment["controllers"]:
            require(len(enrollment["controllers"]) < 128, "RESOURCE_LIMIT")
            enrollment["controllers"].append(row)
        registry = {"format": 1, "environment": "ubuntu24.04-amd64-systemd", "qualifications": {}, "recipes": {}}
        if (CONFIG / "resources.json").exists():
            registry = decode(regular_file(CONFIG / "resources.json")[0])
        secure_directory(CODE, mode=0o755)
        secure_directory(CODE / "serverdeck_executor")
        secure_directory(CODE / "empty")
        names = {"__init__.py", "codec.py", "compiler.py", "journal.py", "probes.py", "runner.py",
                 "jobs.py", "preflight.py", "bridge.py", "supervisor.py", "qualification.py", "apt.py", "apt_gate.py"}
        files = {}
        for name in sorted(names):
            source = SOURCE / "serverdeck_executor" / name
            install_file(source, CODE / "serverdeck_executor" / name, 0o600)
            files[name] = hashlib.sha256(source.read_bytes()).hexdigest()
        install_file(SOURCE / "requirements.lock", CODE / "requirements.lock", 0o600)
        install_file(SOURCE / "packaging/run-supervisor", CODE / "run-supervisor", 0o755)
        secure_directory(Path("/usr/libexec"), mode=0o755)
        install_file(SOURCE / "packaging/serverdeck-executor-bridge",
                     Path("/usr/libexec/serverdeck-executor-bridge"), 0o755)
        install_file(SOURCE / "packaging/serverdeck-apt-transaction-gate",
                     Path("/usr/libexec/serverdeck-apt-transaction-gate"), 0o755)
        install_file(SOURCE / "packaging/apt-probe", CODE / "apt-probe", 0o755)
        install_file(SOURCE / "packaging/recipe-check", CODE / "recipe-check", 0o755)
        if args.prepare_apt_no_start:
            for path, content, mode in ((Path("/usr/sbin/policy-rc.d"), NO_START, 0o755),
                                        (CONFIG / "apt.conf", APT_CONFIG, 0o600)):
                if path.exists() or path.is_symlink():
                    data, attributes = regular_file(path)
                    require(data == content and attributes == {"uid": 0, "gid": 0, "mode": mode}, "QUALIFICATION_REQUIRED")
                else:
                    descriptor = _file(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
                    try:
                        _write_all(descriptor, content)
                        os.fsync(descriptor)
                    finally:
                        os.close(descriptor)
                    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
                    try:
                        os.fsync(directory)
                    finally:
                        os.close(directory)
            secure_directory(CONFIG / "gnupg-empty")
            require(not any((CONFIG / "gnupg-empty").iterdir()), "QUALIFICATION_REQUIRED")
        install_file(SOURCE / "packaging/serverdeck-executor.service",
                     Path("/etc/systemd/system/serverdeck-executor.service"), 0o644)
        if candidate_catalog is not None:
            # Keep the active registry/release unchanged until a separate system
            # interpreter validates the protected candidate against actual APT.
            before_packages = package_snapshot()
            catalog_digest = digest(candidate_catalog)
            atomic_document(CONFIG, "catalog-candidate.json", candidate_catalog)
            qualified = decode(command(["/usr/bin/python3", "-I", str(CODE / "apt-probe"),
                "--qualify-catalog", catalog_digest], maximum=4096, timeout=120), 4096)
            fields(qualified, {"qualifiedCatalogDigest", "packageSnapshotDigest"})
            require(qualified["qualifiedCatalogDigest"] == catalog_digest and
                    qualified["packageSnapshotDigest"] == digest(before_packages) and
                    package_snapshot() == before_packages, "CONFLICT")
            registry["recipes"] = candidate_catalog
        release = {"format": 1, "runtimeVersion": RUNTIME_VERSION,
                   "lockDigest": hashlib.sha256((SOURCE / "requirements.lock").read_bytes()).hexdigest(),
                   "bridgeDigest": hashlib.sha256((SOURCE / "packaging/serverdeck-executor-bridge").read_bytes()).hexdigest(),
                   "registryDigest": digest(registry), "files": files}
        release["runtimeVersion"] = RUNTIME_VERSION + "+" + digest({"baseVersion": RUNTIME_VERSION,
            "lockDigest": release["lockDigest"], "bridgeDigest": release["bridgeDigest"], "files": files})
        atomic_document(CONFIG, "enrollment.json", enrollment)
        atomic_document(CONFIG, "resources.json", registry)
        atomic_document(CONFIG, "release.json", release)
        # Exact command plus empty argument list; no shell, wildcard, arbitrary
        # script path or SETENV permission is delegated to the SSH account.
        rule = f'{account.pw_name} ALL=(root) NOPASSWD: /usr/libexec/serverdeck-executor-bridge ""\n'.encode("ascii")
        candidate = CONFIG / "sudoers-candidate"
        descriptor = _file(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        try:
            _write_all(descriptor, rule)
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        fixed_command(["/usr/sbin/visudo", "-cf", str(candidate)])
        # One fixed per-UID enrollment file preserves other enrolled accounts.
        install_file(candidate, Path("/etc/sudoers.d") / f"serverdeck-executor-{args.uid}", 0o440)
        candidate.unlink()
        fixed_command(["/usr/bin/systemctl", "daemon-reload"])
    finally:
        journal.close()
    # Starting is explicit, so an operator can inspect generated root resources
    # and host identity before the service becomes available to the AI client.
    print("ServerDeck executor provisioned; service not started.")
    print("hostId=" + host["hostId"])


if __name__ == "__main__":
    try:
        main()
    except (Rejected, OSError, KeyError, subprocess.SubprocessError):
        print("Executor provisioning refused; inspect root-owned state and prerequisites.", file=sys.stderr)
        sys.exit(1)
