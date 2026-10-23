"""One-use root APT Pre-Install-Pkgs protocol3 transaction gate.

The protocol format and native frontend-lock ordering are defined upstream:
https://manpages.debian.org/bookworm/apt/apt.conf.5.en.html
https://github.com/Debian/apt/blob/2.8.0/apt-pkg/deb/dpkgpm.cc
No package manager lock is taken by this hook. The actual apt ancestor must
already hold it; the supervisor never holds an outer lock across Ansible.
"""

import hashlib
import os
from pathlib import Path
import re
import signal
import socket
import stat
import sys
import time
from urllib.parse import unquote

from .codec import Rejected, decode, digest, fields, read_frame, require, sha, uuid, wire_bytes, write_frame
from .journal import _file, _write_all, secure_directory
from .probes import (boot_id_hash, netbird_preservation_digest, package_snapshot,
                     protected_package, regular_file, system_slice_cgroup)

GATE = "/usr/libexec/serverdeck-apt-transaction-gate"
CONFIG = "/etc/serverdeck-executor/apt.conf"
KEYRING = "/etc/apt/keyrings/serverdeck-executor.gpg"
WORK = Path("/var/lib/serverdeck-executor/work")
NO_START = b"#!/bin/sh\nexit 101\n"
LAUNCHER = b'''#!/usr/bin/python3 -I
import sys
sys.path.insert(0, "/usr/lib/serverdeck-executor")
from serverdeck_executor.apt_gate import main
main()
'''


def hash_file(path, maximum=512 * 1024 * 1024):
    path = Path(path)
    for parent in reversed(path.parents):
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
                "QUALIFICATION_REQUIRED")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(descriptor)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == 0 and before.st_nlink == 1 and
                not before.st_mode & 0o022 and before.st_size <= maximum, "QUALIFICATION_REQUIRED")
        checksum, count = hashlib.sha256(), 0
        while chunk := os.read(descriptor, 1024 * 1024):
            count += len(chunk)
            require(count <= maximum, "RESOURCE_LIMIT")
            checksum.update(chunk)
        after = os.fstat(descriptor)
        require((before.st_ino, before.st_mtime_ns, before.st_size) ==
                (after.st_ino, after.st_mtime_ns, after.st_size), "CONFLICT")
        return {"path": str(path), "sha256": checksum.hexdigest(), "size": count,
                "uid": before.st_uid, "gid": before.st_gid, "mode": stat.S_IMODE(before.st_mode)}
    finally:
        os.close(descriptor)


def parse_protocol(data):
    require(0 < len(data) <= 1024 * 1024 and data.endswith(b"\n"), "VALIDATION")
    try:
        lines = data.decode("ascii").splitlines()
    except UnicodeError:
        raise Rejected("VALIDATION") from None
    require(lines and lines.pop(0) == "VERSION 3", "INCOMPATIBLE")
    separator = next((i for i, line in enumerate(lines) if line == ""), None)
    require(separator is not None, "VALIDATION")
    config = []
    for line in lines[:separator]:
        require("=" in line and len(line) <= 8192, "VALIDATION")
        key, value = line.split("=", 1)
        key, value = unquote(key, errors="strict"), unquote(value, errors="strict")
        require(key and not any(ord(char) < 32 for char in key + value), "VALIDATION")
        config.append((key.casefold(), value))
    actions = []
    for line in lines[separator + 1:]:
        columns = line.split(" ")
        require(len(columns) == 9 and all(columns), "VALIDATION")
        name, old, old_arch, old_multi, operator, version, architecture, multi, action = columns
        require(re.fullmatch(r"[a-z0-9][a-z0-9+.-]{0,127}", name) is not None and
                not protected_package(name) and
                old == old_arch == "-" and old_multi in ("none", "no") and operator == "<" and
                architecture in ("amd64", "all") and multi in ("none", "no", "same", "foreign", "allowed") and
                re.fullmatch(r"[A-Za-z0-9.+:~\-]{1,256}", version) is not None, "CONFLICT")
        require(action == "**CONFIGURE**" or action.startswith("/var/cache/apt/archives/") and
                Path(action).parent == Path("/var/cache/apt/archives") and action.endswith(".deb"), "CONFLICT")
        actions.append({"name": name, "architecture": architecture, "version": version,
                        "multiArch": "none" if multi == "no" else multi, "action": action})
    require(1 <= len(actions) <= 512, "CONFLICT")
    return config, actions


def check_config(config):
    def one(key, expected):
        values = [value for name, value in config if name == key.casefold()]
        require(values == [expected], "CONFLICT")
    one("Dir::Etc::sourcelist", "/etc/serverdeck-executor/sources.list")
    one("Dir::Etc::sourceparts", "-")
    one("Dir::Etc::parts", "-")
    one("Dir::Etc::main", "-")
    one("Dir::Etc::trusted", KEYRING)
    one("Dir::Etc::trustedparts", "-")
    one("Dir::State::lists", "/var/lib/apt/lists")
    one("Dir::Cache::archives", "/var/cache/apt/archives")
    hooks = [(name, value) for name, value in config if name.startswith("dpkg::pre-install-pkgs")]
    require(len(hooks) == 1 and hooks[0][1] == GATE, "CONFLICT")
    for name, value in config:
        require(not any(part in name for part in ("pre-invoke", "post-invoke")), "CONFLICT")
        if name.startswith("apt::get::") and name.split("::")[-1] in (
                "allowunauthenticated", "allow-downgrades", "allow-change-held-packages"):
            require(value.casefold() in ("false", "0"), "CONFLICT")
        if name.startswith("dpkg::options"):
            require(value in ("--force-confdef", "--force-confold"), "CONFLICT")
        if name == "dpkg::chroot-directory":
            require(value in ("", "/"), "CONFLICT")
    one("DPkg::Tools::Options::" + GATE + "::Version", "3")
    one("DPkg::Tools::Options::" + GATE + "::InfoFD", "0")


def _current_work():
    data = Path("/proc/self/cgroup").read_text(encoding="ascii")
    match = re.fullmatch(re.escape("0::" + system_slice_cgroup() + "/") +
                         r"(serverdeck-([0-9a-f]{32})-([a-z][a-z0-9_]{0,31})\.service)\n", data)
    require(match is not None, "FORBIDDEN")
    hexadecimal = match[2]
    attempt = "-".join((hexadecimal[:8], hexadecimal[8:12], hexadecimal[12:16], hexadecimal[16:20], hexadecimal[20:]))
    uuid(attempt)
    return secure_directory(WORK / match[1].removesuffix(".service")), match[1], attempt, match[3]


def _frontend_locked():
    require(os.environ.get("DPKG_FRONTEND_LOCKED") == "true", "FORBIDDEN")
    ancestors, pid = set(), os.getppid()
    for _ in range(64):
        if pid <= 1 or pid in ancestors:
            break
        ancestors.add(pid)
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        pid = int(raw[raw.rfind(")") + 2:].split()[1])
    target = Path("/var/lib/dpkg/lock-frontend").stat()
    key = f"{os.major(target.st_dev):02x}:{os.minor(target.st_dev):02x}:{target.st_ino}"
    locks = Path("/proc/locks").read_bytes()
    require(len(locks) <= 2 * 1024 * 1024, "RESOURCE_LIMIT")
    for line in locks.decode("ascii").splitlines():
        fields_ = line.split()
        if len(fields_) >= 8 and fields_[1:4] == ["POSIX", "ADVISORY", "WRITE"] and fields_[5] == key:
            holder = int(fields_[4])
            if holder in ancestors and os.readlink(f"/proc/{holder}/exe") == "/usr/bin/apt-get":
                return
    raise Rejected("FORBIDDEN")


def _document(path):
    raw, attributes = regular_file(path, maximum=8 * 1024 * 1024)
    require(attributes["mode"] == 0o600, "FORBIDDEN")
    envelope = decode(raw, 8 * 1024 * 1024)
    fields(envelope, {"document", "checksum"})
    require(digest(envelope["document"]) == envelope["checksum"], "RECOVERY_REQUIRED")
    return envelope["document"]


def verify_transaction(config, actions, context):
    fields(context, {"format", "hostId", "attemptId", "stepId", "unit", "planDigest", "programDigest", "recipeDigest",
                     "bootIdHash", "packages", "files", "pins", "transactionDigest", "expectedPackageSnapshotDigest",
                     "netbirdPreservationDigest"})
    require(context["format"] == 1 and context["bootIdHash"] == boot_id_hash(), "CONFLICT")
    sha(context["planDigest"])
    sha(context["recipeDigest"])
    sha(context["expectedPackageSnapshotDigest"])
    sha(context["programDigest"])
    sha(context["netbirdPreservationDigest"])
    require(netbird_preservation_digest() == context["netbirdPreservationDigest"], "CONFLICT")
    check_config(config)
    policy, policy_mode = regular_file("/usr/sbin/policy-rc.d")
    require(policy == NO_START and policy_mode == {"uid": 0, "gid": 0, "mode": 0o755}, "QUALIFICATION_REQUIRED")
    require(package_snapshot() == context["packages"], "CONFLICT")
    require(type(context["files"]) is list and len(context["files"]) <= 256, "VALIDATION")
    for approved in context["files"]:
        path = Path(approved["path"])
        require(path.parent == Path("/etc/serverdeck-executor") and path.name in
                ("apt.conf", "sources.list") or path == Path(KEYRING) or
                path == Path("/usr/sbin/policy-rc.d") or
                path.parent == Path("/var/lib/apt/lists") and path.name not in ("lock", "partial", "auxfiles"), "FORBIDDEN")
        require(hash_file(path) == approved, "CONFLICT")
    pins = context["pins"]
    require(type(pins) is list and 1 <= len(pins) <= 256, "VALIDATION")
    expected = {(row["name"], row["architecture"], row["version"]): row for row in pins}
    require(len(expected) == len(pins), "VALIDATION")
    seen, archives = set(), []
    for row in actions:
        key = (row["name"], row["architecture"], row["version"])
        pin = expected.get(key)
        require(pin is not None and row["multiArch"] == pin["multiArch"], "CONFLICT")
        operation = "configure" if row["action"] == "**CONFIGURE**" else "install"
        require((key, operation) not in seen, "CONFLICT")
        seen.add((key, operation))
        if operation == "install":
            actual = hash_file(row["action"])
            require(actual["sha256"] == pin["sha256"], "CONFLICT")
            archives.append({"name": pin["name"], "architecture": pin["architecture"],
                             "version": pin["version"], "sha256": actual["sha256"]})
    require(seen == {(key, operation) for key in expected for operation in ("install", "configure")}, "CONFLICT")
    transaction = {"additions": sorted(archives, key=lambda row: (row["name"], row["architecture"])),
                   "configureNew": sorted(f"{row['name']}:{row['architecture']}" for row in pins)}
    require(digest(transaction) == context["transactionDigest"], "CONFLICT")
    return transaction


def main():
    # Killing this read-only gate on deadline aborts the parent before dpkg; it
    # never kills an APT/dpkg transaction after admission.
    signal.signal(signal.SIGALRM, lambda *_: sys.exit(1))
    signal.alarm(5)
    try:
        require(os.geteuid() == 0 and len(sys.argv) == 1 and os.environ.get("APT_HOOK_INFO_FD") == "0", "FORBIDDEN")
        directory, unit, attempt, step = _current_work()
        _frontend_locked()
        context = _document(directory / "apt-context.json")
        launch = _document(directory / "launch.json")
        require(context["unit"] == launch["unit"] == unit and context["attemptId"] == launch["attemptId"] == attempt and
                context["stepId"] == launch["stepId"] == step and
                context["planDigest"] == launch["planDigest"] and context["programDigest"] == launch["programDigest"], "FORBIDDEN")
        program = regular_file(directory / "effect.json", maximum=256 * 1024)[0]
        require(hashlib.sha256(program).hexdigest() == context["programDigest"], "CONFLICT")
        host = decode(regular_file("/etc/serverdeck-executor/host.json")[0])
        require(host["hostId"] == context["hostId"], "FORBIDDEN")
        configuration, actions = parse_protocol(sys.stdin.buffer.read(1024 * 1024 + 1))
        transaction = verify_transaction(configuration, actions, context)
        proof = {"format": 1, "attemptId": attempt, "stepId": step, "unit": unit,
                 "planDigest": context["planDigest"], "transactionDigest": digest(transaction),
                 "protocolDigest": digest(actions), "programDigest": context["programDigest"]}
        descriptor = _file(directory / "apt-gate-proof.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        try:
            _write_all(descriptor, wire_bytes({"document": proof, "checksum": digest(proof)}))
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        # The canonical supervisor journal, not this sidecar alone, must fsync
        # admission before apt is allowed to invoke dpkg. The server validates
        # this actual socket peer PID/cgroup against its committed launch.
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(5)
            client.connect("/run/serverdeck-executor/control.sock")
            with client.makefile("rwb", buffering=0) as channel:
                write_frame(channel, {"gate": proof})
                response = read_frame(channel, 64 * 1024)
                fields(response, {"gateAccepted", "attemptId", "stepId"})
                require(response == {"gateAccepted": True, "attemptId": attempt, "stepId": step}, "FORBIDDEN")
        signal.alarm(0)
    except (Rejected, OSError, ValueError, KeyError, EOFError):
        print("APT_TRANSACTION_REFUSED", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
