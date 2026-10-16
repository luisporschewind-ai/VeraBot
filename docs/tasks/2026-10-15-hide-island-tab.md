# 暂时隐藏底部「小岛」入口

## 需求

从 iOS 主界面的底部 TabBar 移除「小岛」item。

## 修改

- 在 `MainTabView` 中移除 `IslandView` 的 Tab 注册。
- 保留 `IslandView` 实现和现有数据，不改其他 Tab。
- 项目状态和更新日志已同步；现有界面截图未更新。

## 验证

- 本次未运行构建或设备手动验收。
