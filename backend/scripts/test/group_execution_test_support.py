"""Temporary, isolated SQLite fixtures shared by group execution tests."""
import os
import sys
import tempfile
from pathlib import Path

_TMP = tempfile.TemporaryDirectory(prefix="vb_group_execution_")
os.environ["VERABOT_DB"] = str(Path(_TMP.name) / "execution.db")
os.environ["VERABOT_DATA_DIR"] = _TMP.name
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db

db.init_db()


class GroupExecutionFixture:
    def __init__(self):
        self.reset()

    def reset(self):
        with db.tx(immediate=True) as c:
            for table in ("chat_group_events", "chat_group_usage_calls", "chat_group_clarifications",
                          "chat_group_steps", "chat_group_task_inputs", "chat_group_tasks", "chat_groups",
                          "bots", "users"):
                c.execute(f"DELETE FROM {table}")
            self.user_id = c.execute(
                "INSERT INTO users(username,password_hash,created_at) VALUES ('fixture','x','now')"
            ).lastrowid
            self.other_user_id = c.execute(
                "INSERT INTO users(username,password_hash,created_at) VALUES ('other','x','now')"
            ).lastrowid
            self.bot_ids = [c.execute(
                "INSERT INTO bots(user_id,name,created_at) VALUES (?,?,'now')", (self.user_id, name)
            ).lastrowid for name in ("A", "B")]
            self.group_id = c.execute(
                "INSERT INTO chat_groups(user_id,name,created_at,updated_at) VALUES (?,'G','now','now')",
                (self.user_id,),
            ).lastrowid
            self.member_ids = [c.execute(
                "INSERT INTO chat_group_members(group_id,user_id,bot_id,position,name_snapshot,appearance_snapshot) VALUES (?,?,?,?,?,'{}')",
                (self.group_id, self.user_id, bot_id, index, name),
            ).lastrowid for index, (bot_id, name) in enumerate(zip(self.bot_ids, ("A", "B")))]
            self.other_group_id = c.execute(
                "INSERT INTO chat_groups(user_id,name,created_at,updated_at) VALUES (?,'Other','now','now')",
                (self.other_user_id,),
            ).lastrowid
        return self

    def insert_task(self, *, state="running", version=1):
        with db.tx() as c:
            return c.execute(
                "INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,created_at,updated_at) VALUES (?,?,? ,?,?,'now','now')",
                (self.group_id, self.user_id, "goal", state, version),
            ).lastrowid

    def insert_input(self, task_id, request_id="input-1", message="hello"):
        with db.tx() as c:
            return c.execute(
                "INSERT INTO chat_group_task_inputs(task_id,group_id,user_id,client_request_id,request_hash,message,created_at) VALUES (?,?,?,?,?,?, 'now')",
                (task_id, self.group_id, self.user_id, request_id, request_id, message),
            ).lastrowid

    def insert_step(self, task_id, input_id, *, status="running", version=1):
        with db.tx() as c:
            return c.execute(
                "INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,created_at,lease_token,lease_expires_at) VALUES (?,?,?,?,'member','action-1',?,?,?,'now','lease-1','2999-01-01')",
                (task_id, input_id, self.group_id, self.user_id, version, self.member_ids[0], status),
            ).lastrowid
