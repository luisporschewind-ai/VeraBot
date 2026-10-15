# 2026-10-15 · Bot 动态开场词 Phase 1 验证

规格：[bot-opening-message](../specs/bot-opening-message.md)

## 范围

- 后端 schema v32：`bots.opening_templates`；创建 / PATCH 人设后后台生成；`POST .../opening-templates/ensure` 懒生成（mock DeepSeek）。
- iOS：`OpeningMessageComposer` 本地组装（时段 / 日子 / 节气 / 节假日 / 关系阶段 / 称呼）；空对话气泡只改文案。
- `frontend/web` 未改。

## 已跑

| 项 | 结果 | 环境 |
|---|---|---|
| `uv run python scripts/test/opening_message_test.py` | 10/10 通过 | Linux 云代理 |
| `uv run python scripts/test/sql_layer_check.py` | SQL-LAYER-01/02 通过 | 同上 |

## 未跑（本环境无 Swift / Xcode）

- `swift test`（`OpeningMessageTests`）
- 模拟器空对话肉眼验收（初识 / 清空后再进 / 周五晚 / 深夜 / 霜降）

## 已知边界

见 [known-issues](2026-10-14-known-issues.md)「动态开场词」节：逐条删光消息仍可能走初识文案；天气维度属 Phase 2。
