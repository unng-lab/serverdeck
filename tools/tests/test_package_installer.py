"""Synthetic build-tool unit tests; never execute an application or setup."""
import hashlib
import ctypes
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock


class InstallerPackageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            'package_installer', Path(__file__).resolve().parents[1] / 'package-installer.py')
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        # Minimal non-executable x64 PE header; package-release's static import
        # parser accepts the empty import graph without loading anything.
        data = bytearray(1024)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 0x3c, 0x80)
        data[0x80:0x84] = b'PE\0\0'
        struct.pack_into('<HH', data, 0x84, 0x8664, 0)
        struct.pack_into('<H', data, 0x94, 240)
        struct.pack_into('<H', data, 0x98, 0x20b)
        self.app = self.root / 'ServerDeck.exe'
        self.app.write_bytes(data)
        self.policy = {
            'schema': 1, 'endpoint': 'https://updates.example.test/stable',
            'downloadHosts': ['assets.example.test'], 'storeFormat': 2,
            'keys': [{'id': 'test-key', 'p256':
                      '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'
                      '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5'}],
        }

    def test_prepare_binds_exact_app_bytes_and_rc_names(self):
        result = self.module.prepare(self.app, self.root / 'out', '0.2.0+10',
                                     resource_reader=lambda _, name: b'SDBUILD001\n0.2.0+10\n' if name == 'SERVERDECK_BUILD_V1' else None)
        digest = hashlib.sha256(self.app.read_bytes()).hexdigest()
        self.assertEqual(result['appSha256'], digest)
        self.assertEqual((self.root / 'out/setup-manifest.txt').read_bytes(),
                         f'SDSETUP001\n0.2.0+10\n1024\n{digest}\n'.encode())
        resource = (self.root / 'out/setup.rc').read_text(encoding='utf-8')
        self.assertIn('SERVERDECK_APPLICATION_V1 RCDATA', resource)
        self.assertIn(self.app.resolve().as_posix(), resource)
        self.assertIn('SERVERDECK_SETUP_V1 RCDATA', resource)

    def test_versions_are_canonical_and_bounded(self):
        for bad in ['0.2.0', '00.2.0+1', '0.2.0+01', '65536.0.0+1', '0.2.0+-1', '0.2.0+1\n']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.module.prepare(self.app, self.root / 'bad', bad)

    def test_rejects_invalid_pe_or_over_limit_before_writing_output(self):
        with mock.patch.object(self.module, 'ARTIFACT_LIMIT', 1023):
            with self.assertRaises(ValueError):
                self.module.prepare(self.app, self.root / 'large', '0.2.0+1')
        self.assertFalse((self.root / 'large').exists())
        self.app.write_bytes(b'not PE')
        with self.assertRaises((ValueError, struct.error)):
            self.module.prepare(self.app, self.root / 'invalid', '0.2.0+1')

    def test_valid_policy_is_canonical_and_contains_only_public_inputs(self):
        encoded = json.dumps(self.policy).encode()
        canonical = self.module.canonical_policy(encoded, 2)
        self.assertEqual(json.loads(canonical), self.policy)
        self.assertEqual(canonical, self.module.canonical_policy(canonical, 2))
        with self.assertRaises(ValueError):
            self.module.canonical_policy(encoded, 3)

    def test_policy_rejects_aliases_unknown_keys_duplicate_keys_and_invalid_curve(self):
        for host in ['127.0.0.1', '0x7f.0.0.1', '0177.0.0.1', '999.999',
                     '256.256.256.256', '1.2.3.999', '*.example.test', 'UPDATES.example.test']:
            policy = dict(self.policy, downloadHosts=[host])
            with self.subTest(host=host), self.assertRaises(ValueError):
                self.module.canonical_policy(json.dumps(policy).encode(), 2)
        for url in ['http://updates.example.test', 'https://@updates.example.test/a',
                    'https://user:pw@updates.example.test/a', 'https://0x7f.0.0.1/a',
                    'https://999.999/a', 'https://256.256.256.256/a', 'https://1.2.3.999/a',
                    'https://updates.example.test:444/a', 'https://updates.example.test/a#x']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                self.module.canonical_policy(json.dumps(dict(self.policy, endpoint=url)).encode(), 2)
        for policy in [dict(self.policy, unknown=True), dict(self.policy, keys=[]),
                       dict(self.policy, storeFormat=True),
                       dict(self.policy, downloadHosts=['assets.example.test'] * 2),
                       dict(self.policy, keys=[{'id': 'test-key', 'p256': '0' * 128}])]:
            with self.assertRaises(ValueError):
                self.module.canonical_policy(json.dumps(policy).encode(), 2)
        with self.assertRaises(ValueError):
            self.module.canonical_policy(b'{"schema":1,"schema":1}', 2)

    def test_publishable_profile_requires_policy_and_matching_embedded_policy(self):
        with self.assertRaises(ValueError):
            self.module.prepare(self.app, self.root / 'public', '0.2.0+1', publishable=True)
        policy_file = self.root / 'policy.json'
        public_policy = dict(self.policy, endpoint=self.module.GITHUB_ENDPOINT,
                             downloadHosts=sorted(self.module.GITHUB_HOSTS))
        canonical = self.module.canonical_policy(json.dumps(public_policy).encode(), 2, publishable=True)
        policy_file.write_bytes(canonical)
        reader = mock.Mock(side_effect=lambda _, name: b'SDBUILD001\n0.2.0+1\n' if name == 'SERVERDECK_BUILD_V1' else canonical)
        self.module.prepare(self.app, self.root / 'signed-input', '0.2.0+1', policy_file,
                            current_store_format=2, resource_reader=reader, publishable=True)
        reader.assert_has_calls([mock.call(self.app, 'SERVERDECK_BUILD_V1'), mock.call(self.app, 'SERVERDECK_TRUST_V1')])
        for invalid in (self.policy, dict(public_policy, endpoint=self.module.GITHUB_ENDPOINT + '?token=x'),
                        dict(public_policy, downloadHosts=['github.com']),
                        dict(public_policy, downloadHosts=sorted(self.module.GITHUB_HOSTS | {'other.example'}))):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.module.canonical_policy(json.dumps(invalid).encode(), 2, publishable=True)
        policy_file.write_text(json.dumps(self.policy))
        with self.assertRaises(ValueError):
            self.module.prepare(self.app, self.root / 'generic-public', '0.2.0+1', policy_file,
                                current_store_format=2, resource_reader=lambda *_: b'', publishable=True)
        self.assertFalse((self.root / 'generic-public').exists())
        policy_file.write_bytes(canonical)
        with self.assertRaises(ValueError):
            self.module.prepare(self.app, self.root / 'different', '0.2.0+1', policy_file,
                                current_store_format=2, resource_reader=lambda *_: b'{}')
        with self.assertRaises(ValueError):
            self.module.prepare(self.app, self.root / 'lost-policy', '0.2.0+1',
                                resource_reader=lambda *_: canonical)

    def test_static_setup_audit_checks_exact_resources_and_as_invoker(self):
        setup = self.root / 'ServerDeckSetup.exe'
        setup.write_bytes(self.app.read_bytes() + b'synthetic container')
        app_id = {'size': self.app.stat().st_size, 'sha256': hashlib.sha256(self.app.read_bytes()).hexdigest()}
        manifest = f"SDSETUP001\n0.2.0+1\n{app_id['size']}\n{app_id['sha256']}\n".encode()
        xml = b'<assembly><requestedExecutionLevel level="asInvoker" uiAccess="false"/></assembly>'

        def reader(_, name, resource_type=10):
            if name == 'SERVERDECK_BUILD_V1':
                return b'SDBUILD001\n0.2.0+1\n'
            if resource_type == 24:
                self.assertEqual(name, 1)
                return xml
            return manifest if name == 'SERVERDECK_SETUP_V1' else None

        self.module.audit_setup(self.app, setup, self.root / 'audit', '0.2.0+1',
                                resource_reader=reader, identity_reader=lambda *_: app_id)
        with self.assertRaises(ValueError):
            self.module.prepare(self.app, self.root / 'wrong-build-version', '0.3.0+1', resource_reader=reader)
        self.assertFalse((self.root / 'wrong-build-version').exists())
        with self.assertRaises(ValueError):
            self.module.audit_setup(self.app, setup, self.root / 'bad-resource', '0.2.0+1',
                                    resource_reader=reader, identity_reader=lambda *_: dict(app_id, sha256='0' * 64))
        for bad in [b'<assembly/>', xml.replace(b'asInvoker', b'requireAdministrator'),
                    xml.replace(b'uiAccess="false"', b'uiAccess="true"')]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.module._as_invoker(bad)

    def test_resource_reader_uses_data_mapping_and_integer_resource_ids(self):
        data = ctypes.create_string_buffer(b'manifest')
        calls = []

        class Function:
            def __init__(self, callback):
                self.callback = callback
            def __call__(self, *args):
                return self.callback(*args)

        def find(module, name, resource_type):
            self.assertIsInstance(name, ctypes.c_wchar_p)
            self.assertEqual(ctypes.cast(name, ctypes.c_void_p).value, 1)
            self.assertEqual(resource_type.value, 24)
            return 2

        kernel = mock.Mock()
        kernel.LoadLibraryExW = Function(lambda path, reserved, flags: calls.append(('map', flags)) or 1)
        kernel.FindResourceW = Function(find)
        kernel.SizeofResource = Function(lambda *_: 8)
        kernel.LoadResource = Function(lambda *_: 3)
        kernel.LockResource = Function(lambda *_: ctypes.addressof(data))
        kernel.FreeLibrary = Function(lambda module: calls.append(('free', module)) or 1)
        with mock.patch.object(ctypes, 'WinDLL', return_value=kernel, create=True):
            self.assertEqual(self.module.resource_bytes(self.app, 1, 24), b'manifest')
        self.assertEqual(calls, [('map', 0x60), ('free', 1)])


if __name__ == '__main__':
    unittest.main()
