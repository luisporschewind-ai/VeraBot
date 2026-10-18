# 当前游戏版本双 iPhone 交付

日期：2026-10-18。用户要求：运行最新版本到主机与备机。

## 构建来源

- 当前 main 工作区，HEAD 为 `6c83716e47785a4f93ba94aeadf96e9420febe85`，包含未提交的右侧 Bot 布局、贪吃蛇与按钮实体触感改动。
- 使用 Xcode 为 `generic/platform=iOS` 重新构建 Debug 真机包，自动签名；`xcodebuild` 退出码 0，`BUILD SUCCEEDED`。
- Bundle ID `com.verabot.app`，版本沿用 `0.1.0 (2026101701)`，没有修改版本号；两台手机使用同一个新构建产物。
- 构建日志：`/tmp/verabot-device-20261018-games-build.log`；安装包：`/tmp/verabot-device-20261018-games/Build/Products/Debug-iphoneos/VeraBot.app`。
- 没有卸载 App 或清理数据，没有提交、推送、后端部署或数据库迁移。

## 设备结果

- 主机 iPhone 12 Pro Max：覆盖安装成功；首次启动被系统以 `Locked` 拒绝，用户解锁后再次启动成功，并查询确认 VeraBot 进程 `68767` 仍在运行。
- 备机 iPhone 11：覆盖安装、前台启动成功；再次查询确认 VeraBot 进程 `46357` 仍在运行。
- 安装/启动证据：`/tmp/verabot-games-main-install.json`、`/tmp/verabot-games-main-launch.json`、`/tmp/verabot-games-main-process-check.json`、`/tmp/verabot-games-backup-install.json`、`/tmp/verabot-games-backup-launch.json`、`/tmp/verabot-games-backup-process-check.json`。

## 验收边界

本次是最新代码构建、安装与启动交付；游戏内布局、滑动/连点、真实震动、前后台暂停等仍需用户手动验收。音效和 Bot 云端接管仍处于方案阶段，没有随包新增实现。本记录更新后，此前任务记录中的“真机未更新”属于当时的交付状态。
