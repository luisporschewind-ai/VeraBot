# VeraBot 架构说明 (Architecture) — v0.1.0

## 1. 总览：两个可独立交付的项目

```
                      HTTP/JSON + SSE (JWT Bearer)
frontend/ios  (SwiftUI) ─┐
                         ├──────────────▶ backend (FastAPI · uvicorn :8000) ──▶ DeepSeek API (deepseek-chat)
frontend/web  (SPA)  ────┘                    │                             ├─▶ Open-Meteo (天气)
                                              ▼                             └─▶ OpenAI Audio (可选，语音转写)
                                     SQLite backend/data/verabot.db
```

| 项目 | 交付物 | 依赖管理 | 与另一方的关系 |
|---|---|---|---|
| `backend/` | 目录或 `dist/VeraBot-backend-v0.1.0.zip` (`start.command` / `start.sh` 一键启动；可选 Docker) | uv：`pyproject.toml` + `uv.lock` (+ `requirements.txt` 导出) | 只提供 HTTP API；可选托管 `frontend/web` 静态文件 (`VERABOT_WEB_DIR`) |
| `frontend/ios` | Xcode 工程 `VeraBot.xcodeproj` + 本地包 `Packages/VeraBotKit` | SPM (无第三方依赖) | 只通过 API 访问后端，服务器地址可在登录页配置 |
| `frontend/web` | 3 个静态文件 | 无 | 同源调用 `/api/*` |

规则：**前端不 import 后端代码，后端不依赖前端代码** (Web 目录不存在时 `/` 只返回 API 信息)。接口契约 = OpenAPI (`/docs`) + SSE 事件格式 (见 [FEATURES.md](../product/FEATURES.md#api-摘要))。

## 2. 后端 (backend/verabot)

### 2.1 模块

| 包 | 职责 | 主要文件 |
|---|---|---|
| `core` | 配置 (环境变量)、安全 (bcrypt + JWT)、记忆加密 (Fernet，密钥与数据库分离) | `config.py`、`security.py`、`crypto.py` |
| `db` | SQLite 连接 / 事务、建表与幂等迁移 (当前 schema v10：v1 → v2 → v3 → v4 → v5 → v6 → v7 MCP → v8 MCP 同意 / 同步 / 熔断 → v9 账号 → v10 插件安装表)、查询 | `database.py`、`schema.py`、`repository.py`、`plugin_store.py`、`mcp_store.py` |
| `tools` | 工具注册表 (`@tool`、schema 导出、安全执行；`Tool.kind` 区分 builtin / memory) 和内置工具 | `registry.py`、`weather.py`、`reminder.py` |
| `services` | 外部服务与业务逻辑：LLM 客户端、语音转写、Bot 权限校验、用量统计、用户资料、头像处理；长期记忆；MCP 客户端；插件安装层 | `llm.py`、`transcribe.py`、`bots.py`、`quota.py`、`users.py`、`avatars.py`、`memory/`、`mcp/`、`plugins/{catalog,service}.py` |
| `agents` | Agent Loop 与多 Agent：system prompt、权限、护栏、上下文隔离、`ask_bot` 委派 | `runtime.py`、`prompts.py`、`permissions.py`、`guardrails.py`、`context.py`、`delegation.py`、`memory_tools.py` (`remember` / `forget_memory`) |
| `api` | HTTP 层：鉴权依赖、pydantic 模型、路由 | `deps.py`、`schemas.py`、`routers/{auth,avatars,bots,chat,voice,reminders,meta,memories,mcp,plugins}.py` |
| `main.py` | 组装 FastAPI app：CORS、422 处理、启动 `init_db`、挂载路由、托管 Web | — |

### 2.2 依赖规则 (Dependency rules)

```
main ──▶ api ──▶ services ──▶ db ──▶ core
          │         ▲          ▲
          └──▶ agents ──▶ tools ┘
```

- 只允许**向下**依赖：`api → services / agents → tools / db → core`。`core` 不依赖任何内部包；`db` 只依赖 `core`。
- HTTP 细节 (FastAPI、`HTTPException`、pydantic 请求模型) 只出现在 `api/` 和 `main.py`。
- 模块通过包引用调用 (`from ..services import llm` → `llm.complete(...)`)，测试可以直接替换 (monkeypatch) 模块属性，例如 `multi_agent_test.py` 用 mock LLM 替换 `llm.stream_chat`。
- 两处**有意的例外** (工具自注册例外，都有注释)：
  1. `tools/__init__.py` 导入 `agents.delegation` 与 `agents.memory_tools`，让 `ask_bot`、`remember`、`forget_memory` 按顺序注册到工具表 (`get_weather`、`create_reminder`、`list_reminders`、`ask_bot`，之后是 `kind="memory"` 的记忆工具；记忆工具不进 `allowed_tools`，由 `bots.memory_access` 控制，详见 [MEMORY_GROWTH.md](MEMORY_GROWTH.md) §5.3)。
  2. `tools/registry.run_tool` 在函数内延迟导入 `agents.permissions.is_permitted` (执行前的二次权限检查)，避免循环导入。
- 新增工具：在 `tools/` 新建模块并用 `@tool` 注册，在 `tools/__init__.py` import；权限白名单 `ALL_TOOLS_V2` 在 `db/schema.py`。

### 2.3 一次对话的时序 (含多 Agent 委派)

```mermaid
sequenceDiagram
    participant U as 用户 (iOS / Web)
    participant S as api/routers/chat (SSE)
    participant A as agents/runtime.run_chat (Vera)
    participant L as services/llm → DeepSeek
    participant B as agents/delegation → run_once (小研)

    U->>S: POST /api/bots/7/chat (Bearer JWT)
    S->>S: 校验 Token 预算 (超额 429)
    S->>A: 最近 20 条历史 (仅该用户、该 Bot)
    A-->>U: event: status (phase recalling，开启记忆时)
    A->>L: messages + 有权限的工具 schema (stream)
    L-->>A: tool_calls: ask_bot(小研, question, shared_context)
    A-->>U: event: tool_start
    Note over A,B: 委派期间 B 的进度经队列转发为 event: status (phase thinking / tool，parent_id = 外层 tool_start.id)
    A->>B: guardrails.check_delegation → 只发 question + 限长 shared_context + 公开资料
    B->>L: 非流式 (全新会话，无历史)
    L-->>B: answer
    B-->>A: 结果 (写 delegations 审计记录)
    A-->>U: event: tool_result (交接 Trace 卡片)
    A->>L: 追加 tool 结果，继续流式
    A-->>U: event: delta … / done (usage)
    A->>S: 保存回复 + traces；usage_log 记账
```

### 2.4 数据模型

```mermaid
erDiagram
    users ||--o{ bots : owns
    users ||--o{ messages : owns
    bots ||--o{ messages : "chat history"
    users ||--o{ reminders : owns
    users ||--o{ delegations : owns
    users ||--o{ usage_log : "token usage"
    users ||--o{ audit_log : "security events"
    users ||--o{ avatars : "owns bytes"
    users ||--o{ memories : "long-term memory"
    bots ||--o{ memories : "bot / summary scope"
    bots ||--o| avatars : "optional photo"
    users { int id string username string password_hash string nickname string avatar_updated_at int token_budget int memory_enabled }
    bots { int id int user_id string name string avatar string color string persona string instructions json allowed_tools json delegate_to int accept_delegation string image_updated_at string memory_access json tags }
    avatars { int user_id int bot_id string content_type blob data string updated_at }
    messages { int id int user_id int bot_id string role string content json traces json memory_ids }
    memories { int id int user_id string scope int bot_id string type string content string content_enc string content_hash string status string sensitivity string action int target_id int use_count }
    reminders { int id int user_id int bot_id string content string due_at int done }
    delegations { int id int user_id int from_bot_id int to_bot_id string status string reason int depth json payload int total_tokens }
    usage_log { int id int user_id int bot_id string kind int prompt_tokens int completion_tokens int total_tokens }
    audit_log { int id int user_id int bot_id string kind string detail }
```

另有 `transcriptions` (Web 语音转写计数，用于用量看板) 和 `avatars` (用户 / Bot 的 512 JPEG)。`schema_meta` 记录 schema 版本；`init_db()` 建表并做幂等迁移 (v1 → v2 → v3 → v4 → v5)。v3 只加列和头像表，不改 v2 的权限回填。v4 新增 `memories` 表和 `bots.memory_access` (默认 `bot_and_global`)、`users.memory_enabled` (默认 1)、`messages.memory_ids` 三列，不写入任何记忆。v5 只给 `bots` 加 `tags` (JSON 数组，默认 `[]`)，不改权限、记忆或头像。详见下文「资料与头像」「Bot 标签」与 [MEMORY_GROWTH.md](MEMORY_GROWTH.md) §3。

## 3. iOS 客户端 (frontend/ios)

### 3.1 模块

```
VeraBot (App target, SwiftUI)                    Packages/VeraBotKit (本地 Swift Package)
├── App/        入口、AppState、AppConfig          ├── VeraBotCore        模型 (Codable)、SettingsKeys、  ← 无依赖
├── Core/UI/    Theme、CircleAvatar、BotAvatar、  │                      ListTimestamp、MessageMarkdown、HealthStatus、BotTags
│               MessageContentView、InAppBrowser、│
│               UserAvatar、AvatarPicker、       ├── VeraBotNetworking  VeraBotAPI 协议 + APIClient     → Core
│               LiveBotAvatar、DismissToolbarButton │                   （含头像 multipart / 字节下载）
│               Haptics、AvatarImage、BotTagViews │
├── Features/   Auth · BotList · BotInfo · Chat    └── VeraBotTTS         TTSEngine 协议 + SpeechPlayer  → Core
│               Settings (含 DebugView) · Reminders · Quota (由 设置 › 用量 push)
│               Memory (确认卡片、「Vera 了解的你」、编辑页、设置分组)
└── Services/   Keyboard、Speech (语音输入)、Avatar (AvatarStore)
```

依赖规则：

- `VeraBotCore` 不依赖其他模块、不含 UI；`VeraBotNetworking`、`VeraBotTTS` 只依赖 Core，二者互不依赖。
- App 依赖 Kit，Kit 不依赖 App。App 持有**协议**：`AppState.api: any VeraBotAPI`、`ChatViewModel` 通过 `VeraBotAPI` 访问网络，TTS 通过 `TTSEngine` 分派，便于注入 mock。
- Features 之间不直接互相引用状态，只通过 `AppState` (`@Observable`，`.environment` 注入) 和导航传参。
- 放进 Kit 的标准：与 SwiftUI 视图无关、可单元测试、可能被其他 target (Widget / 扩展) 复用。视图和交互留在 App。
- Swift 6 语言模式 + 严格并发 (`SWIFT_STRICT_CONCURRENCY = complete`)；Kit 的公开类型都是 `Sendable` 或 `@MainActor`。

### 3.2 工程

- `VeraBot.xcodeproj` 使用文件夹同步组 (PBXFileSystemSynchronizedRootGroup)：`VeraBot/` 下新增 / 移动文件无需改工程文件。
- 本地包通过 `XCLocalSwiftPackageReference (relativePath = Packages/VeraBotKit)` 引用，产品 VeraBotCore / VeraBotNetworking / VeraBotTTS 链接到 App target。
- `project.yml` 是等价的 xcodegen 描述 (备用)。

### 3.3 消息富文本 (Rich messages)

- 解析：`VeraBotCore/MessageMarkdown`（无 UI、可单测）。`blocks(_:)` 自写的行级解析 → `[MessageBlock]`（heading / paragraph / list / quote / code / table / rule）；`inline(_:)` 用 Foundation `AttributedString(markdown:, .inlineOnlyPreservingWhitespace)` 处理行内格式（先转义代码外的 `~`，BUG-01），再用 `NSDataDetector` 给网址 / 电话 / 邮箱加 `.link`（跳过已有链接与行内代码）；`links(in:)` 供长按菜单。不引入第三方 Markdown 库。
- 排版：`Core/UI/MessageContentView`（块 → 原生 Text / Grid / ScrollView，颜色取 Theme 的 `codeFill` / `quoteBar`），`MessageCopyMenu`（长按复制）。
- 链接路由：`Core/UI/InAppBrowser` 的 `.inAppBrowser()` 在对话页设置 `OpenURLAction`：`URL.opensInAppBrowser`（http/https，定义在 Core）→ `fullScreenCover` 里的 `SafariView`（`SFSafariViewController` 包装）；其他 scheme → `.systemAction`。视图只产出带 `.link` 的 AttributedString，不直接依赖浏览器实现。

### 3.4 主题 (Theme)

所有颜色与玻璃样式集中在 `Core/UI/Theme.swift`，视图只引用语义名，不写死颜色值：

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `Color.appBackground` | `#FFFFFF` | `#000000` | 页面背景 |
| `Color.sectionFill` | `#EFEFEE` (RGB 239, 239, 238；原为 `#F2F2F7`) | `secondarySystemBackground` (sheet 内 elevated) | 分组 Section、卡片、输入框底 |
| `Color.botBubble` / `traceFill` | = `sectionFill` | = `sectionFill` | Bot 回复气泡、工具 Trace |
| `Color.insetFill` | = `appBackground` | = `appBackground` | 卡片里再嵌一层的内容 |
| `Color.brandSoft` | `#E7EEF3` | `#1A3144` | 表情选中、交接 Trace (Vera `surface_elevated`) |
| `Color.brand` / `AccentColor` | `#3A7485` | `#548EA0` | 强调色 (`.tint`)：按钮文字、导航、置顶 (`pinTint`)、开关。Vera CLI 青绿 |
| `Color.brandFill` | `#3A7485` | `#3D7A8C` | 白字下面的实色底：用户消息气泡、默认头像 |
| `Color.brandText` | `#1A2B36` | `#D7E4EE` | 品牌文字：登录页「Vera Bot」、设置里的账号名 (Vera `text_primary`) |
| `Color.brandLight` / `brandDark` | `#548EA0` / `#2F6F82` | `#5B9BB0` / `#2F6F82` | 品牌辅助色 (引用竖条、用量进度条) |

品牌色来源 (2026-10-03 Boss 选定)：Vera CLI 默认「深海」主题 `~/Vera/src/vera/terminal/theme.py` —— `accent #3D7A8C` (VERA 点阵 Logo 主体)、`logo #548EA0` (扫光高光)、`text_primary #D7E4EE`。终端 256 色把它们显示成 `#5F8787` / `#5F87AF` / `#D7D7FF` (截图里的灰绿和淡紫)。浅色模式把 `#3D7A8C` 压暗为 `#3A7485` (白底 5.2:1、`#EFEFEE` 上 4.5:1)；深色模式文字 / 图标用 `#548EA0` (黑底 5.8:1)，白字实色底用 `#3D7A8C` (4.8:1)。Bot 自己的颜色选项 (`BotLook.colors`、后端默认 `#0F766E`) 是用户数据，不随主题改。
| `Color.codeFill` | = `insetFill` | = `insetFill` | 消息里的代码块 / 表格底 |
| `Color.quoteBar` | = `brandLight` | = `brandLight` | 消息里引用块左侧竖条 |

- 语义色是 `UIColor { trait in … }` 动态色，按 trait 解析；外观设置通过根视图 `preferredColorScheme` 改变 trait，所有页面同步更新。
- 容器：`ThemedForm` / `ThemedList`（`scrollContentBackground(.hidden)` + `appBackground`，行底 `listRowBackground(sectionFill)`，行内可再覆盖）；修饰符 `themedPageBackground()`、`plainListRow()`（首页平铺无分隔线）、`themedFieldBackground()`。
- Liquid Glass：`glassButtonStyle()` (`.glass`)、`prominentButtonStyle()` (`.glassProminent`)、`glassSurface(in:)` (`.glassEffect(.regular.interactive())`)、`GlassGroup` (`GlassEffectContainer`)；均以 `#available(iOS 26)` 判断，iOS 17–18 回退 bordered / `regularMaterial`。不加自定义动画。

## 4. 依赖管理选择 (Dependency management)

| | 选择 | 理由 | 不选 |
|---|---|---|---|
| iOS | **Swift Package Manager (SPM)** | Xcode 原生、无需额外工具和 `Podfile` / workspace；本地包可以把核心代码模块化，并用 `swift test` 在 Mac 上测试；以后加第三方包只需在 `Package.swift` 或 Xcode「Package Dependencies」里声明，版本记录在 `Package.resolved` | CocoaPods (额外 Ruby 工具链、修改工程文件、已进入维护模式)、Carthage |
| 后端 | **uv** (`pyproject.toml` + `uv.lock`) | 一个工具管理 Python 版本 + 虚拟环境 + 依赖；锁文件跨平台、`uv sync --frozen` 可复现；安装速度快；支持镜像 (`UV_INDEX_URL`、`UV_PYTHON_INSTALL_MIRROR`)，适合国内网络 | 仅 pip + requirements.txt (没有传递依赖锁、没有 Python 版本管理)、Poetry (更慢、交付时需要额外安装) |
| 后端回退 | `requirements.txt` (由 uv.lock 导出，版本全部锁定) | 没有 uv 或官方源不可用时，`start.sh` 用清华 tuna 镜像 `uv pip install -r requirements.txt`；也可以直接 `pip install -r` | — |
| 部署 (可选) | Dockerfile + docker-compose (`python:3.12-slim` + `uv sync --frozen`) | 服务器部署；数据目录挂载 `./data` | — |

当前版本锁定：Python 3.12；fastapi 0.142.1、uvicorn 0.54.0、httpx 0.28.1、pyjwt 2.15.1、bcrypt 5.0.0、python-multipart 0.0.32、pillow 11.3.0、cryptography 50.0.2 (共 48 个包，见 `uv.lock`)。iOS 无第三方依赖；工具链 Xcode 26.0.1 / Swift 6.2，部署目标 iOS 17.0。

## 5. 资料与头像 (Profile & avatars) — schema v3

启动时 `init_db()` 幂等执行。已有库从 v2 升到 v3 时**不会**重跑 v2 的「存量 Bot 授予全部工具」逻辑。

### 5.1 表

| 列 / 表 | 含义 |
|---|---|
| `users.nickname` | 可空。NULL 或空白 = 未设置，`display_name` 回退 `username` |
| `users.avatar_updated_at` | 可空。非空表示有自定义用户头像 |
| `bots.avatar` | 原有 emoji，不变 |
| `bots.image_updated_at` | 可空。非空表示该 Bot 有照片（API 字段名仍是 `has_avatar` / `avatar_updated_at`） |
| `avatars` | 主键 `(user_id, bot_id)`。`bot_id = 0` 是用户自己的头像；正数是 Bot id。`data` 为 JPEG BLOB，`content_type` 固定 `image/jpeg`。用户删除时随 `users` 级联；Bot 删除时由触发器 `avatars_delete_with_bot` 删掉对应行 |

公开 JSON（`services/users.public_user`、`services/bots.public_bot`）不包含 `password_hash` 和图片字节。图片只走下面的 GET。

### 5.2 HTTP

均需 Bearer JWT。用户头像没有 user id 路径，只能操作当前 token。Bot 头像先 `require_bot`（他人与不存在都是 404），再按 `user_id` 读写。

| 方法 | 路径 | 行为 |
|---|---|---|
| PATCH | `/api/me` | body `{nickname}`。`clean_nickname`：strip、非空、≤ 32 个字、拒绝控制字符。422 文案不带 pydantic 前缀 |
| POST | `/api/me/avatar`、`/api/bots/{id}/avatar` | `multipart/form-data`，字段名 `file`。不信任 Content-Type，只看文件头：JPEG / PNG / WebP；HEIC 能识别，未装 `pillow-heif` 时 415。大于 8MB → 413。解码失败 → 400。处理：EXIF 转正、居中裁正方形、512×512、JPEG quality 85。成功返回更新后的 user 或 bot |
| GET | 同上路径 | `image/jpeg`。没有自定义头像 → 404「未设置头像」，客户端显示首字或 emoji |
| DELETE | 同上路径 | 删 BLOB 并清空时间戳，返回更新后的 user 或 bot（Bot 的 emoji 还在） |

常量在 `services/avatars.py`：`MAX_AVATAR_BYTES = 8 MiB`，`AVATAR_SIZE = 512`。不新增环境变量。

iOS 在上传前用 `AvatarImage.jpegData` 把照片收成边长 1024 的 JPEG（相册里的 HEIC 由系统 `UIImage` 解码后再编码）。圆形预览用系统 sheet，显示区域与服务端中心裁切一致。昵称和用户头像放在 `AppState`；Bot 照片放在 `AvatarStore`。设置页保存后，首页工具栏和对话里的用户昵称读的是同一份 `displayName`，不会各刷各的接口。

## 5.3 Bot 标签 (Tags) — schema v5

`bots.tags` 是 JSON 文本列，默认 `[]`。`init_db()` 用已有的 `_add_column` 幂等添加；已有行得到 `[]`，再次启动不覆盖后来写入的标签，也不改 `allowed_tools` / `memory_access` / 头像。

公开 Bot JSON（列表、详情、创建、更新）都带 `tags: string[]`。创建时省略为 `[]`；更新时省略表示不改，传 `[]` 清空。`services/bots.public_bot` 把解析后的数组放进响应；库里仍是 JSON 字符串。

校验在 `api/schemas.py::clean_tags`（422，中文，去掉 pydantic 前缀）：

| 规则 | 行为 |
|---|---|
| trim | 去掉首尾空白（含全角空格） |
| 空白项 | 丢掉，不报错 |
| 重复 | 丢掉，保留第一次出现的顺序 |
| 个数 | 清洗后最多 3 个，否则「每个 Bot 最多 3 个标签」 (2026-10-01 由 5 改为 3) |
| 长度 | 每个最多 4 个 Unicode 码位，否则「每个标签最多 4 个字」 (由 12 改为 4) |
| 控制字符 | Unicode 类别 `Cc`（含换行、DEL），「标签不能包含控制字符」 |
| 类型 | 不是数组 →「标签必须是列表」；元素不是字符串 →「标签必须是文字」 |

上限定义在 `core/tags.py` (`MAX_BOT_TAGS` / `MAX_TAG_CHARS`)。存量超限数据由 `coerce_stored_tags` 收敛 (去控制字符、trim、截到 4 字、去重、留前 3 个)：`init_db()` 每次启动幂等改写，`db/repository._bot` 读取时也收敛。

读写仍走现有 Bot 接口，查询带 `user_id`；他人的 Bot 返回 404，不会改到别人的标签。标签不进入 system prompt，也不参与记忆。

iOS：`VeraBotCore/BotTags.swift` 的 `BotTagRules` 与上面同一套规则（字数按 Unicode scalar，与 Python `len` 对齐），另有 `parse` (按「,」「，」「、」与空白拆分) 和 `display` (「a, b, c」)。`Bot.tags` 在字段缺失或 JSON null 时解码为 `[]`。展示用 `Core/UI/BotTagViews.swift`：首页行名称后的 `BotTagChip` (一个 `Color.sectionFill` 圆角 5 的矩形，「搜索, 查询, 调研」，`.caption` 次要字，单行尾部截断，无 `+N`)；Bot 详情卡片名称下方一行文字；对话标题不显示标签。创建页用 `BotTagsField` (一行原生 TextField，输入时即时校验)；Bot 详情点卡片标签行弹出系统 alert 修改，经 `VeraBotCore/BotProfileDraft.swift` 暂存 (昵称 / 标签 / 照片的待保存改动，点「保存」才依次 `PATCH /api/bots/{id}` 与 `POST`/`DELETE /api/bots/{id}/avatar`)。无自定义动画。

## 6. 关键设计决策

| 主题 | 决策 | 理由 |
|---|---|---|
| 模型接入 | 服务端统一持有 `DEEPSEEK_API_KEY`，OpenAI 兼容协议 | 用户零配置；可切换其他 OpenAI 兼容模型 |
| 租户隔离 | 每条 SQL 带 `user_id`；他人资源返回 404 | 简单可审计，防枚举 |
| 记忆隔离 | 历史按 `(user_id, bot_id)` 存取；当前只有滑动窗口 (最近 `VERABOT_HISTORY_WINDOW`=20 条)，另有经用户确认的长期记忆 (M1 已实现：`memories` 表，按 `memory_access` 注入 depth 0 的 prompt，被委派方不读写；摘要等见 [MEMORY_GROWTH.md](MEMORY_GROWTH.md) M2+) | Bot 之间人格与上下文互不串扰 |
| 多 Agent | Agent-as-a-Tool (`ask_bot`)，最小权限 + 服务端强制 + 上下文隔离 + 护栏 + 审计 | 可控、可观测；详见 MULTI_AGENT_DESIGN |
| 工具轮次 | 每轮最多 4 轮工具调用 (`VERABOT_MAX_TOOL_ROUNDS`) | 防止工具循环 |
| 流式协议 | SSE (`event:` + `data:` JSON) | 浏览器 `fetch` 与 iOS `URLSession.bytes` 都能直接解析 |
| 语音输入 | Web 走服务端转写，iOS 走系统 Speech；结果只填入输入框 | 用户确认后再发送，避免误发 |
| 存储 | SQLite (WAL) | 原型零运维；表结构可平移到 PostgreSQL |
