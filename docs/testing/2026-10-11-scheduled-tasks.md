# 服务端定时任务第一版验证记录

状态：2026-10-12 原工作树 36 项与整合后 36 项定时任务测试全部通过；实现已保存为 9869e92 并正在合入本地 main，主线使用 v23。整合结果与设备交付见 [Main 集成记录](2026-10-12-main-integration.md)。测试不使用正式数据库或真实模型。

## 自动验证

从 backend 运行：

    python -m unittest discover -s scripts/test -p 'scheduled_task_*_test.py' -v

首轮完整验证：36 tests，0 failures。包括迁移与唯一约束、API 幂等/版本冲突/隔离、修改和删除、时区/DST、调度竞争、跳过与只补一次、Worker 竞争/租约/过期/重试、暂停运行取消、已知用量保留、工具写入拦截、MCP 提示不授权、独立上下文、预算检查及边界、持久结果投递重试、删除消息不恢复。

真实子进程与本地 HTTP 假提供者验证：
- 执行成功后一个 run、一条 Bot 消息、一条通知；空队列不调用提供者。
- 执行中强制终止 Worker，租约到期后重启：原 run 标记 interrupted，提供者请求数仍为 1。

相关回归：
- notify_test.py：PASS。
- group_lifecycle_test.py：8 tests PASS。
- mcp_m3_test.py：ALL PASS。
- llm_body_test.py：7/7 PASS。
- reminder_test.py：PASS；原测试硬编码 schema=17，当前基线为 v20，此次 v21 迁移仅把该断言改为与 db.SCHEMA_VERSION 比较。
- compileall、git diff --check：PASS。
- 新增任务服务/API 的 SQL 分层检查：12 modules PASS。

## 既存问题与验证边界

全仓库 sql_layer_check.py 在未修改的主线也失败：bots API、actions、OAuth、memory 等模块已有 SQL 分层违规。此功能没有增加这些违规，也没有扩展修复这些既存模块；不能报告全仓库 SQL 检查通过。

未执行全部 scripts/test 脚本：目录包含要求真实账号、外部服务或运行中的 API 的专项脚本，本次运行上述相关离线回归。

未调用真实提供者，真实模型结果质量、真实 MCP 连接与费用未验收。没有 iOS 新任务页面或 APNs；App 关闭时后端可以工作，但完成通知要通过已有收件箱/对话刷新查看。

## 复现环境

使用现有 Python 3.12 虚拟环境执行，新依赖为零。数据库环境由测试支持模块设置到系统临时目录；进程测试连接 127.0.0.1 假提供者。完整测试日志和决策记录位于本工作树 .superpowers/sdd/2026-10-11-scheduled-tasks/（git ignored）。

## 独立审阅

独立审阅检查了已跟踪变更与全部新增文件，并通过临时库复现了 6 个重要边界问题：整次尝试输出预算、过期一次性排程编辑、completed 排程修改、回拨时钟后恢复重复时刻、已取消执行的租约恢复、提供者缺失用量。全部已修复，并由 36 项回归测试覆盖；未进行第二次独立审阅。

审阅范围不包含真实提供者、真实 MCP、生产部署/监督、设备推送或针对任意提示注入的完整评测。审阅者独立运行了针对性复现，全部测试套件与既有回归的通过结果来自实施者执行。
