"""`/api/*` 响应一律 `Cache-Control: no-store`：接口返回的都是某个账号的数据（令牌、对话、记忆、头像…），
不能留在客户端 / 代理的 HTTP 缓存里（iOS 的 URLCache 会把它们明文写进 Caches/<bundle>/Cache.db，
换账号后还在）。

规则：
- 只管 `/api/` 开头的路径；Web 静态文件、`/docs` 不动。
- 路由自己已经写了含 `no-store` 的值就保留（头像接口用 `private, no-store`）；其他值（如 SSE 的
  `no-cache`）一律替换成 `no-store`。另加 `Pragma: no-cache` 兼容 HTTP/1.0 代理。
- 纯 ASGI 实现，只改 `http.response.start` 的头，不缓冲响应体，SSE 流式不受影响。
"""
from __future__ import annotations

API_PREFIX = "/api/"
NO_STORE = "no-store"


class NoStoreAPIMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") != "http" or not str(scope.get("path", "")).startswith(API_PREFIX):
            await self.app(scope, receive, send)
            return

        async def send_wrapper(message):
            if message.get("type") == "http.response.start":
                message = dict(message)
                message["headers"] = with_no_store(message.get("headers") or [])
            await send(message)

        await self.app(scope, receive, send_wrapper)


def with_no_store(headers) -> list[tuple[bytes, bytes]]:
    """返回新的头列表：Cache-Control 必含 no-store，Pragma: no-cache。"""
    kept: list[tuple[bytes, bytes]] = []
    existing = None
    for k, v in headers:
        name = bytes(k).lower()
        if name == b"cache-control":
            existing = bytes(v)
            continue
        if name == b"pragma":
            continue
        kept.append((bytes(k), bytes(v)))
    value = existing if existing and NO_STORE.encode() in existing.lower() else NO_STORE.encode()
    kept.append((b"cache-control", value))
    kept.append((b"pragma", b"no-cache"))
    return kept
