"""Stateless checks of the delivered EXE. Does not launch the GUI or open data."""
import argparse
import base64
import ctypes
from ctypes import wintypes
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import struct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', type=Path, required=True)
    parser.add_argument('--native-tests', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verification-runtime', type=Path)
    args = parser.parse_args()
    results = []
    for arguments, expected, error in [
        (['--mcp-stdio', '--client', '12345678-1234-4234-8234-123456789abc'], 20, b'MCP_UNAVAILABLE\n'),
        (['--mcp-stdio'], 2, b''),
        (['--mcp-stdio', '--client', 'invalid'], 2, b''),
        (['--unknown'], 2, b''),
    ]:
        process = subprocess.run([str(args.exe.resolve()), *arguments],
                                 capture_output=True, timeout=10,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        if process.returncode != expected or process.stdout or process.stderr != error:
            raise RuntimeError(f'Reserved argument branch failed: {arguments}')
        results.append({'args': arguments, 'exit': process.returncode,
                        'stdoutBytes': len(process.stdout), 'stderr': process.stderr.decode()})
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    kernel.LoadLibraryExW.restype = wintypes.HMODULE
    kernel.FindResourceW.argtypes = [wintypes.HMODULE, wintypes.LPCWSTR, ctypes.c_void_p]
    kernel.FindResourceW.restype = wintypes.HRSRC
    kernel.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HRSRC]
    kernel.SizeofResource.restype = wintypes.DWORD
    kernel.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HRSRC]
    kernel.LoadResource.restype = wintypes.HGLOBAL
    kernel.LockResource.argtypes = [wintypes.HGLOBAL]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
    module = kernel.LoadLibraryExW(str(args.exe.resolve()), None, 0x22)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        resource = kernel.FindResourceW(module, 'SERVERDECK_PAYLOAD_V1', ctypes.c_void_p(10))
        if not resource:
            raise RuntimeError('Missing embedded payload')
        size = kernel.SizeofResource(module, resource)
        pointer = kernel.LockResource(kernel.LoadResource(module, resource))
        if not pointer or not size:
            raise RuntimeError('Unreadable embedded payload')
        with tempfile.TemporaryDirectory(prefix='serverdeck-release-probe-') as directory:
            bundle = Path(directory) / 'payload.bin'
            embedded = ctypes.string_at(pointer, size)
            bundle.write_bytes(embedded)
            process = subprocess.run([str(args.native_tests.resolve() / 'payload_test.exe'), str(bundle)],
                                     capture_output=True, timeout=120,
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            if process.returncode:
                raise RuntimeError(f'Embedded payload/cache probe failed: {process.returncode}, {process.stderr.decode(errors="replace")}')
            results.append({'test': 'embedded payload/extraction/reuse/corruption quarantine', 'exit': 0})
            _, _, manifest_length, _ = struct.unpack_from('<8sIQQ', embedded)
            manifest = embedded[28:28 + manifest_length].decode('utf-8')
            records = {parts[4]: parts for line in manifest.splitlines()
                       if (parts := line.split('\t'))[0] == 'file'}
            verification_runtime = {}
            if args.verification_runtime:
                destination = args.verification_runtime.absolute()
                for ancestor in (destination, *destination.parents):
                    if ancestor.is_symlink() or ancestor.is_junction():
                        raise RuntimeError('Verification runtime destination has a reparse point')
                destination.mkdir(parents=True, exist_ok=True)
                for name in ('libisar.dll', 'vcruntime140.dll', 'licenses/isar_community.txt',
                             'licenses/isar_community_flutter_libs.txt'):
                    record = records[name]
                    length, offset, digest = int(record[1]), int(record[2]), record[3]
                    start = 28 + manifest_length + offset
                    data = embedded[start:start + length]
                    if hashlib.sha256(data).hexdigest() != digest:
                        raise RuntimeError('Verification runtime does not match embedded manifest')
                    target = destination / name
                    for ancestor in (target, *target.parents):
                        if ancestor.is_symlink() or ancestor.is_junction():
                            raise RuntimeError('Verification runtime file path has a reparse point')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                    verification_runtime[name] = digest
                results.append({'test': 'verification runtime bytes match the actual embedded manifest', 'exit': 0})
            build_record = next(line for line in manifest.splitlines() if line.startswith('build='))
            build_identities = json.loads(base64.b64decode(build_record[6:], validate=True))
            if not isinstance(build_identities, dict):
                raise RuntimeError('Embedded build identities must be an object')
            host_record = next(line.split('\t') for line in manifest.splitlines()
                               if line.endswith('\tserverdeck_host.dll'))
            host_size, host_offset = int(host_record[1]), int(host_record[2])
            host_path = Path(directory) / 'host.dll'
            start = 28 + manifest_length + host_offset
            host_path.write_bytes(embedded[start:start + host_size])
            host_bytes = embedded[start:start + host_size]
            # Inspect the real host artifact; a correctly compiled test helper
            # alone cannot prove that the host used the same source charset.
            labels = ['\u041e\u0442\u043a\u0440\u044b\u0442\u044c', '\u0412\u044b\u0445\u043e\u0434']
            if any(label.encode('utf-16-le') + b'\0\0' not in host_bytes for label in labels):
                raise RuntimeError('Native host tray labels have incorrect Unicode code points')
            results.append({'test': 'actual host native tray labels contain correct Unicode code points', 'exit': 0})
            host = kernel.LoadLibraryExW(str(host_path), None, 0x22)
            if not host:
                raise RuntimeError('Cannot inspect host icon resource')
            try:
                icon = kernel.FindResourceW(host, ctypes.cast(ctypes.c_void_p(1), wintypes.LPCWSTR), ctypes.c_void_p(3))
                if not icon:
                    raise RuntimeError('Host brand icon resource is absent')
                icon_size = kernel.SizeofResource(host, icon)
                icon_bytes = ctypes.string_at(kernel.LockResource(kernel.LoadResource(host, icon)), icon_size)
                brand = (Path(__file__).resolve().parent.parent /
                         'assets/brand/logos/mark-dark.png').read_bytes()
                if icon_bytes != brand:
                    raise RuntimeError('Host icon does not contain the unchanged brand001 mark')
                results.append({'test': 'host native icon resource matches brand001 PNG', 'exit': 0})
            finally:
                kernel.FreeLibrary(host)
    finally:
        kernel.FreeLibrary(module)
    with args.exe.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        'scope': 'local stateless arguments and native payload; GUI/clean offline VM NOT checked',
        'exeSHA256': digest, 'embeddedBuildIdentities': build_identities,
        'verificationRuntimeSHA256': verification_runtime, 'results': results,
    }, indent=2), encoding='utf-8')
    print(f'{len(results)} local release probes passed; clean offline VM gate remains pending')


if __name__ == '__main__':
    main()
