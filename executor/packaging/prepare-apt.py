#!/usr/bin/python3 -I
"""Explicit administrator preparation; never installed or reachable through MCP.

Only --refresh performs network metadata refresh. No package installation,
repository key download, service start or automatic version selection occurs.
"""
import argparse
import os
from pathlib import Path
import stat
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from serverdeck_executor.apt import APT_CONFIG, build_prepared_catalog
from serverdeck_executor.apt_gate import CONFIG, KEYRING, NO_START
from serverdeck_executor.codec import decode, fields, require, wire_bytes
from serverdeck_executor.journal import _file, _write_all, secure_directory
from serverdeck_executor.probes import command, regular_file

ROOT = Path('/etc/serverdeck-executor')
diagnostic_codes = False


def diagnostic_locations(error):
    """Public source identifiers only; never exception text, locals or inputs."""
    source = Path(__file__).resolve().parent.parent
    allowed = {source / 'packaging/prepare-apt.py': 'packaging/prepare-apt.py'}
    allowed.update({source / 'serverdeck_executor' / name:
                    'serverdeck_executor/' + name for name in
                    ('apt.py', 'apt_gate.py', 'codec.py', 'journal.py', 'probes.py')})
    result = []
    for frame in traceback.extract_tb(error.__traceback__):
        label = allowed.get(Path(frame.filename))
        if label is not None and 1 <= frame.lineno <= 99999:
            result.append('APT_PREPARE_LOCATION ' + label + ':' + str(frame.lineno))
    return result[-8:]


def write_fixed(path, data, mode=0o600, *, exclusive=False):
    """Create fixed protected inputs; existing different inputs are not reset."""
    path = Path(path)
    if not exclusive and os.path.lexists(path):
        actual, attributes = regular_file(path, maximum=2 * 1024 * 1024)
        require(actual == data and attributes == {'uid': 0, 'gid': 0, 'mode': mode},
                'QUALIFICATION_REQUIRED')
        return
    secure_directory(path.parent, mode=stat.S_IMODE(path.parent.lstat().st_mode))
    fd = _file(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        _write_all(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def source_bytes(path):
    import re
    raw = regular_file(path, maximum=64 * 1024)[0]
    entries = []
    for row in raw.decode('ascii').splitlines():
        row = row.strip()
        if not row or row.startswith('#'):
            continue
        require(re.fullmatch(
            r'deb \[signed-by=' + re.escape(KEYRING) + r'\] '
            r'https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?/[A-Za-z0-9._/~%-]* '
            r'[A-Za-z0-9._/-]+(?: [A-Za-z0-9 /-]+)?', row) is not None,
            'QUALIFICATION_REQUIRED')
        require(row not in entries, 'QUALIFICATION_REQUIRED')
        entries.append(row)
    require(1 <= len(entries) <= 16, 'QUALIFICATION_REQUIRED')
    return ('\n'.join(entries) + '\n').encode('ascii')


def main():
    global diagnostic_codes
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--keyring', type=Path, required=True)
    parser.add_argument('--request', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--refresh', action='store_true')
    parser.add_argument('--diagnostic-codes', action='store_true')
    args = parser.parse_args()
    diagnostic_codes = args.diagnostic_codes
    require(os.geteuid() == 0 and sys.platform == 'linux' and
            sys.version_info[:2] == (3, 12), 'FORBIDDEN')
    sources = source_bytes(args.sources)
    keyring = regular_file(args.keyring, maximum=2 * 1024 * 1024)[0]
    require(keyring, 'QUALIFICATION_REQUIRED')
    request = decode(regular_file(args.request, maximum=64 * 1024)[0], 64 * 1024)
    fields(request, {'format', 'recipes'})
    require(type(request['format']) is int and request['format'] == 1 and
            type(request['recipes']) is list and 1 <= len(request['recipes']) <= 2)
    output = args.output.absolute()
    secure_directory(output.parent)
    require(not os.path.lexists(output), 'ALREADY_EXISTS')
    secure_directory(ROOT)
    write_fixed(CONFIG, APT_CONFIG)
    write_fixed(ROOT / 'sources.list', sources)
    # APT's _apt signature verifier must read its public trust anchor. Private
    # configuration, enrollment and journal directories remain root0700.
    secure_directory(Path(KEYRING).parent, mode=0o755)
    write_fixed(KEYRING, keyring, 0o644)
    write_fixed('/usr/sbin/policy-rc.d', NO_START, 0o755)
    secure_directory(ROOT / 'gnupg-empty')
    require(not any((ROOT / 'gnupg-empty').iterdir()), 'QUALIFICATION_REQUIRED')
    if args.refresh:
        # APT_CONFIG is read first; fixed Dir::Etc disables ambient apt snippets.
        # Error-Mode=any makes even a partial repository update fail closed.
        command(['/usr/bin/env', 'APT_CONFIG=' + CONFIG, '/usr/bin/apt-get',
                 '-o', 'APT::Update::Error-Mode=any', 'update'],
                maximum=1024 * 1024, timeout=120)
    catalog = build_prepared_catalog(request)
    write_fixed(output, wire_bytes(catalog), exclusive=True)
    print('Pinned catalog prepared; installation qualification remains required.')


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        if diagnostic_codes:
            for location in diagnostic_locations(error):
                print(location, file=sys.stderr)
        print('APT preparation refused; private root inputs retained.', file=sys.stderr)
        sys.exit(1)
