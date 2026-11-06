"""Prepare the full offline setup's resources; never execute a product binary.

This is build tooling, not an installed runtime. Binary import/manifest audits are
separate build gates; this tool binds exact application bytes and immutable policy.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import socket
import struct
from contextlib import contextmanager
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

ARTIFACT_LIMIT = 1024 ** 3
POLICY_LIMIT = 8192
GITHUB_ENDPOINT = 'https://api.github.com/repos/unng-lab/serverdeck/releases/latest'
GITHUB_HOSTS = {'github.com', 'release-assets.githubusercontent.com',
                'objects.githubusercontent.com', 'github-releases.githubusercontent.com'}


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(
            r'(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})', value):
        raise ValueError('Invalid canonical version')
    parts = tuple(int(part) for part in value.split('.'))
    if any(part > 65535 for part in parts):
        raise ValueError('Version exceeds supported range')
    return parts


def dns_host(value):
    if not isinstance(value, str) or len(value) > 253 or '.' not in value:
        raise ValueError('Invalid DNS host')
    if all(c in '0123456789.' for c in value):
        raise ValueError('Numeric dotted hosts are not source DNS names')
    for label in value.split('.'):
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label):
            raise ValueError('Invalid DNS label')
    # inet_aton is numeric parsing only, including Windows hexadecimal/octal aliases.
    try:
        socket.inet_aton(value)
    except OSError:
        return value
    raise ValueError('IP addresses are not source DNS names')


def https_url(value):
    if not isinstance(value, str) or len(value) > 2048 or not value.startswith('https://'):
        raise ValueError('Invalid HTTPS URL')
    if any(ord(c) < 33 or ord(c) > 126 for c in value) or '\\' in value:
        raise ValueError('Invalid URL characters')
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or parsed.fragment or '#' in value or
            parsed.username is not None or parsed.password is not None or '@' in parsed.netloc or
            parsed.port not in (None, 443)):
        raise ValueError('Source URL must not contain credentials, fragment or alternate port')
    host = dns_host(parsed.hostname)
    if parsed.netloc not in (host, host + ':443'):
        raise ValueError('Noncanonical URL authority')
    return host


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate policy field')
        result[key] = value
    return result


def _p256_point(value):
    if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{128}', value):
        raise ValueError('Invalid P256 public point encoding')
    # Standard P-256 public-point validation, not signature implementation.
    # Parameters: https://www.rfc-editor.org/rfc/rfc5114.html#section-2.6
    prime = 2 ** 256 - 2 ** 224 + 2 ** 192 + 2 ** 96 - 1
    b = int('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b', 16)
    x, y = int(value[:64], 16), int(value[64:], 16)
    if not (0 <= x < prime and 0 <= y < prime) or (y * y - (x * x * x - 3 * x + b)) % prime:
        raise ValueError('Invalid P256 public point')


def canonical_policy(data, current_store_format, publishable=False):
    if not data or len(data) > POLICY_LIMIT or type(current_store_format) is not int or current_store_format <= 0:
        raise ValueError('Invalid policy bounds or storage format')
    policy = json.loads(data.decode('utf-8-sig'), object_pairs_hook=_unique_object)
    fields = {'schema', 'endpoint', 'downloadHosts', 'keys', 'storeFormat'}
    if not isinstance(policy, dict) or set(policy) != fields or type(policy['schema']) is not int or policy['schema'] != 1:
        raise ValueError('Unsupported policy schema or fields')
    if type(policy['storeFormat']) is not int or policy['storeFormat'] != current_store_format or current_store_format > 0xffffffff:
        raise ValueError('Policy must match the current application storage format')
    https_url(policy['endpoint'])
    hosts, keys = policy['downloadHosts'], policy['keys']
    if not isinstance(hosts, list) or not 1 <= len(hosts) <= 8:
        raise ValueError('Invalid host count')
    validated = [dns_host(host) for host in hosts]
    if len(set(validated)) != len(validated):
        raise ValueError('Duplicate hosts')
    if publishable and (policy['endpoint'] != GITHUB_ENDPOINT or set(validated) != GITHUB_HOSTS):
        raise ValueError('Publishable policy must use the project GitHub Releases source and CDN hosts')
    if not isinstance(keys, list) or not 1 <= len(keys) <= 3:
        raise ValueError('Invalid trust key count')
    ids = set()
    for key in keys:
        if not isinstance(key, dict) or set(key) != {'id', 'p256'} or not isinstance(key['id'], str) or not re.fullmatch('[a-z0-9-]{1,32}', key['id']):
            raise ValueError('Invalid public key fields')
        if key['id'] in ids:
            raise ValueError('Duplicate public key id')
        ids.add(key['id'])
        _p256_point(key['p256'])
    result = (json.dumps(policy, sort_keys=True, separators=(',', ':'), ensure_ascii=True) + '\n').encode('utf-8')
    if len(result) > POLICY_LIMIT:
        raise ValueError('Canonical policy exceeds bounds')
    return result


@contextmanager
def _resource_view(binary, name, resource_type=10):
    """Map resources as data only; the returned pointer lives within this context."""
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p, ctypes.c_uint32]
    kernel.LoadLibraryExW.restype = ctypes.c_void_p
    kernel.FindResourceW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_void_p]
    kernel.FindResourceW.restype = ctypes.c_void_p
    kernel.SizeofResource.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    kernel.SizeofResource.restype = ctypes.c_uint32
    kernel.LoadResource.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    kernel.LoadResource.restype = ctypes.c_void_p
    kernel.LockResource.argtypes = [ctypes.c_void_p]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.FreeLibrary.argtypes = [ctypes.c_void_p]
    kernel.FreeLibrary.restype = ctypes.c_int
    module = kernel.LoadLibraryExW(str(binary.resolve()), None, 0x40 | 0x20)
    if not module:
        raise ValueError('Cannot map binary resources')
    try:
        resource_name = ctypes.cast(ctypes.c_void_p(name), ctypes.c_wchar_p) if isinstance(name, int) else name
        resource = kernel.FindResourceW(module, resource_name, ctypes.c_void_p(resource_type))
        if not resource:
            if ctypes.get_last_error() in (1812, 1813, 1814, 1815):
                yield None
                return
            raise ValueError('Required embedded policy resource missing')
        length = kernel.SizeofResource(module, resource)
        if not 0 < length <= ARTIFACT_LIMIT:
            raise ValueError('Embedded resource exceeds bounds')
        pointer = kernel.LockResource(kernel.LoadResource(module, resource))
        if not pointer:
            raise ValueError('Cannot read embedded resource')
        yield pointer, length
    finally:
        kernel.FreeLibrary(module)


def resource_bytes(binary, name, resource_type=10):
    """Copy a small resource without loading imports or executing an entrypoint."""
    with _resource_view(binary, name, resource_type) as view:
        if view is None:
            return None
        pointer, length = view
        if length > POLICY_LIMIT:
            raise ValueError('Small resource exceeds bounds')
        return ctypes.string_at(pointer, length)


def resource_identity(binary, name):
    with _resource_view(binary, name) as view:
        if view is None:
            raise ValueError('Application resource missing')
        pointer, length = view
        digest = hashlib.sha256()
        for offset in range(0, length, 65536):
            digest.update(ctypes.string_at(pointer + offset, min(65536, length - offset)))
        return {'size': length, 'sha256': digest.hexdigest()}


def _as_invoker(data):
    if data is None:
        raise ValueError('Execution manifest missing')
    root = ET.fromstring(data)
    levels = [node for node in root.iter() if node.tag.rsplit('}', 1)[-1] == 'requestedExecutionLevel']
    if len(levels) != 1 or levels[0].get('level') != 'asInvoker' or levels[0].get('uiAccess') != 'false':
        raise ValueError('Product must run asInvoker without uiAccess')
    if any(node.tag.rsplit('}', 1)[-1] == 'autoElevate' and (node.text or '').strip().lower() == 'true'
           for node in root.iter()):
        raise ValueError('Product must not auto-elevate')


def audit_setup(application, setup, output, version, policy_path=None, current_store_format=None,
               publishable=False, resource_reader=None, identity_reader=None):
    version_tuple(version)
    application, setup, output = Path(application), Path(setup), Path(output)
    identities = {}
    for label, path in [('application', application), ('setup', setup)]:
        if path.is_symlink() or path.is_junction() or not path.is_file() or not 0 < path.stat().st_size <= ARTIFACT_LIMIT:
            raise ValueError('Invalid final artifact')
        _validate_pe(path)
        with path.open('rb') as source:
            identities[label] = {'size': path.stat().st_size, 'sha256': hashlib.file_digest(source, 'sha256').hexdigest()}
    reader = resource_reader or resource_bytes
    if reader(application, 'SERVERDECK_BUILD_V1') != f'SDBUILD001\n{version}\n'.encode('ascii'):
        raise ValueError('Mapped application build version differs from setup version')
    embedded = (identity_reader or resource_identity)(setup, 'SERVERDECK_APPLICATION_V1')
    if embedded != identities['application']:
        raise ValueError('Setup does not embed the exact final application')
    app = identities['application']
    expected = f"SDSETUP001\n{version}\n{app['size']}\n{app['sha256']}\n".encode('ascii')
    if reader(setup, 'SERVERDECK_SETUP_V1') != expected:
        raise ValueError('Setup resource manifest does not match the application')
    if publishable and policy_path is None:
        raise ValueError('Publishable audit requires policy')
    policy = canonical_policy(Path(policy_path).read_bytes(), current_store_format, publishable) if policy_path else None
    for path in (application, setup):
        if reader(path, 'SERVERDECK_TRUST_V1') != policy:
            raise ValueError('Final artifact policy mismatch')
        _as_invoker(reader(path, 1, 24))
    identities['version'] = version
    identities['profile'] = 'publishable' if publishable else 'developer'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'setup-audit.json').write_text(json.dumps(identities, sort_keys=True, indent=2), encoding='utf-8')
    return identities


def _validate_pe(path):
    with path.open('rb') as source:
        header = source.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise ValueError('Application is not a PE')
        pe = struct.unpack_from('<I', header, 0x3c)[0]
        if pe > path.stat().st_size - 26:
            raise ValueError('PE header exceeds file bounds')
        source.seek(pe)
        coff = source.read(26)
        if (len(coff) != 26 or coff[:4] != b'PE\0\0' or
                struct.unpack_from('<H', coff, 4)[0] != 0x8664 or
                struct.unpack_from('<H', coff, 24)[0] != 0x20b):
            raise ValueError('Application must be x64 PE32+')


def _rc_path(path):
    value = path.resolve().as_posix()
    if any(c in value for c in '"\r\n\0'):
        raise ValueError('Path cannot be embedded in RC source')
    return value


def prepare(application, output, version, policy_path=None, current_store_format=None,
            publishable=False, resource_reader=None):
    version_tuple(version)
    application, output = Path(application), Path(output)
    if application.is_symlink() or application.is_junction() or not application.is_file():
        raise ValueError('Application must be a regular build output')
    size = application.stat().st_size
    if not 0 < size <= ARTIFACT_LIMIT:
        raise ValueError('Application exceeds setup bounds')
    _validate_pe(application)
    if publishable and policy_path is None:
        raise ValueError('Publishable profile requires an immutable update policy')
    policy = None
    if policy_path is not None:
        policy = canonical_policy(Path(policy_path).read_bytes(), current_store_format, publishable)
    reader = resource_reader or resource_bytes
    if reader(application, 'SERVERDECK_BUILD_V1') != f'SDBUILD001\n{version}\n'.encode('ascii'):
        raise ValueError('Mapped application build version differs from setup version')
    if reader(application, 'SERVERDECK_TRUST_V1') != policy:
        raise ValueError('Setup policy differs from the final application policy')
    with application.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    manifest = f'SDSETUP001\n{version}\n{size}\n{digest}\n'.encode('ascii')
    app_path = _rc_path(application)
    manifest_path = _rc_path(output / 'setup-manifest.txt')
    policy_resource_path = _rc_path(output / 'trust-policy.json')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'setup-manifest.txt').write_bytes(manifest)
    resource = (f'#pragma code_page(65001)\nSERVERDECK_APPLICATION_V1 RCDATA "{app_path}"\n'
                f'SERVERDECK_SETUP_V1 RCDATA "{manifest_path}"\n')
    if policy is not None:
        (output / 'trust-policy.json').write_bytes(policy)
        resource += f'SERVERDECK_TRUST_V1 RCDATA "{policy_resource_path}"\n'
    (output / 'setup.rc').write_text(resource, encoding='utf-8')
    result = {'version': version, 'appSize': size, 'appSha256': digest,
              'profile': 'publishable' if publishable else 'developer', 'policyEmbedded': policy is not None}
    (output / 'setup-inputs.json').write_text(json.dumps(result, sort_keys=True, indent=2), encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version')
    parser.add_argument('--policy', type=Path)
    parser.add_argument('--store-format', type=int)
    parser.add_argument('--publishable', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--canonicalize-policy', action='store_true')
    mode.add_argument('--audit-setup', type=Path)
    args = parser.parse_args()
    if args.canonicalize_policy:
        if args.policy is None or args.store_format is None:
            parser.error('Policy and current storage format are required')
        data = canonical_policy(args.policy.read_bytes(), args.store_format, args.publishable)
        args.output.mkdir(parents=True, exist_ok=True)
        destination = args.output / 'trust-policy.json'
        destination.write_bytes(data)
        (args.output / 'trust.rc').write_text(
            f'#pragma code_page(65001)\nSERVERDECK_TRUST_V1 RCDATA "{_rc_path(destination)}"\n', encoding='utf-8')
    else:
        if args.application is None or args.version is None:
            parser.error('Application and version are required')
        if args.audit_setup:
            audit_setup(args.application, args.audit_setup, args.output, args.version, args.policy, args.store_format, args.publishable)
        else:
            prepare(args.application, args.output, args.version, args.policy, args.store_format, args.publishable)


if __name__ == '__main__':
    main()
