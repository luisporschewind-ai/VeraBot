"""MCP 表的查询。所有读取都带 user_id。"""
from __future__ import annotations

import json

from .database import now_iso, tx


def _server(row):
    if row is None:
        return None
    item = dict(row)
    item["enabled"] = item.get("status") != "disabled"
    return item


def _tool(row):
    if row is None:
        return None
    item = dict(row)
    for key in ("input_schema", "output_schema", "annotations"):
        raw = item.get(key)
        if raw:
            try:
                item[key] = json.loads(raw)
            except ValueError:
                item[key] = None
        else:
            item[key] = None
    return item


def list_servers(user_id: int) -> list[dict]:
    with tx() as c:
        rows = c.execute(
            "SELECT * FROM mcp_servers WHERE user_id=? ORDER BY id", (user_id,)
        ).fetchall()
    return [_server(r) for r in rows]


def get_server(user_id: int, server_id: int) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_servers WHERE id=? AND user_id=?", (server_id, user_id)
        ).fetchone()
    return _server(row)


def get_server_by_slug(user_id: int, slug: str) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_servers WHERE user_id=? AND slug=?", (user_id, slug)
        ).fetchone()
    return _server(row)


def insert_server(user_id: int, spec: dict, status: str) -> dict:
    now = now_iso()
    with tx() as c:
        cur = c.execute(
            """INSERT INTO mcp_servers(
                user_id, slug, source, catalog_id, name, transport, url, trust, auth_type,
                status, plugin_id, created_at, updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (user_id, spec["slug"], "catalog", spec["catalog_id"], spec["name"],
             spec["transport"], spec.get("url") or None, spec["trust"], spec["auth"],
             status, spec.get("catalog_id"), now, now),
        )
        sid = cur.lastrowid
    return get_server(user_id, sid)


def update_server(user_id: int, server_id: int, **fields):
    if not fields:
        return get_server(user_id, server_id)
    fields["updated_at"] = now_iso()
    cols = ", ".join(f"{k}=?" for k in fields)
    with tx() as c:
        c.execute(
            f"UPDATE mcp_servers SET {cols} WHERE id=? AND user_id=?",
            (*fields.values(), server_id, user_id),
        )
    return get_server(user_id, server_id)


def update_server_unless_disabled(user_id: int, server_id: int, **fields) -> bool:
    """同 update_server，但只在服务未停用时写入；检查和写入在同一条 SQL 里完成。

    给后台同步写结果用：同步进行中用户可能已经停用，停用优先，不能被同步结果改回 connected / error。
    返回是否写入（False：已停用，或行已不存在）。
    """
    fields["updated_at"] = now_iso()
    cols = ", ".join(f"{k}=?" for k in fields)
    with tx() as c:
        cur = c.execute(
            f"UPDATE mcp_servers SET {cols} WHERE id=? AND user_id=? AND status!='disabled'",
            (*fields.values(), server_id, user_id),
        )
        return cur.rowcount > 0


def settle_disabled_sync(user_id: int, server_id: int) -> bool:
    """已停用的服务结束一次同步：sync_status 由 syncing 回到 pending（与 _sync_body 开头「已停用」分支一致）。

    只改已停用且仍是 syncing 的行；其间若已重新启用（set_enabled 会写 pending），这里不动。
    """
    with tx() as c:
        cur = c.execute(
            "UPDATE mcp_servers SET sync_status='pending', updated_at=? "
            "WHERE id=? AND user_id=? AND status='disabled' AND sync_status='syncing'",
            (now_iso(), server_id, user_id),
        )
        return cur.rowcount > 0


def delete_server(user_id: int, server_id: int) -> bool:
    with tx() as c:
        from .action_store import detach_for_server
        detach_for_server(c, user_id, server_id)
        cur = c.execute(
            "DELETE FROM mcp_servers WHERE id=? AND user_id=?", (server_id, user_id)
        )
        return cur.rowcount > 0


def tool_count(user_id: int, server_id: int) -> int:
    with tx() as c:
        return c.execute(
            "SELECT COUNT(*) FROM mcp_tools WHERE user_id=? AND server_id=? AND status!='removed'",
            (user_id, server_id),
        ).fetchone()[0]


def list_tools(user_id: int, server_id: int | None = None) -> list[dict]:
    sql = "SELECT * FROM mcp_tools WHERE user_id=?"
    args: list = [user_id]
    if server_id is not None:
        sql += " AND server_id=?"
        args.append(server_id)
    sql += " ORDER BY id"
    with tx() as c:
        rows = c.execute(sql, args).fetchall()
    return [_tool(r) for r in rows]


def get_tool(user_id: int, tool_id: int) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_tools WHERE id=? AND user_id=?", (tool_id, user_id)
        ).fetchone()
    return _tool(row)


def get_tool_by_full_name(user_id: int, full_name: str) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_tools WHERE user_id=? AND full_name=?", (user_id, full_name)
        ).fetchone()
    return _tool(row)


def upsert_tool(user_id: int, server_id: int, rec: dict) -> str:
    """插入或更新。返回 added / unchanged / changed。"""
    now = now_iso()
    fields = (
        rec["full_name"], rec.get("title"), rec["description"],
        json.dumps(rec["input_schema"], ensure_ascii=False),
        json.dumps(rec["output_schema"], ensure_ascii=False) if rec.get("output_schema") is not None else None,
        json.dumps(rec["annotations"], ensure_ascii=False) if rec.get("annotations") is not None else None,
        rec["def_hash"], rec["risk"],
    )
    with tx() as c:
        old = c.execute(
            "SELECT id, def_hash, accepted_hash, status FROM mcp_tools WHERE server_id=? AND mcp_name=?",
            (server_id, rec["mcp_name"]),
        ).fetchone()
        if old is None:
            c.execute(
                """INSERT INTO mcp_tools(
                    server_id, user_id, mcp_name, full_name, title, description,
                    input_schema, output_schema, annotations, def_hash, risk, status,
                    first_seen_at, last_seen_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,'active',?,?)""",
                (server_id, user_id, rec["mcp_name"], *fields, now, now),
            )
            return "added"
        status = "active"
        if old["def_hash"] != rec["def_hash"] and old["accepted_hash"] != rec["def_hash"]:
            status = "changed"
        c.execute(
            """UPDATE mcp_tools SET full_name=?, title=?, description=?, input_schema=?,
               output_schema=?, annotations=?, def_hash=?, risk=?, status=?, last_seen_at=?
               WHERE id=?""",
            (*fields, status, now, old["id"]),
        )
        if status == "changed":
            return "changed"
        return "unchanged"


def mark_removed(server_id: int, seen_names: set[str]) -> list[str]:
    with tx() as c:
        rows = c.execute(
            "SELECT mcp_name FROM mcp_tools WHERE server_id=? AND status!='removed'", (server_id,)
        ).fetchall()
        gone = [r["mcp_name"] for r in rows if r["mcp_name"] not in seen_names]
        for name in gone:
            c.execute(
                "UPDATE mcp_tools SET status='removed', last_seen_at=? WHERE server_id=? AND mcp_name=?",
                (now_iso(), server_id, name),
            )
    return gone


def accept_change(user_id: int, tool_id: int) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT def_hash, status FROM mcp_tools WHERE id=? AND user_id=?", (tool_id, user_id)
        ).fetchone()
        if row is None or row["status"] != "changed":
            return None
        c.execute(
            "UPDATE mcp_tools SET status='active', accepted_hash=?, last_seen_at=? WHERE id=?",
            (row["def_hash"], now_iso(), tool_id),
        )
    return get_tool(user_id, tool_id)


def set_confirm_policy(user_id: int, tool_id: int, policy: str) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT id FROM mcp_tools WHERE id=? AND user_id=?", (tool_id, user_id)
        ).fetchone()
        if row is None:
            return None
        c.execute(
            "UPDATE mcp_tools SET confirm_policy=? WHERE id=? AND user_id=?",
            (policy, tool_id, user_id),
        )
    return get_tool(user_id, tool_id)


def strip_slug_from_bots(user_id: int, slug: str):
    """从该用户所有 Bot 的白名单里去掉 `mcp__{slug}__*`。"""
    prefix = f"mcp__{slug}__"
    with tx() as c:
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
                c.execute(
                    "UPDATE bots SET allowed_tools=? WHERE id=?",
                    (json.dumps(sorted(set(kept)), ensure_ascii=False), row["id"]),
                )


# ---------------- 连接器凭据（v13）。只存密文；明文令牌不经过这一层以外的任何地方落库。 ----------------
def get_credential(user_id: int, server_id: int) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_credentials WHERE user_id=? AND server_id=? ORDER BY id DESC LIMIT 1",
            (user_id, server_id),
        ).fetchone()
    return dict(row) if row else None


def upsert_credential(user_id: int, server_id: int, *, kind: str, issuer: str, access_token_enc: str,
                      token_hint: str | None, expires_at: str | None, scopes: str | None = None) -> dict:
    now = now_iso()
    with tx() as c:
        c.execute("DELETE FROM mcp_credentials WHERE user_id=? AND server_id=?", (user_id, server_id))
        c.execute(
            """INSERT INTO mcp_credentials(user_id, server_id, provider, issuer, access_token_enc, expires_at, scopes,
                   kind, token_hint, last_verified_at, created_at, updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            (user_id, server_id, kind, issuer, access_token_enc, expires_at, scopes,
             kind, token_hint, now, now, now),
        )
    return get_credential(user_id, server_id)


def delete_credential(user_id: int, server_id: int) -> bool:
    with tx() as c:
        cur = c.execute("DELETE FROM mcp_credentials WHERE user_id=? AND server_id=?", (user_id, server_id))
        return cur.rowcount > 0


def get_credential_for_issuer(user_id: int, server_id: int, issuer: str) -> dict | None:
    with tx() as c:
        row = c.execute(
            "SELECT * FROM mcp_credentials WHERE user_id=? AND server_id=? AND issuer=? ORDER BY id DESC LIMIT 1",
            (user_id, server_id, issuer),
        ).fetchone()
    return dict(row) if row else None


def delete_credential_for_issuer(user_id: int, server_id: int, issuer: str) -> bool:
    with tx() as c:
        cur = c.execute("DELETE FROM mcp_credentials WHERE user_id=? AND server_id=? AND issuer=?",
                        (user_id, server_id, issuer))
        return cur.rowcount == 1


def save_oauth_storage(user_id: int, server_id: int, issuer: str, *, access_token_enc: str | None = None,
                       refresh_token_enc: str | None = None, client_info_enc: str | None = None,
                       expires_at: str | None = None, scopes: str | None = None,
                       token_hint: str | None = None, clear_expiry: bool = False) -> dict:
    """Persist one OAuth issuer's encrypted SDK storage without overwriting another issuer."""
    now = now_iso()
    with tx() as c:
        old = c.execute(
            "SELECT * FROM mcp_credentials WHERE user_id=? AND server_id=? AND issuer=?",
            (user_id, server_id, issuer),
        ).fetchone()
        if old:
            c.execute(
                """UPDATE mcp_credentials SET provider='oauth', kind='oauth',
                   access_token_enc=COALESCE(?,access_token_enc),
                   refresh_token_enc=COALESCE(?,refresh_token_enc),
                   client_info_enc=COALESCE(?,client_info_enc),
                   expires_at=CASE WHEN ? THEN NULL ELSE COALESCE(?,expires_at) END, scopes=COALESCE(?,scopes),
                   token_hint=COALESCE(?,token_hint), last_verified_at=?, updated_at=?
                   WHERE id=?""",
                (access_token_enc, refresh_token_enc, client_info_enc, int(clear_expiry), expires_at, scopes,
                 token_hint, now, now, old["id"]),
            )
        else:
            c.execute(
                """INSERT INTO mcp_credentials(user_id,server_id,provider,issuer,access_token_enc,
                   refresh_token_enc,client_info_enc,expires_at,scopes,kind,token_hint,last_verified_at,
                   created_at,updated_at) VALUES(?,?, 'oauth', ?,?,?,?,?,?,'oauth',?,?,?,?)""",
                (user_id, server_id, issuer, access_token_enc, refresh_token_enc, client_info_enc,
                 expires_at, scopes, token_hint, now, now, now),
            )
    return get_credential_for_issuer(user_id, server_id, issuer) or {}


def insert_oauth_state(state: str, user_id: int, server_id: int, provider: str, payload_enc: str,
                       expires_at: str) -> None:
    with tx() as c:
        c.execute("DELETE FROM oauth_states WHERE expires_at<=?", (now_iso(),))
        c.execute(
            "INSERT INTO oauth_states(state,user_id,server_id,provider,payload_enc,expires_at) VALUES(?,?,?,?,?,?)",
            (state, user_id, server_id, provider, payload_enc, expires_at),
        )


def consume_oauth_state(state: str, user_id: int, server_id: int) -> str | None:
    """Atomically consume a live state. Missing, expired, replayed, and foreign are equivalent."""
    now = now_iso()
    with tx() as c:
        row = c.execute(
            "SELECT expires_at FROM oauth_states WHERE state=? AND user_id=? AND server_id=?",
            (state, user_id, server_id),
        ).fetchone()
        if row is None:
            return None
        c.execute("DELETE FROM oauth_states WHERE state=?", (state,))
        return row["expires_at"] if row["expires_at"] > now else None


def delete_oauth_state(state: str, user_id: int, server_id: int) -> bool:
    with tx() as c:
        cur = c.execute(
            "DELETE FROM oauth_states WHERE state=? AND user_id=? AND server_id=?",
            (state, user_id, server_id),
        )
        return cur.rowcount == 1
