"""Ordered postcheck regressions, not Linux/SQL/Ansible acceptance.

The real compiler and postcheck method run against explicit probe doubles.
No root constructor, filesystem mutation, command or database is used.
"""
import copy
import hashlib
import sys
import types
import unittest
from unittest.mock import Mock, patch

from serverdeck_executor.compiler import ENVIRONMENT, compile_profile, render

# Windows lacks the Unix account module. It is not exercised by these tests;
# any accidental use fails rather than inventing a successful root probe.
if sys.platform == "win32":
    account_module = types.ModuleType("pwd")
    account_module.getpwnam = Mock(side_effect=AssertionError("UNIX_ACCOUNT_PROBE_FORBIDDEN"))
    with patch.dict(sys.modules, {"pwd": account_module}):
        from serverdeck_executor import preflight
else:
    from serverdeck_executor import preflight


class ActivationPostcheckTest(unittest.IsolatedAsyncioTestCase):
    async def verify_order(self, database, order):
        settings = database + ".settings"
        service = database + ".service"
        values = {"max_connections": 100,
                  "shared_buffers_mb" if database == "postgresql" else
                  "max_server_memory_usage_mb": 512}
        config = {"id": "config", "kind": "config_file",
                  "resourceId": settings, "values": values}
        manual = {"id": "manual", "kind": "service",
                  "resourceId": service, "state": "restarted", "enabled": True}
        steps = {"config-only": [config], "manual-before": [manual, config],
                 "manual-after": [config, manual]}[order]
        program = compile_profile({"format": 1, "environment": ENVIRONMENT,
                                   "parameters": {}, "steps": steps}, {},
                                  {settings: "a" * 64, service: "b" * 64}, {})
        model = {"values": {**values, "max_connections": 90},
                 "mainPid": 10, "startMonotonicUs": 10,
                 "activeState": "active", "unitFileState": "disabled"}
        observed_settings = []

        def observe(resource, qualifications):
            if resource == settings:
                observed_settings.append(copy.deepcopy(model["values"]))
                return {"values": copy.deepcopy(model["values"]),
                        "fileDigest": hashlib.sha256(render(settings, model["values"])).hexdigest()}
            self.assertEqual(resource, service)
            return {key: model[key] for key in
                    ("mainPid", "startMonotonicUs", "activeState", "unitFileState")}

        # Only the real postcheck algorithm is under test. The production
        # constructor's root custody/admission are deliberately not fabricated.
        subject = object.__new__(preflight.PreflightService)
        subject.runtime = types.SimpleNamespace(qualifications={})
        subject.journal = types.SimpleNamespace(state={"resources": {}})
        job = {"checks": [], "execution": {
            "effects": program.effects, "checks": program.checks,
            "observations": {service: {"mainPid": 10, "startMonotonicUs": 10}}}}
        effective = Mock(side_effect=lambda resource: copy.deepcopy(model["values"]))
        origin, sql = Mock(), Mock()
        with patch.multiple(preflight, observe=observe,
                            effective_settings=effective,
                            postgresql_origin=origin, sql_one=sql):
            for effect in program.effects:
                if effect["kind"] == "config_file":
                    model["values"] = copy.deepcopy(effect["values"])
                elif effect["kind"] == "service_state":
                    model["mainPid"] += 1
                    model["startMonotonicUs"] += 1
                elif effect["kind"] == "service_enabled":
                    model["unitFileState"] = "enabled"
                previous_reads = len(observed_settings)
                job["checks"] = await subject.postcheck(job, effect)
                ids = [row["checkId"] for row in job["checks"]]
                self.assertEqual(len(ids), len(set(ids)), "each check is reported once")
                if effect["sourceStepId"] == "manual":
                    self.assertEqual(len(observed_settings), previous_reads,
                                     "manual restart must not probe a future or completed config")
        self.assertEqual({row["id"] for row in program.checks},
                         {row["checkId"] for row in job["checks"]})
        self.assertTrue(all(row["passed"] is True for row in job["checks"]))
        effective.assert_called_once_with(settings)
        if database == "postgresql":
            origin.assert_called_once_with(require_managed=True)
        else:
            origin.assert_not_called()
        self.assertEqual(sql.call_count, 1 if order == "config-only" else 2)

    async def test_config_check_waits_for_its_derived_activation(self):
        for database in ("postgresql", "clickhouse"):
            with self.subTest(database=database):
                await self.verify_order(database, "config-only")

    async def test_explicit_restart_does_not_check_future_config(self):
        for database in ("postgresql", "clickhouse"):
            with self.subTest(database=database):
                await self.verify_order(database, "manual-before")

    async def test_explicit_restart_does_not_duplicate_completed_config_check(self):
        for database in ("postgresql", "clickhouse"):
            with self.subTest(database=database):
                await self.verify_order(database, "manual-after")


if __name__ == "__main__":
    unittest.main()
