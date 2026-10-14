"""memory_vectors 的读写。调用方传入同一条连接以保持事务。"""
from __future__ import annotations


def cached(c, user_id: int, model: str, memory_ids: list[int]):
    if not memory_ids:
        return []
    marks = ",".join("?" * len(memory_ids))
    return c.execute(
        f"SELECT memory_id, content_hash, dim, vector FROM memory_vectors "
        f"WHERE user_id=? AND model=? AND memory_id IN ({marks})",
        (user_id, model, *memory_ids)).fetchall()


def upsert(c, model_name: str, dim: int, blob: bytes, updated_at: str, memory_id: int, user_id: int, content_hash):
    c.execute(
        """INSERT INTO memory_vectors(memory_id,user_id,model,dim,content_hash,vector,updated_at)
           SELECT m.id,m.user_id,?,?,m.content_hash,?,?
           FROM memories m WHERE m.id=? AND m.user_id=? AND m.status='active'
             AND m.content_hash=? AND m.sensitivity='normal' AND m.scope IN ('global','bot')
           ON CONFLICT(memory_id) DO UPDATE SET user_id=excluded.user_id,model=excluded.model,
             dim=excluded.dim,content_hash=excluded.content_hash,vector=excluded.vector,updated_at=excluded.updated_at""",
        (model_name, dim, blob, updated_at, memory_id, user_id, content_hash))
