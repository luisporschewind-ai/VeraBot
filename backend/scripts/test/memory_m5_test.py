#!/usr/bin/env python3
"""M5 记忆向量与协作回归。"""
import os
import struct
import sys
import tempfile
import uuid
import unittest
import asyncio
import json
from unittest.mock import AsyncMock
from pathlib import Path
from unittest.mock import patch

TMP = tempfile.mkdtemp(prefix="vb_m5_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "m5.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db
from verabot.services.memory import service as memory_service
from verabot.services.memory import embeddings
from verabot.services.memory.recall import rank, render
from verabot.core import config
from verabot.agents import delegation
from verabot.agents.context import delegation_message
from verabot.agents.prompts import system_prompt
from verabot.agents.runtime import run_once
from verabot.tools.registry import ToolContext, REGISTRY
from verabot.services.memory import feedback as feedback_service
from verabot.services.memory.collaboration import prompt_hints
from verabot.db import delegation_store


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

    def memory(self, *, content="素食偏好", sensitivity="normal", scope="bot", bot_id=None,
               memory_type="preference", status="active", user_id=None):
        user_id = self.uid if user_id is None else user_id
        bot_id = self.bid if bot_id is None and scope != "global" else bot_id
        with db.tx() as c:
            cur = c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,sensitivity,created_at,updated_at) "
                            "VALUES (?, ?, ?, ?, ?, ?, 'memory_page', ?, ?, 'x','x')",
                            (user_id,scope,bot_id,memory_type,content,"hash-"+content,status,sensitivity))
            mid = cur.lastrowid
        return {"id":mid,"user_id":user_id,"scope":scope,"bot_id":bot_id,"type":memory_type,
                "status":status,"sensitivity":sensitivity,"content_hash":"hash-"+content,"_text":content}

    def target_bot(self, access="bot_and_global"):
        name = "M5 Target " + uuid.uuid4().hex[:8]
        with db.tx() as c:
            c.execute("INSERT INTO bots(user_id,name,created_at,memory_access,accept_delegation) VALUES (?, ?,'x',?,1)",
                      (self.uid,name,access))
            target_id = c.execute("SELECT id FROM bots WHERE user_id=? AND name=?",(self.uid,name)).fetchone()[0]
        return db.get_bot(self.uid,target_id)

    def delegation_context(self):
        bot = db.get_bot(self.uid,self.bid)
        bot["delegate_to"] = []
        target = self.target_bot()
        bot["delegate_to"] = [target["id"]]
        return ToolContext(self.uid,bot),target

    def test_ask_bot_schema_and_context_support_bounded_memory_sharing(self):
        props = REGISTRY["ask_bot"].parameters["properties"]
        self.assertIn("memory_ids",props)
        self.assertEqual(props["memory_ids"]["maxItems"],8)
        message = delegation_message({"name":"源Bot"},"问题","背景",shared_memories=[
            {"id":7,"type":"style","content":"简短回答","origin":"selected"},
            {"id":8,"type":"profile","content":"保持礼貌","origin":"target"}])
        self.assertIn("记忆 #7",message)
        self.assertIn("记忆 #8",message)

    def test_ask_bot_shares_only_authorized_active_normal_memories_and_target_style_profile(self):
        ctx,target = self.delegation_context()
        allowed = self.memory(content="只吃素食",scope="global")
        hidden_bot = self.memory(content="源Bot私有",scope="bot",bot_id=self.bid)
        sensitive = self.memory(content="[健康信息]",sensitivity="health",scope="global")
        candidate = self.memory(content="未确认",scope="global",status="candidate")
        with db.tx() as c:
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?, 'x','x')",("m5-cross-"+uuid.uuid4().hex,))
            other_uid = c.execute("SELECT id FROM users ORDER BY id DESC LIMIT 1").fetchone()[0]
        cross_user = self.memory(content="他人资料",scope="global",user_id=other_uid)
        target_style = self.memory(content="回答简短",scope="bot",bot_id=target["id"],memory_type="style")
        target_profile = self.memory(content="称呼用户为林先生",scope="bot",bot_id=target["id"],memory_type="profile")
        capture = {}
        async def run(*args,**kwargs):
            capture.update(kwargs)
            return "答复",{"total_tokens":3},"payload"
        with patch("verabot.agents.runtime.run_once",new=AsyncMock(side_effect=run)):
            result = asyncio.run(delegation.ask_bot(ctx,target["name"],"请推荐晚餐",memory_ids=[
                allowed["id"],hidden_bot["id"],sensitive["id"],candidate["id"],cross_user["id"],999999]))
        self.assertEqual(result["shared_memory_ids"],[allowed["id"]])
        self.assertEqual(result["target_memory_ids"],[target_style["id"],target_profile["id"]])
        sent = capture["shared_memories"]
        self.assertEqual([m["id"] for m in sent],[allowed["id"],target_style["id"],target_profile["id"]])
        self.assertNotIn("源Bot私有",str(sent))
        self.assertNotIn("[健康信息]",str(sent))
        with db.tx() as c:
            rows = c.execute("SELECT kind,detail FROM audit_log WHERE user_id=? AND kind='delegation_memory_filtered'",(self.uid,)).fetchall()
        self.assertTrue(rows)
        self.assertNotIn("只吃素食",rows[-1]["detail"])

    def test_delegation_payload_keeps_structured_ids_and_memory_context_is_bounded(self):
        bot = db.get_bot(self.uid,self.bid)
        target = self.target_bot()
        memories = [self.memory(content=(f"资料{i}"*200),scope="global",memory_type="preference") for i in range(10)]
        selected,shared_ids,target_ids,rejected = delegation.select_shared_memories(self.uid,bot,target,[m["id"] for m in memories])
        self.assertLessEqual(len(shared_ids),8)
        self.assertLessEqual(sum(len(m["content"]) for m in selected),config.MAX_DELEGATION_MEMORY_CHARS)
        self.assertGreaterEqual(rejected,2)
        _,bad_shared,bad_target,bad_rejected = delegation.select_shared_memories(self.uid,bot,target,"not-an-id-list")
        self.assertEqual((bad_shared,bad_target,bad_rejected),([],[],1))
        async def complete(messages, tools):
            return {"content":"ok"},{}
        payload_memories = [{"id":m["id"],"type":m["type"],"scope":m["scope"],"content":m["content"],"origin":"selected"}
                            for m in selected]
        with patch("verabot.agents.runtime.llm.complete",new=AsyncMock(side_effect=complete)):
            _,_,payload = asyncio.run(run_once(self.uid,target,"问题","",from_bot=bot,depth=1,shared_memories=payload_memories))
        payload_obj = json.loads(payload)
        self.assertEqual(payload_obj["shared_memories"],[{"id":m["id"],"type":m["type"],"scope":m["scope"],"origin":m["origin"]} for m in selected])
        self.assertIn("资料",payload_obj["message"])

    def test_target_memory_access_controls_auto_attached_memories(self):
        for access, expected_scopes in (("none",[]),("bot",["bot"]),("bot_and_global",["bot","global"])):
            with self.subTest(access=access):
                ctx,target = self.delegation_context()
                with db.tx() as c:
                    c.execute("UPDATE bots SET memory_access=? WHERE id=?",(access,target["id"]))
                local = self.memory(content=f"风格 {access}",scope="bot",bot_id=target["id"],memory_type="style")
                global_profile = self.memory(content=f"全局资料 {access}",scope="global",memory_type="profile")
                async def run(*args,**kwargs):
                    return "答复",{},"payload"
                with patch("verabot.agents.runtime.run_once",new=AsyncMock(side_effect=run)):
                    result = asyncio.run(delegation.ask_bot(ctx,target["name"],"问题",memory_ids=[global_profile["id"]]))
                ids = result.get("target_memory_ids",[])
                expected = [local["id"]] if "bot" in expected_scopes else []
                self.assertEqual(result["shared_memory_ids"], [global_profile["id"]] if "global" in expected_scopes else [])
                self.assertEqual(ids,expected)
                with db.tx() as c:
                    c.execute("DELETE FROM memories WHERE user_id=? AND id IN (?,?)",(self.uid,local["id"],global_profile["id"]))

    def collab_sample(self, bot, target, question, rating=1, user_id=None):
        user_id = self.uid if user_id is None else user_id
        did = delegation_store.insert(user_id=user_id,from_bot_id=bot["id"],to_bot_id=target["id"],
                                      question=question,shared_context="",answer="答复",status="ok",reason="",
                                      depth=1,payload="{}")
        message_id = db.add_message(user_id,bot["id"],"assistant","已完成咨询",traces=[
            {"id":"call-"+str(did),"name":"ask_bot","result":{"delegation_id":did}}])
        feedback_service.submit(user_id,message_id,rating,None if rating == 1 else "inaccurate")
        return message_id

    def test_collaboration_hints_need_three_feedbacks_rank_targets_and_update_when_cleared(self):
        bot = db.get_bot(self.uid,self.bid)
        targets = [self.target_bot() for _ in range(2)]
        bot["allowed_tools"] = ["ask_bot"]
        bot["delegate_to"] = [t["id"] for t in targets]
        before = self.collab_sample(bot,targets[0],"帮我看这段 Python 代码")
        self.collab_sample(bot,targets[0],"这个编程 bug 怎么修")
        self.assertEqual(prompt_hints(self.uid,bot),[])
        negative = self.collab_sample(bot,targets[1],"iOS 编程接口问题",rating=-1)
        hints = prompt_hints(self.uid,bot)
        self.assertEqual(len(hints),1)
        self.assertIn(targets[0]["name"],hints[0])
        self.assertIn("编程",hints[0])
        root_prompt = system_prompt(self.uid,bot)
        delegated_prompt = system_prompt(self.uid,targets[0],delegated_by=bot,depth=1)
        self.assertIn("基于用户反馈的委派参考",root_prompt)
        self.assertNotIn("基于用户反馈的委派参考",delegated_prompt)
        feedback_service.clear(self.uid,before)
        self.assertEqual(prompt_hints(self.uid,bot),[])
        feedback_service.clear(self.uid,negative)

    def test_collaboration_feedback_is_user_scoped_and_hints_are_capped(self):
        bot = db.get_bot(self.uid,self.bid)
        targets = [self.target_bot() for _ in range(4)]
        bot["allowed_tools"] = ["ask_bot"]
        bot["delegate_to"] = [t["id"] for t in targets]
        with db.tx() as c:
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?, 'x','x')",("m5-other-"+uuid.uuid4().hex,))
            other_uid = c.execute("SELECT id FROM users ORDER BY id DESC LIMIT 1").fetchone()[0]
            c.execute("INSERT INTO bots(user_id,name,created_at,allowed_tools,delegate_to,accept_delegation) VALUES (?, 'Other Source','x','[\"ask_bot\"]','[]',1)",(other_uid,))
            other_bid = c.execute("SELECT id FROM bots WHERE user_id=? AND name='Other Source'",(other_uid,)).fetchone()[0]
            c.execute("INSERT INTO bots(user_id,name,created_at,accept_delegation) VALUES (?, 'Other Target','x',1)",(other_uid,))
            other_target_id = c.execute("SELECT id FROM bots WHERE user_id=? AND name='Other Target'",(other_uid,)).fetchone()[0]
        other_bot = db.get_bot(other_uid,other_bid)
        other_bot["allowed_tools"] = ["ask_bot"]
        other_bot["delegate_to"] = [other_target_id]
        other_target = db.get_bot(other_uid,other_target_id)
        for _ in range(4):
            self.collab_sample(other_bot,other_target,"Python 编程",user_id=other_uid)
        self.assertEqual(prompt_hints(self.uid,bot),[])
        for target,topic in zip(targets,("Python 编程","写作邮件","素食晚餐","日本旅行")):
            self.collab_sample(bot,target,topic)
            self.collab_sample(bot,target,topic)
        self.assertLessEqual(len(prompt_hints(self.uid,bot)),3)

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

    def test_hybrid_rank_keeps_style_profile_first_and_includes_semantic_only_matches(self):
        memories = [{"id":1,"type":"style","_text":"简短回答","scope":"bot"},
                    {"id":2,"type":"profile","_text":"住在杭州","scope":"global"},
                    {"id":3,"type":"preference","_text":"素食","scope":"global"},
                    {"id":4,"type":"fact","_text":"周三有空","scope":"bot"},
                    {"id":5,"type":"fact","_text":"养了两只猫","scope":"bot"}]
        memories.extend({"id":i,"type":"fact","_text":f"无关条目{i}","scope":"bot"} for i in range(6,18))
        result = rank(memories,"周末找餐厅",semantic_scores={3:0.92,4:0.61,5:0.12})
        self.assertEqual([m["id"] for m in result[:4]],[1,2,3,4])
        self.assertNotIn(5,[m["id"] for m in result])
        rendered = render(result)
        self.assertLessEqual(len(rendered.ids),config.MEMORY_INJECT_MAX)
        self.assertLessEqual(sum(len(m["_text"]) for m in result if m["id"] in rendered.ids),
                             config.MEMORY_INJECT_CHARS)
        fallback = rank(memories,"周末找餐厅",semantic_scores=None)
        self.assertNotIn(3,[m["id"] for m in fallback])

    def test_recall_uses_local_semantic_matches_for_large_memory_sets(self):
        records = [self.memory(content=f"条目编号{i}的独有内容") for i in range(14)]
        bot = db.get_bot(self.uid,self.bid)
        target_id = records[-1]["id"]
        with patch.object(embeddings,"score",return_value={target_id:0.95}) as score:
            recalled = memory_service.recall(self.uid,bot,"一个完全不同语义的问题")
        self.assertIn(target_id,recalled.ids)
        score.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
