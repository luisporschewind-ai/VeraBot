#!/bin/bash
set -euo pipefail
SIM_DETAIL="${1:?Usage: run.sh <simulator-udid> [output-directory] [legacy]}"
OUT_DETAIL="${2:-/tmp/verabot-appearance-harness}"
IOS_DETAIL="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT_DETAIL/Probe.app"
SDK_DETAIL="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH_DETAIL="$(uname -m)"
FLAGS_DETAIL=(-Onone)
if [[ "${3:-}" == legacy ]]; then FLAGS_DETAIL+=(-D LEGACY_APPEARANCE); fi
cat > "$OUT_DETAIL/Probe.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>com.verabot.appearance-probe</string><key>CFBundleName</key><string>Appearance Probe</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundlePackageType</key><string>APPL</string><key>MinimumOSVersion</key><string>17.0</string><key>UILaunchScreen</key><dict/><key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict></dict></plist>
PLIST
xcrun swiftc -parse-as-library -sdk "$SDK_DETAIL" -target "$ARCH_DETAIL-apple-ios17.0-simulator" -swift-version 6 \
  "${FLAGS_DETAIL[@]}" "$IOS_DETAIL/VeraBot/Core/UI/Theme.swift" \
  "$IOS_DETAIL/VeraBot/Core/UI/AppearanceWindowSync.swift" \
  "$IOS_DETAIL/VeraBot/Features/Settings/AppearanceMode.swift" "$(dirname "$0")/main.swift" \
  -o "$OUT_DETAIL/Probe.app/Probe" > "$OUT_DETAIL/build.log" 2>&1
ORIGINAL_DETAIL="$(xcrun simctl ui "$SIM_DETAIL" appearance | tr '[:upper:]' '[:lower:]')"
restore_detail() { xcrun simctl ui "$SIM_DETAIL" appearance "$ORIGINAL_DETAIL" >/dev/null 2>&1 || true; }
trap restore_detail EXIT
xcrun simctl terminate "$SIM_DETAIL" com.verabot.appearance-probe >/dev/null 2>&1 || true
xcrun simctl install "$SIM_DETAIL" "$OUT_DETAIL/Probe.app"
for MODE_DETAIL in light dark; do
  xcrun simctl ui "$SIM_DETAIL" appearance "$MODE_DETAIL"
  xcrun simctl launch "$SIM_DETAIL" com.verabot.appearance-probe "--system-$MODE_DETAIL"
  DATA_DETAIL="$(xcrun simctl get_app_container "$SIM_DETAIL" com.verabot.appearance-probe data)"
  # Remove only previous output from this dedicated test app, never user app data.
  rm -f "$DATA_DETAIL/tmp/report.txt"
  for ((I_DETAIL=0; I_DETAIL<40; I_DETAIL++)); do
    if [[ -f "$DATA_DETAIL/tmp/report.txt" ]]; then break; fi
    sleep 1
  done
  mkdir -p "$OUT_DETAIL/system-$MODE_DETAIL"
  cp "$DATA_DETAIL"/tmp/*.txt "$DATA_DETAIL"/tmp/*.png "$OUT_DETAIL/system-$MODE_DETAIL/"
  xcrun simctl terminate "$SIM_DETAIL" com.verabot.appearance-probe >/dev/null 2>&1 || true
  cat "$OUT_DETAIL/system-$MODE_DETAIL/report.txt"
done
python3 - "$OUT_DETAIL" <<'PY'
from pathlib import Path
import sys
reports = list(Path(sys.argv[1]).glob('system-*/report.txt'))
assert len(reports) == 2 and all('checks=8 failures=0' in p.read_text() for p in reports), 'Appearance regression failed'
PY
