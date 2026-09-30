"""请求体校验（Pydantic schemas）。"""
from pydantic import BaseModel, Field, field_validator


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=6, max_length=128)


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


class BotIn(BotPerms):
    name: str = Field(min_length=1, max_length=64)
    avatar: str = Field(default="🤖", max_length=8)
    color: str = Field(default="#0F766E", max_length=9)
    persona: str = Field(default="", max_length=1000)
    instructions: str = Field(default="", max_length=2000)

    @field_validator("name")
    @classmethod
    def _check_name(cls, v):
        return _clean_name(v)


class BotPatch(BotPerms):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    avatar: str | None = Field(default=None, max_length=8)
    color: str | None = Field(default=None, max_length=9)
    persona: str | None = Field(default=None, max_length=1000)
    instructions: str | None = Field(default=None, max_length=2000)

    @field_validator("name")
    @classmethod
    def _check_name(cls, v):
        return _clean_name(v)


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=4000)

    @field_validator("message")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        """BUG-04：纯空白消息拒绝（422）。"""
        if not v.strip():
            raise ValueError("消息不能为空")
        return v
