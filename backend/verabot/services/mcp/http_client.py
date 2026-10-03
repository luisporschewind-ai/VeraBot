"""Streamable HTTP MCP 客户端（无授权）。

微软 Learn 与 AWS Knowledge 都走 2025 年的会话式 Streamable HTTP，而不是
SDK 默认的 2026-07-28 `server/discover`（那条路径没有 `Mcp-Session-Id`，
握手版本也是 2025-11-25）。因此这里自己发 JSON-RPC：

- 每个请求都带 `Accept: application/json, text/event-stream`，JSON 与 SSE 都解析
- 服务器若返回 `Mcp-Session-Id`，后续请求原样带回；没有则不发送该头
- `initialize` 请求 `2025-06-18`（可配置）。服务器协商更低版本时接受，
  并在后续请求的 `MCP-Protocol-Version` 头里使用协商结果
- 工具结果 `isError: true`（HTTP 200）与 JSON-RPC `error` 分成两种错误码
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field

import httpx

from ...core.config import MCP_PROTOCOL_VERSION, MCP_TIMEOUT_DEFAULT

ACCEPT = "application/json, text/event-stream"
SESSION_HEADER = "Mcp-Session-Id"
PROTOCOL_HEADER = "MCP-Protocol-Version"


class MCPClientError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class MCPRPCError(MCPClientError):
    """JSON-RPC `error` 对象。与工具自己的 isError 不是同一种失败。"""

    def __init__(self, message: str, rpc_code: int | None = None):
        super().__init__("mcp_rpc_error", message)
        self.rpc_code = rpc_code


class MCPTimeoutError(MCPClientError):
    def __init__(self, message: str = "MCP 服务超时"):
        super().__init__("mcp_timeout", message)


class MCPProtocolError(MCPClientError):
    def __init__(self, message: str):
        super().__init__("mcp_protocol", message)


@dataclass
class CallResult:
    """HTTP 200 的 tools/call 结果。`is_error` 为真时表示工具执行失败，不是协议错误。"""
    is_error: bool
    text: str
    raw: dict
    code: str  # ok / mcp_tool_error

    @property
    def ok(self) -> bool:
        return not self.is_error


def timeout_seconds() -> float:
    raw = os.getenv("VERABOT_MCP_TIMEOUT", str(MCP_TIMEOUT_DEFAULT))
    try:
        return float(raw)
    except ValueError:
        return float(MCP_TIMEOUT_DEFAULT)


def requested_protocol() -> str:
    return os.getenv("VERABOT_MCP_PROTOCOL_VERSION", MCP_PROTOCOL_VERSION).strip() or MCP_PROTOCOL_VERSION


def _accept_version(requested: str, server: str) -> str:
    if not server or not isinstance(server, str):
        raise MCPProtocolError("服务器没有返回 protocolVersion")
    # 日期形式的版本号可以直接比较大小；更高的版本不接受。
    if server > requested:
        raise MCPProtocolError(f"服务器协议版本 {server} 高于客户端请求的 {requested}")
    return server


def parse_message(content_type: str, body: str) -> dict | None:
    """解析一条 JSON-RPC 响应。空 body（例如通知的 202）返回 None。"""
    text = body or ""
    if not text.strip():
        return None
    ctype = (content_type or "").lower()
    stripped = text.lstrip()
    if "text/event-stream" in ctype or stripped.startswith("event:") or stripped.startswith("data:"):
        return _parse_sse(text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise MCPProtocolError("MCP 响应不是合法 JSON") from exc
    if not isinstance(data, dict):
        raise MCPProtocolError("MCP 响应不是 JSON 对象")
    return data


def _parse_sse(text: str) -> dict:
    messages: list[dict] = []
    data_lines: list[str] = []

    def flush():
        raw = "\n".join(data_lines).strip()
        data_lines.clear()
        if not raw:
            return
        try:
            item = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise MCPProtocolError("SSE data 不是合法 JSON") from exc
        if isinstance(item, dict):
            messages.append(item)

    for line in text.splitlines():
        if line == "":
            flush()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
    flush()
    for item in messages:
        if "result" in item or "error" in item:
            return item
    if messages:
        return messages[-1]
    raise MCPProtocolError("空的 SSE 响应")


def result_text(result: dict) -> str:
    """把 tools/call 的 content / structuredContent 收成一段文字。图片不进入正文。"""
    parts: list[str] = []
    for block in result.get("content") or []:
        if not isinstance(block, dict):
            continue
        kind = block.get("type")
        if kind == "text":
            parts.append(str(block.get("text") or ""))
        elif kind == "image":
            parts.append("[图片 1 张，已在卡片中显示]")
        elif kind == "audio":
            parts.append("[音频 1 段，已在卡片中显示]")
        elif kind in ("resource_link", "resource"):
            uri = str(block.get("uri") or "")
            if "?" in uri:
                uri = uri.split("?", 1)[0]
            name = block.get("name") or ""
            mime = block.get("mimeType") or ""
            parts.append(" ".join(x for x in (str(name), uri, str(mime)) if x))
    structured = result.get("structuredContent")
    if structured is not None:
        parts.append(json.dumps(structured, ensure_ascii=False, separators=(",", ":")))
    return "\n".join(parts)


@dataclass
class MCPSession:
    """一次到某个 MCP 端点的会话。initialize 之后工具调用复用 session id 与协议版本。"""
    url: str
    timeout: float | None = None
    session_id: str | None = None
    protocol_version: str | None = None
    _next_id: int = 1
    _http: httpx.Client = field(init=False, repr=False)

    def __post_init__(self):
        self.timeout = self.timeout if self.timeout is not None else timeout_seconds()
        self._http = httpx.Client(
            timeout=httpx.Timeout(self.timeout),
            follow_redirects=False,
            headers={"User-Agent": "VeraBot/0.1.0"},
        )

    def close(self):
        self._http.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def initialize(self) -> str:
        requested = requested_protocol()
        message = self._post("initialize", {
            "protocolVersion": requested,
            "capabilities": {},
            "clientInfo": {"name": "VeraBot", "version": "0.1.0"},
        }, negotiated=False)
        result = message.get("result") if message else None
        if not isinstance(result, dict):
            raise MCPProtocolError("initialize 没有返回 result")
        self.protocol_version = _accept_version(requested, result.get("protocolVersion"))
        # 规范要求握手后发送 initialized 通知。此时已经有 session id（如果服务器给了）。
        self._post("notifications/initialized", {}, notification=True)
        return self.protocol_version

    def list_tools(self) -> list[dict]:
        self._ensure()
        tools: list[dict] = []
        cursor = None
        seen: set[str] = set()
        while True:
            params = {}
            if cursor:
                params["cursor"] = cursor
            message = self._post("tools/list", params)
            result = (message or {}).get("result") or {}
            batch = result.get("tools") or []
            if not isinstance(batch, list):
                raise MCPProtocolError("tools/list 的 tools 不是数组")
            tools.extend(item for item in batch if isinstance(item, dict))
            cursor = result.get("nextCursor")
            if not cursor or cursor in seen:
                break
            seen.add(cursor)
            if len(seen) > 20:
                break
        return tools

    def call_tool(self, name: str, arguments: dict | None = None) -> CallResult:
        self._ensure()
        message = self._post("tools/call", {"name": name, "arguments": arguments or {}})
        result = (message or {}).get("result")
        if not isinstance(result, dict):
            raise MCPProtocolError("tools/call 没有返回 result")
        is_error = bool(result.get("isError"))
        return CallResult(
            is_error=is_error,
            text=result_text(result),
            raw=result,
            code="mcp_tool_error" if is_error else "ok",
        )

    def _ensure(self):
        if self.protocol_version is None:
            self.initialize()

    def _post(self, method: str, params: dict, *, notification: bool = False, negotiated: bool = True) -> dict | None:
        payload: dict = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notification:
            payload["id"] = self._next_id
            self._next_id += 1
        headers = {
            "Accept": ACCEPT,
            "Content-Type": "application/json",
        }
        # 只有服务器发过 session id 才回显；协议版本只在协商完成之后发送。
        if self.session_id:
            headers[SESSION_HEADER] = self.session_id
        if negotiated and self.protocol_version:
            headers[PROTOCOL_HEADER] = self.protocol_version
        try:
            response = self._http.post(self.url, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise MCPTimeoutError() from exc
        except httpx.TransportError as exc:
            raise MCPClientError("mcp_unavailable", f"MCP 服务不可用（{type(exc).__name__}）") from exc
        session = response.headers.get(SESSION_HEADER)
        if session:
            self.session_id = session
        message = parse_message(response.headers.get("content-type", ""), response.text)
        if message and message.get("error"):
            err = message["error"] if isinstance(message["error"], dict) else {"message": str(message["error"])}
            raise MCPRPCError(str(err.get("message") or "MCP 请求被拒绝"), err.get("code"))
        if response.status_code >= 400 and message is None:
            if response.status_code >= 500:
                raise MCPClientError("mcp_unavailable", f"MCP 服务返回 HTTP {response.status_code}")
            raise MCPProtocolError(f"MCP 服务返回 HTTP {response.status_code}")
        return message
