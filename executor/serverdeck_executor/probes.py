"""Fixed read-only probes. All command/path selection belongs to this module."""

import hashlib
import os
import re
import selectors
import stat
import subprocess
import time
import urllib.request
import urllib.parse
from pathlib import Path

from .codec import Rejected, canonical, digest, require
from .compiler import PATHS, UNITS, render

SYSTEM_PATH = "/usr/sbin:/usr/bin:/sbin:/bin"
PROBE_ENV = {"PATH": SYSTEM_PATH, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "HOME": "/root"}


def command(arguments, maximum=64 * 1024, timeout=5, accepted_codes=(0,)):
    """Only private fixed argv call sites; bounded pipes, no inherited config."""
    process = subprocess.Popen(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, env=PROBE_ENV, close_fds=True)
    collected = bytearray()
    deadline = time.monotonic() + timeout
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            require(remaining > 0, "TIMEOUT")
            for key, _ in selector.select(min(remaining, 0.1)):
                chunk = os.read(key.fd, 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                require(len(collected) + len(chunk) <= maximum, "RESOURCE_LIMIT")
                collected.extend(chunk)
        require(process.wait(timeout=max(0.01, deadline - time.monotonic())) in accepted_codes, "PREFLIGHT_FAILED")
        return bytes(collected)
    except subprocess.TimeoutExpired:
        raise Rejected("TIMEOUT") from None
    finally:
        selector.close()
        process.stdout.close()
        # These are read-only probes, never apt or an effect child.
        if process.poll() is None:
            process.kill()
            process.wait()


def regular_file(path, maximum=64 * 1024, absent=False):
    """Read exact registered paths; reject writable/symlink ancestors."""
    path = Path(path)
    for parent in reversed(path.parents):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            require(absent, "QUALIFICATION_REQUIRED")
            return None
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and
                not info.st_mode & 0o022, "QUALIFICATION_REQUIRED")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except FileNotFoundError:
        require(absent, "QUALIFICATION_REQUIRED")
        return None
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1 and
                not info.st_mode & 0o022 and info.st_size <= maximum, "QUALIFICATION_REQUIRED")
        data = bytearray()
        while True:
            chunk = os.read(descriptor, min(8192, maximum + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
            require(len(data) <= maximum, "RESOURCE_LIMIT")
        after = os.fstat(descriptor)
        require((info.st_ino, info.st_mtime_ns, info.st_size) ==
                (after.st_ino, after.st_mtime_ns, after.st_size), "CONFLICT")
        return bytes(data), {"uid": info.st_uid, "gid": info.st_gid,
                             "mode": stat.S_IMODE(info.st_mode)}
    finally:
        os.close(descriptor)


def boot_id_hash():
    return hashlib.sha256(Path("/proc/sys/kernel/random/boot_id").read_bytes().strip()).hexdigest()


def system_slice_cgroup():
    """Resolve the actual manager slice, including delegated container prefix."""
    value = command(["/usr/bin/systemctl", "show", "system.slice", "--no-pager",
                     "--property=ControlGroup", "--value"], maximum=4096).decode("ascii").strip()
    require(value.startswith("/") and not value.startswith("//") and len(value) <= 1024 and
            Path(value).name == "system.slice" and str(Path(value)) == value and
            ".." not in Path(value).parts and all(32 < ord(char) < 127 for char in value),
            "QUALIFICATION_REQUIRED")
    return value


def protected_package(name):
    binary = name.split(":", 1)[0]
    return binary == "netbird" or binary.startswith("netbird-")


def netbird_preservation_digest():
    """Private no-argument preservation fence, never an RPC file reader.

    Bind canonical service identity/start and its installed unit files, standard
    configuration/state trees and optional distro environment file. Mutable
    daemon state can cause CONFLICT; it never authorizes a guessed success.
    """
    properties = "Id,LoadState,ActiveState,SubState,UnitFileState,MainPID,ExecMainStartTimestampMonotonic,FragmentPath,DropInPaths"
    def unit():
        output = command(["/usr/bin/systemctl", "show", "netbird.service", "--no-pager", "--all",
                          "--property=" + properties], accepted_codes=(0, 4)).decode("utf-8")
        values = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
        require(set(values) == set(properties.split(",")) and values["Id"] == "netbird.service" and
                values["LoadState"] in ("loaded", "not-found"), "QUALIFICATION_REQUIRED")
        return values
    before = unit()
    require(before["ActiveState"] in ("active", "inactive", "failed"), "HOST_BUSY")
    environment_inputs = (_unit_environment_baseline("netbird.service")
                          if before["LoadState"] == "loaded" else None)
    def check_paths(raw):
        value = "\n".join(line for line in raw.decode("utf-8").replace("\0", " ").splitlines()
                          if not line.lstrip().startswith("#"))
        pattern = r'''(?:NB_(?:STATE_DIR|CONFIG|DNS_STATE_FILE)\s*=\s*|--(?:config|state-dir|dns-state-file)(?:=|\s+))["']?([^\s\x00;"']+)'''
        for match in re.finditer(pattern, value):
            selected = match[1]
            require(re.fullmatch(r"/(?:etc|var/lib)/netbird(?:/[a-zA-Z0-9_.@+-]+)*", selected) is not None and
                    str(Path(selected)) == selected and ".." not in Path(selected).parts,
                    "QUALIFICATION_REQUIRED")
    if environment_inputs is not None:
        check_paths("\n".join(environment_inputs["properties"].values()).encode("utf-8"))
        for row in environment_inputs["files"]:
            if row["digest"] is not None:
                check_paths(regular_file(row["path"], maximum=64 * 1024)[0])
    pid = before["MainPID"]
    require(pid.isascii() and pid.isdecimal() and int(pid) <= 2147483647, "QUALIFICATION_REQUIRED")
    if before["ActiveState"] == "active":
        require(int(pid) > 0 and Path("/proc", pid).stat().st_uid == 0, "QUALIFICATION_REQUIRED")
        for name, maximum in (("environ", 1024 * 1024), ("cmdline", 64 * 1024)):
            check_paths(regular_file(Path("/proc", pid, name), maximum=maximum)[0])
    files = []
    for path in ([before["FragmentPath"]] if before["FragmentPath"] else []) + before["DropInPaths"].split():
        require(path.startswith(("/etc/systemd/system/", "/usr/lib/systemd/system/", "/lib/systemd/system/")) and
                ".." not in Path(path).parts, "QUALIFICATION_REQUIRED")
        if path.startswith("/lib/systemd/system/") and Path("/lib").is_symlink():
            require(Path("/lib").lstat().st_uid == 0 and os.readlink("/lib") in ("usr/lib", "/usr/lib"),
                    "QUALIFICATION_REQUIRED")
            path = "/usr" + path
        raw, attributes = regular_file(path, maximum=256 * 1024)
        check_paths(raw)
        files.append({"path": path, "attributes": attributes, "digest": hashlib.sha256(raw).hexdigest()})
    count, total, trees = 0, 0, []
    def capture(path, depth=0):
        nonlocal count, total
        if depth == 0:
            for parent in reversed(path.parents):
                try:
                    ancestor = parent.lstat()
                except FileNotFoundError:
                    return None
                require(stat.S_ISDIR(ancestor.st_mode) and ancestor.st_uid == 0 and
                        not ancestor.st_mode & 0o022, "QUALIFICATION_REQUIRED")
        count += 1
        require(count <= 512 and depth <= 8, "RESOURCE_LIMIT")
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        require(info.st_uid == 0 and not info.st_mode & 0o022, "QUALIFICATION_REQUIRED")
        attributes = {"uid": info.st_uid, "gid": info.st_gid, "mode": stat.S_IMODE(info.st_mode)}
        if stat.S_ISDIR(info.st_mode):
            names = sorted(entry.name for entry in path.iterdir())
            require(count + len(names) <= 512, "RESOURCE_LIMIT")
            children = [{"name": name, "value": capture(path / name, depth + 1)} for name in names]
            require(names == sorted(entry.name for entry in path.iterdir()), "CONFLICT")
            return {"attributes": attributes, "children": children}
        require(stat.S_ISREG(info.st_mode), "QUALIFICATION_REQUIRED")
        raw, attributes = regular_file(path, maximum=16 * 1024 * 1024)
        total += len(raw)
        require(total <= 128 * 1024 * 1024, "RESOURCE_LIMIT")
        return {"attributes": attributes, "digest": hashlib.sha256(raw).hexdigest()}
    for root in (Path("/etc/netbird"), Path("/var/lib/netbird")):
        trees.append({"path": str(root), "value": capture(root)})
    environment = Path("/etc/sysconfig/netbird")
    value = capture(environment)
    trees.append({"path": str(environment), "value": value})
    require(unit() == before, "CONFLICT")
    return digest({"unit": before, "files": files, "trees": trees, "environment": environment_inputs})


def package_snapshot():
    data = command(["/usr/bin/dpkg-query", "-W", "-f=${binary:Package}\t${Architecture}\t${Version}\t${db:Status-Status}\n"],
                   maximum=4 * 1024 * 1024)
    rows = []
    for line in data.decode("utf-8").splitlines():
        row = line.split("\t")
        require(len(row) == 4, "PREFLIGHT_FAILED")
        require(row[3] in ("installed", "config-files", "not-installed"), "PREFLIGHT_FAILED")
        rows.append(row)
    return sorted(rows)


def service_properties(resource):
    require(resource in UNITS)
    properties = ("Id", "LoadState", "ActiveState", "UnitFileState", "MainPID",
                  "ExecMainStartTimestampMonotonic", "FragmentPath", "DropInPaths", "Requires", "Wants")
    output = command(["/usr/bin/systemctl", "show", UNITS[resource], "--no-pager",
                      "--property=" + ",".join(properties)]).decode("utf-8")
    values = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    require(set(values) == set(properties) and values["Id"] == UNITS[resource] and
            values["LoadState"] == "loaded", "QUALIFICATION_REQUIRED")
    return values


def unit_environment_baseline(resource):
    require(resource in UNITS)
    return _unit_environment_baseline(UNITS[resource])


def _unit_environment_baseline(unit):
    """Bind resolved systemd environment inputs, including optional absence.

    v255 prints one EnvironmentFiles= line for each (path, ignore_errors) tuple.
    Never turn it into a dict, which would silently discard all but the last.
    Only bounded literal /etc paths are qualified; globs/unprintable/escaped
    representations require an administrator to simplify the unit first.
    """
    require(unit in set(UNITS.values()) | {"netbird.service"})
    names = {"Environment", "PassEnvironment", "UnsetEnvironment"}
    output = command(["/usr/bin/systemctl", "show", unit, "--no-pager", "--all",
                      "--property=Environment,EnvironmentFiles,PassEnvironment,UnsetEnvironment"])
    values, files = {}, []
    for line in output.decode("utf-8").splitlines():
        require("=" in line, "QUALIFICATION_REQUIRED")
        key, value = line.split("=", 1)
        if key == "EnvironmentFiles":
            if not value:
                continue
            match = re.fullmatch(r"(/etc/[a-zA-Z0-9_./@+-]+) \(ignore_errors=(yes|no)\)", value)
            require(match is not None and ".." not in Path(match[1]).parts and
                    str(Path(match[1])) == match[1] and len(files) < 16, "QUALIFICATION_REQUIRED")
            path, optional = match[1], match[2] == "yes"
            current = regular_file(path, maximum=64 * 1024, absent=optional)
            files.append({"path": path, "optional": optional,
                "attributes": current[1] if current else None,
                "digest": hashlib.sha256(current[0]).hexdigest() if current else None})
        else:
            require(key in names and key not in values and "[unprintable]" not in value,
                    "QUALIFICATION_REQUIRED")
            values[key] = value
    require(set(values) == names, "QUALIFICATION_REQUIRED")
    return {"properties": values, "files": files}


def unit_baseline(resource):
    values = service_properties(resource)
    paths = [values["FragmentPath"], *values["DropInPaths"].split()]
    require(1 <= len(paths) <= 33, "RESOURCE_LIMIT")
    files = []
    for path in paths:
        require(path.startswith(("/etc/systemd/system/", "/usr/lib/systemd/system/", "/lib/systemd/system/")) and
                ".." not in Path(path).parts, "QUALIFICATION_REQUIRED")
        if path.startswith("/lib/systemd/system/") and Path("/lib").is_symlink():
            require(Path("/lib").lstat().st_uid == 0 and os.readlink("/lib") in ("usr/lib", "/usr/lib"),
                    "QUALIFICATION_REQUIRED")
            path = "/usr" + path
        data, attributes = regular_file(path, maximum=256 * 1024)
        files.append({"path": path, "attributes": attributes, "digest": hashlib.sha256(data).hexdigest()})
    return digest({"id": UNITS[resource], "files": files,
                   "requires": sorted(values["Requires"].split()), "wants": sorted(values["Wants"].split()),
                   "environment": unit_environment_baseline(resource)})


def observe(resource, qualifications):
    """Return registered value only; locald supplies captured target identity.

    The administrator-installed qualification map binds DB effective parent
    configuration and canonical units. It cannot be supplied by a profile.
    """
    if resource in UNITS:
        baseline = unit_baseline(resource)
        require(qualifications.get(resource) == baseline, "QUALIFICATION_REQUIRED")
        values = service_properties(resource)
        active, enabled = values["ActiveState"], values["UnitFileState"]
        require(active in ("active", "inactive", "failed", "activating", "deactivating", "reloading") and
                enabled in ("enabled", "enabled-runtime", "disabled", "static", "masked", "masked-runtime",
                            "indirect", "generated", "transient", "linked", "linked-runtime", "alias", "bad"),
                "UNSUPPORTED")
        pid, started = values["MainPID"], values["ExecMainStartTimestampMonotonic"]
        require(pid.isascii() and pid.isdecimal() and int(pid) <= 2147483647 and
                started.isascii() and started.isdecimal() and int(started) <= 9223372036854775807,
                "UNSUPPORTED")
        return {"activeState": active, "unitFileState": enabled, "mainPid": int(pid),
                "startMonotonicUs": str(int(started)), "baselineDigest": baseline}
    require(resource in PATHS, "UNSUPPORTED")
    read = regular_file(PATHS[resource], absent=True)
    if resource != "system.motd":
        # Effective config validation is required before adopting any DB file.
        # A bare text match or presence is never ownership qualification.
        from .qualification import configuration_baseline
        require(qualifications.get(resource) == configuration_baseline(resource), "QUALIFICATION_REQUIRED")
    if read is not None:
        require(read[1] == {"uid": 0, "gid": 0, "mode": 0o644}, "QUALIFICATION_REQUIRED")
    baseline = digest({"path": PATHS[resource], "attributes": {"uid": 0, "gid": 0, "mode": 0o644},
                       "qualification": qualifications.get(resource)})
    if read is None:
        return {"exists": False, "fileDigest": None, "baselineDigest": baseline, "values": None}
    try:
        content = read[0].decode("utf-8")
    except UnicodeError:
        raise Rejected("UNSUPPORTED") from None
    if resource == "system.motd":
        values = {"text": content}
    elif resource == "postgresql.settings":
        import re
        match = re.fullmatch(r"max_connections = ([0-9]+)\nshared_buffers = '([0-9]+)MB'\n", content)
        require(match is not None, "UNSUPPORTED")
        values = {"max_connections": int(match[1]), "shared_buffers_mb": int(match[2])}
        render(resource, values)
    else:
        import re
        match = re.fullmatch(r"<clickhouse>\n  <max_connections>([0-9]+)</max_connections>\n"
                             r"  <max_server_memory_usage>([0-9]+)</max_server_memory_usage>\n</clickhouse>\n", content)
        require(match is not None and int(match[2]) % (1024 * 1024) == 0, "UNSUPPORTED")
        values = {"max_connections": int(match[1]),
                  "max_server_memory_usage_mb": int(match[2]) // (1024 * 1024)}
        render(resource, values)
    return {"exists": True, "fileDigest": hashlib.sha256(read[0]).hexdigest(),
            "baselineDigest": baseline, "values": values}


def sql_one(resource):
    require(resource in UNITS)
    if resource == "postgresql.service":
        output = command(["/usr/sbin/runuser", "-u", "postgres", "--", "/usr/bin/psql",
                          "-X", "-w", "-A", "-t", "-d", "postgres", "-c", "SELECT 1"], maximum=4096)
    else:
        output = _clickhouse("health")
    require(len(output) <= 4096 and output.strip() == b"1", "HEALTH_CHECK_FAILED")
    return 1


def _clickhouse(probe):
    # Private closed selector. No SQL, URL or proxy is supplied by a caller.
    queries = {"health": "SELECT 1", "version": "SELECT version()",
               "settings": "SELECT name, value FROM system.server_settings WHERE name IN "
                           "('max_connections','max_server_memory_usage') ORDER BY name FORMAT TabSeparated"}
    require(probe in queries, "INTERNAL")

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        url = "http://127.0.0.1:8123/?" + urllib.parse.urlencode({"query": queries[probe], "readonly": "1"})
        with opener.open(urllib.request.Request(url, method="GET"), timeout=5) as response:
            output = response.read(4097)
        require(len(output) <= 4096, "RESOURCE_LIMIT")
        return output
    except (OSError, ValueError):
        raise Rejected("HEALTH_CHECK_FAILED") from None


def effective_settings(resource):
    """Actual running settings, separately from rendered file bytes.

    Fixed probes correspond to the upstream current_setting function and
    ClickHouse system.server_settings name/value columns:
    https://www.postgresql.org/docs/16/functions-admin.html
    https://clickhouse.com/docs/reference/system-tables/server_settings
    """
    require(resource in ("postgresql.settings", "clickhouse.settings"))
    if resource == "postgresql.settings":
        query = "SELECT current_setting('max_connections'), pg_size_bytes(current_setting('shared_buffers'))"
        raw = command(["/usr/sbin/runuser", "-u", "postgres", "--", "/usr/bin/psql",
                       "-X", "-w", "-A", "-t", "-F", "\t", "-d", "postgres", "-c", query], maximum=4096)
        columns = raw.decode("ascii").strip().split("\t")
        require(len(columns) == 2 and all(value.isdecimal() for value in columns), "POSTCHECK_FAILED")
        maximum, memory = map(int, columns)
        require(memory % (1024 * 1024) == 0, "POSTCHECK_FAILED")
        result = {"max_connections": maximum, "shared_buffers_mb": memory // (1024 * 1024)}
    else:
        rows = _clickhouse("settings").decode("ascii").strip().splitlines()
        values = {}
        for row in rows:
            pair = row.split("\t")
            require(len(pair) == 2 and pair[0] not in values and pair[1].isdecimal(), "POSTCHECK_FAILED")
            values[pair[0]] = int(pair[1])
        require(set(values) == {"max_connections", "max_server_memory_usage"} and
                values["max_server_memory_usage"] % (1024 * 1024) == 0, "POSTCHECK_FAILED")
        result = {"max_connections": values["max_connections"],
                  "max_server_memory_usage_mb": values["max_server_memory_usage"] // (1024 * 1024)}
    render(resource, result)
    return result
