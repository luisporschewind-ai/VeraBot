#!/usr/bin/env python3
"""可复现的短音效合成脚本（仅标准库 wave/math/struct，无第三方授权问题）。

为俄罗斯方块与贪吃蛇生成约 10 个短 WAV：单声道、统一 44100 Hz、16-bit PCM，
全部包络淡入淡出，总大小 < 1MB。重复运行得到字节级一致的文件。

输出目录：frontend/ios/VeraBot/Resources/Sounds/
"""
import math
import os
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "VeraBot", "Resources", "Sounds")

TWO_PI = 2.0 * math.pi


def _frames(duration_s: float) -> int:
    return max(1, int(round(duration_s * RATE)))


def _envelope(n: int, attack=0.004, release=None):
    """线性淡入淡出，返回 [0..1] 数组。"""
    if release is None:
        release = max(0.005, min(0.02, n / RATE * 0.25))
    a = min(n, max(1, int(attack * RATE)))
    r = min(n, max(1, int(release * RATE)))
    out = [0.0] * n
    for i in range(n):
        env = 1.0
        if i < a:
            env = i / a
        if i >= n - r:
            env = min(env, (n - 1 - i) / r)
        out[i] = env
    return out


def _tone(freq: float, duration_s: float, amp=0.5, attack=0.003, release=None):
    n = _frames(duration_s)
    env = _envelope(n, attack=attack, release=release)
    out = []
    for i in range(n):
        out.append(math.sin(TWO_PI * freq * i / RATE) * env[i] * amp)
    return out


def _sweep(f0: float, f1: float, duration_s: float, amp=0.5):
    n = _frames(duration_s)
    env = _envelope(n)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = f0 + (f1 - f0) * t
        phase += TWO_PI * freq / RATE
        out.append(math.sin(phase) * env[i] * amp)
    return out


def _noise(duration_s: float, amp=0.4, seed=7):
    """带指数衰减的短噪声，做一点低通让声音更软。"""
    n = _frames(duration_s)
    env = _envelope(n)
    out = []
    prev = 0.0
    for i in range(n):
        # 确定性伪随机（LCG），保证可复现。
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
        white = (seed / 0xFFFFFFFF) * 2.0 - 1.0
        prev = 0.72 * prev + 0.28 * white  # 一阶低通
        decay = math.exp(-6.0 * i / n)
        out.append(prev * env[i] * decay * amp)
    return out


def _mix(*tracks):
    length = max((len(t) for t in tracks), default=0)
    out = [0.0] * length
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def _add(a, b):
    """把 b 叠加到 a（a 可更长）。"""
    out = list(a)
    for i, v in enumerate(b):
        if i < len(out):
            out[i] += v
    return out


def _clip(samples, peak=0.62):
    out = []
    for v in samples:
        if v > peak:
            v = peak
        elif v < -peak:
            v = -peak
        out.append(v)
    return out


def _write(name: str, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    data = struct.pack("<%dh" % len(samples), *[int(v * 32767) for v in _clip(samples)])
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{name}.wav  {len(samples)} samples ({len(samples)/RATE*1000:.0f} ms)  {os.path.getsize(path)} B")


def build():
    # 1. keyPress —— 柔和机械点击：低音 + 短噪声，约 42ms。
    click = _add(_tone(640, 0.042, amp=0.30, release=0.012), _noise(0.030, amp=0.18))
    _write("key_press", click)

    # 2. start —— 上行双音确认，约 110ms。
    start = _add(_tone(520, 0.055, amp=0.34), _tone(780, 0.075, amp=0.34))
    _write("start", start)

    # 3. pause —— 下行双音，约 110ms。
    pause = _add(_tone(660, 0.06, amp=0.32), _tone(440, 0.08, amp=0.32))
    _write("pause", pause)

    # 4. resume —— 与 start 相近的上行确认。
    resume = _add(_tone(440, 0.06, amp=0.32), _tone(660, 0.08, amp=0.32))
    _write("resume", resume)

    # 5. hard_drop —— 低沉落地“咚”，约 95ms。
    thud = _add(_tone(150, 0.095, amp=0.5, release=0.03), _noise(0.04, amp=0.24))
    _write("hard_drop", thud)

    # 6. clear_single —— 轻亮单音，约 85ms。
    _write("clear_single", _tone(880, 0.085, amp=0.36))

    # 7. clear_multi —— 三连上行短琶音，约 210ms。
    multi = _tone(660, 0.07, amp=0.30)
    multi = _add(multi, _tone(880, 0.07, amp=0.30))
    multi = _add(multi, _tone(1175, 0.09, amp=0.30))
    _write("clear_multi", multi)

    # 8. eat —— 圆润“啵”：上行扫频，约 70ms。
    _write("eat", _sweep(320, 620, 0.07, amp=0.4))

    # 9. game_over —— 温和下行两音，约 260ms。
    over = _add(_tone(523, 0.12, amp=0.32), _tone(392, 0.16, amp=0.32))
    _write("game_over", over)

    # 10. win —— 短庆祝三连上行，约 300ms。
    win = _tone(523, 0.09, amp=0.30)
    win = _add(win, _tone(659, 0.09, amp=0.30))
    win = _add(win, _tone(784, 0.12, amp=0.30))
    _write("win", win)


if __name__ == "__main__":
    build()
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f)) for f in os.listdir(OUT_DIR) if f.endswith(".wav"))
    print(f"total: {total} B ({total/1024:.1f} KB)")
