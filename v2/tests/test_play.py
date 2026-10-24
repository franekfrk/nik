import importlib.util,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('nik_play',ROOT/'tools/play.py');play=importlib.util.module_from_spec(spec);spec.loader.exec_module(play)

class PlayTests(unittest.TestCase):
    def record(self,x=0,y=64,z=0,yaw=0,dimension='minecraft:overworld'):
        return {'position':[str(x),str(y),str(z)],'rotation':[str(yaw),'0'],'dimension':dimension}
    def test_cardinals_and_rotation(self):
        for x,z,yaw,label in [(0,10,0,'przed Tobą'),(-10,0,0,'po prawej'),(10,0,0,'po lewej'),(0,-10,0,'za Tobą'),(-10,0,90,'przed Tobą')]:
            with self.subTest(x=x,z=z,yaw=yaw):self.assertIn(label,play.guidance(self.record(yaw=yaw),(x,64,z,'minecraft:overworld'))[0])
    def test_diagonal(self):self.assertIn('z przodu po prawej',play.guidance(self.record(),(-10,64,10,'minecraft:overworld'))[0])
    def test_near_and_height(self):
        text,near=play.guidance(self.record(),(1,100,1,'minecraft:overworld'));self.assertTrue(near);self.assertIn('+36',text)
    def test_dimension_mismatch(self):
        with self.assertRaises(AssertionError):play.guidance(self.record(),(0,64,0,'minecraft:the_nether'))
    def test_custom_challenges_and_bad_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'list';p.write_text('# opis\nZbuduj most ♥\n\nZnajdź ametyst\n');self.assertEqual(len(play.challenges(p)),2)
            for text in ['', 'x'*513, 'ABC\x1b[31m']:
                p.write_text(text)
                with self.assertRaises(AssertionError):play.challenges(p)
    def test_reward_validation_before_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'reward';p.write_text('diamond\t3\ntorch\t64\n');self.assertEqual(play.rewards(p,{'diamond','torch'}),[('diamond',3),('torch',64)])
            for text in ['diamond\t0','unknown\t1','diamond\t1\textra','diamond\t2305','diamond\t١']:
                p.write_text(text)
                with self.assertRaises(AssertionError):play.rewards(p,{'diamond'})
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'file';p.write_text('Challenge');link=Path(tmp)/'link';link.symlink_to(p)
            with self.assertRaises(AssertionError):play.challenges(link)
    def test_literal_no_components_or_commands(self):
        self.assertEqual(play.literal('{"click_event": "test"}'),'{"click_event": "test"}')
        with self.assertRaises(AssertionError):play.literal('Hello\nworld')
    def test_all_vanilla_recipes_render(self):
        data=json.loads((ROOT/'data/recipes.json').read_text());self.assertEqual(data['version'],'26.3');self.assertEqual(len(data['recipes']),2042)
        ids=set()
        for recipe in data['recipes'].values():
            result=recipe.get('result',{})
            if isinstance(result,dict) and 'id' in result:ids.add(result['id'].removeprefix('minecraft:'))
        for item in ids:
            with self.subTest(item=item):self.assertTrue(play.recipe_lines(data,item,{}))
    def test_torch_grid_and_count(self):
        data=json.loads((ROOT/'data/recipes.json').read_text());text='\n'.join(play.recipe_lines(data,'torch',{'stick':'patyk','coal':'wegiel','charcoal':'wegiel_drzewny'}))
        self.assertIn('wynik: 4 szt.',text);self.assertIn('patyk',text);self.assertIn('wegiel / wegiel_drzewny',text)
    def test_no_fixed_recipe(self):
        data=json.loads((ROOT/'data/recipes.json').read_text());self.assertIn('Brak stałej receptury',play.recipe_lines(data,'dragon_egg',{})[0])

if __name__=='__main__':unittest.main()
