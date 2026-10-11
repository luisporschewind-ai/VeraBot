#!/bin/bash
set -euo pipefail
NOTICE_IOS="$(cd "$(dirname "$0")/../.." && pwd)"
NOTICE_OUT="${1:-/tmp/verabot-notice-harness}"
mkdir -p "$NOTICE_OUT"
swiftc -parse-as-library -swift-version 6 \
  "$NOTICE_IOS/VeraBot/Core/UI/Notices/NoticeQueue.swift" \
  "$NOTICE_IOS/Tools/NoticeHarness/main.swift" -o "$NOTICE_OUT/checks"
"$NOTICE_OUT/checks"
