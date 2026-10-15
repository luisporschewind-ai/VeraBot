"""Load backend/.env for detached worker processes (stdlib only, no overrides).

start.sh exports .env before launching the API, but workers started directly
(`python -m verabot.services.chat_tasks`, screen, launchd) did not, so they ran
without DEEPSEEK_API_KEY and every reply failed. Must run before verabot.core.config
is imported because config reads os.environ at import time.
"""
import os
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[2]


def load_env_file(path=None):
    p = Path(path) if path else BACKEND_DIR / ".env"
    loaded = []
    if not p.is_file():
        return loaded
    for raw in p.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[7:].strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"\x27":
            val = val[1:-1]
        if key and val and not os.environ.get(key):
            os.environ[key] = val
            loaded.append(key)
    return loaded


def require(*keys):
    missing = [k for k in keys if not os.environ.get(k)]
    if missing:
        raise SystemExit("[VeraBot] worker 缺少环境变量: " + ", ".join(missing) + "（写入 backend/.env 或 export 后重试）")
