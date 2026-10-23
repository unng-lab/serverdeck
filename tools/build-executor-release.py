#!/usr/bin/env python3
"""Generate the nonsecret executor descriptor for the native release bundle."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "executor"))
from serverdeck_executor import RUNTIME_VERSION
from serverdeck_executor.codec import digest
from serverdeck_executor.compiler import compiler_digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    output = parser.parse_args().output
    source = ROOT / "executor"
    names = {"__init__.py", "codec.py", "compiler.py", "journal.py", "probes.py", "runner.py",
             "jobs.py", "preflight.py", "bridge.py", "supervisor.py", "qualification.py", "apt.py", "apt_gate.py"}
    files = {name: hashlib.sha256((source / "serverdeck_executor" / name).read_bytes()).hexdigest()
             for name in sorted(names)}
    program = {"baseVersion": RUNTIME_VERSION,
               "lockDigest": hashlib.sha256((source / "requirements.lock").read_bytes()).hexdigest(),
               "bridgeDigest": hashlib.sha256((source / "packaging/serverdeck-executor-bridge").read_bytes()).hexdigest(),
               "files": files}
    descriptor = {"format": 1, "runtimeVersion": RUNTIME_VERSION + "+" + digest(program),
                  "lockDigest": program["lockDigest"], "bridgeDigest": program["bridgeDigest"],
                  "compilerDigest": compiler_digest(), "files": files}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(descriptor, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
