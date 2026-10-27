"""Durable single-step job state machine used by the root supervisor.

This is not a wire authorization API: caller identities and prepared executions
are supplied by the enrolled socket/preflight services, never trusted JSON flags.
"""

import asyncio
import base64
import copy
import datetime
import hmac
import secrets
import time
from dataclasses import dataclass

from .codec import Rejected, digest, fields, integer, require, sha, uuid
from .probes import boot_id_hash, system_slice_cgroup


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class EnrolledCaller:
    uid: int
    controller_id: str
    workspace_id: str
    stream_id: str


class ExecutionJobs:
    """All methods run on one supervisor event loop; persistence precedes ACK.

    preflights.admit() rechecks the cached full facts/input tuple and returns a
    private immutable execution document. revalidate()/postcheck() are the fixed
    root probes. They must not accept arbitrary commands, paths or caller checks.
    """
    def __init__(self, journal, runner, preflights):
        self.journal, self.runner, self.preflights = journal, runner, preflights
        self.tasks = {}
        self.challenges = {}
        self.waiting = {}
        self.reconciling = set()
        self.watch = time.monotonic()
        self.cleanup_task = None
        self.cleaned_attempts = set()
        self.cleanup_retry_after = {}

    def recover_generation(self):
        for attempt, job in list(self.journal.state["jobs"].items()):
            if job["state"] in ("succeeded", "failed", "cancelled", "cancelled-partial"):
                continue
            if job.get("launch") is not None:
                self._update(attempt, {"state": "unknown", "challenge": None,
                                       "failureCode": "RECOVERY_REQUIRED"}, "recovery", "RECOVERY_REQUIRED")
            else:
                # No committed child can exist. Do not resurrect authorization
                # after supervisor generation change, even for a queued job.
                state = "cancelled-partial" if job["stepIndex"] else "cancelled"
                self._update(attempt, {"state": state, "challenge": None,
                                       "stopRequested": True, "finishedAt": utc_now()},
                             "terminal", "CANCELLED", release=True)

    def _job(self, attempt, caller):
        job = self.journal.state["jobs"].get(uuid(attempt))
        require(job is not None, "NOT_FOUND")
        require(job["controllerId"] == caller.controller_id and
                job["workspaceId"] == caller.workspace_id and job["uid"] == caller.uid, "HOST_BUSY")
        return job

    def _update(self, attempt, patch, kind, code=None, *, release=False, resources=None):
        job = self.journal.state["jobs"][attempt]
        effect = job["execution"]["effects"]
        index = job["stepIndex"]
        self.journal.commit({"kind": "update", "attemptId": attempt, "patch": patch,
                             "event": {"sequence": job["sequence"] + 1, "at": utc_now(),
                                       "kind": kind, "stepId": effect[index]["id"] if index < len(effect) else None,
                                       "code": code}, "release": release,
                             **({"resources": resources} if resources else {})})

    async def _postcheck(self, job, effect):
        if effect["kind"] == "install_recipe":
            return await self.preflights.postcheck_recipe(job, effect)
        return await self.preflights.postcheck(job, effect), {}

    async def submit(self, params, caller):
        fields(params, {"jobId", "attemptId", "planDigest", "profileId", "profileRevision",
                        "profileBody", "profileDigest", "parameters", "preflightDigest", "expectedHostId",
                        "controllerId", "workspaceId"})
        for key in ("jobId", "attemptId", "profileId", "expectedHostId", "controllerId", "workspaceId"):
            uuid(params[key])
        for key in ("planDigest", "profileDigest", "preflightDigest"):
            sha(params[key])
        integer(params["profileRevision"], 1, 2147483647)
        require(params["expectedHostId"] == self.journal.host_id, "TRUST_CHANGED")
        require(params["controllerId"] == caller.controller_id and
                params["workspaceId"] == caller.workspace_id, "FORBIDDEN")
        request_digest = digest(params)
        existing = self.journal.state["plans"].get(params["planDigest"])
        if existing is not None:
            job = self._job(existing, caller)
            require(job["requestDigest"] == request_digest, "CONFLICT")
            return {"attemptId": existing, "state": job["state"], "sequence": job["sequence"]}
        # Check current occupancy before expensive pure probes; there is no
        # waiting host queue. Recheck atomically in journal admission afterwards.
        require(self.journal.state["occupied"] is None, "HOST_BUSY")
        execution = await self.preflights.admit(copy.deepcopy(params), caller)
        require(type(execution) is dict and len(execution["effects"]) <= 32, "PREFLIGHT_FAILED")
        # Admission probes may have yielded while another controller won.
        job = {**copy.deepcopy(params), "uid": caller.uid, "requestDigest": request_digest,
               "execution": execution, "state": "queued", "createdAt": utc_now(),
               "startedMonotonic": time.monotonic(), "stepIndex": 0, "events": [], "sequence": 0,
               "challenge": None, "launch": None, "checks": [], "stopRequested": False,
               "authorizationEpoch": 0, "finishedAt": None, "failureCode": None,
               "droppedEvents": 0, "cancelRequests": {}, "aptGateProof": None}
        # Monotonic values are memory-only. Recovery uses the durable state and
        # boot/process evidence, never a previous process's monotonic deadline.
        job.pop("startedMonotonic")
        self.journal.commit({"kind": "admit", "attemptId": params["attemptId"], "job": job})
        self.waiting[params["attemptId"]] = (time.monotonic(), time.monotonic())
        if not execution["effects"]:
            self._update(params["attemptId"], {"state": "succeeded", "finishedAt": utc_now()},
                         "terminal", release=True)
            return {"attemptId": params["attemptId"], "state": "succeeded", "sequence": 1}
        return {"attemptId": params["attemptId"], "state": "queued", "sequence": 0}

    def status(self, params, caller):
        fields(params, {"attemptId"}, {"afterSequence", "limit"})
        job = self._job(params["attemptId"], caller)
        after = integer(params.get("afterSequence", 0), 0, 9223372036854775807)
        limit = integer(params.get("limit", 50), 1, 100)
        attempt = params["attemptId"]
        if job["state"] in ("queued", "waiting") and not job["stopRequested"]:
            require(job["stepIndex"] < len(job["execution"]["effects"]), "PREFLIGHT_FAILED")
            cached = self.challenges.get(attempt)
            if cached is None or time.monotonic() >= cached[1] or cached[2] != caller.stream_id:
                nonce = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii").rstrip("=")
                expires = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=5)
                challenge = {"challenge": nonce, "stepId": job["execution"]["effects"][job["stepIndex"]]["id"],
                             "planDigest": job["planDigest"],
                             "expiresAt": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z")}
                self._update(attempt, {"state": "waiting", "challenge": challenge}, "waiting")
                self.challenges[attempt] = (nonce, time.monotonic() + 5, caller.stream_id)
                job = self._job(attempt, caller)
        return {"attemptId": attempt, "state": job["state"], "stepIndex": job["stepIndex"],
                "authorizationEpoch": job["authorizationEpoch"],
                "sequence": job["sequence"], "events": [copy.deepcopy(row) for row in job["events"]
                    if row["sequence"] > after][:limit], "checks": copy.deepcopy(job["checks"]),
                "needsAuthorization": copy.deepcopy(job["challenge"]),
                "failureCode": job["failureCode"], "droppedEvents": job["droppedEvents"]}

    async def authorize(self, params, caller):
        fields(params, {"attemptId", "stepId", "planDigest", "challenge", "authorizationEpoch", "expiresAt"})
        attempt = params["attemptId"]
        job = self._job(attempt, caller)
        epoch = integer(params["authorizationEpoch"], 1, 2147483647)
        cached, public = self.challenges.get(attempt), job["challenge"]
        require(cached is not None and public is not None and job["state"] == "waiting" and
                not job["stopRequested"] and attempt not in self.tasks, "CONFLICT")
        require(type(params["challenge"]) is str and
                hmac.compare_digest(cached[0], params["challenge"]) and cached[2] == caller.stream_id and
                time.monotonic() < cached[1] and params["expiresAt"] == public["expiresAt"] and
                params["planDigest"] == job["planDigest"] and params["stepId"] == public["stepId"] and
                epoch > job["authorizationEpoch"], "FORBIDDEN")
        expires = datetime.datetime.fromisoformat(public["expiresAt"].replace("Z", "+00:00"))
        require(0 < (expires - datetime.datetime.now(datetime.timezone.utc)).total_seconds() <= 5, "FORBIDDEN")
        await self.preflights.revalidate(job)
        # Recheck after probes: cancel/session-loss/competing authority can win.
        require(self._job(attempt, caller) is job and self.challenges.get(attempt) == cached and
                time.monotonic() < cached[1] and not job["stopRequested"], "CONFLICT")
        effect = job["execution"]["effects"][job["stepIndex"]]
        preparation = (self.runner.prepare(attempt, effect, job["execution"]["recipes"],
            registry_digest=job["execution"]["capsule"]["registryDigest"])
            if effect["kind"] == "install_recipe" else
            self.runner.prepare(attempt, effect, job["execution"]["recipes"]))
        self._update(attempt, {"state": "running", "challenge": None,
                               "authorizationEpoch": epoch, "launch": preparation, "aptGateProof": None}, "launch_committed")
        if effect["kind"] == "install_recipe":
            self.runner.bind_launch(attempt, effect, preparation, self.journal.state["jobs"][attempt])
        self.challenges.pop(attempt, None)
        task = asyncio.create_task(self._run(attempt, effect, preparation))
        self.tasks[attempt] = task
        task.add_done_callback(lambda _: self.tasks.pop(attempt, None))
        return {"attemptId": attempt, "state": "running"}

    def accept_apt_gate(self, proof, peer_pid):
        fields(proof, {"format", "attemptId", "stepId", "unit", "planDigest", "transactionDigest",
                       "protocolDigest", "programDigest"})
        require(type(proof["format"]) is int and proof["format"] == 1, "FORBIDDEN")
        attempt = uuid(proof["attemptId"])
        require(self.journal.state["occupied"] == attempt, "FORBIDDEN")
        job = self.journal.state["jobs"][attempt]
        require(job["state"] == "running" and job.get("launch") is not None and
                job.get("aptGateProof") is None, "FORBIDDEN")
        effect = job["execution"]["effects"][job["stepIndex"]]
        facts = job["execution"].get("aptTransactions", {}).get(effect["id"])
        require(effect["kind"] == "install_recipe" and type(facts) is dict and
                proof["stepId"] == effect["id"] and proof["planDigest"] == job["planDigest"] and
                proof["unit"] == job["launch"]["unit"] and proof["programDigest"] == job["launch"]["programDigest"] and
                proof["transactionDigest"] == facts["transactionDigest"], "FORBIDDEN")
        sha(proof["protocolDigest"])
        from pathlib import Path
        require(Path(f"/proc/{peer_pid}/cgroup").read_text(encoding="ascii") ==
                "0::" + system_slice_cgroup() + "/" + proof["unit"] + "\n", "FORBIDDEN")
        # _update commits/fsyncs the authoritative journal before returning.
        self._update(attempt, {"aptGateProof": copy.deepcopy(proof)}, "apt_admitted")
        return {"gateAccepted": True, "attemptId": attempt, "stepId": effect["id"]}

    def is_apt_gate_peer(self, peer_pid):
        from pathlib import Path
        attempt = self.journal.state["occupied"]
        job = self.journal.state["jobs"].get(attempt)
        if job is None or job.get("launch") is None or job["state"] != "running":
            return False
        effect = job["execution"]["effects"][job["stepIndex"]]
        if effect["kind"] != "install_recipe":
            return False
        try:
            return Path(f"/proc/{peer_pid}/cgroup").read_text(encoding="ascii") == \
                "0::" + system_slice_cgroup() + "/" + job["launch"]["unit"] + "\n"
        except (OSError, Rejected):
            return False

    async def _run(self, attempt, effect, preparation):
        try:
            outcome = await self.runner.launch_committed(attempt, effect, preparation,
                apt_config="/etc/serverdeck-executor/apt.conf" if effect["kind"] == "install_recipe" else None)
            if outcome.state == "unknown":
                self._update(attempt, {"state": "unknown", "failureCode": outcome.code}, "uncertain", outcome.code)
                return
            self._update(attempt, {"launch": {**preparation,
                "completion": "succeeded" if outcome.code is None else "failed",
                "outputTruncated": outcome.output_truncated}}, "step_exited", outcome.code)
            job = self.journal.state["jobs"][attempt]
            try:
                checks, resources = await self._postcheck(job, effect)
            except Rejected as error:
                # Child/cgroup termination is proven. Health/probe failure
                # proves failure with effects, never a successful apply.
                self._update(attempt, {"state": "failed", "finishedAt": utc_now(),
                                       "failureCode": error.code, "launch": None},
                             "terminal", error.code, release=True)
                return
            job = self.journal.state["jobs"][attempt]
            if outcome.code is not None:
                self._update(attempt, {"state": "failed", "checks": checks, "finishedAt": utc_now(),
                                       "failureCode": outcome.code, "launch": None},
                             "terminal", outcome.code, release=True)
                return
            index = job["stepIndex"] + 1
            terminal = index == len(job["execution"]["effects"]) or job["stopRequested"]
            state = "cancelled-partial" if job["stopRequested"] else "succeeded" if terminal else "waiting"
            if state == "succeeded":
                require({check["id"] for check in job["execution"]["checks"]} ==
                        {check["checkId"] for check in checks if check.get("passed") is True}, "POSTCHECK_FAILED")
            self._update(attempt, {"state": state, "stepIndex": index, "launch": None,
                                   "checks": checks, "finishedAt": utc_now() if terminal else None},
                         "terminal" if terminal else "step_completed", release=terminal, resources=resources)
            if not terminal:
                started = self.waiting[attempt][0]
                self.waiting[attempt] = (started, time.monotonic())
        except Exception as error:
            # Any uncertainty after commitment keeps occupancy. Even a failed
            # postcheck must not lose the receipt or automatically run again.
            try:
                self._update(attempt, {"state": "unknown", "failureCode":
                    error.code if isinstance(error, Rejected) else "INTERNAL"}, "uncertain", "RECOVERY_REQUIRED")
            except Exception:
                self.journal.blocked = True

    def cancel(self, params, caller):
        fields(params, {"attemptId", "requestId"})
        request_id = uuid(params["requestId"])
        attempt = params["attemptId"]
        job = self._job(attempt, caller)
        requests = copy.deepcopy(job.get("cancelRequests", {}))
        if request_id in requests:
            return copy.deepcopy(requests[request_id])
        require(len(requests) < 128, "RESOURCE_LIMIT")
        if job["state"] not in ("queued", "waiting", "running", "unknown") or job["stopRequested"]:
            result = {"attemptId": attempt, "state": job["state"]}
            requests[request_id] = result
            self._update(attempt, {"cancelRequests": requests}, "cancel_recorded")
            return result
        patch = {"stopRequested": True, "challenge": None}
        release = job["launch"] is None
        if release:
            patch.update(state="cancelled-partial" if job["stepIndex"] else "cancelled", finishedAt=utc_now())
        result = {"attemptId": attempt, "state": patch.get("state", job["state"])}
        requests[request_id] = result
        patch["cancelRequests"] = requests
        self._update(attempt, patch, "cancel_requested", release=release)
        self.challenges.pop(attempt, None)
        return result

    async def reconcile(self, params, caller):
        fields(params, {"attemptId"})
        attempt = params["attemptId"]
        job = self._job(attempt, caller)
        if attempt in self.tasks:
            return {"attemptId": attempt, "state": job["state"],
                    "childrenStopped": False, "sequence": job["sequence"]}
        if job["launch"] is None:
            if job["state"] in ("queued", "waiting", "unknown"):
                state = "cancelled-partial" if job["stepIndex"] else "cancelled"
                self._update(attempt, {"state": state, "challenge": None,
                    "stopRequested": True, "finishedAt": utc_now()},
                    "terminal", "CANCELLED", release=True)
                self.challenges.pop(attempt, None)
            job = self._job(attempt, caller)
            return {"attemptId": attempt, "state": job["state"],
                    "childrenStopped": True, "sequence": job["sequence"]}
        require(attempt not in self.reconciling, "HOST_BUSY")
        self.reconciling.add(attempt)
        try:
            require(boot_id_hash() == job["execution"]["capsule"]["bootIdHash"], "UNKNOWN_OUTCOME")
            stopped = await asyncio.to_thread(self.runner.proven_stopped, job["launch"]["unit"])
            completion = job["launch"].get("completion")
            if stopped and completion is None:
                completion = await asyncio.to_thread(self.runner.recovered_completion, job["launch"]["unit"])
            if not stopped or completion not in ("succeeded", "failed"):
                return {"attemptId": attempt, "state": "unknown", "childrenStopped": stopped,
                        "sequence": self._job(attempt, caller)["sequence"]}
            effect = job["execution"]["effects"][job["stepIndex"]]
            checks, resources, failure = job["checks"], {}, "STEP_FAILED" if completion == "failed" else None
            if failure is None:
                try:
                    checks, resources = await self._postcheck(job, effect)
                except Rejected as error:
                    failure = error.code
            # Read/probe-only reconciliation may record a proved outcome; it
            # never authorizes a subsequent effect or invokes Ansible.
            job = self._job(attempt, caller)
            index = job["stepIndex"] + 1
            if failure is not None:
                state = "failed"
            elif job["stopRequested"]:
                state = "cancelled-partial"
            elif index < len(job["execution"]["effects"]):
                state = "cancelled-partial"
            else:
                expected = {check["id"] for check in job["execution"]["checks"]}
                passed = {check["checkId"] for check in checks if check.get("passed") is True}
                require(expected == passed, "UNKNOWN_OUTCOME")
                state = "succeeded"
            self._update(attempt, {"state": state, "stepIndex": index, "launch": None,
                                   "challenge": None, "checks": checks, "failureCode": failure,
                                   "finishedAt": utc_now()}, "terminal", failure, release=True, resources=resources)
            return {"attemptId": attempt, "state": state, "childrenStopped": True,
                    "sequence": self._job(attempt, caller)["sequence"]}
        finally:
            self.reconciling.discard(attempt)

    def detached(self, caller):
        for attempt, cached in list(self.challenges.items()):
            if cached[2] == caller.stream_id:
                self.challenges.pop(attempt, None)
                job = self.journal.state["jobs"][attempt]
                if job["challenge"] is not None:
                    self._update(attempt, {"challenge": None}, "session_lost")

    def tick(self):
        self._schedule_terminal_cleanup()
        for attempt, (started, waiting) in list(self.waiting.items()):
            job = self.journal.state["jobs"][attempt]
            if job["state"] not in ("queued", "waiting", "running", "unknown"):
                self.waiting.pop(attempt, None)
                continue
            if time.monotonic() - started >= 2 * 60 * 60:
                if job["launch"] is not None:
                    self._update(attempt, {"state": "unknown", "stopRequested": True,
                                           "failureCode": "TIMEOUT"}, "uncertain", "TIMEOUT")
                    self.waiting.pop(attempt, None)
                    continue
            elif job["state"] not in ("queued", "waiting") or time.monotonic() - waiting < 60:
                continue
            if job["launch"] is None:
                state = "cancelled-partial" if job["stepIndex"] else "cancelled"
                self._update(attempt, {"state": state, "stopRequested": True, "challenge": None,
                                       "finishedAt": utc_now()}, "terminal", "CANCELLED", release=True)
                self.challenges.pop(attempt, None)

    def _schedule_terminal_cleanup(self):
        if self.journal.blocked or self.cleanup_task is not None or self.runner.draining:
            return
        now = time.monotonic()
        for attempt, job in self.journal.state["jobs"].items():
            if attempt in self.cleaned_attempts or now < self.cleanup_retry_after.get(attempt, 0):
                continue
            if (job["state"] not in ("succeeded", "failed", "cancelled", "cancelled-partial") or
                    job.get("finishedAt") is None or self.journal.state["occupied"] == attempt or
                    attempt in self.tasks or attempt in self.reconciling):
                continue
            effects = copy.deepcopy(job["execution"]["effects"])
            self.cleanup_task = asyncio.create_task(self._cleanup_terminal(attempt, effects))
            return

    async def _cleanup_terminal(self, attempt, effects):
        actual = asyncio.create_task(asyncio.to_thread(self.runner.cleanup_terminal, attempt, effects))
        try:
            try:
                await asyncio.shield(actual)
            except asyncio.CancelledError:
                # Logical shutdown must not detach an actual filesystem owner.
                try:
                    await actual
                except Exception:
                    pass
                raise
            self.cleaned_attempts.add(attempt)
            self.cleanup_retry_after.pop(attempt, None)
        except Exception:
            # Cleanup is not a product effect or an outcome correction. Keep
            # immutable receipts and remaining private evidence; retry later.
            self.cleanup_retry_after[attempt] = time.monotonic() + 60
        finally:
            self.cleanup_task = None
