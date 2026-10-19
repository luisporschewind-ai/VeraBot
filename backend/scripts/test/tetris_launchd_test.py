"""Explicit isolated launchd restart proof; no production service or DB touched.
Run on a logged-in macOS host: python scripts/test/tetris_launchd_test.py --run
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from uuid import uuid4
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from render_tetris_worker_launchd import render
from verabot.db.migrations.v038_tetris_sessions import migrate
BACKEND = Path(__file__).resolve().parents[2]

def wait_value(function, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = function()
        if value: return value
        time.sleep(.1)
    raise RuntimeError("isolated launchd job did not become ready")

def run():
    domain = f"gui/{os.getuid()}"
    label = "com.verabot.tetris-test." + uuid4().hex
    with tempfile.TemporaryDirectory(prefix="verabot-tetris-supervision-") as folder:
        root = Path(folder); db = root / "test.db"
        c = sqlite3.connect(db)
        c.executescript("CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER);")
        migrate(c, 37); c.commit()
        path = root / "worker.plist"
        payload = plistlib.loads(render(BACKEND, Path(sys.executable), db, root, label))
        payload["EnvironmentVariables"]["VERABOT_JWT_SECRET"] = "isolated-supervision-only"
        path.write_bytes(plistlib.dumps(payload))
        def owner(exclude=None):
            row = c.execute("SELECT owner FROM tetris_workers WHERE heartbeat>? ORDER BY heartbeat DESC", (time.time()-3,)).fetchone()
            if row and row[0] != exclude: return row[0]
        try:
            subprocess.run(["launchctl", "bootstrap", domain, str(path)], check=True, capture_output=True)
            first = wait_value(owner)
            os.kill(int(first.split(":")[0]), signal.SIGKILL)
            second = wait_value(lambda: owner(first))
            assert first != second
            print(json.dumps({"isolated": True, "initialHeartbeat": True, "restartAfterSIGKILL": True, "ownerChanged": True, "productionTouched": False}))
        finally:
            subprocess.run(["launchctl", "bootout", domain + "/" + label], capture_output=True)
            # launchd kills its whole job on removal; no persistent agent file is installed.
            c.close()
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--run", action="store_true", required=True)
    parser.parse_args(); run()
