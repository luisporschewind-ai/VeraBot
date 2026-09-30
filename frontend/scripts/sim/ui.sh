# iOS 模拟器 UI 测试辅助函数（macOS）。用法：source frontend/scripts/sim/ui.sh
#   tap PX PY [sleep]      点击（坐标为 471×1024 截图像素，按模拟器窗口实时几何换算）
#   drag X0 Y0 X1 Y1 [s]   拖动（同样使用截图像素坐标）
#   paste "文本"            通过剪贴板粘贴到当前焦点
#   shot NAME              截图到 $SHOT_DIR/NAME.png（并生成 1024 高的 NAME_s.png）
# 需要：Simulator 已启动；终端具有「辅助功能」权限（System Events / CGEvent）。
if [ -n "${BASH_SOURCE:-}" ]; then _vb_f="${BASH_SOURCE[0]}"; else _vb_f="${(%):-%x}"; fi
VB_SIM_DIR="$(builtin cd "$(dirname "$_vb_f")" && pwd)"   # builtin：交互式 zsh 里 cd 可能被别名 (如 zoxide)
VB_ROOT="$(builtin cd "$VB_SIM_DIR/../../.." && pwd)"
S="${SIM_DEVICE:-iPhone 17}"
SHOT_DIR="${SHOT_DIR:-$VB_ROOT/assets/screenshots/scratch}"
mkdir -p "$SHOT_DIR" "$VB_SIM_DIR/.bin"
for _t in click drag; do
  [ -x "$VB_SIM_DIR/.bin/$_t" ] || swiftc -O "$VB_SIM_DIR/$_t.swift" -o "$VB_SIM_DIR/.bin/$_t"
done
act(){ osascript -e 'tell application "Simulator" to activate' >/dev/null; sleep 0.3; }
geo(){ osascript -e 'tell application "System Events" to tell process "Simulator" to tell window 1 to get {position, size} of (first UI element whose role is "AXGroup")' | tr -d ' '; }
_px(){ python3 -c "g=[float(v) for v in '$1'.split(',')]; s=g[2]/471; print(' '.join(str(round(g[i%2]+float(a)*s)) for i,a in enumerate('$2'.split())))"; }
tap(){ act; "$VB_SIM_DIR/.bin/click" $(_px "$(geo)" "$1 $2"); sleep "${3:-0.8}"; }
drag(){ act; "$VB_SIM_DIR/.bin/drag" $(_px "$(geo)" "$1 $2 $3 $4"); sleep "${5:-1}"; }
paste(){ printf "%s" "$1" | pbcopy; printf "%s" "$1" | xcrun simctl pbcopy "$S"; act; osascript -e 'tell application "System Events" to keystroke "v" using command down'; sleep 0.8; }
shot(){ xcrun simctl io "$S" screenshot "$SHOT_DIR/$1.png" >/dev/null 2>&1; sips -Z 1024 "$SHOT_DIR/$1.png" --out "$SHOT_DIR/$1_s.png" >/dev/null 2>&1; }
