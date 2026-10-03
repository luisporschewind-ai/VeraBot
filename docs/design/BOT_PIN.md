# Bot 置顶 (Bot pin) — 规格 v1.0 (Boss 已批准，2026-10-01，已实现)

> 状态：**已实现** (2026-10-01)。schema **v6** 用于本功能；MCP / Gmail 使用 **v7**。

## 1. 后端

| 项 | 规格 |
|---|---|
| 数据库 | `bots.pinned_at TEXT NULL` (UTC ISO 8601，`db.now_iso()` 格式，NULL = 未置顶)。`schema.py` 用 `_add_column` 幂等加列，`SCHEMA_VERSION = 6`，`init_db` docstring 加「v5 → v6」。只加列，不回填、不改已有数据 |
| 迁移前备份 | 先停服务，再备份 `backend/data/verabot.db` → `backend/data/verabot.db.bak-before-v6` (同 v4 的做法；`*.db` 已被 gitignore) |
| Bot JSON | `PUBLIC_FIELDS` 增加 `pinned_at` (字符串或 `null`)。**只有这一个字段**，不另加 `pinned: bool` (客户端用 `pinned_at != null` 判断) |
| 写接口 | 沿用 `PATCH /api/bots/{id}`，新增可选 `pinned: bool`：省略 / null = 不修改；`true` = 置顶 (已置顶时**保留原时间**，幂等)；`false` = 取消 (`pinned_at = NULL`)。`pinned` 不进 `model_dump` 的普通字段，单独处理。不加新接口 |
| 列表顺序 | 只改 `GET /api/bots`：置顶的在前，按 `pinned_at` 倒序 (同一时刻按 id 升序)；其余按 id 升序 (现有顺序)。`db.list_bots` 本身不改 (委派、提示词等其他调用方不受影响) |
| 兼容 | 旧客户端忽略 `pinned_at`；不传 `pinned` 时行为不变。删除 Bot 时随行删除，无需清理 |

## 2. iOS

- 模型：`Bot.pinnedAt: String?` (`pinned_at`，缺失 / null → nil)、`isPinned`；`BotPatch.pinned: Bool?` (nil 不编码)。
- 排序：`VeraBotCore` 的 `BotOrdering.sorted(_:)` 与后端同一规则，置顶变化后本地重排。
- 首页：`.swipeActions(edge: .leading)` 一个按钮「置顶」/「取消置顶」(SF Symbol `pin.fill` / `pin.slash.fill`；置顶按钮 `.tint(Color.pinTint)` = 品牌色，取消置顶 `Color.unpinTint` = 系统灰)；长按 `contextMenu` 加同一项 (在「编辑与权限」旁)。
- 置顶切换 (2026-10-03 改为乐观更新)：点按后等 0.25 s 让左滑按钮收起，再 `withAnimation(.snappy) { bots = BotOrdering.togglingPin(bots, id:) }` (系统 List 行移动)，然后 PATCH；返回后 `BotOrdering.replacingPinnedAt` 用服务端 `pinned_at` 校正，顺序不变则不再动画；失败时动画回滚到原值并显示错误。同一 Bot 同步中忽略重复点按。乐观时间用 `BotOrdering.pinTimestamp` (与 `db.now_iso()` 同格式)，若不晚于已有最新置顶则取其 +1 s，保证新置顶排在最前。旧实现先 await 再重排，且与滑动按钮收起动画冲突，导致卡顿 / 行短暂空白。
- 行内置顶标记：名称右侧 `pin.fill` (caption2，`Color.pinTint`)，出现 / 消失 `.scale + .opacity` 过渡。
- 置顶行：`listRowBackground(Color.sectionFill)` 浅灰底 (#EFEFEE，深色为 `secondarySystemBackground`)；仍是全宽、无分隔线 (`plainListRow`)。
- 搜索结果保持同一顺序。Web 冻结，不做 (STATUS 注明)。

## 3. 测试 (需新增)

| ID | 内容 |
|---|---|
| PIN-01 | v5 → v6 迁移幂等：出现 `pinned_at` 且存量为 NULL，其他列不变；`TAG-01` 的版本断言改为 `db.SCHEMA_VERSION` |
| PIN-02 | 新建 Bot `pinned_at: null` |
| PIN-03 | `pinned: true` → 有时间；再次 `true` 时间不变 |
| PIN-04 | `pinned: false` → null；省略 `pinned` 只改名称时置顶状态不变 |
| PIN-05 | 列表顺序：先后置顶 A、B → [B, A, 其余按 id]；取消 B → [A, 其余] |
| PIN-06 | `pinned` 非布尔 → 422 中文；他人 Bot 404 |
| PIN-07 | 详情 / 列表 / PATCH 响应字段一致 |
| PIN-08 | 契约：后端读取 iOS `Models.swift` 断言 `pinned_at` / `pinned` CodingKeys；`BotOrdering` 与后端排序在同一组样本上结果一致 |
| PIN-UI-01~03 | (待 Boss 验收) 左滑 / 长按置顶与取消、置顶行浅灰底、默认动画重排 |
| Kit | `swift test`：解码 (缺失 / null / 有值)、`BotPatch` 编码、`BotOrdering` |

回归：bot_tags、multi_agent、avatar_profile、memory 全部通过；`swift test` 全过。

## 4. 前后端对照 (Mapping checklist)

| 后端 | iOS | 说明 |
|---|---|---|
| `bots.pinned_at` / JSON `pinned_at` | `Bot.pinnedAt` (`isPinned`) | UTC ISO 字符串或 null |
| PATCH `pinned: bool` | `BotPatch.pinned` | nil = 不修改 |
| `GET /api/bots` 排序 (`list_order_key`) | `BotOrdering.sorted` | 同一规则，PIN-08 断言 |
| schema v6 | — | MCP / Gmail 用 v7 |
