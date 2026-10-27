"""Fixed effective-parent and memory checks for registered database resources.

Only administrator-enrolled fingerprints enable writes. Digests cover actual
parent/include files and canonical unit identity, not a caller qualification flag.
Managed overlay bytes are intentionally excluded so a proved own write does not
invalidate its unchanged parent baseline.
"""

import hashlib
import os
import pwd
import re
import stat
from pathlib import Path
import xml.etree.ElementTree as ET

from .codec import Rejected, digest, require
from .compiler import PATHS

PG = Path("/etc/postgresql/16/main")
CH = Path("/etc/clickhouse-server")
MANAGED_KEYS = {"postgresql.settings": {"max_connections", "shared_buffers"},
                "clickhouse.settings": {"max_connections", "max_server_memory_usage"}}
LAUNCHER = b'''#!/usr/bin/python3 -I
import sys
sys.path.insert(0, "/usr/lib/serverdeck-executor")
from serverdeck_executor.qualification import main
main()
'''


def _files(directory, suffix, excluded):
    # Private fixed directories only; no profile can select an include pathname.
    from .probes import regular_file
    info = directory.lstat()
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
            "QUALIFICATION_REQUIRED")
    entries = list(directory.iterdir())
    require(len(entries) <= 128, "RESOURCE_LIMIT")
    result = []
    for path in sorted(entries):
        if path.name == excluded:
            continue
        require(not path.is_symlink(), "QUALIFICATION_REQUIRED")
        if path.name.endswith(suffix):
            data, attributes = regular_file(path, maximum=256 * 1024)
            result.append((path, data, attributes))
    return result


def _pg_settings(data):
    # PostgreSQL line-oriented literal assignments; reject includes other than
    # the one fixed parent conf.d directory, and unsupported continuation syntax.
    result = []
    for raw in data.decode("utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([a-z_][a-z_0-9]*)\s*(?:=\s*)?('(?:[^']|'')*'|[^#\s]+)\s*(?:#.*)?", line)
        require(match is not None, "QUALIFICATION_REQUIRED")
        name, value = match.groups()
        require("\\" not in value, "QUALIFICATION_REQUIRED")
        result.append((name, value))
    return result


def _pg_auto():
    """Read only the canonical postgres-owned auto.conf without following links."""
    uid = pwd.getpwnam("postgres").pw_uid
    path = Path("/var/lib/postgresql/16/main/postgresql.auto.conf")
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in path.parts[1:-1]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_fd
            info = os.fstat(descriptor)
            require(info.st_uid in (0, uid) and not info.st_mode & 0o022, "QUALIFICATION_REQUIRED")
        file_fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=descriptor)
        try:
            before = os.fstat(file_fd)
            require(stat.S_ISREG(before.st_mode) and before.st_uid == uid and before.st_nlink == 1 and
                    not before.st_mode & 0o022 and before.st_size <= 64 * 1024, "QUALIFICATION_REQUIRED")
            data = os.read(file_fd, 64 * 1024 + 1)
            after = os.fstat(file_fd)
            require(len(data) <= 64 * 1024 and (before.st_ino, before.st_mtime_ns, before.st_size) ==
                    (after.st_ino, after.st_mtime_ns, after.st_size), "CONFLICT")
            # ALTER SYSTEM may override the managed include after its parser.
            # Do not adopt an existing override, even if it happens to match.
            require(not _pg_settings(data), "QUALIFICATION_REQUIRED")
            return {"path": str(path), "digest": hashlib.sha256(data).hexdigest(),
                    "uid": uid, "mode": stat.S_IMODE(before.st_mode)}
        finally:
            os.close(file_fd)
    finally:
        os.close(descriptor)


def _xml(data):
    try:
        literal = data.decode("utf-8")
    except UnicodeError:
        raise Rejected("QUALIFICATION_REQUIRED") from None
    require("\0" not in literal, "QUALIFICATION_REQUIRED")
    require(not any(token in data.upper() for token in
        (b"<!DOCTYPE", b"<!ENTITY", b"<?XML-STYLESHEET")), "QUALIFICATION_REQUIRED")
    try:
        root = ET.fromstring(literal)
    except (ET.ParseError, UnicodeError):
        raise Rejected("QUALIFICATION_REQUIRED") from None
    require(root.tag == "clickhouse", "QUALIFICATION_REQUIRED")
    count = [0]
    def visit(node, depth):
        count[0] += 1
        require(count[0] <= 4096 and depth <= 16, "RESOURCE_LIMIT")
        require(not set(node.attrib).intersection({"incl", "from_env", "from_zk"}) and
                node.tag not in ("include_from", "include"), "QUALIFICATION_REQUIRED")
        for child in node:
            visit(child, depth + 1)
    visit(root, 0)
    return root


def configuration_baseline(resource):
    from .probes import regular_file, unit_baseline
    require(resource in MANAGED_KEYS, "UNSUPPORTED")
    rows = []
    if resource == "postgresql.settings":
        parent = PG / "postgresql.conf"
        data, attributes = regular_file(parent, maximum=256 * 1024)
        settings = _pg_settings(data)
        includes = [(i, value) for i, (name, value) in enumerate(settings) if name.startswith("include")]
        require(len(includes) == 1 and settings[includes[0][0]][0] == "include_dir" and
                includes[0][1] in ("'conf.d'", "conf.d"), "QUALIFICATION_REQUIRED")
        require(all(i < includes[0][0] for i, (name, _) in enumerate(settings)
                    if name in MANAGED_KEYS[resource]), "QUALIFICATION_REQUIRED")
        declared = dict(settings)
        for name, expected in {"data_directory": "'/var/lib/postgresql/16/main'",
            "hba_file": "'/etc/postgresql/16/main/pg_hba.conf'",
            "ident_file": "'/etc/postgresql/16/main/pg_ident.conf'"}.items():
            require(declared.get(name) == expected, "QUALIFICATION_REQUIRED")
        rows.append((parent, data, attributes))
        for sibling in _files(PG / "conf.d", ".conf", "serverdeck.conf"):
            parsed = _pg_settings(sibling[1])
            require(all(name not in MANAGED_KEYS[resource] and not name.startswith("include")
                        for name, _ in parsed), "QUALIFICATION_REQUIRED")
            rows.append(sibling)
        for filename in ("pg_hba.conf", "pg_ident.conf", "start.conf", "pg_ctl.conf"):
            content, mode = regular_file(PG / filename, maximum=256 * 1024)
            rows.append((PG / filename, content, mode))
        # pg_ctlcluster reads the cluster environment independently of systemd's
        # EnvironmentFile list. Bind both contents and absence before adopting
        # a running cluster; a later override must invalidate the plan.
        environment = regular_file(PG / "environment", maximum=64 * 1024, absent=True)
        cluster_environment = {"path": str(PG / "environment"),
            "attributes": environment[1] if environment else None,
            "digest": hashlib.sha256(environment[0]).hexdigest() if environment else None}
        auto = _pg_auto()
    else:
        parent = CH / "config.xml"
        data, attributes = regular_file(parent, maximum=256 * 1024)
        _xml(data)
        rows.append((parent, data, attributes))
        for sibling in _files(CH / "config.d", ".xml", "serverdeck.xml"):
            root = _xml(sibling[1])
            require(all(node.tag not in MANAGED_KEYS[resource] for node in root.iter()),
                    "QUALIFICATION_REQUIRED")
            rows.append(sibling)
        users, user_mode = regular_file(CH / "users.xml", maximum=256 * 1024)
        _xml(users)
        rows.append((CH / "users.xml", users, user_mode))
        for sibling in _files(CH / "users.d", ".xml", ""):
            _xml(sibling[1])
            rows.append(sibling)
        auto = None
        cluster_environment = None
    return digest({"resourceId": resource, "managedPath": PATHS[resource],
        "unitBaseline": unit_baseline(resource.replace(".settings", ".service")),
        "parents": [{"path": str(path), "attributes": attributes,
                     "digest": hashlib.sha256(data).hexdigest()} for path, data, attributes in rows],
        "autoConfig": auto, "clusterEnvironment": cluster_environment})


def validate_database(resource, wanted, qualifications):
    from .probes import effective_settings, regular_file, service_properties, command
    from .compiler import render
    render(resource, wanted)
    baseline = configuration_baseline(resource)
    require(qualifications.get(resource) == baseline, "QUALIFICATION_REQUIRED")
    current = regular_file(PATHS[resource], absent=True)
    if current is not None:
        require(current[1] == {"uid": 0, "gid": 0, "mode": 0o644}, "QUALIFICATION_REQUIRED")
    service = resource.replace(".settings", ".service")
    values = service_properties(service)
    require(values["ActiveState"] == "active", "PREFLIGHT_FAILED")
    if service == "clickhouse.service":
        _, group, pids = database_processes(service)
        verify_local_listeners(service, group, pids, initial_only=False)
    # A live fixed probe is required even if an existing file has valid syntax.
    effective_settings(resource)
    if service == "postgresql.service":
        version = command(["/usr/sbin/runuser", "-u", "postgres", "--", "/usr/bin/psql",
            "-X", "-w", "-A", "-t", "-d", "postgres", "-c", "SHOW server_version_num"], maximum=4096)
        require(version.strip().isdigit() and 160000 <= int(version.strip()) < 170000, "QUALIFICATION_REQUIRED")
        postgresql_origin()
    validate_memory(resource, wanted)
    return baseline


def validate_memory(resource, wanted, *, service_present=True):
    from .probes import command, service_properties
    from .compiler import render
    render(resource, wanted)
    raw = Path("/proc/meminfo").read_bytes()
    require(len(raw) <= 64 * 1024, "RESOURCE_LIMIT")
    memory = re.search(rb"^MemTotal:\s+([0-9]+) kB$", raw, re.MULTILINE)
    require(memory is not None, "PREFLIGHT_FAILED")
    budget = int(memory[1]) * 1024
    # Respect a prepared canonical database unit MemoryMax as well as host RAM.
    if service_present:
        service = resource.replace(".settings", ".service")
        limit = command(["/usr/bin/systemctl", "show", service_properties(service)["Id"],
            "--property=MemoryMax", "--value", "--no-pager"], maximum=4096).strip()
        if limit != b"infinity":
            require(limit.isdigit(), "PREFLIGHT_FAILED")
            budget = min(budget, int(limit))
    wanted_bytes = wanted["shared_buffers_mb" if resource == "postgresql.settings" else
                          "max_server_memory_usage_mb"] * 1024 * 1024
    if wanted_bytes > (budget // 4 if resource == "postgresql.settings" else budget * 3 // 4):
        raise Rejected("RESOURCE_LIMIT", field="memory")


def postgresql_origin(require_managed=False):
    """The running cluster must actually use the registered config hierarchy.

    Source semantics: https://www.postgresql.org/docs/16/view-pg-settings.html
    No arbitrary SQL/path/user argument is accepted by this private fixed probe.
    """
    from .probes import command
    base = ["/usr/sbin/runuser", "-u", "postgres", "--", "/usr/bin/psql",
            "-X", "-w", "-A", "-t", "-F", "\t", "-d", "postgres", "-c"]
    paths = command(base + ["SELECT current_setting('config_file'), current_setting('data_directory'), "
        "current_setting('hba_file'), current_setting('ident_file')"], maximum=4096)
    require(paths.decode("ascii").strip().split("\t") == [str(PG / "postgresql.conf"),
        "/var/lib/postgresql/16/main", str(PG / "pg_hba.conf"), str(PG / "pg_ident.conf")], "QUALIFICATION_REQUIRED")
    raw = command(base + ["SELECT name, COALESCE(sourcefile,''), source, pending_restart "
        "FROM pg_settings WHERE name IN ('max_connections','shared_buffers') ORDER BY name"], maximum=4096)
    rows = [line.split("\t") for line in raw.decode("ascii").splitlines()]
    require(len(rows) == 2 and [row[0] for row in rows] == ["max_connections", "shared_buffers"], "QUALIFICATION_REQUIRED")
    for row in rows:
        require(len(row) == 4 and row[3] in ("t", "f"), "QUALIFICATION_REQUIRED")
        if require_managed:
            require(row[1] == PATHS["postgresql.settings"] and row[2] == "configuration file" and row[3] == "f", "POSTCHECK_FAILED")
        else:
            require(row[1] in (str(PG / "postgresql.conf"), PATHS["postgresql.settings"]) and
                    row[2] == "configuration file" or row[1] == "" and row[2] == "default", "QUALIFICATION_REQUIRED")


def recipe_prestart(recipe):
    """Fixed post-package, pre-start validation inside the admitted unit only."""
    import grp
    from .compiler import recipe_files
    from .probes import command, regular_file, service_properties
    prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
    for path, (content, mode, group) in recipe_files(recipe).items():
        raw, actual = regular_file(path, maximum=256 * 1024)
        require(raw == content.encode("utf-8") and actual == {
            "uid": 0, "gid": grp.getgrnam(group).gr_gid, "mode": int(mode, 8)}, "QUALIFICATION_REQUIRED")
    values = service_properties(prefix + ".service")
    require(values["ActiveState"] in ("inactive", "failed") and values["MainPID"] == "0",
            "QUALIFICATION_REQUIRED")
    require(not any("netbird" in value.lower() for name, value in values.items()
                    if name in ("Requires", "Wants")), "QUALIFICATION_REQUIRED")
    validate_memory(prefix + ".settings", recipe["initialSettings"])
    if prefix == "postgresql":
        value = command(["/usr/sbin/runuser", "-u", "postgres", "--",
            "/usr/lib/postgresql/16/bin/postgres", "-D", "/var/lib/postgresql/16/main",
            "-C", "max_connections", "-c", "config_file=/etc/postgresql/16/main/postgresql.conf"], maximum=4096)
        require(value.strip() == str(recipe["initialSettings"]["max_connections"]).encode("ascii"),
                "QUALIFICATION_REQUIRED")
    # Reparse the actual parent/include/auth hierarchy; rendered file equality
    # alone cannot rule out an unexpected package-generated override/include.
    return configuration_baseline(prefix + ".settings")


def database_processes(resource):
    """Actual canonical systemd cgroup and process identity, not a SQL flag."""
    from .compiler import UNITS
    from .probes import command, service_properties, system_slice_cgroup
    unit = UNITS[resource]
    before = service_properties(resource)
    require(before["ActiveState"] == "active" and before["MainPID"].isdigit() and
            int(before["MainPID"]) > 0, "POSTCHECK_FAILED")
    group = command(["/usr/bin/systemctl", "show", unit, "--property=ControlGroup", "--value", "--no-pager"],
                    maximum=4096).decode("ascii").strip()
    require(group == system_slice_cgroup() + "/" + unit, "QUALIFICATION_REQUIRED")
    with open(Path("/sys/fs/cgroup") / group.removeprefix("/") / "cgroup.procs", "rb") as stream:
        raw = stream.read(64 * 1024 + 1)
    require(len(raw) <= 64 * 1024, "RESOURCE_LIMIT")
    pids = raw.decode("ascii").splitlines()
    require(1 <= len(pids) <= 4096 and all(pid.isdecimal() and 0 < int(pid) <= 2147483647 for pid in pids) and
            before["MainPID"] in pids, "POSTCHECK_FAILED")
    main = Path("/proc") / before["MainPID"]
    expected_user = "postgres" if resource == "postgresql.service" else "clickhouse"
    require(main.stat().st_uid == pwd.getpwnam(expected_user).pw_uid and
            (main / "cgroup").read_text(encoding="ascii") == "0::" + group + "\n", "POSTCHECK_FAILED")
    executable = os.readlink(main / "exe")
    if resource == "postgresql.service":
        require(executable == "/usr/lib/postgresql/16/bin/postgres", "QUALIFICATION_REQUIRED")
    else:
        require(executable == "/usr/bin/clickhouse", "QUALIFICATION_REQUIRED")
        with open(main / "cmdline", "rb") as stream:
            args = stream.read(8193)
        require(len(args) <= 8192, "RESOURCE_LIMIT")
        argv = args.rstrip(b"\0").split(b"\0")
        config = [value for value in argv if value.startswith((b"--config", b"-C"))]
        require(config == [b"--config=/etc/clickhouse-server/config.xml"], "QUALIFICATION_REQUIRED")
    return before, group, pids


def verify_local_listeners(resource, group, pids, *, initial_only=True):
    """Bind SQL endpoints to actual database-owned kernel TCP socket inodes."""
    import ipaddress
    import socket
    import time
    deadline = time.monotonic() + 5
    expected = {5432} if resource == "postgresql.service" else {8123, 9000} if initial_only else {8123}
    owned = set()
    for pid in pids:
        require(time.monotonic() < deadline, "TIMEOUT")
        process = Path("/proc") / pid
        try:
            require((process / "cgroup").read_text(encoding="ascii") == "0::" + group + "\n", "CONFLICT")
            descriptors = list((process / "fd").iterdir())
            require(len(descriptors) <= 16384, "RESOURCE_LIMIT")
            for descriptor in descriptors:
                require(time.monotonic() < deadline, "TIMEOUT")
                try:
                    value = os.readlink(descriptor)
                except FileNotFoundError:
                    continue
                match = re.fullmatch(r"socket:\[([0-9]+)\]", value)
                if match:
                    owned.add(match[1])
        except FileNotFoundError:
            # A short-lived worker can disappear; required listener ownership
            # and the stable main PID/start identity are still mandatory below.
            continue
    ports = set()
    for family, name in ((socket.AF_INET, "tcp"), (socket.AF_INET6, "tcp6")):
        try:
            with open("/proc/net/" + name, "rb") as stream:
                data = stream.read(8 * 1024 * 1024 + 1)
        except FileNotFoundError:
            require(family == socket.AF_INET6, "POSTCHECK_FAILED")
            continue
        require(len(data) <= 8 * 1024 * 1024, "RESOURCE_LIMIT")
        for line in data.decode("ascii").splitlines()[1:]:
            require(time.monotonic() < deadline, "TIMEOUT")
            row = line.split()
            require(len(row) >= 10, "POSTCHECK_FAILED")
            if row[3] != "0A":
                continue
            address, port = row[1].split(":")
            raw = bytes.fromhex(address)
            raw = b"".join(raw[i:i + 4][::-1] for i in range(0, len(raw), 4))
            address, port, inode = ipaddress.ip_address(raw), int(port, 16), row[9]
            if inode in owned:
                if initial_only:
                    require(address.is_loopback and port in expected, "POSTCHECK_FAILED")
                if port in expected and (address.is_loopback or address.is_unspecified):
                    ports.add(port)
            if (address == ipaddress.ip_address("127.0.0.1") or address.version == 4 and address.is_unspecified) and port in expected:
                require(inode in owned, "POSTCHECK_FAILED")
    require(ports == expected, "POSTCHECK_FAILED")


def verify_recipe_install(recipe, expected_packages):
    import grp
    from .compiler import recipe_files
    from .probes import (_clickhouse, command, effective_settings, package_snapshot,
                         regular_file, service_properties, sql_one, unit_baseline)
    prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
    service, settings = prefix + ".service", prefix + ".settings"
    require(package_snapshot() == expected_packages, "POSTCHECK_FAILED")
    for path, (content, mode, group) in recipe_files(recipe).items():
        raw, attributes = regular_file(path, maximum=256 * 1024)
        require(raw == content.encode("utf-8") and attributes == {
            "uid": 0, "gid": grp.getgrnam(group).gr_gid, "mode": int(mode, 8)}, "POSTCHECK_FAILED")
    before, group, pids = database_processes(service)
    require(before["UnitFileState"] == "enabled", "POSTCHECK_FAILED")
    verify_local_listeners(service, group, pids)
    parent, unit = configuration_baseline(settings), unit_baseline(service)
    wanted = recipe["initialSettings"]
    validate_database(settings, wanted, {settings: parent, service: unit})
    require(effective_settings(settings) == wanted, "POSTCHECK_FAILED")
    sql_one(service)
    if prefix == "postgresql":
        postgresql_origin(require_managed=True)
    else:
        expected_version = recipe["version"].split(":")[-1].split("-")[0]
        require(_clickhouse("version").decode("ascii").strip() == expected_version, "POSTCHECK_FAILED")
    after = service_properties(service)
    require((after["MainPID"], after["ExecMainStartTimestampMonotonic"], after["ActiveState"]) ==
            (before["MainPID"], before["ExecMainStartTimestampMonotonic"], "active"), "POSTCHECK_FAILED")
    require(package_snapshot() == expected_packages and configuration_baseline(settings) == parent and
            unit_baseline(service) == unit, "CONFLICT")
    return {settings: parent, service: unit}


def main():
    import sys
    from .codec import decode, sha
    from .apt import validate_catalog
    from .apt_gate import _current_work, _document
    from .probes import boot_id_hash, netbird_preservation_digest, package_snapshot, regular_file
    try:
        require(os.geteuid() == 0 and len(sys.argv) == 3 and sys.version_info[:2] == (3, 12), "FORBIDDEN")
        selected, registry_digest = sha(sys.argv[1]), sha(sys.argv[2])
        directory, unit, attempt, step = _current_work()
        context, launch = _document(directory / "apt-context.json"), _document(directory / "launch.json")
        require(netbird_preservation_digest() == sha(context["netbirdPreservationDigest"]), "POSTCHECK_FAILED")
        proof = _document(directory / "apt-gate-proof.json")
        for document in (context, launch, proof):
            require(document["attemptId"] == attempt and document["unit"] == unit and document["stepId"] == step,
                    "FORBIDDEN")
            require(document["planDigest"] == context["planDigest"] and
                    document["programDigest"] == context["programDigest"], "FORBIDDEN")
        require(context["recipeDigest"] == selected and context["bootIdHash"] == boot_id_hash() and
                proof["transactionDigest"] == context["transactionDigest"], "FORBIDDEN")
        program = regular_file(directory / "effect.json", maximum=256 * 1024)[0]
        require(hashlib.sha256(program).hexdigest() == context["programDigest"], "CONFLICT")
        require(digest(package_snapshot()) == context["expectedPackageSnapshotDigest"], "CONFLICT")
        registry = decode(regular_file("/etc/serverdeck-executor/resources.json", maximum=512 * 1024)[0], 512 * 1024)
        require(digest(registry) == registry_digest, "CONFLICT")
        catalog = validate_catalog(registry["recipes"])
        require(selected in catalog, "QUALIFICATION_REQUIRED")
        recipe_prestart(catalog[selected])
    except Exception:
        # Never leak package/configuration/subprocess diagnostics to the play.
        print("RECIPE_PRESTART_REFUSED", file=sys.stderr)
        sys.exit(1)
