"""OAuth 2.1 support for remote MCP servers.

The MCP SDK owns protocol discovery, PKCE, state/issuer validation and token refresh.
This module supplies issuer-scoped encrypted storage and the in-process callback bridge.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlparse

import httpx2
from mcp.client.auth import OAuthClientProvider, TokenStorage
from mcp.shared.auth import AuthorizationCodeResult, OAuthClientInformationFull, OAuthClientMetadata, OAuthToken

from ...core import crypto
from ...db import mcp_store

log = logging.getLogger("verabot.mcp.oauth")


def _iso_after(seconds: int | None) -> str | None:
    if seconds is None:
        return None
    return (datetime.now(timezone.utc) + timedelta(seconds=max(0, seconds))).isoformat(timespec="seconds")


class DatabaseTokenStorage(TokenStorage):
    """SDK TokenStorage keyed to one user, MCP server, and authorization-server issuer."""

    def __init__(self, user_id: int, server_id: int, issuer: str | None,
                 redirect_uri: str | None = None, client_id: str | None = None,
                 client_secret: str | None = None):
        self.user_id = user_id
        self.server_id = server_id
        self.issuer = issuer
        self.redirect_uri = redirect_uri
        self.pre_registered_client_id = client_id
        self.pre_registered_client_secret = client_secret

    def _row(self) -> dict | None:
        return mcp_store.get_credential_for_issuer(self.user_id, self.server_id, self.issuer)

    async def get_tokens(self) -> OAuthToken | None:
        row = self._row()
        if not row or not row.get("access_token_enc"):
            return None
        access = crypto.decrypt(row.get("access_token_enc"), "token")
        if not access:
            return None
        refresh = crypto.decrypt(row.get("refresh_token_enc"), "token")
        expires_in = None
        if row.get("expires_at"):
            try:
                expiry = datetime.fromisoformat(row["expires_at"].replace("Z", "+00:00"))
                expires_in = max(0, int((expiry - datetime.now(timezone.utc)).total_seconds()))
            except (TypeError, ValueError):
                expires_in = 0
        return OAuthToken(access_token=access, refresh_token=refresh, expires_in=expires_in,
                          scope=row.get("scopes"))

    async def set_tokens(self, tokens: OAuthToken) -> None:
        mcp_store.save_oauth_storage(
            self.user_id, self.server_id, self.issuer,
            access_token_enc=crypto.encrypt(tokens.access_token, "token"),
            refresh_token_enc=crypto.encrypt(tokens.refresh_token, "token") if tokens.refresh_token else None,
            expires_at=_iso_after(tokens.expires_in), scopes=tokens.scope,
            token_hint="…" + tokens.access_token[-4:],
            clear_expiry=True,
        )

    async def get_client_info(self) -> OAuthClientInformationFull | None:
        row = self._row()
        raw = crypto.decrypt(row.get("client_info_enc"), "token") if row else None
        if not raw and self.issuer and self.redirect_uri:
            from ...db.database import tx
            with tx() as c:
                client_row = c.execute(
                    "SELECT registration_enc FROM mcp_oauth_clients WHERE issuer=? AND redirect_uri=?",
                    (self.issuer, self.redirect_uri),
                ).fetchone()
            if client_row:
                raw = crypto.decrypt(client_row["registration_enc"], "token")
        if not raw and self.pre_registered_client_id:
            client = OAuthClientInformationFull(
                client_id=self.pre_registered_client_id,
                client_secret=self.pre_registered_client_secret or None,
                redirect_uris=[self.redirect_uri] if self.redirect_uri else None,
                token_endpoint_auth_method="client_secret_post" if self.pre_registered_client_secret else "none",
                issuer=self.issuer,
            )
            await self.set_client_info(client)
            return client
        if not raw:
            return None
        try:
            client = OAuthClientInformationFull.model_validate_json(raw)
        except Exception:
            return None
        return client

    async def set_client_info(self, client_info: OAuthClientInformationFull) -> None:
        # The SDK stamps the discovered issuer on dynamic registrations. Keep that binding
        # authoritative even if a caller constructed a client record without it.
        if client_info.issuer and client_info.issuer != self.issuer:
            raise ValueError("OAuth client issuer does not match this storage scope")
        bound = client_info.model_copy(update={"issuer": self.issuer})
        encoded = crypto.encrypt(bound.model_dump_json(exclude_none=True), "token")
        redirect_uri = str((bound.redirect_uris or ["com.verabot.app:/oauth/callback"])[0])
        secret_enc = crypto.encrypt(bound.client_secret, "token") if bound.client_secret else None
        registration_enc = crypto.encrypt(bound.model_dump_json(exclude_none=True), "token")
        from ...db.database import now_iso, tx
        stamp = now_iso()
        with tx() as c:
            c.execute(
                """INSERT INTO mcp_oauth_clients(issuer,redirect_uri,client_id,client_secret_enc,
                   registration_enc,created_at,updated_at) VALUES(?,?,?,?,?,?,?)
                   ON CONFLICT(issuer,redirect_uri) DO UPDATE SET client_id=excluded.client_id,
                   client_secret_enc=excluded.client_secret_enc,registration_enc=excluded.registration_enc,
                   updated_at=excluded.updated_at""",
                (self.issuer, redirect_uri, bound.client_id, secret_enc, registration_enc, stamp, stamp),
            )
        mcp_store.save_oauth_storage(self.user_id, self.server_id, self.issuer, client_info_enc=encoded)


@dataclass
class _Attempt:
    user_id: int
    server_id: int
    auth_url: asyncio.Future
    callback: asyncio.Future
    task: asyncio.Task
    storage: DatabaseTokenStorage
    issuer: str | None = None


_ATTEMPTS: dict[str, _Attempt] = {}
_ATTEMPTS_LOCK = asyncio.Lock()
_FLOW_TIMEOUT = 600


class OAuthError(Exception):
    """Safe OAuth flow failure; detail never includes provider response bodies."""


async def start_authorization(user_id: int, server: dict, spec: dict) -> dict:
    if not spec.get("oauth_client_id"):
        raise OAuthError("Google OAuth 客户端尚未配置")
    redirect_uri = str(spec.get("oauth_redirect_uri") or "com.verabot.app:/oauth/callback")
    storage = DatabaseTokenStorage(
        user_id, server["id"], spec.get("oauth_issuer"), redirect_uri,
        spec.get("oauth_client_id"), spec.get("oauth_client_secret"),
    )
    try:
        discovery = json.loads(server.get("discover_json") or "{}")
    except (TypeError, ValueError):
        discovery = {}
    requested_scopes = list(dict.fromkeys(
        (spec.get("oauth_scope") or "").split()
        + (server.get("granted_scopes") or "").split()
        + list(discovery.get("required_scopes") or [])
    ))
    metadata = OAuthClientMetadata(
        redirect_uris=[redirect_uri],
        scope=" ".join(requested_scopes),
        token_endpoint_auth_method="client_secret_post" if spec.get("oauth_client_secret") else "none",
        client_name="VeraBot",
    )
    auth_url_future = asyncio.get_running_loop().create_future()
    callback_future = asyncio.get_running_loop().create_future()
    provider: OAuthClientProvider

    async def redirect_handler(auth_url: str) -> None:
        params = parse_qs(urlparse(auth_url).query)
        state = (params.get("state") or [None])[0]
        issuer = provider.context.auth_server_url or spec.get("oauth_issuer")
        if not state or not issuer:
            raise OAuthError("授权服务器未返回有效授权状态")
        payload = json.dumps({"issuer": issuer, "server_url": server["url"]}, separators=(",", ":"))
        expiry = _iso_after(_FLOW_TIMEOUT)
        mcp_store.insert_oauth_state(state, user_id, server["id"], "mcp", crypto.encrypt(payload, "token"), expiry)
        async with _ATTEMPTS_LOCK:
            attempt.issuer = issuer
            _ATTEMPTS[state] = attempt
        if not auth_url_future.done():
            auth_url_future.set_result((auth_url, state, redirect_uri))

    async def callback_handler() -> AuthorizationCodeResult:
        return await asyncio.wait_for(callback_future, timeout=_FLOW_TIMEOUT)

    provider = OAuthClientProvider(
        server_url=server["url"], client_metadata=metadata, storage=storage,
        redirect_handler=redirect_handler, callback_handler=callback_handler,
    )

    async def probe() -> None:
        try:
            async with httpx2.AsyncClient(auth=provider, timeout=20.0) as client:
                await client.post(
                    server["url"],
                    json={"jsonrpc": "2.0", "id": "oauth-init", "method": "initialize", "params": {
                        "protocolVersion": "2025-06-18", "capabilities": {},
                        "clientInfo": {"name": "VeraBot", "version": "0.1.0"},
                    }},
                    headers={"Accept": "application/json, text/event-stream",
                             "MCP-Protocol-Version": "2025-06-18"},
                )
        except Exception as exc:
            # Do not log SDK exceptions: some HTTP/OAuth errors embed response content.
            if not auth_url_future.done():
                auth_url_future.set_exception(OAuthError("无法启动 OAuth 授权"))
            if not callback_future.done():
                callback_future.set_exception(OAuthError("OAuth 授权未完成"))
            log.warning("MCP OAuth flow ended (%s)", type(exc).__name__)

    task = asyncio.create_task(probe())
    attempt = _Attempt(user_id, server["id"], auth_url_future, callback_future, task, storage)
    try:
        auth_url, state, redirect_uri = await asyncio.wait_for(auth_url_future, timeout=30)
    except Exception:
        task.cancel()
        raise OAuthError("无法从 MCP 服务取得授权地址") from None
    parsed = urlparse(redirect_uri)
    return {"auth_url": auth_url, "state": state, "callback_scheme": parsed.scheme}


async def complete_authorization(user_id: int, server_id: int, *, code: str, state: str,
                                 issuer: str | None) -> dict:
    consumed = mcp_store.consume_oauth_state(state, user_id, server_id)
    if not consumed:
        raise OAuthError("授权状态无效、已过期或已使用")
    async with _ATTEMPTS_LOCK:
        attempt = _ATTEMPTS.pop(state, None)
    if attempt is None or attempt.user_id != user_id or attempt.server_id != server_id:
        raise OAuthError("授权流程已失效，请重新连接")
    if attempt.callback.done():
        raise OAuthError("授权状态已使用")
    attempt.callback.set_result(AuthorizationCodeResult(code=code, state=state, iss=issuer))
    try:
        await asyncio.wait_for(attempt.task, timeout=30)
    except Exception:
        raise OAuthError("Google 授权失败，请重试") from None
    if issuer and attempt.issuer and issuer != attempt.issuer:
        raise OAuthError("授权服务器不匹配")
    tokens = await attempt.storage.get_tokens()
    if not tokens:
        raise OAuthError("授权未返回可用凭据")
    scopes = sorted(set((tokens.scope or "").split()))
    prior_server = mcp_store.get_server(user_id, server_id) or {}
    try:
        prior_discovery = json.loads(prior_server.get("discover_json") or "{}")
    except (TypeError, ValueError):
        prior_discovery = {}
    next_discovery = json.dumps({"step_up_attempts": int(prior_discovery.get("step_up_attempts") or 0)}) \
        if prior_server.get("status") == "needs_scope" else None
    mcp_store.update_server(user_id, server_id, status="connected", auth_error=None, last_error=None,
                            granted_scopes=" ".join(scopes), account_label="Google 账号",
                            discover_json=next_discovery)
    return {"status": "connected", "account": "Google 账号", "scopes": scopes,
            "tools_count": mcp_store.tool_count(user_id, server_id)}


async def cancel_authorization(user_id: int, server_id: int, state: str) -> bool:
    if not mcp_store.delete_oauth_state(state, user_id, server_id):
        return False
    async with _ATTEMPTS_LOCK:
        attempt = _ATTEMPTS.pop(state, None)
    if attempt and attempt.user_id == user_id and attempt.server_id == server_id:
        if not attempt.callback.done():
            attempt.callback.set_exception(OAuthError("用户取消了授权"))
        attempt.task.cancel()
    return True


def disconnect(user_id: int, server: dict, spec: dict) -> None:
    """Remove locally stored OAuth material. Google revocation is best effort and never blocks disconnect."""
    issuer = spec.get("oauth_issuer")
    if not issuer:
        return
    cred = mcp_store.get_credential_for_issuer(user_id, server["id"], issuer)
    if cred:
        refresh = crypto.decrypt(cred.get("refresh_token_enc"), "token")
        access = crypto.decrypt(cred.get("access_token_enc"), "token")
        token = refresh or access
        if token:
            endpoint = spec.get("oauth_revocation_endpoint")
            if endpoint:
                try:
                    httpx2.post(endpoint, data={"token": token}, timeout=8.0)
                except Exception:
                    pass
    mcp_store.delete_credential_for_issuer(user_id, server["id"], issuer)
    mcp_store.update_server(user_id, server["id"], status="needs_auth", auth_error=None,
                            account_label=None, granted_scopes=None, last_error=None, sync_status="pending")
