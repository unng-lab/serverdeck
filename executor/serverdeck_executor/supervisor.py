"""Root Unix-socket supervisor. No public TCP or caller-selected execution."""

import asyncio
import hashlib
import os
import re
import socket
import stat
import struct
import sys
from pathlib import Path
from uuid import uuid4

from . import RUNTIME_VERSION
from .codec import Rejected, canonical, decode, digest, fields, integer, require, sha, uuid, wire_bytes
from .jobs import EnrolledCaller, ExecutionJobs
from .journal import Journal, secure_directory
from .preflight import PreflightService, RootRuntime, capture_target
from .compiler import compiler_digest
from .probes import boot_id_hash, observe, regular_file
from .jobs import utc_now
from .runner import EffectRunner
from .apt import validate_catalog, LAUNCHER as APT_PROBE_LAUNCHER
from .apt_gate import LAUNCHER as APT_GATE_LAUNCHER
from .qualification import LAUNCHER as RECIPE_CHECK_LAUNCHER

CONFIG = Path("/etc/serverdeck-executor")
SPOOL = Path("/var/lib/serverdeck-executor")
RUN = Path("/run/serverdeck-executor")
CODE = Path("/usr/lib/serverdeck-executor")
INSTALL_ENABLED = True  # Actual prepared catalog and fresh per-effect gates still required.


def configuration(name, maximum=256 * 1024):
    require(name in ("host.json", "enrollment.json", "resources.json", "release.json"), "INTERNAL")
    data, attributes = regular_file(CONFIG / name, maximum=maximum)
    require(attributes["mode"] == 0o600, "EXECUTOR_UNAVAILABLE")
    return decode(data, maximum)


def runtime():
    require(os.geteuid() == 0 and sys.version_info[:2] == (3, 12), "EXECUTOR_UNAVAILABLE")
    require(sys.platform == "linux", "EXECUTOR_UNAVAILABLE")
    release_text = regular_file("/usr/lib/os-release", maximum=16 * 1024)[0].decode("utf-8")
    distribution = {}
    for line in release_text.splitlines():
        match = re.fullmatch(r'([A-Z_]+)=(?:"([^"\n]*)"|([^\s\n]+))', line)
        if match:
            require(match[1] not in distribution, "EXECUTOR_UNAVAILABLE")
            distribution[match[1]] = match[2] if match[2] is not None else match[3]
    require(distribution.get("ID") == "ubuntu" and distribution.get("VERSION_ID") == "24.04" and
            os.uname().machine == "x86_64" and Path("/proc/1/comm").read_bytes().strip() == b"systemd" and
            Path("/sys/fs/cgroup/cgroup.controllers").is_file(), "EXECUTOR_UNAVAILABLE")
    import ansible.release
    require(ansible.release.__version__ == "2.21.5", "EXECUTOR_UNAVAILABLE")
    secure_directory(CONFIG)
    host = configuration("host.json")
    fields(host, {"format", "hostId"})
    require(type(host["format"]) is int and host["format"] == 1)
    uuid(host["hostId"])
    enrollment = configuration("enrollment.json")
    fields(enrollment, {"format", "controllers"})
    require(enrollment["format"] == 1 and type(enrollment["controllers"]) is list and
            len(enrollment["controllers"]) <= 128)
    identities = set()
    for row in enrollment["controllers"]:
        fields(row, {"uid", "controllerId", "workspaceId"})
        identity = (integer(row["uid"], 1, 4294967294), uuid(row["controllerId"]), uuid(row["workspaceId"]))
        require(identity not in identities)
        identities.add(identity)
    registry = configuration("resources.json")
    fields(registry, {"format", "environment", "qualifications", "recipes"})
    require(registry["format"] == 1 and registry["environment"] == "ubuntu24.04-amd64-systemd" and
            type(registry["qualifications"]) is dict and type(registry["recipes"]) is dict)
    require(registry["qualifications"].keys() <= {"postgresql.service", "postgresql.settings",
        "clickhouse.service", "clickhouse.settings"}, "QUALIFICATION_REQUIRED")
    for value in registry["qualifications"].values():
        sha(value)
    # Recipe catalog activation requires the actual APT protocol3 gate and
    # materialized qualification evidence; runtime cannot accept bare hashes.
    require(INSTALL_ENABLED or not registry["recipes"], "QUALIFICATION_REQUIRED")
    validate_catalog(registry["recipes"])
    release = configuration("release.json")
    fields(release, {"format", "runtimeVersion", "lockDigest", "registryDigest", "bridgeDigest", "files"})
    require(release["format"] == 1 and
            release["registryDigest"] == digest(registry), "EXECUTOR_UNAVAILABLE")
    expected = {"__init__.py", "codec.py", "compiler.py", "journal.py", "probes.py", "runner.py",
                "jobs.py", "preflight.py", "bridge.py", "supervisor.py", "qualification.py", "apt.py", "apt_gate.py"}
    require(type(release["files"]) is dict and set(release["files"]) == expected, "EXECUTOR_UNAVAILABLE")
    for name, fingerprint in release["files"].items():
        data, _ = regular_file(CODE / "serverdeck_executor" / name, maximum=1024 * 1024)
        require(hashlib.sha256(data).hexdigest() == fingerprint, "EXECUTOR_UNAVAILABLE")
    lock, _ = regular_file(CODE / "requirements.lock", maximum=256 * 1024)
    require(hashlib.sha256(lock).hexdigest() == release["lockDigest"], "EXECUTOR_UNAVAILABLE")
    bridge, _ = regular_file("/usr/libexec/serverdeck-executor-bridge", maximum=64 * 1024)
    require(hashlib.sha256(bridge).hexdigest() == release["bridgeDigest"], "EXECUTOR_UNAVAILABLE")
    for path, expected in (("/usr/libexec/serverdeck-apt-transaction-gate", APT_GATE_LAUNCHER),
                           ("/usr/lib/serverdeck-executor/apt-probe", APT_PROBE_LAUNCHER),
                           ("/usr/lib/serverdeck-executor/recipe-check", RECIPE_CHECK_LAUNCHER)):
        data, attributes = regular_file(path, maximum=64 * 1024)
        require(data == expected and attributes == {"uid": 0, "gid": 0, "mode": 0o755}, "EXECUTOR_UNAVAILABLE")
    version = RUNTIME_VERSION + "+" + digest({"baseVersion": RUNTIME_VERSION,
        "lockDigest": release["lockDigest"], "bridgeDigest": release["bridgeDigest"], "files": release["files"]})
    require(release["runtimeVersion"] == version, "EXECUTOR_UNAVAILABLE")
    return RootRuntime(host["hostId"], version, release["lockDigest"], digest(registry),
                       registry["qualifications"], registry["recipes"], release["bridgeDigest"]), identities


class Supervisor:
    def __init__(self, root_runtime, enrollment):
        self.runtime, self.enrollment = root_runtime, enrollment
        self.journal = Journal(SPOOL, root_runtime.host_id)
        self.preflights = PreflightService(root_runtime, self.journal)
        self.runner = EffectRunner(SPOOL)
        self.jobs = ExecutionJobs(self.journal, self.runner, self.preflights)
        self.jobs.recover_generation()
        self.connections = 0
        self.gate_connections = 0

    async def request(self, request, uid, caller):
        fields(request, {"v", "id", "method", "params"})
        require(type(request["v"]) is int and request["v"] == 1, "INCOMPATIBLE")
        uuid(request["id"])
        params, method = request["params"], request["method"]
        require(type(params) is dict and type(method) is str)
        if method == "hello":
            fields(params, {"controllerId", "workspaceId"})
            controller, workspace = uuid(params["controllerId"]), uuid(params["workspaceId"])
            require((uid, controller, workspace) in self.enrollment, "FORBIDDEN")
            if caller is None:
                caller = EnrolledCaller(uid, controller, workspace, str(uuid4()))
            require((caller.uid, caller.controller_id, caller.workspace_id) == (uid, controller, workspace), "FORBIDDEN")
            return {"hostId": self.runtime.host_id, "runtimeVersion": self.runtime.version,
                    "lockDigest": self.runtime.lock_digest, "registryDigest": self.runtime.registry_digest,
                    "compilerDigest": compiler_digest(), "bridgeDigest": self.runtime.bridge_digest,
                    "bootIdHash": boot_id_hash(), "capabilities":
                    {"preflight": True, "service": True, "configuration": True,
                     "install": INSTALL_ENABLED and bool(self.runtime.recipes)}}, caller
        require(caller is not None and caller.uid == uid and
                (uid, caller.controller_id, caller.workspace_id) in self.enrollment, "FORBIDDEN")
        if method == "recipes":
            fields(params, {"target", "expectedHostId"})
            require(params["expectedHostId"] == self.runtime.host_id, "TRUST_CHANGED")
            capture_target(params["target"], caller)
            recipes = sorted(self.runtime.recipes.values(), key=lambda row: row["id"])
            available = {row["id"] for row in recipes} if INSTALL_ENABLED else set()
            return {"hostId": self.runtime.host_id, "runtimeVersion": self.runtime.version,
                "registryDigest": self.runtime.registry_digest, "environment": "ubuntu24.04-amd64-systemd",
                "installEnabled": INSTALL_ENABLED and bool(recipes), "recipes": recipes,
                "unavailable": [{"id": name, "code": "QUALIFICATION_REQUIRED"}
                    for name in ("postgresql16", "clickhouse") if name not in available],
                "prerequisites": {"requiresFreshInstall": True, "requiresPreflight": True,
                                  "metadataRefresh": False}}, caller
        if method == "preflight":
            return self.preflights.start(params, caller), caller
        if method == "observe":
            fields(params, {"resourceId", "target", "expectedHostId"})
            require(params["expectedHostId"] == self.runtime.host_id, "TRUST_CHANGED")
            resource = params["resourceId"]
            require(type(resource) is str and resource in {"system.motd", "postgresql.service",
                "postgresql.settings", "clickhouse.service", "clickhouse.settings"}, "UNSUPPORTED")
            target = capture_target(params["target"], caller)
            value = await asyncio.to_thread(observe, resource, self.preflights.qualifications())
            observation = {**target, "resourceId": resource, "hostId": self.runtime.host_id,
                "resourceRegistryDigest": self.runtime.registry_digest, "observedAt": utc_now(),
                "status": "known", "value": value}
            require(len(canonical(observation)) <= 128 * 1024, "RESOURCE_LIMIT")
            return {"observation": observation}, caller
        if method == "preflight_get":
            return self.preflights.get(params, caller), caller
        if method == "submit":
            return await self.jobs.submit(params, caller), caller
        if method == "status":
            return self.jobs.status(params, caller), caller
        if method == "authorize_step":
            return await self.jobs.authorize(params, caller), caller
        if method == "cancel":
            return self.jobs.cancel(params, caller), caller
        if method == "reconcile":
            return await self.jobs.reconcile(params, caller), caller
        raise Rejected("UNSUPPORTED")

    async def connection(self, reader, writer):
        peer = writer.get_extra_info("socket").getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
        peer_pid, uid, _ = struct.unpack("3i", peer)
        gate_peer = uid == 0 and self.jobs.is_apt_gate_peer(peer_pid)
        if uid != 0 or (self.gate_connections >= 1 if gate_peer else self.connections >= 16):
            writer.close()
            await writer.wait_closed()
            return
        if gate_peer:
            self.gate_connections += 1
        else:
            self.connections += 1
        caller = None
        try:
            while True:
                try:
                    header = await asyncio.wait_for(reader.readexactly(4), timeout=5) if gate_peer else await reader.readexactly(4)
                except asyncio.IncompleteReadError:
                    return
                count, = struct.unpack(">I", header)
                require(0 < count <= 256 * 1024 + 4096, "INVALID_FRAME")
                data = await asyncio.wait_for(reader.readexactly(count), timeout=5)
                envelope = decode(data, 256 * 1024 + 4096)
                if set(envelope) == {"gate"}:
                    require(gate_peer and caller is None, "FORBIDDEN")
                    result = self.jobs.accept_apt_gate(envelope["gate"], peer_pid)
                    encoded = wire_bytes(result)
                    writer.write(struct.pack(">I", len(encoded)) + encoded)
                    await asyncio.wait_for(writer.drain(), timeout=5)
                    return
                require(not gate_peer, "FORBIDDEN")
                fields(envelope, {"uid", "request"})
                uid = integer(envelope["uid"], 1, 4294967294)
                request = envelope["request"]
                # Apply the public request budget independently of bridge metadata.
                require(len(canonical(request)) <= 256 * 1024, "RESOURCE_LIMIT")
                request_id = uuid(request.get("id")) if type(request) is dict else None
                require(request_id is not None)
                try:
                    # Admission/native probe work may continue after logical IO
                    # deadline; never cancel a committed job or its child here.
                    task = asyncio.create_task(self.request(request, uid, caller))
                    try:
                        result, new_caller = await asyncio.wait_for(asyncio.shield(task), timeout=5)
                    except asyncio.TimeoutError:
                        await task
                        raise Rejected("TIMEOUT")
                    caller = new_caller
                    response = {"id": request_id, "result": result}
                except Rejected as error:
                    response = {"id": request_id, "error": {"code": error.code, "retry": error.retry}}
                encoded = wire_bytes(response)
                require(len(encoded) <= 8 * 1024 * 1024, "RESOURCE_LIMIT")
                writer.write(struct.pack(">I", len(encoded)) + encoded)
                await asyncio.wait_for(writer.drain(), timeout=5)
        except (Rejected, OSError, asyncio.IncompleteReadError, asyncio.TimeoutError):
            pass
        finally:
            if caller is not None:
                self.jobs.detached(caller)
            if gate_peer:
                self.gate_connections -= 1
            else:
                self.connections -= 1
            writer.close()
            await writer.wait_closed()

    async def serve(self):
        secure_directory(RUN)
        path = RUN / "control.sock"
        if path.exists() or path.is_symlink():
            info = path.lstat()
            require(stat.S_ISSOCK(info.st_mode) and info.st_uid == 0, "EXECUTOR_UNAVAILABLE")
            path.unlink()
        server = await asyncio.start_unix_server(self.connection, path=path)
        os.chmod(path, 0o600)
        async with server:
            while True:
                self.jobs.tick()
                await asyncio.sleep(1)


def main():
    try:
        root_runtime, enrollment = runtime()
        asyncio.run(Supervisor(root_runtime, enrollment).serve())
    except (Rejected, OSError):
        # systemd sees only a fixed failure. No local config/document traceback.
        sys.exit(1)


if __name__ == "__main__":
    main()
