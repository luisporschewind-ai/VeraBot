#!/bin/bash
# 头像实验室离屏测试 (offscreen harness)：以 Mac Catalyst 编译 VeraBotCore + Theme + AvatarLab* 源码，
# 运行映射 / 演示序列断言，并用 ImageRenderer 把 5 角色 × 8 状态 × 3 尺寸 × 浅/深色渲染成 PNG。
# 不启动模拟器、不操作界面。用法：Tools/AvatarLabHarness/run.sh [输出目录，默认 /tmp/avatarlab_harness]
set -euo pipefail
IOS="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-/tmp/avatarlab_harness}"
BUILD="$OUT/build"
rm -rf "$BUILD" && mkdir -p "$BUILD/src"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
# 单模块编译：去掉 import VeraBotCore
for f in "$IOS"/Packages/VeraBotKit/Sources/VeraBotCore/*.swift \
         "$IOS"/VeraBot/Core/UI/Theme.swift \
         "$IOS"/VeraBot/Features/Settings/AvatarLabView.swift \
         "$IOS"/VeraBot/Features/Settings/AvatarLabCharacterView.swift \
         "$IOS"/Tools/AvatarLabHarness/main.swift; do
  sed '/^import VeraBotCore$/d' "$f" > "$BUILD/src/$(basename "$f")"
done
cp "$IOS/VeraBot/Assets.xcassets/AvatarLabCloudReference.imageset/cloud-reference.png" "$BUILD/AvatarLabCloudReference.png"
xcrun swiftc -sdk "$SDK" -target "$ARCH-apple-ios17.0-macabi" -swift-version 6 -O \
  -F "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -module-name AvatarLabHarness "$BUILD"/src/*.swift -o "$BUILD/harness"
(cd "$BUILD" && ./harness "$OUT")
