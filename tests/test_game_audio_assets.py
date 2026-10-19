import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'frontend/ios/VeraBot/Resources/Sounds'
SCRIPT = ROOT / 'scripts/check_game_audio.py'


class GameAudioAssetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.assets = Path(self.tmp.name) / 'Sounds'
        shutil.copytree(SOURCE, self.assets)

    def check(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.assets / 'manifest.json')],
                              cwd=ROOT, capture_output=True, text=True)

    def mutate_manifest(self, change):
        path = self.assets / 'manifest.json'
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data))

    def test_actual_synthesized_pack_has_all_ten_valid_assets(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('10 assets', result.stdout)

    def update_hash(self, name):
        digest = hashlib.sha256((self.assets / name).read_bytes()).hexdigest()
        self.mutate_manifest(lambda data: next(item for item in data['assets'] if item['file'] == name).update(sha256=digest))

    def test_optimized_python_still_rejects_missing_provenance(self):
        self.mutate_manifest(lambda data: data.pop('origin'))
        result = subprocess.run([sys.executable, '-O', str(SCRIPT), str(self.assets / 'manifest.json')],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_wrong_sample_rate_is_rejected_with_valid_hash(self):
        with wave.open(str(self.assets / 'eat.wav'), 'wb') as stream:
            stream.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
            stream.writeframes(b'\x01\x00' * 3360)
        self.update_hash('eat.wav')
        self.assertIn('44.1kHz', self.check().stderr)

    def test_peak_is_rejected_with_valid_hash(self):
        with wave.open(str(self.assets / 'eat.wav'), 'wb') as stream:
            stream.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            stream.writeframes(b'\xff\x7f' * 3087)
        self.update_hash('eat.wav')
        self.assertIn('headroom', self.check().stderr)

    def test_leading_silence_is_rejected_with_valid_hash(self):
        with wave.open(str(self.assets / 'eat.wav'), 'wb') as stream:
            stream.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            stream.writeframes(b'\x00\x00' * 500 + b'\x01\x00' * 2587)
        self.update_hash('eat.wav')
        self.assertIn('leading silence', self.check().stderr)

    def test_missing_wave_is_rejected(self):
        (self.assets / 'eat.wav').unlink()
        self.assertNotEqual(self.check().returncode, 0)

    def test_modified_bytes_are_rejected_even_if_header_is_valid(self):
        path = self.assets / 'eat.wav'
        data = bytearray(path.read_bytes())
        data[-4] ^= 1
        path.write_bytes(data)
        self.assertNotEqual(self.check().returncode, 0)

    def test_stereo_source_is_rejected(self):
        with wave.open(str(self.assets / 'eat.wav'), 'wb') as stream:
            stream.setparams((2, 2, 44100, 0, 'NONE', 'not compressed'))
            stream.writeframes(b'\x00' * 400)
        self.update_hash('eat.wav')
        self.assertIn('mono', self.check().stderr)

    def test_path_escape_is_rejected(self):
        self.mutate_manifest(lambda data: data['assets'][0].update(file='../outside.wav'))
        self.assertNotEqual(self.check().returncode, 0)

    def test_missing_origin_is_rejected(self):
        self.mutate_manifest(lambda data: data.pop('origin'))
        self.assertNotEqual(self.check().returncode, 0)

    def test_missing_event_is_rejected(self):
        self.mutate_manifest(lambda data: data['assets'].pop())
        self.assertNotEqual(self.check().returncode, 0)


if __name__ == '__main__':
    unittest.main()
