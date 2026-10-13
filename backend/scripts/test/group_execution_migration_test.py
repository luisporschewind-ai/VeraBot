#!/usr/bin/env python3
"""Group execution v24 migration contracts against an isolated SQLite DB."""
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

TMP = tempfile.TemporaryDirectory(prefix="vb_group_exec_migration_")
os.environ["VERABOT_DB"] = str(Path(TMP.name) / "groups.db")
os.environ["VERABOT_DATA_DIR"] = TMP.name
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db
from verabot.db.database import connect
from verabot.db.migrations import apply


class GroupExecutionMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        db.init_db()
        with db.tx() as c:
            user_id = c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('owner','x','now')").lastrowid
            bot_id = c.execute(
                "INSERT INTO bots(user_id,name,created_at) VALUES (?, 'A','now')", (user_id,)
            ).lastrowid
            group_id = c.execute(
                "INSERT INTO chat_groups(user_id,name,default_bot_id,created_at,updated_at) VALUES (?, 'G', ?, 'now','now')",
                (user_id, bot_id),
            ).lastrowid
            member_id = c.execute(
                "INSERT INTO chat_group_members(group_id,user_id,bot_id,position,name_snapshot,appearance_snapshot) VALUES (?,?,?,0,'A','{}')",
                (group_id, user_id, bot_id),
            ).lastrowid
            turn_id = c.execute(
                "INSERT INTO chat_group_turns(group_id,user_id,client_request_id,request_hash,mode,status,created_at) VALUES (?,?,'req','hash','single','completed','now')",
                (group_id, user_id),
            ).lastrowid
            c.execute(
                "INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,member_id,content,status,created_at) VALUES (?,?,?,'bot',?,'history','completed','now')",
                (group_id, user_id, turn_id, member_id),
            )
        cls.user_id, cls.group_id, cls.member_id, cls.turn_id = user_id, group_id, member_id, turn_id

    def test_migration_preserves_history_and_nulls_legacy_defaults(self):
        with connect() as c:
            message_id = c.execute("SELECT id FROM chat_group_messages").fetchone()[0]
            c.execute("UPDATE schema_meta SET value='23' WHERE key='version'")
            c.commit()
            with c:
                apply(c)
            with c:
                apply(c)
            self.assertEqual(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0], str(db.SCHEMA_VERSION))
            self.assertIsNone(c.execute("SELECT default_bot_id FROM chat_groups WHERE id=?", (self.group_id,)).fetchone()[0])
            self.assertEqual(tuple(c.execute("SELECT id,content FROM chat_group_messages").fetchone()), (message_id, "history"))
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_members WHERE id=?", (self.member_id,)).fetchone()[0], 1)

    def test_one_active_clarification_and_one_running_step_per_group(self):
        with connect() as c:
            c.execute("INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,created_at,updated_at) VALUES (?,?,?,'running',1,'now','now')",
                      (self.group_id, self.user_id, "goal"))
            task_id = c.execute("SELECT id FROM chat_group_tasks WHERE group_id=?", (self.group_id,)).fetchone()[0]
            c.execute("INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,status,created_at,updated_at) VALUES (?,?,?,?,?,?,'awaiting_user','now','now')",
                      (task_id, self.group_id, self.user_id, self.member_id, "help", "goal"))
            with self.assertRaises(sqlite3.IntegrityError):
                c.execute("INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,status,created_at,updated_at) VALUES (?,?,?,?,?,?,'awaiting_user','now','now')",
                          (task_id, self.group_id, self.user_id, self.member_id, "help", "goal"))


if __name__ == "__main__":
    unittest.main()
