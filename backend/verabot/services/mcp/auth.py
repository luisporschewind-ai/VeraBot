"""授权抽象（AuthProvider）：none / static_bearer（MCP_AUTH_CONNECTORS_PLAN v1.0 P1）。OAuth 在 P2。

令牌只在这里解密、只在内存里拼进请求头，不写入日志、异常、审计、API 响应或 LLM 上下文。
密文在 mcp_credentials.access_token_enc（core.crypto 的 token 密钥）。
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from ...core import crypto
from ...db import mcp_store
from . import catalog

# 服务行上的授权错误：有这些错误时视为「没有有效凭据」，停在 needs_auth，不调度同步。
AUTH_ERRORS = frozenset({"token_invalid", "expired", "insufficient_scope"})


def spec_for(row: dict) -> dict | None:
    return catalog.by_id(row.get("catalog_id") or "") or catalog.by_slug(row["slug"])


def requires_auth(spec: dict | None) -> bool:
    return bool(spec) and (spec.get("auth") or "none") != "none"


@dataclass(frozen=True)
class AuthHeaders:
    headers: dict
    version: str   # 凭据版本：换令牌后会话池自动换新会话

    def __repr__(self) -> str:   # 不打印请求头（含令牌）
        return f"AuthHeaders(version={self.version!r}, headers=<{len(self.headers)} redacted>)"


class AuthProvider:
    kind = "none"

    def __init__(self, spec: dict | None):
        self.spec = spec or {}

    def has_credential(self, user_id: int, row: dict) -> bool:
        return True

    def headers(self, user_id: int, row: dict) -> AuthHeaders | None:
        """None = 需要授权但没有可用凭据。"""
        return AuthHeaders(dict(self.spec.get("static_headers") or {}), "none")


class StaticBearerProvider(AuthProvider):
    kind = "static_bearer"

    def has_credential(self, user_id: int, row: dict) -> bool:
        if (row.get("auth_error") or "") in AUTH_ERRORS:
            return False
        return mcp_store.get_credential(user_id, row["id"]) is not None

    def headers(self, user_id: int, row: dict) -> AuthHeaders | None:
        cred = mcp_store.get_credential(user_id, row["id"])
        if cred is None:
            return None
        token = crypto.decrypt(cred.get("access_token_enc"), "token")
        if not token:
            return None   # 密钥丢失 / 被篡改：当作没有凭据
        return AuthHeaders(bearer_headers(self.spec, token), f"{cred['id']}:{cred['updated_at']}")


def provider_for(spec: dict | None) -> AuthProvider:
    if requires_auth(spec):
        if spec.get("auth") == "bearer":
            return StaticBearerProvider(spec)
        raise ValueError(f"unsupported auth {spec.get('auth')}")   # oauth：P2
    return AuthProvider(spec)


def bearer_headers(spec: dict, token: str) -> dict:
    cred = spec.get("credential") or {}
    out = dict(spec.get("static_headers") or {})
    out[cred.get("header") or "Authorization"] = f"{cred.get('scheme') or 'Bearer'} {token}"
    return out


def format_ok(spec: dict, token: str) -> bool:
    pattern = (spec.get("credential") or {}).get("pattern")
    return bool(token) and (not pattern or re.fullmatch(pattern, token) is not None)


def hint(token: str) -> str:
    return "…" + token[-4:]
