#!/usr/bin/env python3
"""M4 记忆成长后端回归：临时 SQLite + mock LLM。"""
import asyncio, json, os, sys, tempfile, unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
TMP=tempfile.mkdtemp(prefix="vb_m4_")
os.environ["VERABOT_DB"]=str(Path(TMP)/"m4.db")
os.environ["VERABOT_DATA_DIR"]=TMP
os.environ["VERABOT_MEMORY_JOBS"]="0"
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot import db
from verabot.db import review_store
from verabot.services.memory import growth, jobs
from verabot.services import llm
from fastapi.testclient import TestClient
from verabot.main import app

class MemoryGrowthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        db.init_db()
        with db.tx() as c:
            for u in ("m4a","m4b"):
                c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?, 'x','2026-10-01')",(u,))
            cls.a=c.execute("SELECT id FROM users WHERE username='m4a'").fetchone()[0]
            cls.b=c.execute("SELECT id FROM users WHERE username='m4b'").fetchone()[0]
            for uid,name in ((cls.a,"助手"),(cls.b,"别人的助手")):
                c.execute("INSERT INTO bots(user_id,name,created_at,memory_access) VALUES (?,?,?,?)",(uid,name,"2026-01-03", "bot_and_global"))
            cls.ba=c.execute("SELECT id FROM bots WHERE user_id=?",(cls.a,)).fetchone()[0]
            cls.bb=c.execute("SELECT id FROM bots WHERE user_id=?",(cls.b,)).fetchone()[0]
        cls.client=TestClient(app)
        auth=cls.client.post("/api/auth/register",json={"username":"m4http","password":"pw123456"}).json()
        cls.headers={"Authorization":"Bearer "+auth["token"]}
        cls.http_uid=auth["user"]["id"]
        cls.http_bot=cls.client.post("/api/bots",json={"name":"API bot"},headers=cls.headers).json()["id"]
    def setUp(self):
        with db.tx() as c:
            for table in ("memory_jobs","reviews","message_feedback","memories","messages","delegations","usage_log"):
                c.execute(f"DELETE FROM {table}")
    def message(self,uid,bid,role,body,when="2026-10-12T12:00:00+00:00",memory_ids=None):
        with db.tx() as c:
            cur=c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,memory_ids) VALUES (?,?,?,?,?,?)",
                           (uid,bid,role,body,when,json.dumps(memory_ids) if memory_ids is not None else None))
            return cur.lastrowid
    def test_v16_migration_is_idempotent_preserves_jobs_and_only_review_allows_null_bot(self):
        with db.tx() as c:
            c.execute("DROP INDEX IF EXISTS idx_mem_jobs_review_month")
            c.execute("DROP INDEX IF EXISTS idx_mem_jobs_status")
            c.execute("DROP INDEX IF EXISTS idx_mem_jobs_user")
            c.execute("DROP TABLE memory_jobs")
            c.execute("""CREATE TABLE memory_jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
                kind TEXT NOT NULL CHECK(kind IN ('summarize','extract','review')),
                status TEXT NOT NULL CHECK(status IN ('pending','running','done','failed','skipped')),
                after_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,attempts INTEGER NOT NULL DEFAULT 0,
                error TEXT,created_at TEXT NOT NULL,finished_at TEXT)""")
            c.execute("INSERT INTO memory_jobs(user_id,bot_id,kind,status,created_at) VALUES (?,?,'summarize','pending','x')",(self.a,self.ba))
            c.execute("UPDATE schema_meta SET value='15' WHERE key='version'")
        db.init_db(); db.init_db()
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM memory_jobs WHERE user_id=? AND kind='summarize'",(self.a,)).fetchone()[0],1)
            c.execute("INSERT INTO memory_jobs(user_id,bot_id,kind,status,created_at,review_month) VALUES (?,NULL,'review','pending','x','2026-10')",(self.a,))
            with self.assertRaises(Exception): c.execute("INSERT INTO memory_jobs(user_id,bot_id,kind,status,created_at) VALUES (?,NULL,'extract','pending','x')",(self.a,))
    def test_growth_counts_only_owned_bot_activity_and_successful_delegation(self):
        self.message(self.a,self.ba,"assistant","完成答复")
        self.message(self.b,self.bb,"assistant","别人的答复")
        with db.tx() as c:
            c.execute("INSERT INTO delegations(user_id,from_bot_id,to_bot_id,question,shared_context,answer,created_at,status,reason,depth) VALUES (?,?,?,?,?,?,?,?,?,?)",(self.a,self.ba,self.bb,"q","","a","2026-10-12", "ok","",0))
            c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,confirmed_at,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",(self.a,"bot",self.ba,"fact","安全偏好","h","memory_page","active","2026-10-12","x","x"))
        result=growth.for_bot(self.a,self.ba)
        self.assertEqual(result["assisted_count"],2)
        self.assertEqual(result["memory_counts"],{"fact":1})
        self.assertEqual(len(result["recent_memories"]),1)
    def test_review_request_is_per_user_month_unique_and_prompt_excludes_raw_or_sensitive_data(self):
        self.message(self.a,self.ba,"user","PRIVATE raw conversation")
        self.message(self.a,self.ba,"assistant","assistant output")
        with db.tx() as c:
            c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_enc,content_hash,source,status,sensitivity,confirmed_at,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",(self.a,"bot",self.ba,"fact","[健康信息]","encrypted","secret","memory_page","active","health","2026-10-12","x","x"))
        with ThreadPoolExecutor(max_workers=2) as pool:
            first,second=list(pool.map(lambda _:growth.request_monthly_review(self.a,"2026-10"),range(2)))
        self.assertEqual(first["review_status"],"pending")
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM reviews WHERE user_id=? AND month='2026-10'",(self.a,)).fetchone()[0],1)
        captured={}
        async def fake(messages,**kwargs):
            captured["prompt"]=messages[1]["content"]; return '{"suggestion":"继续记录重要偏好"}',{"total_tokens":12}
        original=llm.complete_json; llm.complete_json=fake
        try:
            with db.tx() as c: job=dict(c.execute("SELECT * FROM memory_jobs WHERE user_id=? AND kind='review'",(self.a,)).fetchone())
            status,error=asyncio.run(growth.run_review(job))
        finally: llm.complete_json=original
        self.assertEqual((status,error),("done",None))
        self.assertNotIn("PRIVATE raw conversation",captured["prompt"])
        self.assertNotIn("[健康信息]",captured["prompt"])
        self.assertEqual(growth.request_monthly_review(self.a,"2026-10")["review_status"],"ready")
        with self.assertRaises(ValueError): growth.request_monthly_review(self.a,"2026-13")
    def test_export_and_references_are_scoped_and_reference_checks_bot_visibility(self):
        mid=self.message(self.a,self.ba,"user","question")
        memid=self.message(self.a,self.ba,"assistant","answer")
        with db.tx() as c:
            c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",(self.a,"bot",self.ba,"preference","my preference","hash","memory_page","active","x","x"))
            own=c.execute("SELECT last_insert_rowid()").fetchone()[0]
            c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,memory_ids) VALUES (?,?,?,?,?,?)",(self.a,self.ba,"assistant","answer", "2026-10-12",json.dumps([own,999999])))
            c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",(self.b,"bot",self.bb,"fact","other secret","h2","memory_page","active","x","x"))
        refs=growth.message_memories(self.a,memid+1)
        self.assertEqual([m["content"] for m in refs["memories"]],["my preference"])
        self.assertEqual(growth.message_memories(self.b,memid+1),None)
        with db.tx() as c: c.execute("UPDATE bots SET memory_access='none' WHERE id=?",(self.ba,))
        self.assertEqual(growth.message_memories(self.a,memid+1)["memories"],[])
        with db.tx() as c: c.execute("UPDATE bots SET memory_access='bot_and_global' WHERE id=?",(self.ba,))
        export=growth.export_memories(self.a)
        self.assertTrue(all("other secret" not in m["content"] for m in export["memories"]))
        self.assertNotIn("messages",export)
        with db.tx() as c:
            c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_enc,content_hash,source,status,sensitivity,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",(self.a,"global",None,"fact","[健康信息]","malformed-ciphertext","h3","memory_page","active","health","x","x"))
        protected=growth.export_memories(self.a)["memories"]
        self.assertIn("[健康信息]",[m["content"] for m in protected])
    def test_authenticated_api_routes_return_growth_export_review_and_reject_bad_month(self):
        growth_response=self.client.get(f"/api/bots/{self.http_bot}/growth",headers=self.headers)
        export_response=self.client.get("/api/memories/export",headers=self.headers)
        review_response=self.client.get("/api/review/monthly?month=2026-10",headers=self.headers)
        invalid=self.client.get("/api/review/monthly?month=2026-13",headers=self.headers)
        self.assertEqual(growth_response.status_code,200)
        self.assertEqual(export_response.status_code,200)
        self.assertEqual(review_response.json()["review_status"],"pending")
        self.assertEqual(invalid.status_code,422)
        with db.tx() as c:
            cur=c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",(self.http_uid,"bot",self.http_bot,"fact","可见记忆","http-hash","memory_page","active","x","x"))
            visible_id=cur.lastrowid
            cur=c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,memory_ids) VALUES (?,?,?,?,?,?)",(self.http_uid,self.http_bot,"assistant","answer","2026-10-01",json.dumps([visible_id])))
            message_id=cur.lastrowid
        refs=self.client.get(f"/api/messages/{message_id}/memories",headers=self.headers)
        forbidden=self.client.get(f"/api/messages/{message_id}/memories",headers={"Authorization":"Bearer " + "invalid"})
        self.assertEqual(refs.status_code,200)
        self.assertEqual(refs.json()["memories"][0]["content"],"可见记忆")
        self.assertEqual(forbidden.status_code,401)
    def test_failed_review_returns_safe_aggregate_and_remains_retryable(self):
        growth.request_monthly_review(self.a,"2026-09")
        with db.tx() as c: job=dict(c.execute("SELECT * FROM memory_jobs WHERE user_id=? AND review_month='2026-09'",(self.a,)).fetchone())
        async def broken(*args,**kwargs): raise llm.LLMError("mock")
        original=llm.complete_json; llm.complete_json=broken
        try: status,error=asyncio.run(growth.run_review(job))
        finally: llm.complete_json=original
        self.assertEqual((status,error),("failed","llm_error"))
        with db.tx() as c: review=review_store.get(c,self.a,"2026-09")
        self.assertEqual(review["status"],"unavailable")
        self.assertEqual(growth.request_monthly_review(self.a,"2026-09")["review_status"],"pending")
    def test_unexpected_review_worker_crash_marks_cache_retryable(self):
        growth.request_monthly_review(self.a,"2026-07")
        async def crashed(*args,**kwargs): raise RuntimeError("unexpected worker failure")
        original=growth.run_review; growth.run_review=crashed
        try: self.assertTrue(asyncio.run(jobs.process_one()))
        finally: growth.run_review=original
        with db.tx() as c:
            review=review_store.get(c,self.a,"2026-07")
            job=c.execute("SELECT status,error FROM memory_jobs WHERE user_id=? AND kind='review' AND review_month='2026-07'",(self.a,)).fetchone()
        self.assertEqual(review["status"],"unavailable")
        self.assertEqual(tuple(job),("failed","crash"))
        self.assertEqual(growth.request_monthly_review(self.a,"2026-07")["review_status"],"pending")
        with db.tx() as c:
            job=c.execute("SELECT status,attempts,error FROM memory_jobs WHERE user_id=? AND kind='review' AND review_month='2026-07'",(self.a,)).fetchone()
        self.assertEqual(tuple(job),("pending",0,None))
    def test_budget_limit_skips_review_model_and_returns_aggregate_fallback(self):
        growth.request_monthly_review(self.a,"2026-08")
        with db.tx() as c: job=dict(c.execute("SELECT * FROM memory_jobs WHERE user_id=? AND review_month='2026-08'",(self.a,)).fetchone())
        old_budget=growth.db.token_budget; old_ratio=growth.config.MEMORY_BUDGET_SKIP_RATIO
        growth.db.token_budget=lambda uid:(99,100)
        growth.config.MEMORY_BUDGET_SKIP_RATIO=.9
        async def forbidden(*args,**kwargs): raise AssertionError("model must not run")
        original=llm.complete_json; llm.complete_json=forbidden
        try: status,error=asyncio.run(growth.run_review(job))
        finally:
            growth.db.token_budget=old_budget; growth.config.MEMORY_BUDGET_SKIP_RATIO=old_ratio; llm.complete_json=original
        self.assertEqual((status,error),("skipped","budget"))
        self.assertEqual(growth.request_monthly_review(self.a,"2026-08")["review_status"],"pending")

if __name__=="__main__": unittest.main(verbosity=2)
