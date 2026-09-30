#!/usr/bin/env bash
# 命令行编译 iOS App 并安装到模拟器（等同 Xcode ⌘R）。用法：frontend/scripts/run_ios.sh ["iPhone 17"]
set -euo pipefail
cd "$(dirname "$0")/../ios"
SIM="${1:-${SIM_DEVICE:-iPhone 17}}"
DD="${DERIVED_DATA:-/tmp/verabot_dd}"
xcodebuild -project VeraBot.xcodeproj -scheme VeraBot -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$DD" build | tail -3
APP="$DD/Build/Products/Debug-iphonesimulator/VeraBot.app"
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcrun simctl terminate "$SIM" com.verabot.app 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.verabot.app
