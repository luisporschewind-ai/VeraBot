"""记忆策略（Policy）：规范化、哈希、敏感信息检测、注入特征检测、上限常量。纯函数，不访问数据库。

Boss 决策（2026-10-01，MEMORY_GROWTH §17 Q2）：
- 凭据 / 证件号 / 卡号（密码、验证码、密钥、身份证号、银行卡号……）**永不保存** → sensitive_credential
- 健康、财务信息**可以保存**，但正文加密存储（sensitivity = health / finance），界面标注「敏感」
- 其他特殊类别（宗教、政治、性取向、精确住址、他人联系方式）v1 仍不保存 → sensitive_category
- 提示注入特征 → blocked_content
"""
import hashlib
import re
import unicodedata

from ...core import config

TYPES_M1 = ("profile", "preference", "fact")          # M1 允许由对话 / 记忆页写入的类型
ALL_TYPES = ("profile", "preference", "fact", "style", "summary", "routine")
SCOPES_WRITABLE = ("global", "bot")
MEMORY_ACCESS = ("none", "bot", "bot_and_global")
SENSITIVE_PLACEHOLDER = {"health": "[健康信息]", "finance": "[财务信息]"}

# 零宽 / bidi / 控制字符
_HIDDEN = re.compile("[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]")
_WS = re.compile(r"\s+")


def clean(text: str) -> str:
    """存储用正文：去隐藏字符、合并空白、去首尾空白（保留原有标点与全角字符）。"""
    t = _HIDDEN.sub("", text or "")
    return _WS.sub(" ", t).strip()


def _canonical(text: str) -> str:
    """去重用规范形：NFKC（全角→半角）+ 小写 + 去空白 + 去句末标点。"""
    t = unicodedata.normalize("NFKC", clean(text)).lower()
    t = _WS.sub("", t)
    return t.rstrip("。.!！~～;；,，")


def content_hash(text: str, sensitivity: str = "normal") -> str:
    canon = _canonical(text)
    if sensitivity != "normal":
        from ...core import crypto
        return crypto.keyed_hash(canon)
    return hashlib.sha256(canon.encode()).hexdigest()


# ---------------- 敏感信息检测 ----------------
_CRED_WORDS = re.compile(
    r"密码|口令|验证码|校验码|动态码|安全码|pin\s*码|\bpin\b|密钥|秘钥|私钥|公钥|助记词|api\s*key|apikey|access\s*key|secret|"
    r"\btoken\b|password|passcode|\botp\b|cvv|身份证|证件号|护照号|社保号|银行卡号|信用卡号|卡号|银行账号|账户号", re.I)
_SECRET_PATTERNS = [
    re.compile(r"\bsk-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"\b(?:ghp|gho|xox[abpr]|AKIA)[A-Za-z0-9_\-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]
_LONG_TOKEN = re.compile(r"[A-Za-z0-9+/=_\-]{20,}")
_DIGIT_RUN = re.compile(r"(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)")
_ID18 = re.compile(r"(?<![0-9A-Za-z])\d{17}[\dXx](?![0-9A-Za-z])")
_PASSPORT = re.compile(r"(?<![A-Za-z0-9])[EGDSP]\d{8}(?![0-9])")

_HEALTH = re.compile(
    r"疾病|生病|患有|患了|得了.{0,6}(病|症|炎|癌)|诊断|确诊|病史|病情|用药|服药|吃药|药物|处方|过敏|怀孕|孕期|备孕|流产|"
    r"抑郁|焦虑症|心理(健康|咨询|治疗)|精神(病|科)|失眠|血压|血糖|糖尿病|高血压|心脏病|哮喘|癌|肿瘤|手术|住院|体检|"
    r"月经|生理期|艾滋|hiv|残疾|视力|听力|体重|身高|胆固醇|过敏原|疫苗|医生说|复诊", re.I)
_FINANCE = re.compile(
    r"收入|工资|薪水|薪资|月薪|年薪|奖金|存款|储蓄|积蓄|负债|欠款|欠债|债务|贷款|房贷|车贷|借款|信用卡额度|额度|"
    r"投资|股票|基金|理财|余额|资产|净资产|退休金|养老金|公积金|保险|税后|税前|个税|账单|花呗|借呗", re.I)
_SPECIAL = re.compile(
    r"宗教|信仰|佛教|基督教|天主教|伊斯兰|穆斯林|道教|政治(立场|倾向|观点)|党员|政党|性取向|同性恋|双性恋|跨性别|"
    r"门牌号|详细(住址|地址)|家庭住址|住址是|住在.{0,12}(号楼|单元|室|号院|弄\d)|(\d+号楼|\d+单元|\d+室)", re.I)
_PHONE = re.compile(r"(?<!\d)1[3-9]\d{9}(?!\d)")
_EMAIL = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")

# ---------------- 注入特征 ----------------
_INJECTION = [
    re.compile(r"忽略.{0,8}(以上|之前|前面|上述|所有|全部|先前).{0,10}(指令|规则|提示|要求|设定|内容)"),
    re.compile(r"(ignore|disregard|forget)\s+(all\s+|any\s+)?(the\s+)?(previous|prior|above|earlier)\s+(instructions|rules|prompts?)", re.I),
    re.compile(r"system\s*prompt|系统提示|系统指令|开发者模式|developer\s+mode|jailbreak|越狱", re.I),
    re.compile(r"you\s+are\s+now|from\s+now\s+on\s+you|你现在是|你从现在起是|扮演(一个|成)?.{0,6}(角色|助手|ai)", re.I),
    re.compile(r"调用.{0,8}(工具|函数|function|tool)", re.I),
    re.compile(r"\b(ask_bot|get_weather|create_reminder|list_reminders|manage_reminder|remember|forget_memory|mcp__\w+)\b", re.I),
    re.compile(r"<\s*/?\s*(user_memory|system|assistant|tool|instructions?|untrusted\w*)\b", re.I),
    re.compile(r"</"),
]


def _luhn(digits: str) -> bool:
    total, alt = 0, False
    for ch in reversed(digits):
        d = int(ch)
        if alt:
            d = d * 2 - 9 if d * 2 > 9 else d * 2
        total += d
        alt = not alt
    return total % 10 == 0


def _id18_valid(s: str) -> bool:
    w = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
    check = "10X98765432"
    try:
        return check[sum(int(s[i]) * w[i] for i in range(17)) % 11] == s[17].upper()
    except ValueError:
        return False


def _looks_like_secret(text: str) -> bool:
    if any(p.search(text) for p in _SECRET_PATTERNS):
        return True
    for m in _LONG_TOKEN.finditer(text):
        tok = m.group(0)
        if re.search(r"\d", tok) and re.search(r"[A-Za-z]", tok) and not tok.lower().startswith(("http", "www")):
            return True
    return False


def check(text: str) -> tuple[str | None, str]:
    """返回 (错误码 | None, sensitivity)。错误码：invalid / too_long / sensitive_credential / blocked_content / sensitive_category。
    sensitivity：normal / health / finance（health、finance 允许保存，但需加密）。"""
    t = clean(text)
    if not t:
        return "invalid", "normal"
    if len(t) > config.MEMORY_MAX_CHARS:
        return "too_long", "normal"
    if _CRED_WORDS.search(t) or _looks_like_secret(t):
        return "sensitive_credential", "normal"
    if any(_id18_valid(m.group(0)) for m in _ID18.finditer(t)) or _PASSPORT.search(t):
        return "sensitive_credential", "normal"
    for m in _DIGIT_RUN.finditer(t):
        digits = re.sub(r"\D", "", m.group(0))
        if 13 <= len(digits) <= 19 and _luhn(digits):
            return "sensitive_credential", "normal"
    if any(p.search(t) for p in _INJECTION):
        return "blocked_content", "normal"
    if _SPECIAL.search(t) or _PHONE.search(t) or _EMAIL.search(t):
        return "sensitive_category", "normal"
    if _HEALTH.search(t):
        return None, "health"
    if _FINANCE.search(t):
        return None, "finance"
    return None, "normal"


MESSAGES = {
    "invalid": "记忆内容不能为空",
    "too_long": f"记忆最多 {config.MEMORY_MAX_CHARS} 个字",
    "sensitive_credential": "密码、验证码、密钥、证件号、卡号等信息不会被记住",
    "sensitive_category": "宗教、政治、性取向、精确住址、他人联系方式等信息不会被记住",
    "blocked_content": "这段内容看起来像是指令而不是关于你的信息，不能保存为记忆",
    "memory_disabled": "记忆功能已关闭",
    "memory_limit": "记忆已达上限，请在「Vera 了解的你」中整理",
    "proposal_cap": "本轮提议记忆的次数已达上限",
    "not_found": "记忆不存在",
}


def render_safe(text: str, limit: int | None = None) -> str:
    """注入 prompt 前再次清洗：去隐藏字符、单行化、尖括号转全角（防伪造闭合标签）、截断。"""
    t = clean(text).replace("<", "＜").replace(">", "＞")
    limit = limit or config.MEMORY_MAX_CHARS
    return t[:limit]
