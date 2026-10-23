#!/usr/bin/python3 -I
"""Actual installed executor/Ansible qualification in the owned Docker fixture.

This enrolled test controller exercises the real no-argument sudo bridge. It
does not replace the Windows UI/MCP/client or database-recipe acceptance.
"""
import asyncio
import json
import os
from pathlib import Path
import re
import struct
import sys
from uuid import uuid4

SOURCE = Path('/opt/serverdeck-source')

ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8',
       'LC_ALL': 'C.UTF-8', 'HOME': '/root'}
phase = 'fixture'


def check(value):
    if not value:
        raise RuntimeError('EXECUTOR_CORE_ASSERTION')


async def command(arguments, timeout=30):
    child = await asyncio.create_subprocess_exec(*arguments, env=ENV,
        stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE)
    output, errors = await asyncio.wait_for(child.communicate(), timeout)
    check(child.returncode == 0 and len(output) <= 64 * 1024 and len(errors) <= 64 * 1024)


class Bridge:
    @classmethod
    async def open(cls):
        result = cls()
        result.child = await asyncio.create_subprocess_exec(
            '/usr/sbin/runuser', '-u', 'sdeck', '--', '/usr/bin/sudo', '-n',
            '/usr/libexec/serverdeck-executor-bridge', env=ENV,
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE)
        result.errors = asyncio.create_task(result.drain_errors())
        return result

    async def drain_errors(self):
        size = 0
        while chunk := await self.child.stderr.read(8192):
            size += len(chunk)
            check(size <= 64 * 1024)
        return size

    async def call(self, method, params, expected_error=None):
        request_id = str(uuid4())
        data = wire_bytes({'v': 1, 'id': request_id, 'method': method, 'params': params})
        check(len(data) <= 256 * 1024)
        async with asyncio.timeout(8):
            self.child.stdin.write(struct.pack('>I', len(data)) + data)
            await self.child.stdin.drain()
            count, = struct.unpack('>I', await self.child.stdout.readexactly(4))
            check(0 < count <= 8 * 1024 * 1024)
            response = decode(await self.child.stdout.readexactly(count), 8 * 1024 * 1024)
        check(response.get('id') == request_id)
        if expected_error is not None:
            check(set(response) == {'id', 'error'} and
                  set(response['error']) == {'code', 'retry'} and
                  response['error']['code'] == expected_error and
                  type(response['error']['retry']) is bool)
            return
        check(set(response) == {'id', 'result'} and type(response['result']) is dict)
        return response['result']

    async def close(self):
        self.child.stdin.close()
        try:
            await self.child.stdin.wait_closed()
        except (BrokenPipeError, ConnectionResetError):
            pass
        code = await asyncio.wait_for(self.child.wait(), 10)
        errors = await asyncio.wait_for(self.errors, 5)
        check(code == 0 and errors == 0)


async def connect(workspace):
    until = asyncio.get_running_loop().time() + 30
    while True:
        bridge = await Bridge.open()
        try:
            hello = await bridge.call('hello', {'controllerId': workspace, 'workspaceId': workspace})
            return bridge, hello
        except (asyncio.IncompleteReadError, BrokenPipeError, ConnectionResetError):
            # Startup readiness only. Never retry a submitted effect here.
            try:
                await bridge.close()
            except (RuntimeError, BrokenPipeError, ConnectionResetError):
                pass
            check(asyncio.get_running_loop().time() < until)
            await asyncio.sleep(.1)
        except BaseException:
            try:
                await bridge.close()
            except Exception:
                pass
            raise


async def main():
    global phase, decode, digest, wire_bytes
    fixture = os.environ.get('SERVERDECK_FIXTURE_ID', '')
    check(sys.platform == 'linux' and os.geteuid() == 0 and
          re.fullmatch('[a-f0-9]{32}', fixture) is not None and
          Path('/.dockerenv').is_file() and
          Path('/proc/1/comm').read_bytes().strip() == b'systemd' and
          Path(__file__).resolve() == SOURCE / 'ci/core.py')
    sys.path.insert(0, str(SOURCE))
    from serverdeck_executor.codec import decode, digest, wire_bytes
    workspace = str(uuid4())
    phase = 'provision'
    await command(['/opt/serverdeck-executor/venv/bin/python', '-I',
        str(SOURCE / 'packaging/install.py'), '--uid', '42001',
        '--controller-id', workspace, '--workspace-id', workspace,
        '--prepare-apt-no-start'], timeout=120)
    await command(['/usr/bin/systemctl', 'start', 'serverdeck-executor.service'])
    bridge, hello = await connect(workspace)
    try:
        phase = 'bridge-policy'
        check(hello['capabilities']['preflight'] is True and
              hello['capabilities']['configuration'] is True and
              hello['capabilities']['install'] is False)
        # A separate actual bridge stream has no authority before enrollment
        # hello, even though it came from the permitted local Unix account.
        denied = await Bridge.open()
        try:
            await denied.call('status', {'attemptId': str(uuid4())}, 'FORBIDDEN')
            await denied.call('hello', {'controllerId': workspace,
                'workspaceId': str(uuid4())}, 'FORBIDDEN')
        finally:
            await denied.close()
        target = {'workspaceId': workspace, 'serverId': str(uuid4()),
                  'targetRevision': '1', 'connectionRevision': '1',
                  'accessRevision': '1', 'trustRevision': '1'}
        before = Path('/etc/motd').read_bytes() if Path('/etc/motd').exists() else None
        wanted = 'ServerDeck owned executor core ' + fixture + '\n'
        body = {'format': 1, 'environment': 'ubuntu24.04-amd64-systemd',
                'parameters': {}, 'steps': [{'id': 'message', 'kind': 'config_file',
                    'resourceId': 'system.motd', 'values': {'text': wanted}}]}
        phase = 'preflight'
        operation = str(uuid4())
        await bridge.call('preflight', {'operationId': operation,
            'profileBody': body, 'profileDigest': digest(body), 'parameters': {},
            'expectedHostId': hello['hostId'], 'target': target})
        until = asyncio.get_running_loop().time() + 35
        while True:
            pending = await bridge.call('preflight_get', {'operationId': operation})
            check(pending['state'] in ('running', 'succeeded'))
            if pending['state'] == 'succeeded':
                facts = pending['result']
                break
            check(asyncio.get_running_loop().time() < until)
            await asyncio.sleep(.2)
        check(len(facts['effects']) == 1 and len(facts['checks']) == 1 and
              facts['effects'][0]['kind'] == 'config_file' and
              facts['effects'][0]['resourceId'] == 'system.motd')
        base = {'profileId': str(uuid4()), 'profileRevision': 1,
                'profileBody': body, 'profileDigest': digest(body), 'parameters': {},
                'preflightDigest': facts['digest'], 'expectedHostId': hello['hostId'],
                'controllerId': workspace, 'workspaceId': workspace}

        def submission():
            # Root protocol binds an opaque controller plan identity. Actual
            # locald plan/grant authorization is tested by the separate MCP run.
            return {**base, 'jobId': str(uuid4()), 'attemptId': str(uuid4()),
                    'planDigest': digest({'fixture': fixture, 'plan': str(uuid4())})}

        first, second = submission(), submission()
        phase = 'queued-cancel'
        check((await bridge.call('submit', first))['state'] == 'queued')
        await bridge.call('submit', second, 'HOST_BUSY')
        check((Path('/etc/motd').read_bytes() if Path('/etc/motd').exists() else None) == before)
        cancel = {'attemptId': first['attemptId'], 'requestId': str(uuid4())}
        cancelled = await bridge.call('cancel', cancel)
        check(cancelled['state'] == 'cancelled')
        check(await bridge.call('cancel', cancel) == cancelled)
        replay = await bridge.call('submit', first)
        check(replay['attemptId'] == first['attemptId'] and replay['state'] == 'cancelled')
        conflicting = {**first, 'attemptId': str(uuid4())}
        await bridge.call('submit', conflicting, 'CONFLICT')
        check((Path('/etc/motd').read_bytes() if Path('/etc/motd').exists() else None) == before)
        phase = 'step-authorization'
        check((await bridge.call('submit', second))['state'] == 'queued')
        status = await bridge.call('status', {'attemptId': second['attemptId']})
        challenge = status['needsAuthorization']
        authorize = {**challenge, 'attemptId': second['attemptId'], 'authorizationEpoch': 1}
        bad = {**authorize, 'challenge': ('A' if challenge['challenge'][0] != 'A' else 'B') +
               challenge['challenge'][1:]}
        await bridge.call('authorize_step', bad, 'FORBIDDEN')
        check((Path('/etc/motd').read_bytes() if Path('/etc/motd').exists() else None) == before)
        status = await bridge.call('status', {'attemptId': second['attemptId']})
        authorize = {**status['needsAuthorization'], 'attemptId': second['attemptId'],
                     'authorizationEpoch': status['authorizationEpoch'] + 1}
        check((await bridge.call('authorize_step', authorize))['state'] == 'running')
        await bridge.call('authorize_step', authorize, 'CONFLICT')
        phase = 'ansible-effect'
        until = asyncio.get_running_loop().time() + 90
        while True:
            status = await bridge.call('status', {'attemptId': second['attemptId']})
            check(status['state'] in ('running', 'succeeded'))
            if status['state'] == 'succeeded':
                break
            check(asyncio.get_running_loop().time() < until)
            await asyncio.sleep(.5)
        check(status['stepIndex'] == 1 and status['authorizationEpoch'] == 1 and
              status['checks'] == [{'checkId': facts['checks'][0]['id'], 'passed': True}] and
              sum(event['kind'] == 'launch_committed' for event in status['events']) == 1 and
              Path('/etc/motd').read_bytes() == wanted.encode())
        replay = await bridge.call('submit', second)
        check(replay['attemptId'] == second['attemptId'] and replay['state'] == 'succeeded')
    finally:
        await bridge.close()
    phase = 'supervisor-restart'
    await command(['/usr/bin/systemctl', 'restart', 'serverdeck-executor.service'])
    bridge, reopened = await connect(workspace)
    try:
        check(reopened == hello)
        recovered = await bridge.call('status', {'attemptId': second['attemptId']})
        check(recovered == status and Path('/etc/motd').read_bytes() == wanted.encode())
        replay = await bridge.call('submit', second)
        check(replay['attemptId'] == second['attemptId'] and replay['state'] == 'succeeded')
        check((await bridge.call('status', {'attemptId': first['attemptId']}))['state'] == 'cancelled')
    finally:
        await bridge.close()
    print(json.dumps({'scope': 'executor-core', 'systemd': True, 'enrolledSudoBridge': True,
        'actualAnsibleEffect': True, 'authorization': True, 'hostBusy': True,
        'queuedCancel': True, 'samePlanReplay': True, 'supervisorRestart': True,
        'durableReceipt': True, 'recipeAcceptance': False, 'mcpAcceptance': False,
        'executorAcceptance': False, 'kernelReboot': False}, separators=(',', ':')))


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except Exception:
        # No private protocol input, module output or traceback goes to CI logs.
        print('Executor core qualification failed at ' + phase + '.', file=sys.stderr)
        sys.exit(1)
