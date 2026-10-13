# 明确交办的持续任务

主 Bot 是账号级默认负责人，不是群聊默认成员。用户先选择主 Bot，再单独开启“允许主动任务”，最后确认具体目标/完成标准或周期；普通聊天不自动创建任务。

## 服务端运行

先在备份副本演练 v25→v29，并启动 API 完成迁移。正式数据目录与原 API 配置不是此实施自动修改的范围。

后台单独运行，与 API 使用同一绝对 VERABOT_DB、VERABOT_DATA_DIR 和模型配置：

    python -m verabot.services.owned_tasks

`--once`最多领取一步；完成一次咨询可能需要多个步骤。周期 owned 还需运行原 `python -m verabot.services.scheduled_tasks` 调度进程；两个进程各领自己的执行路径。群 v2 仍保留原单API进程限制。

任务总预算默认20000，主动每日默认20000，同时检查账号日额度；每链6次实际生成、2048输出、4工具轮次/8次调用、240秒累计模型等待。租约90秒，每15秒续租。用量未知保持标记并预留2048，不视作免费。外部写结果未知不能自动重放。

周期任务旧模式read_only不变；新模式owned把一个发生关联唯一owned任务，linked run表示retry_wait/error_code=owned_active且不可被旧Worker领取。前实例未结束则新发生skip；显示业务状态请读取owned-task。原周期暂停/删除会使关联业务步骤失效。

## 接口与权限

- GET/PATCH `/api/primary-bot`：nullable primary_bot_id、active_enabled、daily_token_limit、expected_version。
- POST/GET `/api/owned-tasks`、GET `/{id}`：创建需Idempotency-Key；goal、completion_criteria、bot_id、token_limit。
- POST `/{id}/inputs`：message、expected_version、Idempotency-Key；只解决原等待项。
- POST `/{id}/stop|continue|transfer`：expected_version，transfer另带bot_id。
- GET `/{id}/events`：JSON增量；`/{id}/events/stream`：SSE完整快照，游标/版本可以重入；断开观察不停止工作。
- 原scheduled-tasks创建可选execution_mode=owned；旧客户端默认read_only。

冻结工具、咨询目标和至多12条普通可见记忆ID；实际执行/批准再次检查当前权限。咨询只拿具体问题，不读取目标私聊或隐式目标记忆。MCP写工具走旧pending-actions卡片，任务/版本引用原子绑定；真实结果加密保存后回接，未知结果跨版本保留防重放。记忆/提醒写入、主动创建新任务、任意电脑操作和敏感记忆不开放。

## 本地验收准备

纯假模型、独立数据、合成账号，不复制现有数据库或连接真实模型：

    python scripts/dev/primary_bot_manual.py --data-dir /tmp/verabot-primary-manual --port 8096

登录 `primary-test` / `primary-test-2026`。选择“主 Bot 测试伙伴”并单独开启主动任务，交办目标/完成标准；假模型先追问，回答后咨询另一个测试伙伴，再完成。该环境可以观察离开/重进、停止/继续及周期控制，但不证明真实模型质量、外部MCP或APNs。脚本拒绝无fixture标记的非空目录。

本实现不自动替换已有8000/8094服务、不安装真机、不合入main。UI入口：Bot详情“设为主 Bot”，Bot详情/对话更多菜单“任务”，助理页主Bot快捷入口。任务/收件箱刷新或SSE可见进度；尚无APNs，锁屏即时求助未交付。
