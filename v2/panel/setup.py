#!/usr/bin/env python3
"""Create private panel credentials. Run from the installed ~/.nik checkout."""
import argparse,json,os,secrets,tempfile
from pathlib import Path
from urllib.parse import urlsplit
from server import password_record,listener_addresses

def atomic(path,text):
 fd,name=tempfile.mkstemp(prefix='.panel-',dir=path.parent)
 try:
  with os.fdopen(fd,'w') as out:out.write(text)
  os.chmod(name,0o600);os.replace(name,path)
 finally:Path(name).unlink(missing_ok=True)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--origin',required=True);parser.add_argument('--port',type=int,default=6767);parser.add_argument('--lan-ip',help='Opcjonalny prywatny IPv4 dla dostępu HTTP w LAN');args=parser.parse_args()
 url=urlsplit(args.origin)
 if url.scheme!='https' or not url.hostname or url.path or url.query or url.fragment or url.username:raise SystemExit('Podaj pełny adres HTTPS bez ścieżki i hasła.')
 if not 1024<=args.port<=65535:raise SystemExit('Nieprawidłowy port.')
 root=Path(__file__).resolve().parents[1];directory=root/'config';directory.mkdir(mode=0o700,exist_ok=True)
 if directory.is_symlink():raise SystemExit('Config nie może być dowiązaniem.')
 file=directory/'panel.json';plain=directory/'panel-password.txt'
 if file.is_symlink() or plain.is_symlink():raise SystemExit('Pliki panelu nie mogą być dowiązaniami.')
 if file.exists():
  config=json.loads(file.read_text())
  if config['nik_root']!=str(root):raise SystemExit('Istniejący panel wskazuje inny katalog NIK.')
 else:
  password=secrets.token_urlsafe(15);atomic(plain,password+'\n');config={'nik_root':str(root),'password':password_record(password)}
 config.update(bind='127.0.0.1',port=args.port,origins=[args.origin])
 lan=args.lan_ip or config.get('lan_bind')
 if lan:config.update(lan_bind=lan,origins=[args.origin,f'http://{lan}:{args.port}'])
 listener_addresses(config);atomic(file,json.dumps(config,indent=2)+'\n')
 print('Konfiguracja panelu zapisana prywatnie. Hasło: config/panel-password.txt (nie wyświetlono).')
if __name__=='__main__':main()
