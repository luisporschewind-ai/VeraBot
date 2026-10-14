"""Group request contracts. IDs are validated again against their owner in storage."""
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator, field_validator

class GroupCreateIn(BaseModel):
    model_config = {"extra": "forbid"}
    name: str = Field(min_length=1, max_length=64)
    bot_ids: list[int] = Field(min_length=2, max_length=4)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value):
        value = value.strip()
        if not value or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("群名不能为空或包含控制字符")
        return value

    @model_validator(mode="after")
    def members_unique(self):
        if len(set(self.bot_ids)) != len(self.bot_ids) or min(self.bot_ids) <= 0:
            raise ValueError("请选择不同的 Bot")
        return self

class GroupPatchIn(BaseModel):
    model_config = {"extra": "forbid"}
    name: str | None = Field(default=None, min_length=1, max_length=64)

    @model_validator(mode="after")
    def valid_patch(self):
        if self.name is not None:
            self.name = GroupCreateIn.clean_name(self.name)
        return self

class GroupMemberAddIn(BaseModel):
    model_config = {"extra": "forbid"}
    bot_id: int = Field(gt=0)

class GroupChatIn(BaseModel):
    client_request_id: UUID
    message: str = Field(default="", max_length=2000)
    mode: Literal["auto", "single", "round"] = "single"
    target_bot_id: int | None = Field(default=None, gt=0)
    attachment_ids: list[str] = Field(default_factory=list, max_length=1)

    @model_validator(mode="after")
    def validate_message(self):
        self.message = self.message.strip()
        if not self.message and not self.attachment_ids:
            raise ValueError("消息或附件不能为空")
        if self.mode == "round" and self.target_bot_id is not None:
            raise ValueError("大家讨论时不能指定单个成员")
        if self.mode == "auto" and self.target_bot_id is not None:
            raise ValueError("自动回应时不能指定单个成员")
        return self

class GroupRetryIn(BaseModel):
    client_request_id: UUID


class GroupInputIn(BaseModel):
    model_config = {"extra": "forbid"}
    client_request_id: UUID
    message: str = Field(default="", max_length=2000)
    target_member_ids: list[int] = Field(default_factory=list, max_length=4)
    everyone: bool = False
    reply_to_message_id: int | None = Field(default=None, gt=0)
    attachment_ids: list[str] = Field(default_factory=list, max_length=1)
    expected_task_id: int | None = Field(default=None, gt=0)
    expected_version: int | None = Field(default=None, ge=1)
    clarification_id: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_input(self):
        self.message = self.message.strip()
        if not self.message and not self.attachment_ids:
            raise ValueError("消息或附件不能为空")
        if len(set(self.target_member_ids)) != len(self.target_member_ids) or any(x <= 0 for x in self.target_member_ids):
            raise ValueError("成员目标必须是不同的有效 ID")
        if self.everyone and self.target_member_ids:
            raise ValueError("全体讨论不能同时指定成员")
        if (self.expected_task_id is None) != (self.expected_version is None):
            raise ValueError("任务 ID 和版本必须同时提供")
        if self.clarification_id is not None and self.expected_task_id is None:
            raise ValueError("回答澄清时需要携带任务版本")
        return self


class GroupTaskCommandIn(BaseModel):
    client_request_id: UUID
    expected_version: int = Field(ge=1)
    message: str = Field(default="", max_length=2000)
