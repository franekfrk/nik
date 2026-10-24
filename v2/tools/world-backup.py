#!/usr/bin/env python3
"""Offline world snapshots via an isolated helper using the existing Docker image."""
import argparse,datetime,fcntl,hashlib,json,os,re,signal,subprocess,sys,tarfile,uuid
from pathlib import Path

# Executed inside the Minecraft image, without its entrypoint, network or secrets.
HELPER=r'''
import sys,os,json,re,tarfile,tempfile,shutil
from pathlib import Path
root=Path('/data');action=sys.argv[1]
props=(root/'server.properties').read_text()
names=[l.split('=',1)[1].strip() for l in props.splitlines() if l.startswith('level-name=')]
name=names[-1] if names else 'world'
assert re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_. -]{0,79}',name) and name not in {'.','..'}, 'Nieobsługiwane level-name'
allowed=[name,name+'_nether',name+'_the_end']
assert not (root/name).is_symlink() and (root/name/'level.dat').is_file(), 'Brak level.dat'
folders=[n for n in allowed if (root/n).is_dir()]
for n in allowed: assert not (root/n).is_symlink(), 'Świat jest dowiązaniem'
if action=='info': print(json.dumps({'world':name,'folders':folders}));sys.exit(0)
if action=='archive':
 for n in folders:
  for p in (root/n).rglob('*'): assert not p.is_symlink() and (p.is_file() or p.is_dir()), 'Niedozwolony typ pliku świata'
 with tarfile.open(fileobj=sys.stdout.buffer,mode='w|gz') as out:
  for n in folders:out.add(root/n,arcname=n,recursive=True)
 sys.exit(0)
assert action=='restore'
stage=Path(tempfile.mkdtemp(prefix='.nik-restore-',dir=root));old=stage/'old';new=stage/'new';old.mkdir();new.mkdir()
moved=[];installed=[];cleanup=False
try:
 with tarfile.open(fileobj=sys.stdin.buffer,mode='r|gz') as source:
  for m in source:
   parts=Path(m.name).parts
   assert parts and not Path(m.name).is_absolute() and '..' not in parts and parts[0] in allowed, 'Nieprawidłowa ścieżka w kopii'
   assert m.isfile() or m.isdir(), 'Dowiązanie lub plik specjalny w kopii'
   source.extract(m,new,filter='data')
 assert (new/name/'level.dat').is_file(), 'Brak level.dat w kopii'
 # data_filter strips archived uid/gid. Restore the current world's ownership
 # so the non-root Minecraft process can write after the helper exits.
 for folder in new.iterdir():
  owner=(root/folder.name).stat() if (root/folder.name).exists() else (root/name).stat()
  for p in [folder,*folder.rglob('*')]:os.chown(p,owner.st_uid,owner.st_gid)
 for n in allowed:
  if (root/n).exists():os.rename(root/n,old/n);moved.append(n)
 for n in allowed:
  if (new/n).exists():os.rename(new/n,root/n);installed.append(n)
 cleanup=True
except BaseException:
 for n in installed:shutil.rmtree(root/n)
 for n in moved:os.rename(old/n,root/n)
 cleanup=True
 raise
finally:
 if cleanup:shutil.rmtree(stage)
 else:print('Zachowano pliki odzyskiwania: '+str(stage),file=sys.stderr)
print('Przywrócono pliki świata.')
'''

def say(message,error=False):
    stream=sys.stderr if error else sys.stdout
    color=os.environ.get('NIK_COLOR','auto')
    enabled=color=='always' or (color!='never' and not os.environ.get('NO_COLOR') and stream.isatty())
    print(('\033[31m' if error else '\033[32m')+message+'\033[0m' if enabled else message,file=stream,flush=True)

class Backups:
    def __init__(self,args):self.args=args;self.root=args.root;self.info=None;self.stopped=False
    def docker(self,*args,timeout=None,**kwargs):
        return subprocess.run(['docker',*args],check=True,timeout=timeout or max(120,self.args.timeout),stderr=subprocess.PIPE,**kwargs)
    def inspect(self):
        self.info=json.loads(self.docker('inspect',self.args.container,stdout=subprocess.PIPE).stdout)[0]
        mounts=[m for m in self.info['Mounts'] if m['Destination']=='/data']
        assert len(mounts)==1 and mounts[0]['RW'], 'Wymagany zapisywalny wolumen /data'
        assert self.info['State']['Status'] in {'running','exited','created'}, 'Kontener zmienia stan; spróbuj później'
        self.running=self.info['State']['Running']
    def helper(self,action,**kwargs):
        readonly=':rw' if action=='restore' else ':ro'
        return self.docker('run','--rm','--pull','never','--network','none','--read-only','--user','0:0',
                           '--volumes-from',self.args.container+readonly,'--entrypoint','python3','-i',
                           self.info['Image'],'-c',HELPER,action,timeout=1800,**kwargs)
    def stop(self):
        # Mark recovery before requesting stop: a timed out stop can still have succeeded.
        if self.running:
            self.stopped=True;say('Zatrzymywanie serwera na czas kopii/przywracania…')
            self.docker('stop','--time','60',self.args.container,stdout=subprocess.PIPE)
        state=json.loads(self.docker('inspect',self.args.container,stdout=subprocess.PIPE).stdout)[0]
        assert not state['State']['Running'], 'Kontener nadal pracuje'
    def start(self):
        if self.running and self.stopped:
            self.docker('start',self.args.container,stdout=subprocess.PIPE)
            self.stopped=False;say('Kontener uruchomiony. Gotowość gry sprawdź: nik status.')
    def snapshot(self):
        world=json.loads(self.helper('info',stdout=subprocess.PIPE).stdout)
        ident=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
        archive=self.root/(ident+'.tar.gz');pending=self.root/(ident+'.pending')
        try:
            with pending.open('xb') as output:self.helper('archive',stdout=output)
            meta={'id':ident,'world':world['world'],'folders':world['folders'],'container':self.args.container,
                  'image':self.info['Image'],'sha256':hashfile(pending),'bytes':pending.stat().st_size}
            self.validate(pending,meta,world['world'])
            pending.rename(archive)
            (self.root/(ident+'.json')).write_text(json.dumps(meta,ensure_ascii=False,indent=2))
        finally:pending.unlink(missing_ok=True)
        say('Zapisano kopię: '+ident);return ident
    def validate(self,archive,meta,world):
        assert archive.is_file() and not archive.is_symlink(), 'Brak pliku kopii'
        assert meta['container']==self.args.container and meta['world']==world, 'Kopia innego kontenera lub świata'
        assert meta['sha256']==hashfile(archive), 'Błędna suma SHA256 kopii'
        allowed={world,world+'_nether',world+'_the_end'};found=False
        assert world in meta['folders'] and set(meta['folders'])<=allowed, 'Błędna lista światów'
        with tarfile.open(archive,'r:gz') as source:
            seen=set()
            for m in source:
                p=Path(m.name);parts=p.parts
                assert parts and not p.is_absolute() and '..' not in parts and parts[0] in meta['folders'], 'Niebezpieczna ścieżka w kopii'
                assert m.isfile() or m.isdir(), 'Dowiązanie lub plik specjalny w kopii'
                assert m.name not in seen, 'Powtórzona ścieżka w kopii'
                seen.add(m.name)
                if m.name==world+'/level.dat' and m.isfile():found=True
        assert found,'Brak level.dat w kopii'
    def restore(self,ident):
        assert re.fullmatch(r'\d{8}-\d{6}-[a-f0-9]{8}',ident),'Nieprawidłowy ID kopii; użyj kopia lista'
        manifest=self.root/(ident+'.json');assert not manifest.is_symlink(),'Dowiązanie zamiast manifestu'
        meta=json.loads(manifest.read_text());archive=self.root/(ident+'.tar.gz')
        world=json.loads(self.helper('info',stdout=subprocess.PIPE).stdout)['world']
        # Fully validate before stopping the server or touching its files.
        self.validate(archive,meta,world)
        if self.args.dry_run:say('[podgląd] kopia bieżącego świata, przywrócenie '+ident+', uruchomienie serwera');return
        self.stop()
        before=self.snapshot()
        try:
            with archive.open('rb') as source:self.helper('restore',stdin=source,stdout=subprocess.PIPE)
            say('Przywrócono kopię: '+ident+'; kopia stanu sprzed operacji: '+before)
        except BaseException:
            with (self.root/(before+'.tar.gz')).open('rb') as source:self.helper('restore',stdin=source,stdout=subprocess.PIPE)
            say('Błąd przywracania; odtworzono stan sprzed operacji.',True)
            raise

def hashfile(path):
    digest=hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',required=True,type=Path);parser.add_argument('--container',required=True)
    parser.add_argument('--timeout',type=int,default=10);parser.add_argument('--dry-run',action='store_true')
    parser.add_argument('action',choices=['lista','utworz','przywroc']);parser.add_argument('id',nargs='?')
    args=parser.parse_args();os.umask(0o077)
    assert args.root.is_absolute() and not args.root.is_symlink(),'Nieprawidłowy katalog kopii'
    assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',args.container),'Nieprawidłowa nazwa kontenera'
    if args.action=='lista':
        say('KOPIE ŚWIATA — ID / rozmiar')
        for path in sorted(args.root.glob('*.json'),reverse=True):
            if re.fullmatch(r'\d{8}-\d{6}-[a-f0-9]{8}',path.stem) and not path.is_symlink():
                meta=json.loads(path.read_text());say(f"  {path.stem}  {meta['bytes']/1024/1024:.1f} MiB")
        return
    if args.action=='utworz' and args.dry_run:
        say('[podgląd] zatrzymanie kontenera, archiwum świata do '+str(args.root)+', ponowne uruchomienie');return
    if args.action=='przywroc' and args.dry_run:
        assert args.id and re.fullmatch(r'\d{8}-\d{6}-[a-f0-9]{8}',args.id), 'Nieprawidłowy ID kopii'
        manifest=args.root/(args.id+'.json');assert not manifest.is_symlink(), 'Dowiązanie zamiast manifestu'
        meta=json.loads(manifest.read_text())
        Backups(args).validate(args.root/(args.id+'.tar.gz'),meta,meta['world'])
        say('[podgląd] kopia bieżącego świata, przywrócenie '+args.id+', uruchomienie serwera');return
    args.root.mkdir(mode=0o700,parents=True,exist_ok=True)
    lock=args.root/'.lock';assert not lock.is_symlink(),'Dowiązanie zamiast blokady'
    with lock.open('a') as held:
        fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
        job=Backups(args);job.inspect()
        try:
            if args.action=='utworz':job.stop();job.snapshot()
            else:assert args.id,'Podaj ID kopii';job.restore(args.id)
        finally:job.start()

if __name__=='__main__':
    # Convert normal termination to an exception so the recovery finally runs.
    signal.signal(signal.SIGTERM,lambda *_:sys.exit(143))
    try:main()
    except (AssertionError,OSError,ValueError,KeyError,tarfile.TarError,subprocess.SubprocessError) as error:
        detail=error.stderr.decode(errors='replace') if isinstance(error,subprocess.CalledProcessError) and error.stderr else str(error)
        say('NIK: '+detail,True);sys.exit(1)
