"""SNBT inventory parsing with nested components, malicious input and legacy forms."""
import importlib.util,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('inventory',ROOT/'tools/inventory.py');inventory=importlib.util.module_from_spec(spec);spec.loader.exec_module(inventory)
class InventoryTests(unittest.TestCase):
    def rows(self,content):return inventory.inventory_rows('PlayerOne has the following entity data: '+content)
    def test_modern_items_and_enchantments(self):
        rows=self.rows('[{Slot:0b,id:"minecraft:diamond_sword",count:1,components:{"minecraft:enchantments":{"minecraft:sharpness":5,"minecraft:mending":1}}},{Slot:9b,id:"minecraft:torch",count:64}]')
        self.assertEqual(rows[0],('pasek 1','diamentowy_miecz',1,'ostrosc: 5, naprawa: 1'))
        self.assertEqual(rows[1],('plecak 1','pochodnia',64,''))
    def test_nested_components_and_typed_arrays_do_not_confuse_item_boundaries(self):
        rows=self.rows('''[{Slot:2b,id:"minecraft:stone",count:32,components:{"minecraft:custom_data":{values:[I;1,2,-3],longs:[L;1L],bytes:[B;1b],text:'single "quoted", } text',nested:[{a:1}]}}}]''')
        self.assertEqual(rows,[('pasek 3','kamien',32,'')])
    def test_legacy_counts_signed_offhand_slot_and_wrapped_items(self):
        rows=self.rows('[{Slot:-106b,id:"minecraft:shield",Count:1b},{Slot:100b,item:{id:"minecraft:diamond_boots",count:1}}]')
        self.assertEqual(rows[0][0],'buty');self.assertEqual(rows[1][0],'druga ręka')
    def test_empty_list_and_sorted_slots(self):
        self.assertEqual(self.rows('[]'),[])
        rows=self.rows('[{Slot:35b,id:"minecraft:torch",count:1},{Slot:0b,id:"minecraft:stone",count:1}]')
        self.assertEqual([r[0] for r in rows],['pasek 1','plecak 27'])
    def test_unknown_modded_item_is_readable_without_losing_namespace(self):
        self.assertEqual(self.rows('[{Slot:0b,id:"example:thing",count:1}]')[0][1],'example:thing')
    def test_legacy_enchantment_levels_and_stored_books(self):
        rows=self.rows('[{Slot:0b,id:"minecraft:enchanted_book",count:1,components:{"minecraft:stored_enchantments":{levels:{"minecraft:mending":1}}}}]')
        self.assertEqual(rows[0][3],'naprawa: 1')
    def test_rejects_truncated_reply_commands_duplicate_slots_and_bad_counts(self):
        for content in ['[{Slot:0b,id:', '[] run kill @a','[{Slot:0b,id:"minecraft:stone",count:0}]','[{Slot:99b,id:"minecraft:stone",count:1}]','[{Slot:0b,id:"minecraft:stone",count:1},{Slot:0b,id:"minecraft:stone",count:1}]']:
            with self.subTest(content=content),self.assertRaises(AssertionError):self.rows(content)
    def test_rejects_duplicate_keys_and_excessive_nesting(self):
        with self.assertRaises(AssertionError):inventory.Snbt('{a:1,a:2}').parse()
        with self.assertRaises(AssertionError):inventory.Snbt('['*66+'0'+']'*66).parse()
    def test_unicode_and_quoted_backslashes_are_parsed_without_eval(self):
        node=inventory.Snbt(r'''{text:"Franek \u2665",literal:"\\",single:'it\'s fine'}''').parse()
        self.assertEqual(node,{'text':'Franek ♥','literal':'\\','single':"it's fine"})
class InventoryPlanTests(unittest.TestCase):
    prefix='PlayerOne has the following entity data: '
    def test_complete_response_needs_only_one_read(self):
        self.assertEqual(inventory.inventory_plan({'Inventory':self.prefix+'[]'},'Inventory'),[])
    def test_requests_root_before_any_fields(self):
        with self.assertRaises(inventory.NeedQuery) as query:inventory.inventory_plan({},'Inventory')
        self.assertEqual(query.exception.path,'Inventory')
    def test_truncated_items_and_enchantments_are_reassembled(self):
        root='Inventory[0]';comp=root+'.components."minecraft:enchantments"'
        replies={'Inventory':self.prefix+'[{Slot:0b,...',root:self.prefix+'{Slot:0b,...',root+'.Slot':self.prefix+'0b',root+'.id':self.prefix+'"minecraft:diamond_sword"',root+'.count':self.prefix+'1',comp:self.prefix+'{"minecraft:sharpness":5,...',comp+'.levels':'Found no elements matching '+comp+'.levels',root+'.components."minecraft:stored_enchantments"':'Found no elements matching '+root+'.components."minecraft:stored_enchantments"','Inventory[1]':'Found no elements matching Inventory[1]'}
        for line in (ROOT/'data/enchantment-names.tsv').read_text().splitlines():
            id=line.split('\t')[1];path=comp+'."minecraft:'+id+'"'
            replies[path]=self.prefix+'5' if id=='sharpness' else 'Found no elements matching '+path
        rows=inventory.inventory_plan(replies,'Inventory')
        self.assertEqual(rows,[('pasek 1','diamentowy_miecz',1,'ostrosc: 5')])
    def test_truncated_list_can_have_complete_entries(self):
        replies={'EnderItems':self.prefix+'[{Slot:0b,...','EnderItems[0]':self.prefix+'{Slot:0b,id:"minecraft:stone",count:64}','EnderItems[1]':'Found no elements matching EnderItems[1]'}
        self.assertEqual(inventory.inventory_plan(replies,'EnderItems'),[('slot 1','kamien',64,'')])
    def test_truncated_held_item_reads_only_id_and_damage(self):
        replies={'SelectedItem':self.prefix+'{components:...', 'SelectedItem.id':self.prefix+'"minecraft:diamond_sword"','SelectedItem.components."minecraft:damage"':self.prefix+'123'}
        self.assertEqual(inventory.inventory_plan(replies,'SelectedItem'),123)
    def test_undamaged_held_item_and_missing_damage(self):
        self.assertEqual(inventory.inventory_plan({'SelectedItem':self.prefix+'{id:"minecraft:dirt",count:3}'},'SelectedItem'),0)
        replies={'SelectedItem':self.prefix+'{components:...', 'SelectedItem.id':self.prefix+'"minecraft:diamond_sword"','SelectedItem.components."minecraft:damage"':'Found no elements matching SelectedItem.components."minecraft:damage"'}
        self.assertEqual(inventory.inventory_plan(replies,'SelectedItem'),0)
    def test_invalid_reply_is_not_treated_as_truncation(self):
        with self.assertRaises(AssertionError):inventory.inventory_plan({'Inventory':self.prefix+'[{Slot:'},'Inventory')
    def test_offline_reply_is_never_an_empty_inventory(self):
        with self.assertRaises(AssertionError):inventory.inventory_plan({'Inventory':'No entity was found'},'Inventory')
if __name__=='__main__':unittest.main()
