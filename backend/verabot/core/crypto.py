"""对称加密（Encryption at rest）：Fernet / MultiFernet + 带密钥的哈希（HMAC-SHA256）。

密钥与数据库分离：优先读环境变量，否则使用数据目录下单独的密钥文件（权限 600，已 gitignore，
与 .jwt_secret 同样的方式自动生成）。只备份数据库而没有密钥文件时，加密内容无法解密。

每个用途一把独立密钥（key name），互不影响：
  memory → 环境变量 VERABOT_MEMORY_ENC_KEY（逗号分隔多把 = 轮换，第一把用于加密），否则 data/.memory_key
  token  → 环境变量 VERABOT_TOKEN_ENC_KEY（同上），否则 data/.token_key：连接器令牌（mcp_credentials，v13）。
           必须与数据库一起备份；丢失后凭据无法解密，插件回到「需要连接」。
  action → 环境变量 VERABOT_ACTION_ENC_KEY（同上），否则 data/.action_key：待确认操作冻结参数（pending_actions，M3）。
           丢失后未确认的操作无法执行，只能取消或过期。
"""
import hashlib
import hmac
import os
import threading

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from .config import DATA_DIR

_KEYS = {
    "memory": ("VERABOT_MEMORY_ENC_KEY", ".memory_key"),
    "token": ("VERABOT_TOKEN_ENC_KEY", ".token_key"),
    "action": ("VERABOT_ACTION_ENC_KEY", ".action_key"),
}
_cache: dict[str, list[bytes]] = {}
_lock = threading.Lock()


def _keys(name: str) -> list[bytes]:
    with _lock:
        if name in _cache:
            return _cache[name]
        env, filename = _KEYS[name]
        raw = os.getenv(env, "").strip()
        if raw:
            keys = [k.strip().encode() for k in raw.split(",") if k.strip()]
        else:
            f = DATA_DIR / filename
            if not f.exists():
                f.write_bytes(Fernet.generate_key())
                f.chmod(0o600)
            keys = [f.read_bytes().strip()]
        for k in keys:
            Fernet(k)   # 格式校验：非法密钥在启动 / 首次使用时就报错
        _cache[name] = keys
        return keys


def encrypt(plaintext: str, name: str = "memory") -> str:
    return MultiFernet([Fernet(k) for k in _keys(name)]).encrypt(plaintext.encode()).decode()


def decrypt(token: str | None, name: str = "memory") -> str | None:
    """解密失败（密钥丢失 / 被篡改）返回 None，由调用方显示占位文字。"""
    if not token:
        return None
    try:
        return MultiFernet([Fernet(k) for k in _keys(name)]).decrypt(token.encode()).decode()
    except (InvalidToken, ValueError):
        return None


def keyed_hash(text: str, name: str = "memory") -> str:
    """带密钥的哈希：敏感内容的去重 / 拒绝冷却用，避免数据库里的哈希被字典反查。"""
    return "h1:" + hmac.new(_keys(name)[0], text.encode(), hashlib.sha256).hexdigest()


def reset_cache():
    """测试用：切换数据目录 / 环境变量后重新读取密钥。"""
    with _lock:
        _cache.clear()
