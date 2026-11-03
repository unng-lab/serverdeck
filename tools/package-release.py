"""Build deterministic SDPKG001 resources and audit x64 PE import closure.

Only Python's standard library is used; Python is a build prerequisite, never
part of the delivered application. The manifest is UTF-8 SDMF001, tab-delimited.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys


def pe_imports(path):
    data = path.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError(f'Not a PE: {path.name}')
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Invalid PE signature')
    machine, count = struct.unpack_from('<HH', data, pe + 4)
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    optional = pe + 24
    if machine != 0x8664 or struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise ValueError(f'Not x64 PE32+: {path.name}')
    sections = []
    for index in range(count):
        offset = optional + optional_size + index * 40
        virtual_size, address, raw_size, raw = struct.unpack_from('<IIII', data, offset + 8)
        sections.append((address, max(virtual_size, raw_size), raw, raw_size))

    def rva(value, size=1):
        for address, length, raw, raw_size in sections:
            relative = value - address
            if 0 <= relative and relative + size <= min(length, raw_size):
                offset = raw + relative
                if offset + size <= len(data):
                    return offset
        raise ValueError('PE RVA outside raw sections')

    def string(value):
        offset = rva(value)
        end = data.find(b'\0', offset, offset + 260)
        if end == -1:
            raise ValueError('Unterminated PE import name')
        name = data[offset:end].decode('ascii').lower()
        if not re.fullmatch(r'[a-z0-9_.-]+\.dll', name):
            raise ValueError('Invalid PE module name')
        return name

    result = set()
    for directory, stride, name_offset in [(1, 20, 12), (13, 32, 4)]:
        table, length = struct.unpack_from('<II', data, optional + 112 + directory * 8)
        if not table:
            continue
        for index in range(min(length // stride, 10000)):
            offset = rva(table + index * stride, stride)
            if not any(data[offset:offset + stride]):
                break
            if directory == 13 and struct.unpack_from('<I', data, offset)[0] != 1:
                raise ValueError('Unsupported VA delay import')
            result.add(string(struct.unpack_from('<I', data, offset + name_offset)[0]))
        else:
            raise ValueError('Unterminated PE import table')
    return sorted(result)


def os_module(name, system):
    # CRT C++ support is redistributable, even if installed in System32 here.
    if name.startswith(('vcruntime', 'msvcp', 'concrt', 'vcomp')):
        return False
    return name.startswith(('api-ms-win-', 'ext-ms-win-')) or (system / name).is_file()


def audit(tree, system, redist):
    pending = list(tree.glob('*.dll'))
    checked = {}
    while pending:
        item = pending.pop()
        if item.name.lower() in checked:
            continue
        imports = pe_imports(item)
        checked[item.name.lower()] = imports
        for name in imports:
            if os_module(name, system):
                continue
            target = tree / name
            if not target.is_file():
                candidates = list(redist.glob(f'x64/Microsoft.VC143.CRT/{name}'))
                if len(candidates) != 1:
                    raise ValueError(f'Unresolved/nonunique non-OS import: {name}')
                shutil.copy2(candidates[0], target)
            pending.append(target)
    return checked


def audit_existing(tree, system):
    """Check an already supplied private runtime; never resolve/copy dependencies."""
    files = [path for path in tree.iterdir() if path.suffix.lower() in {'.exe', '.dll'}]
    names = {}
    for path in files:
        if path.is_symlink() or path.is_junction() or not path.is_file():
            raise ValueError('Invalid private runtime input')
        if path.name.lower() in names:
            raise ValueError('Case alias in private runtime')
        names[path.name.lower()] = path
    if not names:
        raise ValueError('Private runtime is empty')
    result = {}
    for name, path in names.items():
        imports = pe_imports(path)
        for dependency in imports:
            if not os_module(dependency, system) and dependency not in names:
                raise ValueError(f'Unresolved private runtime import: {name} -> {dependency}')
        result[name] = imports
    return result


def safe_path(name):
    if not name or len(name.encode('utf-16-le')) // 2 > 180 or '\\' in name:
        return False
    for part in name.split('/'):
        if not part or part in ('.', '..') or part[-1] in '. ':
            return False
        if any(ord(c) < 32 or c in ':<>"|?*' for c in part):
            return False
        base = part.split('.')[0].upper()
        if base in {'CON', 'PRN', 'AUX', 'NUL'} or re.fullmatch(r'(COM|LPT)[1-9¹²³]', base):
            return False
    return True


def package(tree, output, identities):
    files = []
    names = set()
    offset = 0
    for path in sorted((p for p in tree.rglob('*') if p.is_file()
                        and p.suffix.lower() not in ('.lib', '.exp', '.pdb')),
                       key=lambda p: p.relative_to(tree).as_posix().encode('utf-16-be')):
        name = path.relative_to(tree).as_posix()
        if path.is_symlink() or not safe_path(name) or name.casefold() in names:
            raise ValueError(f'Unsafe/duplicate package path: {name}')
        names.add(name.casefold())
        size = path.stat().st_size
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        files.append((path, f'file\t{size}\t{offset}\t{digest}\t{name}\n'))
        offset += size
    if len(files) > 10000 or offset > 2 * 1024 ** 3:
        raise ValueError('Payload exceeds limits')
    build = base64.b64encode(json.dumps(identities, sort_keys=True,
                                        separators=(',', ':')).encode()).decode()
    manifest = ('SDMF001\nhostAbi=1\nplatform=windows-x64\nbuild=' + build + '\n' +
                ''.join(line for _, line in files)).encode('utf-8')
    if len(manifest) > 4 * 1024 ** 2:
        raise ValueError('Manifest exceeds limit')
    output.mkdir(parents=True, exist_ok=True)
    bundle = output / 'payload.bin'
    with bundle.open('wb') as target:
        target.write(struct.pack('<8sIQQ', b'SDPKG001', 1, len(manifest), offset))
        target.write(manifest)
        for path, _ in files:
            with path.open('rb') as source:
                shutil.copyfileobj(source, target)
    (output / 'manifest.txt').write_bytes(manifest)
    (output / 'payload-id.txt').write_text(hashlib.sha256(manifest).hexdigest(), encoding='ascii')
    (output / 'payload.rc').write_text(
        f'#pragma code_page(65001)\nSERVERDECK_PAYLOAD_V1 RCDATA "{bundle.resolve().as_posix()}"\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tree', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--identities', type=Path)
    parser.add_argument('--redist', type=Path)
    parser.add_argument('--system', type=Path)
    parser.add_argument('--bootstrap', type=Path)
    parser.add_argument('--verify-tree', type=Path)
    args = parser.parse_args()
    if args.verify_tree:
        imports = audit_existing(args.verify_tree, args.system)
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'closure-imports.json').write_text(json.dumps(imports, indent=2))
    elif args.bootstrap:
        imports = pe_imports(args.bootstrap)
        if any(not os_module(name, args.system) for name in imports):
            raise ValueError(f'Bootstrap has non-OS imports: {imports}')
        (args.output / 'bootstrap-imports.json').write_text(json.dumps(imports, indent=2))
    else:
        imports = audit(args.tree, args.system, args.redist)
        identities = json.loads(args.identities.read_text(encoding='utf-8-sig'))
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'imports.json').write_text(json.dumps(imports, indent=2))
        package(args.tree, args.output, identities)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, struct.error) as error:
        sys.exit(str(error))
