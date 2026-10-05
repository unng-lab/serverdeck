from dataclasses import replace
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest

from runner.jobs import Conflict, ExecutionDisabled, JobStore, Plan, ProbeEvidence


class JobTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "jobs.sqlite"
        self.store = JobStore(self.path)
        self.plan = Plan(host_id="disposable-a", host_fingerprint="SHA256:" + "A" * 43,
                         recipe="postgresql", version="18.6-3.pgdg24.04+1",
                         recipe_digest="sha256:" + "a" * 64, device_id="local-test")

    def tearDown(self):
        self.store.close()
        self.directory.cleanup()

    def running_fixture(self):
        # Inject a historical in-flight record to test recovery. Production launch
        # API remains disabled; no command/SSH/Ansible/host mutation is performed.
        job = self.store.submit(self.plan, "run-fixture")
        self.store.preflight(job)
        self.store.reviewed(job)
        with self.store.transaction():
            self.store._transition(job, "running", "fixture-running")
            self.store.db.execute("UPDATE jobs SET container_id=? WHERE id=?", ("fixture-container", job))
        return job

    def evidence(self, **changes):
        return replace(ProbeEvidence(self.plan.version, True, True, True, True), **changes)

    def test_duplicate_returns_same_job_and_no_extra_event(self):
        job = self.store.submit(self.plan, "duplicate")
        self.assertEqual(job, self.store.submit(self.plan, "duplicate"))
        self.assertEqual(1, len(self.store.events(job)))
        with self.assertRaises(Conflict):
            self.store.submit(replace(self.plan, host_id="disposable-b"), "duplicate")

    def test_host_lock_survives_reopen_and_terminal_releases(self):
        job = self.store.submit(self.plan, "first")
        self.store.close()
        self.store = JobStore(self.path)
        with self.assertRaises(Conflict):
            self.store.submit(self.plan, "second")
        self.store.request_cancel(job)
        self.assertNotEqual(job, self.store.submit(self.plan, "second"))

    def test_profile_alias_cannot_bypass_enrolled_identity_writer_lock(self):
        self.store.submit(self.plan, "first-alias")
        with self.assertRaises(Conflict):
            self.store.submit(replace(self.plan, host_id="same-host-other-profile"), "second-alias")

    def test_restart_retains_running_container_identity_and_requires_reconcile(self):
        job = self.running_fixture()
        self.store.close()
        self.store = JobStore(self.path)
        self.assertEqual("fixture-container", self.store.unsettled()[0]["container_id"])
        self.store.lost_execution(job)
        with self.assertRaises(Conflict):
            self.store.submit(self.plan, "retry")
        self.store.begin_reconcile(job)
        self.store.finish(job, self.evidence(execution_stopped=False))
        self.assertEqual("unknown", self.store.get(job)["phase"])
        self.store.begin_reconcile(job)
        self.store.finish(job, self.evidence())
        self.assertEqual("succeeded", self.store.get(job)["phase"])

    def test_failed_probe_cannot_report_success(self):
        job = self.running_fixture()
        self.store.finish(job, self.evidence(application_healthy=False))
        self.assertEqual("failed", self.store.get(job)["phase"])

    def test_cancel_is_request_then_reconciled_not_rollback(self):
        job = self.running_fixture()
        self.store.request_cancel(job)
        self.store.request_cancel(job)
        self.assertEqual("cancel-requested", self.store.get(job)["phase"])
        self.store.lost_execution(job)
        self.store.begin_reconcile(job)
        self.store.confirm_cancelled(job, self.evidence(remote_lock_clear=False))
        self.assertEqual("unknown", self.store.get(job)["phase"])
        self.store.begin_reconcile(job)
        self.store.confirm_cancelled(job, self.evidence())
        self.assertEqual("cancelled", self.store.get(job)["phase"])
        self.assertIn("not-rolled-back", self.store.events(job)[-1]["code"])

    def test_gate_denies_actual_launch_and_preserves_phase(self):
        job = self.store.submit(self.plan, "gate")
        self.store.preflight(job)
        self.store.reviewed(job)
        with self.assertRaises(ExecutionDisabled):
            self.store.approve_and_launch(job)
        self.assertEqual("awaiting-approval", self.store.get(job)["phase"])

    def test_invalid_recipe_version_and_parameters_fail_closed(self):
        for plan in [replace(self.plan, recipe="netbird"), replace(self.plan, version="latest"),
                     replace(self.plan, host_id="host; rm -rf /"), replace(self.plan, mode="adopt"),
                     replace(self.plan, recipe_digest="missing"), replace(self.plan, host_fingerprint="unknown")]:
            with self.assertRaises(ValueError):
                self.store.submit(plan, "bad")

    def test_events_are_bounded_sequenced_and_resumeable(self):
        job = self.store.submit(self.plan, "events")
        self.store.preflight(job)
        self.store.reviewed(job)
        events = self.store.events(job, after=1, limit=1)
        self.assertEqual([2], [event["sequence"] for event in events])
        self.assertNotIn("stdout", events[0])
        with self.assertRaises(ValueError):
            self.store.events(job, limit=1001)

    def test_atomic_rollback_has_no_orphan_lock(self):
        with self.assertRaises(sqlite3.IntegrityError):
            with self.store.transaction():
                self.store.db.execute("INSERT INTO host_locks VALUES('orphan','missing')")
        self.assertEqual(0, self.store.db.execute("SELECT COUNT(*) FROM host_locks").fetchone()[0])

    def test_two_connections_racing_only_one_host_writer(self):
        barrier = threading.Barrier(2)
        results = []
        def submit(key):
            store = JobStore(self.path)
            try:
                barrier.wait(timeout=5)
                try:
                    store.submit(self.plan, key)
                    results.append("claimed")
                except Conflict:
                    results.append("blocked")
            finally:
                store.close()
        workers = [threading.Thread(target=submit, args=(f"writer-{i}",)) for i in range(2)]
        for worker in workers: worker.start()
        for worker in workers: worker.join(timeout=10)
        self.assertEqual(["blocked", "claimed"], sorted(results))


if __name__ == "__main__":
    unittest.main()
