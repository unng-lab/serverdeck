"""Smoke the compiled sidecar and its native storage library, without source runtimes."""
import argparse
import json
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.request import ProxyHandler, Request, build_opener


def check(executable):
    opener = build_opener(ProxyHandler({}))
    with tempfile.TemporaryDirectory(prefix="serverdeck-bundle-test-") as directory:
        data = Path(directory)
        for attempt in range(2):
            process = subprocess.Popen(
                [str(executable.resolve()), "--data-dir", directory],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                endpoint = data / "endpoint.json"
                deadline = time.monotonic() + 20
                while True:
                    if process.poll() is not None:
                        raise RuntimeError("Packaged locald exited before creating its endpoint")
                    if time.monotonic() > deadline:
                        raise TimeoutError("Packaged locald did not start")
                    if endpoint.exists():
                        try:
                            connection = json.loads(endpoint.read_text())
                            break
                        except (json.JSONDecodeError, FileNotFoundError):
                            pass  # Wait for the endpoint write to finish.
                    time.sleep(0.1)

                def call(operation, body=None):
                    request = Request(
                        f"http://127.0.0.1:{connection['port']}/v1/{operation}",
                        data=json.dumps(body or {}).encode(),
                        headers={
                            "Authorization": f"Bearer {connection['proof']}",
                            "Content-Type": "application/json",
                        },
                    )
                    with opener.open(request, timeout=5) as response:
                        return json.load(response)["data"]

                assert call("health")["service"] == "serverdeck"
                if attempt == 0:
                    call("settings/set", {"theme": "light", "updateAutoCheck": False})
                else:
                    assert call("settings/get") == {"theme": "light", "updateAutoCheck": False}
                call("service/stop")
                assert process.wait(timeout=10) == 0
                assert not endpoint.exists()
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=10)
        assert (data / "database/serverdeck.isar").is_file()
    print("PASS: packaged native locald, authenticated API, Isar reopen, graceful stop")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    check(parser.parse_args().executable)
