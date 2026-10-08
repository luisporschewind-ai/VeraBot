"""Versioned avatar API contract; isolated SQLite, no live service or model requests."""
import copy
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory(prefix="vera_appearance_") as tmp:
    os.environ["VERABOT_DB"] = str(Path(tmp)/"test.db")
    os.environ["VERABOT_DATA_DIR"] = tmp
    os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
    from verabot import db
    from verabot.db import migrations
    # A real historical v14 schema, including one preserved bot.
    with db.tx() as c:
        ver = migrations.v001_base.migrate(c)
        for step in migrations.STEPS:
            if not step.__name__.endswith("v015_bot_appearance"):
                step.migrate(c,ver)
        c.execute("INSERT OR REPLACE INTO schema_meta VALUES ('version','14')")
        c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (99,'historical','x','2026-01-01')")
        c.execute("INSERT INTO bots(user_id,name,avatar,color,created_at) VALUES (99,'OldBot','cloud','#0F766E','2026-01-01')")
    db.init_db(); db.init_db()
    with db.tx() as c:
        assert "appearance" in {r[1] for r in c.execute("PRAGMA table_info(bots)")}, "appearance migration missing"
        old = dict(c.execute("SELECT * FROM bots WHERE user_id=99").fetchone())
        assert old["appearance"] is None and old["avatar"] == "cloud" and old["color"] == "#0F766E"
    from fastapi.testclient import TestClient
    from verabot.main import app
    client = TestClient(app)
    def register(name):
        response=client.post('/api/auth/register',json={'username':name,'password':'pw123456'})
        assert response.status_code == 200,response.text
        return {'Authorization':'Bearer '+response.json()['token']}
    alice,bob=register('appearance_alice'),register('appearance_bob')
    config={'schema_version':1,'template_id':'cx-robot','template_version':1,
            'palette':{'body':{'space':'display-p3','red':0.917647,'green':0.25098,'blue':0.270588},
                       'eyes':{'space':'srgb','red':248/255,'green':248/255,'blue':246/255}},
            'parameters':{'roundness':0.5}}
    response=client.post('/api/bots',headers=alice,json={'name':'Test','appearance':config,'avatar':'cloud','color':'#0F766E'})
    assert response.status_code == 201,response.text
    bot=response.json();bid=bot['id'];url=f'/api/bots/{bid}'
    assert bot['appearance'] == config
    invariant={k:bot[k] for k in ['avatar','color','allowed_tools','delegate_to','accept_delegation','has_avatar']}
    assert client.get(url,headers=alice).json()['appearance']==config
    assert client.get('/api/bots',headers=alice).json()['bots'][0]['appearance']==config
    assert client.patch(url,headers=alice,json={'name':'Renamed'}).json()['appearance']==config
    updated=copy.deepcopy(config);updated['parameters']['roundness']=0.75
    patched=client.patch(url,headers=alice,json={'appearance':updated}).json()
    assert patched['appearance']==updated
    assert all(patched[k]==v for k,v in invariant.items())
    assert client.patch(url,headers=bob,json={'appearance':config}).status_code==404
    assert client.get(url,headers=bob).status_code==404
    assert client.patch(url,headers=alice,json={'appearance':None}).json()['appearance'] is None
    future=copy.deepcopy(config);future['template_id']='future-shape'
    assert client.patch(url,headers=alice,json={'appearance':future}).json()['appearance']==future
    bad=[]
    for key,value in [('schema_version',True),('schema_version',2),('template_version',False),('template_version',0),('template_id','Bad ID'),('template_id','a'*5000)]:
        item=copy.deepcopy(config);item[key]=value;bad.append(item)
    for value in [-0.1,1.1,True,'0.5']:
        item=copy.deepcopy(config);item['palette']['body']['red']=value;bad.append(item)
    for value in [-0.1,1.1,False]:
        item=copy.deepcopy(config);item['parameters']['roundness']=value;bad.append(item)
    item=copy.deepcopy(config);item['parameters']['script']='x';bad.append(item)
    item=copy.deepcopy(config);item['palette']['body']['space']='unknown';bad.append(item)
    for item in bad:
        response=client.patch(url,headers=alice,json={'appearance':item})
        assert response.status_code==422,response.text
    assert client.get(url,headers=alice).json()['appearance']==future
    # Corrupt storage is isolated to the appearance, never to an entire bot list.
    with db.tx() as c: c.execute("UPDATE bots SET appearance='broken-json' WHERE id=?",(bid,))
    assert client.get(url,headers=alice).json()['appearance'] is None
    print('PASS v14 migration twice, legacy preservation, create/read/list/replace/omit/clear, future template, 15 invalid payloads, tenant isolation, corrupt storage fallback')
