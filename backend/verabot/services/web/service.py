"""联网业务：有界缓存、当前轮结果引用、账户预算与稳定错误。"""
import asyncio
from collections import OrderedDict
from copy import deepcopy
from datetime import datetime, timezone
import os
import re
import time
from urllib.parse import urlsplit, urldefrag
from uuid import uuid4

from ...db.web_store import reserve_request
from ..mcp.sanitize import clean_text, escape_markers
from .policy import public_url, validate_search
from .provider import WebError, configured, make_provider, unavailable_code

_CACHE: OrderedDict = OrderedDict()
ERRORS = {
    "web_unavailable": "联网查询暂不可用，请稍后再试",
    "web_browser_unavailable": "联网浏览器暂不可用，请稍后再试",
    "web_access_blocked": "网站要求验证或暂时限制访问，未能完成查询",
    "web_invalid_arguments": "查询参数无效，请调整查询内容",
    "web_invalid_source": "这条来源不属于本次查询，请重新搜索",
    "web_daily_limit": "今日联网查询额度已用完",
    "web_turn_limit": "本轮查询次数已达上限，可缩小范围后再问一次",
    "web_timeout": "查询超时，请稍后再试",
    "web_rate_limited": "查询服务繁忙，请稍后再试",
    "web_bad_response": "查询服务返回的数据无法读取",
    "web_no_results": "没有查到可用资料，可换个关键词再试",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _text(value, limit: int) -> str:
    return escape_markers(clean_text(value))[:limit] if isinstance(value, str) else ""


def failure(code: str) -> dict:
    return {"error": ERRORS[code], "code": code}


def _daily_limit() -> int:
    try:
        return max(0, int(os.getenv("VERABOT_WEB_DAILY_REQUESTS", "50")))
    except ValueError:
        return 50


async def _request(ctx, operation: str, call):
    started = time.monotonic()
    remaining = 45 - ctx.turn.web_elapsed
    if remaining <= 0:
        raise WebError("web_timeout")
    if not reserve_request(ctx.user_id, ctx.bot["id"], operation, _daily_limit()):
        raise WebError("web_daily_limit")
    try:
        async with asyncio.timeout(min(30, remaining)):
            return await call()
    except TimeoutError:
        raise WebError("web_timeout") from None
    finally:
        ctx.turn.web_elapsed += time.monotonic() - started


def _sources(data: dict, fetched_at: str) -> list[dict]:
    sources, seen = [], set()
    for row in data["results"]:
        if not isinstance(row, dict):
            continue
        url = public_url(row.get("url"))
        if not url:
            continue
        canonical = urldefrag(url)[0]
        if canonical in seen:
            continue
        seen.add(canonical)
        sources.append({"title": _text(row.get("title"), 200) or urlsplit(url).hostname,
                        "url": url, "publisher": urlsplit(url).hostname,
                        "published_at": _text(row.get("published_date"), 128) or None,
                        "fetched_at": fetched_at, "content": _text(row.get("content"), 500)})
        if len(sources) == 5:
            break
    return sources


async def search(ctx, query: str, topic: str = "general", time_range: str = "", domains=None, refresh: bool = False) -> dict:
    try:
        query, domains = validate_search(query, topic, time_range, domains, refresh)
    except (ValueError, TypeError):
        return failure("web_invalid_arguments")
    if not configured():
        return failure(unavailable_code())
    if ctx.turn.web_elapsed >= 45:
        return failure("web_timeout")
    if ctx.turn.web_searches >= 2:
        return failure("web_turn_limit")
    ctx.turn.web_searches += 1
    bypass = refresh or topic == "news" or bool(time_range) or bool(re.search(r"重新|刷新|再查|最新|目前|今天|现在|\b(?:latest|current|now|today|refresh|again|up.to.date)\b", ctx.user_text, re.IGNORECASE))
    key = (ctx.user_id, ctx.bot["id"], query, topic, time_range, tuple(domains))
    hit = None if bypass else _CACHE.get(key)
    cached = bool(hit and time.monotonic() - hit[0] < 300)
    if cached:
        sources = deepcopy(hit[1])
        provider = hit[2]
        _CACHE.move_to_end(key)
    else:
        try:
            data = await _request(ctx, "search", lambda: make_provider().search(query, topic, time_range, domains))
        except WebError as exc:
            return failure(exc.code)
        if not isinstance(data, dict) or not isinstance(data.get("results"), list):
            return failure("web_bad_response")
        provider = _text(data.get("provider"), 100) or "网页搜索"
        sources = _sources(data, _now())
        if not sources:
            return failure("web_no_results")
        if not bypass:
            _CACHE[key] = (time.monotonic(), deepcopy(sources), provider)
            _CACHE.move_to_end(key)
            while len(_CACHE) > 128:
                _CACHE.popitem(last=False)
    query_id, queried_at = uuid4().hex, _now()
    for source in sources:
        ctx.turn.web_source_number += 1
        source.update(query_id=query_id, result_id=str(ctx.turn.web_source_number),
                      citation_number=ctx.turn.web_source_number, queried_at=queried_at, cache_hit=cached)
    ctx.turn.web_queries[query_id] = {"user_id": ctx.user_id, "bot_id": ctx.bot["id"],
                                      "sources": deepcopy(sources), "reads": {}}
    ctx.turn.untrusted_tainted = True
    ctx.turn.mcp_read_servers.add("联网查询")
    return {"query_id": query_id, "query": query, "sources": sources, "provider": provider,
            "summary": f"查到 {len(sources)} 条资料", "untrusted": True}


async def read(ctx, query_id: str, result_id: str) -> dict:
    if not isinstance(query_id, str) or not isinstance(result_id, str):
        return failure("web_invalid_source")
    entry = ctx.turn.web_queries.get(query_id)
    if not entry or entry["user_id"] != ctx.user_id or entry["bot_id"] != ctx.bot["id"]:
        return failure("web_invalid_source")
    source = next((s for s in entry["sources"] if s["result_id"] == result_id), None)
    if not source or not public_url(source["url"]):
        return failure("web_invalid_source")
    if not configured():
        return failure(unavailable_code())
    if ctx.turn.web_elapsed >= 45:
        return failure("web_timeout")
    if ctx.turn.web_reads >= 3:
        return failure("web_turn_limit")
    ctx.turn.web_reads += 1
    if result_id in entry["reads"]:
        result = deepcopy(entry["reads"][result_id])
        result["queried_at"], result["cache_hit"] = _now(), True
    else:
        try:
            data = await _request(ctx, "extract", lambda: make_provider().extract(source["url"]))
        except WebError as exc:
            return failure(exc.code)
        row = next((r for r in data["results"] if isinstance(r, dict) and r.get("url") == source["url"]), None)
        content = _text((row or {}).get("raw_content"), 4000)
        if not content:
            return failure("web_no_results")
        result = {**source, "published_at": _text((row or {}).get("published_date"), 128) or source["published_at"], "content": content, "queried_at": _now(), "fetched_at": _now(), "cache_hit": False}
        entry["reads"][result_id] = deepcopy(result)
    ctx.turn.untrusted_tainted = True
    ctx.turn.mcp_read_servers.add("联网查询")
    return {"query_id": query_id, "sources": [result], "summary": "已读取资料", "untrusted": True}
