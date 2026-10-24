#!/usr/bin/env python3
"""Read vanilla SNBT inventory without eval, command execution, or external packages."""
import json,re,sys,unicodedata
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

def inventory_rows(raw,ender=False):
    found=re.fullmatch(r'.+ has the following entity data: (.+)',raw.strip())
    assert found,'Nie rozpoznano odpowiedzi Minecrafta na odczyt plecaka'
    items=Snbt(found[1]).parse();assert isinstance(items,list),'Odpowiedź plecaka nie jest listą'
    assert len(items)<=(27 if ender else 41),'Za dużo pozycji ekwipunku'
    names={line.split('\t')[1]:line.split('\t')[0] for line in (ROOT/'data/items.tsv').read_text().splitlines()}
    enchants={line.split('\t')[1]:line.split('\t')[0] for line in (ROOT/'data/enchantment-names.tsv').read_text().splitlines()}
    seen=set();rows=[]
    for entry in items:
        assert isinstance(entry,dict),'Błędny przedmiot w plecaku'
        slot=integer(entry.get('Slot',entry.get('slot')))
        if slot<0:slot+=256
        assert slot in range(27) if ender else slot in range(36) or slot in {100,101,102,103,150},'Nieznany slot plecaka'
        assert slot not in seen,'Powtórzony slot plecaka';seen.add(slot)
        item=entry.get('item',entry);assert isinstance(item,dict),'Błędny zapis przedmiotu'
        id=item.get('id');assert isinstance(id,str) and re.fullmatch(r'[a-z0-9_.-]+:[a-z0-9_./-]+',id),'Błędny identyfikator przedmiotu'
        count=integer(item.get('count',item.get('Count','1')));assert 1<=count<=2147483647,'Błędna liczba przedmiotów'
        components=item.get('components',{});assert isinstance(components,dict),'Błędne komponenty przedmiotu'
        details=[]
        for component in ['minecraft:enchantments','minecraft:stored_enchantments']:
            values=components.get(component,{})
            assert isinstance(values,dict),'Błędny zapis zaklęć'
            values=values.get('levels',values);assert isinstance(values,dict),'Błędny zapis poziomów zaklęć'
            for enchant,level in values.items():
                level=integer(level);assert 0<=level<=255,'Błędny poziom zaklęcia'
                key=enchant.removeprefix('minecraft:')
                details.append(f'{enchants.get(key,clean(key)).replace("_"," ")}: {level}')
        if ender:label=f'slot {slot+1}';order=slot
        elif slot<9:label=f'pasek {slot+1}';order=slot
        elif slot<36:label=f'plecak {slot-8}';order=slot
        else:label={100:'buty',101:'nogawice',102:'napierśnik',103:'hełm',150:'druga ręka'}[slot];order=slot
        name=names.get(id.removeprefix('minecraft:'),clean(id)) if id.startswith('minecraft:') else clean(id)
        rows.append((order,label,name,count,', '.join(details)))
    return [r[1:] for r in sorted(rows)]

def main():
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
    except (AssertionError,ValueError,KeyError,TypeError,IndexError) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
