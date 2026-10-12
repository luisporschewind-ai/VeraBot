# 群聊正式功能整理 · 2026-10-11

用户要求移除测试功能和页面，将群聊作为正式功能。此次范围限群聊，保留其他实验室和并行语音改动。

- 移除首页「群聊预览」菜单、预览 sheet、模拟成员/回复数据，以及四个 Preview 页面/数据文件。
- 移除 `--group-chat-preview` 与详情预览启动分支，Debug/Release 统一从正常账号根页面进入。
- 正式入口为「助理 → 群聊」及「＋ → 创建群聊」，使用现有 GroupList/CreateGroup/GroupChat/GroupInfo 与 `/api/groups`；无需新数据库迁移，正式库沿用 v20。
- 保留自动化回归和产品外的开发提供者夹具，正式后端与 App 不引用夹具，不产生假回复。
- 既有测试含固定 30ms 延迟，在并行构建负载下旧会话回归存在调度竞态；以 checked continuation 明确等待与释放，保留相同账号隔离断言。

此项是产品路径整理，不能代替真实模型体验、管理与换账号等剩余设备验收。原有群、私聊和账号数据均保留；旧隔离模拟库保留在 `/tmp/verabot-group-g3-demo`，不导入正式账号库。

## 本轮验证与设备交付

- Swift 包 224 Swift Testing + 1 XCTest 通过；模拟器与 arm64 真机 Debug 构建均 BUILD SUCCEEDED，签名校验通过。App 源码与编译文件列表已无群聊 Preview 引用。日志 `/tmp/vb_group_formal_swift_final.log`、`/tmp/vb_group_formal_{sim,device}_build.log`。
- 当前 iPhone 17 模拟器 6FD1E62D-DA65-42B1-81F5-554042006671 已原地安装启动，连接 `http://127.0.0.1:8000`，截图确认正常账号 Bot 列表与正式群聊入口。旧 G3 设备在安装期间被关闭，保持关闭，不再依赖它交付功能。
- 隔离 8093 模拟提供者进程已停止，旧测试数据文件保留；正式 8000 服务健康检查 200，不受影响。
- iPhone 11 备机已安装并启动正式包，进程列表确认新安装路径；iPhone 12 Pro Max 主机已安装相同包，用户解锁后启动成功，进程 89612 确认对应新安装路径。
- 设备包 debug dylib SHA-256 `dc6d619cd7cf0098b8bb4108450a7f62babc03bcdf170fe5009be5f8ea383ce7`；安装/启动/进程证据 `/tmp/vb_group_formal_{primary,secondary}_*.json`。正常 App 运行入口无测试账号或假回复；不删除用户已有账号和群。
- 本轮修改位于 main 工作区，未提交/推送；其他并行语音、提示组件和计划任务改动保留。

## 统一会话列表

- 按用户要求移除 Bot／群聊 segment 与覆盖式群列表，首页同一 List 混排 Bot 和群聊。
- 置顶 Bot 在前，其余按最近消息时间排序；群聊以成员头像、群聊标记与消息摘要区分。
- 搜索同时覆盖 Bot、群名和最近消息，创建群聊后直接进入详情，下拉刷新同时更新两类会话；两类请求分别处理失败，保留已加载列表。
- 统一列表版模拟器与 arm64 真机构建通过（`/tmp/vb_unified_list{,_device}_build.log`），diff check 通过。当前 iPhone 17 模拟器已安装启动，截图 `/tmp/vb_unified_list.png` 确认首页无 segment；该账号当前无群聊，因此截图仅显示 Bot。
- iPhone 11 覆盖安装与启动成功；iPhone 12 Pro Max 覆盖安装成功，此次启动因重新锁屏被系统拒绝，用户解锁后可打开新版。此次列表调整未提交。

## 群聊输入区与设置成员展示

- 删除群聊详情顶部成员选择条；回应方式和点名选择保留在底部输入栏。
- 输入区采用与单聊一致的底部悬浮玻璃样式与键盘避让，支持 Return 发送、语音输入、停止生成和滚动到底；群聊接口目前仅接受文字，因此不显示单聊的附件入口。
- 群设置列出群 API 返回的完整成员，每行显示头像、昵称、默认回应者或不可用状态。
- 模拟器与 arm64 真机 Debug 构建通过（`/tmp/vb_group_input_build_final.log`、`/tmp/vb_group_input_device_build.log`）；模拟器及 iPhone 11 已安装启动，iPhone 12 Pro Max 已安装但处于锁屏状态，系统拒绝启动。未执行自动化测试或手动群聊点按验收。
