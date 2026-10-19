# 游戏改版 Main 验收交付

2026-10-19，用户明确要求“提交所有代码，包括前后端，合并到Main，装三端，我在Main上验收”。三端经用户纠正为主机iPhone12ProMax、备机iPhone11、模拟器；不包含Web或原生Mac App。此新授权取代前阶段“未提交/不执行部署”的交付边界，范围为本机Main验收环境，不另发远程服务器。

## Git与代码

- 游戏前后端、测试、合同、素材元数据、计划与证据：`66c4e12`。
- Main先快进到`53bdb66`（PR66），随后合并游戏为`c5308b7`。轮播卡片、“空间”命名及既有UI保留。
- 合并冲突已解决：三个索引/状态文档合并两边记录；计划/基线/总账采用本轮已验证的最新进度；WorldViews保留最新Main轮播实现。无其他工作树代码混入。
- Main合并后Swift472项/14套件通过；后端9个专项脚本合计41项通过；素材11项、合同13样本与工程格式通过。验收人仍为用户，未代签手感/听感。
- 当前为本地Main提交/合并，尚未推送远端。原工作树保留原始压测日志，Main运行不依赖它。

## Main后端

- 路径：`/Users/admin/Desktop/VeraBot-v0.1/backend`，API `http://127.0.0.1:8000`，手机LAN `http://192.168.0.104:8000`。
- 迁移前一致备份：`/Users/admin/Desktop/VeraBot-v0.1/backend/data/verabot.db.bak-before-v38-main-20261019-170445`，600权限，完整性ok。schema37→38；用户/Bot/消息/附件/记忆/提醒/任务/资料库原有计数保持不变。
- API已由Main重启，PID85426；health200，接管API路由已注册。
- 专属worker由`/Users/admin/Library/LaunchAgents/com.verabot.tetris-worker.plist`监督。schemaReady=true、workerReady=true、capacity=4、规则vera-tetris-2、fixture hash一致。与聊天worker分开，无模型密钥依赖。
- 本机服务在登录会话运行；无登录开机、主机休眠和其他远程环境不作已验证承诺。手机后台/锁屏/终止App的持续代玩仍需用户V-07验收。

## 三端包

全部从Main `c5308b7` 构建，不复用旧工作树包。版本沿用0.1.0 (2026101701)，用源码提交、时间与hash区别旧包。

- iPhone17/iOS26模拟器：Main构建117.4秒成功，8项既有警告；安装、启动成功PID85950。
- 主机iPhone12ProMax：Main签名包构建成功，17:14:59安装成功。随后设备与Mac断开，自动启动未确认；用户明确选择手动打开App，不再等待连接或自动重试。
- 备机iPhone11：同一Main签名包17:15:41安装成功、17:16:08启动成功；进程核验PID48505，容器9884675A-7170-44C1-A68F-4FF3E8D191B4。

真机包：`/tmp/verabot-main-game-acceptance-device/Build/Products/Debug-iphoneos/VeraBot.app`；二进制SHA256：`a5a8c5a4b675e32490fd0f2ce7cc568348cc0c469e37ea3ea1eb2aa61735f03c`。包元数据保存在[Main包证据](../testing/evidence/tetris/2026-10-19-main-package.json)。构建与安装日志分别为`/tmp/verabot-game-main-device-build.log`、`/tmp/verabot-main-game-primary-install.log`、`/tmp/verabot-main-game-backup-install.log`；启动日志为`/tmp/verabot-main-game-backup-launch.log`。

## 人工验收

入口：游乐场→俄罗斯方块/贪吃蛇。先检查布局、按键/长按/多指与触感、暂停/倒数、规则/陪玩和声音；再把同局交给Bot，验证切微信、锁屏、终止App各约2分钟后服务持续推进、同局返回与收回。操作中断网/重进/他端只读/换账号按V-07检查。安装/启动不代替验收，未完成项保留。
