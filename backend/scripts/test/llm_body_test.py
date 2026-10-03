"""P0 模型迁移：DeepSeek 请求体（不发网络请求，不需要 Key）。

LLM-01 默认模型 deepseek-flash（未设置 DEEPSEEK_MODEL 时）
LLM-02 请求体带 thinking: {"type": "disabled"}，流式 / 非流式、带不带 tools 都一样
LLM-03 tools / stream_options 仍按原规则组装
LLM-04 VERABOT_DEEPSEEK_THINKING=1 时不发 thinking 字段
LLM-05 /api/health 的 model 字段等于配置的模型
"""
import importlib
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
TMP = tempfile.mkdtemp()
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.pop("DEEPSEEK_MODEL", None)
os.environ.pop("VERABOT_DEEPSEEK_THINKING", None)
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")

from verabot.core import config  # noqa: E402
from verabot.services import llm  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  {detail}"))


msgs = [{"role": "user", "content": "hi"}]
tools = [{"type": "function", "function": {"name": "get_weather", "parameters": {"type": "object"}}}]

check("LLM-01 default model is deepseek-flash", config.DEEPSEEK_MODEL == "deepseek-flash", config.DEEPSEEK_MODEL)
bodies = [llm._body(msgs, t, s) for t in (None, tools) for s in (True, False)]
check("LLM-02 thinking disabled on every request",
      all(b.get("thinking") == {"type": "disabled"} and b["model"] == "deepseek-flash" for b in bodies), bodies)
b_stream_tools = llm._body(msgs, tools, True)
b_plain = llm._body(msgs, None, False)
check("LLM-03 tools / stream_options unchanged",
      b_stream_tools["tools"] == tools and b_stream_tools["stream_options"] == {"include_usage": True}
      and "tools" not in b_plain and "stream_options" not in b_plain and b_plain["temperature"] == 0.7,
      (b_stream_tools, b_plain))

os.environ["VERABOT_DEEPSEEK_THINKING"] = "1"
importlib.reload(config)
importlib.reload(llm)
check("LLM-04 VERABOT_DEEPSEEK_THINKING=1 omits the field", "thinking" not in llm._body(msgs, tools, True))
os.environ.pop("VERABOT_DEEPSEEK_THINKING")
importlib.reload(config)
importlib.reload(llm)

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402

with TestClient(app) as cli:
    h = cli.get("/api/health").json()
check("LLM-05 /api/health reports the configured model", h.get("model") == config.DEEPSEEK_MODEL == "deepseek-flash", h)

print(f"SUMMARY {sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
