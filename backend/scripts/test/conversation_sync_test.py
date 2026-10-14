"""Sync pages keep revisions and contents in one SQLite snapshot."""
import unittest
from contextlib import contextmanager
from unittest.mock import patch
from uuid import uuid4
import group_store_test as fixture
from verabot import db
from verabot.db import group_store, message_store
from verabot.api.routers.chat import messages_sync


class SyncTests(unittest.TestCase):
    def setUp(self):
        with db.tx() as c:
            c.execute("PRAGMA journal_mode=WAL")

    @contextmanager
    def interleaved_read(self, mutation):
        original = db.tx
        class Cursor:
            def __init__(self, cursor): self.cursor = cursor
            def fetchone(self):
                row = self.cursor.fetchone()
                with original() as writer: mutation(writer)
                return row
        class Connection:
            def __init__(self, conn): self.conn = conn
            def execute(self, sql, *args):
                cursor = self.conn.execute(sql, *args)
                return Cursor(cursor) if sql.startswith("SELECT revision FROM") else cursor
        @contextmanager
        def tx(*args, **kwargs):
            with original(*args, **kwargs) as c: yield Connection(c)
        with patch.object(db, "tx", tx), patch.object(group_store, "tx", tx), patch.object(message_store, "tx", tx): yield

    def test_private_revision_and_content_share_snapshot(self):
        mid = db.add_message(fixture.UID, fixture.BOTS[0], 'user', 'before')
        with self.interleaved_read(lambda c: c.execute("UPDATE messages SET content='after' WHERE id=?", (mid,))):
            page = messages_sync(fixture.BOTS[0], limit=100, before_id=None, expected_revision=None,
                                 user={"id": fixture.UID})
        self.assertEqual(next(m['content'] for m in page['messages'] if m['id']==mid), 'before')
        fresh = messages_sync(fixture.BOTS[0], limit=100, before_id=None, expected_revision=None,user={"id":fixture.UID})
        self.assertGreater(fresh['revision'], page['revision'])

    def test_group_clear_during_page_keeps_old_snapshot(self):
        group = group_store.create_group(fixture.UID, 'sync', fixture.BOTS[:2])
        # The test reads historical data; v2 rejects legacy execution submissions.
        with db.tx() as c:
            tid=c.execute("INSERT INTO chat_group_turns(user_id,group_id,client_request_id,request_hash,mode,status,created_at) VALUES(?,?,'sync-fixture','hash','single','completed','now')",(fixture.UID,group['id'])).lastrowid
            c.execute("INSERT INTO chat_group_messages(user_id,group_id,turn_id,role,content,status,created_at) VALUES(?,?,?,'user','before','completed','now')",(fixture.UID,group['id'],tid))
        with self.interleaved_read(lambda c: c.execute('DELETE FROM chat_group_turns WHERE group_id=?', (group['id'],))):
            page = group_store.sync_messages(fixture.UID, group['id'])
        self.assertEqual([m['content'] for m in page['messages']], ['before'])
        fresh=group_store.sync_messages(fixture.UID, group['id'])
        self.assertEqual(fresh['messages'], [])
        self.assertGreater(fresh['revision'],page['revision'])


if __name__ == '__main__': unittest.main()
