#!/usr/bin/env python3
"""MCP M4 OAuth contracts. All OAuth resources are process-local fakes."""
import json, os, sqlite3, sys, tempfile, threading, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_mcp_oauth_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "oauth.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
os.environ["VERABOT_MEMORY_JOBS"] = "0"
os.environ.pop("VERABOT_TOKEN_ENC_KEY", None)
sys.path.insert(0, str(ROOT))

from mcp.shared.auth import OAuthClientInformationFull, OAuthToken
from verabot import db
from verabot.db import mcp_store
from verabot.services.mcp.oauth import DatabaseTokenStorage

db.init_db()
with sqlite3.connect(os.environ["VERABOT_DB"]) as con:
    con.execute("INSERT INTO users(username,password_hash,created_at) VALUES('oauth-test','x','2026-01-01')")
    user_id = con.execute("SELECT id FROM users WHERE username='oauth-test'").fetchone()[0]
row = mcp_store.insert_server(user_id, {
    "slug": "oauth-test", "catalog_id": "oauth-test", "name": "OAuth test",
    "transport": "streamable_http", "trust": "verified", "auth": "oauth", "url": "http://127.0.0.1:8888/mcp",
}, "needs_auth")
server_id = row["id"]


async def storage_contract():
    storage = DatabaseTokenStorage(user_id, server_id, "https://issuer.test")
    token = OAuthToken(access_token="at-secret", refresh_token="rt-secret", expires_in=120, scope="mail.read")
    client = OAuthClientInformationFull(
        client_id="client-secret-id", client_secret="client-secret-value",
        redirect_uris=["com.verabot.app:/oauth/callback"], issuer="https://issuer.test",
    )
    await storage.set_tokens(token)
    await storage.set_client_info(client)
    loaded = await storage.get_tokens()
    assert loaded is not None and loaded.access_token == token.access_token
    assert loaded.refresh_token == token.refresh_token and loaded.scope == token.scope
    assert 0 < loaded.expires_in <= token.expires_in
    assert (await storage.get_client_info()).client_secret == "client-secret-value"
    other = DatabaseTokenStorage(user_id, server_id, "https://other-issuer.test")
    assert await other.get_tokens() is None
    assert await other.get_client_info() is None
    with sqlite3.connect(os.environ["VERABOT_DB"]) as con:
        raw = " ".join(str(v) for row in con.execute(
            "SELECT access_token_enc,refresh_token_enc,client_info_enc FROM mcp_credentials"
        ) for v in row)
    assert "at-secret" not in raw and "rt-secret" not in raw and "client-secret-value" not in raw


class OAuthMock(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self):
        self.token_form = None
        self.revoked = False
        super().__init__(("127.0.0.1", 0), OAuthHandler)
        self.base = f"http://127.0.0.1:{self.server_address[1]}"
        threading.Thread(target=self.serve_forever, daemon=True).start()


class OAuthHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, body=None, headers=None):
        raw = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if raw:
            self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/.well-known/oauth-protected-resource/mcp":
            return self.reply(200, {"resource": self.server.base + "/mcp",
                                    "authorization_servers": [self.server.base]})
        if self.path == "/.well-known/oauth-authorization-server":
            return self.reply(200, {"issuer": self.server.base,
                                    "authorization_endpoint": self.server.base + "/authorize",
                                    "token_endpoint": self.server.base + "/token",
                                    "code_challenge_methods_supported": ["S256"],
                                    "authorization_response_iss_parameter_supported": True})
        self.reply(404)

    def do_POST(self):
        if self.path == "/token":
            length = int(self.headers.get("Content-Length", "0"))
            self.server.token_form = urllib.parse.parse_qs(self.rfile.read(length).decode())
            form = self.server.token_form
            if form.get("grant_type") == ["refresh_token"]:
                if form.get("refresh_token") != ["oauth-refresh-secret"]:
                    return self.reply(400, {"error": "invalid_grant"})
                return self.reply(200, {"access_token": "oauth-refreshed-access", "token_type": "bearer",
                                        "expires_in": 3600, "scope": "email.read"})
            if form.get("code") != ["good-code"] or not form.get("code_verifier"):
                return self.reply(400, {"error": "invalid_grant"})
            return self.reply(200, {"access_token": "oauth-access-secret", "refresh_token": "oauth-refresh-secret",
                                    "token_type": "bearer", "expires_in": 3600, "scope": "email.read"})
        if self.path == "/revoke":
            self.server.revoked = True
            return self.reply(200, {})
        if self.path == "/mcp":
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
            if self.headers.get("Authorization") != "Bearer oauth-access-secret":
                return self.reply(401, {"detail": "auth required"}, {"WWW-Authenticate":
                    f'Bearer resource_metadata="{self.server.base}/.well-known/oauth-protected-resource/mcp", scope="email.read"'})
            method = body.get("method")
            if method == "initialize":
                return self.reply(200, {"jsonrpc": "2.0", "id": body["id"], "result": {
                    "protocolVersion": "2025-03-26", "capabilities": {"tools": {}}, "serverInfo": {"name": "fake", "version": "1"}}})
            if method == "notifications/initialized":
                return self.reply(202)
            if method == "tools/list":
                return self.reply(200, {"jsonrpc": "2.0", "id": body["id"], "result": {"tools": []}})
            return self.reply(400)
        self.reply(404)


def oauth_api_contract():
    mock = OAuthMock()
    os.environ["VERABOT_MCP_GMAIL_URL"] = mock.base + "/mcp"
    os.environ["VERABOT_MCP_GOOGLE_ISSUER"] = mock.base
    os.environ["VERABOT_MCP_GOOGLE_TOKEN_ENDPOINT"] = mock.base + "/token"
    os.environ["VERABOT_MCP_GOOGLE_REVOCATION_ENDPOINT"] = mock.base + "/revoke"
    os.environ["VERABOT_MCP_GOOGLE_CLIENT_ID"] = "fake-google-client"
    os.environ["VERABOT_MCP_GOOGLE_REDIRECT_URI"] = "com.googleusercontent.apps.fake:/oauth2redirect"
    from fastapi.testclient import TestClient
    from verabot.main import app
    from verabot.services.plugins import service as plugins
    from verabot.db import plugin_store
    with TestClient(app) as client:
        auth = client.post("/api/auth/register", json={"username": "oauth-api", "password": "pw123456"}).json()
        headers = {"Authorization": "Bearer " + auth["token"]}
        installed = client.post("/api/plugins/gmail_google/install", headers=headers)
        assert installed.status_code == 201, installed.text
        server_id = installed.json()["servers"][0]["id"]
        started = client.post(f"/api/mcp/servers/{server_id}/auth/start", headers=headers)
        assert started.status_code == 200, started.text
        result = started.json()
        params = urllib.parse.parse_qs(urllib.parse.urlparse(result["auth_url"]).query)
        assert params["response_type"] == ["code"]
        assert params["code_challenge_method"] == ["S256"]
        assert params["resource"] == [mock.base + "/mcp"]
        callback = client.post(f"/api/mcp/servers/{server_id}/auth/callback", headers=headers, json={
            "code": "good-code", "state": params["state"][0], "iss": mock.base,
        })
        assert callback.status_code == 200, callback.text
        body = callback.json()
        assert body["status"] == "connected" and body["scopes"] == ["email.read"]
        assert "access_token" not in json.dumps(body) and "refresh_token" not in json.dumps(body)
        assert mock.token_form["resource"] == [mock.base + "/mcp"]
        assert len(mock.token_form["code_verifier"][0]) >= 43
        replay = client.post(f"/api/mcp/servers/{server_id}/auth/callback", headers=headers, json={
            "code": "good-code", "state": params["state"][0], "iss": mock.base,
        })
        assert replay.status_code == 400
        with sqlite3.connect(os.environ["VERABOT_DB"]) as con:
            raw = " ".join(str(v) for row in con.execute(
                "SELECT access_token_enc,refresh_token_enc FROM mcp_credentials WHERE server_id=?", (server_id,)
            ) for v in row)
        assert "oauth-access-secret" not in raw and "oauth-refresh-secret" not in raw
        expired_at = "2000-01-01T00:00:00+00:00"
        with sqlite3.connect(os.environ["VERABOT_DB"]) as con:
            owner_id = con.execute("SELECT user_id FROM mcp_servers WHERE id=?", (server_id,)).fetchone()[0]
        from verabot.services.mcp.auth import provider_for
        row = mcp_store.get_server(owner_id, server_id)
        spec = __import__("verabot.services.mcp.catalog", fromlist=["by_id"]).by_id("gmail_google")
        mcp_store.save_oauth_storage(owner_id, server_id, mock.base, expires_at=expired_at)
        oauth_headers = provider_for(spec).headers(owner_id, row)
        assert oauth_headers and oauth_headers.headers["Authorization"] == "Bearer oauth-refreshed-access"
        assert mock.token_form["grant_type"] == ["refresh_token"]
        assert mock.token_form["resource"] == [mock.base + "/mcp"]
        disconnected = client.delete(f"/api/mcp/servers/{server_id}/auth", headers=headers)
        assert disconnected.status_code == 200, disconnected.text
        assert mock.revoked
        assert mcp_store.get_credential_for_issuer(owner_id, server_id, mock.base) is None
    mock.shutdown()


if __name__ == "__main__":
    import asyncio
    asyncio.run(storage_contract())
    print("PASS MCP-21 OAuth token/client info storage encrypted and issuer scoped")
    oauth_api_contract()
    print("PASS MCP-20 OAuth start/callback uses PKCE, resource and one-time user-bound state")
