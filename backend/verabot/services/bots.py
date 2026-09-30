"""Bot 业务逻辑：公开字段、权限配置校验、删除后的委派白名单清理。"""
import json

from fastapi import HTTPException

from .. import db
from ..tools import REGISTRY

PUBLIC_FIELDS = ("id", "name", "avatar", "color", "persona", "instructions", "created_at",
                 "allowed_tools", "delegate_to", "accept_delegation")


def public_bot(b: dict) -> dict:
    return {k: b[k] for k in PUBLIC_FIELDS}


def validate_perms(user: dict, body, self_id: int | None) -> dict:
    """服务端校验权限配置：工具必须存在；委派目标必须是本人的其他 Bot。返回需写入的列。"""
    out = {}
    if body.allowed_tools is not None:
        bad = [t for t in body.allowed_tools if t not in REGISTRY]
        if bad:
            raise HTTPException(422, f"未知工具：{', '.join(bad)}")
        out["allowed_tools"] = json.dumps(sorted(set(body.allowed_tools)))
    if body.delegate_to is not None:
        mine = {b["id"] for b in db.list_bots(user["id"])}
        ids = sorted(set(body.delegate_to))
        if self_id in ids:
            raise HTTPException(422, "不能把自己设为委派目标")
        if any(i not in mine for i in ids):
            raise HTTPException(422, "委派目标必须是你自己的其他 Bot")
        out["delegate_to"] = json.dumps(ids)
    if body.accept_delegation is not None:
        out["accept_delegation"] = int(body.accept_delegation)
    return out


def remove_from_delegate_lists(user_id: int, bot_id: int):
    """从其他 Bot 的委派白名单中移除该 id（删除 Bot 后调用）。"""
    for b in db.list_bots(user_id):
        if bot_id in b["delegate_to"]:
            with db.tx() as c:
                c.execute("UPDATE bots SET delegate_to=? WHERE id=?",
                          (json.dumps([x for x in b["delegate_to"] if x != bot_id]), b["id"]))
