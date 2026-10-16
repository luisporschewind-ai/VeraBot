# 2026-10-16 全部代码提交与 Main 集成

## 范围

用户要求提交全部代码并合并到 Main。盘点时主工作区与 independent-library 工作树均干净，且都位于 `0e2d2ed`，资料库等本地改动已提交并包含在 main。其余未合入的三个本地分支均已通过 PR #48–#50 合入远端 Main。

本轮将远端 `7f78ccc` 合入本地 main，保留本地资料库、离线阅读、群资料分页、导航及点击区域调整，同时合入长回复折叠、旧任务标记及 trace 瘦身。不推送、不删除分支或工作树，不重启服务或迁移实际数据库。

## 冲突处理

- runtime 同时保留资料库服务与 trace 瘦身。
- 两条开发线占用了 schema v33。保留资料库 v33 和 TXT 元数据 v34，将旧任务及 trace 迁移调整为 v35；迁移前生成 `.bak-before-v35-*`。
- 远端 v33 没有资料库表，不能仅凭版本号跳过资料回填；改为同时检查资料库表是否已存在。
- 合并双方文档，保留按日期记录的历史交付和人工验收边界。

## 验证

- Swift：`swift test --jobs 2` 通过，Swift Testing 349 项（含已有跳过项），XCTest 1 项，0 失败。
- 旧任务及 trace 瘦身：分别从 schema v32 / v33 / v34 升级，三轮各 19/19 通过。
- 资料库迁移：6/6 通过，包含远端 v33 无资料库回填及重复迁移幂等。
- 后端相关回归：资料库 API 8、生命周期 6、工具 6、附件 28、删除消息 10、开场词 10、持续对话 12、会话同步 2、主动任务审批 5、主 Bot 7，共 94 项通过。
- SQL 分层：集成当时资料库在 `agents/tool_router.py`、`services/attachments/repo.py`、`services/library.py` 仍有 db 层外 SQL（与合并前本地 `0e2d2ed` 相同，本轮未扩大重构）。**后续已收尾**：上述 SQL 已迁入 `db/library_store.py` / `db/attachment_store.py`，`sql_layer_check` SQL-LAYER-01/02 通过。
- Intel 模拟器构建通过：`xcodebuild ... -jobs 2 ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build`，日志 `/tmp/verabot-main-integration-intel-build.log`。先前通用双架构构建主动中止，收敛到本机验收架构后通过。
- 测试均使用隔离数据库；未进行生产部署、真实模型或设备交互验收。
