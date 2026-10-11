#!/usr/bin/env python3
"""群存储/管理回归：临时数据库，无模型与正式数据。"""
import concurrent.futures
import json
import os
import sqlite3
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from uuid import uuid4

TMP = tempfile.TemporaryDirectory(prefix="vb_groups_")
os.environ["VERABOT_DB"] = str(Path(TMP.name) / "groups.db")
os.environ["VERABOT_DATA_DIR"] = TMP.name
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from fastapi.testclient import TestClient
from verabot import db
from verabot.main import app

db.init_db()
cli = TestClient(app)
def account(name):
    r = cli.post('/api/auth/register', json={'username': name, 'password': 'password123'}).json()
    return r['user']['id'], {'Authorization': 'Bearer ' + r['token']}
UID, H = account('group-owner')
OTHER, H2 = account('group-other')
BOTS = [cli.post('/api/bots', headers=H, json={'name': n, 'persona': '测试伙伴'}).json()['id']
        for n in ['A', 'B', 'C', 'D', 'E']]
FOREIGN = cli.post('/api/bots', headers=H2, json={'name': 'Other'}).json()['id']

class GroupTests(unittest.TestCase):
    def setUp(self):
        with db.tx() as c:
            if c.execute("SELECT 1 FROM sqlite_master WHERE name='chat_groups'").fetchone():
                c.execute('DELETE FROM chat_groups')

    def create(self, ids=None, name='测试群'):
        ids = BOTS[:3] if ids is None else ids
        return cli.post('/api/groups', headers=H,
                        json={'name': name, 'bot_ids': ids, 'default_bot_id': ids[0] if ids else None})

    def group(self):
        r = self.create()
        self.assertEqual(r.status_code, 201, r.text)
        return r.json()

    def claim(self, group, request=None):
        from verabot.db import group_store
        return group_store.claim_turn(UID, group['id'], request or {
            'client_request_id': str(uuid4()), 'message': '问题', 'mode': 'single', 'target_bot_id': BOTS[0]})

    def test_create_group(self):
        g = self.group()
        self.assertEqual([m['bot_id'] for m in g['members']], BOTS[:3])
        self.assertEqual(g['default_bot_id'], BOTS[0])
        self.assertEqual(g['members'][0]['name'], 'A')
        self.assertEqual(cli.get('/api/groups', headers=H).json()['groups'][0]['id'], g['id'])

    def test_validation_and_atomic_creation(self):
        for ids in [BOTS[:1], BOTS, [BOTS[0], BOTS[0]], [BOTS[0], FOREIGN]]:
            self.assertEqual(self.create(ids).status_code, 422)
        for name in ['   ', 'x' * 65]:
            self.assertEqual(self.create(name=name).status_code, 422)
        self.assertEqual(cli.get('/api/groups', headers=H).json()['groups'], [])
        self.assertEqual(self.create(BOTS[:2]).status_code, 201)
        self.assertEqual(self.create(BOTS[:4]).status_code, 201)

    def test_limit(self):
        for _ in range(10): self.assertEqual(self.create().status_code, 201)
        self.assertEqual(self.create().status_code, 422)

    def test_owner_isolation(self):
        g = self.group()
        for method, suffix, body in [('GET', '', None), ('PATCH', '', {'name': 'wrong'}),
                                    ('DELETE', '', None), ('GET', '/messages', None), ('DELETE', '/messages', None)]:
            r = cli.request(method, f"/api/groups/{g['id']}{suffix}", headers=H2, json=body)
            self.assertEqual(r.status_code, 404, r.text)
        self.assertEqual(cli.get('/api/groups', headers=H2).json()['groups'], [])

    def test_patch_and_delete(self):
        g = self.group(); path = f"/api/groups/{g['id']}"
        r = cli.patch(path, headers=H, json={'name': ' 新群 ', 'default_bot_id': BOTS[1]})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['name'], '新群')
        self.assertEqual(r.json()['default_bot_id'], BOTS[1])
        self.assertEqual(cli.patch(path, headers=H, json={'default_bot_id': BOTS[4]}).status_code, 422)
        self.assertEqual(cli.delete(path, headers=H).status_code, 200)
        self.assertEqual(cli.get(path, headers=H).status_code, 404)

    def test_idempotency_and_busy(self):
        from verabot.db import group_store
        g = self.group()
        request = {'client_request_id': str(uuid4()), 'message': '问题', 'mode': 'single'}
        t = self.claim(g, request)
        for changed, code in [(False, 'request_exists'), (True, 'idempotency_conflict')]:
            with self.assertRaises(group_store.GroupStoreError) as error:
                self.claim(g, {**request, 'message': '不同问题' if changed else '问题'})
            self.assertEqual(error.exception.code, code)
            self.assertEqual(error.exception.turn_id, t['id'])
        with self.assertRaises(group_store.GroupStoreError) as error: self.claim(g)
        self.assertEqual(error.exception.code, 'group_busy')
        self.assertEqual(len(cli.get(f"/api/groups/{g['id']}/messages", headers=H).json()['messages']), 1)

    def test_concurrent_claim(self):
        from verabot.db import group_store
        g = self.group(); start = threading.Barrier(2)
        def claim():
            start.wait(timeout=5)
            try: self.claim(g); return 'ok'
            except group_store.GroupStoreError as e: return e.code
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: claim(), range(2)))
        self.assertCountEqual(results, ['ok', 'group_busy'])

    def test_active_management_and_stop_isolation(self):
        g = self.group(); t = self.claim(g); path = f"/api/groups/{g['id']}"
        self.assertEqual(cli.patch(path, headers=H, json={'name': '忙'}).status_code, 409)
        self.assertEqual(cli.delete(path, headers=H).status_code, 409)
        self.assertEqual(cli.delete(path + '/messages', headers=H).status_code, 409)
        for suffix in [f"/turns/{t['id']}", f"/turns/{t['id']}/stop"]:
            method = 'POST' if suffix.endswith('stop') else 'GET'
            self.assertEqual(cli.request(method, path + suffix, headers=H2).status_code, 404)
        stop = cli.post(path + f"/turns/{t['id']}/stop", headers=H)
        self.assertEqual(stop.status_code, 200)
        self.assertTrue(stop.json()['cancel_requested'])
        self.assertEqual(cli.post(path + f"/turns/{t['id']}/stop", headers=H).json(), stop.json())

    def test_usage_finalize_once_and_pagination(self):
        from verabot.db import group_store
        g = self.group()
        for i in range(4):
            t = self.claim(g)
            msg = group_store.start_reply(UID, g['id'], t['id'], g['members'][0]['id'])
            for _ in range(2):
                group_store.save_reply(UID, msg['id'], f'回复{i}', 'completed', {'total_tokens': 7}, finalize=True)
            group_store.finish_turn(UID, g['id'], t['id'], 'completed')
        path = f"/api/groups/{g['id']}/messages"
        newest = cli.get(path, headers=H, params={'limit': 3}).json()
        older = cli.get(path, headers=H, params={'limit': 3, 'before_id': newest['next_before_id']}).json()
        self.assertEqual(len(newest['messages']), 3)
        self.assertEqual(len(older['messages']), 3)
        self.assertTrue(max(m['id'] for m in older['messages']) < min(m['id'] for m in newest['messages']))
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM usage_log WHERE user_id=? AND kind='group_chat'", (UID,)).fetchone()[0], 4)
        self.assertEqual(cli.delete(path, headers=H).status_code, 200)
        self.assertEqual(cli.get(path, headers=H).json()['messages'], [])

    def test_pagination_cap_and_full_walk(self):
        from verabot.db import group_store
        g = self.group()
        for _ in range(52):
            turn = self.claim(g)
            message = group_store.start_reply(UID, g['id'], turn['id'], g['members'][0]['id'])
            group_store.save_reply(UID, message['id'], '回复', 'completed', None, finalize=True)
            group_store.finish_turn(UID, g['id'], turn['id'], 'completed')
        path = f"/api/groups/{g['id']}/messages"
        self.assertEqual(cli.get(path, headers=H, params={'limit': 101}).status_code, 422)
        first = cli.get(path, headers=H, params={'limit': 100}).json()
        self.assertEqual(len(first['messages']), 100)
        older = cli.get(path, headers=H, params={'limit': 100, 'before_id': first['next_before_id']}).json()
        self.assertEqual(len(older['messages']), 4)
        self.assertIsNone(older['next_before_id'])
        ids = [m['id'] for m in older['messages'] + first['messages']]
        self.assertEqual(ids, sorted(set(ids)))
        self.assertEqual(len(ids), 104)

    def test_deleted_member_preserves_history(self):
        from verabot.db import group_store
        g = self.group(); t = self.claim(g)
        msg = group_store.start_reply(UID, g['id'], t['id'], g['members'][0]['id'])
        group_store.save_reply(UID, msg['id'], '保留', 'completed', None, finalize=True)
        group_store.finish_turn(UID, g['id'], t['id'], 'completed')
        # Dedicated disposable Bot, so other tests keep their fixtures.
        deleted = cli.post('/api/bots', headers=H, json={'name': 'Disposable'}).json()['id']
        g2 = self.create([deleted, BOTS[1]]).json()
        t2 = self.claim(g2, {'client_request_id': str(uuid4()), 'message': '问题', 'mode': 'single'})
        historical = group_store.start_reply(UID, g2['id'], t2['id'], g2['members'][0]['id'])
        group_store.save_reply(UID, historical['id'], '旧伙伴的答案', 'completed', None, finalize=True)
        group_store.finish_turn(UID, g2['id'], t2['id'], 'completed')
        cli.delete(f'/api/bots/{deleted}', headers=H)
        history = cli.get(f"/api/groups/{g2['id']}/messages", headers=H).json()['messages']
        self.assertEqual(history[-1]['sender_name'], 'Disposable')
        self.assertEqual(history[-1]['content'], '旧伙伴的答案')
        self.assertEqual(history[-1]['member_id'], g2['members'][0]['id'])
        restored = cli.get(f"/api/groups/{g2['id']}", headers=H).json()
        self.assertIsNone(restored['members'][0]['bot_id'])
        self.assertEqual(restored['members'][0]['name'], 'Disposable')
        self.assertFalse(restored['members'][0]['available'])
        self.assertEqual(restored['default_bot_id'], BOTS[1])

    def test_no_active_members_is_read_only(self):
        from verabot.db import group_store
        ids = [cli.post('/api/bots', headers=H, json={'name': n}).json()['id'] for n in ['Gone1', 'Gone2']]
        g = self.create(ids).json()
        for bid in ids: cli.delete(f'/api/bots/{bid}', headers=H)
        restored = cli.get(f"/api/groups/{g['id']}", headers=H).json()
        self.assertTrue(restored['read_only'])
        self.assertIsNone(restored['default_bot_id'])
        with self.assertRaises(group_store.GroupStoreError) as error:
            self.claim(g)
        self.assertEqual(error.exception.code, 'group_read_only')
        self.assertEqual(cli.get(f"/api/groups/{g['id']}/messages", headers=H).json()['messages'], [])

    def test_migration_preserves_private_history(self):
        from verabot.db.database import connect
        from verabot.db.migrations import apply
        mid = db.add_message(UID, BOTS[0], 'user', '私聊保留')
        # Reconstruct v19 in an isolated copy, then exercise the real upgrade twice.
        old = sqlite3.connect(':memory:')
        with connect() as original: original.backup(old)
        for table in ('chat_group_messages', 'chat_group_turns', 'chat_group_members', 'chat_groups'):
            old.execute(f'DROP TABLE {table}')
        old.execute("UPDATE schema_meta SET value='19' WHERE key='version'")
        old.commit()
        old.execute('PRAGMA foreign_keys=ON')
        with old: apply(old)
        with old: apply(old)
        self.assertEqual(old.execute('SELECT content FROM messages WHERE id=?', (mid,)).fetchone()[0], '私聊保留')
        self.assertEqual(old.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0], '20')
        self.assertEqual(old.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name LIKE 'chat_group%'").fetchone()[0], 4)
        old.close()

if __name__ == '__main__': unittest.main(verbosity=2)
