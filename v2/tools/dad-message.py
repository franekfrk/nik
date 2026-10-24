#!/usr/bin/env python3
"""Build a literal, private Minecraft chat component; never interpret message text."""
import json,sys,unicodedata

def component(message):
    assert 1<=len(message)<=512 and message.strip(),'Wiadomość musi mieć 1–512 znaków i zawierać tekst.'
    assert not any(unicodedata.category(c) in {'Cc','Cs'} for c in message),'Wiadomość zawiera niedozwolony znak sterujący.'
    return json.dumps(['',{'text':'[Tata ♥] ','color':'gold','bold':True},
                       {'text':message,'color':'white','bold':False}],ensure_ascii=False,separators=(',',':'))
if __name__=='__main__':
    try:print(component(' '.join(sys.argv[1:])))
    except AssertionError as error:print('NIK: '+str(error),file=sys.stderr);sys.exit(2)
