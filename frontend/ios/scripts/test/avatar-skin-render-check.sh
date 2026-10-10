#!/usr/bin/env bash
# Render the production Canvas skin code on macOS with fixture gestures and the real texture assets.
set -euo pipefail
cd "$(dirname "$0")/../../../.."
check_dir="$(mktemp -d /tmp/verabot-skin-render.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
sed '/^import UIKit$/d; /^import VeraBotCore$/d' \
  frontend/ios/VeraBot/Features/Settings/RobotAvatarSkinRendering.swift > "$check_dir/RobotAvatarSkinRendering.swift"
swiftc -parse-as-library \
  frontend/ios/scripts/test/avatar-skin-render-check.swift \
  "$check_dir/RobotAvatarSkinRendering.swift" \
  frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotAvatarSkin.swift \
  frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotAvatarSurfaceMapping.swift \
  -o "$check_dir/check"
"$check_dir/check"
