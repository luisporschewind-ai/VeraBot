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
# 2026-10-03 起默认 deepseek-flash（DeepSeek-V4.1-Flash，支持看图）；旧名 deepseek-chat 官方已于 2026-07-24 停用。
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-flash")
# deepseek-flash 默认开启思考模式；带工具的请求必须回传之前各轮的 reasoning_content，否则 400。
# 我们不保存 reasoning_content，所以默认关闭（请求体带 {"thinking": {"type": "disabled"}}）。
# 设成 1 只会去掉这个字段（让服务端默认开启思考）——在 reasoning_content 回传实现之前不要打开。
DEEPSEEK_THINKING = os.getenv("VERABOT_DEEPSEEK_THINKING", "0").strip().lower() in ("1", "true", "yes", "on")

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
# 图片附件（schema v12，见 docs/design/ATTACHMENTS_DESIGN.md）：文件在 DATA_DIR/attachments，元数据在 SQLite
ATTACHMENTS_DIR = Path(os.getenv("VERABOT_ATTACHMENTS_DIR", DATA_DIR / "attachments"))
ATTACHMENT_MAX_BYTES = int(os.getenv("VERABOT_ATTACHMENT_MAX_BYTES", str(10 * 1024 * 1024)))  # 单张上限 10MB
ATTACHMENTS_PER_DAY = int(os.getenv("VERABOT_ATTACHMENTS_PER_DAY", "50"))                   # 每人每天张数
ATTACHMENT_USER_QUOTA_BYTES = int(os.getenv("VERABOT_ATTACHMENT_USER_QUOTA", str(500 * 1024 * 1024)))  # 每人总量
ATTACHMENT_PENDING_TTL_HOURS = 24                                                            # 未发送的上传保留时间
# 账号（schema v9，见 docs/design/AUTH_REFACTOR.md）：访问令牌 7 天，刷新令牌 60 天（每次刷新轮换并重新计时）
TOKEN_TTL_HOURS = int(os.getenv("VERABOT_TOKEN_TTL_HOURS", str(24 * 7)))
REFRESH_TTL_DAYS = int(os.getenv("VERABOT_REFRESH_TTL_DAYS", "60"))
AUTH_CODE_TTL_SECONDS = int(os.getenv("VERABOT_AUTH_CODE_TTL", "600"))       # 邮箱验证码有效期 10 分钟
AUTH_CODE_MAX_ATTEMPTS = 5                                                   # 每个验证码最多试 5 次
AUTH_CODE_COOLDOWN_SECONDS = int(os.getenv("VERABOT_AUTH_CODE_COOLDOWN", "60"))  # 同一邮箱两次发码间隔
AUTH_CODE_DAILY_LIMIT = int(os.getenv("VERABOT_AUTH_CODE_DAILY", "10"))     # 同一邮箱每天最多发码次数
AUTH_LOCK_THRESHOLD = 5                                                      # 同一账号连续密码错误次数
AUTH_LOCK_MINUTES = 15
# 发信：VERABOT_MAIL_BACKEND=console（默认，验证码写日志）/ smtp；SMTP 变量见 services/mailer.py 与 .env.example


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
# ---- 记忆 M2：滚动摘要 + 风格校准（schema v14，MEMORY_GROWTH §11.1）----
MEMORY_SUMMARY_MIN_MESSAGES = int(os.getenv("VERABOT_MEMORY_SUMMARY_MIN", "20"))   # 窗口外累计这么多条才摘要
MEMORY_SUMMARY_MAX_CHARS = int(os.getenv("VERABOT_MEMORY_SUMMARY_MAX_CHARS", "400"))
MEMORY_SUMMARY_MAX_INPUT = int(os.getenv("VERABOT_MEMORY_SUMMARY_MAX_INPUT", "200"))  # 单次摘要最多读入的消息条数
MEMORY_JOBS_POLL_SECONDS = float(os.getenv("VERABOT_MEMORY_JOBS_POLL", "5"))       # worker 空闲轮询间隔
MEMORY_JOBS_MAX_ATTEMPTS = int(os.getenv("VERABOT_MEMORY_JOBS_MAX_ATTEMPTS", "3"))  # 失败重试上限（含首次）
MEMORY_STYLE_TOO_LONG_WINDOW_DAYS = int(os.getenv("VERABOT_MEMORY_STYLE_WINDOW_DAYS", "14"))
MEMORY_STYLE_TOO_LONG_MIN = int(os.getenv("VERABOT_MEMORY_STYLE_TOO_LONG_MIN", "3"))
MEMORY_SUMMARY_BUDGET_SKIP = float(os.getenv("VERABOT_MEMORY_SUMMARY_BUDGET_SKIP", "0.9"))  # 预算用到这里就跳过

# ---- MCP（schema v8，见 docs/design/MCP_CAPABILITY.md）----
# 地址、超时、重试与熔断都在调用时读取环境变量，测试可以在导入之后再改。
# 默认请求协议 2025-06-18；服务器若协商更低版本（如 AWS 的 2025-03-26），客户端接受并在后续请求带上。
MCP_PROTOCOL_VERSION = "2025-06-18"
MCP_TIMEOUT_DEFAULT = 15  # 秒。建议 10–15；测试可调低。单次 HTTP 超时，连接与读取共用（M1 已如此，M2 不拆开）。
MCP_CALLS_PER_TURN_DEFAULT = 8
MCP_MAX_TOOLS_PER_SERVER_DEFAULT = 50
MCP_MAX_RESULT_CHARS_DEFAULT = 8000
MCP_MAX_TOOLS_PER_BOT = 20
MCP_RETRY_MAX_DEFAULT = 2            # 可重试错误的额外次数（不含第一次）
MCP_RETRY_BACKOFF_DEFAULT = "0.5,2"  # 秒，按尝试序号取，用完后沿用最后一档；另加最多 25% 抖动
MCP_BREAKER_THRESHOLD_DEFAULT = 5    # 同一服务器连续传输失败这么多次后打开熔断
MCP_BREAKER_COOLDOWN_DEFAULT = 60    # 秒。打开期间不发请求；到期后放行一次探测


def plugin_default_installed() -> set[str]:
    """新用户预装的插件 id。

    Q6（2026-10-03）：全部不预装，包括 Microsoft Learn。
    `VERABOT_MCP_LEARN_ENABLED` / `VERABOT_MCP_AWS_ENABLED` 不再决定预装；
    地址仍由对应的 `*_URL` 环境变量提供。返回空集合时，迁移也不会为「没用过」的
    目录行写 uninstalled 墓碑，避免以后若重新打开预装却永远装不上。
    """
    return set()
