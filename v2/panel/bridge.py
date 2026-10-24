"""Allowlisted HTTP-to-NIK adapter. NIK remains the domain/validation engine."""
import csv, os, re, subprocess, unicodedata
from pathlib import Path

class InputError(ValueError): pass

ACTIONS = {
 'heal':('Ulecz gracza','zdrowie'), 'home':('Powrót do domu','dom'),
 'back':('Poprzednie miejsce','powrot'), 'repair':('Napraw przedmiot','napraw'),
 'fireworks':('Fajerwerki','fajerwerki'), 'where':('Pozycja gracza','gdzie'),
 'inventory':('Plecak','plecak'), 'ender':('Skrzynia Endera','ender'),
 'freeze':('Zamroź','zamroz'), 'thaw':('Odmroź','odmroz'),
 'give':('Daj przedmiot','daj'), 'summon':('Przywołaj stworzenie','przywolaj'),
 'enchant':('Daj zaklęty przedmiot','encik'), 'enchant_hand':('Zaklnij trzymany przedmiot','zaklnij'),
 'effect':('Dodaj efekt','efekt'), 'clear_effects':('Usuń efekty','wyczysc'),
 'teleport':('Teleportuj do punktu','tp'), 'guide':('Prowadź do punktu','prowadz'),
 'point':('Zapisz punkt','punkt'), 'message':('Wiadomość od Taty','tata'),
 'title':('Duży napis','napis'), 'countdown':('Odliczanie','odliczanie'),
 'random':('Wylosuj zadanie','losuj'), 'quest':('Nowe zadanie','zadanie'),
 'quest_show':('Zobacz zadanie','zadanie'), 'quest_done':('Zadanie gotowe','zadanie'),
 'reward':('Nagroda od Taty','nagroda'), 'weather':('Zmień pogodę','pogoda'),
 'day':('Ustaw dzień','dzien'), 'night':('Ustaw noc','noc'),
 'save':('Zapisz świat','zapisz'), 'status':('Sprawdź serwer','status'),
 'players':('Stan graczy','stan'), 'backup':('Kopia świata','kopia'), 'backups':('Lista kopii świata','kopia'),
 'kit':('Daj ulubiony zestaw','zestaw'), 'equip':('Gotowe wyposażenie','wyposaz'),
 'recipe':('Przepis wytwarzania','przepis'), 'mode':('Tryb gry',''),
}
GLOBAL={'players','backup','backups','weather','day','night','save','status','recipe'}
CONFIRM={'clear_effects','equip','backup'}
ANSI=re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')

def text(data,key,default=None,limit=100):
 value=data.get(key,default)
 if not isinstance(value,str) or not value.strip() or len(value)>limit or any(unicodedata.category(c) in {'Cc','Cs'} for c in value):
  raise InputError('Uzupełnij poprawnie pole: '+key)
 return value.strip()

def integer(data,key,default,minimum,maximum):
 value=data.get(key,default)
 if type(value) is not int or not minimum<=value<=maximum:raise InputError(f'Ilość lub poziom: wymagany zakres {minimum}–{maximum}.')
 return str(value)

def build(data):
 if not isinstance(data,dict):raise InputError('Nieprawidłowe żądanie.')
 action=data.get('action')
 if not isinstance(action,str) or action not in ACTIONS:raise InputError('Nieznana czynność.')
 for flag in ('preview','confirm'):
  if flag in data and type(data[flag]) is not bool:raise InputError('Nieprawidłowa opcja.')
 preview=data.get('preview',False);confirmed=data.get('confirm',False)
 if action in CONFIRM and not (preview or confirmed):raise InputError('Ta czynność wymaga potwierdzenia.')
 args=[ACTIONS[action][1]]
 if action not in GLOBAL:args.append(text(data,'player'))
 if action=='players':args.extend(['lista','json'])
 elif action=='backup':args.append('utworz')
 elif action=='backups':args.append('dane')
 elif action in {'kit','equip'}:args.append(text(data,'kit'))
 elif action in {'give','summon'}:
  args.extend([text(data,'item' if action=='give' else 'creature'),integer(data,'count',1,1,2304 if action=='give' else 64)])
 elif action in {'enchant','enchant_hand'}:
  if action=='enchant':args.append(text(data,'item'))
  ench=data.get('enchantments')
  if not isinstance(ench,list) or not 1<=len(ench)<=43 or any(not isinstance(e,str) or not re.fullmatch(r'[a-z_]+(?::[0-9]{1,3})?',e) for e in ench):raise InputError('Wybierz co najmniej jedno zaklęcie.')
  args.extend(ench)
 elif action=='effect':args.extend([text(data,'effect'),text(data,'duration','5m',12),integer(data,'level',1,1,256)])
 elif action in {'teleport','guide'}:
  args.append(text(data,'place'))
  if action=='guide':args.append('60s')
 elif action=='point':args.append(text(data,'name',limit=40))
 elif action in {'message','title','quest'}:args.append(text(data,'text',limit=512))
 elif action=='countdown':args.extend([integer(data,'seconds',10,1,60),text(data,'text','Start!',512)])
 elif action=='quest_show':args.append('pokaz')
 elif action=='quest_done':args.append('gotowe')
 elif action=='reward':args.append(text(data,'reward'))
 elif action=='weather':
  kind=text(data,'weather')
  if kind not in {'slonce','deszcz','burza'}:raise InputError('Nieprawidłowa pogoda.')
  args.extend([kind,text(data,'duration','10m',12)])
 elif action=='recipe':args.append(text(data,'item'))
 elif action=='mode':
  mode=text(data,'mode')
  if mode not in {'kreatywny','przetrwanie','obserwator','przygodowy'}:raise InputError('Nieprawidłowy tryb gry.')
  args[0]=mode
 return args,preview,confirmed

def argv(root,config,data):
 args,preview,confirmed=build(data)
 return ['bash',str(root/'nik.sh'),'--konfiguracja',str(config),*(['--podglad'] if preview else []),*(['--potwierdz'] if confirmed else []),'--',*args]

def environment(root):
 # Do not import a remote request, extension path or shell program from the client.
 env=dict(os.environ)
 for key in ('BASH_ENV','ENV','NIK_CONFIG','NIK_STATE','SHELLOPTS','BASHOPTS'):env.pop(key,None)
 env.update(NIK_COLOR='never',NO_COLOR='1',NIK_WIDTH='52',NIK_STATE=str(root/'state'))
 return env

def clean(output):
 return ''.join(c for c in ANSI.sub('',output) if c in '\n\t' or unicodedata.category(c) not in {'Cc','Cs'})

def rows(path):
 with path.open() as f:return [r for r in csv.reader(f,delimiter='\t') if r and r[0] and not r[0].startswith('#')]

def metadata(root,config):
 # Use the real central config validator before presenting its logical names.
 check=subprocess.run(['bash',str(root/'nik.sh'),'--konfiguracja',str(config),'--podglad','status'],env=environment(root),capture_output=True,text=True,timeout=20)
 if check.returncode:raise InputError('NIK zgłosił błąd konfiguracji. Sprawdź nik status na serwerze.')
 players=[{'id':r[0],'alias':r[1],'name':r[0].replace('_',' ').capitalize()} for r in rows(config/'players.tsv')]
 items=[{'id':r[0],'name':r[0].replace('_',' '),'english':r[1]} for r in rows(root/'data/items.tsv')]
 creatures=[{'id':r[0],'name':r[0].replace('_',' '),'english':r[1]} for r in rows(root/'data/creatures.tsv')]
 maxima={r[0]:r[1:] for r in rows(root/'data/enchantments.tsv')}
 enchantments=[{'id':r[0],'name':r[0].replace('_',' '),'max':int(maxima[r[1]][0]),'description':maxima[r[1]][1]} for r in rows(root/'data/enchantment-names.tsv')]
 effects=[{'id':r[0],'name':r[0].replace('_',' '),'description':r[2] if len(r)>2 else ''} for r in rows(root/'data/effects.tsv')]
 rewards=sorted({p.stem for directory in [root/'data/rewards',config/'rewards'] for p in directory.glob('*.tsv') if p.is_file() and not p.is_symlink()})
 kits=sorted(p.stem for p in (config/'favorites').glob('*.tsv') if p.is_file() and not p.is_symlink())
 equipment=sorted(p.stem for p in (config/'sets').glob('*.tsv') if p.is_file() and not p.is_symlink())
 return {'kits':kits,'equipment':equipment,'players':players,'items':items,'creatures':creatures,'enchantments':enchantments,'effects':effects,'places':[r[0] for r in rows(config/'places.tsv')],'rewards':rewards,'version':'NIK Mobile 1.3','actions':list(ACTIONS)}
