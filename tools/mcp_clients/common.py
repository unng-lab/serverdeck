"""Private fixture actor controls; no ServerDeck implementation is imported."""
import json
import os
from pathlib import Path
import re
import threading

LIMIT = 8 * 1024 * 1024


def configuration():
    import sys
    raw = sys.stdin.buffer.readline(65537)
    if not raw.endswith(b"\n") or len(raw) > 65536:
        raise ValueError("ACTOR_CONFIGURATION")
    value = json.loads(raw)
    command = Path(value["command"])
    root = command.parent.parent
    repository = Path(__file__).resolve().parents[2]
    if (os.name != "nt" or not command.is_absolute() or command.name != "mcp.exe" or
            command.parent.name != "application bundle" or
            root.parent.resolve() != (repository / ".local").resolve() or
            re.fullmatch(r"mcp-acceptance-[a-f0-9]{32}", root.name) is None):
        raise ValueError("OWNED_FIXTURE_REQUIRED")
    for parent in [root, *root.parents, command.parent, command]:
        if parent.is_symlink() or parent.is_junction():
            raise ValueError("OWNED_FIXTURE_REQUIRED")
    if Path(os.environ.get("LOCALAPPDATA", "")).absolute() != root / "profile":
        raise ValueError("OWNED_FIXTURE_REQUIRED")
    manifest = json.loads((root / "fixture.json").read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or manifest.get("fixtureId") != root.name.removeprefix("mcp-acceptance-"):
        raise ValueError("OWNED_FIXTURE_REQUIRED")
    args = value["args"]
    if not (args == [] or len(args) == 4 and args[0] == "--app-root" and
            Path(args[1]) == command.parent and args[2] == "--grant-id" and
            re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", args[3])):
        raise ValueError("ACTOR_CONFIGURATION")
    markers = value.get("markers", [])
    if not isinstance(markers, list) or len(markers) > 32 or any(
            not isinstance(marker, str) or not 8 <= len(marker) <= 4096 for marker in markers):
        raise ValueError("ACTOR_CONFIGURATION")
    return value, Scanner(markers)


class Scanner:
    def __init__(self, markers):
        self.markers = [marker.encode("utf-8") for marker in markers]
        self.failed = False

    def check(self, data):
        if self.failed or any(marker in data for marker in self.markers):
            self.failed = True
            raise ValueError("ACTOR_SECRET_LEAK")

    def drain(self, stream):
        def work():
            tail, count = b"", 0
            try:
                while chunk := stream.read(8192):
                    count += len(chunk)
                    if count > 256 * 1024:
                        self.failed = True
                    try:
                        self.check(tail + chunk)
                    except ValueError:
                        pass
                    tail = (tail + chunk)[-4096:]
            finally:
                stream.close()
        thread = threading.Thread(target=work, daemon=True)
        thread.start()
        return thread


def emit(value, scanner):
    import sys
    raw = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(raw) > LIMIT:
        raise ValueError("ACTOR_LIMIT")
    scanner.check(raw)
    sys.stdout.buffer.write(raw + b"\n")
    sys.stdout.buffer.flush()


def controls():
    import sys
    while line := sys.stdin.buffer.readline(256 * 1024 + 1):
        if len(line) > 256 * 1024 or not line.endswith(b"\n"):
            raise ValueError("ACTOR_LIMIT")
        value = json.loads(line)
        if value.get("method") not in ("tools/list", "tools/call", "ping") or not isinstance(value.get("id"), str):
            raise ValueError("ACTOR_CONTROL")
        yield value


def failed():
    import sys
    # Fixed output only. Parent never receives a traceback or raw failed input.
    sys.stderr.write("MCP_ACTOR_FAILED\n")
    sys.stderr.flush()
    return 1
