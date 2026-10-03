# 插件能力设计（Plugin Capability Design）— v1.0

> 状态：**v1.0 定稿**。Q4、Q6、Q7 已由产品负责人拍板（2026-10-03）；其中 **Q6 与 v0.2 建议不同**（新账号不预装任何插件）。其余决定沿用 v0.2 的默认值。P1 与本文同一提交实现。
> 撰写：Sonic；审查：Veronica；定稿：产品负责人决定写入 v1.0。
> 依据代码：`luisporschewind-ai/VeraBot` `main` 分支 `502e11e`（2026-10-03）。schema 取合并时下一个可用版本，当时 `SCHEMA_VERSION = 9`，P1 使用 **v10**。
> 相关文档：[MCP_CAPABILITY.md](MCP_CAPABILITY.md)（v1.0 已批准，M1 / M2 已实现；本文不修改其 §16 决定 D1–D10；进度记在 §18.4）、[GMAIL_CAPABILITY.md](GMAIL_CAPABILITY.md)、[ARCHITECTURE.md](ARCHITECTURE.md)、[AUTH_REFACTOR.md](AUTH_REFACTOR.md)（占用 schema v9）。

## 修订记录（Changelog）

### v0.2 → v1.0（2026-10-03，产品负责人拍板 Q4 / Q6 / Q7）

1. **Q4 采纳**：插件页两组为「内置」和「外部」。内置组展示天气、提醒；不可卸载、无需同意。某个 Bot 能否使用它们仍在该 Bot 的「工具权限」；插件页按 §6.2 `BuiltinPluginDetailView` 导航过去。PLG-11 / PLG-UI-08 适用。
2. **Q6 与 v0.2 建议不同**：新账号**不预装任何插件**。`default_installed()` 对每个插件（含 Microsoft Learn）都返回假。老用户迁移：用过的插件（已同意、已同步，或任一 Bot 白名单含 `mcp__{slug}__`）记为已安装；没用过的记为未安装，**迁移不写 `uninstalled` 墓碑**。演示账号的 Learn 若已同意，迁移后仍是已安装。PLG-04 改为「新用户已安装列表为空，且 GET 不在请求内联网」。新增老用户迁移用例（用过 → 已安装，没用过 → 未安装）。§4.2 与 PLG-02b 按此重写，避免 v0.1 那种墓碑挡住以后的预装。
3. **Q7 采纳**：卸载清除同意记录，并从所有 Bot 与工具缓存移除该插件的工具。iOS 卸载前弹出确认。重装必须重新同意，并按 Bot 重新开启。
4. 插件页分组文案由「已安装 + 内置」改为「内置 + 外部」（覆盖 §6.2 原稿）。

### v0.1 → v0.2（2026-10-03，依据 Veronica 审查意见）

1. **迁移缺陷修复**：v0.1 的第二条 `INSERT` 会把「默认预装但从未使用」的 Microsoft Learn 行记为 `uninstalled`，形成墓碑（tombstone），导致 Q6 的自动预装永远不会触发。改为：`default_installed` 为真的插件**一律迁移为已安装**；只有默认不安装的插件（AWS Knowledge）才按「是否用过」判断（§4.2）。新增用例 PLG-02b。
2. **安装返回码统一**：首次安装（含卸载后重装）返回 **201**；已安装返回 **409**（§5.2、PLG-05、PLG-08）。
3. **卸载与进行中调用的并发**：明确连接池关闭、进行中调用返回 `plugin_uninstalled`、Trace 文案、后台同步中止；新增用例 PLG-14、PLG-15（§4.4）。
4. **与账号隔离修复对齐**：所有 `/api/*` 响应带 `Cache-Control: no-store`，iOS 使用不缓存的 `URLSession`；插件接口遵循同一规则，PLG-12 增加该断言。schema 版本写作「取合并时下一个可用版本，目前预计 v10」，避免与隔离修复冲突（§4、§5.6）。
5. **内置插件的开关位置**：天气、提醒在插件页只读；详情页增加说明文字和前往「Bot 详情 › 工具权限」的导航路径（§6.2、PLG-UI-08）。
6. **细节**：Q13 改为「内置」单独成组，不作为分类；附录 A 增加 `backend/README.md` 与 `MCP_CAPABILITY.md` §18 字段对照表。
7. **决定状态**：Q4、Q6、Q7 标为「待 Boss 拍板」，其余按默认值标为「已决定」。

---

## 0. 摘要（TL;DR）

| 项 | 建议 |
|---|---|
| 定位 | 插件（Plugin）是面向用户的**产品层概念**；MCP 是插件的一种**能力实现（capability）**。现有 MCP 客户端、同意、审计、同步、重试与熔断全部保留，只在其上增加一层插件模型与统一入口 |
| 用户可见变化 | 设置页的「连接的账号 / MCP 服务」分组替换为一行「插件」入口，进入后为：已安装插件 → 插件详情；「浏览插件」进入精选目录（Plugin Catalog）。用户界面不再出现「MCP」字样 |
| 数据模型 | 新增 `user_plugins` 表只记录「安装关系」；`mcp_servers` 增加 `plugin_id` 列关联。启用、同意（D4）、同步、熔断字段**继续留在 `mcp_servers`**，保持单一事实来源（single source of truth） |
| schema 版本 | **v10**（合并时 main 仍是 v9；若合并前 main 再占用版本号则顺延）。下文的「v10」指这次实际使用的版本 |
| API | 新增 `/api/plugins/*`（目录、已安装列表、安装 / 卸载、启用 / 停用、同意、工具、同步）；`/api/mcp/*` 在 P1、P2 期间**保持原样可用**，文档标注为「已弃用（Deprecated）」，最早在 P3 之后移除 |
| 分期 | **P1** 收敛与入口（仅内置精选目录、仅免授权插件，单个 PR）→ **P2** 需授权插件（API Key / OAuth，复用 `mcp_credentials`、`oauth_states`，危险操作走 `pending_actions` 确认）→ **P3** 插件绑定到 Bot + 技能说明（Skill） |
| 不做 | 第三方开发者上架、用户自定义插件 URL、stdio 插件（沿用 D3：仅内置目录与运维配置） |

---

## 1. 现状盘点（As-is，基于 `502e11e`）

### 1.1 后端

| 模块 | 现状 | 对插件化的影响 |
|---|---|---|
| `backend/verabot/services/mcp/catalog.py` | 代码内置两条目录：`microsoft_learn`（slug `learn`，默认开启）、`aws_knowledge`（slug `aws`，默认关闭）；地址与开关来自 `VERABOT_MCP_LEARN_URL / _ENABLED`、`VERABOT_MCP_AWS_URL / _ENABLED`；`_LABELS` 提供工具中文名 | 插件目录的「能力」可直接引用这里的 `catalog_id`，不需要改动这份目录 |
| `backend/verabot/services/mcp/service.py` | `ensure_servers()` 在每次 `GET /api/mcp/servers` 时**按目录为用户补齐所有条目**（默认关闭的条目以 `status='disabled'` 入库）；`set_enabled()`、`set_consent()`、`remove_server()`、`sync_server()` / `schedule_sync()`、`connected_tool_rows()`、`invoke()`、`circuit_state()`、`public_server()` / `public_tool()` | **关键问题**：`remove_server()` 删除行后，下一次 `ensure_servers()` 会把它重新插回来，所以当前不存在真正的「卸载」语义。插件化必须让「补齐」改为「仅为已安装插件补齐」 |
| `backend/verabot/db/mcp_store.py` | `mcp_servers` / `mcp_tools` 的全部查询，均带 `user_id`；`strip_slug_from_bots()` 从所有 Bot 的 `allowed_tools` 中去掉 `mcp__{slug}__*` | 卸载流程直接复用 |
| `backend/verabot/api/routers/mcp.py` | `GET /api/mcp/catalog`、`GET/POST /api/mcp/servers`、`PATCH/DELETE /api/mcp/servers/{id}`、`POST /api/mcp/servers/{id}/consent`、`POST /api/mcp/servers/{id}/sync`、`GET /api/mcp/servers/{id}/tools`、`POST /api/mcp/tools/{id}/accept-change` | 保留；新路由作为其上的薄封装 |
| `backend/verabot/agents/tool_router.py` | `schemas_for()` 合并内置工具与「已连接 + 已同意 + 熔断未打开 + 在 Bot 白名单内」的 MCP 工具；`_call_mcp()` 依次检查 `unknown_tool` → `tool_not_allowed` → `not_delegable` → `not_connected` → `tool_changed` / `tool_removed` → `turn_cap` → `needs_confirmation` | P1 **不改**权限判定顺序与命名空间 `mcp__{slug}__{tool}` |
| `backend/verabot/api/routers/meta.py` | `GET /api/tools` 返回内置工具（`source="builtin"`）与已连接 MCP 工具（`source="mcp"`、`server`、`server_id`、`risk` 等） | P1 仅追加可选字段 `plugin_id` |
| `backend/verabot/tools/registry.py`、`tools/__init__.py` | 进程级 `REGISTRY`：`get_weather`、`create_reminder`、`list_reminders`、`ask_bot`，以及 `kind="memory"` 的 `remember` / `forget_memory`；内置工具名禁止以 `mcp__` 开头 | 内置工具能否呈现为「内置插件」见 §3.3 |
| `backend/verabot/db/schema.py` | `MCP_SCHEMA`（v7）：`mcp_servers`、`mcp_credentials`、`mcp_tools`、`oauth_states`、`pending_actions`；v8 通过 `_add_column` 补 `consent_at`、`sync_status`、`circuit_failures`、`circuit_open_until`；v9 为账号体系；`SCHEMA_VERSION = 9` | 插件迁移取合并时下一个可用版本（预计 v10），沿用 `_add_column` + `CREATE TABLE IF NOT EXISTS` 的幂等写法 |
| `audit_log` | 已有 `mcp_server_added` / `mcp_server_removed` / `mcp_server_disabled`、`mcp_consent_granted` / `mcp_consent_revoked`、`mcp_tool_call`、`mcp_tool_change_accepted`、`tool_denied` | 全部保留；新增 `plugin_installed` / `plugin_uninstalled` |

### 1.2 iOS

| 文件 | 现状 |
|---|---|
| `frontend/ios/VeraBot/Features/Settings/SettingsView.swift` | 分组顺序：`AccountSettingsSection` → `UsageSettingsSection` → `MemorySettingsSection` → **`MCPServicesSection`** → `GeneralSettingsSection` → `VoiceSettingsSection` → `AboutSettingsSection` → `SignOutSettingsSection` |
| `frontend/ios/VeraBot/Features/MCP/MCPSettings.swift` | `MCPServicesSection`（服务列表，轮询 `sync_status` 最多 20 次）与 `MCPServerDetailView`（状态 / 同步 / 熔断、启用开关、刷新工具、D4 同意开关与时间、「应用到 Bot」选择器 + 工具开关 +「开启全部只读」） |
| `frontend/ios/VeraBot/Features/BotInfo/BotEditView.swift` | 「工具权限」分组（内置工具）与「MCP 服务」分组（按服务列出工具开关），数据来自 `mcpServers()` + `mcpTools(serverID:)` |
| `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/MCP.swift` | `MCPCatalogItem`、`MCPServer`、`MCPTool`、`MCPSyncResult`、`MCPTraceText`（对话 Trace 标题与错误文案）、`MCPToolRules`（每 Bot 最多 20 个、`addingReadOnly`） |
| `frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient.swift`、`VeraBotAPI.swift` | `mcpCatalog()`、`mcpServers()`、`addMCPServer`、`updateMCPServer`、`setMCPConsent`、`deleteMCPServer`、`syncMCPServer`、`mcpTools` |
| `frontend/ios/VeraBot.xcodeproj/project.pbxproj` | 使用 `PBXFileSystemSynchronizedRootGroup`：新增 Swift 文件**无需修改 pbxproj**，与「不提交本地签名改动」的规则相容 |

### 1.3 测试与文档

- `backend/scripts/test/mcp_test.py`：MCP-01~08、MCP-25、MCP-CONSENT / SESSION / AUDIT / SYNC / RETRY / BREAKER、MCP-CONTRACT（`_keys()` 解析 iOS `CodingKeys`，校验其为后端 JSON 键的子集）、MCP-LIVE-*（需 `VERABOT_MCP_LIVE_TESTS=1`）。
- `frontend/ios/Packages/VeraBotKit/Tests/VeraBotKitTests/MCPTests.swift`。
- 字段对照：`docs/design/MCP_CAPABILITY.md` §18.2、§18.3。
- 术语冲突：`docs/design/ARCHITECTURE.md` §2.2 与 `tools/__init__.py` 注释中已有「插件注册」一词（指 `ask_bot` / 记忆工具的自注册例外），与本文的「插件」含义不同，需在 P1 中改称（见 §8 Q10）。

---

## 2. 目标与范围（Goals & Scope）

### 2.1 目标

1. 以「插件（Plugin）」作为用户理解与管理外部能力的唯一入口；「MCP」降为实现细节，不出现在面向用户的界面上。
2. 为后续需授权插件（Gmail、日历等）和「插件绑定到 Bot」建立稳定的数据模型与 API，避免日后再次迁移。
3. 不削弱 M1 / M2 已经落地的安全规则：D4 按服务同意、默认关闭、委派禁用（D6）、污染标记（taint）、审计不存外部原文、重试与熔断。
4. 提供真正的「安装 / 卸载」语义，修复 `ensure_servers()` 在删除后自动回填的问题。

### 2.2 用户可见变化（P1）

| 现在 | P1 之后 |
|---|---|
| 设置 › 「连接的账号 / MCP 服务」分组，直接列出 Microsoft Learn、AWS Knowledge | 设置 › 一行「插件」（右侧显示「已安装 N 个」），点入后为插件页 |
| 所有目录条目自动出现在列表中（AWS 以「已停用」出现） | 「已安装」只显示用户安装过的插件；未安装的在「浏览插件」中显示「安装」按钮 |
| 删除服务后会被自动补回 | 卸载后保持未安装，直到用户再次安装 |
| 服务详情页 `MCPServerDetailView` | 插件详情页：简介、发布方、版本、数据与隐私（同意状态与时间）、工具列表与开关、同步 / 熔断状态、卸载 |
| Bot 详情「MCP 服务」分组 | 改名为「插件」分组，按已安装插件分组列出工具开关（行为不变） |
| 对话 Trace「🔌 Microsoft Learn · 搜索微软文档」 | 不变 |

### 2.3 非目标（P1 不做）

- 需授权插件（API Key / OAuth）、确认卡片（HITL）、工具定义变更审阅界面。
- 第三方开发者上架、用户自定义 URL、stdio 插件（D3）。
- 插件级 Bot 绑定与技能说明注入提示词（P3）。
- 插件版本升级流程、远程拉取目录、插件评分 / 搜索。
- Web 端（`frontend/web` 冻结）。

---

## 3. 概念模型（Concept Model）

### 3.1 定义

```
插件 Plugin（目录条目，代码内置、随版本发布）
├─ 元数据 metadata：plugin_id, name, description, category, publisher, version, icon(SF Symbol)
├─ 能力 capabilities[]：
│    ├─ { type: "mcp", catalog_id: "microsoft_learn" }   ← 指向 services/mcp/catalog.py 的条目
│    └─ { type: "builtin", tools: ["get_weather"] }       ← 指向 tools/registry.REGISTRY（见 §3.3）
├─ 授权方式 auth_mode：none（P1）/ api_key（P2）/ oauth（P2）
├─ 信任级别 trust：verified（内置目录）/ operator（运维配置，P2 起）
├─ 数据说明 data_notice：同意文案（D4：「工具返回的内容会发送给 DeepSeek」）
├─ 默认安装 default_installed：新用户是否预装
└─ 技能说明 skill（可选，P3）：给模型的使用说明，仅允许来自 verified 目录

用户插件 User Plugin（每用户实例，表 user_plugins）
├─ 安装关系：installed / uninstalled，installed_at，catalog_version
└─ 关联的能力实例：mcp_servers 行（plugin_id 相同）——启用、同意、同步、熔断都在这里
```

### 3.2 与现有 MCP 概念的对应

| 插件层 | MCP 层（已实现） | 说明 |
|---|---|---|
| 插件目录条目 `plugin_id` | 目录条目 `catalog_id` | P1 一一对应，且取值相同（`microsoft_learn`、`aws_knowledge`），降低迁移与排错成本 |
| 已安装插件 | `mcp_servers` 行 | P1 一个插件只有一个 MCP 能力；结构上允许一对多（如未来「Google」插件 = Gmail + Calendar） |
| 插件启用 / 停用 | `mcp_servers.status = 'disabled'` | 插件级开关写入其下所有 MCP 服务 |
| 插件同意 | `mcp_servers.consent_at`（D4，按服务） | 插件详情显示每个服务的同意状态；P1 一对一，即一个开关 |
| 插件工具 | `mcp_tools`（`mcp__{slug}__{tool}`） | 命名空间不变，Bot 白名单 `allowed_tools` 不变 |
| 插件状态 | `status`、`sync_status`、`circuit_state` 组合 | 后端计算一个派生字段 `state`（§5.3），iOS 不再自行组合 |

### 3.3 内置工具是否呈现为「内置插件」

**建议：P1 以「只读展示」的方式呈现两个内置插件，不进入安装 / 卸载流程，不改 schema。**

| 候选 | 建议 | 理由 |
|---|---|---|
| 天气 `get_weather` | 呈现为内置插件「天气」 | 用户感知为一种外部能力；可在插件页统一说明数据来源（Open-Meteo） |
| 提醒 `create_reminder`、`list_reminders` | 呈现为内置插件「提醒」 | 同上 |
| 委派 `ask_bot` | **不**作为插件 | 属于多 Agent 协作核心机制，权限由 `delegate_to` / `accept_delegation` 管理 |
| 记忆 `remember`、`forget_memory` | **不**作为插件 | 由 `bots.memory_access` 与设置 › 记忆管理，已有独立入口 |

内置插件的约束（Q4 已采纳）：`kind = "builtin"`、不可卸载、不需要 D4 同意（结果由 VeraBot 自有工具产生，且与现状一致）、无同步 / 熔断；工具开关仍在 Bot 详情「工具权限」中，插件页只读并提供前往该设置的导航（§6.2）。

---

## 4. 数据模型与迁移（Schema：取合并时下一个可用版本，目前预计 v10）

### 4.1 方案比较

| 方案 | 做法 | 评价 |
|---|---|---|
| A. 重命名 | `mcp_servers` 改名为 `plugins` | **不建议**。`mcp_tools`、`mcp_credentials`、`oauth_states`、`pending_actions` 均以外键引用 `mcp_servers(id)`；SQLite 重命名表需重建并迁移外键，风险高，且一对多能力无法表达 |
| B. 仅代码映射 | 不建表，`plugin_id = catalog_id`，以 `mcp_servers` 行是否存在表示安装 | 改动最小，但无法记录「用户主动卸载」，`ensure_servers()` 的回填问题无法干净解决；内置插件与将来一对多插件也无处落地 |
| **C. 新增安装表（建议）** | 新表 `user_plugins` 只记录安装关系；`mcp_servers` 增加 `plugin_id` 列 | 不动已有表结构与外键；启用 / 同意 / 同步 / 熔断仍在 `mcp_servers`，没有重复字段；卸载可用墓碑（tombstone）记录，防止默认插件被自动重装 |

### 4.2 DDL 与迁移（幂等；下文「v10」指合并时的实际版本号）

```sql
-- v10：插件安装关系。启用、同意、同步、熔断仍在 mcp_servers（单一事实来源）。
CREATE TABLE IF NOT EXISTS user_plugins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plugin_id TEXT NOT NULL,                     -- 目录键，P1 与 mcp catalog_id 相同
  status TEXT NOT NULL DEFAULT 'installed',    -- installed / uninstalled（墓碑：阻止默认插件被自动重装）
  catalog_version TEXT,                        -- 安装时的目录版本（仅展示与将来升级判断）
  settings TEXT,                               -- JSON，预留（P2 的非机密配置，如区域）；机密一律进 mcp_credentials
  installed_at TEXT, uninstalled_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(user_id, plugin_id)
);
CREATE INDEX IF NOT EXISTS idx_user_plugins_user ON user_plugins(user_id, status);
```

```python
# core/config.py（db 只能依赖 core，因此默认安装集合定义在这里）
def plugin_default_installed() -> set[str]:
    # Q6：新账号不预装。VERABOT_MCP_LEARN_ENABLED / _AWS_ENABLED 不再决定预装。
    return set()

# db/migrations/v010_plugins.py（init_db() 中紧接 v9 之后）。整段由 ver < 10 守住，重复启动不再插入。
_add_column(c, "mcp_servers", "plugin_id", "TEXT")
c.executescript(PLUGIN_SCHEMA)
if ver < 10:
    now = now_iso()
    c.execute("""UPDATE mcp_servers SET plugin_id = catalog_id
                 WHERE plugin_id IS NULL AND source='catalog' AND catalog_id IS NOT NULL""")
    # 用过 = 同意过、同步过，或某个 Bot 的白名单里已经有 mcp__{slug}__。
    # 没用过的不插入任何行（也不写 uninstalled）。status='disabled' 本身不算用过：
    # 旧 ensure_servers 会把 Learn 建成 enabled、把 AWS 建成 disabled，两者都可能从未被用户碰过。
    c.execute("""INSERT OR IGNORE INTO user_plugins(
                     user_id, plugin_id, status, installed_at, created_at, updated_at)
                 SELECT s.user_id, s.plugin_id, 'installed', s.created_at, s.created_at, ?
                 FROM mcp_servers s
                 WHERE s.plugin_id IS NOT NULL AND (
                   s.consent_at IS NOT NULL
                   OR s.last_synced_at IS NOT NULL
                   OR EXISTS (
                     SELECT 1 FROM bots b
                     WHERE b.user_id = s.user_id
                       AND instr(b.allowed_tools, 'mcp__' || s.slug || '__') > 0
                   )
                 )""", (now,))
```

迁移约束：

- **不修改** `mcp_servers` 的身份字段（`id`、`slug`、`catalog_id`）、`consent_at`、`sync_status`、`circuit_*`、`last_*`；**不修改** `mcp_tools`；**不修改**任何 Bot 的 `allowed_tools`。
- 已同意的服务在 v10 之后仍为已同意（同意挂在服务行上，未迁移，不需要用户重新同意）。演示账号的 Learn 若已同意，因此保持已安装。
- **迁移不为任何插件写 `uninstalled` 墓碑。** 墓碑只在用户之后主动卸载时写入。这样即使将来 `default_installed()` 不再为空，也不会被历史墓碑挡住（v0.1 的缺陷）。
- 没用过的目录行（包括旧版自动建出、但从未同意、从未同步、也没有 Bot 开启其工具的 Learn / AWS）迁移后是「未安装」：`user_plugins` 没有对应行。行本身保留不删，状态不变，不进模型 schema，也不访问网络。用户安装时复用此行。
- 用过但被停用（`consent_at` 非空，或已同步，或白名单里有工具）的行迁移为已安装，`mcp_servers.status` 仍是 `disabled`，界面显示「已停用」。
- 测试需覆盖：空库、v8 库、v9 库各启动两次；`schema_meta.version` 为 10；用过 → `installed`，没用过 → 没有行且墓碑数为 0（PLG-02 / PLG-02b / PLG-02c）。

### 4.3 运行时规则调整

| 位置 | 现状 | P1 调整 |
|---|---|---|
| `mcp.ensure_servers()` | 为目录中所有条目补行 | 改为：① 用户在 `user_plugins` 中**没有任何记录**且 `plugin_default_installed()` 非空 → 自动安装（当前该函数返回空集，所以新用户不会自动安装）；② 仅为 `installed` 插件物化 `mcp_servers` 行；③ 墓碑（`uninstalled`）不补。后台同步调度逻辑 `_should_schedule()` 不变 |
| `default_installed` 的来源 | `VERABOT_MCP_LEARN_ENABLED` / `_AWS_ENABLED` 决定行初始是否停用 | **Q6：这两个变量不再预装。** `plugin_default_installed()` 固定返回空集。只更新 `.env.example` 注释（不改 `.env`） |
| 卸载 | `remove_server()`：断开会话、`strip_slug_from_bots()`、删除行、审计 | 插件卸载 = 对其每个 MCP 服务执行 `remove_server()`（级联删除 `mcp_tools`）+ `user_plugins.status='uninstalled'` + 审计 `plugin_uninstalled`。重新安装时为全新服务行：新工具 id、同意为空、需重新同意 |
| 审计 | — | 新增 `plugin_installed`、`plugin_uninstalled`，`detail` 含 `plugin_id`、`catalog_version`；现有 `mcp_*` 审计类型不变，只在 `detail` 中追加 `plugin_id` |

### 4.4 卸载与进行中调用 / 后台同步的并发（Concurrency）

背景：`invoke()` 在 `asyncio.to_thread` 中执行，通过 `borrow_session((user_id, server_id), …)` 取得池中的 `MCPSession`（`services/mcp/http_client.py`）；`drop_session()` 会关闭底层 `httpx.Client`。数据库连接启用了 `PRAGMA foreign_keys=ON`（`db/database.py`），因此服务行删除后再写入 `mcp_tools` 会触发外键错误。

**卸载顺序（不等待进行中调用）**

1. 在同一事务内：`user_plugins.status='uninstalled'`、`uninstalled_at=now`；从所有 Bot 的 `allowed_tools` 去掉 `mcp__{slug}__*`；删除 `mcp_servers` 行（级联删除 `mcp_tools`）。
2. 事务提交后调用 `drop_session((user_id, server_id))`，关闭连接池中的会话；进行中的 HTTP 请求因客户端关闭而立即失败。
3. 写审计 `plugin_uninstalled`；接口立即返回，不等待进行中调用结束。

**进行中的工具调用**

| 情形 | 行为 |
|---|---|
| 调用在等待服务器响应时会话被关闭 | `invoke()` 捕获异常后**先检查服务行是否仍存在**；不存在时返回 `{"error": "插件已卸载，本次调用已取消", "code": "plugin_uninstalled"}` |
| 调用恰好在卸载提交后才返回成功结果 | 同样检查服务行；不存在则**丢弃结果**，返回 `plugin_uninstalled`，不把外部内容交给模型，也不设置污染标记（taint） |
| 重试 | `plugin_uninstalled` 不重试（在 `services/mcp/resilience.py` 的 `_with_retries()` 每次尝试前检查服务行） |
| 熔断 | 不计入熔断（`_record_failure()` 不执行；服务行已不存在） |
| 审计 | 仍写一条 `mcp_tool_call`，`status='cancelled'`、`error_class='plugin_uninstalled'`；不存外部原文 |
| 同一轮之后的调用 | 工具已从 `mcp_tools` 删除。`tool_router._call_mcp()` 在 `get_tool_by_full_name()` 为空时，若名称的 slug 属于该用户 `uninstalled` 的插件，返回 `plugin_uninstalled`（而不是笼统的 `unknown_tool`），并写 `tool_denied` 审计 |
| 下一轮对话 | 工具不再出现在 `schemas_for()` 的结果中 |
| 非只读工具（P2 起才会真正发出） | 若请求已发出而会话被关闭，按 M2 规则返回 `result_unknown`（请求可能已执行），不返回 `plugin_uninstalled`，以免误导用户 |

**Trace 显示**：标题不变（`MCPTraceText.title(for:)` 由 slug 映射，例如「🔌 Microsoft Learn · 搜索微软文档」）；说明行为「插件已卸载，本次调用已取消」。实现上在 `VeraBotCore/MCP.swift` 的 `MCPTraceText.errorText(code:error:)` 中增加 `plugin_uninstalled` 分支。模型收到的是同一条错误，应在回答中说明该资料未能获取。

**进行中的后台同步**：`services/mcp/sync.py` 的 `_sync_body()` 在写入工具前和 `apply()`（同一模块）之后各检查一次服务行；不存在时中止并静默结束（不写 `error` 状态、不计熔断）。`schedule_sync()` 的线程若因外键错误抛出 `sqlite3.IntegrityError`，按「已卸载」处理并只记调试日志，不再尝试把不存在的行标记为 `error`。

**停用与进行中的后台同步**：停用优先。`_sync_body()` 写同步结果（成功分支的 `connected`、失败分支和未配置地址分支的 `error`），以及 `schedule_sync()` 线程兜底的 `error`，都通过 `db/mcp_store.py` 的 `update_server_unless_disabled()` 完成，检查和写入在同一条 SQL 里（`… AND status!='disabled'`）。没有写入时调用 `settle_disabled_sync()`，把 `sync_status` 从 `syncing` 收回 `pending`。这次同步的结果不写进服务行。`mcp_tools` 照常写入（停用不删除工具，可用性由 `status='connected'` 决定）。以前的做法是先读后写，停用落在读和写之间时会被覆盖。`mcp_disable_race_test.py`（MCP-RACE-01~08）覆盖这几种情况。

（模块位置：PR #11 起，`_sync_body()` / `schedule_sync()` 在 `services/mcp/sync.py`，`_with_retries()` / `_interruptible()` / `_record_failure()` 在 `services/mcp/resilience.py`，`invoke()` 在 `services/mcp/invoke.py`，`services/mcp/service.py` 是门面并 re-export。）

---

## 5. 后端 API

### 5.1 模块划分（遵循 `api → services / agents → tools / db → core`）

```
backend/verabot/services/plugins/__init__.py
backend/verabot/services/plugins/catalog.py     # 插件目录（元数据 + capabilities），引用 services/mcp/catalog.py 的 catalog_id
backend/verabot/services/plugins/service.py     # 安装 / 卸载 / 启用 / 同意 / 工具 / 同步；聚合 state；调用 services/mcp/service.py
backend/verabot/db/plugin_store.py              # user_plugins 查询，所有读取带 user_id
backend/verabot/api/routers/plugins.py          # /api/plugins/*，在 main.py 的 include_router 列表中注册
```

### 5.2 接口（路径参数使用字符串 `plugin_id`，按用户唯一）

| 方法 | 路径 | 说明 | 主要错误 |
|---|---|---|---|
| GET | `/api/plugins/catalog` | 精选目录全部条目，带当前用户的 `installed` 与 `available`（地址已配置） | — |
| GET | `/api/plugins` | 内置插件 + 已安装的外部插件。新用户只有内置两项，外部列表为空。**不在请求内联网**；已安装且需要同步时才调度后台同步 | — |
| GET | `/api/plugins/{plugin_id}` | 单个插件详情（含 `servers[]` 子项） | 404 未安装 / 未知 |
| POST | `/api/plugins/{plugin_id}/install` | 安装：写 `user_plugins`、补 `mcp_servers`（复用迁移遗留的停用行）、启用并调度后台同步；**不自动同意**。首次安装与卸载后重装均返回 **201** 与插件对象 | **409 已安装**；404 未知插件；422 地址未配置 / 需授权（P1 不支持）/ 内置插件 |
| DELETE | `/api/plugins/{plugin_id}` | 卸载（§4.3）；返回 `{ok, removed_tools, affected_bots}` | 404；422 内置插件不可卸载 |
| PATCH | `/api/plugins/{plugin_id}` | `{enabled: bool}`，写入其下全部 MCP 服务（`mcp.set_enabled`） | 404；422 内置插件 |
| POST | `/api/plugins/{plugin_id}/consent` | `{granted: bool}`，写入其下全部 MCP 服务（`mcp.set_consent`，审计不变） | 404；422 内置插件 |
| GET | `/api/plugins/{plugin_id}/tools` | 工具列表，字段同 `MCPTool`，追加 `plugin_id` | 404 |
| POST | `/api/plugins/{plugin_id}/sync` | 阻塞式同步（`mcp.sync_server`），返回 `{added, changed, removed, plugin}` | 404；409 已停用 |

工具定义变更接受仍使用 `POST /api/mcp/tools/{id}/accept-change`（变更审阅界面不在 P1 范围），P2 再决定是否增加 `/api/plugins/{plugin_id}/tools/{id}/accept-change`。

### 5.3 插件对象（`Plugin` JSON）

```json
{
  "plugin_id": "microsoft_learn",
  "kind": "mcp",
  "name": "Microsoft Learn",
  "description": "查询微软官方技术文档与代码示例。",
  "category": "知识与文档",
  "publisher": "Microsoft",
  "version": "1.0.0",
  "icon": "book.closed",
  "auth_mode": "none",
  "trust": "verified",
  "installed": true,
  "available": true,
  "removable": true,
  "enabled": true,
  "state": "needs_consent",
  "consent_required": true,
  "consent_at": null,
  "data_notice": "工具返回的内容会发送给 DeepSeek 用来生成回答。",
  "tools_count": 3,
  "sync_status": "ok",
  "last_synced_at": "2026-10-03T08:12:00+00:00",
  "last_error": null,
  "circuit_state": "closed",
  "circuit_open_until": null,
  "consecutive_failures": 0,
  "servers": [ { "...": "public_server() 原样输出，含 id / slug / consent_at 等" } ]
}
```

派生字段 `state` 的判定顺序（后端计算，iOS 只做文案映射）：
`not_installed` → `disabled` → `circuit_open` → `syncing`（`pending` / `syncing`）→ `error`（`sync_status='error'` 或 `status='error'`）→ `needs_consent`（任一服务 `consent_at` 为空）→ `ready`。内置插件固定为 `ready`。多服务插件取「最差」状态。

时间字段沿用现有约定（后端 UTC ISO 8601，iOS 用 `ListTimestamp` 转本地时间显示）。公开 JSON 继续不含原始 URL（沿用 M1 的 `url_configured` 原则，此处为 `available`）。

### 5.4 `/api/mcp/*` 的处理

- P1、P2：**路径保留**，文档标注为「已弃用」。不给这些路径单独加缓存头。
- 行为变化有两处，都是为了让「未安装」成立：① `GET /api/mcp/servers` 不再补齐未安装插件的行，卸载后的服务不再出现；② `POST /api/mcp/servers` 改为调用 `plugins.install`（201 返回原来的服务器对象；已安装 → 409「已经添加过这个服务」；未知目录 → 422「未知的 MCP 服务」）。否则旧接口依赖「GET 时自动建行」，在不再预装之后无法添加服务。
- iOS 在 P1 中改用 `/api/plugins/*`；`APIClient` 中的 `mcp*` 方法保留至 P3 再移除。
- `GET /api/tools`：每项追加可选 `plugin_id`（MCP 工具为所属插件；天气 / 提醒为 `builtin_weather` / `builtin_reminder`；`ask_bot` 等其余为 `null`）。iOS `ToolInfo` 追加可选属性，旧 JSON 缺键时为 `nil`。

### 5.5 契约测试（Contract test）

- 新建 `backend/scripts/test/plugin_test.py`，复用 `mcp_test.py` 的 `_keys()` 思路与进程内假 MCP 服务器。
- PLUGIN-CONTRACT：`VeraBotCore/Plugin.swift` 中 `Plugin`、`PluginToolsResponse`、`PluginSyncResult` 的 `CodingKeys` ⊆ 对应后端 JSON 键；`Models.swift` 的 `ToolInfo` ⊆ `/api/tools` 每项键（含新增 `plugin_id`）。
- MCP-CONTRACT 保持并继续通过（证明 `/api/mcp/*` 未被破坏）。

### 5.6 缓存与账号隔离（与账号隔离修复对齐）

- 账号隔离修复（`2a0dc0f`）已在 main：所有 `/api/*` 响应由 `NoStoreAPIMiddleware` 带 `Cache-Control: no-store`；iOS `APIClient` 使用 `APITransport.session`（无 `URLCache`）。
- 插件接口不另设缓存头。`APIClient` 中的 `plugin*` 方法都走 `call(...)`，因此用同一套不缓存的会话。
- PLG-12 同时断言：跨用户访问返回 404，且 `/api/plugins`、`/api/plugins/catalog`、`/api/plugins/{plugin_id}`、`/api/plugins/{plugin_id}/tools` 的响应头包含 `Cache-Control: no-store`。

---

## 6. iOS 界面（系统原生样式）

### 6.1 设置页入口

- `SettingsView.body` 中以 `PluginsSettingsSection()` 替换 `MCPServicesSection()`，位置不变（记忆之后、通用之前）。
- 该分组只有一行：`NavigationLink` + `LabeledContent { Text("已安装 N 个") } label: { Label("插件", systemImage: "puzzlepiece.extension") }`，与「用量」行的写法一致；`.toolbar(.hidden, for: .tabBar)` 沿用现有做法。
- 分组页脚一句话：「插件为 Bot 提供外部能力。每个插件需要单独同意后才会调用。」

### 6.2 页面结构

| 页面（建议文件） | 内容 |
|---|---|
| 插件页 `PluginListView`（`Features/Plugins/PluginListView.swift`） | **Q4：两组为「内置」和「外部」**，不是「已安装 + 内置」。「内置」：天气、提醒，副标题「内置 · 无需安装」。「外部」：已安装的 MCP 插件，副标题为状态文案（「可用」「待同意」「正在同步」「已停用」「已熔断」「同步失败」）；空时「还没有安装外部插件」。底部一行「浏览插件」。同步中每 0.5 秒刷新，最多 20 次。设置行「已安装 N 个」只数 `kind=mcp` 且已安装的插件 |
| 插件目录 `PluginCatalogView`（`Features/Plugins/PluginCatalogView.swift`） | 按 `category` 分组的 `List`；每行名称、发布方、一句简介，右侧为「安装」按钮（`.buttonStyle(.bordered)`）或「已安装」次要文字；`available=false` 时置灰并说明「服务地址未配置」。安装成功后跳转详情页，并提示需要同意 |
| 插件详情 `PluginDetailView`（`Features/Plugins/PluginDetailView.swift`，由 `MCPServerDetailView` 重构而来） | ① 头部：图标、名称、发布方 · 版本、简介；② 「状态」：状态、同步、上次同步、熔断（打开时显示恢复时间）、连续失败、最近错误、「启用此插件」开关、「刷新工具」；③ 「数据与隐私」：「同意把工具结果发送给 DeepSeek」开关 + 同意时间（D4 文案不变）；④ 「工具」：「应用到 Bot」选择器、「开启全部只读」、逐个工具开关与风险标签（只读 / 写入 / 发送 / 破坏性）；⑤ 「卸载插件」（`role: .destructive`，`confirmationDialog` 说明：会从所有 Bot 移除该插件的工具，并清除同意记录） |
| 内置插件详情 `BuiltinPluginDetailView`（与外部详情同一文件） | 只读：图标、名称、简介、数据来源（天气：Open-Meteo）、所含工具。**说明文字**：「内置插件无需安装，也不能卸载。是否让某个 Bot 使用它，在该 Bot 的『工具权限』里设置。」**「已开启的 Bot」**分组：列出 `allowed_tools` 中包含该插件工具的 Bot（只读）。**导航路径**：「前往 Bot 的工具权限」→ 选择 Bot 的列表（数据来自 `bots()`）→ 进入该 Bot 的 `BotEditView`，其中「工具权限」分组即为开关所在位置。不提供开关，避免两处修改同一设置 |
| Bot 详情 `BotEditView` | 「MCP 服务」分组改名「插件」，数据源改为 `plugins()` + `pluginTools(id:)`；未安装的插件不显示；行为与 `MCPToolRules` 不变 |

规则：只用系统组件（`Form` / `ThemedForm`、`Section`、`LabeledContent`、`CompactToggle`、`NavigationLink`、`confirmationDialog`）与 Theme 语义色；不加自定义动画；不加载远程图片（图标只用目录里的 SF Symbol 名称，与 MCP_CAPABILITY §6.3「App 不直接加载第三方 URL」一致）；界面文案不出现「MCP」。

### 6.3 VeraBotKit 改动

- `VeraBotCore/Plugin.swift`：`Plugin`、`PluginState`（文案映射）、`PluginCatalogResponse`、`PluginsResponse`、`PluginToolsResponse`（复用 `MCPTool`，追加可选 `pluginId`）、`PluginSyncResult`。
- `VeraBotNetworking/VeraBotAPI.swift` 与 `APIClient.swift`：`pluginCatalog()`、`plugins()`、`plugin(id:)`、`installPlugin(id:)`、`uninstallPlugin(id:)`、`updatePlugin(id:enabled:)`、`setPluginConsent(id:granted:)`、`pluginTools(id:)`、`syncPlugin(id:)`。
- `Models.swift`：`ToolInfo` 追加可选 `pluginId`。
- `MCPTraceText`：标题逻辑不变（服务显示名仍由 slug 映射）；`errorText` 增加 `plugin_uninstalled` →「插件已卸载，本次调用已取消」。
- 测试：`Tests/VeraBotKitTests/PluginTests.swift`（解码、忽略多余键、`state` 文案、缺字段兼容）。
- `Features/MCP/MCPSettings.swift`：P1 中删除 `MCPServicesSection`，详情逻辑迁入 `PluginDetailView`；文件可整体移除（无 pbxproj 改动，见 §1.2）。

### 6.4 Bot 级插件绑定（P3，仅说明）

现状已能在 Bot 粒度按工具开关（`allowed_tools`）。P3 再引入「插件绑定」：Bot 详情中以插件为单位开启，开启时展开为具体工具名写入 `allowed_tools`（与 D7「开启全部只读」的展开原则一致，不做隐式授权），并可附带插件的技能说明。

---

## 7. 分期（Phasing）

| 阶段 | 范围 | 前提 | 规模（粗估） |
|---|---|---|---|
| **P1 收敛与入口（单个 PR）** | schema（合并时下一个可用版本，预计 v10；`user_plugins` + `mcp_servers.plugin_id`）；`services/plugins/*`、`db/plugin_store.py`、`api/routers/plugins.py`；`ensure_servers()` 改为只补已安装插件；真正的卸载（含 §4.4 并发规则）；`/api/tools` 追加 `plugin_id`；iOS 设置「插件」入口、插件页、目录页、详情页、Bot 详情分组改名；内置精选目录仅 Microsoft Learn、AWS Knowledge（+ 可选内置插件展示）；`plugin_test.py`、`PluginTests.swift`；文档 | 本文审查通过、§8 决定完成 | 约 2–3 人日 |
| **P2 需授权插件** | `auth_mode = api_key / oauth`；API Key 加密存入 `mcp_credentials`（Fernet，`VERABOT_TOKEN_ENC_KEY`）；OAuth 2.1 按 MCP_CAPABILITY §5 使用 `oauth_states`；`pending_actions` 确认卡片（对应 MCP_CAPABILITY 的 M3 / M4）；首个授权插件为 Gmail（对应 M5 / M6）；变更审阅界面 | P1；Google 准备事项（D9） | 按 MCP_CAPABILITY §15 M3–M6 估算 |
| **P3 Bot 绑定与技能说明** | Bot 详情以插件为单位开启（展开为工具名）；插件 `skill` 文本在该 Bot 的系统提示词中以「插件使用说明」注入（仅 verified 目录、限长、清洗，不改变 §9 的不可信结果规则）；移除 `/api/mcp/*` 与 iOS `mcp*` 方法 | P2（或 P1 之后即可，若 Boss 优先） | 约 2 人日 |

P1 的边界控制：不新增任何第三方插件；不改权限判定顺序、命名空间、同意语义、审计字段、重试与熔断参数；不引入新依赖。

---

## 8. 风险与待决定事项（Open Decisions）

| # | 问题 | 决定 / 建议默认值 | 状态 | 理由 |
|---|---|---|---|---|
| Q1 | schema 版本号 | **取合并时下一个可用版本，目前预计 v10** | ✅ 已决定 | v9 已被账号体系占用；避免与账号隔离修复冲突 |
| Q2 | 数据模型 | **新增 `user_plugins` 安装表 + `mcp_servers.plugin_id`**（方案 C） | ✅ 已决定 | 不动外键与已有数据；能表达卸载墓碑与将来一对多能力 |
| Q3 | 同意粒度 | **保持按 MCP 服务记录（D4 不变）**；插件详情一个开关，写入其下全部服务；多服务插件在详情中分别显示 | ✅ 已决定 | 不改已批准决定；P1 一对一，无差异 |
| Q4 | 天气、提醒是否呈现为「内置插件」 | **采纳。** 插件页「内置」组展示天气、提醒；不可卸载、无需同意。某个 Bot 能否使用仍在该 Bot 的「工具权限」；插件页导航过去（`BuiltinPluginDetailView`）。`ask_bot` 与记忆不作为插件 | ✅ 已决定 | 统一用户认知，零 schema 成本 |
| Q5 | 迁移时 AWS Knowledge（默认不安装、从未使用）的状态 | **记为「未安装」**，出现在「浏览插件」中 | ✅ 已决定 | 与「已安装只放用户主动选择的」一致；行保留不删 |
| Q6 | 新用户是否预装；老用户迁移 | **不预装。** `default_installed()` 为空（含 Microsoft Learn）。用过（同意、同步，或任一 Bot 已开启其工具）→ `installed`；没用过 → 未安装，**迁移不写墓碑**。演示账号已同意的 Learn 保持已安装。仅 `status='disabled'` 不算用过 | ✅ 已决定（与 v0.2 建议不同） | 新账号从空列表开始；墓碑只留给主动卸载，避免挡住以后的预装 |
| Q7 | 卸载的影响 | **采纳。** 从所有 Bot 移除该插件工具、删除工具缓存、清除同意；iOS 卸载前 `confirmationDialog`。重装须重新同意，并按 Bot 重新开启 | ✅ 已决定 | 与 `remove_server()` 现有语义一致，避免残留授权 |
| Q8 | `/api/mcp/*` 的去留 | **P1、P2 保留不变，仅文档标注弃用；P3 移除** | ✅ 已决定 | Web 冻结且未使用这些接口；降低单个 PR 风险 |
| Q9 | 设置页入口形态 | **以单行「插件」替换现有分组，位置不变** | ✅ 已决定 | 设置页保持简洁；详情下沉到二级页 |
| Q10 | 「插件注册」术语冲突 | **将 ARCHITECTURE §2.2 与 `tools/__init__.py` 注释中的「插件注册」改称「工具自注册例外」**（仅文字） | ✅ 已决定 | 避免与本功能混淆 |
| Q11 | Bot 详情「MCP 服务」分组 | **P1 改名为「插件」并改用插件接口** | ✅ 已决定 | 用户界面不再出现「MCP」；行为不变 |
| Q12 | `version` 字段含义 | **VeraBot 目录版本（语义化版本），不取服务器自报的 `serverInfo.version`**；P1 仅展示 | ✅ 已决定 | 服务器自报信息不可信且不保证稳定 |
| Q13 | 插件分类与「内置」 | **「内置」单独成组（独立 Section），不是分类**；P1 分类只有「知识与文档」；P2 再增「邮件与日历」等 | ✅ 已决定 | 「内置」描述的是来源而非用途，与分类不同维度 |
| Q14 | 第三方 / 自定义 URL 插件 | **P1–P3 均不做**，沿用 D3 | ✅ 已决定 | 攻击面与合规成本 |

主要风险：

1. **卸载导致 Bot 工具丢失**：属于预期行为，但会改变 Bot 能力。对策：确认对话框列出受影响的 Bot 数量；响应体返回 `affected_bots`；审计记录。
2. **`ensure_servers()` 行为变化**：可能影响依赖「目录条目总会出现」的现有用例（MCP-API、MCP-06）。对策：P1 同步调整这两条用例的预期，并在 TEST_CASES 中说明原因。
3. **重装后工具 id 变化**：`mcp_tools.id` 会变，但 Bot 白名单使用 `full_name`，卸载时已清除，不存在悬挂引用。
4. **派生 `state` 前后端不一致**：对策：状态只在后端计算，iOS 只做文案映射，并纳入契约测试。
5. **内置插件与 MCP 插件混排的认知负担**：对策：「内置」单独成组，明确标注「内置 · 无需安装」，详情页说明开关位置并提供导航。
6. **卸载 / 停用与进行中调用 / 后台同步竞争**：对策见 §4.4（实现在 `services/mcp/sync.py` 的 `_sync_body()` 与 `services/mcp/resilience.py` 的 `_with_retries()` / `_interruptible()`）；卸载以 PLG-14、PLG-15 覆盖，停用以 MCP-RACE-01~08 覆盖。
7. **与账号隔离修复的合并顺序**：schema 版本号与缓存头都可能冲突。对策：版本号取合并时的下一个可用值；缓存头按 §5.6 处理，后合并的一方负责对齐。

---

## 9. 沿用的规则（Rules carried over）

1. 前后端同步改：后端接口、iOS 模型与界面、契约测试、字段对照表在**同一个提交**中交付。
2. Web（`frontend/web`）冻结：不实现插件界面；在 STATUS「已知遗留」中注明「插件 P1 没有 Web 对应」。由于 `/api/mcp/*` 与 `/api/tools` 向后兼容，Web 现有功能不受影响。
3. 不改动：`backend/.env`、tag `v0.1.0`、本地签名改动（`frontend/ios/VeraBot.xcodeproj/project.pbxproj` 中的 `DEVELOPMENT_TEAM`）、`frontend/ios/VeraBot/InfoPlist.xcstrings`、`AvatarLab*` 相关文件。只 `git add` 自己的文件。
4. iOS 只用系统原生样式与 Theme 语义色，不加自定义动画。
5. 文档同提交：`docs/design/PLUGIN_DESIGN.md`（本文定稿）、`MCP_CAPABILITY.md` 增加 §18.4「插件化」进度说明（不改 §16）、`STATUS.md`、`CHANGELOG.md`、`TEST_CASES_v0.1.md`（PLG-xx）、`FEATURES.md`、`ARCHITECTURE.md`（模块列表与 §2.2 术语）、`docs/README.md` 索引、`backend/README.md`（API 列表）、`MCP_CAPABILITY.md` §18 增补插件字段对照表（§18.4）。
6. 提交作者 `Luis <luisporschewind@gmail.com>`；版本号按 SemVer，P1 不单独发版。

---

## 10. P1 验收标准（Acceptance Criteria）

### 10.1 后端（`backend/scripts/test/plugin_test.py`，进程内假 MCP 服务器，不依赖外网）

| ID | 用例 | 预期 |
|---|---|---|
| PLG-01 | v8 库、v9 库、空库各启动两次 | `schema_meta.version` 为合并时版本（预计 10）；`user_plugins` 存在；`mcp_servers.plugin_id` 回填为 `catalog_id`；重复启动无新增行、无报错 |
| PLG-02 | v9 库中 Learn 已同意并同步 | 迁移后 Learn 为 `installed`，`consent_at` 不变，Bot 白名单不变，工具可直接调用 |
| PLG-02b | v9 库中 Learn 与 AWS 都未同意、未同步，且没有任何 Bot 开启其工具 | 迁移后两者都**不是** `installed`，`user_plugins` 没有 `uninstalled` 墓碑；重复启动行数不变 |
| PLG-02c | 另一份 v9：某 Bot 白名单含 `mcp__aws__*`，Learn 未使用；再一份：Learn 已同意但 `status='disabled'` | 用过的 AWS 为 `installed`，未使用的 Learn 没有行。已同意但停用的 Learn 为 `installed`，没有墓碑 |
| PLG-03 | v9 库中 AWS 为停用且从未使用 | 与 PLG-02b 相同：未安装、无墓碑；`GET /api/plugins` 不含 AWS；目录里 `installed=false`；无网络请求 |
| PLG-04 | 新用户首次 `GET /api/plugins`；`plugin_default_installed()` | 已安装列表只有内置天气与提醒，没有外部插件；0.7 秒内返回且假服务器没有 `tools/list`。`default_installed()` 为空集 |
| PLG-05 | 安装 AWS | 首次安装返回 **201** 与插件对象；复用原服务行；后台同步；`consent_at` 为空；再次安装返回 **409** |
| PLG-06 | 同意 / 撤回 | `POST /api/plugins/{id}/consent` 写入其下服务的 `consent_at`，审计 `mcp_consent_granted` / `_revoked` 带 `plugin_id`；撤回后调用返回 `mcp_consent_required` |
| PLG-07 | 卸载 | Bot 白名单中 `mcp__learn__*` 被移除；工具缓存删除；`status=uninstalled`；审计 `plugin_uninstalled`；之后 `GET /api/plugins` 与 `GET /api/mcp/servers` 均**不再自动补回** |
| PLG-08 | 卸载后重装 | 返回 **201**；新服务行、同意为空、需重新同意；旧审计记录保留 |
| PLG-09 | 启用 / 停用 | 停用后工具不进 schema、调用返回 `not_connected`；`sync` 返回 409 |
| PLG-10 | 派生 `state` | 覆盖 `disabled`、`circuit_open`、`syncing`、`error`、`needs_consent`、`ready` 的判定顺序 |
| PLG-11 | 内置插件 | 出现在 `GET /api/plugins`，`kind=builtin`、`removable=false`、`state=ready`；卸载 / 同意 / 启用接口返回 422 |
| PLG-12 | 租户隔离与缓存 | 用户 B 访问用户 A 的插件详情、工具、同意、卸载均 404 或仅作用于自身；`/api/plugins*` 响应头含 `Cache-Control: no-store`（§5.6） |
| PLG-13 | `/api/tools` | MCP 工具带 `plugin_id`；旧字段不变 |
| PLG-14 | 卸载时有进行中调用：假服务器 `tools/call` 睡 1.5 秒，在另一线程发起 `dispatch()`，0.3 秒后卸载 | 卸载接口 0.5 秒内返回（不等待调用）；调用返回 `code=plugin_uninstalled`，不重试；`TurnState.untrusted_tainted` 为假；审计有 `mcp_tool_call`（`status=cancelled`、`error_class=plugin_uninstalled`）；无未捕获异常；同一轮再次调用该工具名返回 `plugin_uninstalled`；连接池中不再有该会话 |
| PLG-15 | 卸载时后台同步进行中：假服务器 `tools/list` 睡 1.5 秒，安装后立即卸载 | 同步线程静默结束；`mcp_tools` 中没有该插件的行；无外键错误日志外泄；`user_plugins` 仍为 `uninstalled` |
| PLG-CONTRACT | 契约 | iOS `Plugin` 等类型的 `CodingKeys` ⊆ 后端 JSON 键；`ToolInfo` ⊆ `/api/tools` |
| 回归 | 全部 | `mcp_test.py`（MCP-API、MCP-06 按 §8 风险 2 调整预期后）、`multi_agent_test`、`memory_test`、`bot_pin_test`、`bot_tags_test`、`avatar_profile_test`、`status_event_test`、`auth_test` 全部通过；`VERABOT_MCP_LIVE_TESTS=1` 下 Learn / AWS 公网用例通过 |

### 10.2 iOS

| ID | 验收点 |
|---|---|
| PLG-KIT | `swift test` 全部通过（含新增 `PluginTests.swift`；`MCPTraceText.errorText` 覆盖 `plugin_uninstalled`） |
| PLG-BUILD | `xcodebuild`（iPhone 17 模拟器）编译通过，无 pbxproj 改动 |
| PLG-UI-01 | 设置页出现「插件」一行，显示「已安装 N 个」；原「连接的账号 / MCP 服务」分组已移除 |
| PLG-UI-02 | 插件页：分组为「内置」「外部」，底部「浏览插件」；状态文案正确；同步中自动刷新 |
| PLG-UI-03 | 目录页：安装 AWS → 进入详情 → 提示需要同意；已安装条目显示「已安装」 |
| PLG-UI-04 | 详情页：同意开关与同意时间（本地时间）、工具开关与风险标签、刷新工具、熔断与错误信息、启用开关 |
| PLG-UI-05 | 卸载：二次确认 → 返回插件页且该插件消失；Bot 详情中对应工具开关消失 |
| PLG-UI-06 | Bot 详情「插件」分组：开关与「开启全部只读」行为与现状一致；界面无「MCP」字样 |
| PLG-UI-07 | 对话中使用 Learn 工具一轮：Trace 显示「🔌 Microsoft Learn · …」，结果正常 |
| PLG-UI-08 | 内置插件：天气详情页显示说明文字与「已开启的 Bot」；「前往 Bot 的工具权限」→ 选择 Bot → 进入该 Bot 编辑页，「工具权限」中可开关天气 |
| PLG-UI-09 | 对话中调用 Learn 工具时卸载插件：Trace 说明行显示「插件已卸载，本次调用已取消」，App 不崩溃 |

### 10.3 文档与交付

- §9 第 5 条所列文档在同一提交中更新；STATUS 注明 Web 落后与本机数据库迁移前备份路径（建议 `backend/data/verabot.db.bak-before-v10-<时间戳>`）。
- PR 为草稿（Draft），由 Veronica 在 Boss 的 Mac 上审查、编译、跑测试与模拟器验收后合并，再交 Boss 验收。

---

## 附录 A：P1 预计改动文件清单

**后端**：`backend/verabot/core/config.py`（`plugin_default_installed()`）、`backend/verabot/db/schema.py`（合并时版本，预计 v10）、新增 `backend/verabot/db/plugin_store.py`、新增 `backend/verabot/services/plugins/{__init__,catalog,service}.py`、`backend/verabot/services/mcp/service.py`（`ensure_servers()`、卸载辅助、`invoke()` / `_sync_body()` 的已卸载检查）、`backend/verabot/agents/tool_router.py`（仅 `plugin_uninstalled` 拒绝码）、新增 `backend/verabot/api/routers/plugins.py`、`backend/verabot/main.py`（注册路由）、`backend/verabot/api/routers/meta.py`（`plugin_id`）、`backend/.env.example`（注释）、新增 `backend/scripts/test/plugin_test.py`、`backend/scripts/test/mcp_test.py`（MCP-API / MCP-06 预期）、`backend/verabot/tools/__init__.py`（仅注释术语）。

**iOS**：`frontend/ios/VeraBot/Features/Settings/SettingsView.swift`、新增 `frontend/ios/VeraBot/Features/Plugins/{PluginsSettingsSection,PluginListView,PluginCatalogView,PluginDetailView}.swift`、删除 `frontend/ios/VeraBot/Features/MCP/MCPSettings.swift`、`frontend/ios/VeraBot/Features/BotInfo/BotEditView.swift`、新增 `frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Plugin.swift`、`Models.swift`（`ToolInfo.pluginId`）、`VeraBotNetworking/{VeraBotAPI,APIClient}.swift`、新增 `Tests/VeraBotKitTests/PluginTests.swift`。

**文档**：`docs/design/PLUGIN_DESIGN.md`（本文）、`docs/design/MCP_CAPABILITY.md`（§18.4「插件化」进度说明与**插件字段对照表**：`Plugin` JSON ↔ iOS `Plugin`、`/api/plugins/{id}/tools` ↔ `MCPTool.pluginId`、`/api/tools.plugin_id` ↔ `ToolInfo.pluginId`；不改 §16）、`docs/STATUS.md`、`docs/CHANGELOG.md`、`docs/testing/TEST_CASES_v0.1.md`（PLG-xx）、`docs/product/FEATURES.md`、`docs/design/ARCHITECTURE.md`（模块列表、§2.2 术语）、`docs/README.md`、**`backend/README.md`**（新增 `/api/plugins/*` 接口说明、`/api/mcp/*` 标注弃用）。

**不改**：`frontend/web/*`、`backend/.env`、`project.pbxproj`、`InfoPlist.xcstrings`、`AvatarLab*`、`services/mcp/http_client.py`、`agents/tool_router.py` 的既有判定顺序、`agents/permissions.py`。
