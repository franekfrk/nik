#!/usr/bin/env python3
"""Parse the three vanilla /data responses and validate private return records."""
import datetime,json,re,sys
from decimal import Decimal,InvalidOperation,ROUND_HALF_UP
from pathlib import Path
NUM=r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?'
DIM=re.compile(r'[a-z0-9_.-]+:[a-z0-9_./-]+')

def number(value,limit):
    assert isinstance(value,str) and len(value)<=80 and re.fullmatch(NUM,value),'Nieprawidłowa współrzędna'
    n=Decimal(value)
    assert n.is_finite() and abs(n)<=limit,'Współrzędna poza zakresem'
    n=n.quantize(Decimal('0.000001'),rounding=ROUND_HALF_UP)
    return format(n,'f').rstrip('0').rstrip('.') if n else '0'

def payload(raw):
    found=re.fullmatch(r'.+ has the following entity data: (.+)',raw.strip())
    assert found,'Nie rozpoznano odpowiedzi Minecrafta na odczyt pozycji'
    return found[1]

def vector(raw,count,limit):
    values=re.fullmatch(r'\[\s*(.*?)\s*\]',payload(raw))
    assert values,'Nieprawidłowa lista współrzędnych'
    parts=[p.strip() for p in values[1].split(',')]
    assert len(parts)==count,'Nieprawidłowa liczba współrzędnych'
    return [number(re.sub(r'[dDfF]$','',p),limit) for p in parts]

def validate(record,player,container):
    assert record['schema']==1 and record['player']==player and record['container']==container,'Punkt powrotu należy do innego gracza lub kontenera'
    assert isinstance(record['position'],list) and len(record['position'])==3,'Błędna pozycja'
    assert isinstance(record['rotation'],list) and len(record['rotation'])==2,'Błędny kierunek'
    position=[number(v,30000000) for v in record['position']]
    rotation=[number(v,360000000) for v in record['rotation']]
    assert abs(Decimal(rotation[1]))<=90,'Błędny kąt patrzenia'
    assert isinstance(record['dimension'],str) and DIM.fullmatch(record['dimension']),'Błędny wymiar'
    return [*position,record['dimension'],*rotation]

def capture(player,container,pos,dimension,rotation):
    dim=json.loads(payload(dimension));assert isinstance(dim,str) and DIM.fullmatch(dim),'Błędny wymiar'
    record={'schema':1,'player':player,'container':container,'position':vector(pos,3,30000000),
            'rotation':vector(rotation,2,360000000),'dimension':dim,
            'saved_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    validate(record,player,container)
    return record

def main():
    action=sys.argv[1]
    if action=='capture':print(json.dumps(capture(*sys.argv[2:]),ensure_ascii=False))
    elif action=='fields':print('\t'.join(validate(json.load(sys.stdin),*sys.argv[2:])))
    elif action=='read':
        path=Path(sys.argv[2]);assert path.is_file() and not path.is_symlink(),'Brak punktu powrotu lub dowiązanie'
        assert path.stat().st_size<=4096,'Nieprawidłowy plik powrotu'
        print('\t'.join(validate(json.loads(path.read_text()),*sys.argv[3:])))
    else:raise AssertionError('Nieznana operacja pozycji')
if __name__=='__main__':
    try:main()
    except (AssertionError,ValueError,KeyError,TypeError,OSError,InvalidOperation) as error:
        print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
