# 堆叠缩略图填满与查看页完整比例

日期：2026-10-16

## 用户要求

堆叠展示允许裁切，但不能有容器白边；点击查看后必须按原比例完整展示，不变形、不裁切。

## 修改

- 静态图与 GIF 统一使用 UIImageView 的内容模式，在明确的容器宽高内缩放。
- 堆叠缩略图使用 `scaleAspectFill`，填满统一卡片尺寸并裁切溢出内容；保留独立点击和堆叠大小。
- 查看页使用 `scaleAspectFit`，按真实图片比例放入完整可用区域；不再以缩略图的宽高比限制查看容器高度。
- 查看页图片容器透明、无圆角，不额外铺气泡背景或裁掉图片四角。屏幕与图片比例不同产生的页面空余区域不拉伸填充；图片自身内容不修改。
- 修复版：0.1.0 (2026101609)，继续主辅机覆盖安装，数据保留。

## 验证与验收

- 真机 `xcodebuild` 成功，日志 `/tmp/verabot-image-fit-build.log`；`git diff --check` 通过。
- iPhone 12 Pro Max、iPhone 11 覆盖安装成功，已通过各自应用清单确认 0.1.0 (2026101609)，保留应用数据。
- 安装与版本证据：`/tmp/verabot-fit-primary-install.json`、`/tmp/verabot-fit-secondary-install.json`、`/tmp/verabot-fit-primary-app.json`、`/tmp/verabot-fit-secondary-app.json`。
- 未操作手机对话，设备视觉交互仍由用户验收。
- 本次只调整展示，未新增镜像式单元测试；用户验收横图/竖图/GIF：堆叠填满卡片，点开后完整显示四边且比例正确。
