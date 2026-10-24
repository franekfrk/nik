#!/usr/bin/env python3
"""Check the complete item catalogue and its compatibility aliases."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]

def mapping(filename):
    result={}
    for number,line in enumerate((root/'data'/filename).read_text().splitlines(),1):
        fields=line.split('\t')
        if len(fields)!=2:
            raise SystemExit(f'{filename}:{number}: wymagane dwie kolumny')
        name,item=fields
        if not re.fullmatch(r'[a-z][a-z0-9_]*',name) or not re.fullmatch(r'[a-z0-9_]+',item):
            raise SystemExit(f'{filename}:{number}: nieprawidłowa nazwa lub ID')
        if name in result:
            raise SystemExit(f'{filename}:{number}: powtórzona nazwa')
        result[name]=item
    return result

items=mapping('items.tsv');aliases=mapping('item-aliases.tsv')
ids=set(items.values())
assert len(items)==len(ids), 'Kilka nazw głównych dla jednego ID'
assert not (items.keys() & aliases.keys()), 'Alias zasłania nazwę główną'
for name,item in aliases.items():
    assert item in ids, 'Alias wskazuje nieznany ID'
    assert name not in ids or name==item, 'Alias zmienia znaczenie angielskiego ID'
changes=(root/'data/item-renames.tsv').read_text().splitlines()
for line in changes:
    old,new,item,reason=line.split('\t')
    assert items.get(new)==item and aliases.get(old)==item, 'Brak zgodności starej nazwy'
assert not any(name.startswith('jajo_przyzywajace_') for name in items), 'Nieskrócona nazwa jaja'
assert items['jajo_niuchacza']=='sniffer_egg'
assert items['jajo_niuchacza_spawn']=='sniffer_spawn_egg'
registry=set((root/'data/registry-items.tsv').read_text().splitlines())
assert ids==registry-{'air'}, 'Katalog nie odpowiada rejestrowi gry'
effects={line.split('\t')[1] for line in (root/'data/effects.tsv').read_text().splitlines()}
assert effects==set((root/'data/registry-effects.tsv').read_text().splitlines()), 'Brak efektów'
assert aliases['chain']=='iron_chain'
enchants={line.split('\t')[0] for line in (root/'data/enchantments.tsv').read_text().splitlines()}
names=mapping('enchantment-names.tsv')
assert set(names.values())==enchants, 'Brak polskich nazw zaklęć'
assert len(names)==len(enchants), 'Kilka polskich nazw głównych jednego zaklęcia'
assert all(name not in enchants or name==target for name,target in names.items()), 'Polska nazwa zasłania angielską'
for line in (root/'data/enchantment-items.tsv').read_text().splitlines():
    enchant,item=line.split('\t'); assert enchant in enchants and item in ids, 'Błędna reguła zaklęcia'
for line in (root/'data/enchantment-conflicts.tsv').read_text().splitlines():
    a,b=line.split('\t'); assert a in enchants and b in enchants and a!=b, 'Błędny konflikt'

print(f'Audyt OK: {len(items)} przedmiotów, {len(aliases)} aliasów, {len(changes)} zmian nazw; brak kolizji i utraconych ID.')

creatures=mapping('creatures.tsv'); creature_aliases=mapping('creature-aliases.tsv')
assert len(set(creatures.values()))==len(creatures), 'Powtórzony ID stworzenia'
assert set(creatures.values())==set((root/'data/registry-creatures.tsv').read_text().splitlines()), 'Brak stworzeń w katalogu'
assert not (creatures.keys() & creature_aliases.keys()), 'Kolidujący alias stworzenia'
for name,id in {**creatures,**creature_aliases}.items():
    assert id in creatures.values(), 'Alias wskazuje nieznane stworzenie'
    assert name not in creatures.values() or name==id, 'Polska nazwa zasłania angielski ID'
print(f'Stworzenia: {len(creatures)} nazw, {len(creature_aliases)} aliasów — OK.')
