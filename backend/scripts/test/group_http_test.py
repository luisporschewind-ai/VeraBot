#!/usr/bin/env python3
"""Real socket HTTP regression against group_chat_demo.py (no real provider)."""
import asyncio
import json
from pathlib import Path
import sys
from uuid import uuid4
import httpx

URL = sys.argv[1] if len(sys.argv)>1 else 'http://127.0.0.1:8093'

async def main():
    async with httpx.AsyncClient(base_url=URL, timeout=40) as c:
        r=await c.post('/api/auth/login',json={'username':'group-demo','password':'group-demo-123'})
        r.raise_for_status(); c.headers['Authorization']='Bearer '+r.json()['token']
        ids=[b['id'] for b in (await c.get('/api/bots')).json()['bots']][:3]
        r=await c.post('/api/groups',json={'name':'G3 HTTP 联调','bot_ids':ids,'default_bot_id':ids[0]})
        assert r.status_code==201,r.text
        gid=r.json()['id']; path=f'/api/groups/{gid}'
        def body(text='讨论问题',mode='single',target=None):
            b={'client_request_id':str(uuid4()),'message':text,'mode':mode}
            if target: b['target_bot_id']=target
            return b
        async def send(b, suffix='/chat'):
            r=await c.post(path+suffix,json=b); assert r.status_code==200,r.text
            assert r.headers['cache-control']=='no-store'
            frames=[]
            for frame in r.text.split('\n\n'):
                if not frame.strip(): continue
                lines=frame.splitlines(); frames.append((lines[0][7:],json.loads(lines[1][6:])))
            assert frames[-1][0]=='turn_done'
            assert all(f[1]['group_id']==gid for f in frames)
            return frames
        req=body(); await send(req)
        duplicate=await c.post(path+'/chat',json=req)
        assert duplicate.status_code==409 and duplicate.json()['detail']['code']=='request_exists'
        await send(body(target=ids[1])); await send(body(mode='round'))
        history=(await c.get(path+'/messages')).json()['messages']
        assert [m['sender_name'] for m in history if m['role']=='bot']==['A','B','A','B','C']
        print('PASS create/default A/target B/ordered round/persisted history/UUID duplicate',flush=True)
        # Stop while the real network stream is active; reject concurrent writes.
        async with c.stream('POST',path+'/chat',json=body(mode='round')) as response:
            assert response.status_code==200
            event=None
            async for line in response.aiter_lines():
                if line.startswith('event: '): event=line[7:]
                if line.startswith('data: ') and event=='message_start':
                    data=json.loads(line[6:]); tid=data['turn_id']
                    busy=await c.post(path+'/chat',json=body())
                    assert busy.status_code==409 and busy.json()['detail']['code']=='group_busy'
                    assert (await c.delete(path+'/messages')).status_code==409
                    assert (await c.post(path+f'/turns/{tid}/stop')).status_code==200
                    assert (await c.post(path+f'/turns/{tid}/stop')).status_code==200
                if line.startswith('data: ') and event=='turn_done': break
        turn=(await c.get(path+f'/turns/{tid}')).json()
        assert turn['status']=='stopped' and len([m for m in turn['messages'] if m['role']=='bot'])==1,turn
        print('PASS concurrent busy/clear busy/stop repeated/no later members',flush=True)
        # Deliberate B failure, C continues, B-only retry adds no user question.
        await send(body('[fail-once]',mode='round'))
        before=(await c.get(path+'/messages')).json()['messages']
        failed=next(m for m in reversed(before) if m['status']=='failed')
        await send({'client_request_id':str(uuid4())},f"/messages/{failed['id']}/retry")
        after=(await c.get(path+'/messages')).json()['messages']
        assert len(after)==len(before)+1 and after[-1]['sender_name']=='B' and after[-1]['status']=='completed'
        assert after[-1]['retry_of_message_id']==failed['id']
        print('PASS B failure/C continuation/B-only retry/original question/no duplicate user',flush=True)
        # Closing a socket after the first delta must terminalize the turn.
        async with c.stream('POST',path+'/chat',json=body(mode='round')) as response:
            event=None
            async for line in response.aiter_lines():
                if line.startswith('event: '): event=line[7:]
                if line.startswith('data: ') and event=='delta':
                    tid=json.loads(line[6:])['turn_id']; break
        for _ in range(100):
            turn=(await c.get(path+f'/turns/{tid}')).json()
            if turn['status']!='running': break
            await asyncio.sleep(.05)
        assert turn['status']=='interrupted',turn
        assert (await c.get(path)).json()['active_turn_id'] is None
        assert (await c.delete(path+'/messages')).status_code==200
        assert (await c.get(path+'/messages')).json()['messages']==[]
        assert (await c.delete(path)).status_code==200
        assert (await c.get(path)).status_code==404
        print('PASS real socket disconnect/re-entry/clear/delete',flush=True)
        # Leave a clean group for the human's Simulator acceptance.
        r=await c.post('/api/groups',json={'name':'伙伴讨论 · G3 验收','bot_ids':ids,'default_bot_id':ids[0]})
        assert r.status_code==201,r.text
        print('ALL HTTP CHECKS PASSED; human demo group',r.json()['id'])

asyncio.run(main())
