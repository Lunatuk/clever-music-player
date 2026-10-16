"""Offline distribution checks, including sources/licenses and PE dependencies."""
import argparse
import json
from pathlib import Path
import struct

from build_media_helper import BINARIES, SOURCES, digest


def pe_imports(file):
    data = file.read_bytes()
    if data[:2] != b'MZ':
        raise ValueError('Not PE: ' + file.name)
    header = struct.unpack_from('<I', data, 0x3c)[0]
    machine, count = struct.unpack_from('<HH', data, header + 4)
    size = struct.unpack_from('<H', data, header + 20)[0]
    optional = header + 24
    if data[header:header + 4] != b'PE\0\0' or machine != 0x8664 or struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise ValueError('Expected x64 PE: ' + file.name)
    sections = []
    for index in range(count):
        offset = optional + size + 40 * index
        virtual_size, address, raw_size, pointer = struct.unpack_from('<IIII', data, offset + 8)
        sections.append((address, max(virtual_size, raw_size), pointer, raw_size))

    def rva(value):
        for address, span, pointer, raw_size in sections:
            if address <= value < address + span:
                if value - address >= raw_size:
                    break
                return pointer + value - address
        raise ValueError('Invalid PE RVA: ' + file.name)

    imports_rva = struct.unpack_from('<I', data, optional + 112 + 8)[0]
    delay_rva = struct.unpack_from('<I', data, optional + 112 + 13 * 8)[0]
    if delay_rva:
        raise ValueError('Unexpected delayed dependency: ' + file.name)
    result = set()
    offset = rva(imports_rva)
    for _ in range(128):
        descriptor = struct.unpack_from('<IIIII', data, offset)
        if not any(descriptor):
            return result
        name = rva(descriptor[3])
        end = data.index(b'\0', name, name + 256)
        result.add(data[name:end].decode('ascii').lower())
        offset += 20
    raise ValueError('Too many imports: ' + file.name)


def verify(root):
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf8'))
    if (manifest['schema'], manifest['profile'], manifest['target'], manifest['ffmpegVersion']) != (1, 'cmp-audio-1', 'windows-x64', '7.1.5'):
        raise ValueError('Incompatible bundle manifest.')
    if set(manifest['files']) != set(BINARIES):
        raise ValueError('Wrong binary set.')
    system = {'kernel32.dll', 'shell32.dll', 'psapi.dll', 'bcrypt.dll'}
    supplied = {name.lower() for name in BINARIES if name.endswith('.dll')}
    dependencies = {}
    for name in BINARIES:
        file = root / name
        evidence = manifest['files'][name]
        if file.stat().st_size != evidence['bytes'] or digest(file) != evidence['sha256']:
            raise ValueError('Binary evidence mismatch: ' + name)
        imports = pe_imports(file)
        if not imports <= system | supplied:
            raise ValueError('Unbundled dependencies: ' + str(imports - system - supplied))
        dependencies[name] = sorted(imports)
    for name, (_, expected) in SOURCES.items():
        if digest(root / 'sources' / name) != expected:
            raise ValueError('Corresponding source mismatch: ' + name)
    for name in ['COPYING.LGPLv2.1', 'FFmpeg-LICENSE.md', 'zlib-LICENSE.txt', 'NOTICE.txt',
                 'sources/build_media_helper.py', 'sources/build-info.json', 'sources/media_helper_NOTICE.txt']:
        if not (root / name).is_file() or (root / name).stat().st_size == 0:
            raise ValueError('Missing distribution notice/recipe: ' + name)
    return {'runtimeBytes': sum((root / name).stat().st_size for name in BINARIES),
            'files': len([file for file in root.rglob('*') if file.is_file()]),
            'dependencies': dependencies}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.bundle), indent=2))
