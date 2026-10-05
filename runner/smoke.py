"""Linux Runner compatibility smoke: localhost assertions only, no remote host."""
import importlib.metadata
import json
import os
from pathlib import Path
import tempfile

import ansible_runner


def main():
    Path(os.environ["HOME"]).mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="serverdeck-smoke-") as directory:
        project = Path(directory) / "project"
        project.mkdir()
        (project / "smoke.yml").write_text("""---
- name: ServerDeck dependency smoke (no host writes)
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Verify pinned controller version
      ansible.builtin.assert:
        that:
          - ansible_version.full == '2.21.4'
        quiet: true
""", encoding="utf-8")
        result = ansible_runner.run(
            private_data_dir=directory, playbook="smoke.yml", quiet=True,
            envvars={"ANSIBLE_LOCAL_TEMP": str(Path(directory) / "ansible-tmp"),
                     "ANSIBLE_HOST_KEY_CHECKING": "True"},
        )
        print(json.dumps({
            "scope": "localhost assertion only; no SSH or package writes",
            "ansible_core": importlib.metadata.version("ansible-core"),
            "ansible_runner": importlib.metadata.version("ansible-runner"),
            "status": result.status, "rc": result.rc,
            "event_count": sum(1 for _ in result.events),
        }))
        if result.status != "successful" or result.rc != 0:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
