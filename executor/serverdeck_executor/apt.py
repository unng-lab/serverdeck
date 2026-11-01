"""Read-only isolated python3-apt resolver and root prepared recipe catalog.

No update(), fetch_archives(), commit() or package-manager write occurs here.
The descriptor is resolved from root resources.json; no caller supplied catalog
or "qualified" flag is accepted. Full package/index/config evidence is retained
privately for the one-use native-lock transaction gate.
"""

import datetime
from email.utils import parsedate_to_datetime
import hashlib
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

from .apt_gate import CONFIG, GATE, KEYRING, NO_START, hash_file
from .codec import Rejected, decode, digest, fields, integer, require, sha, text, wire_bytes
from .probes import command, package_snapshot, protected_package, regular_file

ABSENT = {"postgresql16": {"/etc/postgresql/16/main", "/var/lib/postgresql/16/main"},
          "clickhouse": {"/etc/clickhouse-server", "/var/lib/clickhouse"}}
PRIMARY = {"postgresql16": {"postgresql-16", "postgresql-client-16"},
           "clickhouse": {"clickhouse-server", "clickhouse-client", "clickhouse-common-static"}}
LAUNCHER = b'''#!/usr/bin/python3 -I
import sys
sys.path.insert(0, "/usr/lib/serverdeck-executor")
from serverdeck_executor.apt import main
main()
'''
APT_CONFIG = ('''Dir::Etc::parts "-";
Dir::Etc::main "-";
Dir::Etc::sourcelist "/etc/serverdeck-executor/sources.list";
Dir::Etc::sourceparts "-";
Dir::Etc::trusted "/etc/apt/keyrings/serverdeck-executor.gpg";
Dir::Etc::trustedparts "-";
Dir::State::lists "/var/lib/apt/lists";
Dir::Cache::archives "/var/cache/apt/archives";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
APT::Architecture "amd64";
APT::Architectures { "amd64"; };
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::AllowUnauthenticated "false";
APT::Get::allow-downgrades "false";
APT::Get::allow-change-held-packages "false";
Acquire::AllowInsecureRepositories "false";
Acquire::AllowDowngradeToInsecureRepositories "false";
Acquire::Retries "0";
DPkg::Lock::Timeout "1";
#clear DPkg::Pre-Invoke;
#clear DPkg::Post-Invoke;
#clear DPkg::Pre-Install-Pkgs;
DPkg::Pre-Install-Pkgs { "/usr/libexec/serverdeck-apt-transaction-gate"; };
DPkg::Tools::Options::/usr/libexec/serverdeck-apt-transaction-gate::Version "3";
DPkg::Tools::Options::/usr/libexec/serverdeck-apt-transaction-gate::InfoFD "0";
''').encode("ascii")


def transaction_digest(pins):
    return digest({"additions": sorted(pins, key=lambda row: (row["name"], row["architecture"])),
                   "configureNew": sorted(f"{row['name']}:{row['architecture']}" for row in pins)})


def validate_catalog(catalog):
    require(type(catalog) is dict and len(catalog) <= 2, "QUALIFICATION_REQUIRED")
    ids = set()
    for key, recipe in catalog.items():
        sha(key)
        fields(recipe, {"format", "id", "version", "revision", "digest", "environment", "packagePins",
            "dependencyTransactionDigest", "repositoryFingerprints", "aptIndexDigests", "expectedAbsentPaths",
            "ownedResources", "prechecks", "postchecks", "licenseNotices", "initialSettings"})
        require(type(recipe["format"]) is int and recipe["format"] == 1 and recipe["environment"] == "ubuntu24.04-amd64-systemd" and
                recipe["id"] in PRIMARY and recipe["id"] not in ids, "QUALIFICATION_REQUIRED")
        ids.add(recipe["id"])
        text(recipe["version"], 1, 256, public=True)
        require(recipe["version"].lower() != "latest", "QUALIFICATION_REQUIRED")
        integer(recipe["revision"], 1, 2147483647)
        require(recipe["digest"] == key and digest({name: value for name, value in recipe.items()
                    if name != "digest"}) == key, "QUALIFICATION_REQUIRED")
        pins = recipe["packagePins"]
        require(type(pins) is list and 1 <= len(pins) <= 256, "QUALIFICATION_REQUIRED")
        seen = set()
        for pin in pins:
            fields(pin, {"name", "architecture", "version", "sha256"})
            require(type(pin["name"]) is str and re.fullmatch(r"[a-z0-9][a-z0-9+.-]{0,127}", pin["name"]) and
                    pin["architecture"] in ("amd64", "all") and type(pin["version"]) is str and
                    re.fullmatch(r"[A-Za-z0-9.+:~\-]{1,256}", pin["version"]) and
                    not protected_package(pin["name"]) and (pin["name"], pin["architecture"]) not in seen,
                    "QUALIFICATION_REQUIRED")
            seen.add((pin["name"], pin["architecture"]))
            sha(pin["sha256"])
        require(PRIMARY[recipe["id"]] <= {pin["name"] for pin in pins} and all(
            pin["version"] == recipe["version"] for pin in pins if pin["name"] in PRIMARY[recipe["id"]]),
            "QUALIFICATION_REQUIRED")
        require(recipe["dependencyTransactionDigest"] == transaction_digest(pins), "QUALIFICATION_REQUIRED")
        require(type(recipe["repositoryFingerprints"]) is list and 1 <= len(recipe["repositoryFingerprints"]) <= 16,
                "QUALIFICATION_REQUIRED")
        require(all(type(value) is str and re.fullmatch(r"[a-f0-9]{40}|[a-f0-9]{64}", value)
                    for value in recipe["repositoryFingerprints"]), "QUALIFICATION_REQUIRED")
        require(len(set(recipe["repositoryFingerprints"])) == len(recipe["repositoryFingerprints"]), "QUALIFICATION_REQUIRED")
        require(type(recipe["aptIndexDigests"]) is list and 1 <= len(recipe["aptIndexDigests"]) <= 64,
                "QUALIFICATION_REQUIRED")
        for value in recipe["aptIndexDigests"]:
            sha(value)
        require(len(set(recipe["aptIndexDigests"])) == len(recipe["aptIndexDigests"]), "QUALIFICATION_REQUIRED")
        prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
        from .compiler import render
        render(prefix + ".settings", recipe["initialSettings"])
        for name in ("ownedResources", "expectedAbsentPaths"):
            require(type(recipe[name]) is list and len(recipe[name]) == 2 and
                    all(type(value) is str for value in recipe[name]), "QUALIFICATION_REQUIRED")
        require(set(recipe["ownedResources"]) == {prefix + ".settings", prefix + ".service"} and
                len(recipe["ownedResources"]) == 2 and set(recipe["expectedAbsentPaths"]) == ABSENT[recipe["id"]] and
                len(recipe["expectedAbsentPaths"]) == 2, "QUALIFICATION_REQUIRED")
        required = {"prechecks": {"fresh_product", "apt_snapshot", "apt_indexes", "no_start", "paths_absent"},
                    "postchecks": {"versions", "local_listeners", "sql", "owned_resources"}}
        for name, checks in required.items():
            require(type(recipe[name]) is list and all(type(value) is str for value in recipe[name]) and
                    set(recipe[name]) == checks and len(recipe[name]) == len(checks),
                    "QUALIFICATION_REQUIRED")
        require(type(recipe["licenseNotices"]) is list and 1 <= len(recipe["licenseNotices"]) <= 16,
                "QUALIFICATION_REQUIRED")
        for notice in recipe["licenseNotices"]:
            text(notice, 1, 2000, public=True)
    return catalog


def _validate_release_time(data, now):
    """APT's signed expiry semantics, including immutable base releases.

    A release without Valid-Until makes no expiry promise. Its exact signed
    bytes are still pinned by the recipe, never treated as a latest candidate.
    """
    dates = re.findall(r"^Date:[ \t]*(.*)$", data, re.MULTILINE | re.IGNORECASE)
    expiry = re.findall(r"^Valid-Until:[ \t]*(.*)$", data, re.MULTILINE | re.IGNORECASE)
    require(len(dates) == 1 and len(expiry) <= 1, "QUALIFICATION_REQUIRED")
    try:
        published = parsedate_to_datetime(dates[0])
        expires = parsedate_to_datetime(expiry[0]) if expiry else None
    except (TypeError, ValueError, OverflowError):
        raise Rejected("QUALIFICATION_REQUIRED") from None
    require(published.tzinfo is not None and
            (published - now).total_seconds() <= 300, "QUALIFICATION_REQUIRED")
    if expires is not None:
        require(expires.tzinfo is not None and expires > published and now < expires,
                "QUALIFICATION_REQUIRED")


def _prepared_files(recipe):
    raw, attributes = regular_file(CONFIG)
    require(raw == APT_CONFIG and attributes == {"uid": 0, "gid": 0, "mode": 0o600}, "QUALIFICATION_REQUIRED")
    policy, policy_attributes = regular_file("/usr/sbin/policy-rc.d")
    require(policy == NO_START and policy_attributes == {"uid": 0, "gid": 0, "mode": 0o755}, "QUALIFICATION_REQUIRED")
    source, _ = regular_file("/etc/serverdeck-executor/sources.list")
    entries = []
    for raw in source.decode("ascii").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"deb \[signed-by=" + re.escape(KEYRING) + r"\] (https://\S+) ([a-zA-Z0-9._/-]+)(?: ([a-zA-Z0-9 /-]+))?", line)
        require(match is not None, "QUALIFICATION_REQUIRED")
        parsed = urlsplit(match[1])
        require(parsed.hostname and parsed.username is None and parsed.password is None and
                not parsed.query and not parsed.fragment, "QUALIFICATION_REQUIRED")
        entries.append(line)
    require(1 <= len(entries) <= 16, "QUALIFICATION_REQUIRED")
    files = [hash_file(path) for path in (CONFIG, "/usr/sbin/policy-rc.d",
        "/etc/serverdeck-executor/sources.list", KEYRING)]
    _, keyring_attributes = regular_file(KEYRING, maximum=2 * 1024 * 1024)
    require(keyring_attributes == {"uid": 0, "gid": 0, "mode": 0o644}, "QUALIFICATION_REQUIRED")
    # Verify actual sandbox access, including ancestor search permissions/ACLs,
    # instead of inferring it from the final file's mode alone.
    command(["/usr/sbin/runuser", "-u", "_apt", "--", "/usr/bin/test", "-r", KEYRING],
            maximum=1024)
    lists = []
    for path in Path("/var/lib/apt/lists").iterdir():
        if path.name in ("lock", "partial", "auxfiles"):
            continue
        require(path.is_file() and not path.is_symlink(), "QUALIFICATION_REQUIRED")
        lists.append(path)
    require(1 <= len(lists) <= 64, "RESOURCE_LIMIT")
    indexes = [hash_file(path) for path in sorted(lists)]
    if recipe is not None:
        require(sorted(row["sha256"] for row in indexes) == sorted(recipe["aptIndexDigests"]), "CONFLICT")
    releases = [path for path in lists if path.name.endswith("_InRelease")]
    require(releases, "QUALIFICATION_REQUIRED")
    fingerprints = set()
    now = datetime.datetime.now(datetime.timezone.utc)
    for path in releases:
        status = command(["/usr/bin/gpgv", "--homedir", "/etc/serverdeck-executor/gnupg-empty",
            "--keyring", KEYRING, "--status-fd=1", str(path)], maximum=64 * 1024)
        valid = re.findall(rb"^\[GNUPG:\] VALIDSIG ([A-Fa-f0-9]{40,64}) ", status, re.MULTILINE)
        require(valid, "QUALIFICATION_REQUIRED")
        fingerprints.update(value.decode("ascii").lower() for value in valid)
        data = regular_file(path, maximum=4 * 1024 * 1024)[0].decode("utf-8")
        _validate_release_time(data, now)
    if recipe is None:
        return {"files": files + indexes,
                "aptIndexDigests": sorted(row["sha256"] for row in indexes),
                "repositoryFingerprints": sorted(fingerprints)}
    require(fingerprints == set(recipe["repositoryFingerprints"]), "QUALIFICATION_REQUIRED")
    return files + indexes


def _new_install_candidate(package, code="QUALIFICATION_REQUIRED"):
    # libapt Upgrade() includes NewInstall(): Status2 satisfies Status>0.
    # python-apt exposes both flags for new packages. marked_install is the
    # NewInstall flag; installed/config-file state below still forbids upgrades.
    candidate = package.candidate
    require(not protected_package(package.shortname) and not package.is_installed and
            not package.has_config_files and package.marked_install and
            not any((package.marked_delete, package.marked_downgrade,
                     package.marked_reinstall)) and candidate is not None and candidate.downloadable and
            candidate.architecture in ("amd64", "all") and candidate.origins and
            all(origin.trusted for origin in candidate.origins), code)
    return candidate


def build_prepared_catalog(request):
    """Materialize real immutable pins from prepared signed indexes, root only.

    Exact primary versions, initial settings and notices are operator inputs;
    dependencies, archive hashes, signer identities and index hashes are actual
    resolver evidence. No refresh, fetch or dpkg commit is performed.
    """
    require(os.geteuid() == 0 and sys.version_info[:2] == (3, 12), "FORBIDDEN")
    fields(request, {"format", "recipes"})
    require(type(request["format"]) is int and request["format"] == 1 and
            type(request["recipes"]) is list and 1 <= len(request["recipes"]) <= 2)
    metadata = _prepared_files(None)
    before, catalog, identifiers = package_snapshot(), {}, set()
    os.environ["APT_CONFIG"] = CONFIG
    import apt as system_apt
    import apt_pkg
    apt_pkg.init_config()
    apt_pkg.init_system()
    for row in request["recipes"]:
        fields(row, {"id", "version", "revision", "initialSettings", "licenseNotices"})
        product = row["id"]
        require(type(product) is str and product in PRIMARY and product not in identifiers)
        identifiers.add(product)
        version = text(row["version"], 1, 256, public=True)
        require(re.fullmatch(r"[A-Za-z0-9.+:~\-]{1,256}", version) and version.lower() != "latest")
        if product == "postgresql16":
            require(version.split(":")[-1].split(".")[0] == "16", "QUALIFICATION_REQUIRED")
        cache = system_apt.Cache()
        require(cache.broken_count == 0, "PREFLIGHT_FAILED")
        for name in sorted(PRIMARY[product]):
            require(name in cache and not cache[name].is_installed and not cache[name].has_config_files,
                    "QUALIFICATION_REQUIRED")
            versions = [candidate for candidate in cache[name].versions if candidate.version == version and
                        candidate.architecture in ("amd64", "all")]
            require(len(versions) == 1, "QUALIFICATION_REQUIRED")
            cache[name].candidate = versions[0]
        for name in sorted(PRIMARY[product]):
            cache[name].mark_install(auto_fix=False, auto_inst=True, from_user=True)
        require(cache.broken_count == 0, "PREFLIGHT_FAILED")
        pins = []
        for package in cache.get_changes():
            candidate = _new_install_candidate(package)
            pins.append({"name": package.shortname, "architecture": candidate.architecture,
                         "version": candidate.version, "sha256": sha(candidate.record.get("SHA256", "").lower())})
        pins.sort(key=lambda pin: (pin["name"], pin["architecture"]))
        prefix = "postgresql" if product == "postgresql16" else "clickhouse"
        descriptor = {"format": 1, "id": product, "version": version,
            "revision": integer(row["revision"], 1, 2147483647), "environment": "ubuntu24.04-amd64-systemd",
            "packagePins": pins, "dependencyTransactionDigest": transaction_digest(pins),
            "repositoryFingerprints": metadata["repositoryFingerprints"],
            "aptIndexDigests": metadata["aptIndexDigests"], "expectedAbsentPaths": sorted(ABSENT[product]),
            "ownedResources": [prefix + ".settings", prefix + ".service"],
            "prechecks": ["fresh_product", "apt_snapshot", "apt_indexes", "no_start", "paths_absent"],
            "postchecks": ["versions", "local_listeners", "sql", "owned_resources"],
            "initialSettings": row["initialSettings"], "licenseNotices": row["licenseNotices"]}
        descriptor["digest"] = digest(descriptor)
        catalog[descriptor["digest"]] = descriptor
    validate_catalog(catalog)
    recipes = sorted(catalog.values(), key=lambda value: value["id"])
    orders = [[recipe] for recipe in recipes]
    if len(recipes) == 2:
        orders += [recipes, list(reversed(recipes))]
    for ordered in orders:
        require(prepare_many(ordered)["packages"] == before, "CONFLICT")
    require(package_snapshot() == before, "CONFLICT")
    for evidence in metadata["files"]:
        require(hash_file(evidence["path"]) == evidence, "CONFLICT")
    return catalog


def prepare_many(recipes):
    """Resolve ordered recipe effects without changing dpkg's live database.

    Cumulative marks retain shared dependencies in one resolver, but each gate
    receives only additions first introduced by its effect. Later effects bind
    the complete intermediate package snapshot, including earlier additions.
    """
    require(type(recipes) is list and 1 <= len(recipes) <= 2, "QUALIFICATION_REQUIRED")
    catalog = {recipe["digest"]: recipe for recipe in recipes}
    require(len(catalog) == len(recipes), "QUALIFICATION_REQUIRED")
    validate_catalog(catalog)
    before = package_snapshot()
    pins_by_name, prepared_files = {}, None
    for recipe in recipes:
        prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
        require(not any(row[0].split(":")[0].startswith(prefix) for row in before), "QUALIFICATION_REQUIRED")
        for path in recipe["expectedAbsentPaths"]:
            require(not os.path.lexists(path), "QUALIFICATION_REQUIRED")
        from .qualification import validate_memory
        validate_memory(prefix + ".settings", recipe["initialSettings"], service_present=False)
        if prefix == "clickhouse":
            flags = Path("/proc/cpuinfo").read_bytes()
            require(len(flags) <= 16 * 1024 * 1024 and b"sse4_2" in flags.split(), "QUALIFICATION_REQUIRED")
        units = (["postgresql@16-main.service", "postgresql@.service", "postgresql.service"]
                 if prefix == "postgresql" else ["clickhouse-server.service"])
        for root in ("/etc/systemd/system", "/run/systemd/system"):
            for unit in units:
                require(not os.path.lexists(root + "/" + unit) and
                        not os.path.lexists(root + "/" + unit + ".d"), "QUALIFICATION_REQUIRED")
        files = _prepared_files(recipe)
        require(prepared_files is None or prepared_files == files, "CONFLICT")
        prepared_files = files
        for pin in recipe["packagePins"]:
            previous = pins_by_name.setdefault(pin["name"], pin)
            require(previous == pin, "CONFLICT")
    os.environ["APT_CONFIG"] = CONFIG
    import apt as system_apt
    import apt_pkg
    apt_pkg.init_config()
    apt_pkg.init_system()
    cache = system_apt.Cache()
    require(cache.broken_count == 0, "PREFLIGHT_FAILED")
    selected, qualified = {}, {}
    for pin in pins_by_name.values():
        require(pin["name"] in cache, "QUALIFICATION_REQUIRED")
        package = cache[pin["name"]]
        require(not package.is_installed and not package.has_config_files and not package.marked_delete,
                "QUALIFICATION_REQUIRED")
        versions = [value for value in package.versions if value.version == pin["version"] and
                    value.architecture == pin["architecture"]]
        require(len(versions) == 1, "QUALIFICATION_REQUIRED")
        version = versions[0]
        require(version.downloadable and version.record.get("SHA256", "").lower() == pin["sha256"] and
                version.origins and all(origin.trusted for origin in version.origins), "QUALIFICATION_REQUIRED")
        package.candidate = version
        selected[pin["name"]] = package
        multi = version.record.get("Multi-Arch", "none")
        require(multi in ("none", "no", "same", "foreign", "allowed"), "QUALIFICATION_REQUIRED")
        multi = "none" if multi == "no" else multi
        qualified[pin["name"]] = {**pin, "multiArch": multi}
    introduced, expected_rows, transactions = set(), list(before), []
    for recipe in recipes:
        names = {pin["name"] for pin in recipe["packagePins"]}
        additions = names - introduced
        require(PRIMARY[recipe["id"]] <= additions, "CONFLICT")
        for name in sorted(names):
            selected[name].mark_install(auto_fix=False, auto_inst=True, from_user=True)
        cumulative = introduced | names
        changes = cache.get_changes()
        require(cache.broken_count == 0 and len(changes) == len(cumulative) and
                {package.shortname for package in changes} == cumulative, "CONFLICT")
        for package in changes:
            version = _new_install_candidate(package, "CONFLICT")
            pin = qualified[package.shortname]
            require(version.version == pin["version"] and version.architecture == pin["architecture"] and
                    version.record.get("SHA256", "").lower() == pin["sha256"], "CONFLICT")
        pins = sorted((qualified[name] for name in additions), key=lambda row: (row["name"], row["architecture"]))
        snapshot = sorted(expected_rows)
        for pin in pins:
            binary = pin["name"] + (":" + pin["architecture"] if pin["multiArch"] == "same" else "")
            retained = []
            for row in expected_rows:
                if row[0].split(":")[0] == pin["name"]:
                    # dpkg may retain a not-installed database row without
                    # conffiles. It becomes installed, rather than producing a
                    # duplicate row in the expected complete snapshot.
                    require(row[3] == "not-installed" and row[1] == pin["architecture"], "CONFLICT")
                else:
                    retained.append(row)
            expected_rows = retained
            expected_rows.append([binary, pin["architecture"], pin["version"], "installed"])
        transactions.append({"recipeDigest": recipe["digest"], "packages": snapshot,
            "expectedPackages": sorted(expected_rows), "pins": pins, "files": prepared_files,
            "transactionDigest": transaction_digest([{key: value for key, value in pin.items()
                if key != "multiArch"} for pin in pins])})
        introduced = cumulative
    require(package_snapshot() == before, "CONFLICT")
    for row in prepared_files:
        require(hash_file(row["path"]) == row, "CONFLICT")
    return {"packages": before, "expectedPackages": sorted(expected_rows), "transactions": transactions}


def prepare(recipe):
    result = prepare_many([recipe])["transactions"][0]
    return {key: value for key, value in result.items() if key != "recipeDigest"}


def probe_recipe(recipe_digest, registry_digest):
    result = probe_recipes([recipe_digest], registry_digest)["transactions"][0]
    return {key: value for key, value in result.items() if key != "recipeDigest"}


def probe_recipes(recipe_digests, registry_digest):
    require(type(recipe_digests) is list and 1 <= len(recipe_digests) <= 2 and
            len(set(recipe_digests)) == len(recipe_digests), "QUALIFICATION_REQUIRED")
    for value in recipe_digests:
        sha(value)
    sha(registry_digest)
    result = decode(command(["/usr/lib/serverdeck-executor/apt-probe", *recipe_digests, registry_digest],
                            maximum=8 * 1024 * 1024, timeout=25), 8 * 1024 * 1024)
    if "error" in result:
        fields(result, {"error"})
        require(result["error"] in ("QUALIFICATION_REQUIRED", "CONFLICT", "PREFLIGHT_FAILED",
                                    "RESOURCE_LIMIT", "TIMEOUT"), "PREFLIGHT_FAILED")
        raise Rejected(result["error"])
    fields(result, {"packages", "expectedPackages", "transactions"})
    require(type(result["transactions"]) is list and len(result["transactions"]) == len(recipe_digests),
            "PREFLIGHT_FAILED")
    previous = result["packages"]
    for selected, transaction in zip(recipe_digests, result["transactions"]):
        fields(transaction, {"recipeDigest", "packages", "expectedPackages", "pins", "files", "transactionDigest"})
        require(transaction["recipeDigest"] == selected and transaction["packages"] == previous,
                "PREFLIGHT_FAILED")
        sha(transaction["transactionDigest"])
        previous = transaction["expectedPackages"]
    require(previous == result["expectedPackages"], "PREFLIGHT_FAILED")
    return result


def qualify_prepared_catalog(expected_digest):
    """Root provisioning only; bridge/read/apply cannot select this operation.

    Ubuntu's system Python owns python-apt. Check the protected candidate and
    every supported order with read-only cumulative resolver state; publication
    remains owned by the installer's stopped-supervisor journal lock.
    """
    expected_digest = sha(expected_digest)
    candidate = decode(regular_file("/etc/serverdeck-executor/catalog-candidate.json",
                                   maximum=512 * 1024)[0], 512 * 1024)
    validate_catalog(candidate)
    require(digest(candidate) == expected_digest, "CONFLICT")
    before = package_snapshot()
    recipes = sorted(candidate.values(), key=lambda row: row["id"])
    orders = [[recipe] for recipe in recipes]
    if len(recipes) == 2:
        orders += [recipes, list(reversed(recipes))]
    for ordered in orders:
        facts = prepare_many(ordered)
        require(facts["packages"] == before and package_snapshot() == before, "CONFLICT")
    require(digest(decode(regular_file("/etc/serverdeck-executor/catalog-candidate.json",
                                     maximum=512 * 1024)[0], 512 * 1024)) == expected_digest, "CONFLICT")
    return {"qualifiedCatalogDigest": expected_digest, "packageSnapshotDigest": digest(before)}


def main():
    try:
        require(os.geteuid() == 0 and len(sys.argv) in (3, 4) and sys.version_info[:2] == (3, 12), "FORBIDDEN")
        if sys.argv[1] == "--qualify-catalog":
            require(len(sys.argv) == 3, "FORBIDDEN")
            sys.stdout.buffer.write(wire_bytes(qualify_prepared_catalog(sys.argv[2])))
            return
        recipes, registry_digest = [sha(value) for value in sys.argv[1:-1]], sha(sys.argv[-1])
        require(len(set(recipes)) == len(recipes), "QUALIFICATION_REQUIRED")
        registry = decode(regular_file("/etc/serverdeck-executor/resources.json", maximum=512 * 1024)[0], 512 * 1024)
        require(digest(registry) == registry_digest, "CONFLICT")
        catalog = validate_catalog(registry["recipes"])
        require(all(recipe in catalog for recipe in recipes), "QUALIFICATION_REQUIRED")
        result = prepare_many([catalog[recipe] for recipe in recipes])
    except Exception as error:
        result = {"error": error.code if isinstance(error, Rejected) and error.code in
            ("QUALIFICATION_REQUIRED", "CONFLICT", "PREFLIGHT_FAILED", "RESOURCE_LIMIT", "TIMEOUT")
            else "QUALIFICATION_REQUIRED"}
    output = wire_bytes(result)
    require(len(output) <= 8 * 1024 * 1024, "RESOURCE_LIMIT")
    sys.stdout.buffer.write(output)


if __name__ == "__main__":
    main()
