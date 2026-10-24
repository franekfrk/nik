#!/usr/bin/env python3
"""Check release boundaries and tracked private paths; not a general secret scanner."""
import re,subprocess,sys
from pathlib import Path
from release_manifest import FORBIDDEN,public_files

root=Path(__file__).resolve().parents[1]

def private_path(relative):
    p=Path(relative)
    if any(part in FORBIDDEN for part in p.parts):return True
    if 'config' in p.parts and not (p.name=='.gitkeep' and p.parent.name=='config'):return True
    return (p.name.startswith(('.env','id_rsa','id_ed25519')) or p.suffix in {'.pem','.key'}
            or p.name in {'nik-oryginal.sh','nik.local.sh'})

def main():
    files=public_files(root)
    git=subprocess.run(['git','-C',str(root),'rev-parse','--show-toplevel'],capture_output=True,text=True)
    if '--git' in sys.argv:assert git.returncode==0,'Kontrola Git wymaga repozytorium.'
    if git.returncode==0:
        repository=Path(git.stdout.strip())
        tracked=subprocess.check_output(['git','-C',str(repository),'ls-files','-z']).decode().split('\0')
        for relative in filter(None,tracked):
            assert not private_path(relative),'Prywatna ścieżka śledzona w Git: '+relative
            content=(repository/relative).read_bytes()
            assert not re.search(rb'(?m)^-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',content), 'Klucz prywatny w Git: '+relative
        prefix=root.relative_to(repository).as_posix()
        expected={p[len(prefix)+1:] for p in tracked if p.startswith(prefix+'/')} if prefix!='.' else set(filter(None,tracked))
        released={p.as_posix() for _,p in files}
        assert expected<=released, 'Pliki v2 poza manifestem: '+', '.join(sorted(expected-released))
    print(f'Audyt projektu OK: {len(files)} jawnych plików publicznej paczki; kontrola granic prywatności.')
if __name__=='__main__':
    try:main()
    except (AssertionError,OSError,ValueError,subprocess.SubprocessError) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(1)
