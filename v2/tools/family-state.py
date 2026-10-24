#!/usr/bin/env python3
"""Validated private task and protection records, plus literal task books."""
import datetime,json,re,sys,unicodedata,textwrap
from pathlib import Path
RULES={'mob_griefing':'false','fire_spread_radius_around_player':'0','tnt_explodes':'false','projectiles_can_break_blocks':'false'}
def text(value):
    assert isinstance(value,str) and 1<=len(value)<=512 and value.strip(),'Treść musi mieć 1–512 znaków'
    assert not any(unicodedata.category(c) in {'Cc','Cs'} for c in value),'Niedozwolony znak sterujący'
    return value

def load(path):
    p=Path(path);assert p.is_file() and not p.is_symlink() and p.stat().st_size<=8192,'Nieprawidłowy prywatny plik stanu'
    return json.loads(p.read_text())

def task(record,player,container):
    assert record['schema']==1 and record['player']==player and record['container']==container,'Zadanie należy do innego gracza lub kontenera'
    text(record['text']);assert record['status'] in {'aktywne','gotowe'},'Błędny status zadania'
    return record

def book(record):
    lines=textwrap.wrap(record['text'],width=18,break_long_words=True,break_on_hyphens=False)
    pages=[]
    for start in range(0,len(lines),9):
        pages.append({'text':'ZADANIE OD TATY ♥\n\n','color':'dark_green','bold':True,'extra':[
            {'text':'\n'.join(lines[start:start+9]),'color':'black','bold':False},
            {'text':'\n\nStatus: '+record['status'],'color':'dark_gray','bold':False}]})
    content={'title':'Zadanie od Taty','author':'Tata','pages':pages}
    return 'minecraft:written_book[minecraft:written_book_content='+json.dumps(content,ensure_ascii=False,separators=(',',':'))+']'

def capture_rules(container,replies):
    assert len(replies)==len(RULES),'Niepełny odczyt reguł'
    values={}
    for key,reply in zip(RULES,replies):
        m=re.fullmatch(r'Game rule (?:minecraft:)?'+re.escape(key)+r' is currently set to (true|false|-?\d+)',reply.strip())
        assert m,'Nie rozpoznano reguły: '+key
        value=m[1]
        assert value in {'true','false'} if key!='fire_spread_radius_around_player' else -1<=int(value)<=2147483647,'Błędna wartość reguły'
        values[key]=value
    return {'schema':1,'container':container,'values':values}

def main():
    mode=sys.argv[1]
    if mode in {'rules-capture','rules-values'}:
        record=capture_rules(sys.argv[2],sys.argv[3:])
        if mode=='rules-capture':print(json.dumps(record,ensure_ascii=False))
        else:
            for key,value in record['values'].items():print(key+'\t'+value)
        return
    if mode=='rules-read':
        record=load(sys.argv[2]);assert record['schema']==1 and record['container']==sys.argv[3] and set(record['values'])==set(RULES),'Błędny profil ochrony'
        replies=[f'Game rule {key} is currently set to {record["values"][key]}' for key in RULES]
        record=capture_rules(sys.argv[3],replies)
        for key,value in record['values'].items():print(key+'\t'+value)
        return
    if mode=='task-new':
        player,container=sys.argv[2:4];record={'schema':1,'player':player,'container':container,'text':text(' '.join(sys.argv[4:])),'status':'aktywne','created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    else:record=task(load(sys.argv[2]),*sys.argv[3:5])
    if mode=='task-done':record['status']='gotowe'
    if mode in {'task-new','task-done'}:print(json.dumps(record,ensure_ascii=False))
    elif mode=='task-book':print(book(record))
    elif mode=='task-read':print(record['status']+'\t'+record['text'])
    else:raise AssertionError('Nieznana operacja stanu')
if __name__=='__main__':
    try:main()
    except (AssertionError,ValueError,KeyError,TypeError,OSError,IndexError) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
