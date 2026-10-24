#!/usr/bin/env python3
"""Private NIK panel: stdlib HTTP, PBKDF2 auth, CSRF and bounded CLI jobs."""
import argparse,collections,concurrent.futures,hashlib,hmac,http.cookies,ipaddress,json,os,re,secrets,signal,subprocess,tempfile,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import bridge

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
  self.lock=threading.RLock();self.sessions={};self.failures={};self.jobs={};self.keys={};self.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1);self.slots=threading.BoundedSemaphore(6)
 def login(self,password,ip):
  now=time.monotonic()
  with self.lock:
   failures=self.failures.setdefault(ip,collections.deque())
   while failures and failures[0]<now-900:failures.popleft()
   if len(failures)>=5:raise HTTPError(429,'Za dużo prób. Spróbuj ponownie za 15 minut.')
  if not password_matches(password,self.config['password']):
   with self.lock:failures.append(now)
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
  bridge.build(data)
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
   self.jobs[id]={'id':id,'owner':owner,'key':key,'digest':digest,'created':time.monotonic(),'state':'queued','output':'','code':None,'label':bridge.ACTIONS[data['action']][0],'preview':data.get('preview',False)}
   self.keys[owner,key]=id
   self.pool.submit(self.run_job,id,dict(data))
   return id
 def run_job(self,id,data):
  job=self.jobs[id]
  try:
   with self.lock:
    if job['state']=='cancelled':return
    job['state']='running'
   with tempfile.TemporaryFile() as out:
    process=subprocess.Popen(bridge.argv(self.root,self.nik_config,data),env=bridge.environment(self.root),stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
    with self.lock:
     job['process']=process
     if job['state']=='cancelled':os.killpg(process.pid,signal.SIGTERM)
    try:code=process.wait(timeout=180)
    except subprocess.TimeoutExpired:
     self.stop(process);code=124
    out.seek(0);output=bridge.clean(out.read(131072).decode(errors='replace'))
    with self.lock:
     job.pop('process',None);job['code']=code;job['output']=output
     if job['state']!='cancelled':job['state']='success' if code==0 else 'error'
     if code==124:job['output']+='\nPrzekroczono czas panelu. Część operacji mogła zostać wykonana; nie ponawiaj automatycznie.'
  except Exception as error:
   with self.lock:job.update(state='error',code=1,output='Panel nie mógł uruchomić NIK. Sprawdź usługę na serwerze.');job.pop('process',None)
   print('Błąd uruchomienia zadania: '+type(error).__name__,flush=True)
  finally:self.slots.release()
 def stop(self,process):
  if process.poll() is None:
   try:os.killpg(process.pid,signal.SIGTERM);process.wait(timeout=2)
   except subprocess.TimeoutExpired:
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait()
   except ProcessLookupError:pass
 def view(self,id,owner):
  with self.lock:
   j=self.jobs.get(id)
   if not j or j['owner']!=owner:raise HTTPError(404,'Nie znaleziono operacji w tej sesji.')
   return {k:j[k] for k in ('id','state','output','code','label','preview')}
 def cancel(self,id,owner):
  self.view(id,owner)
  with self.lock:
   j=self.jobs[id]
   if j['state'] not in {'running','queued'}:return
   j['state']='cancelled';j['output']='Zatrzymano oczekiwanie i proces NIK. Wcześniejsze kroki mogły zostać wykonane.';p=j.get('process')
  if p:self.stop(p)

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
   if path=='/api/jobs':
    id=app.job(owner,data.get('request'),data.get('key'));self.response(202,{'id':id});return
   if re.fullmatch('/api/jobs/[A-Za-z0-9_-]+/cancel',path):app.cancel(path.split('/')[3],owner);self.response(200,{'ok':True});return
   raise HTTPError(404,'Nie znaleziono czynności.')
  if path=='/api/session':
   _,s=self.authenticated();self.response(200,{'csrf':s['csrf']});return
  if path=='/api/metadata':
   self.authenticated();self.response(200,bridge.metadata(app.root,app.nik_config));return
  if path.startswith('/api/jobs/key/'):
   owner,_=self.authenticated();key=path.rsplit('/',1)[-1]
   with app.lock:id=app.keys.get((owner,key))
   if not id:raise HTTPError(404,'Nie odnaleziono potwierdzenia operacji. Nie ponawiaj jej automatycznie.')
   self.response(200,app.view(id,owner));return
  if re.fullmatch('/api/jobs/[A-Za-z0-9_-]+',path):
   owner,_=self.authenticated();self.response(200,app.view(path.rsplit('/',1)[-1],owner));return
  files={'/':'index.html','/index.html':'index.html','/app.css':'app.css','/app.js':'app.js','/sw.js':'sw.js','/manifest.webmanifest':'manifest.webmanifest','/terrain.svg':'terrain.svg','/icon.svg':'icon.svg','/icons.css':'icons.css','/icons.json':'icons.json','/icons-items.png':'icons-items.png','/icons-creatures.png':'icons-creatures.png','/icon-192.png':'icon-192.png','/icon-512.png':'icon-512.png','/apple-touch-icon.png':'apple-touch-icon.png'}
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
