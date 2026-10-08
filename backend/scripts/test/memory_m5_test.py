#!/usr/bin/env python3
"""M5 记忆向量与协作回归。"""
import os
import struct
import sys
import tempfile
import uuid
import unittest
from pathlib import Path
from unittest.mock import patch

TMP = tempfile.mkdtemp(prefix="vb_m5_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "m5.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db
from verabot.services.memory import embeddings


class MemoryM5Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        db.init_db()

    def setUp(self):
        username = "m5-" + uuid.uuid4().hex
        with db.tx() as c:
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?, 'x','x')", (username,))
            self.uid = c.execute("SELECT id FROM users WHERE username=?", (username,)).fetchone()[0]
            c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?, 'M5 Bot','x')", (self.uid,))
            self.bid = c.execute("SELECT id FROM bots WHERE user_id=?", (self.uid,)).fetchone()[0]

    def memory(self, *, content="素食偏好", sensitivity="normal"):
        with db.tx() as c:
            cur = c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,sensitivity,created_at,updated_at) "
                            "VALUES (?, 'bot', ?, 'preference', ?, ?, 'memory_page', 'active', ?, 'x','x')",
                            (self.uid,self.bid,content,"hash-"+content,sensitivity))
            mid = cur.lastrowid
        return {"id":mid,"user_id":self.uid,"scope":"bot","bot_id":self.bid,"type":"preference",
                "status":"active","sensitivity":sensitivity,"content_hash":"hash-"+content,"_text":content}

    def test_v17_vectors_migrate_idempotently_and_cascade_with_memory(self):
        db.init_db()
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0], "17")
            cols = {r[1] for r in c.execute("PRAGMA table_info(memory_vectors)")}
            self.assertTrue({"memory_id", "user_id", "model", "dim", "content_hash", "vector", "updated_at"} <= cols)
            fk = c.execute("PRAGMA foreign_key_list(memory_vectors)").fetchall()
            self.assertTrue(any(r[2] == "memories" and r[3] == "memory_id" and r[6].upper() == "CASCADE" for r in fk))
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('m5-migrate','x','x')")
            uid = c.execute("SELECT id FROM users WHERE username='m5-migrate'").fetchone()[0]
            c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?, 'M5 Bot','x')", (uid,))
            bid = c.execute("SELECT id FROM bots WHERE user_id=?", (uid,)).fetchone()[0]
            cur = c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,created_at,updated_at) "
                            "VALUES (?, 'bot', ?, 'preference', '素食', 'hash-m5', 'memory_page', 'active', 'x','x')", (uid,bid))
            mid = cur.lastrowid
            c.execute("INSERT INTO memory_vectors(memory_id,user_id,model,dim,content_hash,vector,updated_at) VALUES (?,?,?,?,?,?,?)",
                      (mid,uid,"test-model",1,"hash-m5",struct.pack("<f",1.0),"x"))
            c.execute("DELETE FROM memories WHERE user_id=? AND id=?", (uid,mid))
            self.assertEqual(c.execute("SELECT COUNT(*) FROM memory_vectors WHERE memory_id=?", (mid,)).fetchone()[0], 0)

    def test_local_vectors_are_cached_and_rebuilt_when_content_hash_changes(self):
        memory = self.memory()
        vector = [1.0] + [0.0] * 511
        with patch.object(embeddings, "_encode_local", return_value=[vector, vector]) as encode:
            scores = embeddings.score(self.uid, [memory], "吃什么")
        self.assertAlmostEqual(scores[memory["id"]], 1.0)
        self.assertEqual(encode.call_args.args[0], ["吃什么", "preference：素食偏好"])
        with db.tx() as c:
            stored = c.execute("SELECT model,dim,content_hash,length(vector) AS size FROM memory_vectors WHERE memory_id=?",(memory["id"],)).fetchone()
        self.assertEqual((stored["model"],stored["dim"],stored["content_hash"],stored["size"]),
                         ("BAAI/bge-small-zh-v1.5",512,"hash-素食偏好",2048))
        memory["content_hash"] = "updated-hash"
        memory["_text"] = "不吃香菜"
        with db.tx() as c:
            c.execute("UPDATE memories SET content='不吃香菜',content_hash='updated-hash' WHERE user_id=? AND id=?",
                      (self.uid,memory["id"]))
        with patch.object(embeddings, "_encode_local", return_value=[vector, vector]) as encode:
            embeddings.score(self.uid, [memory], "吃什么")
        self.assertEqual(encode.call_args.args[0], ["吃什么", "preference：不吃香菜"])
        with db.tx() as c:
            stored_hash = c.execute("SELECT content_hash FROM memory_vectors WHERE memory_id=?",(memory["id"],)).fetchone()[0]
        self.assertEqual(stored_hash,"updated-hash")

    def test_sensitive_memories_are_never_written_to_plaintext_vector_cache(self):
        memory = self.memory(content="[健康信息]",sensitivity="health")
        with patch.object(embeddings, "_encode_local") as encode:
            self.assertEqual(embeddings.score(self.uid,[memory],"建议"),{})
        encode.assert_not_called()
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM memory_vectors WHERE user_id=?",(self.uid,)).fetchone()[0],0)

    def test_model_or_runtime_failure_returns_keyword_fallback_signal(self):
        memory = self.memory()
        with patch.object(embeddings, "_encode_local", side_effect=RuntimeError("local model unavailable")):
            self.assertIsNone(embeddings.score(self.uid,[memory],"晚餐"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
