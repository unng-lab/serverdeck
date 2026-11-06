"""Prepare bounded GitHub catalog payload from an audited publishable installer."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import time

_spec = importlib.util.spec_from_file_location('installer_packaging', Path(__file__).with_name('package-installer.py'))
packaging = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(packaging)


def _integer(value, maximum):
    if type(value) is not int or not 0 < value <= maximum:
        raise ValueError('Invalid catalog integer')
    return value


def _identity(value):
    _integer(value['size'], packaging.ARTIFACT_LIMIT)
    if not isinstance(value['sha256'], str) or not re.fullmatch('[0-9a-f]{64}', value['sha256']):
        raise ValueError('Invalid artifact hash')
    return value


def _number(text, maximum):
    if not re.fullmatch('[1-9][0-9]*', text):
        raise ValueError('Noncanonical catalog integer')
    return _integer(int(text), maximum)


def _url(version):
    return f'https://github.com/unng-lab/serverdeck/releases/download/v{version.replace("+", "%2B")}/ServerDeckSetup.exe'


def _previous(payload, version, issued):
    if payload is None:
        return []
    if not 0 < len(payload) <= 131072 or not payload.endswith(b'\n') or b'\r' in payload or b'\0' in payload:
        raise ValueError('Invalid previous catalog payload')
    lines = payload.decode('ascii').split('\n')[:-1]
    if len(lines) < 3 or lines[0] != 'SDRELEASES002':
        raise ValueError('Previous static catalog required')
    old_issued = _number(lines[1], issued + 300)
    count = _number(lines[2], 31)
    if len(lines) != 3 + count * 11:
        raise ValueError('Invalid previous catalog count')
    records, seen = [], set()
    for offset in range(3, len(lines), 11):
        row = lines[offset:offset + 11]
        target = packaging.version_tuple(row[0])
        if target >= packaging.version_tuple(version) or row[0] in seen:
            raise ValueError('Release versions are immutable and must increase')
        seen.add(row[0])
        if row[1] != 'windows-x64' or row[2] != '1' or row[9] != _url(row[0]):
            raise ValueError('Invalid previous release target')
        _number(row[3], 0xffffffff)
        _number(row[4], min(old_issued, issued))
        for size, digest in [(row[5], row[6]), (row[7], row[8])]:
            _identity({'size': _number(size, packaging.ARTIFACT_LIMIT), 'sha256': digest})
        notes = base64.b64decode(row[10], validate=True)
        if len(notes) > 16384 or b'\0' in notes:
            raise ValueError('Invalid previous notes')
        notes.decode('utf-8')
        records.append(row)
    return records


def prepare(setup, audit, policy_bytes, notes_bytes, issued, previous=None, reader=None, identity_reader=None):
    version = audit['version']
    packaging.version_tuple(version)
    _integer(issued, 253402300799)
    if audit['profile'] != 'publishable':
        raise ValueError('Developer installers must not be released')
    setup = Path(setup)
    if setup.is_symlink() or setup.is_junction() or not setup.is_file():
        raise ValueError('Regular final installer required')
    packaging._validate_pe(setup)
    expected, app = _identity(audit['setup']), _identity(audit['application'])
    with setup.open('rb') as stream:
        actual = {'size': setup.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
    if expected != actual:
        raise ValueError('Final installer differs from audited bytes')
    policy = json.loads(policy_bytes)
    canonical = packaging.canonical_policy(policy_bytes, policy['storeFormat'], publishable=True)
    read = reader or packaging.resource_bytes
    if read(setup, 'SERVERDECK_TRUST_V1') != canonical:
        raise ValueError('Installer trust differs from publishing policy')
    if (identity_reader or packaging.resource_identity)(setup, 'SERVERDECK_APPLICATION_V1') != app:
        raise ValueError('Embedded application differs from audit')
    manifest = f"SDSETUP001\n{version}\n{app['size']}\n{app['sha256']}\n".encode('ascii')
    if read(setup, 'SERVERDECK_SETUP_V1') != manifest:
        raise ValueError('Installer version differs from audit')
    packaging._as_invoker(read(setup, 1, 24))
    if not 0 < len(notes_bytes) <= 16384 or b'\0' in notes_bytes:
        raise ValueError('Release notes must be nonempty UTF8, at most16KiB')
    notes = notes_bytes.decode('utf-8-sig').strip().encode('utf-8')
    if not notes:
        raise ValueError('Release notes are empty')
    rows = _previous(previous, version, issued)
    current = [version, 'windows-x64', '1', str(policy['storeFormat']), str(issued), str(expected['size']),
               expected['sha256'], str(app['size']), app['sha256'], _url(version), base64.b64encode(notes).decode('ascii')]
    fields = ['SDRELEASES002', str(issued), str(1 + len(rows)), *current]
    for row in rows:
        fields.extend(row)
    result = ('\n'.join(fields) + '\n').encode('ascii')
    if len(result) > 131072 - 180:
        raise ValueError('Catalog exceeds envelope limit; explicitly retire old releases')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['installer', 'audit', 'policy', 'notes', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--previous-payload', type=Path)
    args = parser.parse_args()
    payload = prepare(args.installer, json.loads(args.audit.read_bytes()), args.policy.read_bytes(), args.notes.read_bytes(),
                      int(time.time()), args.previous_payload.read_bytes() if args.previous_payload else None)
    args.output.write_bytes(payload)


if __name__ == '__main__':
    main()
