"""user_plugins 查询。所有读取都带 user_id。安装关系只在这张表，启用 / 同意 / 同步仍在 mcp_servers。"""
from __future__ import annotations

import json

from . import action_store
from .database import now_iso, tx


def _row(row):
    return dict(row) if row is not None else None


def get(user_id: int, plugin_id: str) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM user_plugins WHERE user_id=? AND plugin_id=?",
            (user_id, plugin_id),
        ).fetchone()
    return _row(row)


def has_any(user_id: int) -> bool:
    with tx() as c:
        return c.execute(
            "SELECT 1 FROM user_plugins WHERE user_id=? LIMIT 1", (user_id,)
        ).fetchone() is not None


def installed_ids(user_id: int) -> set[str]:
    with tx() as c:
        rows = c.execute(
            "SELECT plugin_id FROM user_plugins WHERE user_id=? AND status='installed'",
            (user_id,),
        ).fetchall()
    return {r["plugin_id"] for r in rows}


def mark_installed(user_id: int, plugin_id: str, catalog_version: str | None) -> str:
    """created / reinstalled / exists。exists 表示已经是 installed，调用方应返回 409。"""
    now = now_iso()
    with tx() as c:
        row = c.execute(
            "SELECT status FROM user_plugins WHERE user_id=? AND plugin_id=?",
            (user_id, plugin_id),
        ).fetchone()
        if row and row["status"] == "installed":
            return "exists"
        if row:
            c.execute(
                """UPDATE user_plugins
                   SET status='installed', catalog_version=?, installed_at=?,
                       uninstalled_at=NULL, updated_at=?
                   WHERE user_id=? AND plugin_id=?""",
                (catalog_version, now, now, user_id, plugin_id),
            )
            return "reinstalled"
        c.execute(
            """INSERT INTO user_plugins(
                   user_id, plugin_id, status, catalog_version, installed_at, created_at, updated_at)
               VALUES (?,?, 'installed', ?, ?, ?, ?)""",
            (user_id, plugin_id, catalog_version, now, now, now),
        )
        return "created"


def tombstone(user_id: int, plugin_id: str):
    """用户主动卸下（或通过旧的删除服务接口卸下）时写墓碑。迁移不会调用这里。"""
    now = now_iso()
    with tx() as c:
        row = c.execute(
            "SELECT status FROM user_plugins WHERE user_id=? AND plugin_id=?",
            (user_id, plugin_id),
        ).fetchone()
        if row and row["status"] == "uninstalled":
            return
        if row:
            c.execute(
                """UPDATE user_plugins SET status='uninstalled', uninstalled_at=?, updated_at=?
                   WHERE user_id=? AND plugin_id=?""",
                (now, now, user_id, plugin_id),
            )
            return
        c.execute(
            """INSERT INTO user_plugins(
                   user_id, plugin_id, status, uninstalled_at, created_at, updated_at)
               VALUES (?,?,'uninstalled',?,?,?)""",
            (user_id, plugin_id, now, now, now),
        )


def commit_uninstall(user_id: int, plugin_id: str) -> dict | None:
    """同一事务：墓碑、从所有 Bot 去掉工具、删除服务行（级联工具缓存）。未安装返回 None。

    连接池在事务提交之后由调用方关闭，这样进行中的调用能看到「行已经不在」。
    """
    now = now_iso()
    with tx() as c:
        row = c.execute(
            "SELECT status FROM user_plugins WHERE user_id=? AND plugin_id=?",
            (user_id, plugin_id),
        ).fetchone()
        if row is None or row["status"] != "installed":
            return None
        servers = c.execute(
            """SELECT id, slug FROM mcp_servers
               WHERE user_id=? AND (plugin_id=? OR (plugin_id IS NULL AND catalog_id=?))""",
            (user_id, plugin_id, plugin_id),
        ).fetchall()
        removed = 0
        affected: set[int] = set()
        ids: list[int] = []
        slugs: list[str] = []
        for server in servers:
            ids.append(server["id"])
            slugs.append(server["slug"])
            action_store.detach_for_server(c, user_id, server["id"], stamp=now)
            removed += c.execute(
                "SELECT COUNT(*) FROM mcp_tools WHERE server_id=?", (server["id"],)
            ).fetchone()[0]
            affected |= _strip(c, user_id, server["slug"])
            c.execute(
                "DELETE FROM mcp_servers WHERE id=? AND user_id=?",
                (server["id"], user_id),
            )
        c.execute(
            """UPDATE user_plugins SET status='uninstalled', uninstalled_at=?, updated_at=?
               WHERE user_id=? AND plugin_id=?""",
            (now, now, user_id, plugin_id),
        )
    return {
        "server_ids": ids,
        "slugs": slugs,
        "removed_tools": removed,
        "affected_bots": len(affected),
    }


def _strip(c, user_id: int, slug: str) -> set[int]:
    prefix = f"mcp__{slug}__"
    affected: set[int] = set()
    rows = c.execute(
        "SELECT id, allowed_tools FROM bots WHERE user_id=?", (user_id,)
    ).fetchall()
    for row in rows:
        try:
            names = json.loads(row["allowed_tools"] or "[]")
        except ValueError:
            continue
        kept = [n for n in names if not str(n).startswith(prefix)]
        if kept != names:
            affected.add(row["id"])
            c.execute(
                "UPDATE bots SET allowed_tools=? WHERE id=?",
                (json.dumps(sorted(set(kept)), ensure_ascii=False), row["id"]),
            )
    return affected
