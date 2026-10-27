"""Root journal with durable host occupancy and no uncertain-step retry.

The journal is the authority. A checksummed snapshot accelerates inspection but
never authorizes skipping a damaged journal tail. Disk/IO failures poison the
writer until operator recovery; existing evidence is retained untouched.
"""

import copy
import hashlib
import os
import stat
import struct
from pathlib import Path

from .codec import Rejected, canonical, decode, fields, integer, require, sha, uuid, wire_bytes

QUOTA = 256 * 1024 * 1024
FREE_FLOOR = 16 * 1024 * 1024
MAX_RECORD = 8 * 1024 * 1024


def secure_directory(path, mode=0o700):
    """Inspect every actual ancestor; do not follow symlinks during creation."""
    path = Path(path)
    require(path.is_absolute(), "EXECUTOR_UNAVAILABLE")
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            current.mkdir(mode=mode)
            info = current.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and
                not info.st_mode & 0o022, "EXECUTOR_UNAVAILABLE")
    require(stat.S_IMODE(path.stat().st_mode) == mode, "EXECUTOR_UNAVAILABLE")
    return path


def _file(path, flags, mode=0o600):
    descriptor = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC, mode)
    if flags & os.O_CREAT and flags & os.O_EXCL:
        # A restrictive administrator umask must not change the required mode
        # of a file we exclusively created. Never chmod an existing file here.
        os.fchmod(descriptor, mode)
    info = os.fstat(descriptor)
    if not (stat.S_ISREG(info.st_mode) and info.st_uid == 0 and
            info.st_nlink == 1 and stat.S_IMODE(info.st_mode) == mode):
        os.close(descriptor)
        raise Rejected("EXECUTOR_UNAVAILABLE")
    return descriptor


def _write_all(descriptor, data):
    view = memoryview(data)
    while view:
        count = os.write(descriptor, view)
        if count <= 0:
            raise OSError("short write")
        view = view[count:]


def atomic_document(directory, name, value):
    # Names are private constants supplied by the supervisor, never wire paths.
    require(name in ("snapshot.json", "host.json", "enrollment.json", "resources.json", "release.json",
                     "catalog-candidate.json"), "INTERNAL")
    data = wire_bytes(value)
    target, temporary = directory / name, directory / (name + ".pending")
    descriptor = _file(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    try:
        _write_all(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    # A previous pending file is not deleted on recovery: a crash is evidence.
    os.replace(temporary, target)
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


class Journal:
    def __init__(self, directory, host_id):
        import fcntl

        require(os.geteuid() == 0, "FORBIDDEN")
        self.directory = secure_directory(directory)
        self.host_id = uuid(host_id)
        self.blocked = False
        self.sequence = 0
        self.previous = "0" * 64
        self.state = {"hostId": host_id, "occupied": None, "plans": {}, "jobs": {}, "resources": {}}
        self.lock = _file(self.directory / "writer.lock", os.O_RDWR | os.O_CREAT)
        self.descriptor = None
        try:
            try:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Rejected("HOST_BUSY") from None
            self.descriptor = _file(self.directory / "journal.bin", os.O_RDWR | os.O_CREAT | os.O_APPEND)
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            self._recover()
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.descriptor is not None:
            os.close(self.descriptor)
            self.descriptor = None
        if self.lock is not None:
            os.close(self.lock)
            self.lock = None

    def _recover(self):
        size = os.fstat(self.descriptor).st_size
        require(size <= QUOTA, "RESOURCE_LIMIT")
        offset = 0
        while offset < size:
            header = os.pread(self.descriptor, 4, offset)
            require(len(header) == 4, "RECOVERY_REQUIRED")
            count, = struct.unpack(">I", header)
            require(0 < count <= MAX_RECORD and offset + count + 36 <= size, "RECOVERY_REQUIRED")
            data = os.pread(self.descriptor, count, offset + 4)
            checksum = os.pread(self.descriptor, 32, offset + 4 + count)
            require(hashlib.sha256(data).digest() == checksum, "RECOVERY_REQUIRED")
            document = decode(data, MAX_RECORD)
            fields(document, {"format", "hostId", "sequence", "previous", "transaction"})
            require(document["format"] == 1 and type(document["format"]) is int and
                    document["hostId"] == self.host_id and
                    document["sequence"] == self.sequence + 1 and
                    type(document["sequence"]) is int and document["previous"] == self.previous,
                    "RECOVERY_REQUIRED")
            candidate = copy.deepcopy(self.state)
            self._apply(candidate, document["transaction"])
            self.state = candidate
            self.sequence += 1
            self.previous = checksum.hex()
            offset += count + 36
        # A committed launch is never replayed here. The supervisor must prove
        # cgroup/process outcome; until then its durable occupancy remains.

    def _space(self, additional):
        total = 0
        for root, directories, files in os.walk(self.directory, followlinks=False):
            for name in directories + files:
                info = (Path(root) / name).lstat()
                require(not stat.S_ISLNK(info.st_mode), "EXECUTOR_UNAVAILABLE")
                if stat.S_ISREG(info.st_mode):
                    total += info.st_size
        free = os.statvfs(self.directory)
        require(total + additional <= QUOTA and
                free.f_bavail * free.f_frsize - additional >= FREE_FLOOR, "RESOURCE_LIMIT")

    def commit(self, transaction):
        require(not self.blocked, "RECOVERY_REQUIRED")
        candidate = copy.deepcopy(self.state)
        self._apply(candidate, transaction)
        data = wire_bytes({"format": 1, "hostId": self.host_id,
                          "sequence": self.sequence + 1, "previous": self.previous,
                          "transaction": transaction})
        require(len(data) <= MAX_RECORD, "RESOURCE_LIMIT")
        self._space(len(data) + 36)
        checksum = hashlib.sha256(data).digest()
        try:
            _write_all(self.descriptor, struct.pack(">I", len(data)) + data + checksum)
            os.fsync(self.descriptor)
        except OSError:
            self.blocked = True
            raise Rejected("RECOVERY_REQUIRED") from None
        self.state, self.previous = candidate, checksum.hex()
        self.sequence += 1

    def snapshot(self):
        require(not self.blocked, "RECOVERY_REQUIRED")
        value = {"format": 1, "hostId": self.host_id, "sequence": self.sequence,
                 "previous": self.previous, "state": self.state}
        envelope = {"document": value, "checksum": digest_document(value)}
        self._space(len(wire_bytes(envelope)))
        try:
            atomic_document(self.directory, "snapshot.json", envelope)
        except OSError:
            self.blocked = True
            raise Rejected("RECOVERY_REQUIRED") from None

    @staticmethod
    def _apply(state, transaction):
        fields(transaction, {"kind", "attemptId"}, {"job", "patch", "event", "release", "resources"})
        attempt = uuid(transaction["attemptId"])
        kind = transaction["kind"]
        if kind == "admit":
            fields(transaction, {"kind", "attemptId", "job"})
            job = transaction["job"]
            require(type(job) is dict and job.get("attemptId") == attempt)
            plan = sha(job.get("planDigest"))
            require(attempt not in state["jobs"] and plan not in state["plans"], "CONFLICT")
            require(state["occupied"] is None, "HOST_BUSY")
            require(len(state["jobs"]) < 1000, "RESOURCE_LIMIT")
            require(job.get("state") == "queued" and job.get("events") == [] and
                    job.get("sequence") == 0, "INTERNAL")
            state["jobs"][attempt] = copy.deepcopy(job)
            state["plans"][plan] = attempt
            state["occupied"] = attempt
            return
        require(kind == "update" and attempt in state["jobs"], "NOT_FOUND")
        fields(transaction, {"kind", "attemptId", "patch", "event", "release"}, {"resources"})
        job, patch, event = state["jobs"][attempt], transaction["patch"], transaction["event"]
        require(type(patch) is dict and patch.keys() <= {
            "state", "stepIndex", "challenge", "launch", "checks", "stopRequested",
            "authorizationEpoch", "finishedAt", "failureCode", "droppedEvents", "cancelRequests", "aptGateProof"}, "INTERNAL")
        require(type(transaction["release"]) is bool, "INTERNAL")
        sequence = job["sequence"] + 1
        fields(event, {"sequence", "at", "kind", "stepId", "code"})
        require(event["sequence"] == sequence and type(event["sequence"]) is int and
                len(canonical(event)) <= 4096, "INTERNAL")
        bindings = transaction.get("resources")
        if bindings is not None:
            require(type(bindings) is dict and len(bindings) == 2 and
                    set(bindings) <= {"postgresql.settings", "postgresql.service", "clickhouse.settings", "clickhouse.service"} and
                    job["state"] in ("running", "unknown") and job.get("aptGateProof") is not None and
                    patch.get("stepIndex") == job["stepIndex"] + 1 and
                    patch.get("state") in ("waiting", "succeeded", "cancelled-partial"), "INTERNAL")
            effect = job["execution"]["effects"][job["stepIndex"]]
            require(effect["kind"] == "install_recipe", "INTERNAL")
            recipe = job["execution"]["recipes"][effect["recipeDigest"]]
            require(set(bindings) == set(recipe["ownedResources"]), "INTERNAL")
            checks = [check for check in job["execution"]["checks"] if check["effectId"] == effect["id"]]
            require(len(checks) == 1 and checks[0]["kind"] == "recipe" and
                    {"checkId": checks[0]["id"], "passed": True} in patch.get("checks", []), "INTERNAL")
            for resource, binding in bindings.items():
                fields(binding, {"format", "hostId", "resourceId", "recipeDigest", "registryDigest", "runtimeVersion",
                                 "sourceAttemptId", "sourceEffectId", "baselineDigest", "confirmedAt"})
                require(type(binding["format"]) is int and binding["format"] == 1 and
                        binding["hostId"] == state["hostId"] and binding["resourceId"] == resource and
                        binding["recipeDigest"] == recipe["digest"] and binding["sourceAttemptId"] == attempt and
                        binding["sourceEffectId"] == effect["id"] and
                        binding["registryDigest"] == job["execution"]["capsule"]["registryDigest"] and
                        binding["runtimeVersion"] == job["execution"]["capsule"]["runtimeVersion"], "INTERNAL")
                sha(binding["baselineDigest"])
                from datetime import datetime
                timestamp = datetime.fromisoformat(binding["confirmedAt"].replace("Z", "+00:00"))
                require(binding["confirmedAt"].endswith("Z") and
                        timestamp.isoformat(timespec="milliseconds").replace("+00:00", "Z") == binding["confirmedAt"],
                        "INTERNAL")
            state.setdefault("resources", {}).update(copy.deepcopy(bindings))
        job.update(copy.deepcopy(patch))
        job["sequence"] = sequence
        if len(job["events"]) < 10000:
            job["events"].append(copy.deepcopy(event))
        elif event["kind"] in ("progress", "waiting"):
            job["droppedEvents"] = job.get("droppedEvents", 0) + 1
        else:
            # Keep outcome/current sequence; bounded history may discard only
            # progress, never a commitment, authorization or terminal outcome.
            progress = next((i for i, row in enumerate(job["events"])
                             if row["kind"] in ("progress", "waiting")), None)
            require(progress is not None, "RESOURCE_LIMIT")
            job["events"].pop(progress)
            job["events"].append(copy.deepcopy(event))
            job["droppedEvents"] = job.get("droppedEvents", 0) + 1
        if transaction["release"]:
            require(state["occupied"] == attempt and job["state"] in
                    ("succeeded", "failed", "cancelled", "cancelled-partial"), "INTERNAL")
            state["occupied"] = None


def digest_document(value):
    return hashlib.sha256(canonical(value)).hexdigest()
