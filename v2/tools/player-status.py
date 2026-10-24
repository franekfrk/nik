#!/usr/bin/env python3
"""Typed read-only player snapshots for NIK CLI and its optional interfaces."""
import json,os,re,sys
from location import payload,vector,DIM,number

def online(nick,raw):
 found=re.fullmatch(r'There are (\d+) of a max of (\d+) players online:\s*(.*)',raw.strip())
 assert found,'Nie rozpoznano listy graczy online'
 names=[name.strip() for name in found[3].split(',') if name.strip()]
 assert len(names)==int(found[1]) and all(re.fullmatch(r'\.?[A-Za-z0-9_]{1,16}',n) for n in names),'Nieprawidłowa lista online'
 return nick.casefold() in {n.casefold() for n in names}

def snapshot(id,health,food,mode,pos,dimension):
 health=float(number(re.sub('[fFdD]$','',payload(health)),1000000));assert health>=0,'Błędne zdrowie'
 food=int(payload(food));assert 0<=food<=20,'Błędny głód'
 mode=int(payload(mode));assert mode in range(4),'Błędny tryb gry'
 dim=json.loads(payload(dimension));assert isinstance(dim,str) and DIM.fullmatch(dim),'Błędny wymiar'
 return {'id':id,'online':True,'health':health,'food':food,'mode':['przetrwanie','kreatywny','przygodowy','obserwator'][mode],'position':[float(v) for v in vector(pos,3,30000000)],'dimension':dim}

def main():
 action=sys.argv[1]
 if action=='online':print('true' if online(*sys.argv[2:]) else 'false')
 elif action=='snapshot':print(json.dumps(snapshot(*sys.argv[2:]),ensure_ascii=False))
 elif action=='offline':print(json.dumps({'id':sys.argv[2],'online':False}))
 elif action=='error':print(json.dumps({'id':sys.argv[2],'online':True,'error':'Nie udało się odczytać danych; gracz mógł wyjść z gry.'}))
 elif action=='collect':
  records=[json.loads(line) for line in sys.stdin if line.strip()]
  if sys.argv[2]=='json':print(json.dumps({'players':records},ensure_ascii=False))
  else:
   setting=os.environ.get('NIK_COLOR','auto');color=setting=='always' or (setting!='never' and not os.environ.get('NO_COLOR') and sys.stdout.isatty())
   for p in records:
    title=p['id']+' · '+('online' if p['online'] else 'offline')
    print(('\033[92m'+title+'\033[0m') if color else title)
    if p.get('error'):print('  '+p['error'])
    elif p['online']:print(f"  Zdrowie: {p['health']:g} HP · jedzenie: {p['food']}/20 · {p['mode']}\n  Pozycja: "+', '.join(f'{n:.1f}' for n in p['position'])+' · '+p['dimension'])
 else:raise AssertionError('Nieznana operacja stanu gracza')
if __name__=='__main__':
 try:main()
 except (AssertionError,ValueError,TypeError,IndexError) as error:print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
