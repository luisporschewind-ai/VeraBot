#!/usr/bin/env python3
"""Validate the bundled, original synthesized game audio pack. No dependencies."""
import array
import hashlib
import json
from pathlib import Path
import sys
import wave
ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {name + '.wav' for name in ('key_press', 'start', 'pause', 'resume', 'hard_drop', 'clear_single', 'clear_multi', 'eat', 'game_over', 'win')}

def validate(manifest):
    data = json.loads(manifest.read_text())
    if not (data['version'] == 1 and data['origin'] == 'original-synthesis'):
        raise ValueError('missing original source provenance')
    generator = ROOT / 'frontend/ios/Tools/gen_game_sounds.py'
    if not data['generator'] == str(generator.relative_to(ROOT)):
        raise ValueError('unexpected generator')
    if not data['generatorSHA256'] == hashlib.sha256(generator.read_bytes()).hexdigest():
        raise ValueError('generator hash mismatch')
    entries = data['assets']
    names = [entry['file'] for entry in entries]
    if not (len(names) == len(REQUIRED) and set(names) == REQUIRED):
        raise ValueError('expected exactly ten unique event files')
    total = 0
    for entry in entries:
        name = entry['file']
        path = manifest.parent / name
        if not (not path.is_symlink() and path.resolve().parent == manifest.parent.resolve()):
            raise ValueError('asset path escape')
        raw = path.read_bytes()
        total += len(raw)
        if not hashlib.sha256(raw).hexdigest() == entry['sha256']:
            raise ValueError(name + ': hash mismatch')
        with wave.open(str(path), 'rb') as stream:
            if not stream.getcomptype() == 'NONE':
                raise ValueError(name + ': compressed WAV')
            if not stream.getnchannels() == entry['channels'] == 1:
                raise ValueError(name + ': expected mono')
            if not stream.getsampwidth() * 8 == entry['bits'] == 16:
                raise ValueError(name + ': expected 16-bit PCM')
            if not stream.getframerate() == entry['sampleRate'] == 44100:
                raise ValueError(name + ': expected 44.1kHz')
            duration = stream.getnframes() * 1000 / stream.getframerate()
            if not abs(duration - entry['durationMs']) < 0.001:
                raise ValueError(name + ': duration metadata mismatch')
            if not (30 <= duration <= 70 if name == 'key_press.wav' else 20 <= duration <= 600):
                raise ValueError(name + ': duration out of range')
            samples = array.array('h', stream.readframes(stream.getnframes()))
        if sys.byteorder != 'little':
            samples.byteswap()
        peak = max(map(abs, samples), default=0)
        if not 0 < peak <= 32767 * 0.7:
            raise ValueError(name + ': silence or peak above headroom limit')
        onset = next((i for (i, value) in enumerate(samples) if value), len(samples))
        if not onset <= 44100 * 0.005:
            raise ValueError(name + ': excessive leading silence')
    if not total <= 1024 * 1024:
        raise ValueError('audio pack exceeds 1MiB')
    return f'{len(entries)} assets validated, {total} bytes, original mono PCM 44.1kHz'
if __name__ == '__main__':
    try:
        print(validate(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'frontend/ios/VeraBot/Resources/Sounds/manifest.json'))
    except (AssertionError, KeyError, ValueError, OSError, wave.Error) as error:
        print(f'Invalid game audio: {error}', file=sys.stderr)
        sys.exit(1)
