"""One committed effect in a tracked systemd unit; no unsafe timeout kill."""

import asyncio
import hashlib
import os
import shutil
import stat
from dataclasses import dataclass
from pathlib import Path

from .codec import Rejected, canonical, digest, identifier, require, uuid, wire_bytes
from .compiler import playbook
from .journal import _file, _write_all, secure_directory
from .probes import PROBE_ENV, command, system_slice_cgroup

ANSIBLE = "/opt/serverdeck-executor/venv/bin/ansible-playbook"
OUTPUT_LIMIT = 1024 * 1024


def _mount_id(descriptor):
    with open(f"/proc/self/fdinfo/{descriptor}", "rb") as stream:
        data = stream.read(4097)
    require(len(data) <= 4096, "RESOURCE_LIMIT")
    rows = [line.split(b":", 1)[1].strip() for line in data.splitlines() if line.startswith(b"mnt_id:")]
    require(len(rows) == 1 and rows[0].isdigit(), "RECOVERY_REQUIRED")
    return rows[0]


def _walk_error(error):
    raise error


ANSIBLE_CONFIG = """[defaults]
inventory = /dev/null
host_key_checking = True
retry_files_enabled = False
gathering = explicit
local_tmp = ./tmp
remote_tmp = ./remote-tmp
roles_path = /usr/lib/serverdeck-executor/empty
collections_path = /opt/serverdeck-executor/venv/lib/python3.12/site-packages/ansible_collections
action_plugins = /usr/lib/serverdeck-executor/empty
callback_plugins = /usr/lib/serverdeck-executor/empty
connection_plugins = /usr/lib/serverdeck-executor/empty
filter_plugins = /usr/lib/serverdeck-executor/empty
lookup_plugins = /usr/lib/serverdeck-executor/empty
vars_plugins = /usr/lib/serverdeck-executor/empty
library = /usr/lib/serverdeck-executor/empty
fact_caching = memory
nocows = True
display_args_to_stdout = False
no_target_syslog = True
[privilege_escalation]
become = False
"""


@dataclass(frozen=True)
class EffectOutcome:
    # "completed" is process completion only. Required factual postchecks still
    # determine success. Unknown never releases durable host occupancy.
    state: str
    code: str | None
    output_truncated: bool
    unit: str


class EffectRunner:
    def __init__(self, spool):
        self.directory = secure_directory(Path(spool) / "work")
        self.running = {}
        self.draining = set()

    @staticmethod
    def unit(attempt_id, step_id):
        return "serverdeck-" + uuid(attempt_id).replace("-", "") + "-" + identifier(step_id) + ".service"

    def cleanup_terminal(self, attempt_id, effects):
        """Delete private inputs only after caller proves a durable terminal job.

        Receipts/full execution documents live in Journal, never under work/.
        Every target is derived from its immutable attempt/effect IDs. Unknown
        directories without a receipt are intentionally retained for recovery.
        """
        require(shutil.rmtree.avoids_symlink_attacks, "EXECUTOR_UNAVAILABLE")
        require(not self.draining, "HOST_BUSY")
        secure_directory(self.directory)
        parent = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            parent_info = os.fstat(parent)
            parent_mount = _mount_id(parent)
            for effect in effects:
                unit = self.unit(attempt_id, effect["id"])
                name = unit.removesuffix(".service")
                require(unit not in self.running, "HOST_BUSY")
                try:
                    initial = os.stat(name, dir_fd=parent, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                require(stat.S_ISDIR(initial.st_mode) and initial.st_uid == 0 and
                        stat.S_IMODE(initial.st_mode) == 0o700 and initial.st_dev == parent_info.st_dev,
                        "RECOVERY_REQUIRED")
                require(self.proven_stopped(unit), "RECOVERY_REQUIRED")
                count, total = 0, 0
                for root, directories, files, descriptor in os.fwalk(name, dir_fd=parent,
                                                                   onerror=_walk_error,
                                                                   follow_symlinks=False):
                    require(len(Path(root).parts) <= 16, "RESOURCE_LIMIT")
                    current = os.fstat(descriptor)
                    require(current.st_uid == 0 and current.st_dev == initial.st_dev and
                            not current.st_mode & 0o022 and _mount_id(descriptor) == parent_mount,
                            "RECOVERY_REQUIRED")
                    for entry in directories + files:
                        count += 1
                        require(count <= 4096, "RESOURCE_LIMIT")
                        info = os.stat(entry, dir_fd=descriptor, follow_symlinks=False)
                        require(info.st_uid == 0 and info.st_dev == initial.st_dev and
                                (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode) or
                                 stat.S_ISLNK(info.st_mode)), "RECOVERY_REQUIRED")
                        if stat.S_ISREG(info.st_mode):
                            total += info.st_size
                            require(info.st_nlink == 1 and total <= 128 * 1024 * 1024, "RESOURCE_LIMIT")
                # No effect can be admitted for a terminal attempt. Still prove
                # kernel stop and directory identity immediately before removal.
                current = os.stat(name, dir_fd=parent, follow_symlinks=False)
                require((current.st_ino, current.st_dev) == (initial.st_ino, initial.st_dev) and
                        unit not in self.running and self.proven_stopped(unit), "RECOVERY_REQUIRED")
                shutil.rmtree(name, dir_fd=parent)
                os.fsync(parent)
        finally:
            os.close(parent)

    def prepare(self, attempt_id, effect, recipes, *, registry_digest=None):
        """Before launch commitment; exclusively create immutable literal input."""
        unit = self.unit(attempt_id, effect["id"])
        path = self.directory / unit.removesuffix(".service")
        # Never reuse an existing workdir, even after a crash before child spawn.
        path.mkdir(mode=0o700)
        secure_directory(path)
        for name in ("tmp", "remote-tmp", "home"):
            (path / name).mkdir(mode=0o700)
        document = canonical(playbook(effect, recipes, registry_digest=registry_digest))
        for name, data in (("effect.json", document), ("ansible.cfg", ANSIBLE_CONFIG.encode("ascii"))):
            descriptor = _file(path / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
            try:
                _write_all(descriptor, data)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        return {"unit": unit, "programDigest": hashlib.sha256(document).hexdigest()}

    def bind_launch(self, attempt_id, effect, commitment, receipt):
        if effect["kind"] != "install_recipe":
            return
        # Called only AFTER the supervisor has fsynced launch_committed. No
        # incoming root/MCP method can manufacture either of these documents.
        path = self.directory / self.unit(attempt_id, effect["id"]).removesuffix(".service")
        facts = receipt["execution"].get("aptTransactions", {}).get(effect["id"])
        require(type(facts) is dict, "QUALIFICATION_REQUIRED")
        launch = {"format": 1, "attemptId": attempt_id, "stepId": effect["id"],
                  "unit": commitment["unit"], "planDigest": receipt["planDigest"],
                  "programDigest": commitment["programDigest"]}
        context = {**launch, "hostId": receipt["expectedHostId"],
                   "recipeDigest": effect["recipeDigest"],
                   "bootIdHash": receipt["execution"]["capsule"]["bootIdHash"],
                   "netbirdPreservationDigest": receipt["execution"]["netbirdPreservationDigest"],
                   "packages": facts["packages"], "files": facts["files"], "pins": facts["pins"],
                   "expectedPackageSnapshotDigest": digest(facts["expectedPackages"]),
                   "transactionDigest": facts["transactionDigest"]}
        for name, value in (("launch.json", launch), ("apt-context.json", context)):
            descriptor = _file(path / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
            try:
                _write_all(descriptor, wire_bytes({"document": value, "checksum": digest(value)}))
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

    async def launch_committed(self, attempt_id, effect, commitment, *, apt_config=None):
        """Caller must fsync launch_committed and consume authority FIRST.

        This private supervisor API accepts only its retained preparation and
        committed receipt. Neither the method nor a launch boolean is exposed
        over MCP/root wire. Recovery never calls it for an existing commitment.
        """
        unit = self.unit(attempt_id, effect["id"])
        require(commitment["unit"] == unit and unit not in self.running, "CONFLICT")
        path = self.directory / unit.removesuffix(".service")
        secure_directory(path)
        descriptor = _file(path / "effect.json", os.O_RDONLY)
        try:
            data = os.read(descriptor, 256 * 1024 + 1)
            require(hashlib.sha256(data).hexdigest() == commitment["programDigest"], "CONFLICT")
        finally:
            os.close(descriptor)
        environment = {**PROBE_ENV, "HOME": str(path / "home"),
                       "ANSIBLE_CONFIG": str(path / "ansible.cfg"),
                       "ANSIBLE_NOCOLOR": "1", "ANSIBLE_LOAD_CALLBACK_PLUGINS": "0"}
        if effect["kind"] == "install_recipe":
            # No package effect without the fixed, qualified protocol3 gate.
            require(apt_config == "/etc/serverdeck-executor/apt.conf", "QUALIFICATION_REQUIRED")
            environment["APT_CONFIG"] = apt_config
        try:
            process = await asyncio.create_subprocess_exec(
                "/usr/bin/systemd-run", "--quiet", "--wait", "--pipe", "--service-type=exec",
                "--unit=" + unit, "--property=KillMode=none", "--property=TimeoutStartSec=infinity",
                "--property=Slice=system.slice",
                "--property=TimeoutStopSec=infinity", "--property=Restart=no",
                "--property=UMask=0077", "--property=WorkingDirectory=" + str(path),
                "/usr/bin/env", "-i", *(f"{key}={value}" for key, value in environment.items()),
                ANSIBLE, "--inventory", "localhost,", "--connection", "local", str(path / "effect.json"),
                cwd=path, env=PROBE_ENV, stdin=asyncio.subprocess.DEVNULL,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        except OSError:
            # Commitment already exists: lack of a child handle is uncertainty,
            # never permission to retry the same effect with a new request id.
            return EffectOutcome("unknown", "EXECUTOR_UNAVAILABLE", False, unit)
        self.running[unit] = process
        truncated = [False]

        async def discard(stream):
            size = 0
            while chunk := await stream.read(8192):
                size += len(chunk)
                truncated[0] |= size > OUTPUT_LIMIT
                # Deliberately never retain module output or expose it as an
                # event. The independent typed postchecks are the evidence.

        async def drain():
            await asyncio.gather(discard(process.stdout), discard(process.stderr), process.wait())
            self.running.pop(unit, None)

        task = asyncio.create_task(drain())
        self.draining.add(task)
        task.add_done_callback(self.draining.discard)
        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=30 * 60)
        except asyncio.TimeoutError:
            # Keep draining and tracking. Do not kill systemd-run or apt/dpkg.
            return EffectOutcome("unknown", "TIMEOUT", truncated[0], unit)
        if not await asyncio.to_thread(self.proven_stopped, unit):
            return EffectOutcome("unknown", "RECOVERY_REQUIRED", truncated[0], unit)
        return EffectOutcome("completed", None if process.returncode == 0 else "STEP_FAILED",
                             truncated[0], unit)

    @staticmethod
    def recovered_completion(unit):
        if not EffectRunner.proven_stopped(unit):
            return None
        try:
            output = command(["/usr/bin/systemctl", "show", unit, "--no-pager",
                              "--property=LoadState,ExecMainCode,ExecMainStatus,Result"],
                             accepted_codes=(0, 4)).decode("ascii")
            values = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
            # A collected unit has lost its exit evidence. Cgroup absence alone
            # is not successful execution and never justifies an automatic retry.
            if values.get("LoadState") != "loaded" or values.get("ExecMainCode") not in ("1", "2", "3"):
                return None
            return "succeeded" if (values["ExecMainCode"] == "1" and
                values.get("ExecMainStatus") == "0" and values.get("Result") == "success") else "failed"
        except (OSError, ValueError, Rejected):
            return None

    @staticmethod
    def proven_stopped(unit):
        # Unit is generated from private captured IDs, not caller arbitrary text.
        require(unit.startswith("serverdeck-") and "/" not in unit and "\0" not in unit, "INTERNAL")
        try:
            output = command(["/usr/bin/systemctl", "show", unit, "--no-pager",
                              "--property=LoadState,ActiveState,SubState,MainPID,ControlPID,ControlGroup"],
                             accepted_codes=(0, 4)).decode("utf-8")
            values = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
            require(values.get("LoadState") in ("loaded", "not-found"), "RECOVERY_REQUIRED")
            require(values.get("ActiveState") in ("inactive", "failed") and
                    values.get("MainPID") == "0" and values.get("ControlPID") == "0", "RECOVERY_REQUIRED")
            expected = system_slice_cgroup() + "/" + unit
            group = values.get("ControlGroup") or expected
            require(group == expected, "RECOVERY_REQUIRED")
            path = Path("/sys/fs/cgroup") / group.removeprefix("/")
            if path.exists():
                events = dict(line.split() for line in (path / "cgroup.events").read_text().splitlines())
                require(events.get("populated") == "0", "RECOVERY_REQUIRED")
            return True
        except (OSError, ValueError, Rejected):
            return False
