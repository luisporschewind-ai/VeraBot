# 附件直接发送与多图堆叠

日期：2026-10-16

## 已确认交互

- 私聊、群聊选择图片或文件后自动上传并发送，移除发送前的缩略图预览和再次点击发送步骤。相机仍使用系统拍照界面。
- 相册一次最多选择 9 张，按选择顺序串行上传，全部成功后作为一条消息发送。已有文字草稿保留，附件单独发送；文件入口仍单选。
- 多图消息采用卡片堆叠，显示「共 N 张图片」；点按打开可滑动的查看页，支持单张原件查看。横屏按可用宽高缩放，GIF 保留动画。
- 上传期间仅显示进度和取消；失败保留重试。重试复用已成功上传的部分；取消清理未发送的服务器附件。
- 对话正在回复时等待其结束后自动发送；私聊问题关联未退出时等待退出。现有发送回执和网络不确定结果核对流程继续使用原请求，避免重复发送。

## 实现

- `ComposerAttachmentModel` 改为批次上传，保存部分成功结果和失败资源；取消后迟到的上传结果也会删除。
- 私聊发送接口改接附件数组；在本地发送记录保存失败时保留批次重试。群聊纯附件发送不覆盖内存或持久文字草稿，并在发送队列持久保存后才释放批次；保存失败允许重试。
- `MessageAttachments` 统一私聊/群聊的单图、多图和文件展示。刚上传的图片优先读取本机内存缓存。
- 私聊/群聊请求校验及附件服务上限从 1 调整到 9；无数据库迁移。私聊历史对同秒附件按上传 rowid 排序，群聊关联按写入 rowid 排序，避免随机 ID 打乱图片顺序。
- 将附件选择相关修饰符与私聊原页面拆开，解决 SwiftUI 大表达式类型检查超时。

## 验证

- 新增后端临时数据库回归：私聊 9 图绑定同一消息及全部模型图片片段；群聊 9 图及相同请求幂等重放；10 图拒绝；混入他人图片时整批拒绝且不部分绑定。
- 新增 Swift 群聊回归：纯附件发送保留内存与数据库文字草稿、持久保存失败不提交网络请求且可重试。
- 最终 `swift test --package-path frontend/ios/Packages/VeraBotKit -j 2`：Swift Testing 351 项、XCTest 1 项通过。
- `backend/.venv/bin/python backend/scripts/test/multi_attachment_test.py`：4 项通过。
- `backend/.venv/bin/python backend/scripts/test/attachments_test.py`：28/28 通过，原 ATT-07 数量断言同步调整为超过 9 张拒绝。
- `backend/.venv/bin/python backend/scripts/test/group_execution_api_test.py`：8 项通过。
- iPhone 17 / iOS 26 模拟器目标 `xcodebuild ... -jobs 2 build`：最终构建成功，DerivedData `/tmp/verabot-multi-attachment-dd`。
- `git diff --check` 通过。静态复核提出的批次过早释放、拒绝后残留本地消息、横屏图片裁切均已修正。
- 构建日志：`/tmp/verabot-multi-build.log`；测试日志：`/tmp/verabot-multi-swift.log`、`/tmp/verabot-multi-backend.log`、`/tmp/verabot-multi-attachment-regression.log`、`/tmp/verabot-multi-group-regression.log`。

## 手动验收

1. 输入一段未完成文字后选择 3 张照片：无需发送前预览/确认，最终是一条带数量标签的堆叠消息；文字保留。
2. 点击堆叠，左右滑动核对图片顺序，旋转横屏核对完整显示；混入 GIF 检查动画。
3. 私聊、群聊分别发送 1 张、9 张和一个文件；离开后重新进入，确认数量和顺序一致。
4. 上传中断网后重试，核对不重复上传成功部分、不重复生成消息；上传中取消不发送。
5. Bot 回复中选择图片，回复结束后自动发送；私聊退出问题关联后自动发送。

首轮仅完成代码与构建，未更新运行服务或设备；随后用户要求安装 iPhone 主辅机，交付进度如下。

## iPhone 主辅机交付

- 2026-10-16：实时确认主机 iPhone 12 Pro Max、辅机 iPhone 11 均连接，iOS 26.6.1，开发者模式已启用；签名配置覆盖两台设备。
- 原运行后端 OpenAPI 仍为每条最多 1 个附件。使用项目停止/启动脚本重启本机服务后，`/api/health` 正常，`ChatInput` 和 `GroupInputIn` 的 `attachment_ids.maxItems` 均为 9。
- 真机版构建成功（`/tmp/verabot-library-device`），`com.verabot.app` 0.1.0 (2026101605)。构建日志 `/tmp/verabot-multi-device-build.log`。
- 主机 iPhone 12 Pro Max、辅机 iPhone 11 均安装成功；分别读取设备已安装应用清单，确认两台都是 0.1.0 (2026101605)。采用覆盖安装，未卸载或清理应用数据。
- 安装证据：`/tmp/verabot-primary-install.json`、`/tmp/verabot-secondary-install.json`；安装版本核对：`/tmp/verabot-primary-app.json`、`/tmp/verabot-secondary-app.json`。
- 两台检查时均处于需要密码的锁屏状态；完成安装后没有启动应用或操作对话，留给用户自行打开验收。
- 用户明确要求自行验收；不代替用户操作对话或执行真实模型验收。
