# 2026-10-15 对话离线进入体验修复

## 原因与修改

页面原先先等待 `refreshActivityForEntry`，再开始读取 SQLite；初次滚动定位又要等 ViewModel 内历史、任务状态及附属信息请求结束。群聊 `loading` 状态还禁止本地翻页。

私聊和群聊新增本地恢复完成回调，页面在该阶段完成消息定位；活动摘要并行刷新，网络超时不阻止本地展示。群聊本地翻页单独使用 `loadingOlder`，并删除 SQLite 同步路径里重复拉群历史的请求。刷新按已展开消息数量恢复本地记录。

## 验证

- 新用例 `cachedGroupHistoryCanPageWhileServerIsUnavailable`：真实临时 SQLite 保存 105 条消息和草稿，服务端挂起请求；验证本地回调发生于远程请求前，草稿可用，等待期间可从 100 条翻到全部 105 条。
- 修复前该用例失败：消息数停在 100，第一条是 local 6。修复后通过。
- Swift Testing 318 项及 XCTest 1 项通过，日志 `/tmp/verabot-offline-tests.log`。
- iOS 模拟器构建通过，日志 `/tmp/verabot-offline-sim-build.log`。
- 真机构建通过，日志 `/tmp/verabot-offline-device-build.log`。
- 修复版已安装至原 iPhone 17 模拟器、iPhone 12 Pro Max 与 iPhone 11；模拟器和 iPhone 11 已启动。主机安装成功，但启动被系统以 Locked 拒绝，等待解锁重试。
- 模拟器截图确认列表已显示；可访问性读取耗时较长，不将其当作离线对话交互验收。设备手工离线阅读待用户验收。

## 范围

本次覆盖已保存的私聊/群聊消息、文字草稿及本地翻页。未下载内容、图片/文件原件的离线缓存和提醒/记忆等其他页面的统一离线改造另行确认。代码尚未提交。
