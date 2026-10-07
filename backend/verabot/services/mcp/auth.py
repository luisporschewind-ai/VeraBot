"""授权抽象（AuthProvider）：none / static_bearer（MCP_AUTH_CONNECTORS_PLAN v1.0 P1）。OAuth 在 P2。

令牌只在这里解密、只在内存里拼进请求头，不写入日志、异常、审计、API 响应或 LLM 上下文。
密文在 mcp_credentials.access_token_enc（core.crypto 的 token 密钥）。
"""
from __future__ import annotations

import re
import threading
from datetime import datetime, timezone
from dataclasses import dataclass

import httpx

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


_oauth_refresh_locks: dict[tuple[int, int], threading.Lock] = {}
_oauth_refresh_locks_guard = threading.Lock()


class OAuthBearerProvider(AuthProvider):
    """Issuer-bound OAuth credentials with serialized, fail-closed refresh."""
    kind = "oauth"

    def _credential(self, user_id: int, row: dict) -> dict | None:
        issuer = self.spec.get("oauth_issuer")
        return mcp_store.get_credential_for_issuer(user_id, row["id"], issuer) if issuer else None

    def has_credential(self, user_id: int, row: dict) -> bool:
        if (row.get("auth_error") or "") in AUTH_ERRORS:
            return False
        cred = self._credential(user_id, row)
        if not cred or not cred.get("access_token_enc"):
            return False
        return bool(crypto.decrypt(cred["access_token_enc"], "token"))

    def headers(self, user_id: int, row: dict) -> AuthHeaders | None:
        if (row.get("auth_error") or "") in AUTH_ERRORS:
            return None
        cred = self._credential(user_id, row)
        if not cred:
            return None
        token = crypto.decrypt(cred.get("access_token_enc"), "token")
        if not token:
            return None
        expiry = cred.get("expires_at")
        if expiry:
            try:
                expires = datetime.fromisoformat(expiry.replace("Z", "+00:00"))
                remaining = (expires - datetime.now(timezone.utc)).total_seconds()
            except (TypeError, ValueError):
                remaining = -1
            if remaining < 60:
                refreshed = self._refresh(user_id, row, cred)
                if not refreshed:
                    return None
                cred = refreshed
                token = crypto.decrypt(cred.get("access_token_enc"), "token")
                if not token:
                    return None
        return AuthHeaders(bearer_headers(self.spec, token), f"{cred['id']}:{cred['updated_at']}")

    def _refresh(self, user_id: int, row: dict, cred: dict) -> dict | None:
        key = (user_id, row["id"])
        with _oauth_refresh_locks_guard:
            lock = _oauth_refresh_locks.setdefault(key, threading.Lock())
        with lock:
            latest = self._credential(user_id, row)
            if not latest:
                return None
            try:
                if latest.get("expires_at"):
                    expires = datetime.fromisoformat(latest["expires_at"].replace("Z", "+00:00"))
                    if (expires - datetime.now(timezone.utc)).total_seconds() >= 60:
                        return latest
            except (TypeError, ValueError):
                pass
            refresh_token = crypto.decrypt(latest.get("refresh_token_enc"), "token")
            if not refresh_token:
                self._mark_expired(user_id, row["id"])
                return None
            client_id = self.spec.get("oauth_client_id")
            client_secret = self.spec.get("oauth_client_secret")
            if not client_id:
                self._mark_expired(user_id, row["id"])
                return None
            form = {"grant_type": "refresh_token", "refresh_token": refresh_token,
                    "client_id": client_id, "resource": row["url"]}
            if client_secret:
                form["client_secret"] = client_secret
            try:
                response = httpx.post(self.spec.get("oauth_token_endpoint", "https://oauth2.googleapis.com/token"),
                                      data=form, timeout=15.0, follow_redirects=False)
                if response.status_code != 200:
                    self._mark_expired(user_id, row["id"])
                    return None
                payload = response.json()
                access = payload.get("access_token")
                if not isinstance(access, str) or not access:
                    self._mark_expired(user_id, row["id"])
                    return None
                from .oauth import _iso_after
                mcp_store.save_oauth_storage(
                    user_id, row["id"], self.spec["oauth_issuer"],
                    access_token_enc=crypto.encrypt(access, "token"),
                    refresh_token_enc=crypto.encrypt(payload["refresh_token"], "token")
                    if payload.get("refresh_token") else None,
                    expires_at=_iso_after(payload.get("expires_in")),
                    scopes=payload.get("scope") or latest.get("scopes"),
                    token_hint="…" + access[-4:],
                    clear_expiry=True,
                )
                return self._credential(user_id, row)
            except Exception:
                # Do not surface provider bodies or credentials through logs/errors.
                return None

    @staticmethod
    def _mark_expired(user_id: int, server_id: int) -> None:
        mcp_store.update_server(user_id, server_id, status="needs_auth", auth_error="expired",
                                last_error="授权已失效")


def provider_for(spec: dict | None) -> AuthProvider:
    if requires_auth(spec):
        if spec.get("auth") == "bearer":
            return StaticBearerProvider(spec)
        if spec.get("auth") == "oauth":
            return OAuthBearerProvider(spec)
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
