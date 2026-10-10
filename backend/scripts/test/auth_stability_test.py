#!/usr/bin/env python3
"""登录稳定性回归：真实临时库、并发请求及密码输入边界。"""
import concurrent.futures
import os
from pathlib import Path
import sys
import tempfile
import threading

with tempfile.TemporaryDirectory(prefix="vb_auth_stability_") as tmp:
    os.environ["VERABOT_DB"] = str(Path(tmp) / "auth.db")
    os.environ["VERABOT_DATA_DIR"] = tmp
    os.environ["VERABOT_MAIL_BACKEND"] = "console"
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from fastapi.testclient import TestClient
    from verabot import db
    from verabot.main import app
    from verabot.services import auth

    db.init_db()
    client = TestClient(app, raise_server_exceptions=False)
    failures = []

    def check(name, fn):
        try:
            fn()
            print("PASS", name)
        except Exception as error:
            failures.append(name)
            print("FAIL", name, str(error))

    def run_together(count, fn):
        start = threading.Barrier(count)
        def worker():
            start.wait(timeout=10)
            return fn()
        with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool:
            return list(pool.map(lambda _: worker(), range(count)))

    def long_password_returns_validation_error():
        for body in [{"email": "long-ascii@example.com", "password": "a" * 73},
                     {"email": "long-unicode@example.com", "password": "锁" * 25},
                     {"username": "long-legacy", "password": "a" * 73}]:
            r = client.post("/api/auth/register", json=body)
            assert r.status_code == 422, (r.status_code, r.text)

    def concurrent_failures_are_counted_and_lock_account():
        account = auth.register_username("lock-race", "password123")
        def fail():
            try:
                auth.login("lock-race", "wrong-password")
                return 200
            except auth.AuthError as error:
                return error.status
        statuses = run_together(6, fail)
        with db.tx() as c:
            row = c.execute("SELECT locked_until FROM users WHERE id=?", (account["user"]["id"],)).fetchone()
        assert row[0] is not None, (statuses, "account was not locked")
        assert statuses.count(401) == 5 and statuses.count(429) == 1, statuses

    def concurrent_refresh_token_is_used_only_once():
        account = auth.register_username("refresh-race", "password123")
        def refresh():
            try:
                auth.refresh(account["refresh_token"])
                return 200
            except auth.AuthError as error:
                return error.status
        statuses = run_together(6, refresh)
        assert statuses.count(200) == 1 and statuses.count(401) == 5, statuses

    def concurrent_registration_returns_conflict():
        def register():
            return client.post("/api/auth/register", json={"email": "register-race@example.com",
                                                         "password": "password123"}).status_code
        statuses = run_together(6, register)
        assert statuses.count(200) == 1 and statuses.count(409) == 5, statuses

    def password_byte_limit_can_register_and_login():
        for email, password in [("ascii-limit@example.com", "a" * 72),
                                ("unicode-limit@example.com", "锁" * 24)]:
            created = client.post("/api/auth/register", json={"email": email, "password": password})
            assert created.status_code == 200, created.status_code
            logged_in = client.post("/api/auth/login", json={"identifier": email, "password": password})
            assert logged_in.status_code == 200, logged_in.status_code
            assert logged_in.json()["user"]["id"] == created.json()["user"]["id"]

    def concurrent_valid_logins_have_independent_sessions():
        account = auth.register_username("multi-device", "password123")
        sessions = run_together(6, lambda: auth.login("multi-device", "password123"))
        assert {s["user"]["id"] for s in sessions} == {account["user"]["id"]}
        assert len({s["refresh_token"] for s in sessions}) == 6
        # 每台设备可独立刷新，其他设备的刷新令牌仍然有效。
        for session in sessions:
            assert auth.refresh(session["refresh_token"])["user"]["id"] == account["user"]["id"]

    check("AUTH-STABLE-01 oversized password is 422", long_password_returns_validation_error)
    check("AUTH-STABLE-02 concurrent failures lock account", concurrent_failures_are_counted_and_lock_account)
    check("AUTH-STABLE-03 concurrent refresh has one success", concurrent_refresh_token_is_used_only_once)
    check("AUTH-STABLE-04 concurrent registration returns conflict", concurrent_registration_returns_conflict)
    check("AUTH-STABLE-05 password byte limit can register and login", password_byte_limit_can_register_and_login)
    check("AUTH-STABLE-06 concurrent valid logins have independent sessions", concurrent_valid_logins_have_independent_sessions)
    assert not failures, failures
    print("AUTH stability tests passed: 6/6")
