#!/usr/bin/env python3
"""Package a public tree plus an optional private config, never the whole repo."""
import argparse
import hashlib
import os
import tempfile
from pathlib import Path
import stat
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--private-config', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.out.mkdir(parents=True, exist_ok=True)
# An incidental file placed in lib/data/tools cannot enter a public release.
from release_manifest import public_files
try:
    files = public_files(root)
except (AssertionError,ValueError,OSError) as error:
    raise SystemExit('NIK: '+str(error)) from error

def archive(name, private=False):
    target = args.out / f'nik-v2-{name}.zip'
    entries = list(files)
    if private:
        if not args.private_config.is_dir():
            raise SystemExit('Brak prywatnej konfiguracji.')
        entries += [(file, Path('config') / file.relative_to(args.private_config))
                    for file in sorted(args.private_config.rglob('*'))
                    if file.is_file() and not file.is_symlink() and file.suffix != '.lock' and file.name != '.gitkeep']
    descriptor, pending = tempfile.mkstemp(prefix='.nik-package-', dir=args.out)
    os.close(descriptor)
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED) as output:
        for file, relative in entries:
            info = zipfile.ZipInfo(str(Path('nik-v2-' + name) / relative))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            executable = str(relative) in {'nik.sh', 'tests/check.sh', 'tools/migrate-v1.py', 'tools/package.py'}
            mode = (0o700 if executable else 0o600) if private else (0o755 if executable else 0o644)
            info.external_attr = (stat.S_IFREG | mode) << 16
            output.writestr(info, file.read_bytes())
    Path(pending).chmod(0o600 if private else 0o644)
    os.replace(pending, target)
    return target

outputs = [archive('public')]
if args.private_config:
    outputs.append(archive('private', True))
checksums = ''.join(hashlib.sha256(file.read_bytes()).hexdigest() + '  ' + file.name + '\n' for file in outputs)
(args.out / 'SHA256SUMS').write_text(checksums)
print('Utworzono: ' + ', '.join(file.name for file in outputs))
