#!/usr/bin/env python3
"""Generate rules from vanilla server JSON; never execute any game code."""
from pathlib import Path
import hashlib,json,re,sys,zipfile
if len(sys.argv)!=2:sys.exit('Użycie: update-enchantment-rules.py GAME_DATA_ZIP')
root=Path(__file__).resolve().parents[1];source=Path(sys.argv[1]);archive=zipfile.ZipFile(source)
def expand(value,kind,seen=()):
    if isinstance(value,list):return set().union(*(expand(v,kind,seen) for v in value)) if value else set()
    if isinstance(value,dict):return expand(value['id'],kind,seen)
    if not value.startswith('#'):return {value.removeprefix('minecraft:')}
    name=value.removeprefix('#minecraft:')
    if name in seen:raise ValueError('Cykliczny tag')
    return expand(json.loads(archive.read('data/minecraft/tags/'+kind+'/'+name+'.json'))['values'],kind,seen+(name,))
definitions={name.rsplit('/',1)[1][:-5]:json.loads(archive.read(name)) for name in archive.namelist() if name.startswith('data/minecraft/enchantment/') and name.endswith('.json')}
old={row[0]:row[2] for line in (root/'data/enchantments.tsv').read_text().splitlines() for row in [line.split('\t')]}
old['lunge']='szarża włócznią';old['breach']='przebicie pancerza (buzdygan)'
old['smite']='większe obrażenia nieumarłym';old['bane_of_arthropods']='większe obrażenia stawonogom'
old.update({'binding_curse': 'klątwa uniemożliwiająca zdjęcie założonego przedmiotu', 'fire_aspect': 'podpala trafionego przeciwnika', 'infinity': 'nie zużywa zwykłych strzał; potrzebna 1 strzała w ekwipunku', 'impaling': 'większe obrażenia wybranym wodnym mobom (trójząb)', 'riptide': 'napędza gracza rzutem trójzębu w wodzie lub deszczu', 'soul_speed': 'szybszy ruch po piasku dusz i glebie dusz (buty)', 'thorns': 'zadaje odwetowe obrażenia napastnikowi (zbroja)', 'unbreaking': 'spowalnia zużywanie się przedmiotów z trwałością', 'vanishing_curse': 'klątwa znikania przedmiotu po śmierci', 'wind_burst': 'odbija gracza w górę po trafieniu miażdżącym (buzdygan)'})
allowed=set();conflicts=set()
for name,data in definitions.items():
    for item in expand(data['supported_items'],'item'):allowed.add((name,item))
    for other in expand(data.get('exclusive_set',[]),'enchantment'):
        if name!=other:conflicts.add(tuple(sorted((name,other))))
(root/'data/enchantments.tsv').write_text(''.join(f'{name}\t{data["max_level"]}\t{old.get(name,name)}\n' for name,data in sorted(definitions.items())))
(root/'data/enchantment-items.tsv').write_text(''.join(f'{name}\t{item}\n' for name,item in sorted(allowed)))
(root/'data/enchantment-conflicts.tsv').write_text(''.join(f'{a}\t{b}\n' for a,b in sorted(conflicts)))
items=dict(line.split('\t') for line in (root/'data/items.tsv').read_text().splitlines());known=set(items.values());aliases=dict(line.split('\t') for line in (root/'data/item-aliases.tsv').read_text().splitlines())
materials={'wooden':('drewniany','drewniana','drewniane'),'stone':('kamienny','kamienna','kamienne'),'copper':('miedziany','miedziana','miedziane'),'iron':('zelazny','zelazna','zelazne'),'golden':('zloty','zlota','zlote'),'diamond':('diamentowy','diamentowa','diamentowe'),'netherite':('netherytowy','netherytowa','netherytowe')}
parts={'axe':('siekiera',1),'boots':('buty',2),'chestplate':('napiersnik',0),'helmet':('helm',0),'hoe':('motyka',1),'leggings':('nogawice',2),'pickaxe':('kilof',0),'shovel':('lopata',1),'spear':('wlocznia',1),'sword':('miecz',0)}
added=0
for item in sorted({item for name,item in allowed}-known):
    match=re.fullmatch(r'(wooden|stone|copper|iron|golden|diamond|netherite)_(axe|boots|chestplate|helmet|hoe|leggings|pickaxe|shovel|spear|sword)',item)
    if not match:raise ValueError('Brak polskiej nazwy nowego przedmiotu '+item)
    material,part=match.groups();noun,gender=parts[part];name=materials[material][gender]+'_'+noun
    assert name not in items and name not in aliases
    items[name]=item;added+=1
    if 'netheryt' in name:aliases[name.replace('netheryt','neteryt')]=item
(root/'data/items.tsv').write_text(''.join(f'{name}\t{item}\n' for name,item in sorted(items.items())))
(root/'data/item-aliases.tsv').write_text(''.join(f'{name}\t{item}\n' for name,item in sorted(aliases.items())))
(root/'data/enchantment-rules-source.txt').write_text('Vanilla Minecraft Java 26.3, JSON z używanego na serwerze mojang_26.3.jar.\nSHA256 archiwum danych wejściowych: '+hashlib.sha256(source.read_bytes()).hexdigest()+'\nReguły supported_items, max_level oraz exclusive_set rozwinięto z tagów gry.\nNiestandardowe datapacki mogą wymagać regeneracji.\n')
print(f'Zaklęcia: {len(definitions)}, reguły przedmiotów: {len(allowed)}, konflikty: {len(conflicts)}, nowe przedmioty: {added}')
