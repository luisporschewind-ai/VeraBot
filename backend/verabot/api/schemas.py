"""请求体校验（Pydantic schemas）。"""
import unicodedata
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from ..services.users import clean_nickname


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=6, max_length=128)


class NicknameIn(BaseModel):
    """PATCH /api/me。先 strip，再限制 1–32 个字（过长的原文在 clean_nickname 里拒绝）。"""
    nickname: str

    @field_validator("nickname", mode="before")
    @classmethod
    def _check(cls, v):
        return clean_nickname(v)


MAX_BOT_TAGS = 5
MAX_TAG_CHARS = 12


def clean_tags(v):
    """标签：trim，丢掉空白和重复（保留首次出现的顺序）。

    最多 5 个，每个最多 12 个字，不能含控制字符。非法时抛 ValueError，由 422 处理成中文提示。
    """
    if not isinstance(v, list):
        raise ValueError("标签必须是列表")
    out: list[str] = []
    seen: set[str] = set()
    for item in v:
        if not isinstance(item, str):
            raise ValueError("标签必须是文字")
        tag = item.strip()
        if not tag:
            continue
        if any(unicodedata.category(ch) == "Cc" for ch in tag):
            raise ValueError("标签不能包含控制字符")
        if len(tag) > MAX_TAG_CHARS:
            raise ValueError("每个标签最多 12 个字")
        if tag in seen:
            continue
        seen.add(tag)
        out.append(tag)
    if len(out) > MAX_BOT_TAGS:
        raise ValueError("每个 Bot 最多 5 个标签")
    return out


def _clean_name(v):
    """BUG-02/03：名称先去首尾空白再校验，纯空白名称拒绝（422）。"""
    if v is None:
        return v
    v = v.strip()
    if not v:
        raise ValueError("Bot 名称不能为空")
    if len(v) > 20:
        raise ValueError("Bot 名称最多 20 个字")
    return v


class BotPerms(BaseModel):
    """多 Agent 权限（Permissions）。None = 不修改。"""
    allowed_tools: list[str] | None = Field(default=None, max_length=20)   # 工具白名单
    delegate_to: list[int] | None = Field(default=None, max_length=100)    # 可委派的目标 Bot id
    accept_delegation: bool | None = None                                  # 是否接受其他 Bot 委派
    memory_access: Literal["none", "bot", "bot_and_global"] | None = None   # 记忆授权（v4）；None = 不修改 / 用默认值


class BotIn(BotPerms):
    name: str = Field(min_length=1, max_length=64)
    avatar: str = Field(default="🤖", max_length=8)
    color: str = Field(default="#0F766E", max_length=9)
    persona: str = Field(default="", max_length=1000)
    instructions: str = Field(default="", max_length=2000)
    tags: list[str] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def _check_name(cls, v):
        return _clean_name(v)

    @field_validator("tags", mode="before")
    @classmethod
    def _check_tags(cls, v):
        if v is None:
            raise ValueError("标签必须是列表")
        return clean_tags(v)


class BotPatch(BotPerms):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    avatar: str | None = Field(default=None, max_length=8)
    color: str | None = Field(default=None, max_length=9)
    persona: str | None = Field(default=None, max_length=1000)
    instructions: str | None = Field(default=None, max_length=2000)
    tags: list[str] | None = None   # None = 不修改；[] = 清空

    @field_validator("name")
    @classmethod
    def _check_name(cls, v):
        return _clean_name(v)

    @field_validator("tags", mode="before")
    @classmethod
    def _check_tags(cls, v):
        if v is None:
            return None
        return clean_tags(v)


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=4000)

    @field_validator("message")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        """BUG-04：纯空白消息拒绝（422）。"""
        if not v.strip():
            raise ValueError("消息不能为空")
        return v


# ---------------- 记忆（Memory，v4） ----------------
MemoryType = Literal["profile", "preference", "fact"]


class MemoryIn(BaseModel):
    """POST /api/memories：记忆页手动添加（直接生效）。正文的策略检查在 services.memory。"""
    content: str = Field(min_length=1, max_length=400)
    type: MemoryType = "fact"
    scope: Literal["global", "bot"] = "global"
    bot_id: int | None = None


class MemoryPatch(BaseModel):
    content: str | None = Field(default=None, min_length=1, max_length=400)
    type: MemoryType | None = None
    scope: Literal["global", "bot"] | None = None
    bot_id: int | None = None


class MemoryConfirmIn(BaseModel):
    """POST /api/memories/{id}/confirm：content 可选（编辑后记住）。"""
    content: str | None = Field(default=None, min_length=1, max_length=400)


class MemorySettingsIn(BaseModel):
    enabled: bool
