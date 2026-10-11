# 群聊首版设备交付 · 2026-10-11

用户授权汇总进度并运行到现有模拟器、主机和备机；明确两台真机接现有正式后端验证真实 Bot。代码来源为独立群聊工作树，基础提交 `84e0dc3`；不包含主工作区本轮未提交的语音播放等并行改动。未提交、合并或推送群聊代码。

## 当前进度

G0 界面、G1 数据与协议、G2 后端执行和 iOS 接线已实现；G3 自动验证及主要模拟器交互通过。包括建群、默认回应、顶部点名、顺序讨论、停止、仅重试失败成员、后台中断和重启偏好。用户反馈的「保存 C 仍由 B 回应」代验收时未复现，原因仍未确认。

历史自动证据：后端 74 项；Swift 214 Swift Testing + 1 XCTest；模拟器构建通过。详情见 [G3 验收记录](2026-10-11-bot-group-chat.md)。真实模型体验/用量/耗时，以及管理、换账号、删除成员和完整私聊设备回归仍待验收。

## 后端交付

- 同一 Mac 的现有服务地址 `http://192.168.0.104:8000`，原服务已有局域网监听，本次沿用。
- 运行独立群聊工作树的 `backend/verabot`，使用主工作区现有 `.env`、`backend/data`、JWT 和数据库；不输出或复制提供者密钥。
- 启动前 SQLite 在线备份：`/Users/admin/Desktop/VeraBot-v0.1/backend/data/verabot.db.bak-before-v20-20261011-184515`。先在备份副本演练 v19→v20，原有 users/bots/messages 数量一致、integrity_check=ok。
- 正式库现已迁移 v20，完整性检查正常；`127.0.0.1` 与 `192.168.0.104` 的 OpenAPI 均含 7 条群聊路由。未使用模拟提供者覆盖此服务。
- 当前服务 PID 96911，记录到主工作区 `backend/data/server.pid`；日志 `backend/data/group-server.log`。隔离模拟服务仍在本机 8093，数据独立。
- 后端运行从独立工作树导入代码；直接用主线旧代码重新启动将缺少群聊接口。后续重启可在主工作区 `backend` 使用：

```sh
VERABOT_DATA_DIR=/Users/admin/Desktop/VeraBot-v0.1/backend/data \
VERABOT_DB=/Users/admin/Desktop/VeraBot-v0.1/backend/data/verabot.db \
PYTHONPATH=/Users/admin/.codex/worktrees/bot-group-chat-preview/VeraBot-v0.1/backend \
./start.sh --detach
```

重启前按现有停止流程结束当前服务；不可同时启动多个共用库的群聊 worker。

## 设备

- 现有模拟器：VeraBot G3 验收，F02AB43D-CB5B-4F7E-AAF4-679D2EEB0E3B；原地安装已验收的模拟器构建并启动，截图确认助理页和群聊入口。保留隔离模拟账号与历史，连接本机 8093。
- 主机：iPhone 12 Pro Max，0C62BF91-5AB3-5DC7-9706-586C85E51FC1；现有服务器偏好 `http://192.168.0.104:8000`，保留账号与数据。
- 备机：iPhone 11，FB04D26C-3E70-5121-A891-4717A6AA665C；同一现有服务器偏好，保留账号与数据。
- 真机 Debug / arm64 签名构建 `BUILD SUCCEEDED`，codesign 校验通过；同一包依次安装两台真机，devicectl 安装/启动均退出 0。主机进程 88067、备机进程 37717，随后进程列表均确认对应新安装路径。
- 后端收到主机 `192.168.0.103` 与备机 `192.168.0.100` 的 `/api/me`、`/api/bots` 等请求，均返回 200；说明保留登录且与现有后端通信正常。未替用户发送正式账号的真实模型消息，讨论质量仍待设备验收。
- 构建日志 `/tmp/vb_group_device_build.log`；安装、启动和进程证据 `/tmp/vb_group_{primary,secondary}_{install,launch,processes}.json`；设备包 debug dylib SHA-256 `42d57ef0b547c16097ef2ca934ff38423f5c394473524f2935af934579504764`。
- 实际运行与连通性已确认；不把安装/启动记录当作真实群聊体验验收。

## 本地 main 集成

设备交付后用户明确授权提交群聊并合入 main。群聊提交包含实现、回归、设计/实施文档与验收证据，其他语音播放改动保持未提交；不推送远端。合并前回归日志 `/tmp/vb_group_premerge_swift.log` 与 `/tmp/vb_group_premerge_{group_store,group_runtime,group_lifecycle,multi_agent,status_event,auth_stability,llm_body}.log`。主工作区纳入群聊后，正常 `backend/start.sh --detach` 即可导入群聊实现；上方 PYTHONPATH 启动说明保留为此前工作树交付记录。

### main 合并结果

群聊实现提交 `2978090` 已本地合入 main。原有语音播放实现、测试、设计文件逐字节恢复；App 和文档的共用改动并存，语音部分仍未提交。合并后工作区完整 Swift 224 Swift Testing + 1 XCTest、后端 74 项通过（224 包括保留的 8 项语音测试；群聊独立提交为 216 + 1）。日志 `/tmp/vb_group_main_swift.log`、`/tmp/vb_group_main_*.log`。后端已从主工作区代码启动，PID 99314，现有配置与数据保持；本机和局域网健康/群聊路由正常。原工作树保留用于隔离模拟验收，不再是 8000 服务的代码来源。未推送。
