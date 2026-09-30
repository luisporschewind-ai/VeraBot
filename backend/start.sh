#!/usr/bin/env bash
# VeraBot 后端一键启动（macOS / Linux）
#   ./start.sh              安装 uv（如缺失）→ 按 uv.lock 同步依赖 → 准备 .env → 初始化数据库 → 前台启动
#   ./start.sh --detach     同上，但后台运行（日志 data/server.log，PID data/server.pid；停止：./stop.sh）
#   ./start.sh --setup-only 只做安装与初始化，不启动服务
# 网络受限时自动回退到国内镜像：PyPI 使用 VERABOT_PYPI_MIRROR（默认清华 tuna），Python 解释器使用 npmmirror。
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"
MIRROR="${VERABOT_PYPI_MIRROR:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PY_MIRROR="${VERABOT_PYTHON_MIRROR:-https://registry.npmmirror.com/-/binary/python-build-standalone}"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
say() { echo "[VeraBot] $*"; }

# ---- 1. uv ----
UV=(uv)
if ! command -v uv >/dev/null 2>&1; then
  say "未找到 uv，正在安装 …"
  if ! curl -LsSf --max-time 120 https://astral.sh/uv/install.sh | sh; then
    say "官方安装失败，改用 PyPI 镜像安装 uv：$MIRROR"
    python3 -m pip install --user -q -i "$MIRROR" uv
  fi
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || UV=(python3 -m uv)
fi
say "uv: $("${UV[@]}" --version)"

# ---- 2. Python + 依赖（按 uv.lock 精确同步）----
if ! "${UV[@]}" python find >/dev/null 2>&1; then
  say "安装 Python（.python-version）…"
  "${UV[@]}" python install || UV_PYTHON_INSTALL_MIRROR="$PY_MIRROR" "${UV[@]}" python install
fi
if [ "${VERABOT_FORCE_MIRROR:-0}" != "1" ] && "${UV[@]}" sync --frozen --no-dev; then
  :
else
  say "改用镜像 ${MIRROR}（按 requirements.txt 锁定版本安装；VERABOT_FORCE_MIRROR=1 可直接走镜像）"
  UV_INDEX_URL="$MIRROR" "${UV[@]}" venv --allow-existing .venv
  UV_INDEX_URL="$MIRROR" "${UV[@]}" pip install --python .venv/bin/python -r requirements.txt
fi
PY=.venv/bin/python

# ---- 3. .env（已导出的环境变量优先）----
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  say "已根据 .env.example 创建 .env"
fi
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  val="${val%\"}"; val="${val#\"}"
  if [ -z "${!key:-}" ] && [ -n "$val" ]; then export "$key=$val"; fi
done < .env
if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  if [ -t 0 ]; then
    read -r -s -p "[VeraBot] 请输入 DeepSeek API Key（输入不回显，保存到 .env）：" DEEPSEEK_API_KEY; echo
    [ -n "$DEEPSEEK_API_KEY" ] || { say "未输入 Key，退出"; exit 1; }
    KEY="$DEEPSEEK_API_KEY" "$PY" - <<'PYEOF'
import os, re
p = ".env"; s = open(p, encoding="utf-8").read(); k = os.environ["KEY"]
s = re.sub(r"(?m)^DEEPSEEK_API_KEY=.*$", lambda m: "DEEPSEEK_API_KEY=" + k, s) if re.search(r"(?m)^DEEPSEEK_API_KEY=", s) else s + "\nDEEPSEEK_API_KEY=" + k + "\n"
open(p, "w", encoding="utf-8").write(s)
PYEOF
    export DEEPSEEK_API_KEY
  else
    say "缺少 DEEPSEEK_API_KEY：请写入 backend/.env 或 export 后重试"; exit 1
  fi
fi

# ---- 4. 初始化数据库（建表 + 幂等迁移）----
"$PY" -c "from verabot import db; db.init_db(); print('[VeraBot] 数据库就绪：', db.database.DB_PATH)"
[ "$MODE" = "--setup-only" ] && { say "安装完成（--setup-only，未启动服务）"; exit 0; }

# ---- 5. 启动 ----
HOST="${HOST:-0.0.0.0}"; PORT="${PORT:-8000}"
say "启动 http://$HOST:$PORT  （API 文档 /docs，健康检查 /api/health）"
if [ "$MODE" = "--detach" ]; then
  mkdir -p data
  # 新会话 (new session) 启动，关闭终端 / 父进程退出也不会带走服务（macOS 没有 setsid 命令）
  "$PY" - "$HOST" "$PORT" <<'PYEOF'
import subprocess, sys
log = open("data/server.log", "ab")
p = subprocess.Popen([".venv/bin/python", "-m", "uvicorn", "verabot.main:app", "--host", sys.argv[1], "--port", sys.argv[2]],
                     stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
open("data/server.pid", "w").write(str(p.pid))
PYEOF
  say "已在后台运行，PID $(cat data/server.pid)，日志 data/server.log"
  exit 0
fi
exec "$PY" -m uvicorn verabot.main:app --host "$HOST" --port "$PORT"
