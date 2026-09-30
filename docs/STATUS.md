# 项目状态 (STATUS) — 2026-09-30

## v0.1.0 · 原型验证完成 (Prototype validated, feasible)

| 项 | 状态 |
|---|---|
| 结论 | ✅ 原型验证完成，方案可行：多 Bot 私聊 + 多 Agent 协作 (权限 / 隔离 / 护栏 / 审计) + SSE 流式 + 工具调用在 iOS 模拟器 + 本机后端上端到端跑通 |
| 版本 | git tag `v0.1.0`；后端 `verabot 0.1.0` (schema v2)；iOS `0.1.0 (1)` |
| 测试 | **91 条用例：通过 90 / 失败 0 / 跳过 1** (TC-31 语音输入按要求跳过)，见 [TEST_CASES_v0.1.md](testing/TEST_CASES_v0.1.md)；重构后回归见同文档末尾 |
| 交付 | 后端 `dist/VeraBot-backend-v0.1.0.zip` (一键启动)；iOS Xcode 工程 + SPM 本地包；见 [DELIVERY.md](ops/DELIVERY.md) |
| 运行环境 | macOS Intel (MacBook Pro 13" 2018)、Xcode 26.0.1、iPhone 17 模拟器 (iOS 26)、Python 3.12 (uv)、DeepSeek `deepseek-chat` |

## 1. 已完成功能 (Features done)

| 模块 | 状态 | 说明 |
|---|---|---|
| 账号 Accounts | ✅ | 注册 / 登录 (bcrypt + JWT)，Token 持久化，失效自动退出，设置页退出登录 (二次确认) |
| 租户隔离 Isolation | ✅ | 所有查询带 `user_id`，越权 (IDOR) 返回 404 |
| Bot 管理 | ✅ | 创建 (＋)、编辑 (Bot 详情 / 长按「编辑与权限」)、左滑删除；软上限 20 (`MAX_BOTS_PER_USER`) |
| 流式对话 SSE | ✅ | 逐 token 渲染、工具卡片、交接 Trace 卡片、错误气泡 |
| 记忆 Memory | ✅ | 每 Bot 独立，最近 20 条；清空对话 (二次确认) |
| 工具 Tools | ✅ | 天气 (Open-Meteo)、创建 / 查询提醒、`ask_bot` |
| 多 Agent 协作 | ✅ | 工具白名单、委派白名单、接受委派、上下文隔离、深度 / 环路 / 单轮上限 / Token 预算、审计日志、协作记录页 |
| 每日 Token 预算 | ✅ | 超额 429，委派也被拒 |
| 提醒 Reminders / 用量 Quota | ✅ | Tab 页；提醒只落库，不推送 |
| 语音输入 Voice input | ✅ (未实测) | Web `/api/transcribe`；iOS Speech 框架 |
| 语音播放 TTS | ✅ | 用户 + Bot 气泡 🔊，本机 TTS；设置里可关闭 |
| 设置页 Settings | ✅ | 首页头像入口；账号 → 语音 → 关于 |
| 导航 Navigation | ✅ | 二级页面隐藏 Tab 栏；对话标题 → Bot 详情 sheet；首页原生圆形按钮 |
| 键盘 Keyboard | ✅ | 输入栏随键盘上移、点空白 / 下拉收起、表单 next、多行人设 / 指令、sheet 保存后布局正常 |
| 附件 Attachments | 🟡 占位 | ＋ 菜单：图片 / 相机 / 文件「即将支持」(禁用) |

## 2. 已知限制 (Known limits)

- **iOS 与 Web 不对等**：Web SPA 没有迭代 2 的 iOS UI 改动 (权限编辑、协作记录、设置页、TTS)，只作为 API 验收客户端。
- **提醒不推送**：没有 APNs / 本地通知。
- **记忆**：滑动窗口 (最近 N 条)，没有摘要 / 向量检索。
- **安全**：Token 存 UserDefaults / localStorage (生产应改 Keychain / HttpOnly Cookie)，没有刷新 Token、没有速率限制 (Rate limit)，CORS `*`，ATS 允许本地 HTTP。
- **云端 TTS**：只是占位 (stub)，设置里置灰。
- **后端不会开机自启**：Mac 重启后需要重新运行 `backend/start.sh --detach` (或双击 `start.command`)；日志在 `backend/data/server.log`。
- **Docker 未实测**：`Dockerfile` / `docker-compose.yml` 已提供，`docker compose config` 校验通过；但测试机的 Docker daemon 未运行，镜像没有实际构建 / 运行过。
- **Bot 详情 sheet 内没有键盘「完成」按钮** (KB-12 修复所致)：用 下拉表单 / 保存 / 关闭 收起键盘。
- **文案过时**：新建 Bot 表单页脚仍写「创建后可在对话页右上角「Bot 设置」中开启」，现在的入口是「对话页点标题 → Bot 详情」(待改，重构时按「不改行为」原则未动)。
- **截图过时**：`R34_form_keyboard` 仍显示已移除的键盘工具栏「完成」；`R11_settings` 是旧的分组顺序 (语音在前)，现为账号在前 (见 R31)。
- **来源不明的文件**：`frontend/ios/VeraBot/File.txt` (8 字节，内容「QA回归」)，重构时原样保留，待确认是否删除 (NEW-03)。

## 3. 未测 / 仅代码审查 (Untested / code review only)

| 项目 | 状态 |
|---|---|
| TC-31 语音输入 (`/api/transcribe`、iOS 麦克风) | 跳过 (按要求) |
| KB-04 交互式下拉收起键盘 | 代码审查 (模拟器鼠标拖动难以复现) |
| KB-08 进入后台收起键盘 | 代码审查 |
| KB-09 登录 / 新建 Bot 表单键盘行为 | 代码审查 |
| TC-07 Token 失效、TC-29 ＋ 菜单、TC-30 断网气泡 | 沿用迭代 1 结果，迭代 2 未重新点测 |
| 真机 (Real device) | 未测，只在 iPhone 17 模拟器 (iOS 26) 上测试 |
| iOS 17 / 18 旧系统 | 未测 (`defaultScrollAnchor` 等 iOS 18+ API 已做版本判断) |
| 深色模式 (Dark mode)、动态字体 (Dynamic Type)、iPad | 未测 |

## 4. 下一步 (Next steps)

1. 修正新建 Bot 表单页脚的过时文案；重新截 R34 (无键盘工具栏) 和 R11。
2. 补测 TC-07 / TC-29 / TC-30、KB-04 / 08 / 09，以及真机测试 (语音输入、TTS、键盘)。
3. 提醒推送：本地通知 (UNUserNotificationCenter) 或 APNs。
4. 附件：图片上传 + 多模态模型。
5. 云端 TTS：后端 `/api/tts` + 实现 `CloudTTSEngine`。
6. 安全加固：Keychain、刷新 Token、Rate limit、HTTPS / 移除 ATS 例外、收紧 CORS。
7. 后端常驻：launchd plist (开机自启 + 崩溃重启)；实测 Docker 镜像。
8. 记忆：长对话摘要压缩 (summarization)。
9. Web SPA 跟进 iOS 的权限编辑 / 协作记录 UI (如果还需要 Web)。
10. 确认 `frontend/ios/VeraBot/File.txt` 是否删除 (NEW-03)。
11. 配置远程 Git 仓库 (目前只有本地仓库) 和 CI (后端 mock 测试 + `swift test` + xcodebuild)。
