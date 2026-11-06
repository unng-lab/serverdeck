"""Synthetic publisher inputs and isolated build-tool adapters; no product launch."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parents[1]


class ReleasePayloadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('release_payload', TOOLS / 'prepare-release-payload.py')
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.setup = Path(self.temp.name) / 'ServerDeckSetup.exe'
        data = bytearray(512)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 60, 128)
        data[128:132] = b'PE\0\0'
        struct.pack_into('<H', data, 132, 0x8664)
        struct.pack_into('<H', data, 152, 0x20b)
        self.setup.write_bytes(data)
        self.audit = {'profile': 'publishable', 'version': '0.1.1',
                      'setup': {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()},
                      'application': {'size': 7, 'sha256': 'a' * 64}}
        self.policy = {'schema': 1, 'endpoint': self.module.packaging.GITHUB_ENDPOINT,
                       'downloadHosts': sorted(self.module.packaging.GITHUB_HOSTS), 'storeFormat': 2,
                       'keys': [{'id': 'unit', 'p256':
                                 '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'
                                 '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5'}]}
        self.policy_bytes = json.dumps(self.policy).encode()
        self.trust = self.module.packaging.canonical_policy(self.policy_bytes, 2, True)

    def read(self, _, name, kind=10):
        if name == 'SERVERDECK_TRUST_V1':
            return self.trust
        if name == 'SERVERDECK_SETUP_V1':
            return b'SDSETUP001\n0.1.1\n7\n' + b'a' * 64 + b'\n'
        if name == 1 and kind == 24:
            return b'<assembly><requestedExecutionLevel level="asInvoker" uiAccess="false"/></assembly>'
        raise AssertionError(name)

    def payload(self, **extra):
        args = dict(setup=self.setup, audit=self.audit, policy_bytes=self.policy_bytes, notes_bytes='Изменения'.encode(),
                    issued=100000, reader=self.read, identity_reader=lambda *_: self.audit['application'])
        args.update(extra)
        return self.module.prepare(**args)

    def test_exact_bytes_policy_and_notes(self):
        fields = self.payload().decode().splitlines()
        self.assertEqual(fields[:6], ['SDRELEASES002', '100000', '1', '0.1.1', 'windows-x64', '1'])
        self.assertEqual(fields[9], self.audit['setup']['sha256'])
        self.assertIn('/v0.1.1/ServerDeckSetup.exe', fields[12])

    def test_developer_tampered_setup_trust_and_app_are_refused(self):
        developer = copy.deepcopy(self.audit)
        developer['profile'] = 'developer'
        for overrides in [{'audit': developer}, {'reader': lambda *_: None},
                          {'identity_reader': lambda *_: {'size': 8, 'sha256': 'a' * 64}}]:
            with self.subTest(overrides=overrides.keys()), self.assertRaises(ValueError):
                self.payload(**overrides)
        self.setup.write_bytes(self.setup.read_bytes() + b'tampered')
        with self.assertRaises(ValueError):
            self.payload()

    def test_previous_records_are_preserved_and_version_reuse_refused(self):
        prior = self.payload().replace(b'0.1.1', b'0.1.0').replace(b'0.1.1', b'0.1.0')
        combined = self.payload(previous=prior)
        self.assertEqual(combined.splitlines()[2], b'2')
        self.assertEqual(combined.splitlines()[14:], prior.splitlines()[3:])
        for invalid in [self.payload(), prior.replace(b'100000', b'0100000'), prior + b'extra\n', prior.replace(b'windows-x64', b'linux-x64')]:
            with self.assertRaises(ValueError):
                self.payload(previous=invalid)
        with self.assertRaises(ValueError):
            self.payload(previous=prior.replace(b'100000', b'100100'))

    def test_notes_and_old_release_capacity_are_bounded(self):
        for notes in [b'', b'\0', b'x' * 16385, b'\xff']:
            with self.assertRaises((ValueError, UnicodeDecodeError)):
                self.payload(notes_bytes=notes)
        prior = self.payload().replace(b'\n1\n0.1.1', b'\n32\n0.1.1', 1)
        with self.assertRaises(ValueError):
            self.payload(previous=prior)


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 publisher unit adapter')
class PublisherBootstrapTest(unittest.TestCase):
    def test_persistent_key_missing_key_guard_and_private_acl(self):
        with tempfile.TemporaryDirectory() as directory:
            quote = lambda p: "'" + str(p).replace("'", "''") + "'"
            script = f"""
$ErrorActionPreference = 'Stop'
$root = {quote(directory)}
$policy = Join-Path $root 'public.json'; $keys = Join-Path $root 'keys'
& {quote(TOOLS / 'initialize-update-signing.ps1')} -Policy $policy -KeyDirectory $keys -KeyId unit
if ($LASTEXITCODE) {{ throw 'Initialization failed' }}
$first = [IO.File]::ReadAllBytes((Join-Path $keys 'unit.pem'))
$public = [IO.File]::ReadAllText($policy)
& {quote(TOOLS / 'initialize-update-signing.ps1')} -Policy $policy -KeyDirectory $keys -KeyId unit
if ($LASTEXITCODE -or [IO.File]::ReadAllText($policy) -cne $public -or
    [Convert]::ToHexString([IO.File]::ReadAllBytes((Join-Path $keys 'unit.pem'))) -cne [Convert]::ToHexString($first)) {{ throw 'Key rotated' }}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
foreach ($path in @($keys, (Join-Path $keys 'unit.pem'))) {{
    $acl = Get-Acl -LiteralPath $path
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid.Value -or
        !$acl.AreAccessRulesProtected -or $acl.Access.Count -ne 2) {{ throw 'Private owner/ACL' }}
    $principals = @($acl.Access | ForEach-Object {{
        if ($_.IsInherited -or $_.AccessControlType -ne 'Allow' -or $_.FileSystemRights -ne 'FullControl') {{ throw 'Private ACL rights' }}
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    }})
    if ($sid.Value -cnotin $principals -or 'S-1-5-18' -cnotin $principals) {{ throw 'Private ACL principals' }}
}}
Remove-Item -LiteralPath (Join-Path $keys 'unit.pem')
& {quote(TOOLS / 'initialize-update-signing.ps1')} -Policy $policy -KeyDirectory $keys -KeyId unit 2>$null
if (!$LASTEXITCODE -or (Test-Path -LiteralPath (Join-Path $keys 'unit.pem')) -or [IO.File]::ReadAllText($policy) -cne $public) {{ throw 'Lost key silently replaced' }}
exit 0
"""
            result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('PRIVATE KEY', result.stdout + result.stderr)

    def test_existing_foreign_directory_is_rejected_before_creating_key(self):
        with tempfile.TemporaryDirectory() as directory:
            quote = lambda p: "'" + str(p).replace("'", "''") + "'"
            script = f"""
$ErrorActionPreference = 'Stop'
$root = {quote(directory)}
$policy = Join-Path $root 'public.json'; $keys = Join-Path $root 'keys'
New-Item -ItemType Directory -Path $keys | Out-Null
function global:Get-Acl {{
    param([string]$LiteralPath)
    $acl = Microsoft.PowerShell.Security\\Get-Acl -LiteralPath $LiteralPath
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-18'))
    return $acl
}}
& {quote(TOOLS / 'initialize-update-signing.ps1')} -Policy $policy -KeyDirectory $keys -KeyId unit 2>$null
if (!$LASTEXITCODE -or (Test-Path -LiteralPath (Join-Path $keys 'unit.pem')) -or
    (Test-Path -LiteralPath $policy)) {{ throw 'Foreign publisher directory accepted or modified' }}
exit 0
"""
            result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('PRIVATE KEY', result.stdout + result.stderr)

    def test_signer_matches_policy_and_authenticates_previous_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            quote = lambda p: "'" + str(p).replace("'", "''") + "'"
            script = f"""
$ErrorActionPreference = 'Stop'
$root = {quote(directory)}; $keys = Join-Path $root 'keys'; $policy = Join-Path $root 'public.json'
& {quote(TOOLS / 'initialize-update-signing.ps1')} -Policy $policy -KeyDirectory $keys -KeyId unit
$audit = Join-Path $root 'audit.json'; [IO.File]::WriteAllText($audit, '{{"version":"0.1.1"}}')
$installer = Join-Path $root 'ServerDeckSetup.exe'; $payload = Join-Path $root 'update-payload.txt'
$global:producerCalls = 0
function global:python {{
    param([Parameter(ValueFromRemainingArguments=$true)]$Parameters)
    $global:producerCalls++
    [IO.File]::WriteAllBytes($payload, [Text.Encoding]::ASCII.GetBytes("SDRELEASES002`n100000`n0`n"))
    $global:LASTEXITCODE = 0
}}
$key = Join-Path $keys 'unit.pem'
& {quote(TOOLS / 'prepare-release.ps1')} -Installer $installer -Audit $audit -Policy $policy -PrivateKey $key -KeyId unit -Notes fixture -FirstRelease
if ($LASTEXITCODE -or $global:producerCalls -ne 1) {{ throw 'Signed preparation failed' }}
$catalog = Join-Path $root 'serverdeck-update-catalog.txt'
$valid = [IO.File]::ReadAllBytes($catalog)
& {quote(TOOLS / 'prepare-release.ps1')} -Installer $installer -Audit $audit -Policy $policy -PrivateKey $key -KeyId unit -Notes fixture -PreviousCatalog $catalog
if ($LASTEXITCODE -or $global:producerCalls -ne 2) {{ throw 'Previous signature refused' }}
$tampered = [byte[]]$valid.Clone(); $tampered[$tampered.Length-3] = 49; [IO.File]::WriteAllBytes($catalog, $tampered)
& {quote(TOOLS / 'prepare-release.ps1')} -Installer $installer -Audit $audit -Policy $policy -PrivateKey $key -KeyId unit -Notes fixture -PreviousCatalog $catalog 2>$null
if (!$LASTEXITCODE -or $global:producerCalls -ne 2) {{ throw 'Tampered prior metadata accepted' }}
$bad = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
try {{ [IO.File]::WriteAllText($key, $bad.ExportPkcs8PrivateKeyPem()) }} finally {{ $bad.Dispose() }}
& {quote(TOOLS / 'prepare-release.ps1')} -Installer $installer -Audit $audit -Policy $policy -PrivateKey $key -KeyId unit -Notes fixture -FirstRelease 2>$null
if (!$LASTEXITCODE -or $global:producerCalls -ne 2) {{ throw 'Wrong publisher key accepted' }}
exit 0
"""
            result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('PRIVATE KEY', result.stdout + result.stderr)

    def test_default_and_ci_never_silently_build_developer(self):
        build = (TOOLS / 'build-release.ps1').read_text(encoding='utf-8-sig')
        workflow = (TOOLS.parent / '.github/workflows/release.yml').read_text(encoding='utf-8')
        self.assertIn("$Profile = 'publishable'", build)
        self.assertIn('release/update-policy.json', build)
        self.assertIn('-Profile publishable -UpdatePolicy release/update-policy.json', workflow)
        self.assertNotIn('Build developer installer', workflow)

    def test_missing_release_policy_fails_before_building(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(TOOLS / 'build-release.ps1'),
                                     '-UpdatePolicy', str(Path(directory) / 'absent.json')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Publishable build requires', result.stderr)
