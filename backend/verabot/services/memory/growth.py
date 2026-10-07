"""成长统计、受限月度回顾、导出与消息记忆引用。"""
from __future__ import annotations
import json
import logging
import re
from datetime import datetime

from ... import db
from ...core import config, crypto
from ...db import memory_store, message_store, review_store
from ...services import llm
from . import policy, repository as memrepo

log = logging.getLogger("verabot.memory.growth")
_REVIEW_SYSTEM = "你为用户写简短中文月度回顾。仅可用给定的数量、能力类别和记忆 ID/正文。不要引入敏感内容、等级或积分。请输出 JSON 对象，包含 suggestion 字符串字段。"

def _valid_month(month: str) -> bool:
    return bool(re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", month or ""))

def aggregate(user_id: int, month: str | None = None):
    month = month or datetime.now().strftime("%Y-%m")
    if not _valid_month(month): raise ValueError("invalid_month")
    dt=datetime.strptime(month,"%Y-%m")
    start=month+"-01"
    end=(dt.replace(year=dt.year+1,month=1) if dt.month==12 else dt.replace(month=dt.month+1)).strftime("%Y-%m-%d")
    with db.tx() as c:
        memory_store.expire_stale(c,user_id)
        bots = c.execute("SELECT id FROM bots WHERE user_id=?", (user_id,)).fetchall()
        ids = [r[0] for r in bots]
        if not ids: return {"month":month,"assisted_count":0,"capabilities":{},"new_memories":[],"candidate_count":0}
        q = ",".join("?"*len(ids))
        first = c.execute(f"SELECT MIN(created_at) FROM messages WHERE user_id=? AND bot_id IN ({q})", (user_id,*ids)).fetchone()[0]
        assisted = c.execute(f"SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id IN ({q}) AND role='assistant' AND created_at>=? AND created_at<?",
                             (user_id,*ids,start,end)).fetchone()[0]
        delegated = c.execute("SELECT COUNT(*) FROM delegations WHERE user_id=? AND status='ok' AND created_at>=? AND created_at<?",(user_id,start,end)).fetchone()[0]
        caps = c.execute(f"SELECT kind,COUNT(*) n FROM usage_log WHERE user_id=? AND bot_id IN ({q}) AND created_at>=? AND created_at<? GROUP BY kind",
                         (user_id,*ids,start,end)).fetchall()
        rows = c.execute("SELECT id,scope,bot_id,type,content,source,status,sensitivity,action,confidence,use_count,last_used_at,confirmed_at,created_at,updated_at FROM memories WHERE user_id=? AND status='active' AND confirmed_at>=? AND confirmed_at<? AND sensitivity='normal' ORDER BY confirmed_at DESC LIMIT 20",(user_id,start,end)).fetchall()
        memories=[]
        for raw in rows:
            r=dict(raw); memories.append(r)
        candidates = c.execute("SELECT COUNT(*) FROM memories WHERE user_id=? AND status='candidate' AND sensitivity='normal'",(user_id,)).fetchone()[0]
    return {"month":month,"assisted_count":assisted+delegated,"assistant_messages":assisted,"successful_delegations":delegated,
            "first_conversation_at":first,"capabilities":{r["kind"]:r["n"] for r in caps},"new_memories":memories,"candidate_count":candidates}

def for_bot(user_id: int, bot_id: int):
    with db.tx() as c:
        bot=c.execute("SELECT id FROM bots WHERE id=? AND user_id=?",(bot_id,user_id)).fetchone()
        if not bot: return None
        access=c.execute("SELECT memory_access FROM bots WHERE id=? AND user_id=?",(bot_id,user_id)).fetchone()[0]
        counts=c.execute("SELECT type,COUNT(*) n FROM memories WHERE user_id=? AND status='active' AND ((scope IN ('bot','summary') AND bot_id=?) OR (scope='global' AND ?='bot_and_global')) GROUP BY type",(user_id,bot_id,access)).fetchall()
        messages=c.execute("SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id=? AND role='assistant'",(user_id,bot_id)).fetchone()[0]
        delegations=c.execute("SELECT COUNT(*) FROM delegations WHERE user_id=? AND from_bot_id=? AND status='ok'",(user_id,bot_id)).fetchone()[0]
        first=c.execute("SELECT MIN(created_at) FROM messages WHERE user_id=? AND bot_id=?",(user_id,bot_id)).fetchone()[0]
        recent=c.execute("SELECT id,scope,bot_id,type,content,source,status,sensitivity,action,confidence,use_count,last_used_at,confirmed_at,created_at,updated_at FROM memories WHERE user_id=? AND status='active' AND sensitivity='normal' AND ((scope IN ('bot','summary') AND bot_id=?) OR (scope='global' AND ?='bot_and_global')) ORDER BY confirmed_at DESC LIMIT 3",(user_id,bot_id,access)).fetchall()
    return {"bot_id":bot_id,"memory_counts":{r["type"]:r["n"] for r in counts},"assisted_count":messages+delegations,
            "first_conversation_at":first,"recent_memories":[dict(r) for r in recent]}

def request_monthly_review(user_id:int, month:str):
    if not _valid_month(month): raise ValueError("invalid_month")
    safe=aggregate(user_id,month)
    with db.tx() as c:
        row=review_store.get(c,user_id,month)
        if row is None or row["status"]=="unavailable": row=review_store.start(c,user_id,month)
        try: content=json.loads(row["content"] or "{}")
        except ValueError: content={}
    return {**safe,"review_status":row["status"],"suggestion":content.get("suggestion") if row["status"]=="ready" else None}

async def run_review(job:dict):
    user_id=job["user_id"]
    month=job.get("review_month")
    if not month: return "skipped","no_review"
    safe=aggregate(user_id,month)
    used,budget=db.token_budget(user_id)
    if budget>0 and used>=budget*config.MEMORY_BUDGET_SKIP_RATIO:
        with db.tx() as c: review_store.save(c,user_id,month,"unavailable","{}")
        return "skipped","budget"
    # The prompt is deliberately built from an allowlist; no conversation, summary, tool payload, or candidate body.
    allow={"month":safe["month"],"assisted_count":safe["assisted_count"],"capabilities":safe["capabilities"],
           "new_memories":[{"id":m["id"],"type":m["type"],"content":m["content"]} for m in safe["new_memories"]],"candidate_count":safe["candidate_count"]}
    try: raw,usage=await llm.complete_json([{"role":"system","content":_REVIEW_SYSTEM},{"role":"user","content":json.dumps(allow,ensure_ascii=False)}],max_tokens=300)
    except llm.LLMError:
        with db.tx() as c: review_store.save(c,user_id,month,"unavailable","{}")
        return "failed","llm_error"
    db.log_usage(user_id,None,"memory",usage)
    try:
        parsed=json.loads(raw)
        if not isinstance(parsed,dict): raise ValueError("invalid")
        suggestion=parsed.get("suggestion","")
    except (ValueError,AttributeError):
        with db.tx() as c: review_store.save(c,user_id,month,"unavailable","{}")
        return "failed","invalid_json"
    if not isinstance(suggestion,str): suggestion=""
    suggestion=policy.clean(suggestion)[:160]
    code,sens=policy.check(suggestion,max_chars=160) if suggestion else (None,"normal")
    if code or sens!="normal": suggestion=""
    with db.tx() as c:
        # Recheck every memory ID immediately before caching.
        ids=[m["id"] for m in allow["new_memories"]]
        if ids:
            valid={r[0] for r in c.execute(f"SELECT id FROM memories WHERE user_id=? AND status='active' AND sensitivity='normal' AND id IN ({','.join('?'*len(ids))})",(user_id,*ids)).fetchall()}
            allow["new_memories"]=[m for m in allow["new_memories"] if m["id"] in valid]
        review_store.save(c,user_id,month,"ready",json.dumps({"suggestion":suggestion,"new_memory_ids":[m["id"] for m in allow["new_memories"]]},ensure_ascii=False),int(usage.get("total_tokens") or 0))
    return "done",None

def export_memories(user_id:int):
    with db.tx() as c: rows=c.execute("SELECT * FROM memories WHERE user_id=? ORDER BY id",(user_id,)).fetchall()
    out=[]
    for rr in rows:
        r=dict(rr); content=(crypto.decrypt(r.get("content_enc")) or policy.SENSITIVE_PLACEHOLDER.get(r.get("sensitivity"),"[敏感信息]") ) if r.get("sensitivity")!="normal" else (r.get("content") or "")
        out.append({k:r.get(k) for k in ("id","scope","bot_id","type","source","source_bot_id","source_message_id","status","action","target_id","sensitivity","confidence","use_count","last_used_at","confirmed_at","expires_at","created_at","updated_at")} | {"content":content})
    return {"format":"verabot-memory-export-v1","memories":out}

def message_memories(user_id:int,message_id:int):
    with db.tx() as c:
        m=message_store.get_owned(c,user_id,message_id)
        if not m or m["role"]!="assistant": return None
        bot=c.execute("SELECT id,memory_access FROM bots WHERE id=? AND user_id=?",(m["bot_id"],user_id)).fetchone()
        if not bot:return None
        full=c.execute("SELECT memory_ids FROM messages WHERE id=? AND user_id=?",(message_id,user_id)).fetchone()
        try: ids=json.loads(full["memory_ids"] or "[]")
        except (TypeError,ValueError): ids=[]
        if not isinstance(ids,list):ids=[]
        ids=list(dict.fromkeys(i for i in ids if type(i) is int and i>0))[:50]
        items=[]
        for mid in ids:
            r=memory_store.get(c,user_id,mid)
            if not r or r["status"]!="active":continue
            access=bot["memory_access"] or "none"
            if access not in ("bot","bot_and_global"):continue
            if (r["scope"] in ("bot","summary") and r["bot_id"]!=bot["id"]) or (r["scope"]=="global" and access!="bot_and_global"):continue
            items.append({"id":r["id"],"content":memrepo.plaintext(r),"type":r["type"],"scope":r["scope"],"sensitivity":r["sensitivity"]})
    return {"message_id":message_id,"memories":items}
