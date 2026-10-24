"""Queue cancellation never invokes NIK; replay params remain private and unconfirmed."""
import json,os,shlex,sys,tempfile,time,unittest
from pathlib import Path
from test_panel import server,bridge
class WorkflowsTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.root.joinpath('nik.sh').write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> '''+shlex.quote(str(self.root/'calls'))+'''
if [[ ${*: -1} == status ]]; then
 touch '''+shlex.quote(str(self.root/'started'))+'''
 while [[ ! -f '''+shlex.quote(str(self.root/'release'))+''' ]]; do sleep .02; done
fi
printf 'Command completed successfully\\n'
''')
  self.app=server.App({'nik_root':str(self.root),'origins':['https://test.example'],'password':server.password_record('test')})
 def tearDown(self):self.root.joinpath('release').touch();self.app.pool.shutdown(wait=True);self.temp.cleanup()
 def running(self):
  id=self.app.job('owner',{'action':'status'},'status_key_123456789');deadline=time.monotonic()+5
  while not (self.root/'started').exists() and time.monotonic()<deadline:time.sleep(.01)
  self.assertTrue((self.root/'started').exists());return id
 def test_queued_cancel_never_invokes_nik_and_releases_capacity_immediately(self):
  self.running();ids=[self.app.job('owner',{'action':'day'},'queued_key_123456'+str(i)) for i in range(5)]
  for id in ids:self.app.cancel(id,'owner');self.assertEqual(self.app.history_view(id)['state'],'cancelled')
  replacements=[self.app.job('owner',{'action':'night'},'new_queue_123456'+str(i)) for i in range(5)];self.assertEqual(len(replacements),5)
  for id in replacements:self.app.cancel(id,'owner')
  self.root.joinpath('release').touch();self.app.pool.shutdown(wait=True);self.assertEqual(len((self.root/'calls').read_text().splitlines()),1)
  self.assertIn('nie została uruchomiona',self.app.history_view(ids[0])['output'])
 def test_replay_request_survives_storage_without_confirmation_or_unknown_fields(self):
  self.running();data={'action':'clear_effects','player':'g1','confirm':True,'secret_extra':'do-not-store'};id=self.app.job('owner',data,'replay_key_123456789');stored=self.app.history.get(id);self.assertEqual(stored['request'],{'action':'clear_effects','player':'g1'});self.assertNotIn('request',self.app.history_list()[0]);self.app.cancel(id,'owner')
  with self.assertRaises(bridge.InputError):bridge.build(stored['request'])
 def test_queue_only_cancel_never_stops_a_job_that_has_started(self):
  running=self.running()
  with self.assertRaises(server.HTTPError):self.app.cancel(running,'owner',queued_only=True)
  self.assertEqual(self.app.history_view(running)['state'],'running')
 def test_authenticated_other_session_can_cancel_queued_but_not_running_job(self):
  running=self.running();queued=self.app.job('owner',{'action':'day'},'shared_queue_1234567');self.app.cancel(queued,'another-session');self.assertEqual(self.app.history_view(queued)['state'],'cancelled')
  with self.assertRaises(server.HTTPError):self.app.cancel(running,'another-session')
if __name__=='__main__':unittest.main()
