#!/usr/bin/env bash
# 编译真实陪玩 Model / Policy，替换 AppState、网络与数据类型以隔离生命周期竞态；不请求模型或真实数据库。
set -euo pipefail
cd "$(dirname "$0")/../../../.."
package_path=frontend/ios/Packages/VeraBotKit
module_path="$package_path/.build/debug/Modules"
if [ ! -d "$module_path" ]; then swift build --package-path "$package_path"; fi
check_binary="$(mktemp /tmp/verabot-tetris-model-check.XXXXXX)"
trap 'rm -f "$check_binary"' EXIT
swiftc -parse-as-library -I "$module_path" \
  frontend/ios/scripts/test/tetris-companion-model-check.swift \
  frontend/ios/VeraBot/Features/Playground/TetrisCompanionModel.swift \
  "$package_path/Sources/VeraBotCore/TetrisCompanionPolicy.swift" -o "$check_binary"
"$check_binary"
