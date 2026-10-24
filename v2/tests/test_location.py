"""Verify untrusted RCON text and stored coordinates never become commands."""
import importlib.util,json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
location=module('location','location.py');dad=module('dad_message','dad-message.py')
class LocationTests(unittest.TestCase):
    def capture(self,pos='[12.5d, 64.0d, -9.25d]',dimension='"minecraft:the_end"',rotation='[45.5f, -12.0f]'):
        wrap=lambda s:'PlayerOne has the following entity data: '+s
        return location.capture('PlayerOne','minecraft',wrap(pos),wrap(dimension),wrap(rotation))
    def test_round_trip_preserves_dimension_rotation_and_negative_values(self):
        record=self.capture();self.assertEqual(location.validate(record,'PlayerOne','minecraft'),['12.5','64','-9.25','minecraft:the_end','45.5','-12'])
    def test_exponents_high_precision_and_negative_zero_are_canonical(self):
        record=self.capture('[1.23456789d, -0.0d, -1.25E3d]')
        self.assertEqual(record['position'],['1.234568','0','-1250'])
    def test_rejects_wrong_vector_length_nonfinite_and_commands(self):
        for text in ['[1d,2d]','[NaNd,2d,3d]','[Infinityd,2d,3d]','[1d,2d,3d] run kill @a','[1e999d,2d,3d]','[30000001d,2d,3d]']:
            with self.subTest(text=text),self.assertRaises((AssertionError,ValueError)):self.capture(text)
    def test_rejects_unrecognized_rcon_reply_and_multiline_data(self):
        for reply in ['No entity was found','OK','PlayerOne has the following entity data: [1d,2d,3d]\nInjected']:
            with self.subTest(reply=reply),self.assertRaises(AssertionError):location.vector(reply,3,30000000)
    def test_rejects_invalid_dimensions_rotation_and_mismatched_identity(self):
        with self.assertRaises(AssertionError):self.capture(dimension='"minecraft:the_end run kill @a"')
        with self.assertRaises(AssertionError):self.capture(rotation='[45f,91f]')
        record=self.capture()
        for player,container in [('PlayerTwo','minecraft'),('PlayerOne','other')]:
            with self.assertRaises(AssertionError):location.validate(record,player,container)
    def test_only_literal_text_component_can_contain_message_input(self):
        text='Cześć "Franek"! @a {"clickEvent":{"action":"run_command"}} \\ ♥'
        parts=json.loads(dad.component(text));self.assertEqual(parts[2]['text'],text)
        self.assertEqual(set(parts[2]),{'text','color','bold'});self.assertTrue(parts[1]['bold']);self.assertFalse(parts[2]['bold'])
    def test_rejects_empty_controls_surrogates_and_oversized_messages(self):
        for text in ['', '  ','hello\nworld','escape\x1b[31m','\x00','\ud800','a'*513]:
            with self.subTest(text=repr(text)),self.assertRaises(AssertionError):dad.component(text)
        self.assertEqual(json.loads(dad.component('a'*512))[2]['text'],'a'*512)
if __name__=='__main__':unittest.main()
