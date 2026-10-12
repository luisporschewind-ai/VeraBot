#!/bin/bash
set -euo pipefail
MENTION_SIM="${1:?Usage: run.sh <simulator-udid> [output-directory]}"
MENTION_OUT="${2:-/tmp/verabot-mention-harness}"
MENTION_IOS="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$MENTION_OUT/Probe.app"
cat > "$MENTION_OUT/Probe.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>com.verabot.mention-probe</string><key>CFBundleName</key><string>Mention Probe</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundlePackageType</key><string>APPL</string><key>MinimumOSVersion</key><string>17.0</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
xcrun swiftc -parse-as-library -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target "$(uname -m)-apple-ios17.0-simulator" -swift-version 6 \
  "$MENTION_IOS/VeraBot/Core/UI/Theme.swift" "$MENTION_IOS/VeraBot/Features/Settings/AppearanceMode.swift" "$MENTION_IOS/VeraBot/Features/GroupChat/MentionTextEditor.swift" "$(dirname "$0")/main.swift" \
  -o "$MENTION_OUT/Probe.app/Probe" > "$MENTION_OUT/build.log" 2>&1
xcrun simctl install "$MENTION_SIM" "$MENTION_OUT/Probe.app"
MENTION_DATA="$(xcrun simctl get_app_container "$MENTION_SIM" com.verabot.mention-probe data)"
rm -f "$MENTION_DATA/tmp/report.txt"
xcrun simctl launch "$MENTION_SIM" com.verabot.mention-probe
for ((MENTION_I=0; MENTION_I<30; MENTION_I++)); do
  if [[ -f "$MENTION_DATA/tmp/report.txt" ]]; then break; fi
  sleep 1
done
cp "$MENTION_DATA/tmp/report.txt" "$MENTION_OUT/report.txt"
cat "$MENTION_OUT/report.txt"
xcrun simctl terminate "$MENTION_SIM" com.verabot.mention-probe
! grep -q '^FAIL' "$MENTION_OUT/report.txt"
