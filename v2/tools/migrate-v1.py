#!/usr/bin/env python3
"""Import only the known NIK v1 layout, never execute shell source."""
import os
from pathlib import Path
import re
import shutil
import sys

def migrate(source, dest):
    text = source.read_text()
    players_match = re.search(r'declare -a MC_GRACZE=\(([^\n]*)\)', text)
    if not players_match:
        raise ValueError('Nie rozpoznano listy graczy NIK v1.')
    players = players_match.group(1).split()
    aliases_match = re.search(r'declare -A MC_GRACZE_SKROTY=\(([^\n]*)\)', text)
    if not aliases_match:
        raise ValueError('Nie rozpoznano skrótów NIK v1.')
    aliases = dict(re.findall(r'\[([a-z0-9_]+)\]="([a-z0-9_]+)"', aliases_match.group(1)))
    cases = re.search(r'gracz_nick\(\)\s*\{(.*?)\n\}', text, re.S)
    if not cases:
        raise ValueError('Nie rozpoznano funkcji gracza NIK v1.')
    nick_map = {}
    for alternatives, nick in re.findall(r'([a-z0-9_|]+)\)\s*echo "([^"\n]+)"', cases.group(1)):
        for name in alternatives.split('|'):
            nick_map[name] = nick
    rows = []
    for player in players:
        if not re.fullmatch(r'[a-z][a-z0-9_]*', player):
            raise ValueError('Nieprawidłowa nazwa gracza.')
        alias, nick = aliases.get(player), nick_map.get(player)
        if not alias or not nick or not re.fullmatch(r'\.?[a-zA-Z0-9_]{1,16}', nick):
            raise ValueError('Niekompletne dane gracza.')
        rows.append(f'{player}\t{alias}\t{nick}\n')
    def literal(name):
        match = re.search(r'^' + name + r'="([^"\n]*)"$', text, re.M)
        if not match:
            raise ValueError('Nie rozpoznano ustawienia ' + name)
        value = match.group(1)
        if name == 'MC_LOG':
            fallback = re.fullmatch(r'\$\{MC_LOG:-(.*)\}', value)
            if fallback:
                value = fallback.group(1)
            value = value.replace('${HOME}', str(Path.home())).replace('$HOME', str(Path.home()))
        if any(c in value for c in '$`\r\n'):
            raise ValueError('Nieobsługiwana ekspansja w ' + name)
        return value
    container = literal('MC_CONTAINER')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', container):
        raise ValueError('Nieprawidłowy kontener.')
    log = literal('MC_LOG')
    if not log.startswith('/'):
        raise ValueError('Nieprawidłowy log.')
    coords = []
    for axis in 'XYZ':
        match = re.search(r'^MC_DOM_' + axis + r'=("?)(-?[0-9]+(?:\.[0-9]+)?)\1$', text, re.M)
        if not match:
            raise ValueError('Nie rozpoznano współrzędnej domu.')
        coords.append(match.group(2))
    castle = re.search(r'zamek\(\)\s*\{(.*?)\n\}', text, re.S)
    match = re.search(r'rcon "tp \$nick (-?[0-9.]+) (-?[0-9.]+) (-?[0-9.]+)"', castle.group(1) if castle else '')
    if not match:
        raise ValueError('Nie rozpoznano współrzędnych zamku.')
    if dest.exists():
        raise ValueError('Katalog docelowy już istnieje; nie nadpisuję konfiguracji.')
    os.umask(0o077)
    shutil.copytree(Path(__file__).resolve().parents[1] / 'config.example', dest)
    (dest / 'config.env').write_text(f'CONTAINER={container}\nTIMEOUT=10\nCOMPONENTS=modern\nLOG_DAYS=30\nLOG={log}\n')
    (dest / 'players.tsv').write_text(''.join(rows))
    # v1 teleported in the current dimension; use explicit overworld after migration.
    (dest / 'places.tsv').write_text('dom\t'+'\t'.join(coords)+'\tminecraft:overworld\nzamek\t'+'\t'.join(match.groups())+'\tminecraft:overworld\n')
    for file in dest.rglob('*'):
        file.chmod(0o700 if file.is_dir() else 0o600)
    dest.chmod(0o700)
    print(f'Zaimportowano graczy: {len(rows)}; miejsca: 2. Nie kopiowano haseł spoza pliku.')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Użycie: migrate-v1.py STARY_PLIK NOWY_KATALOG_KONFIGURACJI')
    try:
        migrate(Path(sys.argv[1]), Path(sys.argv[2]))
    except (ValueError, OSError) as error:
        sys.exit(str(error))
