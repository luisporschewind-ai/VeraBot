"""Isolated contract, privacy and durable publication regression tests."""
from scheduled_task_test_support import DBTest, db, NOW
import importlib.util
import unittest
from datetime import timedelta
from unittest.mock import patch

class FeatureTests(DBTest):
    def test_feed_subsystem_exists(self):
        self.assertIsNotNone(importlib.util.find_spec('verabot.db.feed_store'), 'Feed store is missing')

# Imports stay optional only for the initial missing-feature RED run.
if importlib.util.find_spec('verabot.db.feed_store'):
    from verabot.db import feed_store as store
    from verabot.services.feed import service, parser, fetcher, worker
    from verabot.api.routers import feed
    from verabot.api.deps import current_user
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    class FeedTests(DBTest):
        def setUp(self):
            super().setUp()
            self.app=FastAPI(); self.app.include_router(feed.router)
            self.app.dependency_overrides[current_user]=lambda: {'id':1}
            self.client=TestClient(self.app)
        def plan(self, **kw):
            body=dict(enabled=True,bot_ids=[1],topics=['科技'],excluded_topics=[],use_memory=True,expected_version=0)
            body.update(kw)
            return self.client.put('/api/feed/plan',json=body)
        def source(self, bot=1):
            return service.add_source(1,dict(name='Example',url='https://example.com/feed',kind='news',bot_id=bot))
        def publish(self, source, entries=None):
            with db.tx(immediate=True) as c: job=store.claim(c,NOW.isoformat(),300)
            self.assertIsNotNone(job)
            with db.tx(immediate=True) as c:
                return store.complete(c,job,entries or [dict(kind='news',title='A',url='https://example.com/a',summary='actual',summary_basis='description')],NOW.isoformat(),etag='tag',modified=None)
        def test_plan_defaults_cas_and_tenant_bot_validation(self):
            p=self.client.get('/api/feed/plan').json()
            self.assertEqual(p,dict(enabled=False,bot_ids=[],topics=[],excluded_topics=[],use_memory=True,daily_limit=20,version=0))
            self.assertEqual(self.plan(bot_ids=[2]).status_code,404)
            self.assertEqual(self.plan().json()['version'],1)
            self.assertEqual(self.plan().status_code,409)
        def test_migration_idempotent_from_v35(self):
            with db.tx() as c:
                for table in ('feed_pending_candidates','feed_item_recommendations','feed_items','feed_sources','feed_plans'): c.execute('DROP TABLE IF EXISTS '+table)
                c.execute("UPDATE schema_meta SET value='35' WHERE key='version'")
            db.init_db(); db.init_db()
            with db.tx() as c:
                self.assertEqual(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0],'36')
        def test_source_idempotent_separate_bots(self):
            a=self.source(); self.assertEqual(a,self.source())
            with db.tx() as c: c.execute("INSERT INTO bots(id,user_id,name,created_at) VALUES(3,1,'other','x')")
            b=self.source(3)
            self.assertNotEqual(a['id'],b['id']); self.assertIsInstance(a['id'],int)
            self.assertIsNone(a['last_error'])
            with self.assertRaises(service.FeedError): service.add_source(1,dict(name='x',url='https://example.com',kind='news',bot_id=2))
        def test_publish_state_cursor_quota_and_duplicate_budget(self):
            self.plan(); s=self.source()
            entries=[dict(kind='news',title=str(i),url=f'https://example.com/{i}',summary='real',summary_basis='description') for i in range(25)]
            self.assertEqual(self.publish(s,entries),20)
            items=service.items(1,limit=7)
            self.assertEqual(len(items['items']),7)
            ids={i['id'] for i in items['items']}
            other=service.items(1,limit=7,cursor=items['next_cursor'])
            self.assertFalse(ids & {i['id'] for i in other['items']})
            item=items['items'][0]
            self.assertIsNone(item['author']); self.assertIsNone(item['image_url'])
            self.assertEqual(service.state(1,item['id'],{'saved':True})['saved'],True)
            service.toggle_source(1,s['id'],False)
            self.assertEqual(service.items(1)['items'],[])
            self.assertEqual(len(service.items(1,saved_only=True)['items']),1)
            self.assertEqual(service.items(2)['items'],[])
            with self.assertRaises(service.FeedError): service.item(2,item['id'])
            self.assertEqual(self.client.get('/api/feed/items?cursor=-1').status_code,422)
            self.assertEqual(self.client.get('/api/feed/items?limit=101').status_code,422)
        def test_duplicate_entries_do_not_consume_remaining_daily_budget(self):
            self.plan(); self.source()
            entry=dict(kind='news',title='x',url='https://example.com/a',summary='source',summary_basis='description')
            def collect(job): return dict(entries=[entry]*30+[dict(entry,url=f'https://example.com/new/{i}') for i in range(25)])
            worker.process_one(collect,lambda:NOW.isoformat())
            self.assertEqual(len(service.items(1,limit=100)['items']),20)
            with db.tx() as c:
                self.assertEqual(c.execute('SELECT COUNT(*) FROM feed_items').fetchone()[0],20)
        def test_source_write_and_state_are_tenant_scoped(self):
            self.plan(); source=self.source(); self.publish(source)
            iid=service.items(1)['items'][0]['id']
            for call,args in [(service.toggle_source,(2,source['id'],False)),(service.state,(2,iid,{'saved':True}))]:
                with self.assertRaises(service.FeedError) as err: call(*args)
                self.assertEqual(err.exception.status,404)
            self.assertFalse(service.item(1,iid)['saved'])
            self.assertTrue(service.sources(1)[0]['enabled'])

        def test_multisource_fair_share_and_pending_survive_next_day_304(self):
            self.plan()
            sources=[service.add_source(1,dict(name=kind,url=f'https://example.com/{kind}.xml',kind=kind,bot_id=1)) for kind in ('news','audio','video')]
            def collect(job):
                return dict(entries=[dict(kind=job['kind'],title=str(i),url=f"https://example.com/{job['kind']}/{i}",summary='actual',summary_basis='description') for i in range(20)],etag=job['kind']+'-etag')
            for _ in sources: self.assertTrue(worker.process_one(collect,lambda:NOW.isoformat()))
            first=service.items(1,limit=100)['items']
            self.assertEqual({kind:sum(i['kind']==kind for i in first) for kind in ('news','audio','video')},dict(news=6,audio=6,video=6))
            # A restarted worker receives only304; the fetched but unpublished content persists.
            following=(NOW+timedelta(days=1)).isoformat()
            def not_modified(job): return dict(entries=[],etag=job['etag'])
            for _ in sources: self.assertTrue(worker.process_one(not_modified,lambda:following))
            second=service.items(1,limit=100)['items']
            self.assertEqual({kind:sum(i['kind']==kind for i in second) for kind in ('news','audio','video')},dict(news=12,audio=12,video=12))
            with db.tx() as c:
                self.assertEqual(c.execute('SELECT COUNT(*) FROM feed_pending_candidates').fetchone()[0],24)
        def test_more_than_twenty_source_urls_rotate_without_starvation(self):
            self.plan()
            for i in range(21): service.add_source(1,dict(name=str(i),url=f'https://example.com/rotate/{i}',kind='news',bot_id=1))
            def collect(job):
                return dict(entries=[dict(kind='news',title=str(job['id']),url=f"https://example.com/rotation-item/{job['id']}",summary='actual',summary_basis='description')])
            for _ in range(21): worker.process_one(collect,lambda:NOW.isoformat())
            self.assertEqual(len(service.items(1,limit=100)['items']),20)
            for _ in range(21): worker.process_one(lambda _:dict(entries=[]),lambda:(NOW+timedelta(days=1)).isoformat())
            self.assertEqual(len(service.items(1,limit=100)['items']),21)

        def test_newest_first_dates_and_missing_date_feed_order(self):
            self.plan(); self.source()
            dated=[dict(kind='news',title=str(i),url=f'https://example.com/dated/{i}',published_at=f'2026-09-{i:02}T00:00:00+00:00',summary='actual',summary_basis='description') for i in range(30,0,-1)]
            worker.process_one(lambda _:dict(entries=dated),lambda:NOW.isoformat())
            self.assertEqual([i['title'] for i in service.items(1)['items']],[str(i) for i in range(30,10,-1)])
            with db.tx() as c: c.execute('UPDATE feed_sources SET next_fetch_at=NULL')
            undated=[dict(kind='news',title=str(i),url=f'https://example.com/undated/{i}',summary='actual',summary_basis='description') for i in (6,5,4)]
            worker.process_one(lambda _:dict(entries=undated),lambda:(NOW+timedelta(days=1)).isoformat())
            self.assertEqual([i['title'] for i in service.items(1)['items'][:3]],['6','5','4'])
        def test_cached_candidates_pause_fence_and_bound(self):
            self.plan(); source=self.source()
            entries=[dict(kind='news',title=str(i),url=f'https://example.com/pending/{i}',summary='actual',summary_basis='description') for i in range(250)]
            worker.process_one(lambda _:dict(entries=entries),lambda:NOW.isoformat())
            with db.tx(immediate=True) as c:
                self.assertLessEqual(c.execute('SELECT COUNT(*) FROM feed_pending_candidates').fetchone()[0],200)
                c.execute('UPDATE feed_sources SET next_fetch_at=NULL')
                job=store.claim(c,(NOW+timedelta(days=1)).isoformat(),300)
            service.toggle_source(1,source['id'],False)
            with db.tx(immediate=True) as c:
                self.assertEqual(store.complete(c,job,[],(NOW+timedelta(days=1)).isoformat()),0)
            self.assertEqual(len(service.items(1,saved_only=True)['items']),0)
        def test_pending_same_source_url_multiple_bots_share_one_budget(self):
            with db.tx() as c: c.execute("INSERT INTO bots(id,user_id,name,created_at) VALUES(3,1,'other','x')")
            self.plan(bot_ids=[1,3]); self.source(); self.source(3)
            entries=[dict(kind='news',title=str(i),url=f'https://example.com/bot-shared/{i}',summary='actual',summary_basis='description') for i in range(25)]
            for _ in range(2): worker.process_one(lambda _:dict(entries=entries),lambda:NOW.isoformat())
            first=service.items(1,limit=100)['items']; self.assertEqual(len(first),20)
            self.assertTrue(all({r['bot_id'] for r in i['recommended_by']}=={1,3} for i in first))
            following=(NOW+timedelta(days=1)).isoformat()
            for _ in range(2): worker.process_one(lambda _:dict(entries=[]),lambda:following)
            second=service.items(1,limit=100)['items']; self.assertEqual(len(second),25)
            self.assertTrue(all({r['bot_id'] for r in i['recommended_by']}=={1,3} for i in second))

        def test_same_url_multiple_bot_association(self):
            with db.tx() as c: c.execute("INSERT INTO bots(id,user_id,name,created_at) VALUES(3,1,'other','x')")
            self.plan(bot_ids=[1,3]); a=self.source(); b=self.source(3)
            self.publish(a); self.publish(b)
            found=service.items(1)['items']; self.assertEqual(len(found),1)
            self.assertEqual({r['bot_id'] for r in found[0]['recommended_by']},{1,3})
            self.assertEqual(len(service.items(1,bot_id=3)['items']),1)
        def test_inflight_pause_plan_source_and_bot_delete(self):
            for mode in ['plan','source','bot']:
                with self.subTest(mode=mode):
                    self.setUp(); self.plan(); s=self.source()
                    with db.tx(immediate=True) as c: job=store.claim(c,NOW.isoformat(),300)
                    if mode=='plan': self.plan(enabled=False,expected_version=1)
                    elif mode=='source': service.toggle_source(1,s['id'],False)
                    else:
                        with db.tx() as c: c.execute('DELETE FROM bots WHERE id=1')
                    with db.tx(immediate=True) as c:
                        self.assertEqual(store.complete(c,job,[dict(kind='news',title='x',url='https://example.com/a',summary='',summary_basis='description')],NOW.isoformat()),0)
                    self.assertEqual(service.items(1)['items'],[])
        def test_lease_expiry_stale_token_retry_304_refresh(self):
            self.plan(); self.source()
            with db.tx(immediate=True) as c:
                a=store.claim(c,NOW.isoformat(),10)
                self.assertIsNone(store.claim(c,NOW.isoformat(),10))
                b=store.claim(c,(NOW+timedelta(seconds=11)).isoformat(),10)
                self.assertNotEqual(a['lease_token'],b['lease_token'])
                self.assertEqual(store.complete(c,a,[],NOW.isoformat()),0)
                store.fail(c,b,'network_error',NOW.isoformat())
            source=service.sources(1)[0]; self.assertEqual(source['failure_count'],1)
            self.assertGreater(source['next_fetch_at'],NOW.isoformat())
            self.assertTrue(service.refresh(1))
            with db.tx(immediate=True) as c:
                c.execute("UPDATE feed_sources SET next_fetch_at=?",(NOW.isoformat(),))
                job=store.claim(c,NOW.isoformat(),300)
                store.complete(c,job,[],NOW.isoformat(),etag='abc',modified=None)
            self.assertEqual(service.sources(1)[0]['failure_count'],0)
        def test_memory_privacy_and_switches(self):
            with db.tx() as c:
                for i,(scope,bot,sensitivity,status,confirmed,expires,content) in enumerate([
                    ('bot',1,'normal','active','yes',None,'喜欢科技'),
                    ('bot',2,'normal','active','yes',None,'天文学'),
                    ('global',None,'health','active','yes',None,'天文学'),
                    ('global',None,'normal','active','yes','2000-01-01','天文学'),
                    ('global',None,'normal','candidate',None,None,'天文学')]):
                    c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,sensitivity,status,confirmed_at,expires_at,created_at,updated_at) VALUES(1,?,?,'preference',?,?,'memory_page',?,?,?,?, 'x','x')",(scope,bot,content,str(i),sensitivity,status,confirmed,expires))
            suggestion=service.suggest(1,[1],[])
            self.assertIn('科技',suggestion['topics']); self.assertNotIn('天文学',suggestion['topics'])
            self.assertNotIn('喜欢',str(suggestion))
            with db.tx() as c: c.execute('UPDATE users SET memory_enabled=0 WHERE id=1')
            self.assertEqual(service.suggest(1,[1],[])['topics'],[])
            self.assertIn('冷启动',service.suggest(1,[1],[])['basis'])
            with db.tx() as c:
                c.execute('UPDATE users SET memory_enabled=1 WHERE id=1'); c.execute("UPDATE bots SET memory_access='none' WHERE id=1")
            self.assertEqual(service.suggest(1,[1],[])['topics'],[])
        def test_suggestion_request_can_disable_memory_before_plan_save(self):
            with db.tx() as c:
                c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,sensitivity,status,confirmed_at,created_at,updated_at) VALUES(1,'bot',1,'preference','喜欢科技','hash','memory_page','normal','active','yes','x','x')")
            r=self.client.post('/api/feed/plan/suggest',json=dict(bot_ids=[1],topics=[],use_memory=False))
            self.assertEqual(r.status_code,200); self.assertEqual(r.json()['topics'],[])

        def test_context_is_bounded_and_no_message_side_effect(self):
            self.plan(); self.publish(self.source())
            item=service.items(1)['items'][0]
            result=service.context(1,item['id'],1)
            self.assertIn('https://example.com/a',result['prompt']); self.assertIn('外部资料',result['prompt'])
            with self.assertRaises(service.FeedError): service.context(1,item['id'],2)
            with db.tx() as c: self.assertEqual(c.execute('SELECT count(*) FROM messages').fetchone()[0],0)
        def test_source_count_limit_and_idempotent_at_limit(self):
            first=self.source()
            for i in range(29):
                service.add_source(1,dict(name='x',url=f'https://example.com/feed/{i}',kind='news',bot_id=1))
            self.assertEqual(self.source()['id'],first['id'])
            with self.assertRaises(service.FeedError) as caught:
                service.add_source(1,dict(name='x',url='https://example.com/over',kind='news',bot_id=1))
            self.assertEqual(caught.exception.status,422)
        def test_worker_fetch_runs_outside_write_transaction_and_restart(self):
            self.plan(); self.source()
            def fetch(job):
                # A second writer can commit while collection is in progress.
                with db.tx(immediate=True) as c: c.execute("UPDATE bots SET name='renamed' WHERE id=1")
                return dict(entries=[dict(kind='post',title='real',url='https://example.com/item',summary='source',summary_basis='description')])
            self.assertTrue(worker.process_one(fetch,lambda:NOW.isoformat()))
            self.assertEqual(len(service.items(1)['items']),1)
            self.assertFalse(worker.process_one(fetch,lambda:NOW.isoformat()))
            self.assertEqual(service.sources(1)[0]['last_success_at'],NOW.isoformat())
        def test_worker_304_and_failed_collection_backoff(self):
            from verabot.services.feed import collector
            self.plan(); self.source()
            with patch.object(fetcher,'fetch',return_value=(304,{'etag':'abc'},b'', 'https://example.com/feed')):
                self.assertTrue(worker.process_one(collector.collect,lambda:NOW.isoformat()))
            self.assertEqual(service.items(1)['items'],[])
            with db.tx() as c:
                c.execute("UPDATE feed_sources SET next_fetch_at=NULL")
                self.assertEqual(c.execute('SELECT etag FROM feed_sources').fetchone()[0],'abc')
            def failed(job): raise TimeoutError('private URL secret must not be retained')
            worker.process_one(failed,lambda:NOW.isoformat())
            source=service.sources(1)[0]
            self.assertEqual(source['failure_count'],1)
            self.assertNotIn('private',source['last_error'])
        def test_pause_reenable_does_not_accept_old_lease(self):
            self.plan(); s=self.source()
            with db.tx(immediate=True) as c: old=store.claim(c,NOW.isoformat(),300)
            service.toggle_source(1,s['id'],False); service.toggle_source(1,s['id'],True)
            with db.tx(immediate=True) as c:
                self.assertEqual(store.complete(c,old,[],NOW.isoformat()),0)
                self.assertIsNotNone(store.claim(c,NOW.isoformat(),300))

        def test_api_nullable_patch_dismiss_and_disabled_refresh(self):
            self.assertEqual(self.client.post('/api/feed/refresh').json(),{'queued':False})
            self.plan(); self.publish(self.source())
            item=service.items(1)['items'][0]
            r=self.client.patch(f"/api/feed/items/{item['id']}/state",json={'read':True,'saved':None})
            self.assertEqual(r.status_code,200); self.assertTrue(r.json()['read']); self.assertFalse(r.json()['saved'])
            service.state(1,item['id'],{'dismissed':True}); self.assertEqual(service.items(1)['items'],[])

    class ParsingTests(unittest.TestCase):
        def test_rss_atom_media_plaintext_evidence(self):
            rss=b'''<rss xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><item><title>A</title><link>https://example.com/a#x</link><description>&lt;b&gt;actual&lt;/b&gt;&lt;script&gt;evil&lt;/script&gt;</description><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/><itunes:duration>01:02:03</itunes:duration></item><item><title>B</title><link>https://example.com/b</link><content:encoded>&lt;p&gt;full body&lt;/p&gt;</content:encoded></item></channel></rss>'''
            items=parser.parse(rss,'https://example.com/feed','news')
            self.assertEqual(items[0]['summary'],'actual'); self.assertEqual(items[0]['kind'],'audio')
            self.assertEqual(items[0]['duration_seconds'],3723); self.assertEqual(items[0]['url'],'https://example.com/a')
            self.assertEqual(items[1]['summary_basis'],'body')
            atom=b'''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Post</title><link href="https://example.com/post"/><summary>source text</summary><author><name>Writer</name></author><published>2026-10-01T00:00:00Z</published><link rel="enclosure" type="video/mp4" href="https://example.com/v.mp4"/></entry></feed>'''
            item=parser.parse(atom,'https://example.com/feed','post')[0]
            self.assertEqual(item['kind'],'video'); self.assertEqual(item['author'],'Writer')
            self.assertEqual(item['summary_basis'],'description')
        def test_actual_socket_connect_uses_numeric_ip_and_original_tls_name(self):
            from unittest.mock import MagicMock
            raw=MagicMock(); context=MagicMock()
            with patch.object(fetcher.ssl,'create_default_context',return_value=context), patch.object(fetcher.socket,'socket',return_value=raw), patch.object(fetcher.socket,'getaddrinfo',side_effect=AssertionError('secondary DNS forbidden')):
                connection=fetcher.PinnedHTTPSConnection('example.com','93.184.216.34',5)
                connection.connect()
                raw.connect.assert_called_once_with(('93.184.216.34',443))
                context.wrap_socket.assert_called_once_with(raw,server_hostname='example.com')
        def test_article_and_media_urls_reject_unsafe_destinations(self):
            rss=b'<rss><channel><item><title>safe</title><link>https://example.com/a</link><description>actual</description><enclosure url="https://10.0.0.1/a.mp3" type="audio/mpeg"/></item><item><title>bad</title><link>javascript:alert(1)</link></item></channel></rss>'
            items=parser.parse(rss,'https://example.com/feed','news')
            self.assertEqual(len(items),1); self.assertIsNone(items[0]['media_url'])
            self.assertEqual(items[0]['kind'],'news')

        def test_mastodon_titleless_post_uses_actual_description(self):
            rss=b'<rss><channel><item><guid>https://example.com/post</guid><link>https://example.com/post</link><description>&lt;p&gt;New #Plushtodon colours&lt;/p&gt;</description></item></channel></rss>'
            entries=parser.parse(rss,'https://example.com/rss','post')
            self.assertEqual(len(entries),1)
            self.assertEqual(entries[0]['title'],'New #Plushtodon colours')
            self.assertEqual(entries[0]['summary_basis'],'description')
        def test_http_gzip_bounded_decompression_and_non_xml_rejection(self):
            import gzip,time
            from unittest.mock import MagicMock
            def request(body,headers):
                response=MagicMock(status=200)
                response.getheaders.return_value=list(headers.items())
                response.read1.side_effect=[body,b'']
                connection=MagicMock(); connection.getresponse.return_value=response
                with patch.object(fetcher,'PinnedHTTPSConnection',return_value=connection):
                    return fetcher.request_ip('https://example.com/rss','93.184.216.34',{},time.monotonic()+3)
            xml=b'<rss><channel/></rss>'
            result=request(gzip.compress(xml),{'Content-Encoding':'gzip','Content-Type':'application/rss+xml'})
            self.assertEqual(result[2],xml)
            with self.assertRaises(ValueError): request(gzip.compress(b'x'*2100000),{'Content-Encoding':'gzip'})
            with self.assertRaises(ValueError): request(b'<html/>',{'Content-Type':'text/html'})
            with self.assertRaises(ValueError): request(b'',{'Content-Length':'2000001'})

        def test_reject_entities_oversize_invalid_item_and_private_url(self):
            for xml in [b'<!DOCTYPE x [<!ENTITY a "x">]><rss/>',b'<?xml version="1.0"?><!DOCTYPE x><rss/>',b'x'*2100000]:
                with self.assertRaises(ValueError): parser.parse(xml,'https://example.com','news')
            for url in ['http://example.com','https://user:pass@example.com','https://localhost/a','https://127.0.0.1','https://[::1]','https://10.1.1.1','https://example.com:444/','https://example.com/\nHost:x']:
                with self.subTest(url=url), self.assertRaises(ValueError): fetcher.validate_url(url)
        def test_opt_in_doh_pins_bootstrap_and_rejects_private_answers(self):
            import os,json
            with patch.dict(os.environ,{'VERABOT_FEED_DOH':'1'}), patch.object(fetcher,'request_ip',return_value=(200,{},json.dumps({'Status':0,'Answer':[{'type':1,'data':'93.184.216.34'}]}).encode())) as request:
                result=fetcher.resolve('https://example.com/private/path?secret=value')
                self.assertEqual(result[1],'93.184.216.34')
                self.assertEqual(request.call_args.args[1],'1.1.1.1')
                self.assertIn('name=example.com',request.call_args.args[0])
                self.assertNotIn('secret',request.call_args.args[0])
            with patch.dict(os.environ,{'VERABOT_FEED_DOH':'1'}), patch.object(fetcher,'request_ip',return_value=(200,{},b'{"Status":0,"Answer":[{"type":1,"data":"10.0.0.1"}]}')):
                with self.assertRaises(ValueError): fetcher.resolve('https://example.com')

        def test_dns_rebinding_pins_connection_and_redirect_rechecks(self):
            addresses=[(2,1,6,'',('93.184.216.34',443))]
            with patch.object(fetcher.socket,'getaddrinfo',return_value=addresses), patch.object(fetcher,'request_ip',return_value=(200,{},b'<rss/>')) as request:
                result=fetcher.fetch('https://example.com/rss')
                self.assertEqual(result[0],200); self.assertEqual(request.call_args.args[1],'93.184.216.34')
            with patch.object(fetcher.socket,'getaddrinfo',return_value=addresses), patch.object(fetcher,'request_ip',return_value=(302,{'location':'https://127.0.0.1/'},b'')):
                with self.assertRaises(ValueError): fetcher.fetch('https://example.com/rss')
            with patch.object(fetcher.socket,'getaddrinfo',return_value=[(2,1,6,'',('10.0.0.1',443))]):
                with self.assertRaises(ValueError): fetcher.fetch('https://example.com/rss')

if __name__=='__main__': unittest.main()
