#!/usr/bin/python3 -I
"""Explicit root-only catalog generation from already prepared signed APT data."""

import argparse
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from serverdeck_executor.apt import build_prepared_catalog
from serverdeck_executor.codec import decode, require, wire_bytes
from serverdeck_executor.journal import _file, _write_all, secure_directory
from serverdeck_executor.probes import regular_file


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(os.geteuid() == 0 and sys.platform == "linux" and sys.version_info[:2] == (3, 12), "FORBIDDEN")
    request = decode(regular_file(args.request, maximum=64 * 1024)[0], 64 * 1024)
    catalog = build_prepared_catalog(request)
    output = args.output.absolute()
    secure_directory(output.parent)
    descriptor = _file(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    try:
        _write_all(descriptor, wire_bytes(catalog))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    directory = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
    print("Pinned catalog created; runtime qualification is still required.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Catalog preparation refused; inspect root prerequisites and exact versions.", file=sys.stderr)
        sys.exit(1)
