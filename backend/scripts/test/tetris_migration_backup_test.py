"""v38 backup against a temporary SQLite database only."""
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot.db.migrations.v038_tetris_sessions import backup_before_v38,migrate
class BackupTests(unittest.TestCase):
    def test_backup_precedes_migration_and_is_not_repeated_for_v38(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"migration.db"
            c=sqlite3.connect(path)
            c.executescript("CREATE TABLE schema_meta(key TEXT PRIMARY KEY,value TEXT);INSERT INTO schema_meta VALUES('version','37');CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY);INSERT INTO users VALUES(1);")
            c.commit()
            with patch('verabot.db.database.DB_PATH',path):backup_before_v38()
            backups=list(path.parent.glob('*.bak-before-v38-*'))
            self.assertEqual(len(backups),1)
            restored=sqlite3.connect(backups[0])
            self.assertEqual(restored.execute('PRAGMA integrity_check').fetchone()[0],'ok')
            self.assertEqual(restored.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0],'37')
            self.assertEqual(restored.execute('SELECT count(*) FROM users').fetchone()[0],1)
            self.assertEqual(backups[0].stat().st_mode & 0o777,0o600)
            restored.close()
            migrate(c,37);c.execute("UPDATE schema_meta SET value='38' WHERE key='version'");c.commit()
            with patch('verabot.db.database.DB_PATH',path):backup_before_v38()
            self.assertEqual(len(list(path.parent.glob('*.bak-before-v38-*'))),1)
            c.close()
if __name__=='__main__':unittest.main()
