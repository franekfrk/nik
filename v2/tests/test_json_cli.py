"""Exercise the real NIK JSON API and graphical inventory with isolated Docker."""
import json,os,shutil,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
if sys.argv[1]=='inspect':print('true');sys.exit(0)
command=sys.argv[-1];case=os.environ.get('NIK_TEST_CASE','normal')
with (Path(os.environ['NIK_TEST_DIR'])/'calls').open('a') as out:out.write(command+'\n')
if case=='fail_give' and command.startswith('give '):print('Unknown or incomplete command');sys.exit(0)
if command.startswith('data get entity '):
 if os.environ.get('NIK_TEST_DELAY'):__import__('time').sleep(float(os.environ['NIK_TEST_DELAY']))
 field=command.split(' ',4)[4]
 prefix='PlayerOne has the following entity data: '
 if case=='offline':print('No entity was found');sys.exit(0)
 sword={'Slot':0,'id':'minecraft:diamond_sword','count':1,'components':{'minecraft:damage':161,'minecraft:max_damage':1000,'minecraft:enchantments':{'minecraft:sharpness':5,'minecraft:mending':1}}}
 torch={'Slot':9,'id':'minecraft:torch','count':64}
 helmet={'id':'minecraft:golden_helmet','count':1,'components':{'minecraft:damage':3}}
 values={'Inventory':[] if case=='empty' else [sword,torch],'EnderItems':[],'Inventory[0]':sword,'Inventory[1]':torch}
 if case!='empty':values['equipment.head']=helmet
 if field=='Inventory' and (case=='changing_always' or (case=='changing_once' and (Path(os.environ['NIK_TEST_DIR'])/'calls').read_text().splitlines().count(command)==1)):values[field]=[sword,sword]
 if case in {'truncated','truncated_item'}:
  if field=='Inventory' or (case=='truncated_item' and field=='Inventory[0]'):print(prefix+'[{Slot:0b,...');sys.exit(0)
 if field.startswith('Inventory[0].'):
  key=field.removeprefix('Inventory[0].')
  values[field]={'Slot':0,'id':sword['id'],'count':1,'components."minecraft:damage"':161,'components."minecraft:max_damage"':1000,'components."minecraft:enchantments"':sword['components']['minecraft:enchantments']}.get(key)
 if values.get(field) is None:print('Found no elements matching '+field)
 else:print(prefix+json.dumps(values[field]))
elif command.startswith('tellraw '):pass
else:print('Command completed successfully')
'''
class Fixture:
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name);self.cfg=self.base/'config';shutil.copytree(ROOT/'config.example',self.cfg);(self.base/'bin').mkdir();docker=self.base/'bin/docker';docker.write_text(FAKE);docker.chmod(0o700)
  with (self.cfg/'config.env').open('a') as out:out.write('LOG='+str(self.base/'nik.log')+'\n')
  self.env={**os.environ,'NIK_TEST_DIR':str(self.base),'NIK_STATE':str(self.base/'state'),'PATH':str(self.base/'bin')+os.pathsep+os.environ['PATH']}
 def tearDown(self):self.tmp.cleanup()
 def run_nik(self,*args):return subprocess.run(['bash',str(ROOT/'nik.sh'),'--config',str(self.cfg),*args],env=self.env,capture_output=True,text=True,timeout=30)
class JsonTests(Fixture,unittest.TestCase):
 def test_json_envelope_preserves_validation_error_and_never_calls_docker(self):
  result=self.run_nik('--json','daj','g1','diament','x');value=json.loads(result.stdout);self.assertEqual(result.returncode,2);self.assertEqual(value['code'],2);self.assertFalse(value['ok']);self.assertIn('NIK:',value['output']);self.assertFalse((self.base/'calls').exists())
 def test_help_version_and_dry_run_are_wrapped_without_changing_shell(self):
  for args in [('--wersja',),('--pomoc',),('--podglad','zdrowie','g1')]:
   result=self.run_nik('--json',*args);self.assertEqual(result.returncode,0,result.stderr);data=json.loads(result.stdout);self.assertTrue(data['ok']);self.assertEqual(data['schema'],1)
  self.assertFalse((self.base/'calls').exists())
 def test_inventory_has_real_slots_enchantments_equipment_and_component_durability(self):
  result=self.run_nik('--json','plecak','g1');self.assertEqual(result.returncode,0,result.stdout+result.stderr);data=json.loads(result.stdout)['result'];self.assertEqual(data['type'],'inventory');items={r['slot']:r for r in data['slots']}
  self.assertEqual(set(items),{0,9,103});self.assertEqual(items[0]['id'],'minecraft:diamond_sword');self.assertEqual(items[0]['remaining'],839);self.assertEqual(items[0]['durability_source'],'component');self.assertEqual(items[0]['enchantments'][0]['name'],'ostrosc');self.assertEqual(items[9]['count'],64);self.assertIsNone(items[9]['max_damage']);self.assertEqual(items[103]['max_damage'],77)
  self.assertTrue(all(c.startswith('data get entity ') for c in (self.base/'calls').read_text().splitlines()))
 def test_truncated_inventory_preserves_wear_and_equipment(self):
  for case in ['truncated','truncated_item']:
   self.env['NIK_TEST_CASE']=case;result=self.run_nik('--json','plecak','g1');self.assertEqual(result.returncode,0,result.stdout+result.stderr);sword=next(r for r in json.loads(result.stdout)['result']['slots'] if r['slot']==0);self.assertEqual(sword['damage'],161);self.assertEqual(sword['max_damage'],1000);self.assertEqual(len(sword['enchantments']),2)
 def test_offline_is_an_error_and_empty_is_a_valid_empty_inventory(self):
  self.env['NIK_TEST_CASE']='offline';result=self.run_nik('--json','plecak','g1');data=json.loads(result.stdout);self.assertFalse(data['ok']);self.assertEqual(data['result']['kind'],'player_offline')
  self.env['NIK_TEST_CASE']='empty';result=self.run_nik('--json','plecak','g1');self.assertEqual(result.returncode,0,result.stdout);self.assertEqual(json.loads(result.stdout)['result']['slots'],[])
 def test_jsonl_has_live_progress_output_and_one_final_result(self):
  result=self.run_nik('--jsonl','plecak','g1');events=[json.loads(line) for line in result.stdout.splitlines()];self.assertEqual(events[-1]['type'],'result');self.assertEqual(sum(e['type']=='result' for e in events),1);self.assertTrue(any(e['type']=='progress' for e in events));self.assertTrue(any(e['type']=='output' for e in events));self.assertEqual(events[-1]['data']['code'],result.returncode)
 def test_ender_json_is_a_27_slot_container(self):
  result=self.run_nik('--json','ender','g1');self.assertEqual(result.returncode,0,result.stdout);data=json.loads(result.stdout)['result'];self.assertEqual(data['kind'],'ender');self.assertEqual(data['capacity'],27);self.assertEqual(data['slots'],[])
 def test_changing_inventory_requests_retry_instead_of_returning_duplicate_slots(self):
  state={'Inventory':'Player has the following entity data: [{Slot:0b,id:"minecraft:stone"},{Slot:0b,id:"minecraft:torch"}]'}
  result=subprocess.run(['python3',str(ROOT/'tools/inventory.py'),'--plan','Inventory'],input=json.dumps(state),env=self.env,capture_output=True,text=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout.strip(),'RETRY')
 def test_changed_inventory_retries_once_then_succeeds(self):
  self.env['NIK_TEST_CASE']='changing_once';result=self.run_nik('--json','plecak','g1');self.assertEqual(result.returncode,0,result.stdout);self.assertEqual(len(json.loads(result.stdout)['result']['slots']),3)
 def test_continuously_changing_inventory_stops_without_partial_result(self):
  self.env['NIK_TEST_CASE']='changing_always';result=self.run_nik('--json','plecak','g1');data=json.loads(result.stdout);self.assertEqual(result.returncode,2);self.assertIsNone(data['result']);self.assertIn('bez przekładania',data['output'])
 def test_game_error_has_a_polish_typed_message_and_original_details(self):
  self.env['NIK_TEST_CASE']='fail_give';result=self.run_nik('--json','daj','g1','diament','1');data=json.loads(result.stdout);self.assertNotEqual(result.returncode,0);self.assertEqual(data['result']['kind'],'unsupported_command');self.assertIn('Serwer nie rozpoznaje',data['result']['message']);self.assertIn('Unknown or incomplete command',data['result']['details'])
 def test_literal_shell_text_is_not_executed(self):
  marker=self.base/'MUST_NOT_EXIST';result=self.run_nik('--json','tata','g1','$(touch '+str(marker)+')');self.assertEqual(result.returncode,0,result.stdout);self.assertFalse(marker.exists());self.assertTrue(json.loads(result.stdout)['ok'])
if __name__=='__main__':unittest.main()
