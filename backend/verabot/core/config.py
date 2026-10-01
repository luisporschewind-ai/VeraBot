"""集中配置：全部来自环境变量，绝不硬编码密钥。"""
import os
import secrets
from pathlib import Path

# 路径：backend/ 为独立项目根目录（BACKEND_DIR）；数据默认放在 backend/data/（已 gitignore）
BACKEND_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = Path(os.getenv("VERABOT_DATA_DIR", BACKEND_DIR / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = Path(os.getenv("VERABOT_DB", DATA_DIR / "verabot.db"))
# Web 客户端（可选）：单仓库开发时自动使用 ../frontend/web；单独交付后端时不存在则只提供 API
WEB_DIR = Path(os.getenv("VERABOT_WEB_DIR", BACKEND_DIR.parent / "frontend" / "web"))

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")

# Bot 数量软上限（Soft limit，可配置；取代 v0.1 的硬编码 5）。兼容旧变量 VERABOT_MAX_BOTS
MAX_BOTS_PER_USER = int(os.getenv("MAX_BOTS_PER_USER", os.getenv("VERABOT_MAX_BOTS", "20")))
HISTORY_WINDOW = int(os.getenv("VERABOT_HISTORY_WINDOW", "20"))  # 注入上下文的历史消息条数
MAX_TOOL_ROUNDS = int(os.getenv("VERABOT_MAX_TOOL_ROUNDS", "4"))
DAILY_TOKEN_QUOTA = int(os.getenv("VERABOT_DAILY_TOKEN_QUOTA", "200000"))  # 每用户每日 Token 预算（可被 users.token_budget 覆盖）

# ---- 多 Agent 协作护栏（Multi-agent guardrails）----
MAX_DELEGATION_DEPTH = int(os.getenv("VERABOT_MAX_DELEGATION_DEPTH", "1"))        # 委派最大跳数，默认 1 跳
MAX_DELEGATIONS_PER_TURN = int(os.getenv("VERABOT_MAX_DELEGATIONS_PER_TURN", "3"))  # 单轮对话（一次用户请求）内委派次数上限
MAX_SHARED_CONTEXT = int(os.getenv("VERABOT_MAX_SHARED_CONTEXT", "2000"))          # shared_context 字符上限
EMPTY_REPLY_RETRIES = int(os.getenv("VERABOT_EMPTY_REPLY_RETRIES", "1"))            # LLM 空回复自动重试次数
TIMEZONE = os.getenv("VERABOT_TZ", "Asia/Shanghai")
TOKEN_TTL_HOURS = int(os.getenv("VERABOT_TOKEN_TTL_HOURS", str(24 * 30)))


def _jwt_secret() -> str:
    env = os.getenv("VERABOT_JWT_SECRET")
    if env:
        return env
    f = DATA_DIR / ".jwt_secret"
    if not f.exists():
        f.write_text(secrets.token_urlsafe(48))
        f.chmod(0o600)
    return f.read_text().strip()


JWT_SECRET = _jwt_secret()

# 语音转写（Speech-to-Text）
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
TRANSCRIBE_MODELS = [m.strip() for m in os.getenv("VERABOT_TRANSCRIBE_MODELS", "gpt-4o-mini-transcribe,whisper-1").split(",") if m.strip()]
TRANSCRIBE_MAX_BYTES = int(os.getenv("VERABOT_TRANSCRIBE_MAX_BYTES", str(10 * 1024 * 1024)))  # 10 MB
TRANSCRIBE_MAX_SECONDS = float(os.getenv("VERABOT_TRANSCRIBE_MAX_SECONDS", "60"))
# 可选本地回退：安装 faster-whisper 后，OpenAI 不可用（如额度耗尽）时使用本地模型；VERABOT_LOCAL_STT=0 关闭
LOCAL_STT = os.getenv("VERABOT_LOCAL_STT", "1") != "0"
LOCAL_STT_MODEL = os.getenv("VERABOT_LOCAL_STT_MODEL", "small")

# ---- 记忆（Memory，schema v4，见 docs/design/MEMORY_GROWTH.md）----
MEMORY_ENABLED = os.getenv("VERABOT_MEMORY", "1") != "0"                         # 全局功能开关（运维）
MEMORY_MAX_ACTIVE = int(os.getenv("VERABOT_MEMORY_MAX_ACTIVE", "200"))           # 每用户生效记忆上限（不含 summary）
MEMORY_MAX_CHARS = int(os.getenv("VERABOT_MEMORY_MAX_CHARS", "200"))             # 单条正文上限
MEMORY_INJECT_MAX = int(os.getenv("VERABOT_MEMORY_INJECT_MAX", "12"))            # 每轮最多注入条数
MEMORY_INJECT_CHARS = int(os.getenv("VERABOT_MEMORY_INJECT_CHARS", "1000"))      # 每轮注入正文总字数
MEMORY_PROPOSALS_PER_TURN = int(os.getenv("VERABOT_MEMORY_PROPOSALS_PER_TURN", "2"))
MEMORY_PROPOSAL_TTL_DAYS = int(os.getenv("VERABOT_MEMORY_PROPOSAL_TTL_DAYS", "7"))
MEMORY_REJECT_COOLDOWN_DAYS = int(os.getenv("VERABOT_MEMORY_REJECT_COOLDOWN_DAYS", "30"))
# 敏感记忆（健康 / 财务）加密密钥：VERABOT_MEMORY_ENC_KEY，留空则自动生成 data/.memory_key（见 core/crypto.py）
