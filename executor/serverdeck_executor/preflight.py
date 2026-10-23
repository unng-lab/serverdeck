"""Pure root preflight and immutable full-evidence admission for format1."""

import asyncio
import copy
import datetime
import hashlib
import time
from dataclasses import dataclass
from pathlib import Path

from .codec import Rejected, canonical, digest, fields, require, sha, uuid, wire_bytes
from .compiler import ENVIRONMENT, UNITS, compile_profile, compiler_digest, resolve
from .jobs import utc_now
from .journal import atomic_document, secure_directory
from .probes import (boot_id_hash, effective_settings, observe, package_snapshot,
                     netbird_preservation_digest, protected_package, regular_file, sql_one)
from .qualification import postgresql_origin, validate_database, verify_recipe_install
from .apt import probe_recipes
from .apt_gate import hash_file


@dataclass(frozen=True)
class RootRuntime:
    # Constructed by root startup after file custody/release/runtime validation.
    # Not deserializable as a caller-provided "qualified" flag.
    host_id: str
    version: str
    lock_digest: str
    registry_digest: str
    qualifications: dict
    recipes: dict
    bridge_digest: str


def capture_target(raw, caller):
    fields(raw, {"workspaceId", "serverId", "targetRevision", "connectionRevision", "accessRevision", "trustRevision"})
    uuid(raw["workspaceId"])
    uuid(raw["serverId"])
    require(raw["workspaceId"] == caller.workspace_id, "FORBIDDEN")
    for key in ("targetRevision", "connectionRevision", "accessRevision", "trustRevision"):
        value = raw[key]
        require(type(value) is str and value.isascii() and value.isdecimal() and
                not value.startswith("0") and len(value) <= 19 and
                1 <= int(value) <= 9223372036854775807)
    require(int(raw["connectionRevision"]) <= int(raw["trustRevision"]) <= int(raw["targetRevision"]) and
            int(raw["accessRevision"]) <= int(raw["targetRevision"]))
    return copy.deepcopy(raw)


def observation_fingerprint(target, runtime, resource, value):
    return digest({**target, "resourceId": resource, "hostId": runtime.host_id,
                   "resourceRegistryDigest": runtime.registry_digest, "value": value})


class PreflightService:
    def __init__(self, runtime, journal):
        self.runtime = runtime
        self.journal = journal
        self.cache = secure_directory(journal.directory / "preflight")
        self.operations = {}
        self.closed = False
        self._load_cache()

    def qualifications(self):
        result = dict(self.runtime.qualifications)
        for resource, binding in self.journal.state.get("resources", {}).items():
            if (binding["hostId"] == self.runtime.host_id and
                    binding["registryDigest"] == self.runtime.registry_digest and
                    binding["runtimeVersion"] == self.runtime.version):
                result[resource] = binding["baselineDigest"]
        return result

    def _load_cache(self):
        from .codec import decode
        directories = list(self.cache.iterdir())
        require(len(directories) <= 128, "RESOURCE_LIMIT")
        for path in directories:
            uuid(path.name)
            secure_directory(path)
            require({item.name for item in path.iterdir()} == {"snapshot.json"}, "RECOVERY_REQUIRED")
            data, attributes = regular_file(path / "snapshot.json", maximum=8 * 1024 * 1024)
            require(attributes["mode"] == 0o600, "RECOVERY_REQUIRED")
            envelope = decode(data, 8 * 1024 * 1024)
            fields(envelope, {"document", "checksum"})
            document = envelope["document"]
            require(digest(document) == envelope["checksum"], "RECOVERY_REQUIRED")
            fields(document, {"format", "hostId", "operationId", "expiresAt", "owner", "input", "facts", "requestDigest"})
            require(document["format"] == 1 and document["hostId"] == self.runtime.host_id and
                    document["operationId"] == path.name, "RECOVERY_REQUIRED")
            expires = datetime.datetime.fromisoformat(document["expiresAt"].replace("Z", "+00:00"))
            remaining = (expires - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
            require(remaining <= 300, "RECOVERY_REQUIRED")
            if remaining <= 0:
                # Exact closed, validated files only. No recursive cleanup and
                # no active/unknown job evidence is touched by cache expiry.
                (path / "snapshot.json").unlink()
                path.rmdir()
                continue
            facts = document["facts"]
            require(type(facts) is dict and type(facts.get("capsule")) is dict, "RECOVERY_REQUIRED")
            capsule = facts["capsule"]
            if (capsule.get("registryDigest") != self.runtime.registry_digest or
                    capsule.get("runtimeVersion") != self.runtime.version or
                    capsule.get("runtimeLockDigest") != self.runtime.lock_digest or
                    capsule.get("compilerDigest") != compiler_digest()):
                # Only this validated pure preflight cache is obsolete. Admitted
                # jobs already contain a full durable copy of all evidence; no
                # occupied/unknown receipt or job work file is removed here.
                (path / "snapshot.json").unlink()
                path.rmdir()
                continue
            require(len(self.operations) < 16, "RESOURCE_LIMIT")
            fingerprint = digest(facts["capsule"])
            self.operations[path.name] = {"input": document["input"], "requestDigest": document["requestDigest"],
                "owner": tuple(document["owner"]), "done": True, "expires": time.monotonic() + remaining,
                "result": self._public_facts(facts, fingerprint),
                "code": None, "facts": facts, "digest": fingerprint, "task": None,
                "expiresWall": document["expiresAt"]}

    def _persist(self, entry):
        operation = entry["input"]["operationId"]
        path = self.cache / operation
        path.mkdir(mode=0o700)
        secure_directory(path)
        document = {"format": 1, "hostId": self.runtime.host_id, "operationId": operation,
                    "expiresAt": entry["expiresWall"], "owner": list(entry["owner"]),
                    "input": entry["input"], "facts": entry["facts"], "requestDigest": entry["requestDigest"]}
        envelope = {"document": document, "checksum": digest(document)}
        self.journal._space(len(wire_bytes(envelope)))
        atomic_document(path, "snapshot.json", envelope)

    def _sweep(self):
        now = time.monotonic()
        for operation, entry in list(self.operations.items()):
            if entry["done"] and entry["expires"] <= now:
                path = self.cache / operation
                if path.exists():
                    secure_directory(path)
                    require({item.name for item in path.iterdir()} == {"snapshot.json"}, "RECOVERY_REQUIRED")
                    (path / "snapshot.json").unlink()
                    path.rmdir()
                self.operations.pop(operation, None)

    def start(self, params, caller):
        fields(params, {"operationId", "profileBody", "profileDigest", "parameters", "expectedHostId", "target"})
        require(not self.closed, "EXECUTOR_UNAVAILABLE")
        operation = uuid(params["operationId"])
        require(params["expectedHostId"] == self.runtime.host_id, "TRUST_CHANGED")
        sha(params["profileDigest"])
        require(digest(params["profileBody"]) == params["profileDigest"], "CONFLICT")
        captured = copy.deepcopy(params)
        captured["target"] = capture_target(params["target"], caller)
        parameters, desired = resolve(captured["profileBody"], captured["parameters"])
        captured["parameters"] = parameters
        request = digest(captured)
        self._sweep()
        entry = self.operations.get(operation)
        if entry is not None:
            self._owner(entry, caller)
            require(entry["requestDigest"] == request, "CONFLICT")
            return {"operationId": operation, "state": "running" if not entry["done"] else "completed"}
        require(len(self.operations) < 16, "RESOURCE_LIMIT")
        entry = {"input": captured, "requestDigest": request, "owner":
                 (caller.uid, caller.controller_id, caller.workspace_id), "done": False,
                 "expires": time.monotonic() + 300, "result": None, "code": None,
                 "facts": None, "digest": None, "task": None}
        entry["expiresWall"] = (datetime.datetime.now(datetime.timezone.utc) +
            datetime.timedelta(seconds=300)).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        self.operations[operation] = entry
        entry["task"] = asyncio.create_task(self._run(entry, desired))
        return {"operationId": operation, "state": "running"}

    @staticmethod
    def _owner(entry, caller):
        require(entry["owner"] == (caller.uid, caller.controller_id, caller.workspace_id), "FORBIDDEN")

    def get(self, params, caller):
        fields(params, {"operationId"})
        self._sweep()
        entry = self.operations.get(uuid(params["operationId"]))
        require(entry is not None, "NOT_FOUND")
        self._owner(entry, caller)
        if entry["code"] is not None:
            return {"operationId": params["operationId"], "state": "failed", "code": entry["code"],
                    "field": entry.get("field") or "executor"}
        if not entry["done"]:
            return {"operationId": params["operationId"], "state": "running"}
        return {"operationId": params["operationId"], "state": "succeeded", "result": copy.deepcopy(entry["result"])}

    def _probe(self, captured, desired):
        qualifications = self.qualifications()
        resources, recipes, install_steps = set(), {}, []
        for step in desired:
            if step["kind"] == "install_recipe":
                recipe = self.runtime.recipes.get(step["recipeDigest"])
                if type(recipe) is not dict or recipe["version"] != step["version"]:
                    raise Rejected("QUALIFICATION_REQUIRED", field="recipe")
                recipes[step["recipeDigest"]] = recipe
                install_steps.append(step)
                continue
            resource = step["resourceId"]
            if resource.endswith(".settings"):
                validate_database(resource, step["values"], qualifications)
            resources.add(resource)
            if resource.endswith(".settings"):
                resources.add(resource.replace(".settings", ".service"))
        protected_netbird = netbird_preservation_digest() if install_steps else None
        apt = probe_recipes([step["recipeDigest"] for step in install_steps],
                            self.runtime.registry_digest) if install_steps else None
        packages = apt["packages"] if apt else package_snapshot()
        observations, observation_times = {}, {}
        for resource in sorted(resources):
            observations[resource] = observe(resource, qualifications)
            observation_times[resource] = utc_now()
        fingerprints = {resource: observation_fingerprint(captured["target"], self.runtime, resource, value)
                        for resource, value in observations.items()}
        compiled = compile_profile(captured["profileBody"], captured["parameters"], fingerprints, recipes)
        transactions = {}
        if apt:
            pending = iter(apt["transactions"])
            for effect in compiled.effects:
                if effect["kind"] != "install_recipe":
                    continue
                transaction = next(pending)
                require(transaction["recipeDigest"] == effect["recipeDigest"], "CONFLICT")
                transactions[effect["id"]] = transaction
            require(next(pending, None) is None, "CONFLICT")
        require(package_snapshot() == packages, "CONFLICT")
        if protected_netbird is not None:
            require(netbird_preservation_digest() == protected_netbird, "CONFLICT")
        snapshot = digest(packages)
        capsule = {"format": 1, "operationId": captured["operationId"], "hostId": self.runtime.host_id,
                   "environment": ENVIRONMENT, "profileDigest": captured["profileDigest"],
                   "inputDigest": digest(compiled.parameters), "runtimeVersion": self.runtime.version,
                   "runtimeLockDigest": self.runtime.lock_digest, "compilerDigest": compiler_digest(),
                   "registryDigest": self.runtime.registry_digest, "bootIdHash": boot_id_hash(),
                   "packageSnapshotDigest": snapshot,
                   "expectedPackageSnapshotDigest": digest(apt["expectedPackages"]) if apt else snapshot,
                   "netbirdSnapshotDigest": digest([row for row in packages if protected_package(row[0])]),
                   "aptIndexDigests": sorted({value for recipe in recipes.values()
                                              for value in recipe["aptIndexDigests"]}),
                   "recipes": list(recipes.values()), "baseObservations":
                   [{"resourceId": resource, "fingerprint": value} for resource, value in fingerprints.items()]}
        require(len(canonical(capsule)) <= 256 * 1024, "RESOURCE_LIMIT")
        facts = {"target": captured["target"], "packages": packages, "observations": observations,
                 "observationTimes": observation_times,
                 "capsule": capsule, "parameters": compiled.parameters, "desired": compiled.desired,
                 "effects": compiled.effects, "checks": compiled.checks, "recipes": recipes,
                 "aptTransactions": transactions, "netbirdPreservationDigest": protected_netbird,
                 "observedAt": utc_now()}
        return facts

    async def _run(self, entry, desired):
        task = asyncio.create_task(asyncio.to_thread(self._probe, entry["input"], desired))
        try:
            # Late native subprocess/probe completion remains charged to this
            # operation even after its logical 30-second result times out.
            try:
                facts = await asyncio.wait_for(asyncio.shield(task), timeout=30)
            except asyncio.TimeoutError:
                entry["code"] = "TIMEOUT"
                try:
                    await task
                except Exception:
                    pass
                return
            entry["facts"], entry["digest"] = facts, digest(facts["capsule"])
            self._persist(entry)
            entry["result"] = self._public_facts(facts, entry["digest"])
        except Exception as error:
            entry["code"] = error.code if isinstance(error, Rejected) else "PREFLIGHT_FAILED"
            entry["field"] = error.field if isinstance(error, Rejected) else None
        finally:
            entry["done"] = True

    def _public_facts(self, facts, fingerprint):
        return {"planFacts": facts["capsule"], "digest": fingerprint,
                "effects": facts["effects"], "checks": facts["checks"], "reasons": [],
                "observations": [{**facts["target"], "resourceId": resource,
                    "hostId": self.runtime.host_id, "resourceRegistryDigest": self.runtime.registry_digest,
                    "observedAt": facts["observationTimes"][resource], "status": "known", "value": value}
                    for resource, value in facts["observations"].items()]}

    async def admit(self, params, caller):
        require(not self.closed, "EXECUTOR_UNAVAILABLE")
        self._sweep()
        matches = [entry for entry in self.operations.values() if entry["digest"] == params["preflightDigest"]]
        require(len(matches) == 1, "PREFLIGHT_FAILED")
        entry = matches[0]
        self._owner(entry, caller)
        require(entry["done"] and entry["code"] is None and time.monotonic() < entry["expires"], "PREFLIGHT_FAILED")
        captured = entry["input"]
        require(params["profileDigest"] == captured["profileDigest"] and
                digest(params["profileBody"]) == params["profileDigest"] and
                digest(params["parameters"]) == digest(captured["parameters"]), "CONFLICT")
        facts = copy.deepcopy(entry["facts"])
        require(facts["target"]["workspaceId"] == caller.workspace_id, "FORBIDDEN")
        await self.revalidate({"execution": facts, "stepIndex": 0})
        return facts

    async def revalidate(self, job):
        facts = job["execution"]

        def probe():
            qualifications = self.qualifications()
            require(boot_id_hash() == facts["capsule"]["bootIdHash"], "TRUST_CHANGED")
            if facts["recipes"]:
                require(netbird_preservation_digest() == facts["netbirdPreservationDigest"], "CONFLICT")
            expected_packages = facts["packages"]
            for effect in facts["effects"][:job["stepIndex"]]:
                if effect["kind"] == "install_recipe":
                    expected_packages = facts["aptTransactions"][effect["id"]]["expectedPackages"]
            require(package_snapshot() == expected_packages, "CONFLICT")
            current = facts["effects"][job["stepIndex"]] if job["stepIndex"] < len(facts["effects"]) else None
            if current is not None:
                source = next(step for step in facts["desired"] if step["id"] == current["sourceStepId"])
                if source["kind"] == "install_recipe":
                    transaction = facts["aptTransactions"][current["id"]]
                    require(transaction["packages"] == expected_packages, "CONFLICT")
                    for row in transaction["files"]:
                        require(hash_file(row["path"]) == row, "CONFLICT")
                    import os
                    recipe = facts["recipes"][source["recipeDigest"]]
                    require(all(not os.path.lexists(path) for path in recipe["expectedAbsentPaths"]), "CONFLICT")
                if source["kind"] == "config_file" and source["resourceId"].endswith(".settings"):
                    validate_database(source["resourceId"], source["values"], qualifications)
            # Revalidate resources that earlier committed effects have not
            # deliberately changed. Completed-step postchecks bind owned values.
            previous = facts["effects"][:job["stepIndex"]]
            modified = {effect.get("resourceId") for effect in previous}
            for resource, baseline in facts["observations"].items():
                current = observe(resource, qualifications)
                if resource not in modified:
                    require(current == baseline, "CONFLICT")
                else:
                    require(current["baselineDigest"] == baseline["baselineDigest"], "CONFLICT")
        await asyncio.to_thread(probe)

    async def postcheck(self, job, effect):
        facts = job["execution"]

        def probe():
            qualifications = self.qualifications()
            resource = effect["resourceId"]
            value = observe(resource, qualifications)
            results = copy.deepcopy(job["checks"])
            checks = [check for check in facts["checks"] if check["effectId"] == effect["id"]]
            for check in checks:
                kind = check["kind"]
                if kind == "file_digest":
                    require(value["fileDigest"] == check["digest"], "POSTCHECK_FAILED")
                elif kind == "settings":
                    # Settings are validated after their derived activation,
                    # never inferred effective merely from a file write.
                    continue
                elif kind == "service_state":
                    require(value["activeState"] == check["state"], "POSTCHECK_FAILED")
                elif kind == "service_enabled":
                    require(value["unitFileState"] == ("enabled" if check["enabled"] else "disabled"), "POSTCHECK_FAILED")
                elif kind == "service_restarted":
                    before = facts["observations"][resource]
                    require(value["mainPid"] > 0 and
                            (value["mainPid"], value["startMonotonicUs"]) !=
                            (before["mainPid"], before["startMonotonicUs"]), "POSTCHECK_FAILED")
                elif kind == "sql":
                    sql_one(resource)
                else:
                    raise Rejected("POSTCHECK_FAILED")
                results.append({"checkId": check["id"], "passed": True})
            if effect["kind"] == "service_state" and effect["state"] == "restarted":
                # Only the derived activation of this exact configuration
                # source step can complete its deferred settings check. A
                # separate service step may precede or follow the configuration.
                activated = {item["id"] for item in facts["effects"]
                             if item["kind"] == "config_file" and
                             item["sourceStepId"] == effect["sourceStepId"] and
                             item["resourceId"].replace(".settings", ".service") == resource}
                for check in facts["checks"]:
                    if check["kind"] == "settings" and check["effectId"] in activated:
                        current = observe(check["resourceId"], qualifications)
                        require(current["values"] == check["values"], "POSTCHECK_FAILED")
                        require(effective_settings(check["resourceId"]) == check["values"], "POSTCHECK_FAILED")
                        if check["resourceId"] == "postgresql.settings":
                            postgresql_origin(require_managed=True)
                        results.append({"checkId": check["id"], "passed": True})
            return results
        return await asyncio.to_thread(probe)

    async def postcheck_recipe(self, job, effect):
        def probe():
            require(effect["kind"] == "install_recipe", "POSTCHECK_FAILED")
            facts = job["execution"]
            require(facts["capsule"]["runtimeVersion"] == self.runtime.version and
                    facts["capsule"]["registryDigest"] == self.runtime.registry_digest,
                    "QUALIFICATION_REQUIRED")
            transaction = facts["aptTransactions"][effect["id"]]
            proof, launch = job.get("aptGateProof"), job.get("launch")
            require(type(proof) is dict and type(launch) is dict and
                    proof["attemptId"] == job["attemptId"] and proof["stepId"] == effect["id"] and
                    proof["planDigest"] == job["planDigest"] and proof["unit"] == launch["unit"] and
                    proof["programDigest"] == launch["programDigest"] and
                    proof["transactionDigest"] == transaction["transactionDigest"], "POSTCHECK_FAILED")
            require(boot_id_hash() == facts["capsule"]["bootIdHash"], "TRUST_CHANGED")
            recipe = facts["recipes"][effect["recipeDigest"]]
            require(transaction["recipeDigest"] == recipe["digest"] and recipe["version"] == effect["version"],
                    "POSTCHECK_FAILED")
            baselines = verify_recipe_install(recipe, transaction["expectedPackages"])
            require(netbird_preservation_digest() == facts["netbirdPreservationDigest"], "POSTCHECK_FAILED")
            require(digest([row for row in transaction["expectedPackages"]
                            if protected_package(row[0])]) == facts["capsule"]["netbirdSnapshotDigest"],
                    "POSTCHECK_FAILED")
            checks = [check for check in facts["checks"] if check["effectId"] == effect["id"]]
            require(len(checks) == 1 and checks[0]["kind"] == "recipe" and
                    checks[0]["recipeDigest"] == recipe["digest"], "POSTCHECK_FAILED")
            results = copy.deepcopy(job["checks"]) + [{"checkId": checks[0]["id"], "passed": True}]
            at = utc_now()
            bindings = {resource: {"format": 1, "hostId": self.runtime.host_id, "resourceId": resource,
                "recipeDigest": recipe["digest"], "registryDigest": facts["capsule"]["registryDigest"],
                "runtimeVersion": facts["capsule"]["runtimeVersion"], "sourceAttemptId": job["attemptId"],
                "sourceEffectId": effect["id"], "baselineDigest": baseline, "confirmedAt": at}
                for resource, baseline in baselines.items()}
            return results, bindings
        return await asyncio.to_thread(probe)

    async def close(self):
        self.closed = True
        await asyncio.gather(*(entry["task"] for entry in self.operations.values()
                               if entry["task"] is not None), return_exceptions=True)
