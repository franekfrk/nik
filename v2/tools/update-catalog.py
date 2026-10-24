#!/usr/bin/env python3
"""Merge vanilla registries + Mojang Polish language into the NIK catalogue."""
from pathlib import Path
import json,re,sys,unicodedata,hashlib
if len(sys.argv)!=3:sys.exit('Użycie: update-catalog.py REGISTRIES_JSON PL_PL_JSON')
root=Path(__file__).resolve().parents[1];regpath=Path(sys.argv[1]);plpath=Path(sys.argv[2]);reg=json.loads(regpath.read_text());pl=json.loads(plpath.read_text())
items=dict(line.split('\t') for line in (root/'data/items.tsv').read_text().splitlines());aliases=dict(line.split('\t') for line in (root/'data/item-aliases.tsv').read_text().splitlines())
# The generic chain ID was renamed to iron_chain in the Copper Age update.
old_names=[name for name,item in items.items() if item=='chain']
for name in old_names:
 del items[name];items['zelazny_lancuch']='iron_chain';aliases[name]='iron_chain'
 with (root/'data/item-renames.tsv').open('a') as f:f.write(name+'\tzelazny_lancuch\tiron_chain\trozróżnienie żelaznego i miedzianego łańcucha\n')
for name,item in list(aliases.items()):
 if item=='chain':aliases[name]='iron_chain'
aliases['chain']='iron_chain'
(root/'data/item-id-migrations.tsv').write_text('chain\tiron_chain\n')
def normal(text):
 text=text.lower().replace('ł','l');text=unicodedata.normalize('NFKD',text).encode('ascii','ignore').decode()
 return re.sub('[^a-z0-9]+','_',text).strip('_')
map_names={'abandoned_camp_map':'mapa_obozowiska','buried_ancient_city_map':'mapa_pradawnego_miasta','buried_mineshaft_map':'mapa_kopalni','buried_treasure_map':'mapa_skarbu','buried_trial_chambers_map':'mapa_komnat_prob','desert_pyramid_map':'mapa_pustynnej_piramidy','desert_village_map':'mapa_pustynnej_wioski','jungle_pyramid_map':'mapa_dzunglowej_piramidy','ocean_monument_map':'mapa_swiatyni','plains_village_map':'mapa_rowninnej_wioski','savanna_village_map':'mapa_sawannowej_wioski','snowy_village_map':'mapa_snieznej_wioski','swamp_hut_map':'mapa_chatki_wiedzmy','taiga_village_map':'mapa_tajgowej_wioski','warm_ocean_ruins_map':'mapa_podwodnych_ruin','woodland_mansion_map':'mapa_lesnego_dworu'}
spawn_names={'camel_husk_spawn_egg':'jajo_wielblada_posucha','copper_golem_spawn_egg':'jajo_miedzianego_golema','happy_ghast_spawn_egg':'jajo_wesolego_ghasta','nautilus_spawn_egg':'jajo_lodzika','parched_spawn_egg':'jajo_oschlaka','sulfur_cube_spawn_egg':'jajo_kostki_siarki','zombie_nautilus_spawn_egg':'jajo_lodzika_zombie'}
official={name.removeprefix('minecraft:') for name in reg['minecraft:item']['entries']};known=set(items.values());added=0
for item in sorted(official-known-{'air'}):
 label=pl.get('item.minecraft.'+item,pl.get('block.minecraft.'+item))
 if not label:raise ValueError('Brak tłumaczenia dla '+item)
 long=normal(label);name=map_names.get(item,spawn_names.get(item,long))
 if item.startswith('music_disc_'):name='plyta_'+item.removeprefix('music_disc_')
 if name in items or name in aliases:raise ValueError('Kolizja nowej nazwy '+name+' dla '+item)
 items[name]=item;added+=1
 if long!=name and long not in items and long not in aliases and not item.startswith('music_disc_'):aliases[long]=item
 for prefix in ['spawn_'] if item.endswith('_spawn_egg') else []:aliases[prefix+name.removeprefix('jajo_')]=item
 assert item in official
assert set(items.values())==official-{'air'}
(root/'data/items.tsv').write_text(''.join(f'{name}\t{item}\n' for name,item in sorted(items.items())))
(root/'data/item-aliases.tsv').write_text(''.join(f'{name}\t{item}\n' for name,item in sorted(aliases.items())))
(root/'data/registry-items.tsv').write_text(''.join(item+'\n' for item in sorted(official)))
effect_descriptions={row[0]:row[2] if len(row)>2 else '' for line in (root/'data/effects.tsv').read_text().splitlines() for row in [line.split('\t')]}
effects=dict(line.split('\t')[:2] for line in (root/'data/effects.tsv').read_text().splitlines());known_effects=set(effects.values())
for item in reg['minecraft:mob_effect']['entries']:
 item=item.removeprefix('minecraft:')
 if item not in known_effects:effects[normal(pl['effect.minecraft.'+item])]=item
(root/'data/effects.tsv').write_text(''.join(f'{name}\t{item}\t{effect_descriptions.get(name) or pl.get("effect.minecraft."+item,item)}\n' for name,item in sorted(effects.items())))
(root/'data/registry-effects.tsv').write_text(''.join(item.removeprefix('minecraft:')+'\n' for item in sorted(reg['minecraft:mob_effect']['entries'])))
(root/'data/catalog-source.txt').write_text('Minecraft Java 26.3: rejestry wygenerowane przez net.minecraft.data.Main --reports.\nNazwy nowych przedmiotów: oficjalny plik Mojang minecraft/lang/pl_pl.json, uproszczone dla CLI.\nSHA256 rejestru: '+hashlib.sha256(regpath.read_bytes()).hexdigest()+'\nSHA1 pliku PL: '+hashlib.sha1(plpath.read_bytes()).hexdigest()+'\nWykluczono air, którego nie można otrzymać jako normalnego przedmiotu.\n')
print(f'Katalog: {len(items)} przedmiotów, {len(aliases)} aliasów, {len(effects)} efektów; dodano {added} przedmiotów.')
