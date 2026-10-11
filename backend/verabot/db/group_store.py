"""Tenant-scoped group SQL and short atomic mutations; never holds a model call."""
import hashlib
import json

from .database import now_iso, tx
from .group_types import Group, GroupChatInput, GroupMessage, GroupTurn

class GroupStoreError(Exception):
    def __init__(self, status, code, message, turn_id=None):
        super().__init__(message)
        self.status, self.code, self.message, self.turn_id = status, code, message, turn_id

def _missing():
    raise GroupStoreError(404, "not_found", "群或记录不存在")

def _group(c, user_id: int, group_id: int) -> Group:
    raw = c.execute("SELECT * FROM chat_groups WHERE id=? AND user_id=?", (group_id, user_id)).fetchone()
    if raw is None: _missing()
    found = dict(raw)
    members = []
    for r in c.execute(
        "SELECT m.*, b.name AS live_name,b.color AS live_color,b.avatar AS live_avatar,b.persona AS live_detail,"
        "b.appearance AS live_appearance FROM chat_group_members m LEFT JOIN bots b "
        "ON b.id=m.bot_id AND b.user_id=m.user_id WHERE m.user_id=? AND m.group_id=? ORDER BY m.position",
        (user_id, group_id)):
        snapshot = json.loads(r["appearance_snapshot"])
        available = r["bot_id"] is not None and r["live_name"] is not None
        members.append({"id": r["id"], "bot_id": r["bot_id"] if available else None,
                        "name": r["live_name"] if available else r["name_snapshot"],
                        "color": r["live_color"] if available else snapshot["color"],
                        "avatar": r["live_avatar"] if available else snapshot["avatar"],
                        "detail": (r["live_detail"] or "") if available else snapshot["detail"],
                        "appearance": json.loads(r["live_appearance"]) if available and r["live_appearance"]
                                      else snapshot.get("appearance"), "available": available})
    active = [m["bot_id"] for m in members if m["available"]]
    default = found["default_bot_id"]
    latest=c.execute('SELECT * FROM chat_group_messages WHERE user_id=? AND group_id=? ORDER BY id DESC LIMIT 1',(user_id,group_id)).fetchone()
    active_turn=c.execute("SELECT id FROM chat_group_turns WHERE user_id=? AND group_id=? AND status='running'",(user_id,group_id)).fetchone()
    return {"id": group_id, "name": found["name"], "members": members,
            "last_message": _message(latest,c) if latest else None, "active_turn_id": active_turn[0] if active_turn else None,
            "default_bot_id": default if default in active else (active[0] if active else None),
            "read_only": not active, "created_at": found["created_at"], "updated_at": found["updated_at"]}

def get_group(user_id: int, group_id: int) -> Group:
    with tx() as c: return _group(c, user_id, group_id)

def list_groups(user_id: int) -> list[Group]:
    with tx() as c:
        ids = [r[0] for r in c.execute("SELECT id FROM chat_groups WHERE user_id=? ORDER BY updated_at DESC,id DESC", (user_id,))]
        return [_group(c, user_id, gid) for gid in ids]

def create_group(user_id: int, name: str, bot_ids: list[int], default_bot_id: int) -> Group:
    with tx(immediate=True) as c:
        if c.execute("SELECT COUNT(*) FROM chat_groups WHERE user_id=?", (user_id,)).fetchone()[0] >= 10:
            raise GroupStoreError(422, "group_limit", "最多创建 10 个群")
        bots = []
        for bid in bot_ids:
            r = c.execute("SELECT * FROM bots WHERE id=? AND user_id=?", (bid, user_id)).fetchone()
            if r is None: raise GroupStoreError(422, "invalid_member", "成员必须是你自己的 Bot")
            bots.append(dict(r))
        now = now_iso()
        gid = c.execute("INSERT INTO chat_groups(user_id,name,default_bot_id,created_at,updated_at) VALUES (?,?,?,?,?)",
                        (user_id, name, default_bot_id, now, now)).lastrowid
        for position, bot in enumerate(bots):
            snapshot = {"avatar": bot["avatar"], "color": bot["color"], "detail": bot["persona"],
                        "appearance": json.loads(bot["appearance"]) if bot.get("appearance") else None}
            c.execute("INSERT INTO chat_group_members(group_id,user_id,bot_id,position,name_snapshot,appearance_snapshot)"
                      " VALUES (?,?,?,?,?,?)", (gid, user_id, bot["id"], position, bot["name"], json.dumps(snapshot)))
        return _group(c, user_id, gid)

def _not_busy(c, user_id, group_id):
    running = c.execute("SELECT id FROM chat_group_turns WHERE user_id=? AND group_id=? AND status='running'",
                        (user_id, group_id)).fetchone()
    if running: raise GroupStoreError(409, "group_busy", "请先停止当前讨论", running[0])

def change_group(user_id: int, group_id: int, patch: dict) -> Group:
    with tx(immediate=True) as c:
        group = _group(c, user_id, group_id)
        _not_busy(c, user_id, group_id)
        if patch.get("default_bot_id") is not None and patch["default_bot_id"] not in [
                m["bot_id"] for m in group["members"] if m["available"]]:
            raise GroupStoreError(422, "invalid_member", "默认回应者必须是可用成员")
        for key in ("name", "default_bot_id"):
            if patch.get(key) is not None:
                c.execute(f"UPDATE chat_groups SET {key}=?,updated_at=? WHERE user_id=? AND id=?",
                          (patch[key], now_iso(), user_id, group_id))
        return _group(c, user_id, group_id)

def delete_group(user_id, group_id, *, clear_only=False):
    with tx(immediate=True) as c:
        _group(c, user_id, group_id); _not_busy(c, user_id, group_id)
        if clear_only:
            c.execute("DELETE FROM chat_group_turns WHERE user_id=? AND group_id=?", (user_id, group_id))
            c.execute("UPDATE chat_groups SET updated_at=? WHERE id=? AND user_id=?", (now_iso(), group_id, user_id))
        else:
            c.execute("DELETE FROM chat_groups WHERE user_id=? AND id=?", (user_id, group_id))

def _message(r, c) -> GroupMessage:
    m = dict(r)
    turn=c.execute('SELECT retry_of_message_id FROM chat_group_turns WHERE id=? AND user_id=?',(m['turn_id'],m['user_id'])).fetchone()
    return {"id": m["id"], "retry_of_message_id": turn[0] if turn else None, "group_id": m["group_id"], "turn_id": m["turn_id"], "member_id": m["member_id"],
            "role": m["role"], "content": m["content"], "status": m["status"],
            "sender_name": m["sender_name_snapshot"], "sender_appearance": json.loads(m["sender_appearance_snapshot"])
            if m["sender_appearance_snapshot"] else None,
            "usage": json.loads(m["usage_json"]) if m["usage_json"] else None, "created_at": m["created_at"],
            "finished_at": m["finished_at"]}

def list_messages(user_id, group_id, before_id=None, limit=50):
    with tx() as c:
        _group(c, user_id, group_id)
        rs = c.execute("SELECT * FROM chat_group_messages WHERE user_id=? AND group_id=? AND id<? ORDER BY id DESC LIMIT ?",
                       (user_id, group_id, before_id if before_id is not None else 9223372036854775807, min(limit, 100)+1)).fetchall()
        more = len(rs) > min(limit, 100)
        page = list(reversed(rs[:min(limit, 100)]))
        return {"messages": [_message(r,c) for r in page], "next_before_id": page[0]["id"] if more and page else None}

def _turn(c, user_id: int, group_id: int, turn_id: int) -> GroupTurn:
    _group(c, user_id, group_id)
    r = c.execute("SELECT * FROM chat_group_turns WHERE id=? AND user_id=? AND group_id=?",
                  (turn_id, user_id, group_id)).fetchone()
    if r is None: _missing()
    out = dict(r)
    for key in ("user_id", "request_hash"): out.pop(key)
    out["cancel_requested"] = bool(out["cancel_requested"])
    out["messages"] = [_message(r,c) for r in c.execute(
        "SELECT * FROM chat_group_messages WHERE user_id=? AND group_id=? AND turn_id=? ORDER BY id",
        (user_id, group_id, turn_id))]
    return out

def get_turn(user_id: int, group_id: int, turn_id: int) -> GroupTurn:
    with tx() as c: return _turn(c, user_id, group_id, turn_id)

def claim_turn(user_id: int, group_id: int, request: GroupChatInput, *, retry_of_message_id: int | None = None) -> GroupTurn:
    from ..api.group_schemas import GroupChatIn
    body = GroupChatIn.model_validate(request).model_dump(mode="json")
    digest = hashlib.sha256(json.dumps({**body, "retry_of_message_id": retry_of_message_id},
                                      sort_keys=True).encode()).hexdigest()
    with tx(immediate=True) as c:
        group = _group(c, user_id, group_id)
        old = c.execute("SELECT id,request_hash FROM chat_group_turns WHERE user_id=? AND group_id=? AND client_request_id=?",
                        (user_id, group_id, body["client_request_id"])).fetchone()
        if old:
            code = "request_exists" if old["request_hash"] == digest else "idempotency_conflict"
            raise GroupStoreError(409, code, "请求已存在" if code == "request_exists" else "请求 ID 对应不同内容", old["id"])
        _not_busy(c, user_id, group_id)
        original = None
        if retry_of_message_id is not None:
            original = c.execute("SELECT m.*,t.user_message_id,t.context_end_message_id FROM chat_group_messages m "
                "JOIN chat_group_turns t ON t.id=m.turn_id AND t.user_id=m.user_id "
                "WHERE m.id=? AND m.user_id=? AND m.group_id=? AND m.role='bot'",
                (retry_of_message_id,user_id,group_id)).fetchone()
            if original is None: _missing()
            if original['status'] not in ('failed','stopped','interrupted'):
                raise GroupStoreError(422, 'retry_invalid', '只能重试未完成的回复')
        if group["read_only"]: raise GroupStoreError(409, "group_read_only", "群里已没有可用成员")
        target = None
        if body["mode"] == "single":
            bid = body["target_bot_id"] or group["default_bot_id"]
            target = next((m for m in group["members"] if m["bot_id"] == bid and m["available"]), None)
            if target is None: raise GroupStoreError(422, "invalid_member", "点名的 Bot 不是可用群成员")
        now = now_iso()
        tid = c.execute("INSERT INTO chat_group_turns(user_id,group_id,client_request_id,request_hash,mode,target_member_id,"
                        "status,created_at) VALUES (?,?,?,?,?,?,'running',?)",
                        (user_id, group_id, body["client_request_id"], digest, body["mode"], target["id"] if target else None, now)).lastrowid
        if original is None:
            mid = c.execute("INSERT INTO chat_group_messages(user_id,group_id,turn_id,role,content,status,created_at,finished_at)"
                            " VALUES (?,?,?,'user',?,'completed',?,?)", (user_id, group_id, tid, body["message"], now, now)).lastrowid
            context_end = mid
        else:
            if target['id'] != original['member_id']:
                raise GroupStoreError(422, 'retry_invalid', '重试成员不匹配')
            mid, context_end = original['user_message_id'], original['context_end_message_id']
        c.execute("UPDATE chat_group_turns SET user_message_id=?,context_end_message_id=?,retry_of_message_id=? WHERE id=? AND user_id=?",
                  (mid, context_end, retry_of_message_id, tid, user_id))
        c.execute("UPDATE chat_groups SET updated_at=? WHERE id=? AND user_id=?", (now, group_id, user_id))
        return _turn(c, user_id, group_id, tid)

def start_reply(user_id: int, group_id: int, turn_id: int, member_id: int) -> GroupMessage:
    with tx(immediate=True) as c:
        turn = _turn(c, user_id, group_id, turn_id)
        if turn["status"] != "running" or turn["cancel_requested"]:
            raise GroupStoreError(409, "turn_stopped", "讨论已停止")
        member = next((m for m in _group(c, user_id, group_id)["members"] if m["id"] == member_id and m["available"]), None)
        if member is None: raise GroupStoreError(422, "invalid_member", "成员已不可用")
        mid = c.execute("INSERT INTO chat_group_messages(user_id,group_id,turn_id,role,member_id,status,sender_name_snapshot,"
                        "sender_appearance_snapshot,created_at) VALUES (?,?,?,'bot',?,'streaming',?,?,?)",
                        (user_id, group_id, turn_id, member_id, member["name"], json.dumps(member), now_iso())).lastrowid
        return _message(c.execute("SELECT * FROM chat_group_messages WHERE id=? AND user_id=?", (mid, user_id)).fetchone(),c)

def save_reply(user_id: int, message_id: int, content: str, status: str, usage: dict | None, *, finalize: bool) -> GroupMessage:
    if status not in ("streaming","completed","failed","stopped","interrupted"):
        raise ValueError("invalid message status")
    if finalize == (status == "streaming"):
        raise ValueError("finalize must match terminal status")
    with tx(immediate=True) as c:
        r = c.execute("SELECT * FROM chat_group_messages WHERE id=? AND user_id=? AND role='bot'",
                      (message_id, user_id)).fetchone()
        if r is None: _missing()
        if r["status"] != "streaming": return _message(r,c)
        if usage is not None and finalize and not r["usage_logged"]:
            member = c.execute("SELECT bot_id FROM chat_group_members WHERE id=? AND user_id=?", (r["member_id"], user_id)).fetchone()
            c.execute("INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at)"
                      " VALUES (?,?,'group_chat',?,?,?,?)",
                      (user_id, member[0] if member else None, int(usage.get("prompt_tokens") or 0),
                       int(usage.get("completion_tokens") or 0), int(usage.get("total_tokens") or 0), now_iso()))
        c.execute("UPDATE chat_group_messages SET content=?,status=?,usage_json=?,usage_logged=?,finished_at=? WHERE id=? AND user_id=?",
                  (content, status, json.dumps(usage) if usage is not None else None,
                   int(finalize and usage is not None), now_iso() if finalize else None, message_id, user_id))
        return _message(c.execute("SELECT * FROM chat_group_messages WHERE id=? AND user_id=?", (message_id, user_id)).fetchone(),c)

def finish_turn(user_id: int, group_id: int, turn_id: int, status: str) -> GroupTurn:
    if status not in ("completed","partial","stopped","failed","interrupted"): raise ValueError("invalid turn status")
    with tx(immediate=True) as c:
        _turn(c, user_id, group_id, turn_id)
        c.execute("UPDATE chat_group_turns SET status=?,finished_at=?,context_end_message_id=CASE WHEN retry_of_message_id IS NULL THEN (SELECT MAX(id) FROM chat_group_messages WHERE turn_id=chat_group_turns.id) ELSE context_end_message_id END WHERE id=? AND group_id=? AND user_id=? AND status='running'",
                  (status, now_iso(), turn_id, group_id, user_id))
        return _turn(c, user_id, group_id, turn_id)

def request_stop(user_id: int, group_id: int, turn_id: int) -> GroupTurn:
    with tx(immediate=True) as c:
        _turn(c, user_id, group_id, turn_id)
        c.execute("UPDATE chat_group_turns SET cancel_requested=1 WHERE id=? AND group_id=? AND user_id=? AND status='running'",
                  (turn_id, group_id, user_id))
        return _turn(c, user_id, group_id, turn_id)


def get_message(user_id: int, group_id: int, message_id: int) -> GroupMessage:
    with tx() as c:
        _group(c,user_id,group_id)
        row = c.execute('SELECT * FROM chat_group_messages WHERE user_id=? AND group_id=? AND id=?',
                        (user_id,group_id,message_id)).fetchone()
        if row is None: _missing()
        return _message(row,c)


def claim_retry(user_id: int, group_id: int, message_id: int, request_id: str) -> GroupTurn:
    message = get_message(user_id,group_id,message_id)
    turn = get_turn(user_id,group_id,message['turn_id'])
    question = get_message(user_id,group_id,turn['user_message_id'])
    group = get_group(user_id,group_id)
    member = next((m for m in group['members'] if m['id']==message['member_id'] and m['available']),None)
    if not member: raise GroupStoreError(422,'invalid_member','原回应者已不可用')
    return claim_turn(user_id,group_id,{'client_request_id':request_id,'message':question['content'],
        'mode':'single','target_bot_id':member['bot_id']},retry_of_message_id=message_id)


def context_messages(user_id: int, group_id: int, turn: GroupTurn) -> list[GroupMessage]:
    with tx() as c:
        _turn(c,user_id,group_id,turn['id'])
        rows = c.execute("SELECT * FROM chat_group_messages WHERE user_id=? AND group_id=? AND status='completed' "
            "AND (id<=? OR turn_id=?) ORDER BY id DESC LIMIT 24",
            (user_id,group_id,turn['context_end_message_id'],turn['id'])).fetchall()
        result = [_message(r,c) for r in reversed(rows)]
        if not any(m['id']==turn['user_message_id'] for m in result):
            question = c.execute('SELECT * FROM chat_group_messages WHERE id=? AND user_id=? AND group_id=?',
                (turn['user_message_id'],user_id,group_id)).fetchone()
            if question: result = [_message(question,c)] + result[-23:]
        return result


def recover_interrupted_turns() -> int:
    with tx(immediate=True) as c:
        count=c.execute("SELECT COUNT(*) FROM chat_group_turns WHERE status='running'").fetchone()[0]
        for row in c.execute("SELECT m.*,gm.bot_id FROM chat_group_messages m LEFT JOIN chat_group_members gm "
                             "ON gm.id=m.member_id AND gm.user_id=m.user_id WHERE m.status='streaming'").fetchall():
            if row['usage_json'] is not None and not row['usage_logged']:
                usage=json.loads(row['usage_json'])
                c.execute("INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) "
                          "VALUES (?,?,'group_chat',?,?,?,?)",(row['user_id'],row['bot_id'],
                          int(usage.get('prompt_tokens') or 0),int(usage.get('completion_tokens') or 0),
                          int(usage.get('total_tokens') or 0),now_iso()))
                c.execute('UPDATE chat_group_messages SET usage_logged=1 WHERE id=?',(row['id'],))
        c.execute("UPDATE chat_group_messages SET status='interrupted',finished_at=? WHERE status='streaming'",
                  (now_iso(),))
        c.execute("UPDATE chat_group_turns SET status='interrupted',finished_at=?,context_end_message_id=CASE "
                  "WHEN retry_of_message_id IS NULL THEN (SELECT MAX(id) FROM chat_group_messages WHERE turn_id=chat_group_turns.id) "
                  "ELSE context_end_message_id END WHERE status='running'",(now_iso(),))
        return count


def existing_request(user_id,group_id,request_id):
    with tx() as c:
        _group(c,user_id,group_id)
        return c.execute('SELECT id FROM chat_group_turns WHERE user_id=? AND group_id=? AND client_request_id=?',
                         (user_id,group_id,str(request_id))).fetchone() is not None
