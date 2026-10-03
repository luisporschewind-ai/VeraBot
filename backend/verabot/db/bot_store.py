"""bots 表的写入与计数（读取 / 反序列化见 db/repository.py 的 get_bot / list_bots）。

权限校验、数量上限、唯一名冲突的 HTTP 映射留在 api / services；这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations


def count_for_user(c, user_id: int) -> int:
    return c.execute("SELECT COUNT(*) FROM bots WHERE user_id=?", (user_id,)).fetchone()[0]


def name_exists(c, user_id: int, name: str) -> bool:
    return bool(c.execute("SELECT 1 FROM bots WHERE user_id=? AND name=?", (user_id, name)).fetchone())


def insert(c, cols: dict) -> int:
    """cols：列名 → 值（列名来自代码，不来自请求）。返回新 id。"""
    return c.execute(f"INSERT INTO bots({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                     tuple(cols.values())).lastrowid


def update_fields(c, user_id: int, bot_id: int, fields: dict, pin_at: str | None = None) -> None:
    """fields：列名 → 值（列名来自代码 / schema 白名单）。pin_at 非 None 时置顶（已置顶的保留原时间）。
    唯一约束冲突原样抛 sqlite3.IntegrityError。"""
    sets = [f"{k}=?" for k in fields]
    values = [*fields.values()]
    if pin_at is not None:
        sets.append("pinned_at=COALESCE(pinned_at, ?)")
        values.append(pin_at)
    c.execute(f"UPDATE bots SET {','.join(sets)} WHERE id=? AND user_id=?", [*values, bot_id, user_id])


def delete(c, user_id: int, bot_id: int) -> None:
    c.execute("DELETE FROM bots WHERE id=? AND user_id=?", (bot_id, user_id))


def set_delegate_to(c, bot_id: int, delegate_to_json: str) -> None:
    c.execute("UPDATE bots SET delegate_to=? WHERE id=?", (delegate_to_json, bot_id))


def set_image_updated(c, user_id: int, bot_id: int, updated_at: str) -> None:
    c.execute("UPDATE bots SET image_updated_at=? WHERE id=? AND user_id=?", (updated_at, bot_id, user_id))


def clear_image_updated(c, user_id: int, bot_id: int) -> None:
    c.execute("UPDATE bots SET image_updated_at=NULL WHERE id=? AND user_id=?", (bot_id, user_id))
