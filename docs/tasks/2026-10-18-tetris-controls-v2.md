# 2026-10-18 · 俄罗斯方块掌机按键 v2

日期：2026-10-18（实现于 2026-10-19 凌晨）。用户要求按 [设计图 v2](product/2026-10-18-tetris-controls-visual-proposal.md) 落实操作区，受掌机启发、非 1:1 复刻实体手柄。只改 iOS，不改后端。

## 实现范围

俄罗斯方块底部操作区去掉五键等宽横排，改为：

- 左侧一体十字方向键：左 / 右移动、向下缓降；**上方向留空、不绑定任何动作、不做硬降**（上臂渲染为禁用空键）。
- 右侧斜排圆形 A / B：A = 旋转、B = 直接落下，中文标签「旋转」「直接落下」放在圆外；B 保留重触感（硬降）。
- 下中两个小胶囊 START / SELECT：START = 暂停/继续，SELECT = 菜单（**重开收进菜单**，不再用独立小键直接清局）。
- 棋盘、右侧 Bot、下个方块、暂停说明按已实现的右侧版保持；换伙伴 / 安静模式 / 聊天 / 重试全部保留。
- 未新增「交给 Bot」按钮（云端接管是独立提案，不在本次）。

## 关键行为

- 命中区 ≥44pt；按键沿用 `GameButtonStyle`（新增 `shape` 参数，圆形 / 胶囊复用同一按压观感）与现有 `hapticFeedback` 包装，遵守「触感反馈」开关与「减少动态效果」。
- 方向键**长按连续移动**（约 110ms 重复），A / B 与 START / SELECT 单次触发；由 `GameKey`（`DragGesture(minimumDistance: 0)`）实现按住重复，旧计时任务按代次失效。
- 暂停 / 结束时方向键与 A / B 禁用，START 在结束后禁用，SELECT 始终可用。

## 文件

- `frontend/ios/VeraBot/Features/Playground/MiniGameViews.swift`：`TetrisGameView` 操作区替换、右侧暂停/重开移除、`togglePause`、菜单 confirmationDialog、`TetrisControlButton` 删除。
- `frontend/ios/VeraBot/Features/Playground/HandheldGameControls.swift`（新增）：`GameKey` / `GameDpad` / `GameFaceCluster` / `GamePillKey`。
- `frontend/ios/VeraBot/Core/UI/Haptics.swift`：`GameButtonStyle` 增加 `shape: AnyShape`。
- `frontend/ios/VeraBot/Features/Playground/SnakeGameView.swift`：贪吃蛇方向键复用 `GameDpad`（四向可用、单次触发）。

## 验证

- `plutil -lint project.pbxproj` 通过；新增文件与资源已在工程登记（上次贪吃蛇漏登记教训）。
- `xcodebuild`（iPhone 17 / iOS 26 模拟器）**未构建**：本环境沙箱拒绝写入 `~/Library/Caches/org.swift.swiftpm`（`Operation not permitted`），按要求未申请权限。
- 未跑真机、未提交 UI 验收；长按手感、A/B 斜排观感、START/SELECT 命中待真机人工验收。

## 未完成 / 风险

- 未编译验证：以上 Swift 文件只经人工审查 + `swift test`（包层）通过，App 目标未编译（见上）。
- 上方向「留空」是禁用渲染；是否要完全不显示上臂、或改成其它视觉，待体验评审。
