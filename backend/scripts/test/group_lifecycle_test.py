#!/usr/bin/env python3
import asyncio
import unittest
from unittest.mock import patch
from uuid import uuid4
import group_store_test as f
from group_runtime_test import RuntimeTests
from verabot.agents import group_runtime as runtime
from verabot.db import group_store as store
from verabot.services import groups,llm
from verabot import db

class LifecycleTests(RuntimeTests):
    def setUp(self):
        super().setUp()
        with db.tx() as c: c.execute("DELETE FROM usage_log WHERE user_id=? AND kind='group_chat'",(f.UID,))

    def turn(self):
        return store.claim_turn(f.UID,self.g['id'],{'client_request_id':str(uuid4()),'message':'原问题','mode':'round'})

    def test_stop_keeps_partial_and_does_not_call_c(self):
        async def scenario():
            turn=self.turn(); seen=[]
            async def provider(messages,tools,**kw):
                name=__import__('json').loads(messages[1]['content'])['current']['name'];seen.append(name)
                yield 'usage',{'total_tokens':5}
                yield 'delta',name+'片段'
                if name=='B': await asyncio.Event().wait()
            with patch.object(llm,'stream_chat',provider):
                async for name,event in runtime.run(f.UID,self.g,turn):
                    if name=='delta' and event['text']=='B片段':
                        groups.request_stop(f.UID,self.g['id'],turn['id'])
                        groups.request_stop(f.UID,self.g['id'],turn['id'])
            saved=store.get_turn(f.UID,self.g['id'],turn['id'])
            self.assertEqual(saved['status'],'stopped')
            self.assertEqual(seen,['A','B'])
            self.assertEqual(saved['messages'][-1]['content'],'B片段')
            self.assertEqual(saved['messages'][-1]['status'],'stopped')
            with db.tx() as c:
                self.assertEqual(c.execute("SELECT COUNT(*) FROM usage_log WHERE kind='group_chat' AND user_id=?",(f.UID,)).fetchone()[0],2)
            self.turn() # No lingering busy lock.
        asyncio.run(scenario())

    def test_disconnect_and_startup_recovery_account_known_usage_once(self):
        async def scenario():
            turn=self.turn(); stream=runtime.run(f.UID,self.g,turn)
            with patch.object(llm,'stream_chat',self.provider):
                async for name,event in stream:
                    if name=='message_done': break
                await stream.aclose()
            self.assertEqual(store.get_turn(f.UID,self.g['id'],turn['id'])['status'],'interrupted')
        asyncio.run(scenario())
        t=self.turn()
        first=store.start_reply(f.UID,self.g['id'],t['id'],self.g['members'][0]['id'])
        store.save_reply(f.UID,first['id'],'重启前 A 完整回答','completed',{'total_tokens':2},finalize=True)
        m=store.start_reply(f.UID,self.g['id'],t['id'],self.g['members'][1]['id'])
        store.save_reply(f.UID,m['id'],'崩溃前文字','streaming',{'total_tokens':7},finalize=False)
        self.assertEqual(store.recover_interrupted_turns(),1)
        self.assertEqual(store.recover_interrupted_turns(),0)
        saved=store.get_message(f.UID,self.g['id'],m['id'])
        self.assertEqual((saved['status'],saved['content']),('interrupted','崩溃前文字'))
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT SUM(total_tokens) FROM usage_log WHERE kind='group_chat' AND user_id=?",(f.UID,)).fetchone()[0],14)
        retry=store.claim_retry(f.UID,self.g['id'],m['id'],str(uuid4()))
        from verabot.agents.group_context import build
        self.assertIn('重启前 A 完整回答',str(build(f.UID,self.g,self.g['members'][1],retry)))
        store.finish_turn(f.UID,self.g['id'],retry['id'],'interrupted')
        self.turn()

    def test_retry_uses_original_context_and_only_failed_member(self):
        self.failed_names={'B'};self.send()
        old=store.list_messages(f.UID,self.g['id'])['messages']; failed=old[2]
        self.failed_names=set();self.send('single',f.BOTS[0]);self.calls=[]
        original_provider=self.provider
        async def provider(messages,tools,**kw):
            self.assertNotIn('后来秘密',str(messages))
            async for event in original_provider(messages,tools,**kw): yield event
        later=store.claim_turn(f.UID,self.g['id'],{'client_request_id':str(uuid4()),'message':'后来秘密'})
        store.finish_turn(f.UID,self.g['id'],later['id'],'completed')
        request={'client_request_id':str(uuid4())};path=f"/api/groups/{self.g['id']}/messages/{failed['id']}/retry"
        with patch.object(llm,'stream_chat',provider): r=f.cli.post(path,headers=f.H,json=request)
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual([x[0] for x in self.calls],['B'])
        self.assertEqual(f.cli.post(path,headers=f.H,json=request).status_code,409)
        self.assertEqual(f.cli.post(path,headers=f.H2,json={'client_request_id':str(uuid4())}).status_code,404)
        new=store.list_messages(f.UID,self.g['id'])['messages'][-1]
        self.assertNotEqual(new['id'],failed['id'])
        turn=store.get_turn(f.UID,self.g['id'],new['turn_id'])
        self.assertEqual(turn['retry_of_message_id'],failed['id'])
        self.assertEqual(turn['user_message_id'],old[0]['id'])

    def test_member_timeout_continues(self):
        async def provider(messages,tools,**kw):
            name=__import__('json').loads(messages[1]['content'])['current']['name']
            self.calls.append(name)
            if name=='B':
                yield 'delta','部分'
                await asyncio.Event().wait()
            else: yield 'delta','完成'
        with patch.object(llm,'stream_chat',provider), patch.object(runtime,'MEMBER_TIMEOUT',0.05):
            r=f.cli.post(f"/api/groups/{self.g['id']}/chat",headers=f.H,json={'client_request_id':str(uuid4()),'message':'问题','mode':'round'})
        self.assertEqual(r.status_code,200)
        self.assertEqual(self.calls,['A','B','C'])
        self.assertIn('member_timeout',r.text)

    def test_cancellation_drops_late_delta_and_keeps_known_usage(self):
        async def scenario():
            turn=self.turn(); blocked=asyncio.Event()
            async def provider(messages,tools,**kw):
                yield 'usage',{'total_tokens':5}
                yield 'delta','保存片段'
                blocked.set()
                try: await asyncio.Event().wait()
                except asyncio.CancelledError: yield 'delta','迟到片段'
            async def consume():
                async for _ in runtime.run(f.UID,self.g,turn): pass
            with patch.object(llm,'stream_chat',provider):
                task=asyncio.create_task(consume());await blocked.wait();task.cancel()
                try: await task
                except asyncio.CancelledError: pass
            saved=store.get_turn(f.UID,self.g['id'],turn['id'])
            self.assertEqual(saved['status'],'interrupted')
            self.assertEqual(saved['messages'][-1]['content'],'保存片段')
            self.assertEqual(saved['messages'][-1]['usage']['total_tokens'],5)
            self.turn()
        asyncio.run(scenario())

    def test_deleted_generating_member_keeps_snapshot_and_continues(self):
        disposable=f.cli.post('/api/bots',headers=f.H,json={'name':'Disposable'}).json()['id']
        self.g=self.create([f.BOTS[0],disposable,f.BOTS[2]]).json()
        async def provider(messages,tools,**kw):
            name=__import__('json').loads(messages[1]['content'])['current']['name'];self.calls.append(name)
            yield 'delta',name+'部分'
            if name=='Disposable':
                f.cli.delete(f'/api/bots/{disposable}',headers=f.H)
                yield 'delta','删除后迟到'
        with patch.object(llm,'stream_chat',provider):
            r=f.cli.post(f"/api/groups/{self.g['id']}/chat",headers=f.H,json={'client_request_id':str(uuid4()),'message':'问题','mode':'round'})
        self.assertEqual(self.calls,['A','Disposable','C'])
        history=store.list_messages(f.UID,self.g['id'])['messages']
        self.assertEqual(history[2]['sender_name'],'Disposable')
        self.assertEqual(history[2]['status'],'stopped')
        self.assertNotIn('删除后迟到',history[2]['content'])
        self.assertEqual(history[3]['status'],'completed')

    def test_sse_disconnect_closes_provider_and_releases_turn(self):
        async def scenario():
            import json
            disconnect=asyncio.Event(); closed=asyncio.Event(); first=True
            payload=json.dumps({'client_request_id':str(uuid4()),'message':'断线问题','mode':'round'}).encode()
            async def receive():
                nonlocal first
                if first:
                    first=False
                    return {'type':'http.request','body':payload,'more_body':False}
                await disconnect.wait()
                return {'type':'http.disconnect'}
            async def send(event):
                if event['type']=='http.response.body' and b'event: delta' in event.get('body',b''):
                    disconnect.set()
            async def provider(messages,tools,**kw):
                try:
                    yield 'usage',{'total_tokens':3}
                    yield 'delta','部分正文'
                    await asyncio.Event().wait()
                finally:
                    await asyncio.sleep(0.01)  # Real transports close asynchronously.
                    closed.set()
            path=f"/api/groups/{self.g['id']}/chat"
            scope={'type':'http','asgi':{'version':'3.0','spec_version':'2.3'},'http_version':'1.1','method':'POST',
                'scheme':'http','path':path,'raw_path':path.encode(),'query_string':b'',
                'headers':[(b'authorization',f.H['Authorization'].encode()),(b'content-type',b'application/json')],
                'client':('127.0.0.1',1234),'server':('testserver',80)}
            with patch.object(llm,'stream_chat',provider):
                await asyncio.wait_for(f.app(scope,receive,send),2)
            self.assertTrue(closed.is_set())
            history=store.list_messages(f.UID,self.g['id'])['messages']
            self.assertEqual(history[-1]['status'],'interrupted')
            self.assertEqual(history[-1]['content'],'部分正文')
            self.assertEqual(store.get_turn(f.UID,self.g['id'],history[-1]['turn_id'])['status'],'interrupted')
            self.turn()
        asyncio.run(scenario())

    def test_turn_deadline_finishes_partial_and_releases_turn(self):
        async def provider(messages,tools,**kw):
            yield 'delta','部分正文'
            await asyncio.Event().wait()
        with patch.object(llm,'stream_chat',provider), patch.object(runtime,'TURN_TIMEOUT',0.05):
            r=f.cli.post(f"/api/groups/{self.g['id']}/chat",headers=f.H,json={'client_request_id':str(uuid4()),'message':'问题','mode':'round'})
        self.assertIn('turn_timeout',r.text)
        history=store.list_messages(f.UID,self.g['id'])['messages']
        self.assertEqual(history[-1]['status'],'failed')
        self.assertIsNone(history[-1]['usage'])
        self.assertEqual(store.get_turn(f.UID,self.g['id'],history[-1]['turn_id'])['status'],'partial')
        self.turn()

if __name__=='__main__':
    names=[n for n in LifecycleTests.__dict__ if n.startswith('test_')]
    result=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(LifecycleTests(n) for n in names))
    raise SystemExit(not result.wasSuccessful())
