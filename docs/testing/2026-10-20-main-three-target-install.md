# Main 三端安装记录 · 2026-10-20

## 范围与代码状态

- 目标分支：本地 `main`，HEAD `3b38904`（`docs: 记录 v39 正式库迁移、Main API 重启与模拟器安装`）。
- 已盘点五个 Git 工作树：Tetris、资料库、个人动态、打 Bot、Bot 漂流瓶。均无未提交修改；其当前有效内容已在本地 Main 历史中。Tetris、资料库、个人动态和漂流瓶分支头均为 Main 祖先；打 Bot 的工作树分支较旧，功能由 Main 提交 `e7d0900` 整合，Main 版本保留了后续验收文档更新。
- 没有额外代码需要再次提交或合并；本次只补充本交付记录与 `STATUS.md`。本地 `main` 相对 `origin/main` 为 ahead 6 / behind 4；本次没有拉取或推送远端。

## 构建与安装

- Xcode `VeraBot` Debug 构建成功，源码来自本地 Main。
- App 版本：`0.1.0 (2026101701)`，Bundle ID：`com.verabot.app`。
- iPhone 17 / iOS 26 模拟器：已安装并启动。
- iPhone 11：已安装签名包，未由本轮启动。
- iPhone 12 Pro Max：已安装同一签名包，未由本轮启动。
- 实体设备安装由 `devicectl` 返回 `App installed` 确认。App 二进制 SHA-256：`b09a8ccd8811f466c979f52c02324b1a788d2e9ee770f4fcfb949260586929aa`。

## 验收边界

- 本轮进行了构建和安装；没有运行测试套件。
- 安装/模拟器启动不代表三端功能验收通过。用户可在 Main 的三端继续手动验证；人工验收结果尚未记录。
