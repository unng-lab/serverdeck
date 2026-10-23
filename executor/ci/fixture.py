#!/usr/bin/python3 -I
"""Owned Docker acceptance setup only; never installed as an executor tool."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from uuid import UUID

SOURCE = Path('/opt/serverdeck-source')
VENV = Path('/opt/serverdeck-executor/venv')
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8', 'HOME': '/root'}


def command(argv, *, data=None, timeout=30):
    result = subprocess.run(argv, input=data, env=ENV, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, timeout=timeout, check=True)
    if len(result.stdout) > 256 * 1024:
        raise ValueError('FIXTURE_LIMIT')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('prepare-ssh', 'enroll'))
    parser.add_argument('--workspace-id')
    args = parser.parse_args()
    fixture = os.environ.get('SERVERDECK_FIXTURE_ID', '')
    if (os.geteuid() != 0 or re.fullmatch('[a-f0-9]{32}', fixture) is None or
            Path('/proc/1/comm').read_bytes().strip() != b'systemd' or
            not Path('/.dockerenv').is_file()):
        raise ValueError('OWNED_DOCKER_FIXTURE_REQUIRED')
    if args.mode == 'prepare-ssh':
        private = Path('/etc/ssh/ssh_host_ed25519_key')
        private.unlink(missing_ok=True)
        Path(str(private) + '.pub').unlink(missing_ok=True)
        command(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(private)])
        password = 'SD' + secrets.token_hex(32)
        command(['/usr/sbin/chpasswd'], data=('sdeck:' + password + '\n').encode('ascii'))
        command(['/usr/bin/systemctl', 'start', 'ssh.service'])
        command(['/usr/bin/systemctl', 'is-active', '--quiet', 'ssh.service'])
        public = Path(str(private) + '.pub').read_text(encoding='ascii').split()
        if public[0] != 'ssh-ed25519':
            raise ValueError('FIXTURE_HOST_KEY')
        fingerprint = base64.b64encode(hashlib.sha256(base64.b64decode(public[1], validate=True)).digest()).decode().rstrip('=')
        # The parent captures this over a private pipe and immediately DPAPI
        # protects it; neither argv, environment nor public proof carries it.
        print(json.dumps({'format': 1, 'fixtureId': fixture, 'uid': 42001,
                          'sshUser': 'sdeck', 'password': password,
                          'hostFingerprint': 'SHA256:' + fingerprint}))
        return
    workspace = str(UUID(args.workspace_id))
    if workspace != args.workspace_id:
        raise ValueError('FIXTURE_WORKSPACE')
    command([str(VENV / 'bin/python'), '-I', str(SOURCE / 'packaging/install.py'),
             '--uid', '42001', '--controller-id', workspace, '--workspace-id', workspace,
             '--prepare-apt-no-start'], timeout=120)
    command(['/usr/bin/systemctl', 'start', 'serverdeck-executor.service'])
    until = time.monotonic() + 30
    while True:
        active = subprocess.run(['/usr/bin/systemctl', 'is-active', '--quiet', 'serverdeck-executor.service'],
            env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        if active.returncode == 0:
            break
        if time.monotonic() >= until:
            raise ValueError('FIXTURE_SERVICE_START')
        time.sleep(.1)
    host = json.loads(Path('/etc/serverdeck-executor/host.json').read_text())
    release = json.loads(Path('/etc/serverdeck-executor/release.json').read_text())
    print(json.dumps({'format': 1, 'fixtureId': fixture, 'workspaceId': workspace,
                      'hostId': host['hostId'], 'runtimeVersion': release['runtimeVersion'],
                      'registryDigest': release['registryDigest']}))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Owned executor fixture setup failed.', file=sys.stderr)
        sys.exit(1)
