"""Closed format1 compiler. It accepts an AST, never YAML or caller commands.

Compilation establishes a deterministic program, not permission to execute it.
The supervisor must additionally verify root preflight, current authorization,
registered resource ownership and factual baseline before every launch.
"""

import copy
import hashlib
from dataclasses import dataclass

from .codec import canonical, digest, fields, identifier, integer, require, sha, text

ENVIRONMENT = "ubuntu24.04-amd64-systemd"
UNITS = {"postgresql.service": "postgresql@16-main.service",
         "clickhouse.service": "clickhouse-server.service"}
PATHS = {"system.motd": "/etc/motd",
         "postgresql.settings": "/etc/postgresql/16/main/conf.d/serverdeck.conf",
         "clickhouse.settings": "/etc/clickhouse-server/config.d/serverdeck.xml"}
CONFIG_FIELDS = {"system.motd": {"text": ("string", 0, 4096)},
                 "postgresql.settings": {"max_connections": ("integer", 10, 1000),
                                         "shared_buffers_mb": ("integer", 16, 16384)},
                 "clickhouse.settings": {"max_connections": ("integer", 10, 10000),
                                         "max_server_memory_usage_mb": ("integer", 128, 1048576)}}
SERVICE = ("enum", ("started", "stopped", "restarted"))
BOOLEAN = ("boolean",)


def _field(value, schema):
    if schema[0] == "integer":
        return integer(value, schema[1], schema[2])
    if schema[0] == "boolean":
        require(type(value) is bool)
        return value
    if schema[0] == "enum":
        require(type(value) is str and value in schema[1])
        return value
    return text(value, schema[1], schema[2], public=True)


def _definition(value):
    fields(value, {"type", "default"}, {"minimum", "maximum", "values", "maxLength"})
    kind = value["type"]
    if kind == "boolean":
        fields(value, {"type", "default"})
        schema = BOOLEAN
    elif kind == "integer":
        fields(value, {"type", "default", "minimum", "maximum"})
        minimum = integer(value["minimum"], 0, 1000000)
        schema = (kind, minimum, integer(value["maximum"], minimum, 1000000))
    elif kind == "enum":
        fields(value, {"type", "default", "values"})
        values = value["values"]
        require(type(values) is list and 1 <= len(values) <= 32)
        for item in values:
            text(item, 1, 64, public=True)
        require(len(set(values)) == len(values))
        schema = (kind, tuple(values))
    else:
        require(kind == "string")
        fields(value, {"type", "default", "maxLength"})
        schema = (kind, 0, integer(value["maxLength"], 1, 4096))
    _field(value["default"], schema)
    return schema


def _binding(value, schema, definitions, parameters):
    if type(value) is not dict:
        return _field(value, schema)
    fields(value, {"param"})
    name = identifier(value["param"])
    require(name in definitions)
    parameter = definitions[name]
    # Validate the whole declared domain, even when the selected/default value
    # happens to fit. Narrow parameter declarations cannot hide unsafe values.
    if parameter[0] == "enum":
        for item in parameter[1]:
            _field(item, schema)
    else:
        require(parameter[0] == schema[0])
        if parameter[0] in ("integer", "string"):
            require(schema[1] <= parameter[1] and parameter[2] <= schema[2])
    return _field(parameters[name], schema)


def resolve(body, inputs):
    require(len(canonical(body)) <= 128 * 1024, "RESOURCE_LIMIT")

    def tree(value, depth=0):
        require(depth <= 12)
        if type(value) is str:
            text(value, maximum=128 * 1024, public=True)
        elif type(value) is dict:
            for key, child in value.items():
                text(key, maximum=128 * 1024, public=True)
                tree(child, depth + 1)
        elif type(value) is list:
            for child in value:
                tree(child, depth + 1)

    tree(body)
    # Match foundation normalization before calculating resolved parameters.
    import json
    body = json.loads(canonical(body))
    fields(body, {"format", "environment", "parameters", "steps"})
    require(type(body["format"]) is int and body["format"] == 1)
    require(body["environment"] == ENVIRONMENT)
    raw = body["parameters"]
    require(type(raw) is dict and len(raw) <= 32)
    definitions = {identifier(name): _definition(value) for name, value in raw.items()}
    require(type(inputs) is dict and inputs.keys() <= definitions.keys())
    parameters = {name: _field(inputs.get(name, raw[name]["default"]), schema)
                  for name, schema in definitions.items()}
    steps = body["steps"]
    require(type(steps) is list and len(steps) <= 32)
    identifiers, resources, desired = set(), set(), []
    for step in steps:
        require(type(step) is dict)
        step_id = identifier(step.get("id"))
        require(step_id not in identifiers)
        identifiers.add(step_id)
        kind = step.get("kind")
        resolved = copy.deepcopy(step)
        if kind == "service":
            fields(step, {"id", "kind", "resourceId", "state"}, {"enabled"})
            resource = step["resourceId"]
            require(type(resource) is str and resource in UNITS)
            resolved["state"] = _binding(step["state"], SERVICE, definitions, parameters)
            if "enabled" in step:
                resolved["enabled"] = _binding(step["enabled"], BOOLEAN, definitions, parameters)
        elif kind == "config_file":
            fields(step, {"id", "kind", "resourceId", "values"})
            resource = step["resourceId"]
            require(type(resource) is str and resource in CONFIG_FIELDS)
            schema = CONFIG_FIELDS[resource]
            fields(step["values"], set(schema))
            resolved["values"] = {name: _binding(step["values"][name], field, definitions, parameters)
                                  for name, field in schema.items()}
        else:
            require(kind == "install_recipe")
            fields(step, {"id", "kind", "recipeDigest", "version"})
            resource = "recipe:" + sha(step["recipeDigest"])
            resolved["version"] = _binding(step["version"], ("string", 1, 256), definitions, parameters)
        require(resource not in resources)
        resources.add(resource)
        desired.append(resolved)
    return parameters, desired


def render(resource, values):
    require(resource in CONFIG_FIELDS)
    fields(values, set(CONFIG_FIELDS[resource]))
    for name, schema in CONFIG_FIELDS[resource].items():
        _field(values[name], schema)
    if resource == "system.motd":
        output = values["text"].rstrip("\n") + "\n"
    elif resource == "postgresql.settings":
        output = (f"max_connections = {values['max_connections']}\n"
                  f"shared_buffers = '{values['shared_buffers_mb']}MB'\n")
    else:
        output = ("<clickhouse>\n"
                  f"  <max_connections>{values['max_connections']}</max_connections>\n"
                  "  <max_server_memory_usage>"
                  f"{values['max_server_memory_usage_mb'] * 1024 * 1024}"
                  "</max_server_memory_usage>\n</clickhouse>\n")
    return output.encode("utf-8")


@dataclass(frozen=True)
class Program:
    parameters: dict
    desired: list
    effects: list
    checks: list


def compile_profile(body, inputs, baseline_fingerprints, recipes):
    """recipes must come from the verified root catalog, never request fields."""
    parameters, desired = resolve(body, inputs)
    effects, checks, occupied = [], [], set()

    def effect(source, kind, **values):
        result = {"id": f"e{len(effects) + 1}", "sourceStepId": source,
                  "kind": kind, **values}
        effects.append(result)
        require(len(effects) <= 32, "RESOURCE_LIMIT")
        return result

    def check(item, kind, resource=None, **values):
        checks.append({"id": f"c{len(checks) + 1}", "effectId": item["id"],
                       "resourceId": resource or item["resourceId"], "kind": kind, **values})

    def service(source, resource, state):
        fingerprint = sha(baseline_fingerprints.get(resource))
        item = effect(source, "service_state", resourceId=resource, state=state)
        check(item, "service_state", state="inactive" if state == "stopped" else "active")
        if state == "restarted":
            check(item, "service_restarted", baselineFingerprint=fingerprint)
        if state != "stopped":
            check(item, "sql", expected=1)

    for step in desired:
        source, kind = step["id"], step["kind"]
        if kind == "install_recipe":
            recipe = recipes.get(step["recipeDigest"])
            require(type(recipe) is dict, "QUALIFICATION_REQUIRED")
            require(recipe["digest"] == step["recipeDigest"] and recipe["version"] == step["version"])
            resources = set(recipe["ownedResources"])
            require(resources.isdisjoint(occupied))
            occupied.update(resources)
            item = effect(source, kind, recipeDigest=recipe["digest"], version=recipe["version"])
            check(item, "recipe", resource="recipe." + recipe["id"], recipeDigest=recipe["digest"])
            continue
        resource = step["resourceId"]
        require(resource not in occupied)
        occupied.add(resource)
        sha(baseline_fingerprints.get(resource))
        if kind == "config_file":
            rendered = hashlib.sha256(render(resource, step["values"])).hexdigest()
            item = effect(source, kind, resourceId=resource, values=step["values"], renderedDigest=rendered)
            check(item, "file_digest", digest=rendered)
            if resource != "system.motd":
                check(item, "settings", values=step["values"])
                service(source, resource.replace(".settings", ".service"), "restarted")
        else:
            service(source, resource, step["state"])
            if "enabled" in step:
                item = effect(source, "service_enabled", resourceId=resource, enabled=step["enabled"])
                check(item, "service_enabled", enabled=step["enabled"])
    return Program(parameters, desired, effects, checks)


def recipe_files(recipe):
    """Literal initial local-only configuration, frozen with recipe defaults."""
    prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
    settings = render(prefix + ".settings", recipe["initialSettings"]).decode("utf-8")
    if prefix == "postgresql":
        parent = ("data_directory = '/var/lib/postgresql/16/main'\n"
                  "hba_file = '/etc/postgresql/16/main/pg_hba.conf'\n"
                  "ident_file = '/etc/postgresql/16/main/pg_ident.conf'\n"
                  "external_pid_file = '/var/run/postgresql/16-main.pid'\n"
                  "listen_addresses = '127.0.0.1'\nport = 5432\n"
                  "unix_socket_directories = '/var/run/postgresql'\n"
                  "include_dir = 'conf.d'\n")
        return {"/etc/postgresql/16/main/postgresql.conf": (parent, "0644", "root"),
            "/etc/postgresql/16/main/pg_hba.conf":
                ("local all all peer\nhost all all 127.0.0.1/32 reject\nhost all all ::1/128 reject\n", "0640", "postgres"),
            "/etc/postgresql/16/main/pg_ident.conf": ("# ServerDeck local peer identity\n", "0644", "root"),
            "/etc/postgresql/16/main/start.conf": ("auto\n", "0644", "root"),
            "/etc/postgresql/16/main/pg_ctl.conf": ("# ServerDeck canonical cluster\n", "0644", "root"),
            PATHS["postgresql.settings"]: (settings, "0644", "root")}
    parent = ("<clickhouse>\n"
        "  <logger><level>warning</level><console>1</console></logger>\n"
        "  <listen_host>127.0.0.1</listen_host>\n"
        "  <http_port>8123</http_port><tcp_port>9000</tcp_port>\n"
        "  <path>/var/lib/clickhouse/</path><tmp_path>/var/lib/clickhouse/tmp/</tmp_path>\n"
        "  <users_config>/etc/clickhouse-server/users.xml</users_config>\n"
        "  <default_profile>default</default_profile><default_database>default</default_database>\n"
        "  <timezone>UTC</timezone>\n</clickhouse>\n")
    users = ("<clickhouse>\n"
        "  <profiles><default><readonly>1</readonly></default></profiles>\n"
        "  <users><default><password></password><networks><ip>127.0.0.1</ip></networks>\n"
        "    <profile>default</profile><quota>default</quota></default></users>\n"
        "  <quotas><default><interval><duration>3600</duration><queries>0</queries>\n"
        "    <errors>0</errors><result_rows>0</result_rows><read_rows>0</read_rows>\n"
        "    <execution_time>0</execution_time></interval></default></quotas>\n</clickhouse>\n")
    return {"/etc/clickhouse-server/config.xml": (parent, "0644", "root"),
            "/etc/clickhouse-server/users.xml": (users, "0644", "root"),
            PATHS["clickhouse.settings"]: (settings, "0644", "root")}


def playbook(effect, recipes, *, registry_digest=None):
    """Exactly one effect per literal JSON play. No implicit continuation."""
    kind = effect["kind"]
    if kind == "config_file":
        content = render(effect["resourceId"], effect["values"])
        require(hashlib.sha256(content).hexdigest() == effect["renderedDigest"], "CONFLICT")
        module, arguments = "ansible.builtin.copy", {
            "dest": PATHS[effect["resourceId"]], "content": content.decode("utf-8"),
            "owner": "root", "group": "root", "mode": "0644", "follow": False,
            "force": True, "backup": False, "unsafe_writes": False}
    elif kind in ("service_state", "service_enabled"):
        module, arguments = "ansible.builtin.systemd_service", {
            "name": UNITS[effect["resourceId"]], "scope": "system",
            "daemon_reload": False, "daemon_reexec": False, "no_block": False}
        arguments.update({"state": effect["state"]} if kind == "service_state"
                         else {"enabled": effect["enabled"]})
    else:
        require(kind == "install_recipe")
        recipe = recipes.get(effect["recipeDigest"])
        require(recipe is not None and recipe["version"] == effect["version"], "QUALIFICATION_REQUIRED")
        module, arguments = "ansible.builtin.apt", {
            "name": [f"{p['name']}:{p['architecture']}={p['version']}" for p in recipe["packagePins"]],
            "auto_install_module_deps": False, "update_cache": False,
            "cache_valid_time": 0, "force_apt_get": True, "allow_downgrade": False,
            "allow_unauthenticated": False, "allow_change_held_packages": False,
            "fail_on_autoremove": True, "autoremove": False, "autoclean": False,
            "clean": False, "lock_timeout": 1, "state": "present"}
    tasks = [{"name": effect["id"], module: arguments}]
    if kind == "install_recipe":
        sha(registry_digest)
        tasks[0]["environment"] = {"DEBIAN_FRONTEND": "noninteractive", "UCF_FORCE_CONFFOLD": "1"}
        prefix = "postgresql" if recipe["id"] == "postgresql16" else "clickhouse"
        directories = (["/etc/postgresql", "/etc/postgresql/16", "/etc/postgresql/16/main",
                        "/etc/postgresql/16/main/conf.d"] if prefix == "postgresql" else
                       ["/etc/clickhouse-server", "/etc/clickhouse-server/config.d", "/etc/clickhouse-server/users.d"])
        for path in directories:
            tasks.append({"name": "Protect owned configuration directory", "ansible.builtin.file": {
                "path": path, "state": "directory", "owner": "root", "group": "root",
                "mode": "0755", "follow": False, "recurse": False}})
        for path, (content, mode, group) in recipe_files(recipe).items():
            tasks.append({"name": "Write initial local-only configuration", "ansible.builtin.copy": {
                "dest": path, "content": content, "owner": "root", "group": group, "mode": mode,
                "follow": False, "force": True, "backup": False, "unsafe_writes": False}})
        tasks.append({"name": "Verify prepared recipe before service start", "ansible.builtin.command": {
            "argv": ["/usr/lib/serverdeck-executor/recipe-check", recipe["digest"], registry_digest]},
            "changed_when": False})
        tasks.append({"name": "Start owned local-only database", "ansible.builtin.systemd_service": {
            "name": UNITS[prefix + ".service"], "scope": "system", "state": "started", "enabled": True,
            "daemon_reload": False, "daemon_reexec": False, "no_block": False}})
    return [{"name": "ServerDeck single admitted effect", "hosts": "localhost",
             "connection": "local", "gather_facts": False, "become": False,
             "vars": {"ansible_python_interpreter": "/usr/bin/python3"},
             "tasks": tasks}]


def compiler_digest():
    from pathlib import Path
    return digest({name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                   for name in ("codec.py", "compiler.py")})
