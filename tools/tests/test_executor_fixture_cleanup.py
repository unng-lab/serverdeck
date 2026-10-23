"""Exercise the real fixture shell's cleanup after a failed Docker start.

The Docker command is a local stub. This checks harness control flow only;
it provides no Docker, executor, Ansible, or MCP runtime qualification.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FixtureCleanupTest(unittest.TestCase):
    def test_failed_start_removes_retained_container_and_image(self):
        bash = shutil.which("bash")
        if os.name == "nt":
            candidate = Path("C:/Program Files/Git/bin/bash.exe")
            bash = str(candidate) if candidate.is_file() else None
        if not bash:
            self.skipTest("Bash is required for the fixture shell regression")
        repository = Path(__file__).resolve().parents[2]
        nonce = "c" * 32
        container = "a" * 64
        image = "sha256:" + "b" * 64
        with tempfile.TemporaryDirectory(prefix="serverdeck-fixture-cleanup-") as root:
            directory = Path(root)
            trace = directory / "trace"
            (directory / "python3").write_text(
                f"#!/usr/bin/env bash\nprintf '%s\\n' '{nonce}'\n",
                encoding="utf-8",
            )
            (directory / "docker").write_text(
                "#!/usr/bin/env bash\n"
                "set -eu\n"
                'printf "%s\\n" "$*" >> "$FIXTURE_TRACE"\n'
                'case "$1" in\n'
                "  build) exit 0 ;;\n"
                f"  create) printf '%s\\n' '{container}' ;;\n"
                "  start) exit 47 ;;\n"
                "  inspect)\n"
                '    if [[ "$3" == *serverdeck.fixtureId* ]]; then\n'
                f"      printf '%s\\n' '{nonce}'\n"
                "    else\n"
                f"      printf '%s\\n' '{image}'\n"
                "    fi ;;\n"
                "  rm) exit 0 ;;\n"
                "  image)\n"
                '    if [[ "$2" == rm ]]; then exit 0; fi\n'
                '    if [[ "$4" == *serverdeck.fixtureId* ]]; then\n'
                f"      printf '%s\\n' '{nonce}'\n"
                "    else\n"
                f"      printf '%s\\n' '{image}'\n"
                "    fi ;;\n"
                "  *) exit 99 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            for name in ("docker", "python3"):
                (directory / name).chmod(0o700)
            environment = dict(os.environ)
            environment["FIXTURE_TRACE"] = trace.as_posix()
            result = subprocess.run(
                [bash, "-c", 'export PATH="$(cd "$1" && pwd):$PATH"; '
                 'exec bash tools/test-executor-container.sh',
                 "fixture-cleanup-test", directory.as_posix()],
                cwd=repository,
                env=environment,
                capture_output=True,
                timeout=20,
                check=False,
            )
            self.assertEqual(result.returncode, 47, result.stderr)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(result.stderr, b"")
            calls = trace.read_text(encoding="utf-8").splitlines()
            self.assertEqual(sum(line.startswith("create ") for line in calls), 1)
            self.assertIn(f"start {container}", calls)
            self.assertIn(f"rm -f {container}", calls)
            self.assertIn(f"image rm serverdeck-executor-ci-{nonce}:test", calls)
            self.assertLess(calls.index(f"start {container}"),
                            calls.index(f"rm -f {container}"))
            self.assertFalse(any(line.startswith("exec ") for line in calls))


if __name__ == "__main__":
    unittest.main()
