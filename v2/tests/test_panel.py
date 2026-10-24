"""HTTP integration, command adapter, auth, CSRF, queue isolation and PWA assets."""
import concurrent.futures,http.client,importlib.util,json,os,re,sys,tempfile,threading,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'panel'))
# Avoid collision with another stdlib/local module named server.
spec=importlib.util.spec_from_file_location('nik_mobile_server',ROOT/'panel/server.py');server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server)
import bridge

class AdapterTests(unittest.TestCase):
 def test_lan_listener_is_explicit_and_private(self):
  cfg={'origins':['https://nik.example.test:6767']}
  self.assertEqual(server.listener_addresses(cfg),[('127.0.0.1',6767)])
  cfg.update(lan_bind='192.168.1.10');cfg['origins'].append('http://192.168.1.10:6767')
  self.assertEqual(server.listener_addresses(cfg)[1],('192.168.1.10',6767))
  for host in ['0.0.0.0','8.8.8.8','127.0.0.2','::1']:
   with self.subTest(host=host),self.assertRaises(ValueError):server.listener_addresses({**cfg,'lan_bind':host})
  with self.assertRaises(ValueError):server.listener_addresses({**cfg,'origins':[]})
 def test_minecraft_icons_cover_the_complete_catalog(self):
  index=json.loads((ROOT/'panel/static/icons.json').read_text())
  for kind,file in [('items','items.tsv'),('creatures','creatures.tsv')]:
   ids={line.split('\t')[1] for line in (ROOT/'data'/file).read_text().splitlines() if line and not line.startswith('#')}
   self.assertEqual(set(index[kind]),ids)
   self.assertEqual(set(index['sources'][kind]),ids)
   for source in index['sources'][kind].values():self.assertNotIn('?',source);self.assertNotIn('unknown',source.lower())
   self.assertNotEqual(index[kind][next(iter(ids))],None)
  self.assertNotEqual(index['items']['diamond_sword'],index['items']['diamond_pickaxe'])
  self.assertNotEqual(index['creatures']['cow'],index['creatures']['pig'])
 def test_icon_cells_fit_the_actual_atlases_and_pwa_caches_them(self):
  import struct
  index=json.loads((ROOT/'panel/static/icons.json').read_text());css=(ROOT/'panel/static/icons.css').read_text();sw=(ROOT/'panel/static/sw.js').read_text()
  for kind in ['items','creatures']:
   image=(ROOT/'panel/static'/('icons-'+kind+'.png')).read_bytes();self.assertEqual(image[:8],b'\x89PNG\r\n\x1a\n');width,height=struct.unpack('!II',image[16:24])
   for id,(x,y) in index[kind].items():
    self.assertGreaterEqual(x,0);self.assertGreaterEqual(y,0);self.assertLessEqual(x+32,width);self.assertLessEqual(y+32,height);self.assertIn('.mc-'+kind+'-'+id+'{',css)
   self.assertIn('/icons-'+kind+'.png',sw)
  self.assertIn('/icons.json',sw);self.assertIn('/icons.css',sw)
 def test_optional_counts_and_real_entrypoint(self):
  for count in [1,3,12,64]:
   args=bridge.argv(ROOT,ROOT/'config',{'action':'summon','player':'g1','creature':'krowa','count':count})
   self.assertEqual(args[-4:],['przywolaj','g1','krowa',str(count)]);self.assertIn('--',args);self.assertEqual(args[:2],['bash',str(ROOT/'nik.sh')])
 def test_invalid_quantities(self):
  for value in [0,65,True,1.5,'6','x',None]:
   with self.subTest(value=value),self.assertRaises(bridge.InputError):bridge.build({'action':'summon','player':'g1','creature':'krowa','count':value})
 def test_text_is_literal_and_options_terminated(self):
  args=bridge.argv(ROOT,ROOT/'config',{'action':'title','player':'g1','text':'$(touch /tmp/NO) {"text":"hi"}'})
  self.assertEqual(args[-1],'$(touch /tmp/NO) {"text":"hi"}');self.assertLess(args.index('--'),args.index('napis'))
 def test_unknown_actions_and_control_characters(self):
  for data in [{'action':'restartmc'},{'action':'shell','text':'id'},[],None,{'action':'title','player':'g1','text':'test\nline'},{'action':'title','player':'g1','text':'x'*513},{'action':'give','player':'g1','item':'diamond','preview':'false'}]:
   with self.subTest(data=data),self.assertRaises(bridge.InputError):bridge.build(data)
 def test_confirmation_is_enforced(self):
  with self.assertRaises(bridge.InputError):bridge.build({'action':'clear_effects','player':'g1'})
  self.assertTrue(bridge.build({'action':'clear_effects','player':'g1','confirm':True})[2])
  self.assertTrue(bridge.build({'action':'clear_effects','player':'g1','preview':True})[1])
 def test_game_modes_and_enchantments(self):
  self.assertEqual(bridge.build({'action':'mode','player':'g1','mode':'kreatywny'})[0],['kreatywny','g1'])
  self.assertEqual(bridge.build({'action':'enchant_hand','player':'g1','enchantments':['ostrosc:5','naprawa']})[0][-2:],['ostrosc:5','naprawa'])
  for data in [{'action':'mode','player':'g1','mode':'op'},{'action':'enchant_hand','player':'g1','enchantments':[]}]:
   with self.assertRaises(bridge.InputError):bridge.build(data)
 def test_all_exposed_actions_have_build_paths(self):
  fields={'player':'g1','item':'diamond_sword','creature':'krowa','place':'dom','name':'baza','text':'Brawo ♥','reward':'budowniczy','weather':'slonce','mode':'przetrwanie','effect':'sila','enchantments':['naprawa'],'kit':'budowniczy','scenario':'wyprawa','steps':['zdrowie {gracz}'],'confirm':True}
  for action in bridge.ACTIONS:
   with self.subTest(action=action):self.assertTrue(bridge.build({'action':action,**fields})[0][0])
 def test_pwa_manifest_and_network_only_api(self):
  data=json.loads((ROOT/'panel/static/manifest.webmanifest').read_text());self.assertEqual(data['display'],'standalone');self.assertEqual(data['start_url'],'/')
  for icon in data['icons']:self.assertTrue((ROOT/'panel/static'/icon['src'].lstrip('/')).is_file())
  sw=(ROOT/'panel/static/sw.js').read_text();self.assertIn("url.pathname.startsWith('/api/')",sw);self.assertIn("event.request.method!=='GET'",sw);self.assertNotIn('sync.add',sw)
 def test_metadata_contains_logical_names_not_private_nicks(self):
  m=bridge.metadata(ROOT,ROOT/'config.example');self.assertGreater(len(m['items']),1600);self.assertEqual(m['players'][0]['id'],'gracz1');self.assertNotIn('PlayerOne',json.dumps(m));self.assertEqual(len(m['enchantments']),43)
 def test_end_is_offered_only_as_a_teleport_destination_without_private_config(self):
  metadata=bridge.metadata(ROOT,ROOT/'config.example');self.assertIn('end',metadata['teleport_places']);self.assertNotIn('end',metadata['places'])
 def test_panel_end_preview_uses_the_original_nik_safe_destination(self):
  import shutil,subprocess
  with tempfile.TemporaryDirectory() as tmp:
   cfg=Path(tmp)/'config';shutil.copytree(ROOT/'config.example',cfg)
   result=subprocess.run(bridge.argv(ROOT,cfg,{'action':'teleport','player':'g1','place':'end','preview':True}),env=bridge.environment(ROOT),capture_output=True,text=True,timeout=20)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);final=json.loads(result.stdout.splitlines()[-1])['data'];self.assertTrue(final['ok']);self.assertIn('spreadplayers 16 0 0 8 under 96 false PlayerOne',final['output'])
 def test_nether_metadata_and_preview_use_nik_without_private_configuration(self):
  metadata=bridge.metadata(ROOT,ROOT/'config.example');self.assertIn('nether',metadata['teleport_places']);self.assertNotIn('nether',metadata['places'])
  import shutil,subprocess
  with tempfile.TemporaryDirectory() as tmp:
   cfg=Path(tmp)/'config';shutil.copytree(ROOT/'config.example',cfg)
   result=subprocess.run(bridge.argv(ROOT,cfg,{'action':'teleport','player':'g1','place':'nether','preview':True}),env=bridge.environment(ROOT),capture_output=True,text=True,timeout=20)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr);final=json.loads(result.stdout.splitlines()[-1])['data'];self.assertTrue(final['ok']);self.assertIn('dwa bloki powietrza',final['output'])
 def test_environment_drops_shell_injection_hooks(self):
  original=os.environ.get('BASH_ENV');os.environ['BASH_ENV']='/tmp/attack'
  try:self.assertNotIn('BASH_ENV',bridge.environment(ROOT))
  finally:
   if original is None:os.environ.pop('BASH_ENV',None)
   else:os.environ['BASH_ENV']=original

class HTTPTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.root=Path(cls.tmp.name)
  # A fake NIK writes invocation arguments to its own temporary fixture only.
  entry=cls.root/'nik.sh';entry.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$@"
if [[ ${*: -1} == FAIL ]]; then exit 7; fi
''')
  (cls.root/'data').symlink_to(ROOT/'data',target_is_directory=True)
  cls.app=server.App({'nik_root':str(cls.root),'origins':['https://nik.example.test:6767'],'password':server.password_record('test-password')})
  cls.http=server.Server(('127.0.0.1',0),cls.app);cls.port=cls.http.server_address[1]
  cls.thread=threading.Thread(target=cls.http.serve_forever,daemon=True);cls.thread.start()
 @classmethod
 def tearDownClass(cls):cls.http.shutdown();cls.http.server_close();cls.app.pool.shutdown(wait=True);cls.tmp.cleanup()
 def test_icon_files_are_public_but_private_metadata_stays_protected(self):
  for path,kind in [('/icons.json','application/json'),('/icons.css','text/css'),('/icons-items.png','image/png'),('/icons-creatures.png','image/png')]:
   status,headers,body=self.request(path);self.assertEqual(status,200);self.assertTrue(headers['Content-Type'].startswith(kind))
  self.assertEqual(self.request('/api/metadata')[0],401)
 def test_lan_http_login_has_httponly_cookie_without_secure(self):
  origin='http://192.168.1.10:6767';host='192.168.1.10:6767'
  self.app.origins.append(origin);self.app.hosts.add(host)
  try:
   status,headers,data=self.request('/api/login',{'password':'test-password'},host=host,origin=origin)
   self.assertEqual(status,200)
   cookie=dict(headers).get('Set-Cookie','')
   self.assertIn('HttpOnly',cookie);self.assertIn('SameSite=Strict',cookie);self.assertNotIn('Secure',cookie)
  finally:self.app.origins.remove(origin);self.app.hosts.remove(host)
 def request(self,path,body=None,cookie=None,csrf=None,host='nik.example.test:6767',origin='https://nik.example.test:6767',content_type='application/json'):
  c=http.client.HTTPConnection('127.0.0.1',self.port,timeout=5);headers={'Host':host}
  if cookie:headers['Cookie']=cookie
  if csrf:headers['X-CSRF-Token']=csrf
  payload=None
  if body is not None:headers.update({'Origin':origin,'Content-Type':content_type});payload=json.dumps(body)
  c.request('GET' if body is None else 'POST',path,body=payload,headers=headers);r=c.getresponse();raw=r.read();h=dict(r.getheaders());status=r.status;c.close()
  return status,h,json.loads(raw) if h.get('Content-Type','').startswith('application/json') else raw
 def login(self):
  status,h,r=self.request('/api/login',{'password':'test-password'});self.assertEqual(status,200);return h['Set-Cookie'].split(';')[0],r['csrf']
 def job(self,cookie,csrf,data,key='a_valid_unique_key_123'):
  return self.request('/api/jobs',{'key':key,'request':data},cookie,csrf)
 def wait(self,id,cookie):
  deadline=time.monotonic()+5
  while time.monotonic()<deadline:
   status,_,j=self.request('/api/jobs/'+id,cookie=cookie)
   if j.get('state') not in {'running','queued'}:return j
   time.sleep(.02)
  self.fail('Job did not complete')
 def test_auth_required_and_secure_cookie(self):
  self.assertEqual(self.request('/api/metadata')[0],401)
  status,h,r=self.request('/api/login',{'password':'test-password'});self.assertEqual(status,200)
  for flag in ['HttpOnly','Secure','SameSite=Strict']:self.assertIn(flag,h['Set-Cookie'])
 def test_login_invalid_password_and_throttling(self):
  for _ in range(5):self.assertEqual(self.request('/api/login',{'password':'bad'})[0],401)
  self.assertEqual(self.request('/api/login',{'password':'bad'})[0],429)
  with self.app.lock:self.app.failures.clear()
 def test_host_origin_and_json_guards(self):
  self.assertEqual(self.request('/',host='evil.test')[0],403)
  self.assertEqual(self.request('/api/login',{'password':'test-password'},origin='https://evil.test')[0],403)
  self.assertEqual(self.request('/api/login',{'password':'test-password'},content_type='text/plain')[0],415)
 def test_csrf_and_unknown_command_rejected(self):
  cookie,csrf=self.login();self.assertEqual(self.job(cookie,'wrong',{'action':'heal','player':'g1'})[0],403)
  self.assertEqual(self.job(cookie,csrf,{'action':'shell'})[0],400)
 def test_job_uses_argv_and_returns_real_exit_status(self):
  cookie,csrf=self.login();status,_,j=self.job(cookie,csrf,{'action':'summon','player':'g1','creature':'krowa','count':6,'preview':True},'summon_preview_123456')
  self.assertEqual(status,202);r=self.wait(j['id'],cookie);self.assertEqual(r['state'],'success');self.assertIn('--podglad',r['output']);self.assertIn('przywolaj\ng1\nkrowa\n6',r['output'])
  status,_,j=self.job(cookie,csrf,{'action':'title','player':'g1','text':'FAIL'},'failed_operation_1234');r=self.wait(j['id'],cookie);self.assertEqual(r['code'],7);self.assertEqual(r['state'],'error')
 def test_idempotency_never_reexecutes_same_request(self):
  cookie,csrf=self.login();d={'action':'heal','player':'g1'}
  a=self.job(cookie,csrf,d,'idempotency_example_1234');b=self.job(cookie,csrf,d,'idempotency_example_1234');self.assertEqual(a[2]['id'],b[2]['id'])
  self.assertEqual(self.job(cookie,csrf,{'action':'home','player':'g1'},'idempotency_example_1234')[0],409)
 def test_results_are_session_private(self):
  a,ac=self.login();b,bc=self.login();_,_,j=self.job(a,ac,{'action':'heal','player':'g1'},'private_result_123456')
  self.assertEqual(self.request('/api/jobs/'+j['id'],cookie=b)[0],404)
  self.assertEqual(self.request('/api/jobs/key/private_result_123456',cookie=b)[0],404)
 def test_history_requires_login_and_is_shared_after_relogin(self):
  a,ac=self.login();_,_,j=self.job(a,ac,{'action':'inventory','player':'g1','preview':True},'durable_history_12345');result=self.wait(j['id'],a)
  self.assertEqual(self.request('/api/history')[0],401);self.assertEqual(self.request('/api/history/'+j['id'])[0],401)
  self.request('/api/logout',{},a,ac);b,bc=self.login()
  status,headers,listing=self.request('/api/history',cookie=b);self.assertEqual(status,200);self.assertEqual(headers['Cache-Control'],'no-store')
  summary=next(e for e in listing['entries'] if e['id']==j['id']);self.assertNotIn('output',summary);self.assertNotIn('owner',summary);self.assertNotIn('key',summary)
  status,_,saved=self.request('/api/history/'+j['id'],cookie=b);self.assertEqual(status,200);self.assertEqual(saved['output'],result['output']);self.assertEqual(saved['state'],'success');self.assertEqual(saved['action'],'inventory');self.assertEqual(saved['player'],'g1')
  self.assertEqual(self.request('/api/history/missing',cookie=b)[0],404)
  self.assertEqual(self.request('/state/panel/history.sqlite3',cookie=b)[0],404)
  self.assertEqual(self.request('/api/jobs/'+j['id']+'/cancel',{},b,bc)[0],404)
 def test_favorites_validate_csrf_and_persist_across_logins(self):
  self.assertEqual(self.request('/api/favorites')[0],401)
  a,csrf=self.login();data={'name':'Ulecz gracza','request':{'action':'heal','player':'g1','confirm':True,'preview':True,'password':'do-not-store'}}
  self.assertEqual(self.request('/api/favorites',data,a,'wrong')[0],403)
  status,_,saved=self.request('/api/favorites',data,a,csrf);self.assertEqual(status,201)
  b,bc=self.login();entries=self.request('/api/favorites',cookie=b)[2]['entries'];favorite=next(e for e in entries if e['id']==saved['id'])
  self.assertEqual(favorite['request'],{'action':'heal','player':'g1'})
  self.assertEqual(self.request('/api/favorites',{'name':'x','request':{'action':'shell'}},a,csrf)[0],400)
  self.assertEqual(self.request('/api/favorites',{'name':'','request':{'action':'heal','player':'g1'}},a,csrf)[0],400)
  self.assertEqual(self.request('/api/favorites/'+saved['id']+'/delete',{},b,bc)[0],200)
  self.assertNotIn(saved['id'],[e['id'] for e in self.request('/api/favorites',cookie=b)[2]['entries']])
 def test_new_adapters_require_confirmation_and_always_use_nik(self):
  for action,command in [('backup','kopia'),('equip','wyposaz')]:
   data={'action':action,'player':'g1','kit':'budowniczy'}
   with self.assertRaises(bridge.InputError):bridge.build(data)
   args=bridge.argv(ROOT,ROOT/'config.example',{**data,'confirm':True});self.assertEqual(args[:2],['bash',str(ROOT/'nik.sh')]);self.assertIn(command,args);self.assertIn('--potwierdz',args)
  self.assertEqual(bridge.build({'action':'players'})[0],['stan','lista','json'])
  self.assertEqual(bridge.build({'action':'backups'})[0],['kopia','dane'])
 def test_edit_and_reorder_favorites_keep_ids_and_survive_relogin(self):
  cookie,csrf=self.login();ids=[]
  for name in ['Pierwszy','Drugi']:
   status,_,data=self.request('/api/favorites',{'name':name,'request':{'action':'heal','player':'g1'}},cookie,csrf);self.assertEqual(status,201);ids.append(data['id'])
  before=self.request('/api/favorites',cookie=cookie)[2]['entries'];order=[e['id'] for e in before][::-1]
  self.assertEqual(self.request('/api/favorites',{'id':ids[0],'name':'Zmieniony','request':{'action':'give','player':'g2','item':'diament','count':16}},cookie,csrf)[0],201)
  self.assertEqual(self.request('/api/favorites/order',{'ids':order},cookie,csrf)[0],200)
  self.assertEqual(self.request('/api/favorites/order',{'ids':order+order},cookie,csrf)[0],400)
  other,_=self.login();saved=self.request('/api/favorites',cookie=other)[2]['entries'];self.assertEqual([e['id'] for e in saved],order);item=next(e for e in saved if e['id']==ids[0]);self.assertEqual(item['name'],'Zmieniony');self.assertEqual(item['request']['count'],16);self.assertEqual(item['request']['player'],'g2')
  for id in ids:self.request('/api/favorites/'+id+'/delete',{},cookie,csrf)
 def test_catalog_preferences_require_auth_csrf_and_real_nik_ids(self):
  self.assertEqual(self.request('/api/catalog')[0],401);cookie,csrf=self.login()
  good={'kind':'items','id':'diamond','enabled':True}
  self.assertEqual(self.request('/api/catalog/pin',good,cookie,'wrong')[0],403)
  self.assertEqual(self.request('/api/catalog/pin',good,cookie,csrf)[0],200)
  for data in [{'kind':[],'id':'diamond','enabled':True},{'kind':'items','id':'missing','enabled':True},{'kind':'items','id':'diamond','enabled':'true'}]:self.assertEqual(self.request('/api/catalog/pin',data,cookie,csrf)[0],400)
  self.assertEqual(self.request('/api/catalog/recent',{'kind':'items','id':'diamond'},cookie,csrf)[0],200)
  other,_=self.login();status,headers,data=self.request('/api/catalog',cookie=other);self.assertEqual(status,200);self.assertEqual(headers['Cache-Control'],'no-store');self.assertIn({'kind':'items','id':'diamond'},data['pins']);self.assertIn({'kind':'items','id':'diamond'},data['recent'])
  self.request('/api/catalog/pin',{**good,'enabled':False},cookie,csrf)
 def test_new_ui_assets_are_local_and_public_but_preferences_are_private(self):
  for path in ['/enhancements.js','/enhancements.css']:self.assertEqual(self.request(path)[0],200)
  self.assertEqual(self.request('/state/panel/history.sqlite3')[0],404)
 def test_logout_revokes_session(self):
  cookie,csrf=self.login();self.assertEqual(self.request('/api/logout',{},cookie,csrf)[0],200);self.assertEqual(self.request('/api/session',cookie=cookie)[0],401)
 def test_static_csp_and_no_file_traversal(self):
  status,h,_=self.request('/');self.assertEqual(status,200);self.assertIn("frame-ancestors 'none'",h['Content-Security-Policy']);self.assertEqual(h['Cache-Control'],'no-store')
  for path in ['/../config/panel.json','/server.py','/config/panel-password.txt','/api/unknown']:self.assertEqual(self.request(path)[0],404)
 def test_private_data_is_not_present_in_shell_assets(self):
  status,_,raw=self.request('/');self.assertEqual(status,200);self.assertNotIn(b'test-password',raw);self.assertNotIn(b'password_hash',raw)


class RealNIKPreviewTests(unittest.TestCase):
 def test_panel_actions_use_real_nik_validation_without_docker(self):
  import shutil,subprocess
  with tempfile.TemporaryDirectory() as tmp:
   base=Path(tmp);cfg=base/'config';shutil.copytree(ROOT/'config.example',cfg)
   with (cfg/'places.tsv').open('a') as out:out.write('baza\t1\t64\t2\tminecraft:overworld\ndom\t10\t64\t20\tminecraft:overworld\n')
   bin=base/'bin';bin.mkdir();docker=bin/'docker';docker.write_text('#!/usr/bin/env bash\ntouch "'+str(base/'DOCKER_WAS_CALLED')+'"\nexit 99\n');docker.chmod(0o700)
   quests=cfg/'quests';quests.mkdir()
   state=base/'state';(state/'returns').mkdir(parents=True);(state/'returns/PlayerOne.json').write_text(json.dumps({'schema':1,'player':'PlayerOne','container':'minecraft','position':['1','64','2'],'rotation':['0','0'],'dimension':'minecraft:overworld'}))
   (cfg/'scenarios').mkdir();(cfg/'scenarios/wyprawa.json').write_text(json.dumps({'schema':1,'name':'wyprawa','steps':['zdrowie {gracz}']}))
   (cfg/'favorites').mkdir();(cfg/'favorites/budowniczy.tsv').write_text('torch\t64\n')
   fields={'player':'g1','item':'diamentowy_miecz','creature':'krowa','place':'baza','name':'port','text':'Brawo ♥','reward':'budowniczy','weather':'slonce','mode':'przetrwanie','effect':'sila','enchantments':['naprawa'],'kit':'budowniczy','scenario':'wyprawa','steps':['zdrowie {gracz}'],'confirm':True,'preview':True}
   for action in bridge.ACTIONS:
    with self.subTest(action=action):
     record=quests/'PlayerOne.json'
     if action in {'quest_show','quest_done'}:
      task=subprocess.check_output(['python3',str(ROOT/'tools/family-state.py'),'task-new','PlayerOne','minecraft','Misja testowa'],text=True);record.write_text(task)
     else:record.unlink(missing_ok=True)
     env=bridge.environment(ROOT);env['NIK_STATE']=str(state);env['PATH']=str(bin)+os.pathsep+env['PATH']
     result=subprocess.run(bridge.argv(ROOT,cfg,{'action':action,**fields}),capture_output=True,text=True,env=env,timeout=15)
     self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   self.assertFalse((base/'DOCKER_WAS_CALLED').exists())

if __name__=='__main__':unittest.main()
