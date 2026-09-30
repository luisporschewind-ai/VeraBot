"""上下文隔离（Context isolation）：决定被委派的 Bot 能看到什么。

被委派方只收到 question + 限长的 shared_context + 发起方公开资料（名称 / 人设摘要），
绝不包含任何一方的对话历史或私有指令（instructions）。
"""
from ..core.config import MAX_SHARED_CONTEXT

MAX_QUESTION_CHARS = 1000


def public_profile(b: dict) -> str:
    """Bot 的公开资料（Public profile）：仅名称 + 人设摘要；自定义指令 instructions 属于私有配置，不外泄。"""
    return f"{b['name']}（{(b.get('persona') or '通用助理')[:80]}）"


def clean_question(question: str) -> str:
    return (question or "").strip()[:MAX_QUESTION_CHARS]


def limit_shared_context(shared_context: str) -> tuple[str, bool]:
    """返回 (截断后的共享背景, 是否被截断)。上限 MAX_SHARED_CONTEXT 字符。"""
    raw = (shared_context or "").strip()
    return raw[:MAX_SHARED_CONTEXT], len(raw) > MAX_SHARED_CONTEXT


def delegation_message(from_bot: dict, question: str, shared_context: str) -> str:
    """发给被委派 Bot 的唯一一条 user 消息（同时作为审计 payload 保存）。"""
    user_msg = f"【来自 {from_bot['name']} 的咨询】\n{question}"
    if shared_context:
        user_msg += f"\n\n【对方共享的背景】\n{shared_context}"
    return user_msg
