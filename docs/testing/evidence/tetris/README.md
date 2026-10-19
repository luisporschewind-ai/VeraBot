# Tetris测试结果归档

2026-10-19，Intel Mac。同日隔离测试，真实uvicorn/SQLite/worker；身份为测试fixture。正式生产数据库/服务未触碰。源base875b608，本轮未提交改动；客户端另保留main390fba8的三处最新UI调整。

`*-load-16.json` 与 `*-load-8.json` 均为原始失败结果，不修饰pass字段。两次结果环境有同期App/Swift编译。16局记录的workerErrors含结束时整组SIGTERM导致的规划池异常；改为正常关闭owner后，8局完整结果为0错误，但延迟仍失败。

`*-load-4.json` 为4局600.08秒完整通过结果；同期仍有其他Swift编译，并未剔除拥堵样本。目标始终workerLatenessP95Ms≤100、workerErrors=0、httpFailures=[]、integrity=ok，不以放宽目标过关。

原始每批日志仍在隔离工作树 `.superpowers/sdd/2026-10-18-tetris-local-upgrade/`；本目录保存无需依赖临时路径即可审查的摘要。完整环境/限制与人工边界见[接管证据](../../2026-10-18-tetris-takeover-evidence.md)。
