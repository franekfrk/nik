"""Real NIK -> JSON stream -> panel -> durable results, plus SQL migrations."""
import importlib.util,json,os,shlex,sqlite3,sys,threading,time,unittest
from pathlib import Path
from unittest.mock import patch
from test_json_cli import Fixture,ROOT
sys.path.insert(0,str(ROOT/'panel'))
from history import History
spec=importlib.util.spec_from_file_location('nik_mobile_data_server',ROOT/'panel/server.py');server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server)
class StreamTests(unittest.TestCase):
 def test_utf8_fragmentation_live_output_and_typed_result(self):
  job={'state':'running','progress':[],'output':''};decoder=server.JobEvents(job,threading.RLock())
  events=[{'type':'progress','message':'Odczytuję plecak ♥'},{'type':'output','text':'Pozycja 1\n'},{'type':'result','data':{'schema':1,'ok':True,'code':0,'output':'Gotowe\n','result':{'type':'inventory','slots':[]}}}]
  raw=('\n'.join(json.dumps(e,ensure_ascii=False) for e in events)+'\n').encode()
  for byte in raw:decoder.feed(bytes([byte]))
  text,result=decoder.finish();self.assertEqual(text,'Gotowe\n');self.assertEqual(job['output'],'Pozycja 1\n');self.assertIn('♥',job['progress'][0]['message']);self.assertEqual(result['result']['slots'],[])
 def test_cancelled_output_is_not_overwritten_and_progress_is_bounded(self):
  job={'state':'cancelled','progress':[],'output':'Zatrzymano'};decoder=server.JobEvents(job,threading.RLock())
  for n in range(70):decoder.feed((json.dumps({'type':'progress','message':str(n)})+'\n').encode())
  decoder.feed(b'{"type":"output","text":"old output"}\n');self.assertEqual(job['output'],'Zatrzymano');self.assertEqual(len(job['progress']),40)
 def test_duplicate_results_and_unbounded_stream_are_rejected(self):
  decoder=server.JobEvents({'state':'running','progress':[]},threading.RLock());event=b'{"type":"result","data":{"schema":1}}\n';decoder.feed(event)
  with self.assertRaises(ValueError):decoder.feed(event)
  with self.assertRaises(ValueError):server.JobEvents({},threading.RLock()).feed(b'x'*8388609)
class PanelNIKTests(Fixture,unittest.TestCase):
 def test_real_nik_inventory_stream_and_result_survive_reopening(self):
  (self.base/'nik.sh').write_text('exec bash '+shlex.quote(str(ROOT/'nik.sh'))+' "$@"\n')
  self.env['NIK_TEST_DELAY']='0.05'
  with patch.dict(os.environ,self.env):
   app=server.App({'nik_root':str(self.base),'nik_config':str(self.cfg),'origins':['https://example.test'],'password':server.password_record('test')})
   try:
    id=app.job('owner',{'action':'inventory','player':'g1'},'typed_inventory_123456');observed=False;deadline=time.monotonic()+20
    while time.monotonic()<deadline:
     j=app.history_view(id);observed=observed or (j['state']=='running' and bool(j['progress']))
     if j['state'] not in {'running','queued'}:break
     time.sleep(.04)
    app.pool.shutdown(wait=True);self.assertEqual(j['state'],'success',j['output']);self.assertTrue(observed);self.assertEqual(j['result']['type'],'inventory');self.assertNotIn('result',app.history_list()[0]);saved=History(self.base).get(id);self.assertEqual(saved['result'],j['result']);self.assertGreater(len(saved['progress']),0)
   finally:app.pool.shutdown(wait=True)
class StateTests(Fixture,unittest.TestCase):
 def test_legacy_favorites_migrate_without_losing_data_and_edit_at_capacity(self):
  folder=self.base/'state/panel';folder.mkdir(parents=True);db=folder/'history.sqlite3'
  with sqlite3.connect(db) as conn:
   conn.execute('CREATE TABLE favorites (id TEXT PRIMARY KEY,name TEXT NOT NULL,request TEXT NOT NULL)');conn.execute('INSERT INTO favorites VALUES (?,?,?)',('old','Stary',json.dumps({'action':'heal','player':'g1'})))
  conn.close()
  history=History(self.base);self.assertEqual(history.favorites()[0]['id'],'old')
  for n in range(23):history.save_favorite(str(n),'Nazwa',{'action':'status'})
  history.edit_favorite('old','Nowy',{'action':'heal','player':'g2'});ids=[e['id'] for e in history.favorites()][::-1];history.reorder_favorites(ids)
  loaded=History(self.base);self.assertEqual([e['id'] for e in loaded.favorites()],ids);self.assertEqual(next(e for e in loaded.favorites() if e['id']=='old')['request']['player'],'g2')
  with self.assertRaises(ValueError):loaded.reorder_favorites(ids[:-1])
  with self.assertRaises(ValueError):loaded.edit_favorite('missing','x',{'action':'status'})
 def test_catalog_preferences_are_bounded_and_survive_restart(self):
  history=History(self.base)
  for n in range(100):history.catalog_pin('items',str(n),True,n);history.catalog_remember('items',str(n),n)
  with self.assertRaises(ValueError):history.catalog_pin('items','new',True,101)
  history.catalog_pin('items','0',True,102);loaded=History(self.base);self.assertEqual(len(loaded.catalog()['pins']),100);self.assertEqual(len(loaded.catalog()['recent']),40);self.assertEqual(loaded.catalog()['recent'][0]['id'],'99')
if __name__=='__main__':unittest.main()
