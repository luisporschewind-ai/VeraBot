"""Detached workers must load backend/.env before verabot.core.config is imported."""
import os, subprocess, sys, tempfile, unittest
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND))


class WorkerEnvTest(unittest.TestCase):
    def test_load_env_file_no_override_and_quotes(self):
        from verabot.core.envfile import load_env_file
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".env"
            p.write_text("# c\nWENV_A=\"one\"\nexport WENV_B=two\nWENV_C=\nWENV_KEEP=file\n", encoding="utf-8")
            os.environ["WENV_KEEP"] = "env"
            for k in ("WENV_A", "WENV_B", "WENV_C"): os.environ.pop(k, None)
            loaded = load_env_file(p)
            self.assertEqual(os.environ["WENV_A"], "one")
            self.assertEqual(os.environ["WENV_B"], "two")
            self.assertNotIn("WENV_C", os.environ)
            self.assertEqual(os.environ["WENV_KEEP"], "env")
            self.assertEqual(sorted(loaded), ["WENV_A", "WENV_B"])

    def test_config_sees_key_when_loaded_first(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / ".env"
            p.write_text("DEEPSEEK_API_KEY=sk-test-worker\n", encoding="utf-8")
            env = {k: v for k, v in os.environ.items() if k != "DEEPSEEK_API_KEY"}
            code = ("from verabot.core.envfile import load_env_file; load_env_file(%r); "
                    "from verabot.core import config; print(config.DEEPSEEK_API_KEY)") % str(p)
            out = subprocess.run([sys.executable, "-c", code], cwd=BACKEND, env=env, capture_output=True, text=True)
            self.assertEqual(out.stdout.strip(), "sk-test-worker", out.stderr)

    def test_worker_mains_load_env_before_imports(self):
        for name in ("chat_tasks", "owned_tasks", "scheduled_tasks"):
            src = (BACKEND / "verabot/services" / name / "__main__.py").read_text(encoding="utf-8")
            self.assertIn("load_env_file()", src, name)
            self.assertLess(src.index("load_env_file()"), src.index("from ... import db"), name)

    def test_require_exits_when_missing(self):
        from verabot.core.envfile import require
        os.environ.pop("WENV_MISSING", None)
        with self.assertRaises(SystemExit):
            require("WENV_MISSING")


if __name__ == "__main__":
    unittest.main()
