# 多图堆叠尺寸与下层内容调整

日期：2026-10-16

## 用户反馈

多图堆叠大体正确，但卡片过大，下面几张只露空白边，希望缩小并展示真实图片。

## 调整

- 多图卡片宽高均缩小到原来的 75%，常见图片宽度从 240pt 改为 180pt，保留原宽高比估算。
- 前 3 张真实图片按后到前顺序组成堆叠，替换原来的空白圆角矩形占位。
- 所有层使用正面卡片的同一尺寸，以 aspect-fill 填满并裁切，避免不同宽高比留下容器空边。静态图片和 GIF 使用一致模式。
- 下层每层向左 12pt、向下 8pt、旋转 -4°，留出能看到真实内容的边缘；卡片留白同步适配。
- 调整仅作用于私聊/群聊共用的多图堆叠；点开后仍按选择顺序翻页查看原图。
- 真机版本：0.1.0 (2026101607)。沿用当前工作区已有附件与短回复修复。

## 验证与交付

- 真机 `xcodebuild` 构建通过；日志 `/tmp/verabot-image-stack-build.log`。
- 主机 iPhone 12 Pro Max、辅机 iPhone 11 均覆盖安装成功；设备应用清单确认版本 0.1.0 (2026101607)，保留数据。
- 安装证据：`/tmp/verabot-stack-primary-install.json`、`/tmp/verabot-stack-secondary-install.json`；版本证据：`/tmp/verabot-stack-primary-app.json`、`/tmp/verabot-stack-secondary-app.json`。
- `git diff --check` 通过。此次是展示布局调整，未添加镜像式单元测试，设备视觉交互留给用户验收。
- 用户继续在 iPhone 12 Pro Max 和 iPhone 11 手动验收：重点查看横竖图混合时下层图片能否露出真实内容、整体尺寸是否合适，以及点击后图片顺序。
