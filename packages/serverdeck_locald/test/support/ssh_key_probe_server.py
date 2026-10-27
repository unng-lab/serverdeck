"""Disposable real SSH handshake server; loopback only, ephemeral in-memory key."""
import base64
import hashlib
import json
import logging
import socket
import sys
import threading

import paramiko

if paramiko.__version__ != "5.0.0":
    raise SystemExit("FIXTURE_DEPENDENCY_MISMATCH")
logging.getLogger("paramiko").addHandler(logging.NullHandler())
logging.getLogger("paramiko").propagate = False
host_key = paramiko.RSAKey.generate(2048)
listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.bind(("127.0.0.1", 0))
listener.listen(8)
listener.settimeout(0.1)
stopped = threading.Event()
handshake = threading.Event()
if "--paused" not in sys.argv:
    handshake.set()
lock = threading.Lock()
active = set()
accepted = authentication = 0


class RejectAuthentication(paramiko.ServerInterface):
    def _reject(self):
        global authentication
        with lock:
            authentication += 1
        return paramiko.AUTH_FAILED

    def check_auth_none(self, username):
        return self._reject()

    def check_auth_password(self, username, password):
        return self._reject()

    def check_auth_publickey(self, username, key):
        return self._reject()


def connection(peer):
    transport = paramiko.Transport(peer)
    with lock:
        active.add(transport)
    try:
        while not handshake.wait(0.01):
            if stopped.is_set():
                return
        transport.add_server_key(host_key)
        transport.start_server(server=RejectAuthentication())
        while transport.is_active() and not stopped.wait(0.01):
            pass
    except (EOFError, OSError, paramiko.SSHException):
        pass
    finally:
        transport.close()
        with lock:
            active.discard(transport)


def accept():
    global accepted
    while not stopped.is_set():
        try:
            peer, _ = listener.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        with lock:
            accepted += 1
        threading.Thread(target=connection, args=(peer,), daemon=True).start()


threading.Thread(target=accept, daemon=True).start()
print(json.dumps({"port": listener.getsockname()[1], "key": {
    "format": "ssh-rsa", "fingerprint": "SHA256:" + base64.b64encode(
        hashlib.sha256(host_key.asbytes()).digest()).decode("ascii").rstrip("=")}}), flush=True)
try:
    for command in sys.stdin:
        if command.strip() == "stats":
            with lock:
                value = {"accepted": accepted, "authentication": authentication, "active": len(active)}
            print(json.dumps(value), flush=True)
        elif command.strip() == "close":
            break
        elif command.strip() == "release":
            handshake.set()
finally:
    stopped.set()
    listener.close()
    with lock:
        pending = list(active)
    for transport in pending:
        transport.close()
