# 俄罗斯方块代玩 worker 运行与回滚

2026-10-19。本文是可审查交付步骤，未在正式库迁移或安装正式服务。当前代码位于独立工作树，尚未合入/提交/推送；正式目录应使用经过审查的完整发布版本。

## 运行契约

- API 与独立 worker 使用同一个 SQLite 数据库；数据库 schema38、ruleVersion `vera-tetris-2`、fixtureSHA256 `bd52a7eb5ed77ba516e6f53746fde5f619e6e2cc7e85d8668e81cede2c841ead` 必须一致。
- worker：`python -m verabot.services.tetris_sessions`。它不初始化/迁移数据库，不启动 API、聊天或模型服务；不需要模型密钥。工作目录为发布版本 `backend/`，按既有 `.env`/环境读取数据库配置。
- 当前实测容量上限4局（600秒长测p95 89.329ms通过），每用户同时1局。16局及8局10分钟实测均未达标，不能沿用较高默认值。2个规划子进程、最多2项在途；20ms扫描，到期局每100ms最多推进100ms，停机时间不补落。
- 租约10秒，成功批提交续租；心跳10秒内才接受新交出。关闭手机或App不影响worker；关闭API不应停止worker。暂停、回接、结束均由事务/版本/epoch仲裁。

## 发布前

1. 确认发布版本包含配套API/worker/Swift协议，运行专项测试与合同、资源校验。先在测试库完成迁移、回滚演练；不能用生产库测试。
2. 在维护窗口使用 SQLite backup API 生成一致备份，记录路径、schema与 `PRAGMA integrity_check`。已有 `backup_before_v38` 会在现有初始化流程迁移前自动备份，但不能替代独立可验证备份。先重查正式schema是否仍37；38被其他发布占用时停止并协调迁移编号，不能覆盖。
3. 按既有后端发布流程部署schema38/API，确认 `/api/games/tetris/sessions/capabilities` 在worker未就绪时报告available=false。不要由worker隐式迁移。
4. 使用下述生成器产生plist，审查绝对路径和数据库，再按当前授权安装监督服务。正式服务未安装前，App只能玩本地或显示代玩未就绪。

## macOS监督配置

生成器只写新文件，不安装、不启动、不覆盖旧文件。下面路径均需替换为当前发布环境的真实绝对路径。

```sh
python backend/scripts/render_tetris_worker_launchd.py \
  --backend /absolute/release/backend \
  --python /absolute/release/backend/.venv/bin/python \
  --database /absolute/data/verabot.db \
  --log-dir /absolute/logs \
  --output /absolute/staging/com.verabot.tetris-worker.plist
plutil -lint /absolute/staging/com.verabot.tetris-worker.plist
```

生成文件含KeepAlive、RunAtLoad、5秒启动节流、15秒退出宽限。macOS LaunchAgent仅在对应用户登录会话存在时持续；无登录开机运行应由管理员审查为LaunchDaemon配置，不能宣称用户LaunchAgent覆盖该场景。Linux服务器需要相应systemd配置，不直接使用plist。

获得正式部署授权后，在对应用户的 `~/Library/LaunchAgents/` 安装已审查文件，用 `launchctl bootstrap gui/UID /absolute/agent.plist` 启动，`launchctl print gui/UID/com.verabot.tetris-worker` 查看，`launchctl bootout gui/UID/com.verabot.tetris-worker` 停止。仅操作这个服务，不停止现有API/聊天worker。

隔离监督验证命令：`python backend/scripts/test/tetris_launchd_test.py --run`。会创建唯一测试label和临时数据库，验证首次心跳、SIGKILL后自动重启及owner改变，finally移除测试job；不安装永久agent、不改正式库。当前Intel Mac已执行通过；真正重启电脑与正式服务未验证。

## 健康与故障

从发布版本backend目录运行 `python -m verabot.services.tetris_sessions --status`，检查JSON中的schemaReady、workerReady、ruleVersion、fixtureSHA256、active、waiting、capacity。命令退出0只表示查询成功；健康判定还必须要求schemaReady=true且workerReady=true，不能只看退出码。`--once`用于隔离测试，不能作为持续服务。

日志 `tetris_tick` 含published/errors/errorKinds/rejected/latenessMs/planningQueue。rejected可能是暂停/收回产生的正常CAS冲突；errors不是同一概念。持续errors、心跳超10秒、等待时长增加或p95调度延迟超100ms要处理；不通过放宽目标冒充达标。日志不得加入token或完整聊天。

数据库写失败时不发布未提交的快照；恢复后从最后持久点继续。planner失败仅丢弃本次计划，重力继续，绝不改盘。原worker被杀后其他worker在租约过期后接续；暂无其他worker时监督进程先重启，仍受原租约到期约束。API重启期间手机显示待确认，不能本地双控。

## 回滚

1. 先关闭新交出入口（暂停接管API新建/hand off；查询和收回继续可用），保持已有局的归属。此步骤是发布操作，需在当前环境明确配置，不假设客户端开关已经上线。
2. 通过已审查工具/API把现有Bot局暂停，确认持久快照/进行中操作和备份，再停止专属worker。不要直接清表、删局或把controller强改player。
3. 旧版App不理解云端局；在可回接版本保留查询/收回通道。回滚API前必须明确现有局的处理，不能留一个“已交给Bot”但无人接续的局。
4. schema38表可暂保留；不运行降级DROP。需要恢复整库时，先停相关写入、另存当前一致备份，再由维护人按备份恢复流程操作并做完整性检查；这会影响其他功能，不能自动执行。

真实手机切微信、锁屏、终止App各约2分钟的同局持续事件与回接验收仍待正式环境就绪后完成；监督进程测试不代替手机验收。
