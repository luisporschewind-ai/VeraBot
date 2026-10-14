#!/usr/bin/env python3
"""Run offline backend checks, each script in its own process.

These scripts open a database while importing, so they cannot share one pytest process.
From the repository root:

    cd backend && uv run python scripts/test/run_offline.py
"""
import os
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[2]
SKIP = {
    "smoke_test.py",          # needs a running API and a real model key
    "web_browser_test.py",    # reaches the network
    "web_query_test.py",      # reaches the network
    "mcp_oauth_test.py",      # reaches an OAuth provider
    "group_http_test.py",     # needs an already-started HTTP server
    "group_execution_http_test.py",
}
EXTRA = ("sql_layer_check.py",)


def scripts():
    found = sorted(p for p in (BACKEND / "scripts" / "test").glob("*_test.py") if p.name not in SKIP)
    found.extend(BACKEND / "scripts" / "test" / name for name in EXTRA)
    return found


def main() -> int:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(BACKEND) + os.pathsep + env.get("PYTHONPATH", "")
    failed = []
    for path in scripts():
        print(f"\n== {path.name} ==", flush=True)
        result = subprocess.run([sys.executable, str(path)], cwd=BACKEND, env=env)
        if result.returncode != 0:
            failed.append(path.name)
            print(f"FAIL {path.name} (exit {result.returncode})", flush=True)
        else:
            print(f"PASS {path.name}", flush=True)
    print(f"\n{len(scripts()) - len(failed)} passed, {len(failed)} failed, {len(SKIP)} skipped")
    if failed:
        print("failed: " + ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
