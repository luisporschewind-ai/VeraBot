"""v34 -> v35: 过时的失败 / 中断任务不再充当会话当前状态；工具 trace 落库瘦身。

1. chat_reply_tasks / owned_tasks 加 superseded_at。同一会话（同一 Bot、同一代）里，失败 / 中断之后
   又有一条正常完成的助手回复（source_kind 为空），或之后又有任务完成，旧任务即标记 superseded_at，
   会话摘要 work_items 不再包含它。由触发器在写入时维护；任务重新进入非终态时清空标记。
   存量数据按同一规则回填一次。不删除任何消息或任务。
2. messages.traces、chat_reply_events 里的工具结果按 core.trace_slim 瘦身（read_file 去原文，
   其他长字符串截到 2000 字）。迁移前备份 verabot.db.bak-before-v35-<时间戳>。
"""
import json
import sqlite3

from ...core.trace_slim import TEXT_LIMIT, slim_trace, slim_traces
from ._util import _add_column

NOW = "strftime('%Y-%m-%dT%H:%M:%S+00:00','now')"
STALE = "state IN ('failed','interrupted') AND superseded_at IS NULL"

TRIGGERS = [
    # 正常完成的助手回复（持久回复完成、旧版流式写入、操作结果说明）。owned_task / scheduled_task 投递不算。
    f'''CREATE TRIGGER IF NOT EXISTS supersede_stale_work_reply_insert AFTER INSERT ON messages
 WHEN NEW.role='assistant' AND NEW.message_status='completed' AND NEW.source_kind IS NULL BEGIN
 UPDATE chat_reply_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND bot_id=NEW.bot_id
  AND generation=NEW.conversation_generation AND output_message_id<NEW.id AND {STALE};
 UPDATE owned_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND owner_bot_id=NEW.bot_id
  AND delivery_generation=NEW.conversation_generation AND {STALE};
END''',
    f'''CREATE TRIGGER IF NOT EXISTS supersede_stale_work_reply_update AFTER UPDATE OF message_status ON messages
 WHEN NEW.role='assistant' AND NEW.message_status='completed' AND OLD.message_status<>'completed' AND NEW.source_kind IS NULL BEGIN
 UPDATE chat_reply_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND bot_id=NEW.bot_id
  AND generation=NEW.conversation_generation AND output_message_id<NEW.id AND {STALE};
 UPDATE owned_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND owner_bot_id=NEW.bot_id
  AND delivery_generation=NEW.conversation_generation AND {STALE};
END''',
    f'''CREATE TRIGGER IF NOT EXISTS supersede_stale_work_owned_completed AFTER UPDATE OF state ON owned_tasks
 WHEN NEW.state='completed' AND OLD.state<>'completed' AND NEW.owner_bot_id IS NOT NULL BEGIN
 UPDATE chat_reply_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND bot_id=NEW.owner_bot_id
  AND generation=NEW.delivery_generation AND {STALE};
 UPDATE owned_tasks SET superseded_at={NOW} WHERE user_id=NEW.user_id AND owner_bot_id=NEW.owner_bot_id
  AND delivery_generation=NEW.delivery_generation AND id<>NEW.id AND {STALE};
END''',
    '''CREATE TRIGGER IF NOT EXISTS superseded_chat_task_reopened AFTER UPDATE OF state ON chat_reply_tasks
 WHEN NEW.superseded_at IS NOT NULL AND NEW.state NOT IN ('failed','interrupted') BEGIN
 UPDATE chat_reply_tasks SET superseded_at=NULL WHERE id=NEW.id;
END''',
    '''CREATE TRIGGER IF NOT EXISTS superseded_owned_task_reopened AFTER UPDATE OF state ON owned_tasks
 WHEN NEW.superseded_at IS NOT NULL AND NEW.state NOT IN ('failed','interrupted') BEGIN
 UPDATE owned_tasks SET superseded_at=NULL WHERE id=NEW.id;
END''',
]

REPLY = ("m.role='assistant' AND m.message_status='completed' AND m.source_kind IS NULL")

BACKFILL_CHAT = f'''UPDATE chat_reply_tasks SET superseded_at={NOW} WHERE {STALE} AND (
 EXISTS(SELECT 1 FROM messages m WHERE m.user_id=chat_reply_tasks.user_id AND m.bot_id=chat_reply_tasks.bot_id
  AND m.conversation_generation=chat_reply_tasks.generation AND {REPLY} AND m.id>chat_reply_tasks.output_message_id)
 OR EXISTS(SELECT 1 FROM chat_reply_tasks n WHERE n.user_id=chat_reply_tasks.user_id AND n.bot_id=chat_reply_tasks.bot_id
  AND n.generation=chat_reply_tasks.generation AND n.state='completed' AND n.id>chat_reply_tasks.id)
 OR EXISTS(SELECT 1 FROM owned_tasks o WHERE o.user_id=chat_reply_tasks.user_id AND o.owner_bot_id=chat_reply_tasks.bot_id
  AND o.delivery_generation=chat_reply_tasks.generation AND o.state='completed' AND o.updated_at>chat_reply_tasks.updated_at))'''

BACKFILL_OWNED = f'''UPDATE owned_tasks SET superseded_at={NOW} WHERE {STALE} AND owner_bot_id IS NOT NULL AND (
 EXISTS(SELECT 1 FROM messages m WHERE m.user_id=owned_tasks.user_id AND m.bot_id=owned_tasks.owner_bot_id
  AND m.conversation_generation=owned_tasks.delivery_generation AND {REPLY} AND m.created_at>owned_tasks.updated_at)
 OR EXISTS(SELECT 1 FROM chat_reply_tasks n WHERE n.user_id=owned_tasks.user_id AND n.bot_id=owned_tasks.owner_bot_id
  AND n.generation=owned_tasks.delivery_generation AND n.state='completed' AND n.updated_at>owned_tasks.updated_at)
 OR EXISTS(SELECT 1 FROM owned_tasks o WHERE o.user_id=owned_tasks.user_id AND o.owner_bot_id=owned_tasks.owner_bot_id
  AND o.delivery_generation=owned_tasks.delivery_generation AND o.id<>owned_tasks.id AND o.state='completed'
  AND o.updated_at>owned_tasks.updated_at))'''


def _slim_event_payload(event: str, payload):
    if not isinstance(payload, dict):
        return payload
    if event == 'tool_result':
        payload = slim_trace(payload)
    if isinstance(payload.get('traces'), list):
        payload = {**payload, 'traces': slim_traces(payload['traces'])}
    task = payload.get('task')
    if isinstance(task, dict) and isinstance(task.get('traces'), list):
        payload = {**payload, 'task': {**task, 'traces': slim_traces(task['traces'])}}
    return payload


def slim_existing_traces(c) -> int:
    """存量 messages.traces 与 chat_reply_events 瘦身；返回改写的行数。"""
    changed = 0
    ids = [r[0] for r in c.execute(
        "SELECT id FROM messages WHERE traces IS NOT NULL AND (length(traces)>? OR traces LIKE '%\"read_file\"%')",
        (TEXT_LIMIT,)).fetchall()]
    for mid in ids:
        raw = c.execute('SELECT traces FROM messages WHERE id=?', (mid,)).fetchone()[0]
        try:
            traces = json.loads(raw)
        except (TypeError, ValueError):
            continue
        slim = slim_traces(traces)
        if slim != traces:
            c.execute('UPDATE messages SET traces=? WHERE id=?', (json.dumps(slim, ensure_ascii=False), mid))
            changed += 1
    ids = [r[0] for r in c.execute(
        "SELECT id FROM chat_reply_events WHERE length(payload_json)>? OR payload_json LIKE '%\"read_file\"%'",
        (TEXT_LIMIT,)).fetchall()]
    for eid in ids:
        event, raw = c.execute('SELECT event,payload_json FROM chat_reply_events WHERE id=?', (eid,)).fetchone()
        try:
            payload = json.loads(raw)
        except (TypeError, ValueError):
            continue
        slim = _slim_event_payload(event, payload)
        if slim != payload:
            c.execute('UPDATE chat_reply_events SET payload_json=? WHERE id=?', (json.dumps(slim, ensure_ascii=False), eid))
            changed += 1
    return changed


def migrate(c, ver: int) -> None:
    _add_column(c, 'chat_reply_tasks', 'superseded_at', 'TEXT')
    _add_column(c, 'owned_tasks', 'superseded_at', 'TEXT')
    for sql in TRIGGERS:
        c.execute(sql)
    if ver < 35:
        c.execute(BACKFILL_CHAT)
        c.execute(BACKFILL_OWNED)
        slim_existing_traces(c)


def backup_before_v35():
    from pathlib import Path
    from datetime import datetime
    from ..database import DB_PATH
    path = Path(DB_PATH)
    if not path.is_file():
        return
    source = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    try:
        try:
            version = source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError:
            return
        if not version or int(version[0]) >= 35:
            return
        destination = path.with_name(path.name + '.bak-before-v35-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        target = sqlite3.connect(destination)
        try:
            source.backup(target)
        finally:
            target.close()
        destination.chmod(0o600)
    finally:
        source.close()
