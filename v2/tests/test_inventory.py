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
if __name__=='__main__':unittest.main()
