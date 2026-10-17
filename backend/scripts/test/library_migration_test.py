import unittest
from library_test_support import setup, attached, db, repo

class MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client, cls.h, cls.uid, _, _, cls.bots = setup()

    def test_migration_preserves_attached_and_ignores_pending(self):
        from verabot.db.migrations import SCHEMA_VERSION
        self.assertGreater(SCHEMA_VERSION, 32, 'independent library migration missing')
        aid, _ = attached(self.uid, self.bots[0])
        pending = repo.create_file(self.uid, self.bots[0], b'pending', 'pending.txt')['id']
        from verabot.db.migrations.v033_independent_library import migrate
        with db.tx() as c:
            migrate(c, 32)
            before = c.execute('SELECT id FROM library_items WHERE user_id=? ORDER BY id', (self.uid,)).fetchall()
            migrate(c, 32)
            after = c.execute('SELECT id FROM library_items WHERE user_id=? ORDER BY id', (self.uid,)).fetchall()
            self.assertEqual([r[0] for r in before], [r[0] for r in after])
            self.assertIn(aid, [r[0] for r in after])
            self.assertNotIn(pending, [r[0] for r in after])

    def test_legacy_text_metadata_matches_preserved_server_bytes(self):
        import json,hashlib
        aid,_=attached(self.uid,self.bots[0],b'original text')
        row=repo.get(self.uid,aid)
        stored=b'original\n\ntext'
        repo.get_store().put(row['storage_key'],stored)
        with db.tx() as c:
            raw=json.loads(c.execute('SELECT payload FROM library_items WHERE id=?',(aid,)).fetchone()[0])
            raw['text_key']=raw['storage_key']
            c.execute('UPDATE library_items SET payload=? WHERE id=?',(json.dumps(raw),aid))
        from verabot.db.migrations.v034_legacy_text_metadata import migrate
        with db.tx() as c: migrate(c,33)
        from verabot.services import library
        item=library.get_item(self.uid,aid)
        self.assertEqual(item['bytes'],len(stored))
        self.assertEqual(item['sha256'],hashlib.sha256(stored).hexdigest())
        self.assertEqual(repo.get_store().path(row['storage_key']).read_bytes(),stored)
    def test_upgrade_backup_restores_pre_v33_database(self):
        import sqlite3,tempfile
        from pathlib import Path
        from verabot.db.migrations.v033_independent_library import backup_before_v33
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"old.db"
            with sqlite3.connect(path) as c:
                c.execute("CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value TEXT)")
                c.execute("INSERT INTO schema_meta VALUES('version','32')")
                c.execute("CREATE TABLE sample(value TEXT)")
                c.execute("INSERT INTO sample VALUES('preserved')")
            backup=backup_before_v33(path)
            self.assertTrue(backup.is_file())
            with sqlite3.connect(backup) as c: self.assertEqual(c.execute("SELECT value FROM sample").fetchone()[0],"preserved")

    def test_remote_v33_without_library_backfills_on_upgrade(self):
        import sqlite3
        from verabot.db.database import DB_PATH
        from verabot.db.migrations import apply
        aid, _ = attached(self.uid, self.bots[0], b'remote-v33-original')
        # Reconstruct the remote v33 lineage: attachments exist, library does not.
        with sqlite3.connect(DB_PATH) as source:
            c = sqlite3.connect(':memory:')
            source.backup(c)
        try:
            c.row_factory = sqlite3.Row
            for name in ('library_source_private_deleted', 'library_source_group_deleted', 'library_link_deleted'):
                c.execute(f'DROP TRIGGER IF EXISTS {name}')
            for name in ('library_upload_keys', 'library_changes', 'library_sources', 'library_unlinked', 'library_bot_links', 'library_items'):
                c.execute(f'DROP TABLE {name}')
            c.execute("UPDATE schema_meta SET value='33' WHERE key='version'")
            apply(c)
            self.assertEqual(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0], str(db.SCHEMA_VERSION))
            self.assertIsNotNone(c.execute('SELECT id FROM library_items WHERE id=?', (aid,)).fetchone())
            self.assertIsNotNone(c.execute('SELECT item_id FROM library_sources WHERE item_id=?', (aid,)).fetchone())
            before = c.execute('SELECT COUNT(*) FROM library_changes').fetchone()[0]
            apply(c)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM library_changes').fetchone()[0], before)
        finally:
            c.close()

    def test_retained_library_bytes_count_toward_quota(self):
        from verabot.db.attachment_store import bytes_used
        aid, mid = attached(self.uid, self.bots[0], b"quota-original")
        with db.tx() as c: before = bytes_used(c,self.uid)
        db.delete_message(self.uid,self.bots[0],mid)
        with db.tx() as c: self.assertEqual(bytes_used(c,self.uid),before)

    def test_reconcile_keeps_library_resource(self):
        from verabot.services import library
        aid, mid = attached(self.uid, self.bots[0])
        original = repo.get(self.uid, aid)
        db.delete_message(self.uid, self.bots[0], mid)
        repo.delete_files(repo.file_keys(original))
        repo.reconcile(now=9999999999)
        item = library.get_item(self.uid, aid)
        self.assertEqual(item['availability'], 'available')
        self.assertEqual(repo.get_store().path(original['storage_key']).read_bytes(), b'library original')
        repo.get_store().delete(original['storage_key'])
        self.assertEqual(library.get_item(self.uid, aid)['availability'], 'missing')

if __name__ == '__main__': unittest.main()
