"""Group request contracts. IDs are validated again against their owner in storage."""
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator, field_validator

class GroupCreateIn(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    bot_ids: list[int] = Field(min_length=2, max_length=4)
    default_bot_id: int

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
        if self.default_bot_id not in self.bot_ids:
            raise ValueError("默认回应者必须是群成员")
        return self

class GroupPatchIn(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    default_bot_id: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def valid_patch(self):
        if "default_bot_id" in self.model_fields_set and self.default_bot_id is None:
            raise ValueError("默认回应者不能为空")
        if self.name is not None:
            self.name = GroupCreateIn.clean_name(self.name)
        return self

class GroupChatIn(BaseModel):
    client_request_id: UUID
    message: str = Field(min_length=1, max_length=2000)
    mode: Literal["single", "round"] = "single"
    target_bot_id: int | None = Field(default=None, gt=0)

    @model_validator(mode="after")
    def validate_message(self):
        self.message = self.message.strip()
        if not self.message:
            raise ValueError("消息不能为空")
        if self.mode == "round" and self.target_bot_id is not None:
            raise ValueError("大家讨论时不能指定单个成员")
        return self

class GroupRetryIn(BaseModel):
    client_request_id: UUID
