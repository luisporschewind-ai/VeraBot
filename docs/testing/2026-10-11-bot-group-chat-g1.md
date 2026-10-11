# Bot 群聊 G1 数据与协议验证记录

日期：2026-10-11。用户在 G0 预览后回复「OK，继续下一阶段」，本次完成实施计划 Task 2 / Task 3。

## 范围与环境

- 工作树：`/Users/admin/.codex/worktrees/bot-group-chat-preview/VeraBot-v0.1`，基础提交 `84e0dc3`。
- 新增逻辑位于此工作树；未提交、合并或推送。未启动正式后端、迁移正式数据库或使用真实模型。
- 后端测试使用临时 SQLite，通过原目录已有 `.venv/bin/python` 提供依赖，导入工作树代码。PATH 无 `uv`；命令依赖问题不作为测试先失败证据。
- G0 界面继续展示模拟数据。此阶段没有正式网络接线，不代表用户交互验收完成。

## 已实现

- v19 → v20 迁移：四张独立群表、稳定成员身份与名称/外观快照；Bot 删除后保留成员及旧回复，默认回应者回退，零可用成员只读。
- REST：群创建/列表/详情/重命名/默认回应者/删除、消息分页/清空、轮次查询/取消标记；他人对象返回 404。
- 约束：2–4 个不同的本人 Bot、最多 10 群、群名 1–64、消息 1–2000；短 BEGIN IMMEDIATE 事务与 running 部分唯一索引保障同群一轮。
- UUID 幂等：相同请求返回 request_exists 与原 turn_id，不同内容返回 idempotency_conflict；其他请求同时领取返回 group_busy，不插入多余消息。
- 回复内容、终态和已知用量同事务保存，重复终结不会重复计入 usage_log，kind 为 group_chat。
- Swift 模型与独立 GroupChatAPI；私聊 ChatEvent / VeraBotAPI 保持兼容。事件校验群/轮次及必要消息/成员标识。
- reducer 分离成员气泡，重复 start 不重复插入，message_done 替换全量文本；拒绝错群、旧轮、错成员与终态后的文本，status 不进入正文。
- 群请求复用 call / AuthSession / 刷新，并检查原会话代次。401 保持请求体和 UUID；409 查询原轮次并抛出 GroupRequestExists 快照，供 ViewModel 恢复。
- SSE 按原始字节保留空行和多行 data。EOF 缺 turn_done 返回中断，恢复使用服务器快照。

## 验证

| 检查 | 结果 |
|---|---|
| 后端先失败 | create_group 业务断言 404 != 201，退出码 1 |
| Swift 先失败 | 事件/reducer 共 32 个业务断言失败，之后补实现 |
| group_store_test.py | 13/13：v19 副本迁移两次、隔离、限制、并发、幂等、取消归属、快照、计费一次与 104 消息分页完整遍历 |
| multi_agent_test.py | 25/25 |
| status_event_test.py | 8/8 |
| auth_stability_test.py | 6/6 |
| llm_body_test.py | 6/6 |
| 群 Swift 测试 | 11 项：事件 fixtures、坏身份、删除成员、编码、reducer、恢复、SSE、刷新/换账号/409 |
| Swift 全量 | 206/206 |
| iOS Simulator build | 最终工作树 BUILD SUCCEEDED；iPhone 17 / iOS 26 |
| SQL 分层 | 全库检查失败；HEAD 基线与当前均 100 条，新增 0 |
| git diff --check | 通过 |

后端命令，在仓库根目录执行：

```sh
/Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python backend/scripts/test/group_store_test.py
```

Swift：在 `frontend/ios/Packages/VeraBotKit` 执行 `swift test --filter GroupChat` / `swift test`。
构建：在 `frontend/ios` 执行 `xcodebuild -project VeraBot.xcodeproj -scheme VeraBot -sdk iphonesimulator -destination 'platform=iOS Simulator,id=6FD1E62D-DA65-42B1-81F5-554042006671' -derivedDataPath /tmp/verabot_group_preview_dd build`。

完整日志：`/tmp/verabot_group_store_green.log`、`/tmp/verabot_group_swift_all.log`、`/tmp/verabot_group_g1_final_build.log`。持久摘要见 [G1 evidence](assets/2026-10-11-group-chat/g1-evidence.txt)。

## G2 / G3 待办

- G2 尚未开放后端 POST chat/retry；客户端流式方法只通过网络 mock 验证。
- stop 当前只保存 cancel_requested；模型取消、离开/断线处理、启动时遗留 running 轮次转为 interrupted，由 G2 runtime 完成。
- 群上下文、Bot 顺序调用、前一位完整回复传递给下一位、超时/预算、部分失败和重试仍待实现。
- G3 再将真实群列表/创建/历史/发送接入预览布局，由用户验收真实讨论体验。
