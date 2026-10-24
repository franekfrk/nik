"""Task book content, private state validation, repairs and Ender inventory."""
import importlib.util,json,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
 s=importlib.util.spec_from_file_location(name,ROOT/'tools'/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
family=module('family','family-state.py');inventory=module('inventory24','inventory.py')
class FamilyTests(unittest.TestCase):
 def task(self):return {'schema':1,'player':'PlayerOne','container':'minecraft','text':'Zbuduj latarnię ♥','status':'aktywne'}
 def test_task_identity_and_text_validation(self):
  t=self.task();self.assertEqual(family.task(t,'PlayerOne','minecraft'),t)
  for player,container in [('PlayerTwo','minecraft'),('PlayerOne','other')]:
   with self.assertRaises(AssertionError):family.task(t,player,container)
  for bad in ['', '  ', 'x'*513, 'x\ny','\x1b[31m']:
   with self.assertRaises(AssertionError):family.text(bad)
 def test_book_uses_literal_component_without_actions(self):
  t=self.task();t['text']='@a {"clickEvent":{"action":"run_command"}}'
  payload=json.loads(family.book(t).split('=',1)[1][:-1]);self.assertEqual(payload['author'],'Tata')
  for page in payload['pages']:
   self.assertEqual(set(page),{'text','color','bold','extra'})
   self.assertEqual(set(page['extra'][0]),{'text','color','bold'})
 def test_long_tasks_are_paginated_into_readable_book_pages(self):
  t=self.task();t['text']='Franek buduje latarnie i zamek. '*16
  self.assertLessEqual(len(t['text']),512)
  payload=json.loads(family.book(t).split('=',1)[1][:-1]);self.assertGreater(len(payload['pages']),1)
  for page in payload['pages']:
   lines=page['extra'][0]['text'].splitlines();self.assertLessEqual(len(lines),9)
   self.assertTrue(all(len(line)<=18 for line in lines))
 def test_rules_capture_retains_nondefault_originals(self):
  values=['false','-1','true','false'];replies=[f'Game rule {k} is currently set to {v}' for k,v in zip(family.RULES,values)]
  record=family.capture_rules('minecraft',replies);self.assertEqual(list(record['values'].values()),values)
 def test_rules_capture_rejects_unknown_or_injected_values(self):
  for bad in ['Game rule mob_griefing is currently set to true run kill @a','Unknown or incomplete command']:
   with self.assertRaises(AssertionError):family.capture_rules('minecraft',[bad]*4)
 def test_private_state_loader_rejects_symlinks_and_oversized_files(self):
  with tempfile.TemporaryDirectory() as directory:
   p=Path(directory)/'task';p.write_text(json.dumps(self.task()));link=Path(directory)/'link';link.symlink_to(p)
   with self.assertRaises(AssertionError):family.load(link)
   p.write_text('x'*8193)
   with self.assertRaises(AssertionError):family.load(p)
 def test_ender_slot_labels_are_independent_of_hotbar_and_reject_equipment(self):
  wrap=lambda v:'PlayerOne has the following entity data: '+v
  rows=inventory.inventory_rows(wrap('[{Slot:0b,id:"minecraft:diamond",count:4},{Slot:26b,id:"minecraft:torch",count:64}]'),ender=True)
  self.assertEqual([r[0] for r in rows],['slot 1','slot 27'])
  with self.assertRaises(AssertionError):inventory.inventory_rows(wrap('[{Slot:100b,id:"minecraft:diamond_boots",count:1}]'),ender=True)
if __name__=='__main__':unittest.main()
