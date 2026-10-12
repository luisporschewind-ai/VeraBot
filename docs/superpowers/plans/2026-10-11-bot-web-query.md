# Bot 联网查询 Implementation Plan

> 后续用户明确要求无需搜索 key；Tavily 配置方案已被替换。当前实现见 [无 key 执行修订](2026-10-11-web-query-no-key.md) 与无 key 验收记录。以下保留初版测试历史。

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 为私聊 Bot 交付可追溯的新闻/资料查询与天气时效。
**Architecture:** 工具复用 registry/router/permissions；提供商与归一化服务独立；来源随 traces 保存，iOS 根据真实结果显示。
**Tech Stack:** Python 3.12, httpx, SQLite, Swift 6, SwiftUI；不添加运行时依赖。
**Spec:** ../specs/2026-10-11-bot-web-query-design.md

## Global Constraints
仅 depth=0；搜索 2 次、读取 3 次、累计 30 秒；单请求 12 秒；日额度默认 50；结果 5 条、摘要 500 字、正文 4000 字、缓存 300 秒/128 条。密钥仅服务端。保留主工作区语音相关改动；不合并、推送或发布。

## Review Focus
- 查询返回的恶意指令/关闭标记不能绕过本轮写操作拦截（Task 3）。
- 并发查询与重启不能突破每日额度（Task 1）。
- 模型伪造 URL/结果编号不能被 reader 接受（Task 2）。
- 旧消息、重复来源、非法链接不能导致 iOS 崩溃或错误跳转（Task 4）。
- 缓存不能掩盖实际数据时间、新闻与用户刷新必须重查（Task 2/5）。

### Task 1: 查询契约与持久预算
Files: Create backend/verabot/db/web_store.py, backend/verabot/services/web/{__init__,policy}.py; Test backend/scripts/test/web_query_test.py.
Interfaces: reserve_request(user_id: int, bot_id: int, operation: str, limit: int) -> bool；public_url(value: str) -> str | None。
- [x] 测试：并发 8 次/额度 3 仅 3 次成功，按账户隔离；拒绝 localhost/私网/凭证/非 HTTPS/端口 URL。
- [x] 运行 unittest，确认新模块缺失导致失败。
- [x] 实现原子 audit_log 预约与 URL/参数验证。
- [x] 运行该测试，全部通过。

### Task 2: 搜索、缓存与结果读取
Files: Create backend/verabot/services/web/{provider,service}.py, backend/verabot/tools/web.py; Modify tools/{registry,__init__}.py, agents/permissions.py.
Interfaces: TavilyProvider.search(query, topic, time_range, domains) -> dict；extract(url) -> dict；service.search/read(ctx, ...) -> dict。
- [x] 测试固定端点请求与归一化、去重/截断、缓存隔离/刷新、turn 上限/超时、无结果、429/401/坏响应、伪造编号/跨 turn 与委派禁止。
- [x] 确认失败后实现适配器与工具注册；环境缺密钥明确不可用。
- [x] 运行 unittest 与已有工具相关回归。

### Task 3: 运行时权限与外部数据边界
Files: Modify agents/{runtime,prompts,tool_router}.py, api/routers/meta.py, services/plugins/catalog.py.
Interfaces: web schema 遵循已有白名单；tool_content 完整封装；写能力 taint 拦截。
- [x] 测试未授权零调用、来源 trace 落库/恢复、恶意文本封装完整、读网页后提醒/记忆禁止写、MCP 仍待确认。
- [x] 实现模型规则、API 标签、内置联网能力介绍与调用元数据；不自动开启任何 Bot。
- [x] 运行 web_query_test.py 与 MCP/委派/插件回归。

### Task 4: iOS 来源与联网状态
Files: Create VeraBotCore/WebSources.swift, VeraBotKitTests/WebSourcesTests.swift, Features/Chat/WebSourcesView.swift；Modify MessageRow.swift, TraceView.swift, PluginDetailView.swift, execution display mapping。
Interfaces: WebSource.sources(from: [ToolTrace]) -> [WebSource]，由真实 trace 推导，保留旧消息兼容。
- [x] Swift Testing：真实搜索/读取 trace 解码、去重、时间/缓存、非法链接拒绝、旧 trace 返回空。
- [x] 确认测试失败后实现来源投影与原生来源列表、权限入口说明。
- [x] swift test 全套与模拟器 build。
- [x] 模拟器 install/launch；人工 UI 验收单列。

### Task 5: 天气时效、配置与交付记录
Files: Modify tools/weather.py, backend/.env.example；Create docs/testing/2026-10-11-web-query.md；更新本计划与执行记录。
Interfaces: 天气保留原字段，新增 queried_at/fetched_at/cache_hit/timezone/source_url。
- [x] 测试天气缓存返回原 fetched_at、新 queried_at、主备源归一化、无数据失败。
- [x] 实现时间元数据、UI 时间展示与配置说明。
- [x] 运行适用后端离线回归、Swift 全套、git diff --check，独立审查；记录真实查询未验收项。

## Execution Ledger
- Ruling: 用户明确要求“规划好任务，开始执行”，直接在本轮原生执行；不追加方案确认。隔离工作区以 HEAD 创建，避免纳入语音未提交改动。
- Ruling: 首个适配器为候选 Tavily；P0 跨服务真实质量/费用比较暂缺凭据，交付可配置实现并明确记录这一验收边界。
- Ruling: 不新增 schema；使用既有 audit_log 在 BEGIN IMMEDIATE 中预约每日请求，避免与群聊 schema v20 发生不必要迁移。

- Ruling: 插件回归已有三处 schema 期望停留 v17（主代码为 v20），更新为迁移模块的当前 target；新增 builtin_web 的未配置状态不再被旧的“所有内置 ready”断言误判。

- Task 1–3: 已完成；22 项后端专项测试通过。来源随现有 traces 持久化，未新增 schema。
- Task 4: 来源模型与 UI 完成；219 Swift Testing +1 XCTest，通过；模拟器构建、安装、启动通过；截图确认登录页，联网页面仍待人工验收。
- Task 5: 天气时效与配置完成；扩大回归含既有失败，已在原工作区复现，详见 ../../testing/2026-10-11-web-query.md。
- 独立审查三项 P2 均修复并复核通过。P0 的真实提供商比较、真实模型/服务验收仍待凭据；P3 专项 API/持续关注为后续范围。

- 2026-10-11 用户调整：新闻默认国内优先、国际其次。已更新模型规则、工具说明和真实验收用例；不限定固定媒体名单。真实模型策略遵循与供应商覆盖仍待验收。
