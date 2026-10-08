#!/bin/bash
set -euo pipefail
IOS="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="$(git -C "$IOS" rev-parse --show-toplevel)"
OUT="${1:-/tmp/vera-avatar-baseline-comparison}"
mkdir -p "$OUT"
python3 - "$ROOT" "$OUT" <<'EXTRACT'
import sys, subprocess
from pathlib import Path
root, out = Path(sys.argv[1]), Path(sys.argv[2])
base = 'frontend/ios/VeraBot/Features/Settings/'
for name in ['RobotAvatarMotion.swift','RobotAvatarSpecialMotion.swift','RobotAvatarView.swift']:
    source = subprocess.check_output(['git','-C',str(root),'show','avatar-lab-robot-v1:'+base+name],text=True)
    if name == 'RobotAvatarView.swift':
        source = 'import Foundation\n'+source[source.index('enum RobotAvatarAction:'):source.index('enum RobotAvatarTone:')]
        name = 'BaselineState.swift'
    (out/name).write_text(source)
EXTRACT
SOURCE="$IOS/VeraBot/Features/Settings"
SAMPLES="$IOS/Tools/RobotAvatarHarness/BaselineSamples.swift"
swiftc -parse-as-library -swift-version 5 "$OUT/BaselineState.swift" "$OUT/RobotAvatarMotion.swift" "$OUT/RobotAvatarSpecialMotion.swift" "$SAMPLES" -o "$OUT/baseline"
swiftc -parse-as-library -swift-version 5 "$SOURCE/BotAvatarState.swift" "$SOURCE/BotAvatarWorkMotion.swift" "$SOURCE/RobotAvatarMotion.swift" "$SOURCE/RobotAvatarSpecialMotion.swift" "$SAMPLES" -o "$OUT/current"
"$OUT/baseline" > "$OUT/baseline.txt"
"$OUT/current" > "$OUT/current.txt"
cmp "$OUT/baseline.txt" "$OUT/current.txt"
echo "PASS exact 17-state tag comparison: normal/reduced motion, durations, eyes, head and antenna flash"
