"""Exercise real archive/restore code against isolated fake Docker volumes."""
import hashlib,json,os,subprocess,sys,tarfile,tempfile,unittest,io
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
FAKE=r'''#!/usr/bin/env python3
import sys,os,json,subprocess
from pathlib import Path
a=sys.argv[1:];base=Path(os.environ['FIXTURE']);state=base/'running';calls=base/'calls'
with calls.open('a') as f:f.write(json.dumps(a[:2])+'\n')
if a[0]=='inspect':print(json.dumps([{'Image':'sha256:test','State':{'Running':state.read_text()=='yes','Status':'running' if state.read_text()=='yes' else 'exited'},'Mounts':[{'Destination':'/data','RW':True}]}]))
elif a[0]=='stop':state.write_text('no')
elif a[0]=='start':state.write_text('yes')
elif a[0]=='run':
 code=a[a.index('-c')+1].replace("Path('/data')",repr(str(base/'data')))
 code=code.replace('root='+repr(str(base/'data')), 'root=Path('+repr(str(base/'data'))+')')
 action=a[-1]
 if os.environ.get('FAIL_ARCHIVE') and action=='archive':sys.exit(9)
 if os.environ.get('FAIL_RESTORE_ONCE') and action=='restore' and not (base/'failed').exists():
  (base/'failed').touch();sys.exit(9)
 sys.exit(subprocess.run([sys.executable,'-c',code,action]).returncode)
else:sys.exit(8)
'''
class WorldBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.base=Path(self.temp.name)
        (self.base/'data/world/region').mkdir(parents=True)
        (self.base/'data/server.properties').write_text('level-name=world\n')
        (self.base/'data/world/level.dat').write_bytes(b'level-original')
        (self.base/'data/world/region/r.0.0.mca').write_bytes(b'original')
        (self.base/'running').write_text('yes')
        (self.base/'bin').mkdir();fake=self.base/'bin/docker';fake.write_text(FAKE);fake.chmod(0o700)
        self.env={**os.environ,'FIXTURE':str(self.base),'PATH':str(self.base/'bin')+':'+os.environ['PATH']}
        self.backups=self.base/'backups'
    def tearDown(self):self.temp.cleanup()
    def run_cli(self,*args,success=True):
        result=subprocess.run([sys.executable,str(ROOT/'tools/world-backup.py'),'--root',str(self.backups),'--container','minecraft',*args],env=self.env,capture_output=True,text=True)
        if success:self.assertEqual(result.returncode,0,result.stderr)
        else:self.assertNotEqual(result.returncode,0)
        return result
    def snapshot(self):
        self.run_cli('utworz');return sorted(self.backups.glob('*.json'))[-1].stem
    def test_snapshot_contains_world_and_restarts(self):
        ident=self.snapshot()
        with tarfile.open(self.backups/(ident+'.tar.gz')) as src:self.assertEqual(src.extractfile('world/level.dat').read(),b'level-original')
        self.assertEqual((self.base/'running').read_text(),'yes')
        self.assertEqual((self.backups/(ident+'.tar.gz')).stat().st_mode&0o777,0o600)
    def test_restore_replaces_world_and_preserves_previous_state(self):
        ident=self.snapshot();world=self.base/'data/world'
        (world/'level.dat').write_bytes(b'new');(world/'extra.dat').write_text('remove')
        self.run_cli('przywroc',ident)
        self.assertEqual((world/'level.dat').read_bytes(),b'level-original');self.assertFalse((world/'extra.dat').exists())
        archives=list(self.backups.glob('*.tar.gz'));self.assertEqual(len(archives),2)
        before=next(p for p in archives if p.stem!=ident+'.tar')
        with tarfile.open(before) as src:self.assertEqual(src.extractfile('world/level.dat').read(),b'new')
        self.assertEqual((self.base/'running').read_text(),'yes')
    def test_corrupt_archive_rejected_before_stop(self):
        ident=self.snapshot();(self.backups/(ident+'.tar.gz')).write_bytes(b'bad');(self.base/'calls').unlink()
        self.run_cli('przywroc',ident,success=False)
        self.assertNotIn('stop',(self.base/'calls').read_text())
    def test_archive_failure_restarts_and_removes_pending(self):
        self.env['FAIL_ARCHIVE']='1';self.run_cli('utworz',success=False)
        self.assertEqual((self.base/'running').read_text(),'yes');self.assertFalse(list(self.backups.glob('*.pending')))
    def test_restore_failure_restores_preoperation_snapshot(self):
        ident=self.snapshot();(self.base/'data/world/level.dat').write_bytes(b'new')
        self.env['FAIL_RESTORE_ONCE']='1';self.run_cli('przywroc',ident,success=False)
        self.assertEqual((self.base/'data/world/level.dat').read_bytes(),b'new');self.assertEqual((self.base/'running').read_text(),'yes')
    def test_stopped_container_stays_stopped(self):
        (self.base/'running').write_text('no');self.snapshot();self.assertEqual((self.base/'running').read_text(),'no')
    def test_dry_run_never_stops_or_creates_archive(self):
        self.run_cli('--dry-run','utworz');self.assertFalse(self.backups.exists());self.assertFalse((self.base/'calls').exists())
    def test_restore_preview_verifies_archive_without_docker(self):
        ident=self.snapshot();(self.base/'calls').unlink()
        self.run_cli('--dry-run','przywroc',ident)
        self.assertFalse((self.base/'calls').exists())
        self.assertEqual((self.base/'data/world/level.dat').read_bytes(),b'level-original')
    def test_list_needs_no_docker(self):
        result=self.run_cli('lista');self.assertIn('KOPIE',result.stdout);self.assertFalse((self.base/'calls').exists())
    def test_rejects_symlink_in_world(self):
        (self.base/'data/world/link').symlink_to(self.base/'running');self.run_cli('utworz',success=False)
        self.assertEqual((self.base/'running').read_text(),'yes')
    def test_rejects_path_traversal_before_stopping(self):
        ident=self.snapshot();path=self.backups/(ident+'.tar.gz')
        with tarfile.open(path,'w:gz') as out:
            info=tarfile.TarInfo('../escape');info.size=1;out.addfile(info,io.BytesIO(b'x'))
        manifest=self.backups/(ident+'.json');meta=json.loads(manifest.read_text());meta['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();manifest.write_text(json.dumps(meta))
        (self.base/'calls').unlink();self.run_cli('przywroc',ident,success=False);self.assertNotIn('stop',(self.base/'calls').read_text())
    def test_preserves_separate_dimension_worlds(self):
        (self.base/'data/world_nether').mkdir();(self.base/'data/world_nether/level.dat').write_bytes(b'nether')
        ident=self.snapshot();self.run_cli('przywroc',ident)
        self.assertEqual((self.base/'data/world_nether/level.dat').read_bytes(),b'nether')
if __name__=='__main__':unittest.main()
