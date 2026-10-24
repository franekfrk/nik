"""Durable history, restart uncertainty, retention and private storage."""
import concurrent.futures,importlib.util,json,os,sqlite3,sys,tempfile,threading,time,unittest
from pathlib import Path
from unittest.mock import patch,MagicMock
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'panel'))
from history import History,LIMIT
spec=importlib.util.spec_from_file_location('nik_history_server',ROOT/'panel/server.py');server=importlib.util.module_from_spec(spec);spec.loader.exec_module(server)

def record(id='example',state='success',timestamp=None):
 return {'id':id,'state':state,'output':'Plecak: diament ♥\n','code':0,'label':'Plecak','preview':True,'action':'inventory','player':'gracz1','timestamp':time.time() if timestamp is None else timestamp,'command':'plecak','owner':'do-not-store','key':'do-not-store','process':object()}

class HistoryTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.store=History(self.root)
 def tearDown(self):self.tmp.cleanup()
 def test_output_and_metadata_survive_reopening_without_credentials(self):
  self.store.put(record());loaded=History(self.root);r=loaded.get('example')
  self.assertEqual(r['output'],'Plecak: diament ♥\n');self.assertEqual(r['action'],'inventory');self.assertEqual(r['player'],'gracz1')
  self.assertNotIn('owner',r);self.assertNotIn('key',r);self.assertNotIn('process',r)
  self.assertNotIn('output',loaded.list()[0])
 def test_pending_jobs_become_uncertain_without_reexecution(self):
  for state in ['queued','running']:self.store.put(record(state,state))
  loaded=History(self.root)
  for state in ['queued','running']:
   r=loaded.get(state);self.assertEqual(r['state'],'interrupted');self.assertIsNone(r['code']);self.assertIn('nie ponowił',r['output'])
  self.assertEqual(History(self.root).get('running'),loaded.get('running'))
 def test_cancelled_and_failed_outputs_are_preserved(self):
  for state in ['cancelled','error']:self.store.put(record(state,state))
  loaded=History(self.root)
  for state in ['cancelled','error']:self.assertEqual(loaded.get(state)['state'],state);self.assertEqual(loaded.get(state)['output'],'Plecak: diament ♥\n')
 def test_retention_keeps_latest_hundred_and_never_evicts_active_job(self):
  self.store.put(record('active','running',0))
  for n in range(LIMIT+7):self.store.put(record(str(n),timestamp=n+1))
  entries=self.store.list();self.assertEqual(len(entries),LIMIT+1);self.assertEqual(entries[0]['id'],str(LIMIT+6));self.assertIsNone(self.store.get('0'));self.assertIsNotNone(self.store.get('active'))
  self.store.put(record('active','success',0));self.assertEqual(len(self.store.list()),LIMIT);self.assertIsNone(self.store.get('active'))
 def test_repeated_updates_do_not_duplicate_entries(self):
  for state in ['queued','running','success']:self.store.put(record(state=state))
  self.assertEqual(len(self.store.list()),1);self.assertEqual(self.store.get('example')['state'],'success')
 def test_parallel_writes_preserve_all_results(self):
  with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(lambda n:self.store.put(record(str(n))),range(25)))
  self.assertEqual(len(self.store.list()),25)
 def test_storage_is_private_even_with_permissive_umask(self):
  # The installation root exists before App creates its state directory.
  root=self.root/'permissive';root.mkdir();previous=os.umask(0)
  try:other=History(root);other.put(record())
  finally:os.umask(previous)
  self.assertEqual(other.path.stat().st_mode&0o777,0o600);self.assertEqual(other.path.parent.stat().st_mode&0o777,0o700)
 def test_symlink_files_and_directories_are_rejected(self):
  for part in ['state','state/panel','state/panel/history.sqlite3']:
   with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp);target=root/'outside';target.write_text('unchanged');link=root/part;link.parent.mkdir(parents=True,exist_ok=True);link.symlink_to(target)
    with self.assertRaises((ValueError,OSError)):History(root)
    self.assertEqual(target.read_text(),'unchanged')
 def test_corrupt_history_is_preserved_instead_of_silently_reset(self):
  self.store.path.write_bytes(b'not a database')
  with self.assertRaises(sqlite3.DatabaseError):History(self.root)
  self.assertEqual(self.store.path.read_bytes(),b'not a database')
 def test_favorites_are_bounded_and_survive_restart(self):
  for n in range(24):self.store.save_favorite(str(n),'Skrót '+str(n),{'action':'heal','player':'gracz1'})
  with self.assertRaises(ValueError):self.store.save_favorite('extra','x',{'action':'status'})
  loaded=History(self.root);self.assertEqual(len(loaded.favorites()),24);loaded.delete_favorite('0');self.assertEqual(len(History(self.root).favorites()),23)
 def test_running_backup_cannot_be_cancelled_before_server_recovery(self):
  app=server.App({'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')})
  try:
   j=record(state='running');j.update(action='backup',owner='owner');app.jobs[j['id']]=j
   with self.assertRaises(server.HTTPError) as error:app.cancel(j['id'],'owner')
   self.assertEqual(error.exception.status,409);self.assertEqual(app.jobs[j['id']]['state'],'running')
  finally:app.pool.shutdown(wait=True)
 def test_unknown_id_and_sql_injection_do_not_return_another_result(self):
  self.store.put(record());self.assertIsNone(self.store.get("' OR 1=1 --"));self.assertIsNone(self.store.get('missing'))
 def test_failed_initial_write_prevents_command_execution_and_releases_slot(self):
  app=server.App({'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')})
  try:
   with patch.object(app.history,'put',side_effect=OSError('disk full')),patch.object(app.pool,'submit') as submit:
    with self.assertRaises(server.HTTPError) as error:app.job('owner',{'action':'status'},'disk_full_example_123')
    self.assertEqual(error.exception.status,503);submit.assert_not_called();self.assertEqual(app.jobs,{})
   for _ in range(6):self.assertTrue(app.slots.acquire(False))
   self.assertFalse(app.slots.acquire(False))
  finally:app.pool.shutdown(wait=True)
 def test_queue_runs_one_nik_process_and_persists_waiting_running_and_finished(self):
  app=server.App({'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')});release=threading.Event();process=MagicMock();process.wait.side_effect=lambda timeout:(release.wait(3) and 0)
  try:
   with patch.object(server.subprocess,'Popen',return_value=process) as run:
    first=app.job('owner',{'action':'status'},'queue_first_123456')
    deadline=time.monotonic()+2
    while app.history.get(first)['state']!='running' and time.monotonic()<deadline:time.sleep(.01)
    second=app.job('owner',{'action':'status'},'queue_second_123456')
    self.assertEqual(app.history.get(first)['state'],'running');self.assertEqual(app.history.get(second)['state'],'queued');self.assertEqual(run.call_count,1)
    release.set();app.pool.shutdown(wait=True)
    self.assertEqual(app.history.get(first)['state'],'success');self.assertEqual(app.history.get(second)['state'],'success');self.assertEqual(run.call_count,2)
  finally:release.set();app.pool.shutdown(wait=True)
 def test_backup_uses_its_longer_timeout_and_the_original_nik_entrypoint(self):
  app=server.App({'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')});process=MagicMock();process.wait.return_value=0
  try:
   with patch.object(server.subprocess,'Popen',return_value=process) as run:
    app.job('owner',{'action':'backup','confirm':True},'backup_example_12345');app.pool.shutdown(wait=True)
    process.wait.assert_called_once_with(timeout=2100);self.assertEqual(run.call_args.args[0][-2:],['kopia','utworz']);self.assertEqual(run.call_args.args[0][:2],['bash',str(self.root/'nik.sh')])
  finally:app.pool.shutdown(wait=True)
 def test_failed_final_write_exposes_live_warning_instead_of_polling_forever(self):
  app=server.App({'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')});process=MagicMock();process.wait.return_value=0;save=app.history.put
  def write(job):
   if job['state'] not in {'queued','running'}:raise OSError('disk full')
   save(job)
  try:
   with patch.object(app.history,'put',side_effect=write),patch.object(server.subprocess,'Popen',return_value=process):
    id=app.job('owner',{'action':'status'},'final_write_failure_1234');app.pool.shutdown(wait=True)
    self.assertEqual(app.history_view(id)['state'],'error');self.assertIn('na dysku',app.history_view(id)['output']);self.assertEqual(app.history_list()[0]['state'],'error');self.assertEqual(app.history.get(id)['state'],'running')
  finally:app.pool.shutdown(wait=True)
 def test_app_restart_keeps_result_without_starting_any_command(self):
  self.store.put(record());config={'nik_root':str(self.root),'origins':['https://example.test'],'password':server.password_record('password')}
  with patch.object(server.subprocess,'Popen') as process:
   app=server.App(config)
   try:self.assertEqual(app.history.get('example')['output'],'Plecak: diament ♥\n');self.assertEqual(app.jobs,{});process.assert_not_called()
   finally:app.pool.shutdown(wait=True)

if __name__=='__main__':unittest.main()
