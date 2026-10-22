# VeraBot Backend (后端) — v0.1.0

## Bot 能力默认全开（2026-10-22，schema v40）

新建 Bot 默认开启全部内置工具、接受委派、委派给账号内其他全部 Bot，并把已连接且已同意服务的 active MCP 工具（创建时快照，每 Bot 最多 20 个）加入白名单；存量 Bot 由 v40 迁移一次性回填。迁移前自动备份 `.bak-before-v40-<时间戳>`。显式传入权限仍可收窄；服务端强制、委派护栏与审计不变。见[任务记录](../docs/tasks/2026-10-22-bot-capabilities-default-on.md)。

## Bot 漂流瓶后台（2026-10-20，未发布工作区）

schema v39 新增 `/api/games/drift-bottle/*`：共享文字瓶、私有相遇、公开投稿、回忆卡、撤回/举报/屏蔽、幂等操作与生成锁。业务路由只做鉴权和错误映射，规则在 `services/drift_bottle/`，SQL 在 `db/drift_bottle_store.py`。模型只返回私人文字，不能发布或改变租约。

举报处理由受限 CLI `scripts/drift_bottle_admin.py` 执行，管理员名单来自 `VERABOT_DRIFT_BOTTLE_ADMINS`；详见[操作说明](../docs/tasks/2026-10-20-bot-drift-bottle-admin.md)。正式数据库已于 2026-10-20 备份并迁移 v39，Main API 已重启；回滚备份见任务记录。

## 个性化 Feed 后台（2026-10-17，未发布）

独立Feed模块及v36迁移位于personal-feed工作区；使用 `/api/feed/*` 管理关注计划、来源、阅读状态和引用草稿。先初始化明确指定的隔离数据库，再单独运行 `python -m verabot.services.feed`；worker不负责迁移，普通API启动沿用现有迁移行为，因此不要把未评审部署指向正式库。本机fake-IP DNS环境显式使用 `VERABOT_FEED_DOH=1`。

采集不需要模型密钥；本版采用公开RSS/Atom/媒体订阅和有权限的本地主题建议。运行、额度、来源限制及API见[Feed说明](verabot/services/feed/README.md)，测试与部署边界见[记录](../docs/testing/2026-10-17-personal-feed.md)。

2026-10-16：私聊、群聊请求的 `attachment_ids` 上限调整为 9，沿用现有上传、绑定、回执及账号隔离机制，无数据库迁移。iOS 相册多图直接发送，详见 [修改记录](../docs/tasks/2026-10-16-direct-multi-image-send.md)。

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
5. **数据库**：`init_db()` 建表与幂等迁移；当前源码含 **v40 Bot 能力默认全开**；最近迁移含 v37 统一事项、v38 俄罗斯方块、v39 漂流瓶、v40 能力默认全开。另有 v20 群聊、v23 定时任务、v27–v29 持续任务、v36 Feed 等。数据在 `data/verabot.db`。升级前先备份并在副本演练。用户事项 API：`/api/items`（见 `api/routers/items.py`）；旧 `/api/reminders` 保持兼容。
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

## Bot 群聊（schema v25，执行协议 v2）

群聊使用独立 `/api/groups` 存储与服务端持久 worker。普通输入按本群上下文分配一个负责人；信息不清时从相关成员中动态选择澄清 Bot，同一次澄清及后续回答复用同一负责人。Bot 可通过受校验的结构化动作咨询其他成员并返回原负责人，或将任务正式交给下一位。没有默认回应者；正文提名不会直接调度。

- `GET/POST /api/groups`、`GET/PATCH/DELETE /api/groups/{id}`：群管理；创建只包含 name、bot_ids。
- `GET/DELETE /api/groups/{id}/messages`：历史/清空；`GET .../messages/sync` 保持分页同步。
- `POST /api/groups/{id}/inputs`：提交 `client_request_id`、message、`target_member_ids`、everyone、reply_to_message_id、附件及可选澄清 task/version；重复 UUID 返回相同回执。
- `GET .../inputs/{client_request_id}`、`GET .../execution`：查询提交回执和当前任务/澄清快照。
- `GET .../events?after_id=N`：按游标重放持久 SSE 事件；断开观察不停止执行。
- `POST .../tasks/{task_id}/stop|resume`、`POST .../messages/{message_id}/retry-v2`：版本校验的停止/继续/失败步骤重试。

全部群写操作需 `X-VeraBot-Group-Protocol: 2`；旧 chat/retry/turn-stop 写入口返回 426，历史读取保持可用。meta 返回 `group_protocol_version=2`。群路由与步骤不读取私聊或长期记忆、不开放一般工具和群外动作；当前执行限制为每条输入最多 6 次模型调用、每步 60 秒、整条任务 240 秒。

**部署限制：** 首版 worker 托管在 API 进程内，生产应运行一个 API 进程；不支持多个 API 副本共享任务执行。数据库 lease 与 task version 用于恢复和 fencing；API 进程关闭会将已开始的步骤标记 interrupted，未开始步骤可恢复领取，用户可显式继续。未知用量保持 unknown，不记作零。按 v23→v25 迁移前先备份并在副本演练；尚无正式数据库迁移或真实模型验收记录。协议、测试和用户验收边界见 [群意图与任务交接实现记录](../docs/testing/2026-10-12-group-intent-and-handoff.md)。

### 群聊开发回归夹具（产品外）

`python scripts/dev/group_chat_demo.py --port 8093` 使用临时库与确定性模拟提供者，只监听127.0.0.1，不请求真实模型。服务启动后运行 `uv run python scripts/test/group_execution_http_test.py http://127.0.0.1:8093` 验证提交、澄清、咨询返回、交接、断开观察、事件重放及旧协议拒绝。此夹具仅用于开发回归，不是 App 功能或正式启动路径。

## Bot 无 key 联网查询

联网搜索通过匿名 Chromium 打开 Google 公开网页/新闻搜索；网站要求验证或暂时不可达时，使用 Bing 公开搜索备用。无需任何搜索 API key，也不读取用户浏览器 Cookie、账号或历史。网页来源以本轮实际结果为准，默认国内新闻优先、国际其次。

部署时运行 `uv sync --frozen`，再运行 `PLAYWRIGHT_SKIP_BROWSER_GC=1 uv run python -m playwright install chromium`；Linux 可用 `playwright install --with-deps chromium` 安装系统浏览器依赖。浏览器缓存应保留在服务运行账户可读的位置。不会在聊天请求中下载浏览器。

服务器 `VERABOT_WEB_ENABLED` 默认 1，可设 0 关闭；Bot 的 `web_search` / `web_read_result` 权限仍逐 Bot 开启。`VERABOT_WEB_DAILY_REQUESTS` 默认 50，是负载保护而非付费额度；每轮搜索2/读取3、累计45秒、单次搜索30秒（正文下载12秒）。缺浏览器、访问验证、超时、无结果均有明确状态。Google 返回验证时冷却5分钟，不重复触发同一个验证，不绕过验证码；Bing备用不支持一年时间范围，保留原错误而不丢弃过滤条件。

正文只读取本轮返回的公开 HTTPS 链接；DNS 全量检查并固定连接 IP，逐跳验证，TLS 保留原域名校验，不执行文章脚本；最多1MiB未压缩响应、4000字正文。

在系统 DNS 把所有解析结果映射到 `198.18.0.0/15` 的环境中，正文读取会对公开主机名改用固定 Google Public DNS over HTTPS 查询；回传的所有地址仍须为公网地址，随后固定目标 IP 并校验原域名 TLS。真实私网或公私混合 DNS 结果不会触发该回退，也不会访问非公开地址。

离线验证：`uv run python scripts/test/web_browser_test.py`、`uv run python scripts/test/web_query_test.py`。真实联网与离线验证结果分别记录在 [无 key 验收记录](../docs/testing/2026-10-11-web-query-no-key.md)。

## 会话同步与服务端定时任务（schema v23）

`GET /api/bots/{id}/messages/sync` 与 `GET /api/groups/{id}/messages/sync` 提供修订号固定的完整历史分页；冲突返回 `sync_revision_changed`。iOS 使用账号/服务器隔离的 SQLite 本地库先展示内容，再原子对账。

`/api/scheduled-tasks` 提供创建、查询、修改、暂停/恢复、删除、立即执行及历史。API 仅管理任务；后台由独立 `python -m verabot.services.scheduled_tasks` 执行，可用 `--once` 扫描一次。API 和后台必须共享 `VERABOT_DB`，后台启动前由 API 完成 v23 迁移。读工具权限、预算、租约与幂等在后端执行；没有新增 iOS 任务页面或 APNs。运行细节见 [服务说明](verabot/services/scheduled_tasks/README.md)，本轮证据见 [Main 集成交付](../docs/testing/2026-10-12-main-integration.md)。
