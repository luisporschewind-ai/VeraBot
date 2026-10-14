#!/usr/bin/env python3
"""Local notification durable feed: no provider or shared database access."""
import os, sys, tempfile, subprocess, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
os.environ['VERABOT_DB'] = str(Path(tempfile.mkdtemp(prefix='vb_notification_events_')) / 'test.db')
os.environ['VERABOT_SCHEDULER'] = '0'
os.environ.setdefault('DEEPSEEK_API_KEY', 'test-unused')
sys.path.insert(0, str(ROOT))
from fastapi.testclient import TestClient
from verabot import db
from verabot.main import app
from verabot.services.notify.dispatcher import notify

db.init_db()
client = TestClient(app)
class NotificationEventsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        a = client.post('/api/auth/register', json={'username':'event-a','password':'pw123456'}).json()
        b = client.post('/api/auth/register', json={'username':'event-b','password':'pw123456'}).json()
        cls.uid = a['user']['id']; cls.other = b['user']['id']
        cls.headers = {'Authorization': 'Bearer ' + a['token']}
        cls.bot = client.post('/api/bots', headers=cls.headers, json={'name':'Events'}).json()['id']
    def setUp(self):
        client.patch('/api/notification-settings', headers=self.headers, json={
            'enabled':True, 'preview':'title', 'quiet_enabled':False, 'muted_bots':[],
            'categories':{'reminder':True, 'bot_message':True, 'task_result':True, 'system':True}})
        client.post('/api/notifications/read-all', headers=self.headers, json={})

    def feed(self, **params):
        response = client.get('/api/notification-events', headers=self.headers, params=params)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()
    def test_durable_page_and_isolation(self):
        initial = self.feed()['next_cursor']
        notify(self.other, category='system', title='other', dedupe_key='foreign')
        first = notify(self.uid, category='system', title='one', dedupe_key='one')
        second = notify(self.uid, category='system', title='two', dedupe_key='two')
        page = self.feed(after=initial, limit=1)
        self.assertTrue(page['has_more'])
        third = notify(self.uid, category='system', title='three', dedupe_key='three')
        rest = self.feed(after=page['next_cursor'], through=page['upper_bound'])
        self.assertEqual([e['notification_id'] for e in page['events'] + rest['events']], [first['id'], second['id']])
        self.assertFalse(rest['has_more'])
        self.assertEqual(self.feed(after=rest['next_cursor'])['events'][0]['notification_id'], third['id'])
    def test_transaction_rollback_and_other_process(self):
        initial = self.feed()['next_cursor']
        try:
            with db.tx(immediate=True) as c:
                notify(self.uid, category='system', title='rollback', dedupe_key='rollback', conn=c)
                raise RuntimeError('rollback')
        except RuntimeError: pass
        self.assertEqual(self.feed(after=initial)['events'], [])
        code = f"from verabot.services.notify.dispatcher import notify; notify({self.uid},category='system',title='worker',dedupe_key='worker')"
        subprocess.run([sys.executable, '-c', code], cwd=ROOT, check=True, env=os.environ.copy(), capture_output=True)
        self.assertEqual(self.feed(after=initial)['events'][0]['notification']['title'], 'worker')
    def test_changes_deletion_and_future_cursor(self):
        note = notify(self.uid, category='system', title='change', dedupe_key='change')
        initial = self.feed()['next_cursor']
        client.post(f"/api/notifications/{note['id']}/read", headers=self.headers)
        self.assertIsNotNone(self.feed(after=initial)['events'][0]['notification']['read_at'])
        initial = self.feed()['next_cursor']
        client.delete(f"/api/notifications/{note['id']}", headers=self.headers)
        self.assertEqual(self.feed(after=initial)['events'][0]['operation'], 'deleted')
        self.assertTrue(self.feed(after=999999999)['reset_required'])
    def test_task_result_policy_and_preview(self):
        client.patch('/api/notification-settings', headers=self.headers, json={'categories': {'task_result': False}, 'preview':'none'})
        note = notify(self.uid, category='task_result', title='Secret result', body='Secret body', bot_id=self.bot,
                      message_id=None, link=f'bot/{self.bot}/chat', dedupe_key='task:1', source_kind='scheduled_task', source_id='1')
        self.assertEqual(note['category'], 'task_result')
        self.assertEqual(note['suppression_reason'], 'category_off')
        self.assertNotIn('Secret', str(note))
        self.assertEqual(notify(self.uid, category='task_result', title='again', dedupe_key='task:1')['id'], note['id'])
        filtered = client.get('/api/notifications', headers=self.headers, params={'category':'task_result'}).json()
        self.assertEqual(filtered['notifications'][0]['id'], note['id'])
        self.assertEqual(client.get('/api/notifications/summary', headers=self.headers).json()['by_category']['task_result'], 1)
        client.patch('/api/notification-settings', headers=self.headers, json={'categories': {'task_result': True}, 'preview':'title'})
    def test_account_cascade_and_migration_reopen(self):
        user = client.post('/api/auth/register', json={'username':'event-delete','password':'pw123456'}).json()['user']['id']
        notify(user, category='system', title='delete me', dedupe_key='delete-user')
        with db.tx() as c:
            before = c.execute('SELECT COUNT(*) FROM notification_events').fetchone()[0]
        db.init_db()
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM notification_events').fetchone()[0], before)
            c.execute('DELETE FROM users WHERE id=?', (user,))
            self.assertEqual(c.execute('SELECT COUNT(*) FROM notification_events WHERE user_id=?', (user,)).fetchone()[0], 0)
            self.assertEqual(c.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_local_snapshot_and_worker_schema_gate(self):
        note = notify(self.uid, category='system', title='snapshot', dedupe_key='snapshot')
        response = client.post('/api/notifications/local-state', headers=self.headers, json={'ids':[note['id'], 99999999]})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual([n['id'] for n in response.json()['notifications']], [note['id']])
        with db.tx() as c: c.execute("UPDATE schema_meta SET value='29' WHERE key='version'")
        try:
            for module in ('owned_tasks', 'scheduled_tasks'):
                result = subprocess.run([sys.executable, '-m', 'verabot.services.' + module, '--once'], cwd=ROOT,
                    env=os.environ.copy(), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, module)
                self.assertIn('v30', result.stderr)
        finally:
            with db.tx() as c: c.execute("UPDATE schema_meta SET value='30' WHERE key='version'")

    def test_recovered_task_without_result_notifies_once(self):
        from verabot.db import owned_task_store
        from verabot.services.owned_tasks import delivery
        with db.tx(immediate=True) as c:
            task = owned_task_store.create(c, self.uid, {'id':self.bot, 'name':'Events'},
                {'goal':'recover task', 'completion_criteria':'done'}, 'recovery-notification', 'hash', {})
            owned_task_store.invalidate(c, task, 'interrupted', 'execution_unknown')
        delivery.flush(); delivery.flush()
        notes = client.get('/api/notifications', headers=self.headers, params={'category':'task_result'}).json()['notifications']
        matched = [n for n in notes if n['source_kind']=='owned_task' and n['source_id']==str(task['id'])]
        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0]['source_state'], 'interrupted')
        client.delete(f"/api/notifications/{matched[0]['id']}", headers=self.headers)
        delivery.flush()
        remaining = client.get('/api/notifications', headers=self.headers, params={'category':'task_result'}).json()['notifications']
        self.assertFalse(any(n['source_kind']=='owned_task' and n['source_id']==str(task['id']) for n in remaining))

    def test_pending_task_summary_excludes_resolved_tasks(self):
        from verabot.db import owned_task_store
        from verabot.services.owned_tasks import delivery
        with db.tx(immediate=True) as c:
            task = owned_task_store.create(c, self.uid, {'id':self.bot, 'name':'Events'},
                {'goal':'waiting task', 'completion_criteria':'done'}, 'waiting-summary', 'hash', {})
            task = owned_task_store.invalidate(c, task, 'awaiting_user', 'needs_input')
        delivery.flush()
        self.assertEqual(client.get('/api/notifications/summary', headers=self.headers).json()['pending_action_count'], 1)
        with db.tx(immediate=True) as c: owned_task_store.invalidate(c, task, 'stopped')
        self.assertEqual(client.get('/api/notifications/summary', headers=self.headers).json()['pending_action_count'], 0)

    def test_atomic_message_publication_and_delivery_receipt(self):
        from verabot.services.notify.dispatcher import report_event
        cursor = self.feed()['next_cursor']
        try:
            with db.tx(immediate=True) as c:
                mid = db.add_message(self.uid, self.bot, 'assistant', 'result', conn=c)
                notify(self.uid, category='bot_message', title='reply', bot_id=self.bot, message_id=mid,
                       dedupe_key=f'atomic:{mid}', source_kind='chat_reply', conn=c)
                raise RuntimeError('rollback')
        except RuntimeError: pass
        self.assertEqual(self.feed(after=cursor)['events'], [])
        note = notify(self.uid, category='bot_message', title='reply', bot_id=self.bot, dedupe_key='receipt', source_kind='chat_reply')
        result = report_event(self.uid, note['id'], event='scheduled', channel='local', device_id='new-device', at=None)
        self.assertEqual(result['state'], 'scheduled')
        report_event(self.uid, note['id'], event='failed', channel='local', device_id='new-device', at=None)
        retried = report_event(self.uid, note['id'], event='scheduled', channel='local', device_id='new-device', at=None)
        self.assertEqual(retried['state'], 'scheduled')

    def test_reply_notification_does_not_use_proactive_limit(self):
        for i in range(5):
            note = notify(self.uid, category='bot_message', title='reply', bot_id=self.bot, dedupe_key=f'reply:{i}', source_kind='chat_reply')
            self.assertIsNone(note['suppression_reason'])
        self.assertEqual(self.feed()['events'], []) # bootstrap does not replay old alerts

if __name__ == '__main__': unittest.main()
