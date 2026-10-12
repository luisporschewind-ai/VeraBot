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
| `DEEPSEEK_MODEL` / `DEEPSEEK_BASE_URL` | `deepseek-flash` / `https://api.deepseek.com` | OpenAI 兼容端点 (2026-10-03 前默认 `deepseek-chat`，官方已停用) |
| `VERABOT_DEEPSEEK_THINKING` | `0` | 默认请求体带 `thinking: {"type":"disabled"}`；设 1 去掉该字段 (需先实现 `reasoning_content` 回传，否则带工具的请求 400) |
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
| `VERABOT_MAX_DELEGATION_MEMORY_IDS` / `_MEMORY_CHARS` / `_AUTO_MEMORIES` | `8` / `1200` / `5` | 委派记忆 ID 上限 / 共享正文总字数 / 自动附加目标 Bot 资料条数 |
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
| `VERABOT_MEMORY_VECTOR` / `_MODEL` / `_MIN_SIMILARITY` | `1` / `BAAI/bge-small-zh-v1.5` / `0.25` | 本地语义召回开关 / 模型 / 最低相似度；先运行 `uv sync --extra memory-vector`，首次召回会在 `data/models/memory` 缓存约 90 MB 模型；模型缺失或失败时退回关键词召回 |

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
├── db/              # database (连接 / 事务)、schema (迁移入口) + migrations/ (每版本一个模块)、repository 与 *_store (全部 SQL)
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
uv run python scripts/test/mcp_disable_race_test.py # MCP-RACE-01~08：后台同步与「停用」竞态，假 MCP 服务器阻塞 tools/list，确定性
uv run python scripts/test/sql_layer_check.py      # SQL-LAYER-01/02：db/ 以外不许有 execute( / SQL 语句字符串（AST 静态扫描，不连库）
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

### 俄罗斯方块陪玩

`POST /api/bots/{bot_id}/tetris-companion` 接收局面摘要和短对话，返回 `{text}`；采用现有登录鉴权、Bot 归属和每日 Token 预算。服务端调用模型，携带 Bot 人设，不执行工具、不持久化对话或记忆。输入验证、权限、预算和错误用例：`uv run python scripts/test/tetris_companion_test.py`。

## Bot 群聊（schema v20）

文字群聊使用独立 `/api/groups` 存储与接口。本人 2–4 个 Bot、最多 10 个群；群名 1–64、消息 1–2000 字符。成员共享本群文字，不读取私聊/长期记忆，不启用工具、附件或语音。

- `GET/POST /api/groups`：列表/创建（name、bot_ids、default_bot_id）。
- `GET/PATCH/DELETE /api/groups/{id}`：详情、名称/默认成员、删除。
- `GET/DELETE /api/groups/{id}/messages`：历史/清空；分页 before_id、limit 最大 100。
- `POST /api/groups/{id}/chat`：client_request_id UUID、message、mode single/round、可选 target_bot_id；群 SSE。
- `GET /api/groups/{id}/turns/{turn_id}` 与 `POST .../stop`：查询、持久化取消并停止执行。
- `POST /api/groups/{id}/messages/{message_id}/retry`：client_request_id UUID，重试原未完成成员。

同群只能一个 running 轮次。相同 UUID 返回 409 request_exists 与原 turn_id，内容冲突返回 idempotency_conflict；不要生成新 UUID 自动重发。查询原轮次快照恢复，不回放 delta。重试 turn_start 引用原问题的消息身份，事件 turn_id 为新轮次。

**当前仅支持单个后端进程/worker。** 模型执行绑定 SSE，请求断开即收尾；启动时遗留轮次变 interrupted，不自动续跑。多 worker 需另补租约与跨进程停止后才能使用。群调用最多 768 输出 tokens，单成员 60 秒、整轮 240 秒；预算检查沿用现有调用前策略，不做跨调用额度预占。

验证记录：[G2](../docs/testing/2026-10-11-bot-group-chat-g2.md)。代码实现与 mock 回归不代表生产部署或真实模型体验已验收。

### 群聊开发回归夹具（产品外）

`python scripts/dev/group_chat_demo.py --port 8093` 使用新临时库与确定性模拟提供者，只监听127.0.0.1，不请求真实模型；可用 `--data-dir` 指定独立测试目录。测试账号 group-demo / group-demo-123，已有A/B/C。服务启动后运行 `python scripts/test/group_http_test.py http://127.0.0.1:8093` 进行真实socket/SSE检查。此服务仅供开发自动回归，不是 App 功能或正式启动路径；正式群运行仍要求单worker。完整证据及人工步骤见 [G3](../docs/testing/2026-10-11-bot-group-chat.md)。

## Bot 无 key 联网查询

联网搜索通过匿名 Chromium 打开 Google 公开网页/新闻搜索；网站要求验证或暂时不可达时，使用 Bing 公开搜索备用。无需任何搜索 API key，也不读取用户浏览器 Cookie、账号或历史。网页来源以本轮实际结果为准，默认国内新闻优先、国际其次。

部署时运行 `uv sync --frozen`，再运行 `PLAYWRIGHT_SKIP_BROWSER_GC=1 uv run python -m playwright install chromium`；Linux 可用 `playwright install --with-deps chromium` 安装系统浏览器依赖。浏览器缓存应保留在服务运行账户可读的位置。不会在聊天请求中下载浏览器。

服务器 `VERABOT_WEB_ENABLED` 默认 1，可设 0 关闭；Bot 的 `web_search` / `web_read_result` 权限仍逐 Bot 开启。`VERABOT_WEB_DAILY_REQUESTS` 默认 50，是负载保护而非付费额度；每轮搜索2/读取3、累计45秒、单次搜索30秒（正文下载12秒）。缺浏览器、访问验证、超时、无结果均有明确状态。Google 返回验证时冷却5分钟，不重复触发同一个验证，不绕过验证码；Bing备用不支持一年时间范围，保留原错误而不丢弃过滤条件。

正文只读取本轮返回的公开 HTTPS 链接；DNS 全量检查并固定连接 IP，逐跳验证，TLS 保留原域名校验，不执行文章脚本；最多1MiB未压缩响应、4000字正文。

在系统 DNS 把所有解析结果映射到 `198.18.0.0/15` 的环境中，正文读取会对公开主机名改用固定 Google Public DNS over HTTPS 查询；回传的所有地址仍须为公网地址，随后固定目标 IP 并校验原域名 TLS。真实私网或公私混合 DNS 结果不会触发该回退，也不会访问非公开地址。

离线验证：`uv run python scripts/test/web_browser_test.py`、`uv run python scripts/test/web_query_test.py`。真实联网与离线验证结果分别记录在 [无 key 验收记录](../docs/testing/2026-10-11-web-query-no-key.md)。
