# 修复短 Bot 回复误折叠

日期：2026-10-16

## 问题与定位

用户在 iPhone 主辅机验收后反馈：回复内容不长，但仍被折叠。

只读检查当前本地消息，发现一条 455 字、16 行、约 398 加权字的回复，因为列表换行被估算为约 32.5 行，单独超过旧规则的 28 行阈值，触发了折叠。旧逻辑没有短回复保护，文字不多但排版松散时容易误判。

## 修复

- 在 `LongReplyCollapse.shouldCollapse` 增加优先条件：不超过 500 个非空白字素时始终完整展示。
- 字数按 Swift `Character` 计算，空格、换行不计入；emoji 和组合字符各算一个字素。Markdown 标记仍计数。
- 超过保护长度后沿用原先的 28 行排版估算 / 500 加权字阈值，以及 200 字 / 8 行预览和手动展开行为。
- 检查最多数到第 501 个非空白字素；空白特别多、正文很少时会扫描到全文末尾。没有增加全文 Markdown 解析或预排版。
- 同步规格、前端 README，真机修复版版本号更新为 0.1.0 (2026101606)。保留同一工作区此前的附件修改。

## 验证

- 修复前，新增格式化短回复、500 字边界、空白填充、emoji 字素用例复现误折叠；修复后通过。
- 原有按行数、加权字数、表格/列表、代码块、截断点测试样例增加必要正文，使其超过新增保护长度，继续检验对应算法，不绕过原断言。
- 完整 Swift 测试：Swift Testing 354 项及 XCTest 1 项通过。
- 静态独立复核未发现 Swift 正确性或测试回归；复核指出的旧规格说明已同步修正。
- 真机 `xcodebuild` 成功，日志 `/tmp/verabot-short-reply-device-build.log`，应用版本 0.1.0 (2026101606)。
- 主机 iPhone 12 Pro Max、辅机 iPhone 11 均覆盖安装成功；分别通过设备应用清单确认安装版本为 2026101606，保留应用数据。
- 安装与版本证据：`/tmp/verabot-short-primary-install.json`、`/tmp/verabot-short-secondary-install.json`、`/tmp/verabot-short-primary-app.json`、`/tmp/verabot-short-secondary-app.json`。
- `git diff --check` 通过；测试日志 `/tmp/verabot-short-reply-tests.log`。未操作手机对话，留待用户验收。

## 验收边界

继续安装到同一主机 iPhone 12 Pro Max、辅机 iPhone 11，保留数据。不代替用户打开对话或执行验收。

用户可重新查看此前被误折叠的短回复，确认直接展示全文；再核对一条较长回复仍可展开/收起。
