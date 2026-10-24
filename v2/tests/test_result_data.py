"""Private result channel rejects symlinks and invalid file types."""
import os,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from result_data import write_result
class ResultDataTests(unittest.TestCase):
 def test_private_file_under_permissive_umask(self):
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'result.json';mask=os.umask(0)
   try:
    with patch.dict(os.environ,{'NIK_RESULT_PATH':str(path)}):write_result({'value':'♥'})
   finally:os.umask(mask)
   self.assertEqual(path.stat().st_mode&0o777,0o600);self.assertIn('♥',path.read_text())
 def test_symlink_and_relative_path_are_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   outside=Path(tmp)/'outside';outside.write_text('unchanged');link=Path(tmp)/'link';link.symlink_to(outside)
   for target in [str(link),'relative.json']:
    with patch.dict(os.environ,{'NIK_RESULT_PATH':target}),self.assertRaises((OSError,AssertionError)):write_result({'bad':True})
   self.assertEqual(outside.read_text(),'unchanged')
 def test_named_pipe_is_rejected_without_blocking(self):
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'pipe';os.mkfifo(path)
   with patch.dict(os.environ,{'NIK_RESULT_PATH':str(path)}),self.assertRaises(OSError):write_result({})
if __name__=='__main__':unittest.main()
