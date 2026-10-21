# Bot 游戏 3D 形象三视图

2026-10-20。用户要求将原 2D Bot 转为 3D，表面光滑，分别交付正面、侧面、背面三张图片，用于后续 Bot 游戏形象参考。

## 交付

- 正面：[bot-front.png](assets/bot-3d-2026-10-20/bot-front.png)
- 侧面：[bot-side.png](assets/bot-3d-2026-10-20/bot-side.png)
- 背面：[bot-back.png](assets/bot-3d-2026-10-20/bot-back.png)

保留圆润方形主体、双眼和顶部独立悬浮圆点。使用光滑石墨黑塑料表面与柔和高光，去掉初稿颗粒纹理。侧面与背面无额外装饰。

依据现有 RobotAvatarView、RobotAvatarGeometry、BotAvatarTemplate 的形象特征进行转译。生成提示目标比例为主体宽高深 200:180:110，顶部球直径 30；深度为本轮设计提议，非原 2D 已有尺寸。三张图片为独立生成的视觉参考，存在细微比例差异，建模时需统一几何。现有 2D 眼睛参数为 54×58、中心间距 68；生成图眼睛比原始参数更窄，后续建模应以原始参数和用户视觉确认为准。

采用内置 imagegen 生成。完整提示见同目录 assets/bot-3d-2026-10-20/generation-prompts.txt。当前只交付图片与设计记录，尚无游戏可用网格、材质文件、绑定或动画，未接入应用，未进行用户验收。
