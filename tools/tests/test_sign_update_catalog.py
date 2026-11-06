"""Synthetic signing keys only; no repository/operator credentials."""
import shutil
import base64
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 required for operator tool')
class CatalogSigningTest(unittest.TestCase):
    def test_exact_bytes_p1363_and_private_input_failure(self):
        tool = Path(__file__).resolve().parents[1] / 'sign-update-catalog.ps1'
        quote = lambda path: "'" + str(path).replace("'", "''") + "'"
        with tempfile.TemporaryDirectory() as directory:
            script = f"""
$ErrorActionPreference = 'Stop'
$root = {quote(directory)}
$payload = Join-Path $root 'payload'
$keyPath = Join-Path $root 'synthetic-private-key.pem'
$catalog = Join-Path $root 'catalog'
$key = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
try {{
  $bytes = [Text.Encoding]::ASCII.GetBytes("SDRELEASES001`n1`n2`n0`n")
  [IO.File]::WriteAllBytes($payload, $bytes)
  [IO.File]::WriteAllText($keyPath, $key.ExportECPrivateKeyPem())
  $LASTEXITCODE = 0
  & {quote(tool)} -Payload $payload -PrivateKey $keyPath -KeyId unit-key -Catalog $catalog
  if ($LASTEXITCODE -ne 0) {{ throw 'Signer failed' }}
  $result = [IO.File]::ReadAllText($catalog)
  $lines = $result.Split("`n")
  if ($lines[0] -cne 'SDCATALOG001' -or $lines[1] -cne 'unit-key' -or $lines[2] -cnotmatch '^[a-f0-9]{{128}}$') {{ throw 'Envelope' }}
  $signed = ($lines[3..($lines.Length-1)] -join "`n")
  if ($signed -cne [Text.Encoding]::ASCII.GetString($bytes)) {{ throw 'Payload changed' }}
  $signature = [Convert]::FromHexString($lines[2])
  $format = [Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation
  if (!$key.VerifyData($bytes, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, $format)) {{ throw 'Signature invalid' }}
  $bytes[0] = 88
  if ($key.VerifyData($bytes, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, $format)) {{ throw 'Tamper accepted' }}
}} finally {{ $key.Dispose() }}
"""
            result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            original = (Path(directory) / 'catalog').read_bytes()
            static_script = script.replace('SDRELEASES001`n1`n2`n0', 'SDRELEASES002`n1`n0').replace(
                'SDCATALOG001', 'SDCATALOG002')
            static_result = subprocess.run(['pwsh', '-NoProfile', '-Command', static_script],
                                           capture_output=True, text=True)
            self.assertEqual(static_result.returncode, 0, static_result.stderr)
            self.assertTrue((Path(directory) / 'catalog').read_bytes().startswith(b'SDCATALOG002\n'))
            lines = ['SDRELEASES001', '1', '2', '6']
            for index, notes_size in enumerate([16384] * 5 + [15000]):
                lines += [f'1.0.{index}', 'windows-x64', '1', '2', '1', '1', 'a' * 64,
                          '1', 'b' * 64, 'https://updates.example/setup.exe',
                          base64.b64encode(b'n' * notes_size).decode('ascii')]
            near_limit = ('\n'.join(lines) + '\n').encode('ascii')
            self.assertGreater(len(near_limit), 130000)
            payload_path = Path(directory) / 'payload'
            payload_path.write_bytes(near_limit)
            def sign_payload():
                return subprocess.run(['pwsh', '-NoProfile', '-File', str(tool),
                                       '-Payload', str(payload_path),
                                       '-PrivateKey', str(Path(directory) / 'synthetic-private-key.pem'),
                                       '-KeyId', 'unit-key', '-Catalog', str(Path(directory) / 'catalog')],
                                      capture_output=True, text=True)
            accepted = sign_payload()
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            bounded = (Path(directory) / 'catalog').read_bytes()
            self.assertLessEqual(len(bounded), 131072)
            self.assertEqual(bounded.split(b'\n', 3)[3], near_limit)
            # Payload alone fits but adding its envelope must fail atomically.
            payload_path.write_bytes(b'SDRELEASES001\n' + b'n' * (131072 - 15) + b'\n')
            self.assertEqual(payload_path.stat().st_size, 131072)
            self.assertNotEqual(sign_payload().returncode, 0)
            self.assertEqual((Path(directory) / 'catalog').read_bytes(), bounded)
            payload_path.write_bytes(b'SDRELEASES001\n1\n2\n0\n')
            (Path(directory) / 'catalog').write_bytes(original)
            for invalid_id in ('UNIT-KEY', 'unit-key\n', 'a' * 33, 'unit_key'):
                rejected = subprocess.run(['pwsh', '-NoProfile', '-File', str(tool),
                                           '-Payload', str(Path(directory) / 'payload'),
                                           '-PrivateKey', str(Path(directory) / 'synthetic-private-key.pem'),
                                           '-KeyId', invalid_id, '-Catalog', str(Path(directory) / 'catalog')],
                                          capture_output=True, text=True)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertEqual((Path(directory) / 'catalog').read_bytes(), original)
            key_path = Path(directory) / 'synthetic-private-key.pem'
            key_path.write_text('invalid PEM', encoding='ascii')
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(tool),
                                     '-Payload', str(Path(directory) / 'payload'),
                                     '-PrivateKey', str(key_path), '-KeyId', 'unit-key',
                                     '-Catalog', str(Path(directory) / 'failed')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(str(key_path), result.stdout + result.stderr)
            self.assertNotIn('invalid PEM', result.stdout + result.stderr)
            self.assertFalse((Path(directory) / 'failed').exists())


if __name__ == '__main__':
    unittest.main()
