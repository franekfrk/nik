#!/usr/bin/env python3
"""Build a literal, private Minecraft chat component; never interpret message text."""
import json,sys,unicodedata

def component(message):
    assert 1<=len(message)<=512 and message.strip(),'Wiadomość musi mieć 1–512 znaków i zawierać tekst.'
    assert not any(unicodedata.category(c) in {'Cc','Cs'} for c in message),'Wiadomość zawiera niedozwolony znak sterujący.'
    return json.dumps(['',{'text':'[Tata ♥] ','color':'gold','bold':True},
                       {'text':message,'color':'white','bold':False}],ensure_ascii=False,separators=(',',':'))
if __name__=='__main__':
    try:
        assert len(sys.argv)>=2 and sys.argv[1] in {'chat','title'}, 'Nieprawidłowy tryb wiadomości.'
        parts=json.loads(component(' '.join(sys.argv[2:])))
        if sys.argv[1]=='title':print(json.dumps({'text':parts[2]['text'],'color':'gold','bold':True},ensure_ascii=False,separators=(',',':')))
        else:print(json.dumps(parts,ensure_ascii=False,separators=(',',':')))
    except AssertionError as error:print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
