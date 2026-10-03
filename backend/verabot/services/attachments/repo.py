"""附件元数据（SQLite）+ 文件生命周期。所有查询都带 user_id（租户隔离）。

写入：处理图片 → 写文件（原子）→ 插库；插库失败立即删文件。
删除：先删库行并提交，再删文件（文件删除失败只会留下孤儿文件，由对账清理）。
对账：启动时一次、之后每天一次——pending 过期删除；磁盘有库里没有且超过 1 小时的文件删除；
库里有磁盘没有只记日志（接口返回 410）。
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import logging
import os
import time
from datetime import datetime, timedelta, timezone

from ... import db
from ...core.config import (ATTACHMENT_MAX_BYTES, ATTACHMENT_PENDING_TTL_HOURS, ATTACHMENT_USER_QUOTA_BYTES,
                            ATTACHMENTS_PER_DAY, TIMEZONE)
from . import images
from .store import get_store

log = logging.getLogger("verabot.attachments")

MAX_PER_MESSAGE = 1
ORPHAN_GRACE_SECONDS = 3600
GONE_MESSAGE = "图片已删除或无法加载"


class AttachmentError(Exception):
    def __init__(self, status: int, message: str, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code


def new_id() -> str:
    return "att_" + base64.b32encode(os.urandom(16)).decode().rstrip("=").lower()


def public(r: dict) -> dict:
    """接口字段（iOS `Attachment` 的 CodingKeys 必须与此一致，见 ATT-CONTRACT）。"""
    return {"id": r["id"], "kind": r["kind"], "mime": r["mime"], "width": r["width"], "height": r["height"],
            "bytes": r["bytes"], "status": r["status"], "expires_at": r["expires_at"]}


def still_key(r: dict) -> str | None:
    key = r["storage_key"]
    return key[: -len(".gif")] + "_still.jpg" if key.endswith(".gif") else None


def file_keys(r: dict) -> list[str]:
    return [k for k in (r["storage_key"], r.get("thumb_key"), still_key(r)) if k]


def delete_files(keys) -> None:
    store = get_store()
    for k in keys:
        try:
            store.delete(k)
        except OSError as e:   # 留给对账
            log.warning("attachment file delete failed %s: %s", k, e)


# ---------------------------------------------------------------- 上传
def create(user_id: int, bot_id: int | None, data: bytes) -> dict:
    if bot_id is not None and not db.get_bot(user_id, bot_id):
        raise AttachmentError(404, "Bot 不存在")
    with db.tx() as c:
        n_today = c.execute("SELECT COUNT(*) FROM attachments WHERE user_id=? AND created_at>=?",
                            (user_id, db.day_start_utc(TIMEZONE))).fetchone()[0]
        used = c.execute("SELECT COALESCE(SUM(bytes),0) FROM attachments WHERE user_id=?", (user_id,)).fetchone()[0]
    if n_today >= ATTACHMENTS_PER_DAY:
        raise AttachmentError(429, f"今天的图片已达上限（{ATTACHMENTS_PER_DAY} 张），请明天再试", "attachment_daily_limit")
    try:
        p = images.process(data, ATTACHMENT_MAX_BYTES)
    except images.ImageError as e:
        raise AttachmentError(e.status, e.message)
    if used + len(p.data) > ATTACHMENT_USER_QUOTA_BYTES:
        raise AttachmentError(413, "图片存储空间已满，请清理旧对话后再试", "attachment_storage_full")

    att_id = new_id()
    base = f"u{user_id}/{att_id[4:6]}/{att_id}"
    key, thumb_key = f"{base}.{p.ext}", f"{base}_thumb.jpg"
    row = {"id": att_id, "storage_key": key, "thumb_key": thumb_key}
    store = get_store()
    written: list[str] = []
    try:
        for k, blob in ((key, p.data), (thumb_key, p.thumb), (still_key(row), p.still)):
            if k and blob is not None:
                store.put(k, blob)
                written.append(k)
        now = datetime.now(timezone.utc)
        expires = (now + timedelta(hours=ATTACHMENT_PENDING_TTL_HOURS)).isoformat(timespec="seconds")
        with db.tx() as c:
            c.execute(
                "INSERT INTO attachments(id,user_id,bot_id,message_id,kind,mime,bytes,width,height,sha256,"
                "storage_backend,storage_key,thumb_key,status,created_at,expires_at)"
                " VALUES (?,?,?,NULL,'image',?,?,?,?,?,?,?,?,'pending',?,?)",
                (att_id, user_id, bot_id, p.mime, len(p.data), p.width, p.height,
                 hashlib.sha256(p.data).hexdigest(), store.backend, key, thumb_key,
                 now.isoformat(timespec="seconds"), expires))
    except BaseException:
        delete_files(written)
        raise
    return get_public(user_id, att_id)


# ---------------------------------------------------------------- 查询
def get(user_id: int, att_id: str) -> dict | None:
    if not isinstance(att_id, str) or not att_id.startswith("att_") or len(att_id) > 40:
        return None
    with db.tx() as c:
        return db.row(c.execute("SELECT * FROM attachments WHERE id=? AND user_id=?", (att_id, user_id)).fetchone())


def get_public(user_id: int, att_id: str) -> dict | None:
    r = get(user_id, att_id)
    return public(r) if r else None


def file_path(r: dict, variant: str = "content"):
    """variant: content / thumb / model（GIF 给模型的第一帧）。文件不在返回 None（→ 410）。"""
    key = {"content": r["storage_key"], "thumb": r.get("thumb_key"),
           "model": still_key(r) or r["storage_key"]}[variant]
    return get_store().path(key) if key else None


def for_messages(user_id: int, message_ids) -> dict[int, list[dict]]:
    ids = [int(i) for i in message_ids if i is not None]
    if not ids:
        return {}
    out: dict[int, list[dict]] = {}
    with db.tx() as c:
        q = ",".join("?" * len(ids))
        for r in c.execute(f"SELECT * FROM attachments WHERE user_id=? AND message_id IN ({q}) ORDER BY created_at, id",
                           (user_id, *ids)).fetchall():
            out.setdefault(r["message_id"], []).append(dict(r))
    return out


def latest_in(user_id: int, bot_id: int, message_ids) -> dict | None:
    """历史窗口里最近一张已发送的图（关键词兜底召回用）。"""
    rows = [r for rs in for_messages(user_id, message_ids).values() for r in rs if r["bot_id"] == bot_id]
    return max(rows, key=lambda r: (r["message_id"], r["created_at"])) if rows else None


# ---------------------------------------------------------------- 发送 / 绑定
def check_pending(user_id: int, bot_id: int, ids: list[str]) -> list[dict]:
    """发送前校验：数量、归属、状态、过期、Bot。失败抛 AttachmentError（路由转 4xx）。"""
    if len(ids) > MAX_PER_MESSAGE:
        raise AttachmentError(422, f"每条消息最多 {MAX_PER_MESSAGE} 张图片")
    out = []
    now = db.now_iso()
    for att_id in ids:
        r = get(user_id, att_id)
        if not r:
            raise AttachmentError(404, "图片不存在")
        if r["status"] != "pending":
            raise AttachmentError(409, "这张图片已经发送过了")
        if r["expires_at"] and r["expires_at"] < now:
            raise AttachmentError(410, "图片已过期，请重新选择")
        if r["bot_id"] is not None and r["bot_id"] != bot_id:
            raise AttachmentError(422, "图片不属于这个对话")
        if not get_store().exists(r["storage_key"]):
            raise AttachmentError(410, GONE_MESSAGE)
        out.append(r)
    return out


def attach(user_id: int, bot_id: int, ids: list[str], message_id: int) -> list[dict]:
    if not ids:
        return []
    with db.tx() as c:
        for att_id in ids:
            c.execute("UPDATE attachments SET status='attached', message_id=?, bot_id=?, expires_at=NULL"
                      " WHERE id=? AND user_id=? AND status='pending'", (message_id, bot_id, att_id, user_id))
    return [r for r in (get(user_id, i) for i in ids) if r]


def set_caption(user_id: int, att_id: str, caption: str | None, status: str):
    with db.tx() as c:
        c.execute("UPDATE attachments SET caption=?, caption_status=? WHERE id=? AND user_id=?",
                  (caption, status, att_id, user_id))


# ---------------------------------------------------------------- 删除
def delete_pending(user_id: int, att_id: str):
    r = get(user_id, att_id)
    if not r:
        raise AttachmentError(404, "图片不存在")
    if r["status"] != "pending":
        raise AttachmentError(409, "已发送的图片随消息一起删除（清空对话或删除 Bot）")
    with db.tx() as c:
        c.execute("DELETE FROM attachments WHERE id=? AND user_id=?", (att_id, user_id))
    delete_files(file_keys(r))


def keys_for_bot(user_id: int, bot_id: int) -> list[str]:
    """清空对话 / 删除 Bot 前调用：先拿到文件 key，事务提交后再 delete_files。"""
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT * FROM attachments WHERE user_id=? AND bot_id=?", (user_id, bot_id)))
    return [k for r in rs for k in file_keys(r)]


def keys_for_message(user_id: int, bot_id: int, message_id: int) -> list[str]:
    """删除单条消息前调用（Q12）：先拿到该消息图片的文件 key，消息删除（行随外键级联）提交后再 delete_files。
    （PR #18 之后 SQL 移到 db/attachment_store.py，这里只留门面）"""
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT * FROM attachments WHERE user_id=? AND bot_id=? AND message_id=?",
                               (user_id, bot_id, message_id)))
    return [k for r in rs for k in file_keys(r)]


def keys_for_user(user_id: int) -> list[str]:
    """删除账号前调用（目前没有删除账号接口；用户行级联删除后由对账清理文件）。"""
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT * FROM attachments WHERE user_id=?", (user_id,)))
    return [k for r in rs for k in file_keys(r)]


# ---------------------------------------------------------------- 对账
def reconcile(now: float | None = None) -> dict:
    store = get_store()
    store.ensure_root()
    stats = {"expired": 0, "orphans": 0, "missing": 0}
    with db.tx() as c:
        expired = db.rows(c.execute("SELECT * FROM attachments WHERE status='pending' AND expires_at<?",
                                    (db.now_iso(),)))
        for r in expired:
            c.execute("DELETE FROM attachments WHERE id=?", (r["id"],))
    for r in expired:
        delete_files(file_keys(r))
    stats["expired"] = len(expired)

    with db.tx() as c:
        rs = db.rows(c.execute("SELECT id, storage_key, thumb_key FROM attachments"))
    known = {k for r in rs for k in file_keys(r)}
    cutoff = (now or time.time()) - ORPHAN_GRACE_SECONDS
    for key, mtime in list(store.iter_keys()):
        if key not in known and mtime < cutoff:
            store.delete(key)
            stats["orphans"] += 1
    for r in rs:
        if not store.exists(r["storage_key"]):
            stats["missing"] += 1
            log.warning("attachment %s: file missing (%s)", r["id"], r["storage_key"])
    return stats


async def reconcile_loop():
    """启动时清空 tmp/ 并对账一次，之后每 24 小时一次。"""
    get_store().clear_tmp()
    while True:
        try:
            stats = await asyncio.to_thread(reconcile)
            log.info("attachments reconcile: %s", stats)
        except Exception as e:  # noqa: BLE001 — 对账失败不影响服务
            log.warning("attachments reconcile failed: %s", e)
        await asyncio.sleep(24 * 3600)
