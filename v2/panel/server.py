#!/usr/bin/env python3
"""Private NIK panel: stdlib HTTP, PBKDF2 auth, CSRF and bounded CLI jobs."""
import argparse,collections,concurrent.futures,hashlib,hmac,http.cookies,ipaddress,json,os,re,secrets,signal,subprocess,tempfile,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import bridge
from history import History,FIELDS

STATIC=Path(__file__).resolve().parent/'static'
COOKIE='nik_session'

class HTTPError(Exception):
 def __init__(self,status,message):self.status=status;self.message=message

def password_record(password):
 salt=secrets.token_hex(24);rounds=600000
 return {'salt':salt,'rounds':rounds,'hash':hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),rounds).hex()}

def password_matches(password,record):
 return hmac.compare_digest(hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(record['salt']),record['rounds']).hex(),record['hash'])

class App:
 def __init__(self,config):
  self.config=config;self.root=Path(config['nik_root']).resolve();self.nik_config=Path(config.get('nik_config',self.root/'config')).resolve()
  self.origins=config['origins'];self.hosts={urlsplit(u).netloc for u in self.origins}
  if not self.origins or any(urlsplit(u).scheme not in {'http','https'} or urlsplit(u).path for u in self.origins):raise ValueError('Nieprawidłowy adres panelu.')
  if not 100000<=config['password']['rounds']<=2000000:raise ValueError('Nieprawidłowy hash hasła.')
  self.history=History(self.root)
  self.lock=threading.RLock();self.sessions={};self.failures={};self.jobs={};self.keys={};self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1);self.slots=threading.BoundedSemaphore(6)
 def login(self,password,ip):
  now=time.monotonic()
  with self.lock:
   failures=self.failures.setdefault(ip,collections.deque())
   while failures and failures[0]<now-900:failures.popleft()
   if len(failures)>=5:raise HTTPError(429,'Za dużo prób. Spróbuj ponownie za 15 minut.')
   # Reserve the attempt before PBKDF2, including concurrent requests.
   failures.append(now)
  if not password_matches(password,self.config['password']):
   raise HTTPError(401,'Nieprawidłowe hasło.')
  token=secrets.token_urlsafe(32);key=hashlib.sha256(token.encode()).hexdigest()
  with self.lock:
   self.failures.pop(ip,None)
   self.sessions={k:v for k,v in self.sessions.items() if v['expires']>now}
   if len(self.sessions)>=32:self.sessions.pop(next(iter(self.sessions)))
   self.sessions[key]={'csrf':secrets.token_urlsafe(32),'expires':now+86400}
  return token,key,self.sessions[key]
 def session(self,token):
  key=hashlib.sha256(token.encode()).hexdigest()
  with self.lock:
   s=self.sessions.get(key)
   if not s or s['expires']<time.monotonic():self.sessions.pop(key,None);raise HTTPError(401,'Zaloguj się do panelu.')
   return key,s
 def job(self,owner,data,key):
  args,_,_=bridge.build(data)
  if not isinstance(key,str) or not re.fullmatch('[a-zA-Z0-9_-]{16,80}',key):raise bridge.InputError('Nieprawidłowy identyfikator operacji.')
  digest=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
  with self.lock:
   for old in list(self.jobs):
    if self.jobs[old]['created']<time.monotonic()-3600 and self.jobs[old]['state'] not in {'queued','running'}:
     j=self.jobs.pop(old);self.keys.pop((j['owner'],j['key']),None)
   existing=self.keys.get((owner,key))
   if existing:
    if self.jobs[existing]['digest']!=digest:raise HTTPError(409,'Identyfikator został już użyty do innej czynności.')
    return existing
   if len(self.jobs)>=200 or not self.slots.acquire(blocking=False):raise HTTPError(429,'Kolejka jest pełna. Poczekaj na zakończenie czynności.')
   id=secrets.token_urlsafe(18)
   self.jobs[id]={'id':id,'owner':owner,'key':key,'digest':digest,'created':time.monotonic(),'state':'queued','output':'','code':None,'label':bridge.ACTIONS[data['action']][0],'preview':data.get('preview',False),'action':data['action'],'player':data.get('player','') if data['action'] not in bridge.GLOBAL else '', 'timestamp':time.time(),'command':args[0],'result':None,'progress':[],'request':bridge.replay_request(data)}
   try:
    self.history.put(self.jobs[id])
    self.keys[owner,key]=id
    self.jobs[id]['future']=self.pool.submit(self.run_job,id,dict(data))
   except Exception:
    try:
     self.jobs[id].update(state='error',code=None,output='Komenda nie została uruchomiona: nie udało się przygotować kolejki.')
     self.history.put(self.jobs[id])
    except Exception:pass
    self.jobs.pop(id,None);self.keys.pop((owner,key),None);self.slots.release()
    raise HTTPError(503,'Nie udało się zapisać operacji. Komenda nie została uruchomiona.')
   return id
 def run_job(self,id,data):
  job=self.jobs[id];process=None
  try:
   with self.lock:
    if job['state']=='cancelled':return
    job['state']='running'
    self.history.put(job)
   with tempfile.TemporaryFile() as out:
    with self.lock:
     # A cancellation between the running-state write and Popen must prevent launch.
     if job['state']=='cancelled':
      job['output']='Anulowano zadanie przed uruchomieniem NIK. Komenda nie została uruchomiona.'
      return
     process=subprocess.Popen(bridge.argv(self.root,self.nik_config,data),env=bridge.environment(self.root),stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
     job['process']=process
    decoder=JobEvents(job,self.lock);offset=0;timed_out=False;deadline=time.monotonic()+(2100 if data['action']=='backup' else 180)
    while True:
     try:code=process.wait(timeout=2100 if data['action']=='backup' else min(.3,max(.01,deadline-time.monotonic())))
     except subprocess.TimeoutExpired:code=None
     chunk=os.pread(out.fileno(),1048576,offset)
     if chunk:offset+=len(chunk);decoder.feed(chunk)
     if code is not None:break
     if time.monotonic()>=deadline:
      self.stop(process,180 if data['action']=='backup' else 2);code=124;timed_out=True;break
    while True:
     chunk=os.pread(out.fileno(),1048576,offset)
     if not chunk:break
     offset+=len(chunk);decoder.feed(chunk)
    output,result=decoder.finish()
    if result is not None:
     if type(result.get('code')) is not int or type(result.get('ok')) is not bool or result['ok']!=(code==0) or result['code']!=code:raise ValueError('Niespójny wynik NIK.')
     job['result']=result.get('result')
    with self.lock:
     job.pop('process',None);job['code']=code
     if job['state']!='cancelled':job['output']=output
     if job['state']!='cancelled':job['state']='success' if code==0 else 'error'
     if timed_out:job['output']+='\nPrzekroczono czas panelu. Część operacji mogła zostać wykonana; nie ponawiaj automatycznie.'
     self.history.put(job)
  except Exception as error:
   if process is not None:self.stop(process)
   with self.lock:job.update(state='error',code=1,output=job['output']+'\nPanel napotkał błąd obsługi operacji. Sprawdź wynik i stan gry przed ponowieniem; wcześniejsze kroki mogły zostać wykonane.');job.pop('process',None)
   print('Błąd uruchomienia zadania: '+type(error).__name__,flush=True)
  finally:
   try:
    with self.lock:self.history.put(job)
   except Exception as error:
    with self.lock:
     job.update(state='error',code=None,output=job['output']+'\nNie udało się zapisać wyniku na dysku. Ten wynik może zniknąć po restarcie panelu. Sprawdź miejsce na dysku i uprawnienia historii.')
    print('Nie zapisano wyniku historii: '+type(error).__name__,flush=True)
   finally:self.slots.release()
 def stop(self,process,grace=2):
  if process.poll() is None:
   try:os.killpg(process.pid,signal.SIGTERM);process.wait(timeout=grace)
   except subprocess.TimeoutExpired:
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait()
   except ProcessLookupError:pass
 def view(self,id,owner):
  with self.lock:
   j=self.jobs.get(id)
   if not j or j['owner']!=owner:raise HTTPError(404,'Nie znaleziono operacji w tej sesji.')
   return {k:j.get(k,[] if k=='progress' else None) for k in FIELDS}
 def history_view(self,id):
  with self.lock:
   if id in self.jobs:return {key:self.jobs[id].get(key,[] if key=='progress' else None) for key in FIELDS}
  return self.history.get(id)
 def history_list(self):
  records=self.history.list()
  with self.lock:
   for record in records:
    if record['id'] in self.jobs:record.update({key:self.jobs[record['id']].get(key,[] if key=='progress' else None) for key in FIELDS if key not in {'output','result','request'}})
  return records
 def cancel(self,id,owner,queued_only=False):
  with self.lock:
   j=self.jobs.get(id)
   if not j or (j['owner']!=owner and j['state']!='queued'):raise HTTPError(404,'Nie znaleziono operacji do zatrzymania.')
   if queued_only and j['state']!='queued':raise HTTPError(409,'Zadanie nie oczekuje już w kolejce. Sprawdź jego aktualny stan; niczego nie zatrzymano.')
   if j['state'] not in {'running','queued'}:return
   queued=j['state']=='queued'
   if j['action']=='backup' and not queued:raise HTTPError(409,'Trwa kopia świata. Poczekaj na bezpieczne zakończenie i uruchomienie serwera.')
   j['state']='cancelled';j['output']='Anulowano oczekujące zadanie. Komenda nie została uruchomiona.' if queued else 'Zatrzymano proces NIK. Wcześniejsze kroki mogły zostać wykonane.';p=j.get('process')
   cancelled_future=queued and j.get('future') is not None and j['future'].cancel()
   if cancelled_future:self.slots.release()
   self.history.put(j)
  if p:self.stop(p)



class JobEvents:
 def __init__(self,job,lock):self.job=job;self.lock=lock;self.pending=b'';self.plain=[];self.result=None;self.size=0;self.live=''
 def feed(self,chunk):
  self.size+=len(chunk)
  if self.size>8388608:raise ValueError('Zbyt duży strumień NIK.')
  self.pending+=chunk
  while b'\n' in self.pending:
   line,self.pending=self.pending.split(b'\n',1);self.line(line)
 def line(self,raw):
  text=raw.decode(errors='replace')
  try:event=json.loads(text)
  except ValueError:event=None
  if isinstance(event,dict) and event.get('type')=='progress' and isinstance(event.get('message'),str):
   with self.lock:self.job['progress']=(self.job.get('progress',[])+[{'message':bridge.clean(event['message'])[:500],'at':time.time()}])[-40:]
  elif isinstance(event,dict) and event.get('type')=='output' and isinstance(event.get('text'),str):
   self.live=(self.live+bridge.clean(event['text']))[:131072]
   with self.lock:
    if self.job['state']!='cancelled':self.job['output']=self.live
  elif isinstance(event,dict) and event.get('type')=='result' and isinstance(event.get('data'),dict) and event['data'].get('schema')==1:
   if self.result is not None:raise ValueError('Powtórzony wynik NIK.')
   self.result=event['data']
  else:self.plain.append(text+'\n')
 def finish(self):
  if self.pending:self.line(self.pending);self.pending=b''
  output=self.result.get('output','') if self.result is not None else ''.join(self.plain) or self.live
  if not isinstance(output,str):raise ValueError('Nieprawidłowy tekst wyniku.')
  return bridge.clean(output)[:131072],self.result

class Server(ThreadingHTTPServer):
 daemon_threads=True;allow_reuse_address=True
 def __init__(self,address,app):self.app=app;self.requests=threading.BoundedSemaphore(24);super().__init__(address,Handler)
 def process_request(self,request,address):
  if not self.requests.acquire(False):request.close();return
  try:super().process_request(request,address)
  except BaseException:self.requests.release();raise
 def process_request_thread(self,request,address):
  try:super().process_request_thread(request,address)
  finally:self.requests.release()

class Handler(BaseHTTPRequestHandler):
 server_version='NIK';sys_version='';protocol_version='HTTP/1.0'
 def setup(self):super().setup();self.connection.settimeout(10)
 def log_message(self,*args):pass
 def response(self,status,payload,content_type='application/json; charset=utf-8',cookie=None):
  body=json.dumps(payload,ensure_ascii=False).encode() if content_type.startswith('application/json') and not isinstance(payload,bytes) else payload
  self.send_response(status);self.send_header('Content-Type',content_type);self.send_header('Content-Length',str(len(body)))
  self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Referrer-Policy','no-referrer')
  self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; worker-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
  if self.secure:self.send_header('Strict-Transport-Security','max-age=31536000')
  if cookie:self.send_header('Set-Cookie',cookie)
  self.end_headers();self.wfile.write(body)
 def token(self):
  c=http.cookies.SimpleCookie()
  try:c.load(self.headers.get('Cookie',''))
  except http.cookies.CookieError:return ''
  return c[COOKIE].value if COOKIE in c else ''
 def authenticated(self):return self.server.app.session(self.token())
 def body(self):
  if self.headers.get_content_type()!='application/json':raise HTTPError(415,'Wymagany format JSON.')
  try:length=int(self.headers.get('Content-Length','0'))
  except ValueError:raise HTTPError(400,'Nieprawidłowe żądanie.')
  if not 1<=length<=16384:raise HTTPError(413,'Zbyt duże lub puste żądanie.')
  try:value=json.loads(self.rfile.read(length))
  except (ValueError,UnicodeError):raise HTTPError(400,'Nieprawidłowy JSON.')
  if not isinstance(value,dict):raise HTTPError(400,'Nieprawidłowe żądanie.')
  return value
 def dispatch(self,post):
  self.secure=False
  app=self.server.app;host=self.headers.get('Host','')
  if host not in app.hosts:raise HTTPError(403,'Niedozwolony adres panelu.')
  expected=[o for o in app.origins if urlsplit(o).netloc==host]
  self.secure=any(o.startswith('https:') for o in expected)
  path=urlsplit(self.path).path
  if post:
   if self.headers.get('Origin') not in expected:raise HTTPError(403,'Niedozwolone źródło żądania.')
   data=self.body()
   if path=='/api/login':
    password=data.get('password')
    if not isinstance(password,str) or not 1<=len(password)<=512 or any(0xD800<=ord(c)<=0xDFFF for c in password):raise HTTPError(401,'Nieprawidłowe hasło.')
    token,owner,s=app.login(password,self.client_address[0]);cookie=f'{COOKIE}={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400'+('; Secure' if self.secure else '')
    self.response(200,{'csrf':s['csrf']},cookie=cookie);return
   owner,s=self.authenticated()
   if not hmac.compare_digest(self.headers.get('X-CSRF-Token','').encode(),s['csrf'].encode()):raise HTTPError(403,'Odśwież panel i spróbuj ponownie.')
   if path=='/api/logout':
    with app.lock:app.sessions.pop(owner,None)
    self.response(200,{'ok':True},cookie=f'{COOKIE}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'+('; Secure' if self.secure else ''));return
   if path=='/api/favorites':
    name=bridge.text(data,'name',limit=40);request=data.get('request')
    if not isinstance(request,dict):raise bridge.InputError('Brak ustawień ulubionej akcji.')
    allowed={'action','player','item','creature','count','enchantments','effect','duration','level','place','name','text','seconds','reward','weather','mode','kit','scenario'}
    request={k:v for k,v in request.items() if k in allowed};bridge.build({**request,'preview':True})
    check=subprocess.run(bridge.argv(app.root,app.nik_config,{**request,'preview':True},structured=False),env=bridge.environment(app.root),capture_output=True,text=True,timeout=20)
    if check.returncode:raise bridge.InputError('NIK nie zaakceptował skrótu: '+bridge.clean(check.stdout+check.stderr)[-2000:])
    id=data.get('id') or secrets.token_urlsafe(18)
    if not isinstance(id,str):raise bridge.InputError('Nieprawidłowy identyfikator skrótu.')
    try:
     if data.get('id'):app.history.edit_favorite(id,name,request)
     else:app.history.save_favorite(id,name,request)
    except ValueError as error:raise bridge.InputError(str(error))
    self.response(201,{'id':id});return
   if path=='/api/favorites/order':
    try:app.history.reorder_favorites(data.get('ids'))
    except ValueError as error:raise bridge.InputError(str(error))
    self.response(200,{'ok':True});return
   if path in {'/api/catalog/pin','/api/catalog/recent'}:
    kind=data.get('kind');id=data.get('id')
    if not isinstance(kind,str) or kind not in {'items','creatures'} or not isinstance(id,str) or id not in {r[1] for r in bridge.rows(app.root/'data'/('items.tsv' if kind=='items' else 'creatures.tsv'))}:raise bridge.InputError('Nieznany wpis katalogu NIK.')
    try:
     if path.endswith('/pin'):
      if type(data.get('enabled')) is not bool:raise bridge.InputError('Nieprawidłowa opcja ulubionego przedmiotu.')
      app.history.catalog_pin(kind,id,data['enabled'],time.time())
     else:app.history.catalog_remember(kind,id,time.time())
    except ValueError as error:raise bridge.InputError(str(error))
    self.response(200,{'ok':True});return
   if re.fullmatch('/api/favorites/[A-Za-z0-9_-]+/delete',path):
    app.history.delete_favorite(path.split('/')[3]);self.response(200,{'ok':True});return
   if path=='/api/jobs':
    id=app.job(owner,data.get('request'),data.get('key'));self.response(202,{'id':id});return
   if re.fullmatch('/api/jobs/[A-Za-z0-9_-]+/cancel',path):
    if type(data.get('queued_only',False)) is not bool:raise bridge.InputError('Nieprawidłowy tryb anulowania.')
    app.cancel(path.split('/')[3],owner,data.get('queued_only',False));self.response(200,{'ok':True});return
   raise HTTPError(404,'Nie znaleziono czynności.')
  if path=='/api/session':
   _,s=self.authenticated();self.response(200,{'csrf':s['csrf']});return
  if path=='/api/metadata':
   self.authenticated();self.response(200,bridge.metadata(app.root,app.nik_config));return
  if path=='/api/catalog':
   self.authenticated();self.response(200,app.history.catalog());return
  if path=='/api/favorites':
   self.authenticated();self.response(200,{'entries':app.history.favorites()});return
  if path=='/api/history':
   self.authenticated();self.response(200,{'entries':app.history_list(),'limit':100});return
  if re.fullmatch('/api/history/[A-Za-z0-9_-]+',path):
   self.authenticated();record=app.history_view(path.rsplit('/',1)[-1])
   if record is None:raise HTTPError(404,'Nie znaleziono wyniku w historii.')
   self.response(200,record);return
  if path.startswith('/api/jobs/key/'):
   owner,_=self.authenticated();key=path.rsplit('/',1)[-1]
   with app.lock:id=app.keys.get((owner,key))
   if not id:raise HTTPError(404,'Nie odnaleziono potwierdzenia operacji. Nie ponawiaj jej automatycznie.')
   self.response(200,app.view(id,owner));return
  if re.fullmatch('/api/jobs/[A-Za-z0-9_-]+',path):
   owner,_=self.authenticated();self.response(200,app.view(path.rsplit('/',1)[-1],owner));return
  files={'/':'index.html','/index.html':'index.html','/app.css':'app.css','/app.js':'app.js','/enhancements.js':'enhancements.js','/enhancements.css':'enhancements.css','/sw.js':'sw.js','/manifest.webmanifest':'manifest.webmanifest','/terrain.svg':'terrain.svg','/icon.svg':'icon.svg','/icons.css':'icons.css','/icons.json':'icons.json','/icons-items.png':'icons-items.png','/icons-creatures.png':'icons-creatures.png','/icon-192.png':'icon-192.png','/icon-512.png':'icon-512.png','/apple-touch-icon.png':'apple-touch-icon.png'}
  if path not in files:raise HTTPError(404,'Nie znaleziono strony.')
  file=STATIC/files[path]
  kinds={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.webmanifest':'application/manifest+json','.svg':'image/svg+xml','.png':'image/png','.json':'application/json; charset=utf-8'}
  self.response(200,file.read_bytes(),kinds[file.suffix])
 def handle_method(self,post):
  try:self.dispatch(post)
  except HTTPError as e:self.response(e.status,{'error':e.message})
  except bridge.InputError as e:self.response(400,{'error':str(e)})
  except (BrokenPipeError,ConnectionResetError,TimeoutError):pass
  except Exception as error:
   print('Błąd HTTP: '+type(error).__name__,flush=True)
   try:self.response(500,{'error':'Błąd panelu. Sprawdź usługę na serwerze.'})
   except (BrokenPipeError,ConnectionResetError):pass
 def do_GET(self):self.handle_method(False)
 def do_POST(self):self.handle_method(True)

def listener_addresses(config):
 host=config.get('bind','127.0.0.1');port=config.get('port',6767)
 if not ipaddress.ip_address(host).is_loopback:raise ValueError('Główny adres panelu musi być loopback.')
 if isinstance(port,bool) or not isinstance(port,int) or not 1024<=port<=65535:raise ValueError('Nieprawidłowy port.')
 addresses=[(host,port)]
 if config.get('lan_bind'):
  lan=ipaddress.ip_address(config['lan_bind'])
  networks=('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')
  if lan.version!=4 or not any(lan in ipaddress.ip_network(n) for n in networks):raise ValueError('LAN wymaga konkretnego prywatnego adresu IPv4.')
  if f'http://{lan}:{port}' not in config['origins']:raise ValueError('Brakuje adresu HTTP LAN w konfiguracji.')
  addresses.append((str(lan),port))
 return addresses

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--config',type=Path,required=True);args=parser.parse_args()
 if args.config.is_symlink() or args.config.stat().st_mode&0o077:raise SystemExit('Konfiguracja panelu musi mieć uprawnienia 600 i nie być dowiązaniem.')
 config=json.loads(args.config.read_text());addresses=listener_addresses(config);app=App(config);servers=[]
 try:
  for address in addresses:servers.append(Server(address,app))
  for extra in servers[1:]:threading.Thread(target=extra.serve_forever,daemon=True).start()
  print(f'NIK Mobile działa na porcie {addresses[0][1]}.',flush=True)
  servers[0].serve_forever()
 finally:
  for extra in servers[1:]:extra.shutdown()
  for instance in servers:instance.server_close()
  app.pool.shutdown(wait=False,cancel_futures=True)
if __name__=='__main__':main()
