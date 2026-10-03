"""MCP 工具名 → `mcp__{slug}__{tool}`，满足 `^[A-Za-z0-9_-]{1,64}$`。"""
from __future__ import annotations

import hashlib
import re

MCP_NAME = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")
FULL_NAME = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
HEADER_NAME = re.compile(r"^[A-Za-z0-9-]{1,64}$")


def namespace(slug: str, mcp_name: str, taken: set[str]) -> str | None:
    """合法则返回 full_name；名称不合法返回 None（调用方记审计并跳过）。"""
    if not MCP_NAME.fullmatch(mcp_name):
        return None
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", mcp_name.replace(".", "_"))
    base = f"mcp__{slug}__{safe}"
    name = _fit(base, mcp_name)
    if name in taken:
        digest = hashlib.sha256(f"{slug}\n{mcp_name}".encode()).hexdigest()[:6]
        stem = base[: 64 - 7]
        name = f"{stem}_{digest}"
    if not FULL_NAME.fullmatch(name):
        return None
    return name


def _fit(base: str, mcp_name: str) -> str:
    if len(base) <= 64:
        return base
    digest = hashlib.sha256(mcp_name.encode()).hexdigest()[:6]
    return f"{base[:57]}_{digest}"


def header_rejected(schema: dict) -> bool:
    """`x-mcp-header` 不是合法头名时，这个工具必须被排除。"""
    props = schema.get("properties") if isinstance(schema, dict) else None
    if not isinstance(props, dict):
        return False
    for spec in props.values():
        if not isinstance(spec, dict) or "x-mcp-header" not in spec:
            continue
        header = spec.get("x-mcp-header")
        if not isinstance(header, str) or not HEADER_NAME.fullmatch(header):
            return True
    return False


def strip_extensions(schema: dict) -> dict:
    """交给模型的参数 schema 去掉 MCP 扩展键。"""
    if not isinstance(schema, dict):
        return {"type": "object", "properties": {}}
    out = {k: v for k, v in schema.items() if not str(k).startswith("x-mcp-")}
    props = out.get("properties")
    if isinstance(props, dict):
        cleaned = {}
        for key, spec in props.items():
            if isinstance(spec, dict):
                cleaned[key] = {k: v for k, v in spec.items() if not str(k).startswith("x-mcp-")}
            else:
                cleaned[key] = spec
        out["properties"] = cleaned
    out.setdefault("type", "object")
    return out
