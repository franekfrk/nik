#!/usr/bin/env python3
"""Versioned JSON/JSONL envelope around the original Bash command dispatcher."""
import json,os,queue,subprocess,sys,tempfile,threading
from pathlib import Path
LIMIT=1048576

def emit(event):print(json.dumps(event,ensure_ascii=False),flush=True)
def main():
 root=Path(sys.argv[1]);args=[];stream=False;options=True
 for arg in sys.argv[2:]:
  if options and arg in {'--json','--jsonl'}:stream=stream or arg=='--jsonl';continue
  if arg=='--':options=False
  args.append(arg)
 with tempfile.TemporaryDirectory(prefix='nik-result-') as directory:
  os.chmod(directory,0o700);result_path=Path(directory)/'result.json'
  env={**os.environ,'NIK_RESULT_PATH':str(result_path),'NIK_PROGRESS':'1','NIK_COLOR':'never','NO_COLOR':'1'}
  process=subprocess.Popen(['bash',str(root/'nik.sh'),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  events=queue.Queue(maxsize=32)
  def read(pipe,kind):
   try:
    while True:
     chunk=pipe.readline(65536)
     if not chunk:break
     events.put((kind,chunk))
   finally:pipe.close();events.put((kind,None))
  for pipe,kind in [(process.stdout,'stdout'),(process.stderr,'stderr')]:threading.Thread(target=read,args=(pipe,kind),daemon=True).start()
  output=[];size=0;closed=0
  if stream:emit({'type':'progress','message':'NIK przygotowuje polecenie.'})
  while closed<2:
   kind,chunk=events.get()
   if chunk is None:closed+=1;continue
   line=chunk.decode(errors='replace')
   if kind=='stderr' and line.startswith('NIK:POSTEP\t'):
    if stream:emit({'type':'progress','message':line.split('\t',1)[1].strip()[:500]})
   elif size<LIMIT:
    part=line[:LIMIT-size];output.append(part);size+=len(part)
    if stream:emit({'type':'output','text':part})
  code=process.wait();code=128-code if code<0 else code;text=''.join(output);result=None
  if result_path.exists():
   if result_path.is_symlink() or result_path.stat().st_size>LIMIT:raise ValueError('Nieprawidłowy wynik NIK.')
   result=json.loads(result_path.read_text())
  elif code==0:
   try:result=json.loads(text)
   except ValueError:pass
  envelope={'schema':1,'ok':code==0,'code':code,'output':text,'result':result}
  emit({'type':'result','data':envelope} if stream else envelope)
  return code
if __name__=='__main__':
 try:sys.exit(main())
 except (OSError,ValueError) as error:
  emit({'schema':1,'ok':False,'code':1,'output':'NIK: nie udało się przygotować wyniku JSON.','result':None});sys.exit(1)
