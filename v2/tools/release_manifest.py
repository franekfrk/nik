"""The release is an explicit, reviewed list; a broad directory is not consent."""
import json
from pathlib import Path

ROOTS={'nik.sh','panel','lib','data','config.example','config','tests','tools','extensions','.github','.gitignore','.shellcheckrc','README.md','VALIDATION.md','ARCHITECTURE.md','SECURITY.md'}
FORBIDDEN={'__pycache__','.git','.aws','.codex','.agents','private','dist','state','world-backups','backups','logs'}

def public_files(root):
    manifest=root/'tools/public-files.json'
    assert not manifest.is_symlink(), 'Manifest paczki nie może być dowiązaniem.'
    values=json.loads(manifest.read_text())
    assert isinstance(values,list) and values and all(isinstance(v,str) for v in values), 'Nieprawidłowy manifest paczki.'
    assert len(values)==len(set(values)), 'Powtórzony plik manifestu.'
    entries=[]
    for value in values:
        relative=Path(value)
        assert not relative.is_absolute() and value==relative.as_posix() and not any(p in {'..','.'} for p in relative.parts), 'Nieprawidłowa ścieżka w manifeście.'
        assert relative.parts[0] in ROOTS and not any(p in FORBIDDEN for p in relative.parts), 'Prywatny katalog w manifeście.'
        assert relative.parts[0]!='config' or value=='config/.gitkeep', 'Prywatna konfiguracja w manifeście.'
        assert not relative.name.startswith(('.env','id_rsa','id_ed25519')) and relative.suffix not in {'.key','.pem','.log','.zip','.gz','.pyc'}, 'Zabroniony rodzaj pliku w manifeście.'
        current=root
        for part in relative.parts:
            current=current/part
            assert not current.is_symlink(), 'Dowiązanie w ścieżce pliku paczki.'
        assert current.is_file(), 'Brak wymaganego pliku: '+value
        entries.append((current,relative))
    assert 'tools/public-files.json' in values, 'Manifest musi należeć do paczki.'
    return entries
