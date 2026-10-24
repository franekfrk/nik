#!/usr/bin/env python3
"""Named NIK plans: argv only, validate every step before the first mutation."""
import argparse,fcntl,json,os,re,shlex,subprocess,sys,tempfile
from pathlib import Path
from result_data import write_result
ALLOWED=set('daj encik efekt usun zdrowie tp dom gdzie napis tata wiadomosc fajerwerki pogoda dzien noc napraw zaklnij zamroz odmroz ratunek plecak ender kreatywny przetrwanie obserwator przygodowy zestaw'.split())

def name(value):
 assert isinstance(value,str) and re.fullmatch('[a-z][a-z0-9_]{0,39}',value),'Nazwa scenariusza: 1–40 znaków a-z, 0-9, _'
 return value

def steps(value):
 assert isinstance(value,list) and 1<=len(value)<=12,'Scenariusz wymaga 1–12 kroków'
 for line in value:
  assert isinstance(line,str) and 1<=len(line)<=2048 and not any(ord(c)<32 for c in line),'Błędny krok scenariusza'
  args=shlex.split(line)
  assert args and args[0] in ALLOWED,'Niedozwolona komenda scenariusza'
  if args[0]=='zestaw':assert len(args)==3 and args[1] not in {'zapisz','lista','pokaz'},'W scenariuszu zestaw służy do dawania wyposażenia'
 return value

def load(path):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=32768,'Brak lub błędny scenariusz'
 value=json.loads(path.read_text());assert value.get('schema')==1 and value.get('name')==path.stem,'Błędny zapis scenariusza'
 name(value['name']);steps(value['steps']);return value

def command(args,player,line,dry=False,jsonl=False):
 values=[v.replace('{gracz}',player) for v in shlex.split(line)]
 return ['bash',str(args.root/'nik.sh'),*(['--jsonl'] if jsonl else []),'--konfiguracja',str(args.config),*(['--podglad'] if dry else []),*(['--potwierdz'] if args.confirm else []),'--',*values]

def validate(args,player,lines):
 steps(lines)
 for i,line in enumerate(lines,1):
  check=subprocess.run(command(args,player,line,True),env=environment(),capture_output=True,text=True,timeout=60)
  assert check.returncode==0,f'Krok {i} nie przeszedł walidacji NIK:\n'+(check.stdout+check.stderr)[-3000:]

def environment():
 env=dict(os.environ);env.pop('NIK_RESULT_PATH',None);return env

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--config',type=Path,required=True);parser.add_argument('--dry-run',action='store_true');parser.add_argument('--confirm',action='store_true');parser.add_argument('action');parser.add_argument('values',nargs='*');args=parser.parse_args()
 folder=args.config/'scenarios';assert not folder.is_symlink(),'Katalog scenariuszy jest dowiązaniem'
 action=args.action;values=args.values
 if action in {'lista','dane'}:
  records=[load(path) for path in sorted(folder.glob('*.json')) if not path.is_symlink()]
  if action=='dane':print(json.dumps({'scenarios':records},ensure_ascii=False))
  else:
   print('SCENARIUSZE')
   for record in records:print('  '+record['name']+' · '+str(len(record['steps']))+' kroków')
  return
 assert values,'Brak nazwy scenariusza';ident=name(values[0]);path=folder/(ident+'.json')
 assert not path.is_symlink(),'Scenariusz jest dowiązaniem'
 if action=='zapisz':
  lines=steps(values[1:]);player=next(line.split('\t')[0] for line in (args.config/'players.tsv').read_text().splitlines() if line and not line.startswith('#'))
  validate(args,player,lines)
  if args.dry_run:print('[podgląd] zapis scenariusza '+ident);return
  folder.mkdir(mode=0o700,exist_ok=True);os.chmod(folder,0o700)
  fd=os.open(folder/'.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
  try:
   fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
   assert path.exists() or len(list(folder.glob('*.json')))<24,'Możesz zapisać najwyżej 24 scenariusze'
   record={'schema':1,'name':ident,'steps':lines};pending_fd,pending=tempfile.mkstemp(prefix='.scenario-',dir=folder)
   try:
    with os.fdopen(pending_fd,'w') as out:json.dump(record,out,ensure_ascii=False);out.flush();os.fsync(out.fileno())
    os.replace(pending,path)
   finally:Path(pending).unlink(missing_ok=True)
  finally:os.close(fd)
  write_result({'type':'scenario_saved','name':ident,'steps':lines});print('Zapisano scenariusz: '+ident);return
 record=load(path)
 if action=='pokaz':
  print(ident)
  for i,line in enumerate(record['steps'],1):print(f'  {i}. {line}')
  return
 if action=='usun':
  assert args.confirm or args.dry_run,'Usunięcie wymaga --potwierdz'
  if args.dry_run:print('[podgląd] usunięcie scenariusza '+ident)
  else:path.unlink();print('Usunięto scenariusz: '+ident)
  return
 assert action=='wykonaj' and len(values)==2,'Nieprawidłowe użycie scenariusza';player=name(values[1]);validate(args,player,record['steps'])
 results=[]
 for i,line in enumerate(record['steps'],1):
  message=f'Krok {i}/{len(record["steps"])}: {shlex.split(line)[0]}'
  if os.environ.get('NIK_PROGRESS')=='1':print('NIK:POSTEP\t'+message,file=sys.stderr,flush=True)
  else:print(message,flush=True)
  process=subprocess.Popen(command(args,player,line,args.dry_run,True),env=environment(),stdout=subprocess.PIPE,text=True)
  final=None
  for raw in process.stdout:
   event=json.loads(raw)
   if event.get('type')=='progress' and os.environ.get('NIK_PROGRESS')=='1':print('NIK:POSTEP\t'+message+' · '+event['message'],file=sys.stderr,flush=True)
   elif event.get('type')=='output':pass
   elif event.get('type')=='result':final=event['data']
  code=process.wait();assert final is not None,'Niepełny wynik kroku scenariusza'
  results.append({'step':i,'command':line,**final});print(final['output'],end='',flush=True)
  if code:
   write_result({'type':'scenario','name':ident,'steps':results,'completed':i-1,'total':len(record['steps'])});return code
 write_result({'type':'scenario','name':ident,'steps':results,'completed':len(results),'total':len(results)})
 return 0
if __name__=='__main__':
 try:sys.exit(main() or 0)
 except (AssertionError,OSError,ValueError,StopIteration,subprocess.SubprocessError) as error:print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
