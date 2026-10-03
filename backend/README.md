# VeraBot Backend (后端) — v0.1.0

FastAPI + SQLite 的 VeraBot 服务端：账号、Bot 管理、SSE 流式对话、工具调用、多 Agent 委派、用量统计。
可以独立交付：本目录 (或打包出的 `VeraBot-backend-v0.1.0.zip`) 自带依赖锁、配置模板和一键启动脚本。

## 1. 一键启动 (One-click start)

| 方式 | 操作 |
|---|---|
| macOS 双击 | Finder 中双击 `start.command` (打开终端窗口运行，关闭窗口即停止) |
| 终端前台 | `./start.sh` |
| 终端后台 | `./start.sh --detach` (日志 `data/server.log`，PID `data/server.pid`)；停止：`./stop.sh` |
| 只安装不启动 | `./start.sh --setup-only` |
| Docker (可选) | `cp .env.example .env` 填 Key → `docker compose up -d --build` |

`start.sh` 依次执行：

1. **uv**：没有则用官方脚本安装 (`~/.local/bin/uv`)；失败时用 PyPI 镜像 `pip install uv`。
2. **Python**：按 `.python-version` (3.12) 由 uv 安装；失败时用 npmmirror 镜像 (`UV_PYTHON_INSTALL_MIRROR`)。
3. **依赖**：`uv sync --frozen --no-dev`，严格按 `uv.lock` 安装到 `.venv/`；失败 (或 `VERABOT_FORCE_MIRROR=1`) 时改用清华 tuna 镜像 (`UV_INDEX_URL`，可用 `VERABOT_PYPI_MIRROR` 覆盖) 按 `requirements.txt` (同样锁定版本) 安装。
4. **配置**：没有 `.env` 就从 `.env.example` 复制，并提示输入 DeepSeek Key (不回显，写入 `.env`，权限 600)。已 export 的环境变量优先于 `.env`。
5. **数据库**：`init_db()` 建表 + 幂等迁移 (当前 schema v8：v3 昵称与头像、v4 长期记忆、v5 Bot 标签、v6 Bot 置顶、v7 MCP 表、v8 MCP 同意 / 同步状态 / 熔断)，数据在 `data/verabot.db`。已有库会在下次启动时自动升级，不用手写 SQL。v7 / v8 不改已有 Bot 的工具白名单。
6. **启动** uvicorn，默认 `0.0.0.0:8000` (`HOST` / `PORT` 可改)。

启动后：API 文档 <http://127.0.0.1:8000/docs>，健康检查 `GET /api/health` → `{"ok":true,...}`。
如果旁边有 `../frontend/web` (或设置了 `VERABOT_WEB_DIR`)，`/` 会托管 Web SPA；否则 `/` 返回 API 信息 JSON。

## 2. 配置 (Configuration)

所有配置都是环境变量，模板见 [`.env.example`](.env.example) (不含任何密钥)。常用项：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DEEPSEEK_API_KEY` | — (必填) | DeepSeek Key，只在服务端读取 |
| `DEEPSEEK_MODEL` / `DEEPSEEK_BASE_URL` | `deepseek-chat` / `https://api.deepseek.com` | OpenAI 兼容端点 |
| `OPENAI_API_KEY` | — | 可选，Web 语音转写 `/api/transcribe` |
| `HOST` / `PORT` | `0.0.0.0` / `8000` | 监听地址 |
| `VERABOT_DATA_DIR` / `VERABOT_DB` | `backend/data` / `data/verabot.db` | 数据目录 / 数据库路径 |
| `VERABOT_JWT_SECRET` | 自动生成到 `data/.jwt_secret` | JWT 签名密钥 (也用于刷新令牌 / 验证码的 HMAC) |
| `VERABOT_TOKEN_TTL_HOURS` / `VERABOT_REFRESH_TTL_DAYS` | `168` / `60` | 访问令牌 7 天 / 刷新令牌 60 天 |
| `VERABOT_MAIL_BACKEND` | `console` | `console` 把验证码写进 `data/server.log`；`smtp` 用 `VERABOT_SMTP_HOST/PORT/USER/PASSWORD/FROM/STARTTLS/SSL/TIMEOUT` 发信 (见 [AUTH_REFACTOR.md](../docs/design/AUTH_REFACTOR.md) §6) |
| `VERABOT_AUTH_CODE_TTL` / `_COOLDOWN` / `_DAILY` / `VERABOT_AUTH_IP_LIMIT` | `600` / `60` / `10` / `30` | 验证码有效期、发码间隔、每日次数；IP 限流 |
| `MAX_BOTS_PER_USER` | `20` | Bot 数量软上限 (兼容旧名 `VERABOT_MAX_BOTS`) |
| `VERABOT_DAILY_TOKEN_QUOTA` | `200000` | 每用户每日 Token 预算，超额 429 |
| `VERABOT_MAX_DELEGATION_DEPTH` / `_MAX_DELEGATIONS_PER_TURN` / `_MAX_SHARED_CONTEXT` | `1` / `3` / `2000` | 多 Agent 护栏 |
| `VERABOT_HISTORY_WINDOW` / `VERABOT_MAX_TOOL_ROUNDS` | `20` / `4` | 记忆窗口 / 单轮工具轮数 |
| `VERABOT_TZ` | `Asia/Shanghai` | 提醒 / 统计时区 |
| `VERABOT_WEB_DIR` | `../frontend/web` | Web 客户端目录 |
| `VERABOT_LOCAL_STT` / `_MODEL` | `1` / `small` | 安装 `local-stt` 额外依赖后，本地 faster-whisper 回退 |
| `VERABOT_MEMORY` | `1` | 长期记忆总开关 (服务器级)；`0` 时不召回、不暴露记忆工具，接口仍可查看 / 删除 |
| `VERABOT_MEMORY_ENC_KEY` | 自动生成到 `data/.memory_key` (权限 600) | 健康 / 财务记忆的 Fernet 密钥；逗号分隔多把用于轮换 (第一把加密)。与数据库分开备份 |
| `VERABOT_MCP_LEARN_URL` / `VERABOT_MCP_LEARN_ENABLED` | `https://learn.microsoft.com/api/mcp` / `1` | Microsoft Learn MCP。默认开启，打开列表时在后台同步 |
| `VERABOT_MCP_AWS_URL` / `VERABOT_MCP_AWS_ENABLED` | `https://knowledge-mcp.global.api.aws` / `0` | AWS Knowledge MCP。默认关闭，不访问网络 |
| `VERABOT_MCP_PROTOCOL_VERSION` / `VERABOT_MCP_TIMEOUT` | `2025-06-18` / `15` | 请求的协议版本（单次 HTTP 超时，秒，建议 10–15） |
| `VERABOT_MCP_RETRY_MAX` / `VERABOT_MCP_RETRY_BACKOFF` | `2` / `0.5,2` | 可重试错误的额外次数 / 退避秒数（另加最多 25% 抖动） |
| `VERABOT_MCP_BREAKER_THRESHOLD` / `VERABOT_MCP_BREAKER_COOLDOWN` | `5` / `60` | 连续传输失败多少次打开熔断 / 冷却秒数 |
| `VERABOT_MCP_CALLS_PER_TURN` / `VERABOT_MCP_MAX_RESULT_CHARS` / `VERABOT_MCP_MAX_TOOLS_PER_SERVER` | `8` / `8000` / `50` | 单轮调用上限 / 结果截断 / 每服务工具上限 |
| `VERABOT_MEMORY_MAX_ACTIVE` / `_MAX_CHARS` / `_INJECT_MAX` / `_INJECT_CHARS` | `200` / `200` / `12` / `1000` | 每用户生效记忆上限 / 单条字数 / 每轮注入条数 / 每轮注入字数 |

## 3. 依赖管理 (uv)

- `pyproject.toml`：直接依赖 (精确版本 `==`) + `[tool.uv] constraint-dependencies` 锁住传递依赖；`package = false` (应用，不发布到 PyPI)。
- `uv.lock`：完整锁文件 (61 个包，含 Pillow 11.3.0 与 `mcp==2.2.0`)，`uv sync --frozen` 严格按它安装。
- `requirements.txt`：由 `uv export --frozen --no-hashes --no-dev --no-emit-project --no-header -o requirements.txt` 导出 (再补上两行注释头)，供没有 uv 的环境 `pip install -r` 使用。
- 可选本地语音转写：`uv sync --extra local-stt` (或 `pip install -r requirements-optional.txt`)。
- 升级依赖：修改 `pyproject.toml` → `uv lock` → 按上面的命令重新导出 `requirements.txt` → 跑测试 → 同一个 commit 提交三个文件。

## 4. 代码结构 (Package `verabot`)

```
verabot/
├── main.py          # FastAPI app：CORS、422 处理、启动时 init_db、挂载路由、托管 Web
├── core/            # config (环境变量)、security (bcrypt + JWT)
├── db/              # database (连接 / 事务)、schema (建表 + 迁移)、repository (查询)
├── api/             # deps (鉴权依赖)、schemas (pydantic)、routers/ (auth, avatars, bots, chat, voice, reminders, meta, mcp, plugins)
├── services/        # llm、transcribe、bots (权限校验)、quota、users (昵称)、avatars (裁切与存储)、mcp (目录与 HTTP 客户端)、plugins (安装层)
├── agents/          # runtime (Agent Loop)、prompts、permissions、guardrails、context、delegation (ask_bot)
└── tools/           # registry (@tool 注册表)、weather、reminder
```

依赖方向：`api → services / agents → tools / db → core`，详见 [docs/design/ARCHITECTURE.md](../docs/design/ARCHITECTURE.md)。
新增工具：在 `verabot/tools/` 新建模块，用 `@tool(...)` 注册，并在 `verabot/tools/__init__.py` 中 import。

## 5. 测试 (Tests)

```bash
uv run python scripts/test/multi_agent_test.py   # mock LLM + 临时 DB，确定性，MA-01~25 (25/25，MA-25 为 /api/quota 前后端契约)
uv run python scripts/test/avatar_profile_test.py # 头像 / 昵称 / 迁移 / 隔离，AV-* + NK-* (21/21)，不调用 LLM
uv run python scripts/test/memory_test.py        # 长期记忆 MEM-01~36 (36/36)，mock LLM + 临时 DB
uv run python scripts/test/mcp_test.py           # MCP：本地假服务器。公网用例默认跳过，VERABOT_MCP_LIVE_TESTS=1 才跑
uv run python scripts/test/plugin_test.py        # 插件 P1：迁移、安装 / 卸载、派生状态、契约。进程内假 MCP，不访问外网
uv run python scripts/test/smoke_test.py         # 端到端 (真实 LLM，需后端运行在 :8000)；结束后清理测试账号
uv run python scripts/test/api_regress.py        # 真实 LLM 回归 REG-*（创建临时用户 qa_reg_*）
uv run python scripts/test/api_regress2.py       # 续跑（预算 / 软上限 / 422），结束时删除临时用户
uv run python scripts/test/api_v01_tc*.py        # v0.1 API 用例 (TC-*)
uv run python scripts/dev/seed_demo.py --reset   # 重建演示账号 demo / verabot2026 (Vera / 小研 / 阿厨)
```

测试脚本默认连接 `http://127.0.0.1:8000`、读取 `data/verabot.db` (可用 `VERABOT_DB` 覆盖)；结果写到 `scripts/test/results/` (已 gitignore)。

## 6. API 摘要

见 [docs/product/FEATURES.md](../docs/product/FEATURES.md#api-摘要)，或启动后访问 `/docs` (OpenAPI)。

## 7. 许可证 (License)

[MIT License](../LICENSE)，Copyright (c) 2026 Luis Porsche。打包的 `VeraBot-backend-v*.zip` 内附 `LICENSE`。
