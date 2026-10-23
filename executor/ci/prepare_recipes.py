#!/usr/bin/python3 -I
"""Prepare public recipe inputs in an owned disposable Docker, without installs.

This fixture helper is never installed or exposed through the executor/MCP.
The checked-in request selects exact versions. APT performs real signature and
dependency validation; downloading this pinned public key is not qualification.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import traceback
import urllib.request

SOURCE = Path('/opt/serverdeck-source')
OUTPUT = Path('/root/serverdeck-recipe-preparation')
GNUPG = Path('/root/serverdeck-recipe-gnupg')
KEY_URL = 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key'
KEY_SHA256 = '74c1dfd89393b27c5739ee579a5af661ebe628cef9c33222c6fb29d0b8d42ad0'
KEY_PRIMARY = '3A9EA1193A97B548BE1457D48919F6BD2B48D754'
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'HOME': '/root',
       'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'}
phase = 'fixture'


def diagnostic_locations(error):
    allowed = {Path(__file__).resolve(): 'ci/prepare_recipes.py'}
    allowed.update({SOURCE / 'serverdeck_executor' / name:
                    'serverdeck_executor/' + name for name in
                    ('apt.py', 'apt_gate.py', 'codec.py', 'journal.py', 'probes.py')})
    result = []
    for frame in traceback.extract_tb(error.__traceback__):
        label = allowed.get(Path(frame.filename))
        if label is not None and 1 <= frame.lineno <= 99999:
            result.append('RECIPE_PREPARE_LOCATION ' + label + ':' + str(frame.lineno))
    return result[-8:]


def check(value):
    if not value:
        raise ValueError('RECIPE_PREPARATION_REFUSED')


def command(arguments, *, data=None, maximum=1024 * 1024, timeout=30, preparation_diagnostics=False):
    result = subprocess.run(arguments, input=data, env=ENV, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE if preparation_diagnostics else subprocess.DEVNULL,
                            timeout=timeout, check=False)
    if preparation_diagnostics and result.returncode != 0:
        # Only the explicit administrator CLI's bounded public source positions.
        # Arbitrary stderr and exception messages are never forwarded.
        for line in result.stderr[:4096].decode('ascii', errors='ignore').splitlines()[:12]:
            if re.fullmatch(r'APT_PREPARE_LOCATION (?:packaging/prepare-apt|serverdeck_executor/(?:apt|apt_gate|codec|journal|probes))\.py:[0-9]{1,5}', line):
                print(line, file=sys.stderr)
    check(result.returncode == 0)
    check(len(result.stdout) <= maximum)
    return result.stdout


def source_inputs(read):
    """Hash the actual runtime and preparation chain through a custody reader."""
    result = {}
    names = ['serverdeck_executor/' + path.name
             for path in sorted((SOURCE / 'serverdeck_executor').glob('*.py'))]
    names += ['requirements.lock', 'packaging/serverdeck-executor-bridge',
              'packaging/prepare-apt.py', 'ci/Dockerfile', 'ci/prepare_recipes.py',
              'recipes/preparation-request.json', 'ci/apt.sources.list']
    for name in names:
        result[name] = hashlib.sha256(read(name, 2 * 1024 * 1024)).hexdigest()
    return result


def main():
    global phase
    fixture = os.environ.get('SERVERDECK_FIXTURE_ID', '')
    check(sys.platform == 'linux' and os.geteuid() == 0 and
          sys.version_info[:2] == (3, 12) and re.fullmatch('[a-f0-9]{32}', fixture) and
          Path('/.dockerenv').is_file() and
          Path('/proc/1/comm').read_bytes().strip() == b'systemd' and
          Path(__file__).resolve() == SOURCE / 'ci/prepare_recipes.py')
    sys.path.insert(0, str(SOURCE))
    from serverdeck_executor.codec import decode, digest, wire_bytes
    from serverdeck_executor.journal import _file, _write_all, secure_directory
    from serverdeck_executor.probes import package_snapshot, regular_file
    from serverdeck_executor.apt import _prepared_files, validate_catalog

    phase = 'fresh-output'
    check(not os.path.lexists(OUTPUT))
    secure_directory(OUTPUT)

    def write(name, data):
        target = OUTPUT / name
        check(target.parent == OUTPUT and re.fullmatch('[a-z0-9.-]+', name))
        fd = _file(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            _write_all(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)

    def source_bytes(relative, maximum):
        return regular_file(SOURCE / relative, maximum=maximum)[0]

    phase = 'public-key'
    request = urllib.request.Request(KEY_URL, headers={'User-Agent': 'curl/8.5.0'})
    with urllib.request.urlopen(request, timeout=20) as response:
        key = response.read(65537)
    check(0 < len(key) <= 65536 and hashlib.sha256(key).hexdigest() == KEY_SHA256)
    check(not os.path.lexists(GNUPG))
    secure_directory(GNUPG)
    key_info = command(['/usr/bin/gpg', '--homedir', str(GNUPG),
                        '--batch', '--no-options', '--show-keys', '--with-colons'], data=key)
    primary = None
    for row in key_info.decode('ascii').splitlines():
        columns = row.split(':')
        if columns[0] == 'fpr':
            primary = columns[9]
            break
    check(primary == KEY_PRIMARY)
    binary = command(['/usr/bin/gpg', '--homedir', str(GNUPG),
                      '--batch', '--no-options', '--dearmor'], data=key)
    ubuntu_keys = regular_file('/usr/share/keyrings/ubuntu-archive-keyring.gpg',
                               maximum=2 * 1024 * 1024)[0]
    write('clickhouse.asc', key)
    write('trusted.gpg', ubuntu_keys + binary)
    write('request.json', source_bytes('recipes/preparation-request.json', 64 * 1024))
    write('sources.list', source_bytes('ci/apt.sources.list', 64 * 1024))
    before = package_snapshot()
    phase = 'signed-metadata-and-resolution'
    command(['/usr/bin/python3', '-I', str(SOURCE / 'packaging/prepare-apt.py'),
             '--sources', str(OUTPUT / 'sources.list'), '--keyring', str(OUTPUT / 'trusted.gpg'),
             '--request', str(OUTPUT / 'request.json'), '--output', str(OUTPUT / 'catalog.json'),
             '--refresh', '--diagnostic-codes'], timeout=180, preparation_diagnostics=True)
    check(package_snapshot() == before)
    catalog_bytes = regular_file(OUTPUT / 'catalog.json', maximum=512 * 1024)[0]
    catalog = validate_catalog(decode(catalog_bytes, 512 * 1024))
    check({row['id'] for row in catalog.values()} == {'postgresql16', 'clickhouse'})
    evidence = _prepared_files(None)
    phase = 'retained-public-inputs'
    indexes = secure_directory(OUTPUT / 'indexes')
    retained = []
    total = 0
    for entry in evidence['files']:
        original = Path(entry['path'])
        if original.parent != Path('/var/lib/apt/lists'):
            continue
        data = regular_file(original, maximum=64 * 1024 * 1024)[0]
        total += len(data)
        check(total <= 256 * 1024 * 1024 and hashlib.sha256(data).hexdigest() == entry['sha256'])
        # Existing APT-generated basenames only, never an operator pathname.
        check('/' not in original.name and original.name not in ('.', '..'))
        descriptor = _file(indexes / original.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            _write_all(descriptor, data)
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        retained.append({'name': original.name, 'sha256': entry['sha256'], 'size': len(data),
                         'uid': entry['uid'], 'gid': entry['gid'], 'mode': entry['mode']})
    check(retained)
    program = source_inputs(source_bytes)
    write('package-baseline.json', wire_bytes(before))
    manifest = {'format': 1, 'scope': 'recipe-catalog-preparation', 'fixtureId': fixture,
                'catalogDigest': digest(catalog), 'catalogSha256': hashlib.sha256(catalog_bytes).hexdigest(),
                'requestSha256': program['recipes/preparation-request.json'], 'sourceInputs': program,
                'packageBaselineDigest': digest(before), 'publicKeySha256': KEY_SHA256,
                'repositoryFingerprints': evidence['repositoryFingerprints'],
                'aptIndexDigests': evidence['aptIndexDigests'], 'indexes': retained,
                'packageInstallation': False, 'recipeAcceptance': False, 'fullAcceptance': False}
    write('preparation.json', wire_bytes(manifest))
    for directory in (indexes, OUTPUT):
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    phase = 'finished'
    print(json.dumps({'scope': 'recipe-catalog-preparation', 'catalogDigest': digest(catalog),
                      'packageInstallation': False, 'recipeAcceptance': False, 'fullAcceptance': False}))


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        for location in diagnostic_locations(error):
            print(location, file=sys.stderr)
        print('Recipe preparation failed at ' + phase + '.', file=sys.stderr)
        sys.exit(1)
