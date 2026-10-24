"""Scenarios use the real NIK dispatcher, dry-run preflight and stop-on-error."""
import json,os,sys,unittest
from test_json_cli import Fixture
class ScenarioTests(Fixture,unittest.TestCase):
 def save(self,name,*steps):
  result=self.run_nik('scenariusz','zapisz',name,*steps);self.assertEqual(result.returncode,0,result.stdout+result.stderr);return self.cfg/'scenarios'/(name+'.json')
 def test_save_is_private_and_cli_and_json_list_use_same_definition(self):
  path=self.save('wyprawa','dzien','zdrowie {gracz}','daj {gracz} pochodnia 64');self.assertEqual(path.stat().st_mode&0o777,0o600);self.assertFalse((self.base/'calls').exists());result=self.run_nik('--json','scenariusz','dane');self.assertEqual(json.loads(result.stdout)['result']['scenarios'][0]['steps'][1],'zdrowie {gracz}')
 def test_invalid_last_step_prevents_saving_or_any_game_write(self):
  result=self.run_nik('scenariusz','zapisz','zle','dzien','daj {gracz} nieistniejacy_przedmiot');self.assertNotEqual(result.returncode,0);self.assertFalse((self.cfg/'scenarios/zle.json').exists());self.assertFalse((self.base/'calls').exists())
 def test_shell_commands_nested_plans_dangerous_commands_and_traversal_are_rejected(self):
  for name,step in [('zle','bash -c id'),('zle','scenariusz g1 zle'),('zle','restartmc'),('../escape','dzien'),('zle','zestaw zapisz a diament=3')]:
   result=self.run_nik('scenariusz','zapisz',name,step);self.assertNotEqual(result.returncode,0,result.stdout)
  self.assertFalse((self.base/'calls').exists())
 def test_dry_run_substitutes_player_and_does_not_mutate_game(self):
  self.save('wyprawa','zdrowie {gracz}','daj {gracz} pochodnia 64');result=self.run_nik('--json','--podglad','scenariusz','g1','wyprawa');self.assertEqual(result.returncode,0,result.stdout);data=json.loads(result.stdout);self.assertIn('give PlayerOne minecraft:torch 64',data['output']);self.assertEqual(data['result']['completed'],2);self.assertFalse((self.base/'calls').exists())
 def test_actual_failure_stops_remaining_steps_and_retains_completed_results(self):
  self.save('wyprawa','zdrowie {gracz}','daj {gracz} diament 1','noc');self.env['NIK_TEST_CASE']='fail_give';result=self.run_nik('--json','scenariusz','g1','wyprawa');self.assertNotEqual(result.returncode,0);data=json.loads(result.stdout);self.assertEqual(data['result']['completed'],1);self.assertEqual(len(data['result']['steps']),2);calls=(self.base/'calls').read_text();self.assertNotIn('time set night',calls)
 def test_edit_revalidates_current_configuration_before_any_step(self):
  path=self.save('wyprawa','dzien','daj {gracz} diament 1');data=json.loads(path.read_text());data['steps'][-1]='daj {gracz} nieistniejacy';path.write_text(json.dumps(data));result=self.run_nik('scenariusz','g1','wyprawa');self.assertNotEqual(result.returncode,0);self.assertFalse((self.base/'calls').exists())
 def test_symlink_is_rejected_without_overwriting_target(self):
  outside=self.base/'outside';outside.write_text('unchanged');(self.cfg/'scenarios').mkdir();(self.cfg/'scenarios/zle.json').symlink_to(outside);result=self.run_nik('scenariusz','zapisz','zle','dzien');self.assertNotEqual(result.returncode,0);self.assertEqual(outside.read_text(),'unchanged')
 def test_definition_length_and_step_limit_are_enforced(self):
  result=self.run_nik('scenariusz','zapisz','zle',*['dzien']*13);self.assertNotEqual(result.returncode,0);self.assertFalse((self.base/'calls').exists())
if __name__=='__main__':unittest.main()
