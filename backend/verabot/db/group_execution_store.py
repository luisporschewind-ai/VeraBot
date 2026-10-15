"""Tenant-scoped persistence for versioned group execution. No model calls here."""
import hashlib
import json
import secrets
import uuid
from datetime import datetime, timedelta

from .database import now_iso, tx


class GroupExecutionError(Exception):
    def __init__(self, status: int, code: str, message: str, snapshot=None):
        super().__init__(message)
        self.status, self.code, self.message, self.snapshot = status, code, message, snapshot


def _not_found():
    raise GroupExecutionError(404, "not_found", "群或执行任务不存在")


def _task(row):
    if row is None:
        return None
    return {"id": row["id"], "group_id": row["group_id"], "goal": row["goal"],
            "state": row["state"], "version": row["version"], "owner_member_id": row["owner_member_id"],
            "root_message_id": row["root_message_id"], "created_at": row["created_at"],
            "updated_at": row["updated_at"], "finished_at": row["finished_at"]}


def _event(c, group_id, user_id, task_id, version, kind, payload):
    c.execute("INSERT INTO chat_group_events(group_id,user_id,task_id,version,kind,payload_json,created_at) VALUES (?,?,?,?,?,?,?)",
              (group_id, user_id, task_id, version, kind, json.dumps(payload, ensure_ascii=False), now_iso()))


def _message_event(c, step, kind, message_id):
    from .group_store import _message
    row = c.execute("SELECT * FROM chat_group_messages WHERE id=? AND user_id=? AND group_id=?", (message_id,step["user_id"],step["group_id"])).fetchone()
    if row:
        _event(c,step["group_id"],step["user_id"],step["task_id"],step["version"],kind,{"message":_message(row,c),"message_id":message_id,"content":row["content"]})


def _state_events(c, group_id, user_id, task_id, version):
    row=c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND user_id=? AND group_id=?",(task_id,user_id,group_id)).fetchone()
    _event(c,group_id,user_id,task_id,version,"task_updated",{"task":_task(row)})
    cl=c.execute("SELECT * FROM chat_group_clarifications WHERE task_id=? AND user_id=? AND status IN ('active','awaiting_user') ORDER BY id DESC LIMIT 1",(task_id,user_id)).fetchone()
    data=dict(cl) if cl else None
    if data:
        data["missing_information"]=json.loads(data["missing_information"] or "[]")
    _event(c,group_id,user_id,task_id,version,"clarification_updated",{"clarification":data})


def _pending_members(c, task_id, *, include_stopped=False):
    states = "('queued','stopped')" if include_stopped else "('queued')"
    rows = c.execute(f"SELECT * FROM chat_group_steps WHERE task_id=? AND input_id=(SELECT MAX(id) FROM chat_group_task_inputs WHERE task_id=?) AND kind='member' AND status IN {states} AND json_extract(input_json,'$.source')='router' AND json_extract(COALESCE(result_json,'{{}}'),'$.message_id') IS NULL ORDER BY id",(task_id,task_id)).fetchall()
    return [{"id":row["id"],"member_id":row["member_id"],"input":json.loads(row["input_json"]),"issue_key":row["issue_key"],"consult_return_step_id":row["consult_return_step_id"]} for row in rows]


def _restore_pending(c, step, version, pending, exclude=()):
    for item in pending:
        if item["member_id"] in exclude:
            continue
        if not c.execute("SELECT 1 FROM chat_group_members WHERE id=? AND group_id=? AND user_id=? AND bot_id IS NOT NULL",(item["member_id"],step["group_id"],step["user_id"])).fetchone():
            continue
        c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,input_json,issue_key,consult_return_step_id,created_at) VALUES (?,?,?,?,'member',?,?,?,'queued',?,?,?,?)",(step["task_id"],step["input_id"],step["group_id"],step["user_id"],f"remaining:{step['input_id']}:{item['id']}",version,item["member_id"],json.dumps(item["input"],ensure_ascii=False),item.get("issue_key"),item.get("consult_return_step_id"),now_iso()))


def snapshot(user_id: int, group_id: int, task_id: int | None = None):
    with tx() as c:
        group = c.execute("SELECT id FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone()
        if group is None:
            _not_found()
        if c.execute("SELECT 1 FROM chat_group_members WHERE group_id=? AND user_id=? AND bot_id IS NOT NULL LIMIT 1",
                     (group_id, user_id)).fetchone() is None:
            raise GroupExecutionError(409, "group_read_only", "群里已没有可用成员")
        if task_id is None:
            row = c.execute("SELECT * FROM chat_group_tasks WHERE user_id=? AND group_id=? AND state IN ('queued','running','awaiting_user') ORDER BY id DESC LIMIT 1",
                            (user_id, group_id)).fetchone()
        else:
            row = c.execute("SELECT * FROM chat_group_tasks WHERE user_id=? AND group_id=? AND id=?",
                            (user_id, group_id, task_id)).fetchone()
        return _task(row)


def input_receipt(user_id: int, group_id: int, client_request_id: str):
    with tx() as c:
        row = c.execute("SELECT i.id AS input_id,i.turn_id,t.*,(SELECT MAX(0,COALESCE(MIN(id),1)-1) FROM chat_group_events WHERE group_id=i.group_id AND user_id=i.user_id AND kind='input_accepted' AND json_extract(payload_json,'$.input_id')=i.id) AS event_cursor FROM chat_group_task_inputs i JOIN chat_group_tasks t ON t.id=i.task_id WHERE i.user_id=? AND i.group_id=? AND i.client_request_id=?",
                        (user_id, group_id, client_request_id)).fetchone()
        if row is None:
            _not_found()
        return {"task": _task(row), "input_id": row["input_id"], "turn_id": row["turn_id"],
                "event_cursor": row["event_cursor"]}


def execution_snapshot(user_id: int, group_id: int, *, include_messages=True):
    with tx() as c:
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone() is None:
            _not_found()
        task_row = c.execute("SELECT t.* FROM chat_group_tasks t WHERE group_id=? AND user_id=? ORDER BY CASE WHEN state IN ('queued','running','awaiting_user') THEN 0 ELSE 1 END,COALESCE((SELECT MAX(e.id) FROM chat_group_events e WHERE e.task_id=t.id AND e.user_id=t.user_id),0) DESC,t.id DESC LIMIT 1",
                             (group_id, user_id)).fetchone()
        if task_row and not task_row["goal"] and task_row["root_message_id"] is None:
            task_row = None
        clarification = None
        if task_row:
            row = c.execute("SELECT * FROM chat_group_clarifications WHERE task_id=? AND user_id=? AND status IN ('active','awaiting_user') ORDER BY id DESC LIMIT 1",
                            (task_row["id"], user_id)).fetchone()
            if row:
                clarification = dict(row)
                clarification["missing_information"] = json.loads(clarification["missing_information"] or "[]")
        cursor = c.execute("SELECT COALESCE(MAX(id),0) FROM chat_group_events WHERE user_id=? AND group_id=?",
                           (user_id, group_id)).fetchone()[0]
        from .group_store import _message
        messages = [_message(row,c) for row in reversed(c.execute("SELECT * FROM chat_group_messages WHERE group_id=? AND user_id=? ORDER BY id DESC LIMIT 100",(group_id,user_id)).fetchall())] if include_messages else []
        return {"task": _task(task_row), "clarification": clarification, "event_cursor": cursor, "messages":messages}


def task_ids(user_id: int, group_id: int) -> list[int]:
    with tx() as c:
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone() is None:
            _not_found()
        return [r[0] for r in c.execute("SELECT id FROM chat_group_tasks WHERE user_id=? AND group_id=? AND state IN ('queued','running','awaiting_user')",
                                        (user_id, group_id)).fetchall()]


def retry_failed(user_id: int, group_id: int, message_id: int, request_id: str, expected_version: int):
    with tx(immediate=True) as c:
        message = c.execute("SELECT m.*,t.id AS task_id,t.version,t.state AS task_state FROM chat_group_messages m JOIN chat_group_task_inputs i ON i.turn_id=m.turn_id JOIN chat_group_tasks t ON t.id=i.task_id WHERE m.id=? AND m.group_id=? AND m.user_id=? AND m.role='bot' ORDER BY i.id DESC LIMIT 1",
                            (message_id, group_id, user_id)).fetchone()
        if message is None:
            _not_found()
        old = c.execute("SELECT i.request_hash,t.* FROM chat_group_task_inputs i JOIN chat_group_tasks t ON t.id=i.task_id WHERE i.user_id=? AND i.group_id=? AND i.client_request_id=?",
                        (user_id, group_id, request_id)).fetchone()
        digest = hashlib.sha256(f"retry:{group_id}:{message_id}:{request_id}:{expected_version}".encode()).hexdigest()
        if old:
            if old["request_hash"] != digest:
                raise GroupExecutionError(409,"idempotency_conflict","请求 ID 已用于不同操作",_task(old))
            return _task(old)
        target_task=c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND user_id=?",(message["task_id"],user_id)).fetchone()
        other=c.execute("SELECT * FROM chat_group_tasks WHERE group_id=? AND user_id=? AND id!=? AND state IN ('queued','running','awaiting_user')",(group_id,user_id,message["task_id"])).fetchone()
        if other:
            raise GroupExecutionError(409,"task_version_changed","另一项任务正在执行，请同步最新状态",_task(other))
        c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE group_id=? AND user_id=? AND task_id!=? AND status IN ('active','awaiting_user')",(now_iso(),group_id,user_id,message["task_id"]))
        if message["status"] not in ("failed", "interrupted") or message["task_state"] not in ("failed", "interrupted"):
            raise GroupExecutionError(409, "retry_invalid", "只能重试失败的成员步骤", _task(target_task))
        if message["version"] != expected_version:
            raise GroupExecutionError(409, "task_version_changed", "群任务已更新", _task(target_task))
        failed = c.execute("SELECT * FROM chat_group_steps WHERE task_id=? AND status IN ('failed','interrupted') AND json_extract(result_json,'$.message_id')=? ORDER BY id DESC LIMIT 1",
                           (message["task_id"], message_id)).fetchone()
        if failed is None:
            _not_found()
        original_input = c.execute("SELECT * FROM chat_group_task_inputs WHERE id=?", (failed["input_id"],)).fetchone()
        now, version = now_iso(), message["version"] + 1
        c.execute("UPDATE chat_group_tasks SET state='queued',version=?,updated_at=?,finished_at=NULL WHERE id=? AND user_id=?",
                  (version, now, message["task_id"], user_id))
        pending_members = _pending_members(c,message["task_id"])
        c.execute("UPDATE chat_group_steps SET status='stopped',finished_at=? WHERE task_id=? AND status='queued'",(now,message["task_id"]))
        input_id = c.execute("INSERT INTO chat_group_task_inputs(task_id,group_id,user_id,client_request_id,request_hash,message,turn_id,created_at) VALUES (?,?,?,?,?,?,?,?)",
                             (message["task_id"], group_id, user_id, request_id, digest, original_input["message"], original_input["turn_id"], now)).lastrowid
        payload = json.loads(failed["input_json"] or "{}")
        c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,issue_key,input_json,created_at) VALUES (?,?,?,?,'member',?,?,?,'queued',?,?,?)",
                  (message["task_id"], input_id, group_id, user_id, f"retry:{request_id}", version,
                   failed["member_id"], failed["issue_key"], json.dumps(payload, ensure_ascii=False), now))
        if failed["consult_return_step_id"] is not None:
            c.execute("UPDATE chat_group_steps SET consult_return_step_id=? WHERE action_key=?", (failed["consult_return_step_id"], f"retry:{request_id}"))
        _restore_pending(c,{"task_id":message["task_id"],"input_id":input_id,"group_id":group_id,"user_id":user_id},version,pending_members)
        _event(c, group_id, user_id, message["task_id"], version, "retry_accepted", {"input_id": input_id, "retry_of_message_id": message_id})
        _state_events(c,group_id,user_id,message["task_id"],version)
        return _task(c.execute("SELECT * FROM chat_group_tasks WHERE id=?", (message["task_id"],)).fetchone())


def create_input(user_id: int, group_id: int, request: dict):
    """Persist an input and route step atomically, before any classifier call."""
    canonical = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode()).hexdigest()
    with tx(immediate=True) as c:
        group = c.execute("SELECT id FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone()
        if group is None:
            _not_found()
        existing = c.execute("SELECT i.request_hash,t.* FROM chat_group_task_inputs i JOIN chat_group_tasks t ON t.id=i.task_id WHERE i.user_id=? AND i.group_id=? AND i.client_request_id=?",
                             (user_id, group_id, request["client_request_id"])).fetchone()
        if existing:
            if existing["request_hash"] != digest:
                raise GroupExecutionError(409, "idempotency_conflict", "请求 ID 已用于不同内容", _task(existing))
            return _task(existing)
        active = c.execute("SELECT * FROM chat_group_tasks WHERE user_id=? AND group_id=? AND state IN ('queued','running','awaiting_user') ORDER BY id DESC LIMIT 1",
                           (user_id, group_id)).fetchone()
        if request.get("resume_task_id") is not None and active is None:
            active=c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND group_id=? AND user_id=? AND state IN ('failed','interrupted','stopped')",(request["resume_task_id"],group_id,user_id)).fetchone()
        pending_members = _pending_members(c,active["id"],include_stopped=bool(request.get("resume_task_id"))) if active else []
        expected_task = request.get("expected_task_id")
        expected_version = request.get("expected_version")
        continuation = active is not None
        if expected_task is not None and (active is None or active["id"] != expected_task or active["version"] != expected_version):
            raise GroupExecutionError(409, "task_version_changed", "群任务已更新，请同步最新状态", _task(active))
        if continuation and (active["id"] != expected_task or active["version"] != expected_version):
            raise GroupExecutionError(409, "task_version_changed", "群任务已更新，请同步最新状态", _task(active))
        if request.get("clarification_id") is not None:
            clarification = c.execute("SELECT id FROM chat_group_clarifications WHERE id=? AND task_id=? AND user_id=? AND status='awaiting_user'",
                                      (request["clarification_id"], active["id"], user_id)).fetchone()
            if clarification is None:
                raise GroupExecutionError(409, "clarification_changed", "澄清状态已更新", _task(active))
        for member_id in request.get("target_member_ids", []):
            if c.execute("SELECT 1 FROM chat_group_members WHERE id=? AND group_id=? AND user_id=? ",
                         (member_id, group_id, user_id)).fetchone() is None:
                _not_found()
        if request.get("reply_to_message_id") is not None and c.execute(
            "SELECT 1 FROM chat_group_messages WHERE id=? AND group_id=? AND user_id=?",
            (request["reply_to_message_id"], group_id, user_id)).fetchone() is None:
            _not_found()
        now = now_iso()
        if active is None:
            c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE group_id=? AND user_id=? AND status IN ('active','awaiting_user')",(now,group_id,user_id))
            task_id = c.execute("INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,created_at,updated_at) VALUES (?,?,?,'queued',1,?,?)",
                                (group_id, user_id, request["message"], now, now)).lastrowid
            version = 1
        elif continuation:
            c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE group_id=? AND user_id=? AND task_id!=? AND status IN ('active','awaiting_user')",(now,group_id,user_id,active["id"]))
            task_id, version = active["id"], active["version"] + 1
            c.execute("UPDATE chat_group_tasks SET state='queued',version=?,updated_at=?,finished_at=NULL WHERE id=? AND user_id=?",
                      (version, now, task_id, user_id))
            c.execute("UPDATE chat_group_steps SET status='stopped',finished_at=? WHERE task_id=? AND status='queued'", (now, task_id))
        else:
            task_id = c.execute("INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,created_at,updated_at) VALUES (?,?,?,'queued',1,?,?)",
                                (group_id, user_id, request["message"], now, now)).lastrowid
            version = 1
        members = request.get("target_member_ids", [])
        for att_id in request.get("attachment_ids", []):
            attachment = c.execute("SELECT status,bot_id,expires_at FROM attachments WHERE id=? AND user_id=?", (att_id, user_id)).fetchone()
            if attachment is None or attachment["bot_id"] is not None:
                _not_found()
            if attachment["status"] != "pending":
                raise GroupExecutionError(409, "attachment_already_sent", "附件已经发送")
            if attachment["expires_at"] and attachment["expires_at"] < now:
                raise GroupExecutionError(410, "attachment_expired", "附件已过期，请重新选择")
        mode = "round" if request.get("everyone") else "single"
        turn_id = c.execute("INSERT INTO chat_group_turns(group_id,user_id,client_request_id,request_hash,mode,status,created_at) VALUES (?,?,?,?,?,'completed',?)",
                            (group_id, user_id, request["client_request_id"], digest, mode, now)).lastrowid
        message_id = c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at,finished_at) VALUES (?,?,?,'user',?,'completed',?,?)",
                                (group_id, user_id, turn_id, request["message"], now, now)).lastrowid
        c.execute("UPDATE chat_group_turns SET user_message_id=?,context_end_message_id=? WHERE id=? AND user_id=?",
                  (message_id, message_id, turn_id, user_id))
        c.execute("UPDATE chat_group_tasks SET root_message_id=COALESCE(root_message_id,?) WHERE id=?", (message_id, task_id))
        input_id = c.execute("INSERT INTO chat_group_task_inputs(task_id,group_id,user_id,client_request_id,request_hash,message,turn_id,created_at) VALUES (?,?,?,?,?,?,?,?)",
                             (task_id, group_id, user_id, request["client_request_id"], digest, request["message"], turn_id, now)).lastrowid
        c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,status,input_json,created_at) VALUES (?,?,?,?,'route',? ,?,'queued',?,?)",
                  (task_id, input_id, group_id, user_id, f"route:{input_id}", version, json.dumps({**request, "previous_task": _task(active), "pending_members":pending_members}, ensure_ascii=False), now))
        for att_id in request.get("attachment_ids", []):
            c.execute("INSERT INTO chat_group_attachments(attachment_id,user_id,group_id,message_id,created_at) VALUES (?,?,?,?,?)",
                      (att_id, user_id, group_id, message_id, now))
            changed = c.execute("UPDATE attachments SET status='attached',expires_at=NULL WHERE id=? AND user_id=? AND status='pending'",
                                (att_id, user_id)).rowcount
            if changed != 1:
                raise GroupExecutionError(409, "attachment_already_sent", "附件已经发送")
            from ..services.library import ingest_attachment
            ingest_attachment(c,user_id=user_id,attachment_id=att_id,source_kind="group",source_id=group_id,bot_id=None)
            c.execute("UPDATE library_sources SET message_id=? WHERE item_id=? AND user_id=? AND kind='group'",(message_id,att_id,user_id))
        _event(c, group_id, user_id, task_id, version, "input_accepted", {"input_id": input_id, "turn_id": turn_id, "message_id": message_id})
        _message_event(c,{"group_id":group_id,"user_id":user_id,"task_id":task_id,"version":version},"message_done",message_id)
        _state_events(c,group_id,user_id,task_id,version)
        row = c.execute("SELECT * FROM chat_group_tasks WHERE id=?", (task_id,)).fetchone()
        return _task(row)


def claim_next(worker_id: str, now: str):
    with tx(immediate=True) as c:
        row = c.execute("SELECT s.*,i.turn_id,i.call_count,i.elapsed_ms FROM chat_group_steps s JOIN chat_group_tasks t ON t.id=s.task_id AND t.version=s.version AND t.state IN ('queued','running') JOIN chat_group_task_inputs i ON i.id=s.input_id WHERE s.status='queued' AND NOT EXISTS(SELECT 1 FROM chat_group_steps r WHERE r.group_id=s.group_id AND r.status='running') ORDER BY CASE WHEN json_extract(s.input_json,'$.source')='router' THEN 1 ELSE 0 END,s.id LIMIT 1").fetchone()
        if row is None:
            return None
        token = secrets.token_hex(16)
        expires = (datetime.fromisoformat(now) + timedelta(seconds=90)).isoformat()
        changed = c.execute("UPDATE chat_group_steps SET status='running',lease_token=?,lease_expires_at=?,started_at=? WHERE id=? AND status='queued'",
                            (token, expires, now, row["id"])).rowcount
        if not changed:
            return None
        c.execute("UPDATE chat_group_tasks SET state='running',updated_at=? WHERE id=? AND version=?",
                  (now, row["task_id"], row["version"]))
        result = dict(row)
        result.update(status="running", lease_token=token, lease_expires_at=expires, input=json.loads(row["input_json"]))
        if row["kind"] == "member":
            if row["call_count"] >= 6 or row["elapsed_ms"] >= 240_000:
                c.execute("UPDATE chat_group_steps SET status='failed',finished_at=? WHERE id=?", (now, row["id"]))
                c.execute("UPDATE chat_group_tasks SET state='failed',finished_at=?,updated_at=? WHERE id=?", (now, now, row["task_id"]))
                _event(c, row["group_id"], row["user_id"], row["task_id"], row["version"], "execution_limit", {})
                return None
            c.execute("UPDATE chat_group_turns SET status='running',target_member_id=?,finished_at=NULL WHERE id=? AND user_id=? AND status IN ('completed','running','failed','interrupted')",
                      (row["member_id"], row["turn_id"], row["user_id"]))
            member = c.execute("SELECT m.name_snapshot,b.name AS live_name,m.appearance_snapshot,b.avatar,b.color,b.persona,b.appearance FROM chat_group_members m LEFT JOIN bots b ON b.id=m.bot_id AND b.user_id=m.user_id WHERE m.id=? AND m.group_id=? AND m.user_id=? AND m.bot_id IS NOT NULL",
                               (row["member_id"], row["group_id"], row["user_id"])).fetchone()
            if member is None:
                c.execute("UPDATE chat_group_steps SET status='failed',finished_at=? WHERE id=?", (now, row["id"]))
                c.execute("UPDATE chat_group_tasks SET state='failed',finished_at=?,updated_at=? WHERE id=?", (now, now, row["task_id"]))
                return None
            appearance = json.loads(member["appearance_snapshot"] or "{}")
            if member["appearance"]:
                appearance["appearance"] = json.loads(member["appearance"])
            message_id = c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,member_id,content,status,sender_name_snapshot,sender_appearance_snapshot,created_at) VALUES (?,?,?,'bot',?,'','streaming',?,?,?)",
                                   (row["group_id"], row["user_id"], row["turn_id"], row["member_id"], member["live_name"] or member["name_snapshot"],
                                    json.dumps(appearance, ensure_ascii=False), now)).lastrowid
            result["message_id"] = message_id
            result["call_count"] = row["call_count"]
            input_data = json.loads(row["input_json"])
            input_data["turn_id"] = row["turn_id"]
            result["input"] = input_data
            step_result = json.loads(row["result_json"] or "{}")
            step_result["message_id"] = message_id
            c.execute("UPDATE chat_group_steps SET result_json=? WHERE id=?", (json.dumps(step_result), row["id"]))
            _message_event(c,row,"message_start",message_id)
        _state_events(c,row["group_id"],row["user_id"],row["task_id"],row["version"])
        return result


def _live_step(c, step_id, lease_token, version):
    return c.execute("SELECT s.*,t.state AS task_state,t.version AS task_version FROM chat_group_steps s JOIN chat_group_tasks t ON t.id=s.task_id AND t.group_id=s.group_id AND t.user_id=s.user_id WHERE s.id=? AND s.status='running' AND s.lease_token=? AND s.version=? AND t.version=? AND t.state='running'",
                     (step_id, lease_token, version, version)).fetchone()


def save_snapshot(step_id: int, lease_token: str, version: int, content: str) -> bool:
    with tx(immediate=True) as c:
        step = _live_step(c, step_id, lease_token, version)
        if step is None:
            return False
        result = json.loads(step["result_json"] or "{}")
        result["content"] = content
        c.execute("UPDATE chat_group_steps SET result_json=? WHERE id=?", (json.dumps(result, ensure_ascii=False), step_id))
        if result.get("message_id"):
            c.execute("UPDATE chat_group_messages SET content=? WHERE id=? AND user_id=? AND status='streaming'",
                      (content, result["message_id"], step["user_id"]))
        _message_event(c,step,"message_snapshot",result.get("message_id"))
        return True


def _public_message_status(content: str, status: str) -> str:
    """Steps may fail internally; a message with usable text must look like a normal reply."""
    if (content or "").strip() and status in {"failed", "interrupted", "stopped"}:
        return "completed"
    return status


def commit_step(step_id: int, lease_token: str, version: int, result: dict) -> bool:
    with tx(immediate=True) as c:
        step = _live_step(c, step_id, lease_token, version)
        if step is None:
            return False
        now = now_iso()
        step_saved = json.loads(step["result_json"] or "{}")
        message_id = step_saved.get("message_id")
        content = result.get("content", step_saved.get("content", ""))
        status = result.get("status", "completed")
        if status not in {"completed", "failed", "stopped", "interrupted"}:
            status = "failed"
        action = result.get("action") if status == "completed" else None
        if message_id:
            c.execute("UPDATE chat_group_messages SET content=?,status=?,usage_json=?,finished_at=? WHERE id=? AND user_id=? AND group_id=? AND status='streaming'",
                      (content, _public_message_status(content, status),
                       json.dumps(result["usage"]) if result.get("usage") is not None else None,
                       now, message_id, step["user_id"], step["group_id"]))
        c.execute("UPDATE chat_group_steps SET status=?,result_json=?,finished_at=?,lease_token=NULL,lease_expires_at=NULL WHERE id=?",
                  (status, json.dumps({**step_saved, **result}, ensure_ascii=False), now, step_id))
        elapsed_ms = max(0, int(result.get("elapsed_ms", 0) or 0))
        c.execute("UPDATE chat_group_task_inputs SET elapsed_ms=elapsed_ms+? WHERE id=?", (elapsed_ms, step["input_id"]))
        usage = result.get("usage")
        if not result.get("usage_recorded") and (usage is not None or result.get("usage_unknown")):
            call_id = result.get("call_id") or f"group-member:{step_id}"
            usage_log_id = None
            if usage is not None:
                member = c.execute("SELECT bot_id FROM chat_group_members WHERE id=? AND group_id=?", (step["member_id"], step["group_id"])).fetchone()
                usage_log_id = c.execute("INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) VALUES (?,?,'group_chat',?,?,?,?)",
                    (step["user_id"], member[0] if member else None, usage.get("prompt_tokens", 0),
                     usage.get("completion_tokens", 0), usage.get("total_tokens", 0), now)).lastrowid
            c.execute("INSERT OR IGNORE INTO chat_group_usage_calls(call_id,user_id,group_id,task_id,step_id,kind,usage_log_id,usage_json,usage_unknown,created_at) VALUES (?,?,?,?,?,'group_chat',?,?,?,?)",
                      (call_id, step["user_id"], step["group_id"], step["task_id"], step_id, usage_log_id,
                       json.dumps(usage) if usage is not None else None, int(bool(result.get("usage_unknown"))), now))
        task = c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND user_id=? AND group_id=?",
                         (step["task_id"], step["user_id"], step["group_id"])).fetchone()
        input_row = c.execute("SELECT turn_id,call_count,elapsed_ms FROM chat_group_task_inputs WHERE id=?", (step["input_id"],)).fetchone()
        action_kind = action.get("kind") if isinstance(action, dict) else None
        planned = result.get("next_steps", []) if isinstance(result.get("next_steps", []), list) else []
        revision_limit_hit = False
        if action_kind == "consult" and planned:
            issue_key = planned[0].get("issue_key") or action.get("issue_key") or f"task:{step['task_id']}:root"
            returned = c.execute("SELECT COUNT(*) FROM chat_group_steps WHERE task_id=? AND issue_key=? AND json_extract(input_json,'$.action')='consult'",
                                 (step["task_id"], issue_key)).fetchone()[0]
            if returned >= 1:
                planned = []
                revision_limit_hit = True
        clarification_id = json.loads(step["input_json"] or "{}").get("clarification_id")
        if status != "completed":
            c.execute("UPDATE chat_group_tasks SET state=?,updated_at=?,finished_at=? WHERE id=? AND version=?",
                      ("stopped" if status == "stopped" else "interrupted" if status == "interrupted" else "failed", now, now, step["task_id"], version))
            c.execute("UPDATE chat_group_turns SET status=?,finished_at=? WHERE id=? AND user_id=? AND status='running'",
                      (status, now, input_row["turn_id"], step["user_id"]))
        elif action_kind == "await_user":
            if not message_id or not content.strip():
                c.execute("UPDATE chat_group_tasks SET state='failed',updated_at=?,finished_at=? WHERE id=? AND version=?", (now, now, step["task_id"], version))
            else:
                if clarification_id:
                    c.execute("UPDATE chat_group_clarifications SET latest_question_message_id=?,status='awaiting_user',updated_at=? WHERE id=? AND task_id=?",
                              (message_id, now, clarification_id, step["task_id"]))
                else:
                    clarification_id = c.execute("INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,latest_question_message_id,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                        (step["task_id"], step["group_id"], step["user_id"], step["member_id"], task["goal"],
                         json.dumps(action.get("missing_information", []), ensure_ascii=False), message_id, "awaiting_user", now, now)).lastrowid
                c.execute("UPDATE chat_group_tasks SET state='awaiting_user',owner_member_id=?,updated_at=? WHERE id=? AND version=?",
                          (step["member_id"], now, step["task_id"], version))
                c.execute("UPDATE chat_group_turns SET status='completed',finished_at=? WHERE id=? AND user_id=? AND status='running'", (now, input_row["turn_id"], step["user_id"]))
        elif planned:
            for planned_step in planned[:1]:
                member_id = planned_step.get("member_id")
                member = c.execute("SELECT 1 FROM chat_group_members WHERE id=? AND group_id=? AND user_id=? AND bot_id IS NOT NULL",
                                   (member_id, step["group_id"], step["user_id"])).fetchone()
                if member is None:
                    continue
                action_key = f"action:{step_id}:{planned_step.get('action')}:{member_id}"
                c.execute("INSERT OR IGNORE INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,consult_return_step_id,issue_key,input_json,created_at) VALUES (?,?,?,?,'member',?,?,?,'queued',?,?,?,?)",
                    (step["task_id"], step["input_id"], step["group_id"], step["user_id"], action_key, version, member_id,
                     planned_step.get("consult_return_step_id"), planned_step.get("issue_key") or action.get("issue_key"), json.dumps(planned_step, ensure_ascii=False), now))
                if ((action_kind == "handoff" and not planned_step.get("consult_stack")) or planned_step.get("action") == "consult_return"):
                    c.execute("UPDATE chat_group_tasks SET owner_member_id=? WHERE id=? AND version=?", (member_id, step["task_id"], version))
                _event(c, step["group_id"], step["user_id"], step["task_id"], version, "handoff_scheduled",
                       {"from_member_id": step["member_id"], "to_member_id": member_id, "kind": action_kind})
        elif c.execute("SELECT 1 FROM chat_group_steps WHERE task_id=? AND version=? AND status IN ('queued','running') LIMIT 1", (step["task_id"], version)).fetchone():
            c.execute("UPDATE chat_group_tasks SET state='queued',updated_at=? WHERE id=? AND version=?", (now, step["task_id"], version))
        else:
            c.execute("UPDATE chat_group_tasks SET state='completed',updated_at=?,finished_at=? WHERE id=? AND version=?", (now, now, step["task_id"], version))
            c.execute("UPDATE chat_group_turns SET status='completed',finished_at=? WHERE id=? AND user_id=? AND status='running'", (now, input_row["turn_id"], step["user_id"]))
        if revision_limit_hit:
            _event(c, step["group_id"], step["user_id"], step["task_id"], version, "revision_limit", {"issue_key": issue_key})
        _event(c, step["group_id"], step["user_id"], step["task_id"], version, "step_completed",
               {"step_id": step_id, "message_id": message_id, "action": action_kind})
        if message_id:
            _message_event(c,step,"message_done",message_id)
        _state_events(c,step["group_id"],step["user_id"],step["task_id"],version)
        return True


def routing_context(user_id: int, group_id: int, task_id: int):
    """Return only group-scoped history, the current clarification, and fair-selection counters."""
    with tx() as c:
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone() is None:
            _not_found()
        clarification = c.execute("SELECT * FROM chat_group_clarifications WHERE task_id=? AND user_id=? AND status IN ('active','awaiting_user') ORDER BY id DESC LIMIT 1",
                                 (task_id, user_id)).fetchone()
        history = [dict(row) for row in c.execute("SELECT id,role,member_id,content FROM chat_group_messages WHERE user_id=? AND group_id=? ORDER BY id DESC LIMIT 24",
                                                   (user_id, group_id)).fetchall()][::-1]
        speech = {row["member_id"]: {"recent_speech_count": row["n"]} for row in c.execute(
            "SELECT member_id,COUNT(*) AS n FROM (SELECT member_id FROM chat_group_messages WHERE user_id=? AND group_id=? AND role='bot' AND member_id IS NOT NULL ORDER BY id DESC LIMIT 24) GROUP BY member_id",
            (user_id, group_id)).fetchall()}
        fairness = {row["id"]: {"last_clarified_at": row["last_clarified_at"], **speech.get(row["id"], {})}
                    for row in c.execute("SELECT id,last_clarified_at FROM chat_group_members WHERE user_id=? AND group_id=?",
                                         (user_id, group_id)).fetchall()}
        task = _task(c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND group_id=? AND user_id=?", (task_id, group_id, user_id)).fetchone())
        if task:
            task["requirements"] = [row[0] for row in c.execute("SELECT message FROM chat_group_task_inputs WHERE task_id=? AND user_id=? ORDER BY id", (task_id, user_id))]
            if task.get("root_message_id"):
                root = c.execute("SELECT content FROM chat_group_messages WHERE id=? AND group_id=? AND user_id=?", (task["root_message_id"], group_id, user_id)).fetchone()
                task["original_request"] = root[0] if root else task["goal"]
        if clarification:
            clarification = dict(clarification)
            clarification["missing_information"] = json.loads(clarification["missing_information"] or "[]")
        return task, dict(clarification) if clarification else None, history, fairness


def validate_action_references(user_id: int, group_id: int, message_ids: list[int], attachment_ids: list[str]) -> bool:
    with tx() as c:
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone() is None:
            return False
        for message_id in message_ids:
            if c.execute("SELECT 1 FROM chat_group_messages WHERE id=? AND user_id=? AND group_id=?",
                         (message_id, user_id, group_id)).fetchone() is None:
                return False
        for attachment_id in attachment_ids:
            if c.execute("SELECT 1 FROM chat_group_attachments WHERE attachment_id=? AND user_id=? AND group_id=?",
                         (attachment_id, user_id, group_id)).fetchone() is None:
                return False
        return True


def apply_route(step_id: int, lease_token: str, version: int, decision: dict) -> bool:
    with tx(immediate=True) as c:
        step = _live_step(c, step_id, lease_token, version)
        if step is None or step["kind"] != "route":
            return False
        group = c.execute("SELECT id FROM chat_groups WHERE id=? AND user_id=?", (step["group_id"], step["user_id"])).fetchone()
        if group is None:
            return False
        available = {r["id"] for r in c.execute("SELECT id FROM chat_group_members WHERE group_id=? AND user_id=? AND bot_id IS NOT NULL",
                                                  (step["group_id"], step["user_id"])).fetchall()}
        targets = decision.get("speaker_member_ids", [])
        if any(type(target) is not int or target not in available for target in targets):
            return False
        now = now_iso()
        if decision.get("intent") == "stop":
            c.execute("UPDATE chat_group_tasks SET state='stopped',version=version+1,updated_at=?,finished_at=? WHERE id=? AND version=?",
                      (now, now, step["task_id"], version))
            c.execute("UPDATE chat_group_steps SET status='completed',finished_at=? WHERE id=?", (now, step_id))
            c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE task_id=? AND status IN ('active','awaiting_user')",(now,step["task_id"]))
            _event(c, step["group_id"], step["user_id"], step["task_id"], version + 1, "task_stopped", {"source": "user_input"})
            _state_events(c,step["group_id"],step["user_id"],step["task_id"],version+1)
            return True

        existing = c.execute("SELECT * FROM chat_group_clarifications WHERE task_id=? AND status IN ('active','awaiting_user') ORDER BY id DESC LIMIT 1",
                             (step["task_id"],)).fetchone()
        clarification_id = None
        if decision.get("intent") == "replace":
            c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE task_id=? AND status IN ('active','awaiting_user')",
                      (now, step["task_id"]))
            request = json.loads(step["input_json"])
            if request.get("previous_task") is not None:
                old_task_id = step["task_id"]
                c.execute("UPDATE chat_group_tasks SET state='stopped',updated_at=?,finished_at=? WHERE id=?", (now, now, old_task_id))
                turn = c.execute("SELECT t.user_message_id FROM chat_group_task_inputs i JOIN chat_group_turns t ON t.id=i.turn_id WHERE i.id=?", (step["input_id"],)).fetchone()
                new_task_id = c.execute("INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,root_message_id,created_at,updated_at) VALUES (?,?,?,'running',1,?,?,?)",
                    (step["group_id"],step["user_id"],decision.get("goal") or request["message"],turn[0] if turn else None,now,now)).lastrowid
                c.execute("UPDATE chat_group_task_inputs SET task_id=? WHERE id=?", (new_task_id,step["input_id"]))
                c.execute("UPDATE chat_group_steps SET task_id=?,version=1 WHERE id=?", (new_task_id,step_id))
                step = {**dict(step), "task_id": new_task_id, "version": 1}
                version = 1
                existing = None
        elif decision.get("intent") == "clarify":
            owner = targets[0] if targets else None
            if existing:
                clarification_id = existing["id"]
                if existing["owner_member_id"] != owner:
                    c.execute("UPDATE chat_group_clarifications SET owner_member_id=?,missing_information=?,status='active',updated_at=? WHERE id=?",
                              (owner, json.dumps(decision.get("missing_information", []), ensure_ascii=False), now, clarification_id))
                    if owner is not None:
                        c.execute("UPDATE chat_group_members SET last_clarified_at=? WHERE id=? AND group_id=?", (now, owner, step["group_id"]))
                else:
                    c.execute("UPDATE chat_group_clarifications SET status='active',missing_information=?,updated_at=? WHERE id=?",
                              (json.dumps(decision.get("missing_information", []), ensure_ascii=False), now, clarification_id))
            else:
                input_row = c.execute("SELECT message FROM chat_group_task_inputs WHERE id=?", (step["input_id"],)).fetchone()
                clarification_id = c.execute(
                    "INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,status,created_at,updated_at) VALUES (?,?,?,?,?,?, 'active',?,?)",
                    (step["task_id"], step["group_id"], step["user_id"], owner, input_row["message"],
                     json.dumps(decision.get("missing_information", []), ensure_ascii=False), now, now)).lastrowid
                if owner is not None:
                    c.execute("UPDATE chat_group_members SET last_clarified_at=? WHERE id=? AND group_id=?", (now, owner, step["group_id"]))
        elif existing:
            c.execute("UPDATE chat_group_clarifications SET status='resolved',updated_at=? WHERE id=?", (now, existing["id"]))

        input_row = c.execute("SELECT message FROM chat_group_task_inputs WHERE id=? AND user_id=?", (step["input_id"], step["user_id"])).fetchone()
        previous_goal = c.execute("SELECT goal FROM chat_group_tasks WHERE id=?", (step["task_id"],)).fetchone()[0]
        goal = decision.get("goal") or previous_goal or input_row["message"]
        if existing and goal == input_row["message"] and goal != previous_goal:
            goal = previous_goal + "\n用户补充：" + input_row["message"]
        c.execute("UPDATE chat_group_tasks SET goal=?,owner_member_id=?,state='queued',updated_at=? WHERE id=? AND version=?",
                  (goal, targets[0] if targets else None, now, step["task_id"], version))
        payload = {"goal": goal, "missing_information": decision.get("missing_information", []),
                   "clarification_id": clarification_id, "owner_member_id": targets[0] if targets else None,
                   "source": "router"}
        c.execute("UPDATE chat_group_steps SET status='completed',result_json=?,finished_at=? WHERE id=?",
                  (json.dumps({**decision, "clarification_id": clarification_id}, ensure_ascii=False), now, step_id))
        route_usage = decision.get("usage")
        if not decision.get("usage_recorded") and (route_usage is not None or decision.get("usage_unknown")):
            call_id = f"group-route:{step_id}"
            usage_log_id = None
            if route_usage is not None:
                usage_log_id = c.execute("INSERT INTO usage_log(user_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) VALUES (?,'group_routing',?,?,?,?)",
                    (step["user_id"], route_usage.get("prompt_tokens", 0), route_usage.get("completion_tokens", 0), route_usage.get("total_tokens", 0), now)).lastrowid
            bot_id = None
            if targets:
                member = c.execute("SELECT bot_id FROM chat_group_members WHERE id=? AND group_id=?", (targets[0], step["group_id"])).fetchone()
                bot_id = member[0] if member else None
            if usage_log_id is not None and bot_id is not None:
                c.execute("UPDATE usage_log SET bot_id=? WHERE id=?", (bot_id, usage_log_id))
            c.execute("INSERT OR IGNORE INTO chat_group_usage_calls(call_id,user_id,group_id,task_id,step_id,kind,usage_log_id,usage_json,usage_unknown,created_at) VALUES (?,?,?,?,?,'group_routing',?,?,?,?)",
                      (call_id, step["user_id"], step["group_id"], step["task_id"], step_id, usage_log_id,
                       json.dumps(route_usage) if route_usage is not None else None, int(bool(decision.get("usage_unknown"))), now))
        if existing and decision.get("intent") != "replace":
            prior = c.execute("SELECT input_json FROM chat_group_steps WHERE task_id=? AND kind='member' AND json_extract(result_json,'$.action.kind')='await_user' ORDER BY id DESC LIMIT 1", (step["task_id"],)).fetchone()
            if prior:
                prior_input = json.loads(prior[0] or "{}")
                for field in ("consult_stack", "completion_criteria", "context_message_ids", "attachment_ids"):
                    if field in prior_input:
                        payload[field] = prior_input[field]
        request=json.loads(step["input_json"] or "{}")
        if request.get("reply_to_message_id"):
            payload["context_message_ids"]=list(dict.fromkeys(payload.get("context_message_ids",[])+[request["reply_to_message_id"]]))
            previous=c.execute("SELECT t.goal,t.id FROM chat_group_messages m JOIN chat_group_task_inputs i ON i.turn_id=m.turn_id JOIN chat_group_tasks t ON t.id=i.task_id WHERE m.id=? AND m.group_id=? AND m.user_id=? ORDER BY i.id DESC LIMIT 1",(request["reply_to_message_id"],step["group_id"],step["user_id"])).fetchone()
            if previous:
                payload["replied_task_goal"]=previous["goal"]
                payload["replied_task_requirements"]=[row[0] for row in c.execute("SELECT message FROM chat_group_task_inputs WHERE task_id=? AND user_id=? ORDER BY id",(previous["id"],step["user_id"]))]
        for order, member_id in enumerate(targets):
            action_key = f"member:{step['input_id']}:{member_id}:{order}"
            c.execute("INSERT OR IGNORE INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,input_json,created_at) VALUES (?,?,?,?,'member',?,?,?,'queued',?,?)",
                      (step["task_id"], step["input_id"], step["group_id"], step["user_id"], action_key, version, member_id,
                       json.dumps(payload, ensure_ascii=False), now))
        if not targets:
            c.execute("UPDATE chat_group_tasks SET state='failed',finished_at=?,updated_at=? WHERE id=?", (now, now, step["task_id"]))
        if targets and decision.get("intent") != "replace" and not decision.get("selection_override") and not request.get("target_member_ids") and not request.get("everyone"):
            _restore_pending(c,step,version,request.get("pending_members",[]),exclude=targets)
        _event(c, step["group_id"], step["user_id"], step["task_id"], version, "route_decided", payload)
        current_input=c.execute("SELECT t.user_message_id FROM chat_group_task_inputs i JOIN chat_group_turns t ON t.id=i.turn_id WHERE i.id=?",(step["input_id"],)).fetchone()
        if current_input:
            _message_event(c,step,"message_done",current_input[0])
        _state_events(c,step["group_id"],step["user_id"],step["task_id"],version)
        return True


def stop(user_id: int, group_id: int, task_id: int, expected_version: int):
    with tx(immediate=True) as c:
        row = c.execute("SELECT * FROM chat_group_tasks WHERE id=? AND group_id=? AND user_id=?", (task_id, group_id, user_id)).fetchone()
        if row is None:
            _not_found()
        if row["state"] == "stopped":
            return _task(row)
        if row["state"] in ("completed", "failed", "interrupted"):
            raise GroupExecutionError(409, "task_not_running", "当前任务已结束", _task(row))
        if row["version"] != expected_version:
            raise GroupExecutionError(409, "task_version_changed", "群任务已更新", _task(row))
        now, version = now_iso(), row["version"] + 1
        c.execute("UPDATE chat_group_tasks SET state='stopped',version=?,updated_at=?,finished_at=? WHERE id=? AND user_id=?",
                  (version, now, now, task_id, user_id))
        c.execute("UPDATE chat_group_steps SET status='stopped',finished_at=? WHERE task_id=? AND status='queued'",
                  (now, task_id))
        c.execute("UPDATE chat_group_clarifications SET status='cancelled',updated_at=? WHERE task_id=? AND status IN ('active','awaiting_user')", (now, task_id))
        _event(c, group_id, user_id, task_id, version, "task_stopped", {})
        _state_events(c,group_id,user_id,task_id,version)
        return _task(c.execute("SELECT * FROM chat_group_tasks WHERE id=?", (task_id,)).fetchone())


def is_current(step_id: int, lease_token: str, version: int) -> bool:
    with tx() as c:
        return _live_step(c, step_id, lease_token, version) is not None


def renew_lease(step_id: int, lease_token: str, version: int, expires_at: str) -> bool:
    with tx(immediate=True) as c:
        return c.execute("UPDATE chat_group_steps SET lease_expires_at=? WHERE id=? AND status='running' AND lease_token=? AND version=? AND EXISTS(SELECT 1 FROM chat_group_tasks t WHERE t.id=chat_group_steps.task_id AND t.version=? AND t.state='running')",
                         (expires_at, step_id, lease_token, version, version)).rowcount == 1


def interrupt_step(step_id: int, lease_token: str, *, stopped: bool = False, result: dict | None = None) -> bool:
    """Release a stale/shutdown lease while preserving its last committed text."""
    with tx(immediate=True) as c:
        step = c.execute("SELECT s.*,t.version AS task_version,i.turn_id FROM chat_group_steps s JOIN chat_group_tasks t ON t.id=s.task_id JOIN chat_group_task_inputs i ON i.id=s.input_id WHERE s.id=? AND s.lease_token=? AND s.status='running'",
                         (step_id, lease_token)).fetchone()
        if step is None:
            return False
        now = now_iso()
        saved = json.loads(step["result_json"] or "{}")
        message_id = saved.get("message_id")
        # A clear removed the message linkage; never recreate cleared content.
        if message_id and result and "content" in result:
            c.execute("UPDATE chat_group_messages SET content=? WHERE id=? AND user_id=? AND status='streaming'", (result["content"], message_id, step["user_id"]))
            saved.update(result)
            c.execute("UPDATE chat_group_steps SET result_json=? WHERE id=?", (json.dumps(saved,ensure_ascii=False), step_id))
        status = "stopped" if stopped or step["task_version"] != step["version"] else "interrupted"
        if message_id:
            row = c.execute("SELECT content FROM chat_group_messages WHERE id=?", (message_id,)).fetchone()
            body = (result or {}).get("content") if result and "content" in (result or {}) else (row["content"] if row else "")
            c.execute("UPDATE chat_group_messages SET status=?,finished_at=? WHERE id=? AND status='streaming'",
                      (_public_message_status(body, status), now, message_id))
        c.execute("UPDATE chat_group_steps SET status=?,finished_at=?,lease_token=NULL,lease_expires_at=NULL WHERE id=? AND lease_token=?",
                  (status, now, step_id, lease_token))
        c.execute("UPDATE chat_group_turns SET status=?,finished_at=? WHERE id=? AND status='running'",
                  (status, now, step["turn_id"]))
        if step["task_version"] == step["version"]:
            c.execute("UPDATE chat_group_tasks SET state='interrupted',updated_at=?,finished_at=? WHERE id=? AND version=?",
                      (now, now, step["task_id"], step["version"]))
        _event(c, step["group_id"], step["user_id"], step["task_id"], step["task_version"],
               "step_interrupted", {"step_id": step_id, "message_id": message_id, "status": status})
        if message_id:
            _message_event(c,{**dict(step),"version":step["task_version"]},"message_done",message_id)
        _state_events(c,step["group_id"],step["user_id"],step["task_id"],step["task_version"])
        return True


def recover_interrupted(now: str) -> int:
    """Never replay an in-flight model call after restart; queued steps remain claimable."""
    with tx(immediate=True) as c:
        running = c.execute("SELECT s.*,t.version AS task_version,i.turn_id FROM chat_group_steps s JOIN chat_group_tasks t ON t.id=s.task_id JOIN chat_group_task_inputs i ON i.id=s.input_id WHERE s.status='running'").fetchall()
        for step in running:
            result = json.loads(step["result_json"] or "{}")
            message_id = result.get("message_id")
            if message_id:
                row = c.execute("SELECT content FROM chat_group_messages WHERE id=?", (message_id,)).fetchone()
                c.execute("UPDATE chat_group_messages SET status=?,finished_at=? WHERE id=? AND status='streaming'",
                          (_public_message_status(row["content"] if row else "", "interrupted"), now, message_id))
            c.execute("UPDATE chat_group_steps SET status='interrupted',finished_at=?,lease_token=NULL,lease_expires_at=NULL WHERE id=?",
                      (now, step["id"]))
            c.execute("UPDATE chat_group_turns SET status='interrupted',finished_at=? WHERE id=? AND status='running'",
                      (now, step["turn_id"]))
            c.execute("UPDATE chat_group_tasks SET state='interrupted',updated_at=?,finished_at=? WHERE id=? AND version=? AND state='running'",
                      (now, now, step["task_id"], step["task_version"]))
            _event(c, step["group_id"], step["user_id"], step["task_id"], step["task_version"],
                   "step_interrupted", {"step_id": step["id"], "message_id": message_id})
        return len(running)


def events(user_id: int, group_id: int, after_id: int, limit: int = 100) -> list[dict]:
    with tx() as c:
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone() is None:
            _not_found()
        found = c.execute("SELECT id,group_id,task_id,version,kind,payload_json,created_at FROM chat_group_events WHERE user_id=? AND group_id=? AND id>? ORDER BY id LIMIT ?",
                          (user_id, group_id, after_id, min(max(limit, 1), 500))).fetchall()
        return [{"id": row["id"], "group_id":row["group_id"], "task_id": row["task_id"], "version": row["version"], "kind": row["kind"],
                 "payload": json.loads(row["payload_json"]), "created_at": row["created_at"]} for row in found]


def record_call(call_id: str, user_id: int, group_id: int, task_id: int | None, step_id: int | None,
                kind: str, usage: dict | None, usage_unknown: bool) -> bool:
    """A known late usage report may upgrade an unknown call exactly once."""
    with tx(immediate=True) as c:
        old = c.execute("SELECT * FROM chat_group_usage_calls WHERE call_id=? AND user_id=?", (call_id,user_id)).fetchone()
        if old and (old["usage_log_id"] is not None or usage is None):
            return False
        if c.execute("SELECT 1 FROM chat_groups WHERE id=? AND user_id=?", (group_id,user_id)).fetchone() is None:
            if old is None:
                _not_found()
            group_id,task_id,step_id = old["group_id"],old["task_id"],old["step_id"]
        log_id = None
        if usage is not None:
            member = c.execute("SELECT m.bot_id FROM chat_group_steps s JOIN chat_group_members m ON m.id=s.member_id WHERE s.id=? AND s.user_id=?", (step_id,user_id)).fetchone() if step_id else None
            log_id=c.execute("INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) VALUES (?,?,?,?,?,?,?)", (user_id,member[0] if member else None,kind,usage.get("prompt_tokens",0),usage.get("completion_tokens",0),usage.get("total_tokens",0),now_iso())).lastrowid
        if old:
            c.execute("UPDATE chat_group_usage_calls SET usage_log_id=?,usage_json=?,usage_unknown=? WHERE id=?", (log_id,json.dumps(usage),int(usage_unknown),old["id"]))
        else:
            c.execute("INSERT INTO chat_group_usage_calls(call_id,user_id,group_id,task_id,step_id,kind,usage_log_id,usage_json,usage_unknown,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)", (call_id,user_id,group_id,task_id,step_id,kind,log_id,json.dumps(usage) if usage is not None else None,int(usage_unknown),now_iso()))
        return True


def begin_member_call(step_id: int, lease_token: str, version: int) -> str:
    with tx(immediate=True) as c:
        step = _live_step(c,step_id,lease_token,version)
        if step is None:
            raise GroupExecutionError(409,"step_stale","任务已更新")
        row=c.execute("SELECT call_count,elapsed_ms FROM chat_group_task_inputs WHERE id=?", (step["input_id"],)).fetchone()
        if row["call_count"]>=6 or row["elapsed_ms"]>=240000:
            raise GroupExecutionError(429,"execution_limit","本轮自动调用额度已用完，请明确继续")
        count=row["call_count"]+1
        c.execute("UPDATE chat_group_task_inputs SET call_count=? WHERE id=?", (count,step["input_id"]))
        call_id=f"group-member:{uuid.uuid4()}"
        c.execute("INSERT INTO chat_group_usage_calls(call_id,user_id,group_id,task_id,step_id,kind,usage_unknown,created_at) VALUES (?,?,?,?,?,'group_chat',1,?)",(call_id,step["user_id"],step["group_id"],step["task_id"],step_id,now_iso()))
        return call_id


def referenced_message_ids(user_id: int, group_id: int, message_ids: list[int], attachment_ids: list[str]) -> list[int]:
    if not validate_action_references(user_id, group_id, message_ids, attachment_ids):
        _not_found()
    with tx() as c:
        result = list(message_ids)
        for attachment_id in attachment_ids:
            row = c.execute("SELECT message_id FROM chat_group_attachments WHERE attachment_id=? AND group_id=? AND user_id=?", (attachment_id, group_id, user_id)).fetchone()
            if row and row[0] not in result:
                result.append(row[0])
        return result
