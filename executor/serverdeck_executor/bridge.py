"""Fixed no-argument sudo bridge, stdin/stdout framed JSON only."""

import os
import socket
import sys

from .codec import Rejected, fields, read_frame, require, write_frame

SOCKET = "/run/serverdeck-executor/control.sock"


def main():
    require(os.geteuid() == 0 and len(sys.argv) == 1, "FORBIDDEN")
    raw = os.environ.get("SUDO_UID", "")
    require(raw.isascii() and raw.isdecimal() and len(raw) <= 10, "FORBIDDEN")
    uid = int(raw)
    require(0 < uid <= 4294967294, "FORBIDDEN")
    # One root socket stream per SSH bridge. The supervisor binds fresh step
    # challenges to this exact stream; no session identifier comes from AI.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(SOCKET)
        with connection.makefile("rwb", buffering=0) as stream:
            while True:
                # Idle SSH streams may remain open. Individual supervisor IO
                # requests have their own bounded deadline.
                marker = sys.stdin.buffer.peek(1)
                if not marker:
                    return
                request = read_frame(sys.stdin.buffer)
                fields(request, {"v", "id", "method", "params"})
                write_frame(stream, {"uid": uid, "request": request}, maximum=256 * 1024 + 4096)
                response = read_frame(stream, maximum=8 * 1024 * 1024)
                write_frame(sys.stdout.buffer, response)


if __name__ == "__main__":
    try:
        main()
    except (Rejected, OSError, EOFError):
        # Never echo rejected private input, arbitrary stderr or a traceback.
        sys.exit(1)
