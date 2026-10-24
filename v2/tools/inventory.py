#!/usr/bin/env python3
"""Read vanilla SNBT inventory without eval, command execution, or external packages."""
import json,os,re,sys,unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class Snbt:
    def __init__(self,text):
        assert len(text)<=1048576,'Odpowiedź ekwipunku jest zbyt duża'
        self.text=text;self.i=0;self.nodes=0
    def ws(self):
        while self.i<len(self.text) and self.text[self.i].isspace():self.i+=1
    def take(self,char):
        self.ws();assert self.i<len(self.text) and self.text[self.i]==char,'Niepełna lub błędna odpowiedź SNBT'
        self.i+=1
    def string(self):
        quote=self.text[self.i];self.i+=1;out=[]
        while self.i<len(self.text):
            c=self.text[self.i];self.i+=1
            if c==quote:return ''.join(out)
            if c=='\\':
                assert self.i<len(self.text),'Niepełny tekst SNBT'
                c=self.text[self.i];self.i+=1
                escape={'n':'\n','r':'\r','t':'\t','b':'\b','f':'\f','\\':'\\','"':'"',"'":"'",'/':'/'}
                if c=='u':
                    h=self.text[self.i:self.i+4];assert re.fullmatch('[0-9a-fA-F]{4}',h),'Błędny znak Unicode SNBT'
                    out.append(chr(int(h,16)));self.i+=4
                else:assert c in escape,'Nieobsługiwany zapis tekstu SNBT';out.append(escape[c])
            else:out.append(c)
        raise AssertionError('Niepełny tekst SNBT')
    def bare(self,key=False):
        self.ws();start=self.i
        while self.i<len(self.text) and self.text[self.i] not in (':,{}[] \t\r\n' if key else ',{}[] \t\r\n'):self.i+=1
        assert self.i>start,'Brak wartości SNBT'
        return self.text[start:self.i]
    def value(self,depth=0):
        self.ws();self.nodes+=1
        assert depth<=64 and self.nodes<=100000,'Odpowiedź SNBT jest zbyt złożona'
        assert self.i<len(self.text),'Niepełna odpowiedź SNBT'
        c=self.text[self.i]
        if c in '\"\'':return self.string()
        if c=='{':
            self.i+=1;result={};self.ws()
            if self.i<len(self.text) and self.text[self.i]=='}':self.i+=1;return result
            while True:
                self.ws();assert self.i<len(self.text),'Niepełny obiekt SNBT'
                key=self.string() if self.text[self.i] in '\"\'' else self.bare(True)
                assert key not in result,'Powtórzony klucz SNBT'
                self.take(':');result[key]=self.value(depth+1);self.ws()
                if self.i<len(self.text) and self.text[self.i]=='}':self.i+=1;return result
                self.take(',')
        if c=='[':
            self.i+=1;result=[];self.ws()
            if self.text[self.i:self.i+2].upper() in {'B;','I;','L;'}:self.i+=2
            self.ws()
            if self.i<len(self.text) and self.text[self.i]==']':self.i+=1;return result
            while True:
                result.append(self.value(depth+1));self.ws()
                if self.i<len(self.text) and self.text[self.i]==']':self.i+=1;return result
                self.take(',')
        return self.bare()
    def parse(self):
        result=self.value();self.ws();assert self.i==len(self.text),'Nadmiarowe dane po SNBT';return result

def clean(text):
    return ''.join(c for c in str(text) if unicodedata.category(c) not in {'Cc','Cs','Cf'})[:200]

def integer(value):
    assert isinstance(value,str) and re.fullmatch(r'-?\d+[bBsSlL]?',value),'Błędna liczba w ekwipunku'
    return int(re.sub('[bBsSlL]$','',value))

class InventoryChanged(AssertionError):pass

def inventory_rows(raw,ender=False,detailed=False):
    found=re.fullmatch(r'.+ has the following entity data: (.+)',raw.strip())
    assert found,'Nie rozpoznano odpowiedzi Minecrafta na odczyt plecaka'
    items=Snbt(found[1]).parse();assert isinstance(items,list),'Odpowiedź plecaka nie jest listą'
    assert len(items)<=(27 if ender else 41),'Za dużo pozycji ekwipunku'
    names={line.split('\t')[1]:line.split('\t')[0] for line in (ROOT/'data/items.tsv').read_text().splitlines()}
    enchants={line.split('\t')[1]:line.split('\t')[0] for line in (ROOT/'data/enchantment-names.tsv').read_text().splitlines()}
    defaults={r.split('\t')[0]:int(r.split('\t')[1]) for r in (ROOT/'data/item-durability.tsv').read_text().splitlines()} if detailed else {}
    seen=set();rows=[]
    for entry in items:
        assert isinstance(entry,dict),'Błędny przedmiot w plecaku'
        slot=integer(entry.get('Slot',entry.get('slot')))
        if slot<0:slot+=256
        assert slot in range(27) if ender else slot in range(36) or slot in {100,101,102,103,150},'Nieznany slot plecaka'
        if slot in seen:raise InventoryChanged('Ekwipunek zmienił się podczas odczytu')
        seen.add(slot)
        item=entry.get('item',entry);assert isinstance(item,dict),'Błędny zapis przedmiotu'
        id=item.get('id');assert isinstance(id,str) and re.fullmatch(r'[a-z0-9_.-]+:[a-z0-9_./-]+',id),'Błędny identyfikator przedmiotu'
        count=integer(item.get('count',item.get('Count','1')));assert 1<=count<=2147483647,'Błędna liczba przedmiotów'
        components=item.get('components',{});assert isinstance(components,dict),'Błędne komponenty przedmiotu'
        details=[];enchantment_details=[]
        for component in ['minecraft:enchantments','minecraft:stored_enchantments']:
            values=components.get(component,{})
            assert isinstance(values,dict),'Błędny zapis zaklęć'
            values=values.get('levels',values);assert isinstance(values,dict),'Błędny zapis poziomów zaklęć'
            for enchant,level in values.items():
                level=integer(level);assert 0<=level<=255,'Błędny poziom zaklęcia'
                key=enchant.removeprefix('minecraft:')
                details.append(f'{enchants.get(key,clean(key)).replace("_"," ")}: {level}')
                enchantment_details.append({'id':clean(enchant),'name':enchants.get(key,clean(key)).replace('_',' '),'level':level,'stored':component=='minecraft:stored_enchantments'})
        if ender:label=f'slot {slot+1}';order=slot
        elif slot<9:label=f'pasek {slot+1}';order=slot
        elif slot<36:label=f'plecak {slot-8}';order=slot
        else:label={100:'buty',101:'nogawice',102:'napierśnik',103:'hełm',150:'druga ręka'}[slot];order=slot
        name=names.get(id.removeprefix('minecraft:'),clean(id)) if id.startswith('minecraft:') else clean(id)
        if detailed:
            damage=integer(components.get('minecraft:damage','0'));assert damage>=0,'Błędne zużycie przedmiotu'
            explicit=components.get('minecraft:max_damage');maximum=integer(explicit) if explicit is not None else defaults.get(id.removeprefix('minecraft:')) if id.startswith('minecraft:') else None
            assert maximum is None or 1<=maximum<=1000000,'Błędna trwałość przedmiotu'
            rows.append((order,{'slot':slot,'label':label,'id':id,'name':name.replace('_',' '),'count':count,'details':', '.join(details),'enchantments':enchantment_details,'damage':damage,'max_damage':maximum,'remaining':max(0,maximum-damage) if maximum else None,'durability_source':'component' if explicit is not None else 'vanilla_reference_26_1' if maximum else None,'unbreakable':'minecraft:unbreakable' in components}))
        else:rows.append((order,label,name,count,', '.join(details)))
    return [r[1] for r in sorted(rows)] if detailed else [r[1:] for r in sorted(rows)]

class NeedQuery(Exception):
    def __init__(self,path):self.path=path

class TruncatedSnbt(AssertionError):pass

def response_value(raw):
    found=re.fullmatch(r'.+ has the following entity data: (.+)',raw.strip())
    assert found,'Nie rozpoznano odpowiedzi Minecrafta na odczyt plecaka'
    text=found[1]
    # Minecraft can replace the rest of a translated component with an ellipsis.
    # Never accept the prefix as a complete inventory or silently drop its tail.
    try:return Snbt(text).parse()
    except AssertionError:
        if text.endswith('...'):raise TruncatedSnbt('Serwer skrócił odpowiedź ekwipunku') from None
        raise

def inventory_plan(replies,tag,detailed=False):
    assert tag in {'Inventory','EnderItems','SelectedItem'},'Nieprawidłowy rodzaj ekwipunku'
    assert isinstance(replies,dict) and len(replies)<=2500,'Zbyt wiele odczytów ekwipunku'
    def read(path,optional=False):
        if path not in replies:raise NeedQuery(path)
        raw=replies[path]
        assert isinstance(raw,str),'Błędna odpowiedź odczytu'
        if optional and raw.strip()=='Found no elements matching '+path:return None
        return response_value(raw)
    if tag=='SelectedItem':
        try:item=read(tag)
        except TruncatedSnbt:
            id=read(tag+'.id');damage=read(tag+'.components."minecraft:damage"',True)
            item={'id':id,'components':{'minecraft:damage':damage if damage is not None else '0'}}
        assert isinstance(item,dict) and 'id' in item,'Trzymaj przedmiot w głównej ręce'
        components=item.get('components',{});assert isinstance(components,dict),'Błędne komponenty przedmiotu'
        damage=integer(components.get('minecraft:damage','0'));assert damage>=0,'Błędne uszkodzenie przedmiotu'
        return damage
    def read_item(path,slot=None):
        try:entry=read(path,True)
        except TruncatedSnbt:
            if slot is None:
                slot=read(path+'.Slot',True)
                if slot is None:slot=read(path+'.slot')
            item_path=path;id=read(path+'.id',True)
            if id is None:item_path=path+'.item';id=read(item_path+'.id')
            count=read(item_path+'.count',True)
            if count is None:count=read(item_path+'.Count',True)
            entry={'Slot':slot,'id':id,'count':count if count is not None else '1','components':{}}
            if detailed:
                for component in ('minecraft:damage','minecraft:max_damage','minecraft:unbreakable'):
                    value=read(item_path+'.components."'+component+'"',True)
                    if value is not None:entry['components'][component]=value
            enchant_ids=[line.split('\t')[1] for line in (ROOT/'data/enchantment-names.tsv').read_text().splitlines()]
            for component in ('minecraft:enchantments','minecraft:stored_enchantments'):
                component_path=item_path+'.components."'+component+'"'
                try:values=read(component_path,True)
                except TruncatedSnbt:
                    level_path=component_path+'.levels'
                    try:legacy=read(level_path,True)
                    except TruncatedSnbt:legacy=True
                    if legacy is None:level_path=component_path
                    values={}
                    for enchant in enchant_ids:
                        level=read(level_path+'."minecraft:'+enchant+'"',True)
                        if level is not None:values['minecraft:'+enchant]=level
                if values is not None:entry['components'][component]=values
        if entry is not None and slot is not None:
            assert isinstance(entry,dict),'Błędny przedmiot wyposażenia'
            entry={**entry,'Slot':str(slot)}
        return entry
    try:items=read(tag)
    except TruncatedSnbt:
        items=[]
        for index in range(27 if tag=='EnderItems' else 41):
            entry=read_item(f'{tag}[{index}]')
            if entry is None:break
            items.append(entry)
    if detailed and tag=='Inventory':
        assert isinstance(items,list),'Błędna lista przedmiotów'
        present={integer(e.get('Slot',e.get('slot','-1')))%256 for e in items if isinstance(e,dict)}
        for part,slot in [('feet',100),('legs',101),('chest',102),('head',103),('offhand',150)]:
            if slot in present:continue
            entry=read_item('equipment.'+part,slot)
            if entry is not None:items.append(entry)
    # JSON is a strict subset of the SNBT accepted here. Reuse all existing slot,
    # ID, quantity and enchantment validation before presenting any rows.
    return inventory_rows('Player has the following entity data: '+json.dumps(items),tag=='EnderItems',detailed=detailed)

def planner_main(args):
    if args[0]=='--update':
        raw=sys.stdin.read();state,response=raw.split('\0',1);replies=json.loads(state)
        assert len(replies)<2500 and len(response)<=1048576,'Odpowiedź ekwipunku jest zbyt duża'
        replies[args[1]]=response;print(json.dumps(replies));return
    if args[0]=='--plan':
        replies=json.load(sys.stdin)
        detailed=bool(os.environ.get('NIK_RESULT_PATH')) and args[1]!='SelectedItem'
        try:rows=inventory_plan(replies,args[1],detailed=detailed)
        except NeedQuery as query:print('QUERY\t'+query.path);return
        except InventoryChanged:print('RETRY');return
        if detailed:
            from result_data import write_result
            write_result({'type':'inventory','kind':'ender' if args[1]=='EnderItems' else 'inventory','capacity':27 if args[1]=='EnderItems' else 36,'slots':rows})
            rows=[(r['label'],r['name'].replace(' ','_'),r['count'],r['details']) for r in rows]
        print('DONE')
        if isinstance(rows,int):print(rows);return
        for label,name,count,detail in rows:print(f'{label}\t{name}\t{count}\t{detail}')
        return
    raise AssertionError('Nieprawidłowy tryb odczytu')

def main():
    if sys.argv[1:2] in (["--plan"],["--update"]):return planner_main(sys.argv[1:])
    raw=sys.stdin.read()
    if sys.argv[1:]==['--damage']:
        found=re.fullmatch(r'.+ has the following entity data: (.+)',raw.strip());assert found,'Nie rozpoznano trzymanego przedmiotu'
        item=Snbt(found[1]).parse();assert isinstance(item,dict) and 'id' in item,'Trzymaj przedmiot w głównej ręce'
        components=item.get('components',{});assert isinstance(components,dict),'Błędne komponenty przedmiotu'
        damage=integer(components.get('minecraft:damage','0'));assert damage>=0,'Błędne uszkodzenie przedmiotu'
        print(damage);return
    rows=inventory_rows(raw,ender=sys.argv[1:]==['--ender'])
    for label,name,count,detail in rows:print(f'{label}\t{name}\t{count}\t{detail}')
if __name__=='__main__':
    try:main()
    except (AssertionError,ValueError,KeyError,TypeError,IndexError,OSError) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
