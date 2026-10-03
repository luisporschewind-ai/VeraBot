"""MCP 重试 + 熔断（retry / circuit breaker）与调用期间的卸载检测。从 service.py 原样搬出。"""
from __future__ import annotations

import os
import random
import threading
import time
from datetime import datetime, timedelta, timezone

from ...core.config import (
    MCP_BREAKER_COOLDOWN_DEFAULT,
    MCP_BREAKER_THRESHOLD_DEFAULT,
    MCP_RETRY_BACKOFF_DEFAULT,
    MCP_RETRY_MAX_DEFAULT,
)
from ...db import mcp_store
from .http_client import (
    MCPClientError,
    MCPSessionExpiredError,
    MCPTimeoutError,
    MCPUnavailableError,
)

_CIRCUIT_MESSAGE = "这个 MCP 服务连续失败，已暂时停止连接。请稍后再试。"


def _server_alive(user_id: int, server_id: int) -> bool:
    return mcp_store.get_server(user_id, server_id) is not None


def _safe_error(exc: MCPClientError) -> str:
    """给界面和模型的固定说明，不带外部响应正文。"""
    code = getattr(exc, "code", "")
    if code == "mcp_timeout":
        return "MCP 服务超时"
    if code == "mcp_protocol":
        return "MCP 协议错误"
    if code == "mcp_session_expired":
        return "MCP 会话已失效"
    if code == "mcp_rpc_error":
        return "MCP 服务拒绝了请求"
    return "MCP 服务不可用"


def _counts_toward_breaker(exc: BaseException) -> bool:
    return isinstance(exc, (MCPTimeoutError, MCPUnavailableError, MCPSessionExpiredError))


def _idempotent(tool: dict) -> bool:
    """只读，或可信注解标明可重复。非幂等的传输失败不自动重试（设计稿 §8）。"""
    if tool.get("risk") == "read":
        return True
    ann = tool.get("annotations") or {}
    return bool(ann.get("idempotentHint"))


_ALIVE_POLL_SECONDS = 0.1


def _interruptible(fn, alive=None):
    """在后台线程里执行一次 HTTP 调用，同时每 0.1 秒检查服务行。

    卸载插件时 drop_session 会关掉 httpx 客户端，但在 macOS 上关闭套接字不会唤醒另一个线程里阻塞的读取，
    进行中的调用要等到 MCP 超时（默认 15 秒）才返回。这里不等：服务行没了就立刻按 sent=True 抛出
    PluginUninstalled，后台线程自己结束（会话已从池里移除，结果丢弃）。
    """
    if alive is None:
        return fn()
    box: dict = {}
    done = threading.Event()

    def run():
        try:
            box["value"] = fn()
        except BaseException as exc:  # noqa: BLE001 - 原样转给调用方
            box["error"] = exc
        finally:
            done.set()

    threading.Thread(target=run, name="mcp-call", daemon=True).start()
    while not done.wait(_ALIVE_POLL_SECONDS):
        if not alive():
            raise PluginUninstalled(sent=True)
    if "error" in box:
        raise box["error"]
    return box["value"]


class _ResultUnknown(Exception):
    pass


class PluginUninstalled(Exception):
    """服务行在调用期间被删掉。sent=True 表示这次尝试已经把请求发出去了。"""

    def __init__(self, sent: bool = False):
        super().__init__("plugin_uninstalled")
        self.sent = sent


def _with_retries(op, *, idempotent: bool, alive=None):
    """超时、5xx、连接错误才重试。工具 isError 与 4xx 由 op 正常返回或直接抛出，不进这里的重试。

    alive 在每次尝试前检查服务行。卸载后不再重试。
    """
    attempts = _retry_max() + 1
    last: MCPClientError | None = None
    for index in range(attempts):
        if alive is not None and not alive():
            raise PluginUninstalled(sent=False)
        try:
            result = op()
        except MCPSessionExpiredError:
            if alive is not None and not alive():
                raise PluginUninstalled(sent=True)
            raise
        except MCPClientError as exc:
            if alive is not None and not alive():
                raise PluginUninstalled(sent=True) from exc
            if not isinstance(exc, (MCPTimeoutError, MCPUnavailableError)):
                raise
            last = exc
            # 非幂等：传输失败时请求可能已经执行，一律返回 result_unknown，不论还剩几次重试
            # （之前先判断 can_retry，VERABOT_MCP_RETRY_MAX=0 时会漏成普通超时 / 不可用）。
            if not idempotent:
                raise _ResultUnknown() from exc
            if index + 1 >= attempts:
                raise
            _sleep_backoff(index, exc)
            continue
        if alive is not None and not alive():
            raise PluginUninstalled(sent=True)
        return result
    if last:
        raise last
    raise MCPUnavailableError()


def _sleep_backoff(index: int, exc: MCPClientError):
    retry_after = getattr(exc, "retry_after", None)
    if isinstance(retry_after, (int, float)) and retry_after > 0:
        time.sleep(min(5.0, float(retry_after)))
        return
    backs = _backoffs()
    delay = backs[min(index, len(backs) - 1)]
    if delay > 0:
        delay += random.uniform(0, delay * 0.25)
        time.sleep(delay)


def _retry_max() -> int:
    raw = os.getenv("VERABOT_MCP_RETRY_MAX", str(MCP_RETRY_MAX_DEFAULT))
    try:
        return max(0, int(raw))
    except ValueError:
        return MCP_RETRY_MAX_DEFAULT



def _backoffs() -> list[float]:
    raw = os.getenv("VERABOT_MCP_RETRY_BACKOFF", MCP_RETRY_BACKOFF_DEFAULT)
    parts: list[float] = []
    for piece in raw.split(","):
        try:
            parts.append(max(0.0, float(piece.strip())))
        except ValueError:
            continue
    return parts or [0.5, 2.0]


def _breaker_threshold() -> int:
    raw = os.getenv("VERABOT_MCP_BREAKER_THRESHOLD", str(MCP_BREAKER_THRESHOLD_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_BREAKER_THRESHOLD_DEFAULT


def _breaker_cooldown() -> float:
    raw = os.getenv("VERABOT_MCP_BREAKER_COOLDOWN", str(MCP_BREAKER_COOLDOWN_DEFAULT))
    try:
        return max(0.0, float(raw))
    except ValueError:
        return float(MCP_BREAKER_COOLDOWN_DEFAULT)


def _record_success(user_id: int, server_id: int):
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return
    if int(row.get("circuit_failures") or 0) or row.get("circuit_open_until"):
        mcp_store.update_server(user_id, server_id, circuit_failures=0, circuit_open_until=None)


def _record_failure(user_id: int, server_id: int):
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return
    failures = int(row.get("circuit_failures") or 0) + 1
    if failures >= _breaker_threshold():
        until = (datetime.now(timezone.utc) + timedelta(seconds=_breaker_cooldown())).isoformat(timespec="microseconds")
        mcp_store.update_server(
            user_id, server_id, circuit_failures=failures, circuit_open_until=until,
            last_error=_CIRCUIT_MESSAGE,
        )
    else:
        mcp_store.update_server(user_id, server_id, circuit_failures=failures)


def _remember_error(user_id: int, server_id: int, exc: MCPClientError):
    mcp_store.update_server(user_id, server_id, last_error=_safe_error(exc))
