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
