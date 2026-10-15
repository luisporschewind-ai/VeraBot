"""用 DeepSeek 一次生成开场词模板；失败返回 None，由客户端兜底。"""
from __future__ import annotations

import json
import logging
from typing import Any, Callable, Awaitable

from ... import db
from ...db import bot_store
from .. import llm

log = logging.getLogger("verabot.opening")

TEMPLATE_VERSION = 1
_MAX_ITEMS = 4

_SYSTEM = """你为私人助理 Bot 生成「空对话开场词」模板。只输出 JSON：
{"version":1,"first_meeting":["..."],"returning":["..."],"invite":"..."}
规则：
- first_meeting / returning 各 2～4 条短中文模板，可含占位符 {greeting}{address}{day_note}{bot_name}{invite}{late_care}
- first_meeting：短自我介绍 + 人设邀请；returning：问候与延续，不要再自我介绍
- invite：一句符合人设的邀请（健康助手偏健康关心；调查员像「想查点什么」；大管家像「有事交给我」）
- 语气关心人、有个性、通用；禁止功能清单、禁止具体城市名、禁止敏感细节
- 不要输出 JSON 以外的文字"""


CompleteJson = Callable[..., Awaitable[tuple[str, dict]]]


def parse_templates(raw: str | dict | None) -> dict | None:
    if raw is None:
        return None
    if isinstance(raw, dict):
        data = raw
    else:
        text = str(raw).strip()
        if not text:
            return None
        try:
            data = json.loads(text)
        except (ValueError, TypeError):
            return None
    if not isinstance(data, dict):
        return None
    first = _clean_list(data.get("first_meeting"))
    returning = _clean_list(data.get("returning"))
    invite = str(data.get("invite") or "").strip()
    if not first or not returning:
        return None
    if not invite:
        invite = "有什么想聊的，跟我说。"
    return {
        "version": int(data.get("version") or TEMPLATE_VERSION),
        "first_meeting": first[:_MAX_ITEMS],
        "returning": returning[:_MAX_ITEMS],
        "invite": invite[:80],
    }


def _clean_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    out = []
    for item in value:
        s = str(item or "").strip()
        if not s or len(s) > 200:
            continue
        # 拒绝硬编码城市示例
        if "石家庄" in s:
            continue
        out.append(s)
    return out


def load_stored(bot: dict) -> dict | None:
    raw = bot.get("opening_templates")
    if raw is None:
        return None
    if isinstance(raw, dict):
        return parse_templates(raw)
    return parse_templates(raw)


def builtin_fallback(name: str, persona: str = "") -> dict:
    """服务端兜底（与 iOS 内置同风格），生成失败时不写库也可返回。"""
    invite = _invite_for(name, persona)
    return {
        "version": TEMPLATE_VERSION,
        "first_meeting": [
            "{greeting}，我是 **{bot_name}**。{invite}",
            "{greeting}，我是 **{bot_name}**。{day_note}{invite}",
        ],
        "returning": [
            "{greeting}，{address}。{day_note}{invite}",
            "{greeting}。{day_note}{invite}{late_care}",
        ],
        "invite": invite,
    }


def _invite_for(name: str, persona: str = "") -> str:
    blob = f"{name} {persona}"
    if "健康" in blob:
        return "身体或作息上有什么想留意的，跟我说。"
    if "调查" in blob:
        return "想查点什么，交给我。"
    if "管家" in blob:
        return "有事交给我。"
    return "有什么想聊的，跟我说。"


async def generate_for_bot(
    name: str,
    persona: str = "",
    instructions: str = "",
    *,
    complete_json: CompleteJson | None = None,
) -> dict | None:
    """调用模型生成模板；失败返回 None。complete_json 可注入 mock。"""
    complete = complete_json or llm.complete_json
    user = json.dumps(
        {"name": name, "persona": persona or "", "instructions": (instructions or "")[:500]},
        ensure_ascii=False,
    )
    try:
        content, _usage = await complete(
            [{"role": "system", "content": _SYSTEM}, {"role": "user", "content": user}],
            max_tokens=800,
        )
    except Exception as e:  # noqa: BLE001 — 开场词失败不得拖垮创建
        log.warning("opening template generation failed: %s", e)
        return None
    parsed = parse_templates(content)
    if parsed is None:
        log.warning("opening template parse failed: %s", (content or "")[:200])
    return parsed


def save_templates(user_id: int, bot_id: int, templates: dict | None) -> None:
    payload = json.dumps(templates, ensure_ascii=False) if templates is not None else None
    with db.tx() as c:
        bot_store.update_fields(c, user_id, bot_id, {"opening_templates": payload})


def clear_templates(user_id: int, bot_id: int) -> None:
    save_templates(user_id, bot_id, None)


async def ensure_templates(
    user: dict,
    bot: dict,
    *,
    complete_json: CompleteJson | None = None,
    generate: bool = True,
) -> dict[str, Any]:
    """若已有模板则返回；否则尝试生成并落库。返回给 API 的 opening 字段。"""
    stored = load_stored(bot)
    if stored is not None:
        return {"opening_templates": stored, "generated": False}
    if not generate:
        return {"opening_templates": None, "generated": False}
    templates = await generate_for_bot(
        bot.get("name") or "",
        bot.get("persona") or "",
        bot.get("instructions") or "",
        complete_json=complete_json,
    )
    if templates is not None:
        save_templates(user["id"], bot["id"], templates)
        return {"opening_templates": templates, "generated": True}
    return {"opening_templates": None, "generated": False}
