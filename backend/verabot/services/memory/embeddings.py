"""本地记忆向量生成与 SQLite 缓存；任何失败都让调用方回退关键词召回。"""
from __future__ import annotations

import logging
import math
import struct
import threading

from ... import db
from ...core import config

log = logging.getLogger("verabot.memory.embeddings")
_MODEL = None
_MODEL_LOCK = threading.Lock()


def _encode_local(texts: list[str]) -> list[list[float]]:
    """懒加载本地 FastEmbed；输入文本始终只交给本机推理。"""
    global _MODEL
    with _MODEL_LOCK:
        if _MODEL is None:
            from fastembed import TextEmbedding
            _MODEL = TextEmbedding(model_name=config.MEMORY_VECTOR_MODEL,
                                   cache_dir=str(config.MEMORY_VECTOR_CACHE),
                                   threads=config.MEMORY_VECTOR_THREADS)
        return [list(map(float, vector)) for vector in _MODEL.embed(texts)]


def _pack(vector: list[float]) -> bytes:
    if len(vector) != config.MEMORY_VECTOR_DIM or not all(math.isfinite(v) for v in vector):
        raise ValueError("invalid embedding vector")
    return struct.pack(f"<{len(vector)}f", *vector)


def _unpack(blob: bytes, dim: int) -> list[float]:
    if dim != config.MEMORY_VECTOR_DIM or len(blob) != dim * 4:
        raise ValueError("invalid stored vector")
    return list(struct.unpack(f"<{dim}f", blob))


def _unit(vector: list[float]) -> list[float]:
    norm = math.sqrt(sum(value * value for value in vector))
    if norm <= 1e-12:
        raise ValueError("empty embedding vector")
    return [value / norm for value in vector]


def _memory_text(memory: dict) -> str:
    return f"{memory.get('type') or ''}：{memory.get('_text') or ''}".strip("：")


def score(user_id: int, memories: list[dict], query: str) -> dict[int, float] | None:
    """当前可见普通记忆的余弦分数；依赖、模型、DB 错误时返回 None。"""
    if not config.MEMORY_VECTOR_ENABLED or not query.strip():
        return None
    eligible = [m for m in memories if m.get("status") == "active" and m.get("scope") != "summary"
                and m.get("sensitivity", "normal") == "normal" and m.get("_text")]
    if not eligible:
        return {}
    try:
        existing: dict[int, list[float]] = {}
        stale: list[dict] = []
        model_name = config.MEMORY_VECTOR_MODEL
        with db.tx() as c:
            cached = {r["memory_id"]: r for r in c.execute(
                f"SELECT memory_id, content_hash, dim, vector FROM memory_vectors "
                f"WHERE user_id=? AND model=? AND memory_id IN ({','.join('?' * len(eligible))})",
                (user_id, model_name, *(m["id"] for m in eligible))).fetchall()}
        for memory in eligible:
            row = cached.get(memory["id"])
            if row and row["content_hash"] == memory.get("content_hash"):
                existing[memory["id"]] = _unpack(row["vector"], row["dim"])
            else:
                stale.append(memory)
        encoded = _encode_local([query, *(_memory_text(m) for m in stale)])
        if len(encoded) != len(stale) + 1:
            raise ValueError("embedding result count mismatch")
        query_vector = _unit(encoded[0])
        updates = [(m, _unit(vector)) for m, vector in zip(stale, encoded[1:])]
        with db.tx() as c:
            for memory, vector in updates:
                blob = _pack(vector)
                c.execute("""INSERT INTO memory_vectors(memory_id,user_id,model,dim,content_hash,vector,updated_at)
                    SELECT m.id,m.user_id,?,?,m.content_hash,?,?
                    FROM memories m WHERE m.id=? AND m.user_id=? AND m.status='active'
                      AND m.content_hash=? AND m.sensitivity='normal' AND m.scope IN ('global','bot')
                    ON CONFLICT(memory_id) DO UPDATE SET user_id=excluded.user_id,model=excluded.model,
                      dim=excluded.dim,content_hash=excluded.content_hash,vector=excluded.vector,updated_at=excluded.updated_at""",
                    (model_name, len(vector), blob, db.now_iso(), memory["id"], user_id, memory.get("content_hash")))
                existing[memory["id"]] = vector
        return {mid: max(-1.0, min(1.0, sum(a * b for a, b in zip(query_vector, vector))))
                for mid, vector in existing.items()}
    except Exception as exc:
        # Logs must never include a query, memory content, or provider exception text.
        log.info("local memory embeddings unavailable: %s", type(exc).__name__)
        return None
