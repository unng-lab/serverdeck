"""Independent stdlib JSON-RPC client over the actual bundled MCP executable."""
import json
import logging
import os
import queue
import subprocess
import sys
import threading
import time

from common import LIMIT, configuration, controls, emit, failed


class WireClient:
    def __init__(self, config, scanner):
        allowed = {"SYSTEMROOT", "SYSTEMDRIVE", "WINDIR", "LOCALAPPDATA", "USERPROFILE",
                   "APPDATA", "TEMP", "TMP", "PATH", "PATHEXT"}
        self.process = subprocess.Popen([config["command"], *config["args"]],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={key: value for key, value in os.environ.items() if key.upper() in allowed},
            creationflags=subprocess.CREATE_NO_WINDOW)
        self.scanner, self.messages = scanner, queue.Queue(maxsize=16)
        self.error_reader = scanner.drain(self.process.stderr)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        try:
            while line := self.process.stdout.readline(LIMIT + 1):
                if len(line) > LIMIT or not line.endswith(b"\n"):
                    raise ValueError("ACTOR_LIMIT")
                self.scanner.check(line)
                self.messages.put(json.loads(line), timeout=45)
        except Exception:
            self.scanner.failed = True
        finally:
            try:
                self.messages.put(None, timeout=1)
            except queue.Full:
                pass

    def send(self, document):
        raw = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(raw) > 256 * 1024:
            raise ValueError("ACTOR_LIMIT")
        self.process.stdin.write(raw + b"\n")
        self.process.stdin.flush()

    def call(self, identifier, method, params):
        self.send({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params})
        until = time.monotonic() + 45
        for _ in range(64):
            response = self.messages.get(timeout=max(.001, until - time.monotonic()))
            if response is None or response.get("jsonrpc") != "2.0":
                raise ValueError("ACTOR_PROTOCOL")
            if response.get("id") == identifier:
                if ("result" in response) == ("error" in response):
                    raise ValueError("ACTOR_PROTOCOL")
                return response
            if "id" in response or not str(response.get("method", "")).startswith("notifications/"):
                raise ValueError("ACTOR_PROTOCOL")
        raise ValueError("ACTOR_PROTOCOL")

    def close(self):
        self.process.stdin.close()
        try:
            code = self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
            raise ValueError("ACTOR_SHUTDOWN")
        finally:
            self.reader.join(timeout=2)
            self.error_reader.join(timeout=2)
            self.process.stdout.close()
        if code != 0 or self.reader.is_alive() or self.error_reader.is_alive() or self.scanner.failed:
            raise ValueError("ACTOR_SHUTDOWN")


def main():
    logging.disable(logging.CRITICAL)
    config, scanner = configuration()
    client = WireClient(config, scanner)
    try:
        initialized = client.call("initialize", "initialize", {"protocolVersion": "2025-11-25",
            "capabilities": {}, "clientInfo": {"name": "serverdeck-independent-wire", "version": "1"}})
        result = initialized.get("result", {})
        if result.get("protocolVersion") != "2025-11-25":
            raise ValueError("ACTOR_PROTOCOL")
        client.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        emit({"ready": True, "client": "stdlib-wire", "protocolVersion": result["protocolVersion"]}, scanner)
        for command in controls():
            emit(client.call(command["id"], command["method"], command.get("params", {})), scanner)
    finally:
        client.close()


if __name__ == "__main__":
    try:
        main()
    except BaseException:
        sys.exit(failed())
