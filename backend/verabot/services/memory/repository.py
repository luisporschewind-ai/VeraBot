"""记忆的存储辅助：正文加解密 / 有效期 / JSON。SQL 在 db/memory_store.py，这里原样 re-export，
调用方（service / recall）继续写 `repo.xxx(c, ...)`。每条语句都带 user_id（租户隔离）。"""
import json
from datetime import datetime, timedelta, timezone

from ...core import crypto
from ...db.memory_store import (COLS, FROM, active_count, active_summary, bot_active_counts, counts, delete,  # noqa: F401
                                delete_all, delete_for_bot, delete_global, delete_scope, delete_summaries,
                                expire_stale, find_by_hash, get, get_raw, insert, list_filtered, mark_used,
                                owner_of, query, recently_declined, set_user_enabled, summary_ids, update,
                                user_enabled, visible_active)
from .policy import SENSITIVE_PLACEHOLDER


def iso_in(days: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat(timespec="seconds")


def plaintext(r: dict) -> str:
    """正文明文：敏感记忆解密（密钥丢失时返回占位文字，不抛错）。"""
    if r.get("sensitivity", "normal") != "normal" and r.get("content_enc"):
        return crypto.decrypt(r["content_enc"]) or "[无法解密：密钥缺失或已更换]"
    return r.get("content") or ""


def stored(content: str, sensitivity: str) -> tuple[str, str | None]:
    """→ (content 列, content_enc 列)。敏感记忆的明文只以密文形式落库。"""
    if sensitivity != "normal":
        return SENSITIVE_PLACEHOLDER[sensitivity], crypto.encrypt(content)
    return content, None


def dumps(v) -> str:
    return json.dumps(v, ensure_ascii=False)
