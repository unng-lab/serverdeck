"""Durable, owner-local job journal. No SSH or privileged executor is enabled.

Events are allowlisted summaries, never arbitrary Ansible stdout. This foundation
does not substitute for remote locks, privilege helper or disposable recipe tests.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import re
import sqlite3
from typing import Iterator
import uuid

CATALOG = {
    "postgresql": {"version": "18.6-3.pgdg24.04+1", "execution_enabled": False},
    "clickhouse": {"version": "26.8.17.4", "execution_enabled": False},
}
TERMINAL = {"succeeded", "failed", "cancelled"}
TRANSITIONS = {
    "queued": {"preflight", "cancelled"},
    "preflight": {"awaiting-approval", "failed", "cancelled"},
    "awaiting-approval": {"running", "cancelled"},
    "running": {"succeeded", "failed", "cancel-requested", "unknown"},
    "cancel-requested": {"unknown"},
    "unknown": {"reconciling"},
    "reconciling": {"succeeded", "failed", "cancelled", "unknown"},
    "succeeded": set(), "failed": set(), "cancelled": set(),
}


class Conflict(ValueError):
    """Conflicting input, illegal transition, or host already has a writer."""


class ExecutionDisabled(PermissionError):
    """Privileged recipe/helper/disposable acceptance gates have not passed."""


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


@dataclass(frozen=True)
class Plan:
    host_id: str
    host_fingerprint: str
    recipe: str
    version: str
    recipe_digest: str
    device_id: str
    mode: str = "fresh"

    def validate(self) -> None:
        for identifier in (self.host_id, self.device_id):
            if not re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", identifier):
                raise ValueError("Invalid local identifier")
        if "netbird" in self.recipe.lower() or self.recipe not in CATALOG:
            raise ValueError("Recipe is not allowlisted")
        if self.version != CATALOG[self.recipe]["version"]:
            raise ValueError("Exact catalog version required; no fallback")
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", self.recipe_digest):
            raise ValueError("Recipe must be bound to SHA256")
        if not re.fullmatch(r"SHA256:[a-zA-Z0-9+/]{43}", self.host_fingerprint):
            raise ValueError("Enrolled SSH fingerprint required")
        if self.mode != "fresh":
            raise ValueError("Adoption needs a separately verified preservation plan")


@dataclass(frozen=True)
class ProbeEvidence:
    version: str
    unit_active: bool
    application_healthy: bool
    execution_stopped: bool
    remote_lock_clear: bool


class JobStore:
    def __init__(self, path: Path | str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version not in {0, 1}:
            self.db.close()
            raise ValueError("Unsupported future job schema; no automatic reset")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                idempotency_key TEXT NOT NULL UNIQUE,
                input_json TEXT NOT NULL,
                input_hash TEXT NOT NULL,
                host_id TEXT NOT NULL,
                phase TEXT NOT NULL,
                container_id TEXT,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );
            CREATE TABLE IF NOT EXISTS host_locks (
                identity_key TEXT PRIMARY KEY,
                job_id TEXT NOT NULL UNIQUE REFERENCES jobs(id)
            );
            CREATE TABLE IF NOT EXISTS events (
                job_id TEXT NOT NULL REFERENCES jobs(id),
                sequence INTEGER NOT NULL,
                phase TEXT NOT NULL,
                code TEXT NOT NULL,
                evidence_json TEXT,
                at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
                PRIMARY KEY(job_id, sequence)
            );
            PRAGMA user_version=1;
        """)

    def close(self) -> None:
        self.db.close()

    @contextmanager
    def transaction(self) -> Iterator[None]:
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
        except BaseException:
            self.db.execute("ROLLBACK")
            raise
        else:
            self.db.execute("COMMIT")

    def _event(self, job_id: str, phase: str, code: str,
               evidence: ProbeEvidence | None = None) -> None:
        sequence = self.db.execute(
            "SELECT COALESCE(MAX(sequence),0)+1 FROM events WHERE job_id=?",
            (job_id,),
        ).fetchone()[0]
        self.db.execute(
            "INSERT INTO events(job_id,sequence,phase,code,evidence_json) VALUES(?,?,?,?,?)",
            (job_id, sequence, phase, code, canonical(asdict(evidence)) if evidence else None),
        )

    def get(self, job_id: str) -> dict:
        row = self.db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if row is None:
            raise KeyError(job_id)
        return dict(row)

    def events(self, job_id: str, after: int = 0, limit: int = 100) -> list[dict]:
        if after < 0 or limit < 1 or limit > 1000:
            raise ValueError("Invalid bounded event page")
        return [dict(row) for row in self.db.execute(
            "SELECT * FROM events WHERE job_id=? AND sequence>? ORDER BY sequence LIMIT ?",
            (job_id, after, limit),
        )]

    def submit(self, plan: Plan, idempotency_key: str) -> str:
        plan.validate()
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,128}", idempotency_key):
            raise ValueError("Invalid idempotency key")
        input_json = canonical(asdict(plan))
        digest = hashlib.sha256(input_json.encode()).hexdigest()
        with self.transaction():
            existing = self.db.execute(
                "SELECT id,input_hash FROM jobs WHERE idempotency_key=?", (idempotency_key,),
            ).fetchone()
            if existing:
                if existing["input_hash"] != digest:
                    raise Conflict("Idempotency key binds different input")
                return existing["id"]
            # Profile aliases cannot bypass the enrolled-key writer lock.
            if self.db.execute("SELECT 1 FROM host_locks WHERE identity_key=?", (plan.host_fingerprint,)).fetchone():
                raise Conflict("Host writer locked; reconciliation required")
            job_id = str(uuid.uuid4())
            self.db.execute(
                "INSERT INTO jobs(id,idempotency_key,input_json,input_hash,host_id,phase) VALUES(?,?,?,?,?,?)",
                (job_id, idempotency_key, input_json, digest, plan.host_id, "queued"),
            )
            self.db.execute("INSERT INTO host_locks VALUES(?,?)", (plan.host_fingerprint, job_id))
            self._event(job_id, "queued", "submitted")
            return job_id

    def _transition(self, job_id: str, target: str, code: str,
                    evidence: ProbeEvidence | None = None) -> None:
        job = self.get(job_id)
        if target not in TRANSITIONS[job["phase"]]:
            raise Conflict(f"Illegal phase: {job['phase']} -> {target}")
        self.db.execute("UPDATE jobs SET phase=? WHERE id=?", (target, job_id))
        self._event(job_id, target, code, evidence)
        if target in TERMINAL:
            self.db.execute("DELETE FROM host_locks WHERE job_id=?", (job_id,))

    def preflight(self, job_id: str) -> None:
        with self.transaction():
            self._transition(job_id, "preflight", "preflight-started")

    def reviewed(self, job_id: str) -> None:
        with self.transaction():
            self._transition(job_id, "awaiting-approval", "preflight-reviewed")

    def approve_and_launch(self, job_id: str) -> None:
        # No fixture UI, sync payload, environment flag or arbitrary caller can
        # enable this gate. Future approved helper/runner implementation replaces it.
        self.get(job_id)
        raise ExecutionDisabled("Privilege helper and disposable recipe tests pending")

    def request_cancel(self, job_id: str) -> None:
        with self.transaction():
            job = self.get(job_id)
            phase = job["phase"]
            if phase in TERMINAL or phase == "cancel-requested":
                return
            if phase in {"queued", "preflight", "awaiting-approval"}:
                self._transition(job_id, "cancelled", "cancelled-before-writes")
            elif phase == "running":
                self._transition(job_id, "cancel-requested", "stop-requested-no-rollback")
            else:
                raise Conflict("Unknown outcome must reconcile before cancellation")

    def lost_execution(self, job_id: str) -> None:
        with self.transaction():
            self._transition(job_id, "unknown", "execution-unobservable")

    def begin_reconcile(self, job_id: str) -> None:
        with self.transaction():
            self._transition(job_id, "reconciling", "reconciliation-started")

    def finish(self, job_id: str, evidence: ProbeEvidence) -> None:
        with self.transaction():
            job = self.get(job_id)
            if job["phase"] not in {"running", "reconciling"}:
                raise Conflict("Postconditions only settle running/reconciling jobs")
            if not evidence.execution_stopped or not evidence.remote_lock_clear:
                if job["phase"] == "reconciling":
                    self._transition(job_id, "unknown", "remote-outcome-uncertain", evidence)
                else:
                    self._transition(job_id, "unknown", "execution-unobservable", evidence)
                return
            plan = json.loads(job["input_json"])
            verified = evidence.version == plan["version"] and evidence.unit_active and evidence.application_healthy
            self._transition(job_id, "succeeded" if verified else "failed",
                             "postconditions-verified" if verified else "postconditions-failed", evidence)

    def confirm_cancelled(self, job_id: str, evidence: ProbeEvidence) -> None:
        with self.transaction():
            if self.get(job_id)["phase"] != "reconciling":
                raise Conflict("Cancellation requires reconciliation")
            if not evidence.execution_stopped or not evidence.remote_lock_clear:
                self._transition(job_id, "unknown", "cancel-outcome-uncertain", evidence)
            else:
                self._transition(job_id, "cancelled", "stopped-partial-effects-not-rolled-back", evidence)

    def unsettled(self) -> list[dict]:
        return [dict(row) for row in self.db.execute(
            "SELECT * FROM jobs WHERE phase IN ('running','cancel-requested','unknown','reconciling')"
        )]
