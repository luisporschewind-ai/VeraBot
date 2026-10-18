# 「安排」：提醒 · 待办 · 任务 一体化方案（Plan）

日期：2026-10-18。状态：**已批准（2026-10-18）**；**P1 已实现（2026-10-18，待验收/部署）**。11 项决策全部定稿：除决策 2 外均按推荐执行；决策 2 定为 Tab / 模块改名「安排」（参考 Meta Muse 的 Upcoming）。
基线：`origin/main` 42e77f8（schema v36）。时间均为 Asia/Shanghai (UTC+8)。

### P1 进度

| 项 | 状态 |
|---|---|
| v37 迁移 + 回填幂等 + `.bak-before-v37-*` | 已完成 |
| `/api/items` 列表/详情/创建/动作/清单 | 已完成（P1 不创建 Bot 任务） |
| Bot 工具待办 + checklist + `source_kind` | 已完成 |
| `unified_items_test.py` + 既有 reminder 测试 | 已完成（本机跑通） |
| iOS「安排」分组 / 详情 / 编辑清单 / 旧入口 / 通知 | 已完成（未跑 xcodebuild / swift test） |
| 文档（CHANGELOG / STATUS / 设计增补 / 用例） | 已完成 |
| P2 交给 Bot / 任务操作代理 / `propose_task` | 未开始 |

## 0. 一句话

把原「提醒」Tab 改名为「安排」，变成统一的事项模块。用户只看到**一种事项**，按属性区分（有没有时间、要不要通知、有没有清单、是否交给 Bot 执行）。后端**不合并执行引擎**：提醒继续由提醒调度执行，Bot 任务继续由 `scheduled_tasks` / `owned_tasks` 执行，事项通过链接字段关联到它们。

## 1. 现状（只读盘点）

| 模块 | 后端 | iOS 入口 | 备注 |
|---|---|---|---|
| 提醒 | `reminders`（v1 建表，v11 扩展：due_utc、rrule、status、notify、alert_offsets、assignee_bot_id、source_message_id、created_by…），`reminder_events`；`/api/reminders`（增删改、complete、snooze、reopen、skip、restore、events）；调度在 API 进程内（`services/reminders/scheduler.py`，每 30 秒） | 「提醒」Tab：`RemindersView`，顶部分段「提醒 / 通知」，分组 逾期 / 今天 / 即将 / 无日期 / 已错过 / 已完成；左上筛选（全部 / 我创建 / Bot 创建 / 某 Bot） | 本地通知（R1），点通知打开该提醒（§9.5）。Bot 工具 `create_reminder` / `list_reminders` / `manage_reminder`，可见范围见 REMINDER_PUSH_DESIGN §5.2 |
| 周期任务 | `scheduled_tasks` / `_runs` / `_attempts`（v23），`/api/scheduled-tasks`（暂停、恢复、立即执行、执行记录）；worker `vbscheduled` | 只能从**对话菜单**或**Bot 编辑页 →「任务」**进 `TaskListView` | 结果写入该 Bot 私聊并发站内通知；可用 `execution_mode=owned` 桥接持续任务 |
| 持续任务 | `owned_tasks` / steps / waits / events（v27–v29），`/api/owned-tasks`（inputs、stop / continue / transfer、SSE 事件）；worker `vbowned` | 同上（`TaskDetailView`、`TaskApprovalView`） | 需要先设主 Bot 并开启「允许主动任务」；普通聊天不会自动建任务 |
| 待办 | 没有独立概念；「无日期」提醒基本等于待办 | — | 没有清单 / 子项 |

正式库现状（只读）：提醒 16 条，进行中 0 条；scheduled / owned 任务均为 0 条，迁移风险低。

痛点：同样是「要做的事」，分散在三个入口；Bot 任务藏在二级页；待办没有清单；通知点开后看不到 Bot 的执行进度和结果。

## 2. 目标与非目标

**目标**
1. 在「安排」一个 Tab 里看全「我要做的、到点提醒的、交给 Bot 做的」。
2. 一种事项、一个创建入口、一个先看后改的详情页。
3. 在事项里直接看到 Bot 任务的业务进度和结果。
4. 旧接口与旧客户端继续可用；迁移幂等、迁移前自动备份。
5. 可见界面改动尽量小：沿用现有列表与分组样式。

**非目标**
- 不合并 scheduled / owned 的执行引擎、租约和队列。
- 不做日历视图、协作共享、APNs（仍按 R3）。
- 不展示 Bot 之间的委派、步骤、租约、token 等内部细节。
- 不改 frontend/web。

## 3. 概念模型（推荐：一种事项 + 属性）

| 属性 | 含义 | 来源字段 |
|---|---|---|
| 标题 / 备注 | — | `title` / `note` |
| 时间 | 可选；有时间算「计划」，无时间算「待办」 | `due_utc`、`all_day`、`timezone` |
| 重复 | RRULE 子集（沿用） | `rrule` |
| 通知 | 到点本地通知（沿用） | `notify`、`alert_offsets` |
| 清单 | 一层子项，可逐项勾选（新增） | `reminder_checklist`（新表） |
| 完成 | 勾选完成，或 Bot 任务完成后自动完成 | `status`、`completed_at` |
| 负责人 | 我 / 某个 Bot | `assignee_bot_id` |
| 执行 | 交给 Bot 时关联到一条周期或持续任务 | `task_kind` + `task_id`（新增） |
| 来源 | 手动 / 某个对话 / 群 / 发现 | `created_by`、`source_bot_id`、`source_message_id`，新增 `source_kind` |

「提醒、待办、Bot 任务」都只是**视图分组**，不是三种数据类型：
- **待办**：没有时间。默认不通知。
- **计划 / 提醒**：有时间。默认通知。
- **Bot 任务**：有关联的执行任务。

为什么不分成三种类型：创建时用户不需要先选类型；一件事可以先当待办、后来加时间、再交给 Bot，不用迁移数据；现有提醒表已经覆盖大部分属性。

为什么不把 Bot 任务并进同一张表：两套任务引擎有租约、重试、预算和批准续跑，合并的风险和工作量都大，用户也得不到额外好处。

## 4. 数据模型与迁移（schema v37）

- `reminders` 新增可空列：`task_kind TEXT CHECK(task_kind IN ('scheduled','owned'))`、`task_id INTEGER`、`source_kind TEXT`（manual / chat / group / feed）、`checklist_done INTEGER DEFAULT 0`、`checklist_total INTEGER DEFAULT 0`（列表展示用的冗余计数）。
- 新表 `reminder_checklist(id, user_id, reminder_id → reminders ON DELETE CASCADE, text, done, position, updated_at)`。
- 新增索引 `(user_id, task_kind, task_id)`，唯一约束：一条任务最多关联一个事项。
- **回填**：每条未删除的 `scheduled_tasks`、以及未关联周期任务的 `owned_tasks`，各生成一条关联事项：
  - `notify=0`，标题取 title 或 goal；
  - `assignee_bot_id` 取任务的负责 Bot；
  - 周期任务把 `next_run_at_utc` 写入 `due_utc`，持续任务不写时间。

  当前正式库这两类任务为 0 条，回填主要用于测试库和以后的环境。
- **兼容**：
  - `/api/reminders` 返回结构不变，只增加字段；
  - 关联了任务的事项在旧接口中照常出现，旧客户端当作普通提醒显示；
  - 旧的 scheduled / owned 接口不变。
- 和以往一样，迁移前生成 `.bak-before-v37-*` 备份；迁移可重复执行。

## 5. 后端 API

- `GET /api/items?view=today|planned|todo|bot|done&bot_id=&cursor=`：聚合列表。每条事项附带任务摘要：状态（业务词）、下次执行、最近一次结果摘要、是否等你处理。
- `POST /api/items`：一次创建事项。如果带 `task` 字段（Bot、指令、一次 / 周期 / 持续），在同一个事务里创建 scheduled 或 owned 任务并关联；需要幂等键 Idempotency-Key。
- `GET / PATCH /api/items/{id}`；`POST /api/items/{id}/complete|reopen|snooze|skip`（复用提醒的状态机）。
- `PUT /api/items/{id}/checklist`（整组替换，带 expected_version），或 `PATCH .../checklist/{cid}` 单项勾选。
- 任务操作代理：`POST /api/items/{id}/task/pause|resume|run|stop|continue|input`，内部转给现有服务；不暴露 step、lease、token。
- `DELETE /api/items/{id}?scope=occurrence|series&task=stop|keep`。
- 同步规则：
  - 持续任务完成 → 关联事项自动完成；
  - 任务被删除 → 事项保留，但解除关联并标注「任务已结束」；
  - 周期任务每次执行后更新事项的下次时间。

  这些都由后台 worker 写回，通过现有 notification_events 通知客户端刷新。
- 权限：Bot 可见和可管理的范围沿用 §5.2；给 Bot 建任务仍要求主 Bot 及「允许主动任务」等现有检查。

## 6. iOS 界面

**Tab**：名称改为「安排」（决策 2），图标不变，大标题「安排」。顶部分段「提醒 / 通知」保留：第一段为事项列表，第二段为通知中心。

**列表**：沿用现有的分组列表，只调整分组：
- 今天（含逾期）
- 计划（未来，有时间）
- 待办（无时间；原「无日期」改名）
- Bot 任务（有关联任务，显示状态胶囊，如 待执行 / 正在处理 / 等你处理 / 已完成 / 未完成）
- 已错过、已完成（默认折叠，保留现有逻辑）

左上筛选沿用（全部 / 我 / Bot 创建 / 某 Bot），新增「仅 Bot 任务」。行内显示清单进度（如 2/5）。勾选圆点完成，沿用现有交互。

**创建（＋）**：沿用现有编辑表单，扩展为：
- 标题；
- 「日期与时间」开关（关闭即待办）；
- 重复；
- 通知；
- 清单（逐行添加）；
- 「交给 Bot 执行」开关。打开后选择 Bot、填写要做什么，再选执行方式：到点做一次 / 按周期 / 持续直到完成（持续模式需主 Bot 权限，没有权限时说明原因并给出设置入口）。

**详情（先看后改）**：点行进入只读详情。
- 内容：标题、时间与重复、通知、清单（可直接勾选）、来源（「来自 与 X 的对话」，点开定位到原消息）。
- Bot 任务区块：当前状态、下次执行、最近结果摘要（「查看全文」进入该 Bot 私聊对应消息）、执行记录（时间 + 成功 / 失败）。「等你处理」时显示问题和回答输入，复用 `TaskApprovalView`。
- 右上「编辑」进入表单。
- 底部操作：
  - 暂停 / 继续、立即执行（周期任务）、停止（持续任务）；
  - 删除：**红色**，二次确认。有关联任务时确认面板提供「删除并停止 Bot 任务」（红色）和「仅删除这一次」（重复事项）。

**通知点按**：
- 提醒通知 → 打开该事项详情（与 §9.5 一致）；
- 任务结果通知 → 打开事项详情，并定位到结果区块；
- 需要你处理 → 打开详情，并聚焦到回答区块；
- 找不到对应事项时，退回到通知中心对应条目。

**旧入口**：对话菜单和 Bot 编辑页的「任务」改为打开「安排」Tab，并预先按该 Bot 筛选。`TaskListView` 逐步下线，不留重复页面。

## 7. 对话与 Bot 如何创建、更新事项

- 保留现有工具名 `create_reminder` / `list_reminders` / `manage_reminder`（兼容），参数增加：可不填时间（即待办）、`checklist`。
- 新增 `propose_task`：Bot 在对话里提议「交给我定期 / 持续做」，生成**确认卡片**（复用 pending_actions），用户点「确认」后才创建任务和关联事项；普通聊天仍不自动建任务（沿用 owned README 的约定）。
- 来源：工具调用自动写入 source_kind=chat、source_bot_id、source_message_id。群聊来源只记录群和消息，不展示 Bot 之间的过程。
- Bot 更新：只能管理自己创建或被指派的事项（§5.2）。完成 / 改期写入 `reminder_events`，详情的「记录」里可以看到是谁、在什么时候改的。
- 任务结果：仍写入负责 Bot 的私聊，并发通知；事项详情只显示摘要和跳转链接。

## 8. 遵守的 Boss 规则

- 可见改动最小：同一个 Tab 位置（改名「安排」）、同样的列表样式，只调整分组名并增加一个分组；详情页是新的，但组件沿用现有。
- 删除等破坏性操作一律红色并二次确认。
- 不展示 Bot 之间的内部过程（委派、步骤、租约、token、重试细节）。
- 文档和代码在同一个 PR 更新（STATUS、CHANGELOG、REMINDER_PUSH_DESIGN 增补、测试用例）。

## 9. 分期与工作量（人日为估算）

| 阶段 | 内容 | 估算 |
|---|---|---|
| **P1 统一事项** | v37 迁移 + 清单表 + `/api/items` 列表 / 详情 / 清单；iOS 分组调整（待办、Bot 任务只读区块）、先看后改详情页、清单、通知点按到详情；旧入口改为预筛选跳转 | 4–5 |
| **P2 交给 Bot** | 创建表单「交给 Bot 执行」（一次 / 周期 / 持续）、任务操作代理、详情内等你处理与结果、worker 写回同步、`propose_task` 确认卡片、下线 `TaskListView` | 4–5 |
| **P3 打磨** | 搜索、今天小组件 / 角标、自定义重复与提前提醒（R2 遗留）、批量完成 / 删除、已完成归档策略 | 3–4 |

每阶段都包含后端测试、Swift 测试、模拟器构建、正式库备份与迁移、Boss 验收。

## 10. 风险

1. **双写一致性**：事项与任务状态不一致。对策：任务表为准，事项只存链接和展示缓存；由 worker 写回，配合定期对账。
2. **删除语义**：误删事项导致任务停掉，或任务变成孤儿。对策：确认面板写明后果，默认「删除并停止」。
3. **重复通知**：周期任务的到点提醒和结果通知同时出现。对策：关联任务的事项默认 notify=0，只发结果通知。
4. **权限越界**：Bot 通过事项看到别的 Bot 的任务。对策：沿用 §5.2，接口层统一过滤，并补测试。
5. **旧客户端**：旧版会把关联任务的事项显示成普通提醒，并可能把它勾掉。对策：旧接口对这类事项的 complete 改为只完成事项、不影响任务，并写日志。
6. **范围膨胀**：日历、共享等需求。对策：明确列为非目标，放到 P3 之后再议。

## 11. Boss 决策（2026-10-18 定稿）

除第 2 项外均按推荐（A）执行；第 2 项定为「安排」。

1. **数据模型**：A. 扩展现有提醒表为统一事项，并关联任务引擎（**已定**）；B. 新建 items 表并迁移提醒；C. 三类全部合并成一张表。
2. **Tab 名称**：**定为「安排」**（原备选：保持「提醒」/「事项」/「待办」）。
3. **列表结构**：A. 保留「提醒 / 通知」分段，列表分组为 今天 / 计划 / 待办 / Bot 任务 / 已完成（**已定**）；B. 顶部 5 段分段控件；C. 只用筛选菜单。
4. **待办定义**：A. 没有时间的事项即待办，默认不通知（**已定**）；B. 单独的待办类型。
5. **清单**：A. P1 只支持一层子项（**已定**）；B. 支持多层子任务。
6. **对话里建 Bot 任务**：A. Bot 提议，用户点确认卡片后才创建（**已定**）；B. 允许 Bot 直接创建。
7. **删除关联事项**：A. 默认「删除并停止 Bot 任务」，红色确认（**已定**）；B. 只解除关联，任务继续。
8. **任务结果通知点按**：A. 打开事项详情的结果区块，可再跳转到对话（**已定**）；B. 直接打开对话。
9. **旧的 Bot「任务」入口**：A. 改为跳转「安排」Tab 并按该 Bot 筛选（**已定**）；B. 保留独立任务页。
10. **已完成保留**：A. 默认折叠，显示最近 30 天，更早的自动归档、可搜索（**已定**）；B. 全部保留在列表中。
11. **执行节奏**：A. Boss 确认后先做 P1，验收后再做 P2（**已定**）；B. P1、P2 一次做完。
