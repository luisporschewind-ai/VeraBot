# 2026-10-15 快捷提问背景与间距检查

## 问题与修复

iPhone 17 / iOS 26 模拟器上复现：输入栏上方快捷提问的玻璃阴影被横向 ScrollView 的边界裁切，形成矩形背景色带。

- 提取 `quickPromptBar`，保持原显示条件与点按填入行为。
- 使用 `GlassGroup(spacing: 4)` 统一渲染按钮；横向间距保持 8pt，低于按钮间距的融合阈值避免相邻胶囊粘连。
- 文字左右 12pt、上下 8pt；滚动内容上下各留 4pt，与输入栏实际边缘间距为 10pt（父 VStack 间距 6pt + 底部留白 4pt）。
- `.scrollClipDisabled()` 保留玻璃视觉溢出，不再把阴影裁成矩形；沿用 iOS 17–25 的材质回退。

## 验证

- 修复前浅色截图：`/tmp/verabot-quick-chat-loaded.png`。
- 模拟器和通用 iOS 实机签名构建通过，日志 `/tmp/verabot-quick-prompts-build.log`、`/tmp/verabot-quick-prompts-device-build.log`。
- 原 iPhone 17 模拟器已安装运行。浅色、深色截图核对均未再出现矩形色带，胶囊与输入栏间距正常：`/tmp/verabot-quick-light-after.png`、`/tmp/verabot-quick-dark-after.png`。
- 输入框聚焦时快捷选项隐藏已观察；快捷选项点按填入与横向滑动的自动点击结果不稳定，保留用户手工验收，不记为通过。
- 两台真机当前在 CoreDevice 中均为 unavailable，本轮布局包尚未安装到手机。
- 本轮为布局与材质修正，不新增实现镜像单元测试。
- 与尚未提交的离线阅读修改共同保留在当前工作区，未提交或推送。

## 参考

- [Apple：scrollClipDisabled](https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:))。
- [Apple：GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)。
