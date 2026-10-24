"""Private typed result channel shared by NIK's own helpers."""
import json,os,stat
from pathlib import Path

def write_result(value):
 name=os.environ.get('NIK_RESULT_PATH')
 if not name:return
 path=Path(name)
 assert path.is_absolute(),'Kanał wyniku wymaga ścieżki absolutnej'
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_NOFOLLOW|os.O_NONBLOCK,0o600)
 try:
  assert stat.S_ISREG(os.fstat(fd).st_mode),'Kanał wyniku wymaga pliku'
  os.fchmod(fd,0o600);os.ftruncate(fd,0)
  with os.fdopen(fd,'w',closefd=False) as out:json.dump(value,out,ensure_ascii=False)
 finally:os.close(fd)
