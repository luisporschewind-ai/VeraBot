import sqlite3
from scheduled_task_test_support import DBTest, db

class StoreTests(DBTest):
    def test_migration_idempotent(self):
        db.init_db()
        with db.tx() as c:
            tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            self.assertTrue({'scheduled_tasks','scheduled_task_runs','scheduled_task_attempts'} <= tables)
            self.assertIn('source_kind', {r[1] for r in c.execute('PRAGMA table_info(messages)')})
            self.assertEqual(int(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]), 21)
    def test_unique_occurrence_and_one_active_run(self):
        with db.tx() as c:
            c.execute("INSERT INTO scheduled_tasks(user_id,bot_id,title,instruction,state,timezone,start_at_utc,created_at,updated_at) VALUES(1,1,'a','b','active','Asia/Shanghai','x','x','x')")
            c.execute("INSERT INTO scheduled_task_runs(task_id,user_id,bot_id,trigger,scheduled_for_utc,schedule_revision,state,task_snapshot_json,available_at,created_at) VALUES(1,1,1,'scheduled','x',1,'queued','{}','x','x')")
            with self.assertRaises(sqlite3.IntegrityError):
                c.execute("INSERT INTO scheduled_task_runs(task_id,user_id,bot_id,trigger,scheduled_for_utc,schedule_revision,state,task_snapshot_json,available_at,created_at) VALUES(1,1,1,'scheduled','y',1,'queued','{}','x','x')")
            c.execute("UPDATE scheduled_task_runs SET state='succeeded'")
            with self.assertRaises(sqlite3.IntegrityError):
                c.execute("INSERT INTO scheduled_task_runs(task_id,user_id,bot_id,trigger,scheduled_for_utc,schedule_revision,state,task_snapshot_json,available_at,created_at) VALUES(1,1,1,'scheduled','x',1,'queued','{}','x','x')")
