"""Use real ZIP packaging with synthetic private configuration and poison files."""
import json,os,shutil,subprocess,tempfile,unittest,uuid,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name);self.root=self.base/'source'
        self.root.mkdir()
        # Never copy the installed root: it may hold real config/backups/logs.
        for relative in json.loads((ROOT/'tools/public-files.json').read_text()):
            target=self.root/relative;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/relative,target)
        self.out=self.base/'out';self.marker='PRIVATE_TEST_'+uuid.uuid4().hex
    def package(self,*args):
        return subprocess.run(['python3',str(self.root/'tools/package.py'),'--out',str(self.out),*map(str,args)],text=True,capture_output=True)
    def manifest_add(self,path):
        p=self.root/'tools/public-files.json';values=json.loads(p.read_text());values.append(path);p.write_text(json.dumps(values))
    def test_private_data_only_in_private_zip(self):
        config=self.root/'config';config.mkdir(exist_ok=True)
        (config/'config.env').write_text(self.marker)
        for directory in ['state','world-backups','backups','logs','lib','data','tools']:
            target=self.root/directory;target.mkdir(exist_ok=True);(target/'accidental-secret.txt').write_text(self.marker)
        result=self.package('--private-config',config);self.assertEqual(result.returncode,0,result.stderr)
        with zipfile.ZipFile(self.out/'nik-v2-public.zip') as archive:
            self.assertFalse(any(self.marker.encode() in archive.read(n) for n in archive.namelist()))
            self.assertNotIn('nik-v2-public/config/config.env',archive.namelist())
        with zipfile.ZipFile(self.out/'nik-v2-private.zip') as archive:self.assertEqual(archive.read('nik-v2-private/config/config.env').decode(),self.marker)
        self.assertEqual((self.out/'nik-v2-private.zip').stat().st_mode&0o777,0o600)
    def test_manifest_rejects_config_and_private_directories(self):
        for relative in ['config/config.env','state/private.json','logs/private.txt','backups/private.txt']:
            with self.subTest(relative=relative):
                manifest=self.root/'tools/public-files.json';before=manifest.read_text()
                path=self.root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(self.marker)
                self.manifest_add(relative);self.assertNotEqual(self.package().returncode,0);manifest.write_text(before)
    def test_manifest_rejects_traversal_absolute_duplicate_and_missing(self):
        for path in ['../outside','/tmp/outside','lib/../tools/package.py','nik.sh','lib/not-present.sh']:
            with self.subTest(path=path):
                manifest=self.root/'tools/public-files.json';before=manifest.read_text();self.manifest_add(path)
                self.assertNotEqual(self.package().returncode,0);manifest.write_text(before)
    def test_symlink_file_or_ancestor_cannot_enter_zip(self):
        outside=self.base/'outside';outside.mkdir();(outside/'secret.txt').write_text(self.marker)
        link=self.root/'lib'/'linked';link.symlink_to(outside,target_is_directory=True)
        self.manifest_add('lib/linked/secret.txt');self.assertNotEqual(self.package().returncode,0)
    def test_missing_source_does_not_replace_old_archive(self):
        self.out.mkdir();archive=self.out/'nik-v2-public.zip';archive.write_bytes(b'previous archive')
        (self.root/'nik.sh').unlink();self.assertNotEqual(self.package().returncode,0);self.assertEqual(archive.read_bytes(),b'previous archive')
    def test_git_audit_rejects_tracked_private_files(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True,capture_output=True)
        config=self.root/'config';config.mkdir(exist_ok=True);(config/'password.env').write_text(self.marker)
        subprocess.run(['git','-C',str(self.root),'add','-f','config/password.env'],check=True,capture_output=True)
        result=subprocess.run(['python3',str(self.root/'tools/audit-project.py'),'--git'],text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0);self.assertIn('Prywatna ścieżka',result.stderr)
    def test_git_audit_requires_new_release_files_in_manifest(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True,capture_output=True)
        # Place the release under v2, as in the real repository.
        nested=self.base/'repository';nested.mkdir();subprocess.run(['git','init','-q',str(nested)],check=True,capture_output=True)
        tree=nested/'v2';shutil.copytree(self.root,tree,ignore=shutil.ignore_patterns('.git'))
        (tree/'lib/new-command.sh').write_text('# new command\n')
        subprocess.run(['git','-C',str(nested),'add','v2/lib/new-command.sh'],check=True,capture_output=True)
        result=subprocess.run(['python3',str(tree/'tools/audit-project.py'),'--git'],text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0);self.assertIn('poza manifestem',result.stderr)

if __name__=='__main__':unittest.main()
