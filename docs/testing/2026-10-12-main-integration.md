# 2026-10-12 全工作区整合与设备交付

## 授权与来源

用户授权提交全部工作区及工作树代码、对齐文档、合并到本地 main，并安装到模拟器与备机。本次未请求推送远端，也未请求删除工作树。

- 主工作区原始基线：b0c48ca；现有改动保存为 a99bbc0（离线持久化、群附件/路由、群 @ 与键盘、头像形状、朗读与通知资料）。
- 定时任务工作树基线：a8e3c2d；实现保存为 9869e92，分支 codex/scheduled-tasks-integration-20261012。
- 头像、群聊、文件附件、MCP OAuth、记忆 M5 五个工作树均干净，HEAD 已在 main 历史中；保留原工作树和分支。
- 网页查询实现 bacc251 已在 main，无另一个待合入的网页查询工作树。

## 整合修复

- 数据库迁移保留 v21 会话修订同步、v22 群附件，定时任务顺延为 v23；后台入口同步检查 v23。
- 私聊与群聊同步显式读取同一 SQLite 快照，避免并发写入返回不匹配的 revision 和正文。
- 私聊本地删除按会话范围内的 remoteID 删除，避免 snapshot UUID 与数据库 local_id 不一致导致离线复活。
- 本地 SQLite transaction 支持首次访问时打开数据库，避免后台 open 尚未执行时事务失败。
- 同会话并发同步采用每会话单飞；旧账号草稿绑定创建时 Repository；退出同步关闭数据库并隔离旧目录；群恢复/停止的最终消息写入 SQLite。均有回归与审查，最终结果见下方。

## 验证方法与边界

Swift 包完整测试；后端离线脚本分别独立进程运行，使用临时库/假提供者，不访问正式账号或真实模型。定时任务 36 项测试已在原工作树与整合代码分别通过。

不能以 unittest 一次 discover 整个 scripts/test 目录：既有脚本在 import 时初始化各自数据库，且有本地 HTTP 服务专项脚本；共享解释器会产生交叉污染。本次尝试产生 108 个导入错误/1 个过时版本断言失败，改为逐脚本独立进程，最终结果以独立运行记录为准。旧迁移回归硬编码 schema=17/18/22 已改为当前 SCHEMA_VERSION，同时保留表、外键与存量消息断言。

模拟器/真机安装和启动只证明可运行；离线冷启动、账号切换、真实模型/MCP、设备声音/锁屏等用户交互验收继续保留待验收状态。定时任务没有新增 iOS 任务页或 APNs，不以保存代码等同部署后台服务。

## 最终结果

整合回归已完成：Swift Testing 241 项 + XCTest 1 项全部通过（/tmp/verabot-final-swift.log），33 个后端离线脚本分别独立运行并全部退出 0（/tmp/verabot-integration-backend-results.json），定时任务 36 项另行通过（/tmp/verabot-merged-scheduled-tests.log）。限定范围独立复审无剩余 Critical/Important。模拟器和备机的构建、安装均完成。模拟器已启动并展示保留账号的助理/群聊列表；备机因锁屏自动启动被系统拒绝，安装完成且数据保留。本记录是本轮当前状态入口，既有日期记录是当时快照。

## 回归检查补充

扩大后端离线回归时发现的测试陈旧问题已针对性修正：迁移编号使用当前常量，提醒日期改为运行时未来日期；附件测试补主入口保护以兼容 spawn，并使用图片 MIME、v19 文件扩展列/可选协议字段；连接器测试按 HTTP 头大小写不敏感读取只读声明。这些修改保留原行为断言，不改变生产权限策略。

SQL 分层静态检查仍失败：基线 b0c48ca 与整合结果均 100 条，新增 0。私聊同步 SQL 已归入 db/message_store；不能报告全库分层检查通过。证据 /tmp/verabot-sql-layer-comparison.json。

开发版本为 0.1.0，iOS 构建号更新为 2026101201，用于识别这轮设备包；不创建发布标签。

## 现有开发后端升级

- 在线备份：`/Users/admin/Desktop/VeraBot-v0.1/backend/data/verabot.db.bak-before-v23-20261012-221338`（本地私有数据，不提交 Git）。
- 备份副本连续迁移两次 v22→v23，integrity_check=ok，存量 users=14 / bots=33 / messages=131 / groups=5 / group_messages=26 保持。
- 主工作区现有后端已重启并迁移 v23；再次读取数量一致、完整性正常，健康请求 200，OpenAPI 同时含两种 sync 和七条定时任务路径。
- 定时任务表当前 0 行；本轮仅更新 API，没有安装系统后台服务或自动创建/执行正式账号任务。现有配置、JWT 与用户数据保留。
- 迁移与服务证据：/tmp/verabot-v23-migration.json、/tmp/verabot-main-runtime.json。

## Main 与设备结果

- 集成合并提交：`eb67ff9`，父提交 `a99bbc0` / `9869e92`。设备包源码与此提交一致；后续记录提交仅更新文档。未推送远端。
- iPhone 17 / iOS 26.0：完整构建成功，原地安装并启动，进程 74288；UI snapshot 确认助理列表与正式群聊入口，保留原登录与内容。
- 模拟器 MCP 构建调用等待 300 秒超时，但构建已产生包；随后使用同一 DerivedData 增量构建明确 `BUILD SUCCEEDED`，再经 MCP 安装/启动成功。日志 /tmp/verabot-main-simulator-build.log。
- iPhone 11 备机：Debug arm64 签名构建成功，codesign 校验通过；安装结果 `success`，bundle com.verabot.app，build 2026101201。安装后自动启动被系统锁屏拒绝（Locked），等待解锁后查看/确认；未卸载 App 或清除其登录数据。
- 备机安装路径 `/private/var/containers/Bundle/Application/E128E6E1-8E66-47C8-A4A6-E7E49124F7B1/VeraBot.app/`；dylib SHA256 `9f5ede0857a02683bdf660311bef126e62a716a33c93b40784af63113db74521`。
- 模拟器 dylib SHA256 `9b53c4e30a800665d709f6ef926a1a4a0e092f2bba2c764c7e41f8a1e8d14d4c`。
- 证据：/tmp/verabot-main-device-build.log、/tmp/verabot-main-secondary-{install,launch,processes}.json、/tmp/verabot-main-simulator-running.jpg。截图保留本机，不把账号页面作为源码提交。

## 本轮验收清单

- Pass：全部代码保存与 main 集成、迁移副本演练/幂等/存量数量、现有后端健康和完整性、Swift/后端离线回归、独立复审。
- Pass：模拟器构建/安装/启动/实际页面；备机签名构建/原地安装。
- Problem：备机自动启动被锁屏拒绝，待解锁；SQL 分层 100 条既有问题，新增 0。
- Not-triggered：备机本轮实际页面与真实模型；断网冷启动/完整大历史/账号服务器切换/快速重登等设备交互；设备音频/锁屏/TTS。
- Not-triggered：真实 OAuth、真实 MCP 与定时任务模型执行、后台进程/系统服务部署；保持既有专题验收状态。
