#!/usr/bin/env python3
"""Literal HUD components, validated private challenges/rewards, vanilla recipes."""
import json, math, secrets, sys
from pathlib import Path
from dad_message_compat import literal

def guidance(record, destination):
    x,y,z,dimension=destination
    x,y,z=map(float,(x,y,z))
    assert record['dimension']==dimension, 'Cel jest w innym wymiarze. Przejdź do niego i uruchom prowadzenie ponownie.'
    px,py,pz=map(float,record['position']); yaw=float(record['rotation'][0])
    dx,dz=x-px,z-pz
    distance=math.hypot(dx,dz)
    bearing=math.degrees(math.atan2(-dx,dz))
    relative=(bearing-yaw+180)%360-180
    directions=['przed Tobą','z przodu po prawej','po prawej','z tyłu po prawej','za Tobą','z tyłu po lewej','po lewej','z przodu po lewej']
    direction=directions[int((relative+22.5)%360//45)]
    if distance<3:
        return f'Cel w pobliżu | różnica wysokości {y-py:+.0f} bloków', True
    return f'{direction} | {distance:.0f} bloków | różnica wysokości {y-py:+.0f}', False

def read_lines(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=65536, 'Brak lub nieprawidłowy plik ustawień zabawy.'
    return [l.strip() for l in path.read_text().splitlines() if l.strip() and not l.startswith('#')]

def challenges(path):
    lines=read_lines(path)
    assert 1<=len(lines)<=1000, 'Lista wyzwań musi zawierać 1–1000 wpisów.'
    for line in lines: literal(line)
    return lines

def rewards(path,items):
    rows=[]
    for line in read_lines(path):
        parts=line.split('\t')
        assert len(parts)==2 and parts[0] in items and parts[1].isascii() and parts[1].isdigit(), 'Nagroda: wymagane ID przedmiotu i ilość rozdzielone tabulatorem.'
        amount=int(parts[1]); assert 1<=amount<=2304, 'Ilość nagrody poza zakresem 1–2304.'
        rows.append((parts[0],amount))
    assert 1<=len(rows)<=36, 'Nagroda musi zawierać 1–36 pozycji.'
    return rows

def recipe_lines(data,item,names):
    recipes=data['recipes']; tags=data['tags']
    def ingredient(value,seen=()):
        if isinstance(value,list):return ' / '.join(ingredient(v,seen) for v in value)
        if value.startswith('#'):
            key=value[1:]
            if key in seen:return key
            values=tags.get(key,[])
            if not values:return key
            expanded=[ingredient(v,(*seen,key)) for v in values]
            return ' / '.join(dict.fromkeys(expanded))
        return names.get(value.removeprefix('minecraft:'),value)
    found=[]
    for key,r in recipes.items():
        result=r.get('result',{})
        if isinstance(result,str):result={'id':result}
        if result.get('id')=='minecraft:'+item:found.append((key,r,result))
    if not found:return ['Brak stałej receptury dla tego przedmiotu w vanilla 26.3. Może pochodzić z łupów, handlu lub receptury specjalnej.']
    methods={'crafting_shaped':'Stół rzemieślniczy — układ','crafting_shapeless':'Wytwarzanie — dowolny układ','smelting':'Piec','blasting':'Piec hutniczy','smoking':'Wędzarka','campfire_cooking':'Ognisko','stonecutting':'Przecinarka','smithing_transform':'Stół kowalski','smithing_trim':'Stół kowalski'}
    lines=[]
    for key,r,result in found:
        kind=r['type'].removeprefix('minecraft:')
        lines += [f"{methods.get(kind,kind)} | wynik: {result.get('count',1)} szt.",f'Receptura: {key}']
        if kind=='crafting_shaped':
            symbols={c:str(i+1) for i,c in enumerate(r['key'])}
            for row in r['pattern']:lines.append('  '+' | '.join(symbols.get(c,'·') for c in row))
            lines += [f'{symbols[c]} = {ingredient(v)}' for c,v in r['key'].items()]
        elif 'ingredients' in r:lines += [f'• {ingredient(v)}' for v in r['ingredients']]
        else:
            for k,label in [('ingredient','Składnik'),('template','Szablon'),('base','Baza'),('addition','Dodatek')]:
                if k in r:lines.append(f'{label}: {ingredient(r[k])}')
        if 'cookingtime' in r:lines.append(f"Czas: {r['cookingtime']/20:g} s przy 20 TPS")
        lines.append('')
    return lines

def main():
    mode=sys.argv[1]
    if mode=='hud': print(json.dumps({'text':literal(' '.join(sys.argv[2:])),'color':'aqua','bold':True},ensure_ascii=False))
    elif mode=='guide':
        record=json.load(sys.stdin)
        # Reuse the strict position/rotation validator before calculations.
        from location import validate
        validate(record,sys.argv[2],sys.argv[3])
        text,arrived=guidance(record,sys.argv[4:8])
        print(('1' if arrived else '0')+'\t'+text)
    elif mode=='challenge':print(secrets.choice(challenges(Path(sys.argv[2]))))
    elif mode=='rewards':
        items={line.split('\t')[1].strip() for line in Path(sys.argv[3]).read_text().splitlines()}
        for id,count in rewards(Path(sys.argv[2]),items):print(id+'\t'+str(count))
    elif mode=='recipe':
        root=Path(sys.argv[2]);names={v:k for k,v in (l.split('\t') for l in (root/'data/items.tsv').read_text().splitlines())}
        print('\n'.join(recipe_lines(json.loads((root/'data/recipes.json').read_text()),sys.argv[3],names)))
    else:raise AssertionError('Nieznana operacja zabawy.')
if __name__=='__main__':
    try:main()
    except (AssertionError,ValueError,KeyError,TypeError,OSError) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
