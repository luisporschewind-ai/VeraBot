#!/bin/bash
set -euo pipefail
IOS="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-/tmp/vera-avatar-system-checks}"
mkdir -p "$OUT/build"
SOURCE="$IOS/VeraBot/Features/Settings"
FILES=("$SOURCE/RobotAvatarMotion.swift" "$SOURCE/RobotAvatarSpecialMotion.swift" "$SOURCE/RobotAvatarInteraction.swift")
FLAGS=(-swift-version 5)
if [[ -f "$SOURCE/BotAvatarState.swift" ]]; then
  FILES+=("$SOURCE/BotAvatarState.swift" "$SOURCE/BotAvatarWorkMotion.swift" "$SOURCE/BotAvatarLabPlayback.swift")
  FLAGS+=(-D AVATAR_SYSTEM)
else
  python3 - "$SOURCE/RobotAvatarView.swift" "$OUT/build/LegacyAction.swift" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
Path(sys.argv[2]).write_text('import Foundation\n'+s[s.index('enum RobotAvatarAction:'):s.index('enum RobotAvatarTone:')])
PY
  FILES+=("$OUT/build/LegacyAction.swift")
fi
if [[ -f "$SOURCE/BotAvatarTemplate.swift" ]]; then
  FILES+=("$SOURCE/BotAvatarTemplate.swift")
  FLAGS+=(-D AVATAR_TEMPLATE)
fi
swiftc -parse-as-library "${FLAGS[@]}" "${FILES[@]}" "$IOS/Tools/RobotAvatarHarness/main.swift" -o "$OUT/build/checks"
"$OUT/build/checks"
