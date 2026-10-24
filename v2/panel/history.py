"""Bounded private operation history. Never replays commands after a restart."""
import json,os,sqlite3,stat,threading
from pathlib import Path
from contextlib import contextmanager

FIELDS=('id','state','output','code','label','preview','action','player','timestamp','command')
LIMIT=100

class History:
 def __init__(self,root):
  self.lock=threading.RLock()
  parent=Path(root)/'state'
  for directory in (parent,parent/'panel'):
   if directory.is_symlink():raise ValueError('Historia nie może być dowiązaniem.')
   directory.mkdir(mode=0o700,exist_ok=True)
  self.path=parent/'panel'/'history.sqlite3'
  os.chmod(self.path.parent,0o700)
  fd=os.open(self.path,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
  try:
   if not stat.S_ISREG(os.fstat(fd).st_mode):raise ValueError('Historia wymaga zwykłego pliku.')
   os.fchmod(fd,0o600)
  finally:os.close(fd)
  with self.lock,self.connect() as db:
   db.execute('CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL)')
   db.execute('CREATE TABLE IF NOT EXISTS favorites (id TEXT PRIMARY KEY, name TEXT NOT NULL, request TEXT NOT NULL)')
   # A stopped process may already have changed Minecraft. Preserve uncertainty.
   for id,payload in db.execute("SELECT id,payload FROM history WHERE state IN ('queued','running')").fetchall():
    record=json.loads(payload);record.update(state='interrupted',code=None,output='Panel został zrestartowany przed zapisaniem wyniku. Wcześniejsze kroki mogły zostać wykonane. Sprawdź stan gry przed ponowieniem; panel nie ponowił operacji.')
    db.execute('UPDATE history SET state=?,payload=? WHERE id=?',(record['state'],json.dumps(record,ensure_ascii=False),id))
   self.prune(db)
 @contextmanager
 def connect(self):
  db=sqlite3.connect(self.path,timeout=5)
  try:
   with db:yield db
  finally:db.close()
 def prune(self,db):
  db.execute("DELETE FROM history WHERE state NOT IN ('queued','running') AND id NOT IN (SELECT id FROM history ORDER BY timestamp DESC,id DESC LIMIT ?)",(LIMIT,))
 def put(self,job):
  record={key:job[key] for key in FIELDS}
  with self.lock,self.connect() as db:
   db.execute('INSERT INTO history VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state,payload=excluded.payload',(record['id'],record['timestamp'],record['state'],json.dumps(record,ensure_ascii=False)))
   self.prune(db)
 def list(self):
  with self.lock,self.connect() as db:
   # Only summaries leave the server until an administrator opens a result.
   return [{k:v for k,v in json.loads(row[0]).items() if k!='output'} for row in db.execute('SELECT payload FROM history ORDER BY timestamp DESC,id DESC')]
 def get(self,id):
  with self.lock,self.connect() as db:
   row=db.execute('SELECT payload FROM history WHERE id=?',(id,)).fetchone()
   return json.loads(row[0]) if row else None

 def favorites(self):
  with self.lock,self.connect() as db:return [{'id':id,'name':name,'request':json.loads(request)} for id,name,request in db.execute('SELECT id,name,request FROM favorites ORDER BY rowid')]
 def save_favorite(self,id,name,request):
  with self.lock,self.connect() as db:
   if db.execute('SELECT COUNT(*) FROM favorites').fetchone()[0]>=24:raise ValueError('Możesz zapisać najwyżej 24 ulubione akcje.')
   db.execute('INSERT INTO favorites VALUES (?,?,?)',(id,name,json.dumps(request,ensure_ascii=False)))
 def delete_favorite(self,id):
  with self.lock,self.connect() as db:db.execute('DELETE FROM favorites WHERE id=?',(id,))
