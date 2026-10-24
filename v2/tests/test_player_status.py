"""NIK owns read-only player snapshots; the panel only invokes its CLI."""
import importlib.util,json,os,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('nik_player_status',ROOT/'tools/player-status.py');status=importlib.util.module_from_spec(spec);spec.loader.exec_module(status)
RAW='PlayerOne has the following entity data: '
class PlayerStateTests(unittest.TestCase):
 def test_online_list_handles_java_bedrock_and_offline_without_guessing(self):
  raw='There are 2 of a max of 20 players online: PlayerOne, .Bedrock'
  self.assertTrue(status.online('playerone',raw));self.assertTrue(status.online('.Bedrock',raw));self.assertFalse(status.online('PlayerTwo',raw))
  self.assertFalse(status.online('PlayerOne','There are 0 of a max of 20 players online: '))
  for raw in ['Command completed successfully','There are 2 of a max of 20 players online: PlayerOne','No entity was found']:
   with self.assertRaises(AssertionError):status.online('PlayerOne',raw)
 def test_typed_snapshot_rejects_invalid_or_truncated_data(self):
  fields=[RAW+'19.5f',RAW+'18',RAW+'1',RAW+'[1.0d, 64d, -3d]',RAW+'"minecraft:overworld"']
  data=status.snapshot('gracz1',*fields);self.assertEqual(data['health'],19.5);self.assertEqual(data['mode'],'kreatywny');self.assertEqual(data['position'],[1,64,-3]);self.assertNotIn('PlayerOne',json.dumps(data))
  for n,value in [(0,'nanf'),(1,'21'),(2,'4'),(3,'[1d,...'),(4,'"bad dim"')]:
   bad=fields.copy();bad[n]=RAW+value
   with self.subTest(n=n),self.assertRaises((ValueError,AssertionError)):status.snapshot('gracz1',*bad)
 def test_cli_completion_offers_players_and_json_format(self):
  env={**os.environ,'NIK_CONFIG':str(ROOT/'config.example')}
  first=subprocess.check_output(['bash',str(ROOT/'nik.sh'),'__complete','stan','1','g'],env=env,text=True);self.assertIn('g1',first)
  second=subprocess.check_output(['bash',str(ROOT/'nik.sh'),'__complete','stan','2','j'],env=env,text=True);self.assertIn('json',second)
 def test_text_color_never_leaks_into_machine_readable_output(self):
  env={**os.environ,'NIK_COLOR':'always'};data=json.dumps({'id':'gracz1','online':False})+'\n'
  for format in ['json','tekst']:
   result=subprocess.run([sys.executable,str(ROOT/'tools/player-status.py'),'collect',format],input=data,env=env,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr)
   if format=='json':self.assertNotIn('\033',result.stdout);self.assertFalse(json.loads(result.stdout)['players'][0]['online'])
   else:self.assertIn('\033[92m',result.stdout)
 def test_real_nik_command_reads_only_and_reports_offline_separately(self):
  with tempfile.TemporaryDirectory() as tmp:
   base=Path(tmp);shutil.copytree(ROOT/'config.example',base/'config');(base/'bin').mkdir()
   docker=base/'bin/docker';docker.write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
with (Path(os.environ['FIXTURE'])/'calls').open('a') as out:out.write(sys.argv[-1]+'\\n')
if sys.argv[1]=='inspect':print('true')
else:
 command=sys.argv[-1]
 if command=='list':print('There are 1 of a max of 20 players online: PlayerOne')
 elif command.startswith('data get entity PlayerOne '):
  values={'Health':'19.0f','foodLevel':'18','playerGameType':'0','Pos':'[1d, 64d, -2d]','Dimension':'"minecraft:overworld"'}
  print('PlayerOne has the following entity data: '+values[command.split()[-1]])
 else:sys.exit(8)
''');docker.chmod(0o700)
   env={**os.environ,'FIXTURE':str(base),'NIK_STATE':str(base/'state'),'PATH':str(base/'bin')+os.pathsep+os.environ['PATH']}
   with (base/'config/config.env').open('a') as out:out.write('LOG='+str(base/'nik.log')+'\n')
   result=subprocess.run(['bash',str(ROOT/'nik.sh'),'--config',str(base/'config'),'stan','lista','json'],env=env,capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr);data=json.loads(result.stdout)['players'];self.assertEqual(data[0]['health'],19);self.assertTrue(data[0]['online']);self.assertFalse(data[1]['online'])
   for call in (base/'calls').read_text().splitlines():self.assertTrue(call in {'minecraft','list'} or call.startswith('data get entity PlayerOne '),call)
   (base/'calls').unlink();result=subprocess.run(['bash',str(ROOT/'nik.sh'),'--config',str(base/'config'),'--podglad','stan','g1'],env=env,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr);self.assertFalse((base/'calls').exists())
if __name__=='__main__':unittest.main()
