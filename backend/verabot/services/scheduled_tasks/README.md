# 服务端定时任务 v1

API 管理任务；独立后台进程负责调度和执行。任务保存在 SQLite，系统 cron 不是必需组件。

## 启动

从 backend 目录启动，两进程必须使用相同绝对数据库路径、数据目录和提供者配置：

    export VERABOT_DB=/absolute/path/to/verabot.db
    export VERABOT_DATA_DIR=/absolute/path/to/data

先启动 API，应用幂等 v21 迁移：

    uv run python -m uvicorn verabot.main:app --host 127.0.0.1 --port 8000

再在相同环境下启动一个后台进程：

    uv run python -m verabot.services.scheduled_tasks

只扫描一次并执行至多一条待执行记录（运维或手动检查）：

    uv run python -m verabot.services.scheduled_tasks --once

后台入口不会迁移旧库；版本低于 21 时要求先启动 API。正式升级前应备份数据库。本次交付未升级正式库或安装系统服务。

单机只部署一个后台进程。API 可独立重启；后台由 launchd、systemd 或部署平台监督并自动重启。机器休眠或服务停止时不能执行，恢复后按错过规则处理；App 是否打开不影响执行。

Linux systemd 示例（替换路径与运行账号，示例不包含密钥）：

    [Unit]
    Description=VeraBot Scheduled Tasks
    After=network-online.target

    [Service]
    Type=simple
    User=verabot
    WorkingDirectory=/opt/verabot/backend
    EnvironmentFile=/etc/verabot/backend.env
    ExecStart=/opt/verabot/backend/.venv/bin/python -m verabot.services.scheduled_tasks
    Restart=on-failure
    RestartSec=5
    TimeoutStopSec=20

    [Install]
    WantedBy=multi-user.target

部署平台可直接把上述 Python 命令作为第二个服务进程。macOS 可用 launchd：ProgramArguments 指向虚拟环境 Python 和上述模块，WorkingDirectory 指向 backend，KeepAlive 设置 true；环境使用服务端配置，不把提供者密钥放入客户端。无须为每个用户任务创建系统 cron 项。

## 创建与管理

认证沿用 Bearer token。POST /api/scheduled-tasks 使用 Idempotency-Key：

    {
      "bot_id": 1,
      "title": "每日天气",
      "instruction": "查询石家庄天气，给出今天的穿衣建议。",
      "start_at": "2026-10-12T09:00:00+08:00",
      "timezone": "Asia/Shanghai",
      "repeat": "daily",
      "misfire_policy": "skip"
    }

实际请求中首次时间必须在未来；start_at 的偏移必须与 timezone 对应。repeat 为 once / daily / weekdays / weekly；weekly 必须提供 weekdays（0=周一…6=周日，不重复）。misfire_policy 为 skip（默认）或 latest。

API：
- GET /api/scheduled-tasks：state / bot_id / before_id / limit 筛选。
- GET /api/scheduled-tasks/{id}：定义与最近执行。
- PATCH /api/scheduled-tasks/{id}：修改字段和 expected_version。
- POST /api/scheduled-tasks/{id}/pause、/resume：请求体含 expected_version。
- DELETE /api/scheduled-tasks/{id}：请求体含 expected_version，软删除；客户端先确认。
- POST /api/scheduled-tasks/{id}/run：Idempotency-Key，返回 202；不影响下一次排程。paused / completed 也可手动执行。
- GET /api/scheduled-tasks/{id}/runs、/runs/{run_id}：历史、结果、尝试与用量。删除后历史仍可访问。

并发修改返回 409；同 key 的创建内容不同返回 409；同任务已有排队或执行返回 task_busy。列表默认 20，上限 100。错误在 detail 中含 code / message。任务标题 1–200 字符，指令 1–8000 字符。

## 执行规则

调度每 30 秒扫描，串行 Worker 每秒检查空队列。分钟级触发，不承诺精确开始时间。一次性任务终结后 completed；重复任务继续未来排程。

错过超过 10 分钟默认跳过；latest 只补最近一次且不超过 24 小时。恢复暂停任务不补过去。时区固定，不跟随手机改变；夏令时缺失时刻跳过，重复时刻只运行第一次。

执行最多 180 秒，4 轮工具交互、8 次工具调用，每次尝试累计输出上限 2048 token。已知连接失败、429、提供者 5xx 最多尝试 3 次，间隔 30 / 120 秒。超时、权限或额度问题不自动重试。进程被终止时已过期租约标 interrupted，不自动重跑；请检查历史后手动执行。租约为 90 秒，正常每 15 秒续租。

Bot 权限和工具连接在执行时再次检查。后台允许 get_weather、list_reminders，以及服务端目录点名、已接受定义且仍获授权的 MCP 只读工具。第三方 readOnlyHint 不足以授权后台调用。不会自动授予 Bot 新工具；任务创建时保存授权上限，新授予工具需新建相应任务。权限撤回导致本次失败；Bot 删除使任务暂停。

不读取整个私人聊天，不写记忆，不调用其他 Bot，不传附件，不创建/管理提醒，不写外部系统。模型最终输出要求 JSON state=succeeded/text 或 state=failed/error_summary；无结果、截断、工具失败和格式错误均不能标成功。内容生成的事实正确性仍需用户判断。

已返回的每轮用量立即记录，使用 scheduled_task 分类并计入既有账号日额度。额度检查为软限额，不能撤回已经发出的请求；费用/用量未知时 attempts.usage_unknown=true，不能当作零费用。

成功结果带“定时任务：标题”写入 Bot 对话；API 消息附 source_kind=scheduled_task/source_id。生成结果先持久保存，再去重创建消息与通知；投递失败只重试投递。删除已投递消息不会被重试恢复。通知中心和已有偏好复用；无 APNs 时需要再次打开/刷新 App 才看到新结果。

## 离线验证

    python -m unittest discover -s scripts/test -p 'scheduled_task_*_test.py' -v

所有测试使用临时数据库、假时钟或 127.0.0.1 假提供者，不接触正式数据库或真实模型。进程用例包含启动、结束、强制终止、租约过期及重启不重复请求。
