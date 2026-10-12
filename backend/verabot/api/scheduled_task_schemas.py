from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator

class CreateTask(BaseModel):
    model_config=ConfigDict(extra='forbid')
    bot_id: int = Field(gt=0)
    title: str = Field(min_length=1,max_length=200)
    instruction: str = Field(min_length=1,max_length=8000)
    start_at: str
    timezone: str
    repeat: Literal['once','daily','weekdays','weekly']='once'
    weekdays: list[int]=Field(default_factory=list,max_length=7)
    misfire_policy: Literal['skip','latest']='skip'
    @field_validator('title','instruction')
    @classmethod
    def nonblank(cls,v):
        if not v.strip(): raise ValueError('内容不能为空')
        return v.strip()

class UpdateTask(BaseModel):
    model_config=ConfigDict(extra='forbid')
    expected_version: int = Field(ge=1)
    title: str | None = Field(default=None,min_length=1,max_length=200)
    instruction: str | None = Field(default=None,min_length=1,max_length=8000)
    start_at: str | None = None
    timezone: str | None = None
    repeat: Literal['once','daily','weekdays','weekly'] | None = None
    weekdays: list[int] | None = Field(default=None,max_length=7)
    misfire_policy: Literal['skip','latest'] | None = None
    @field_validator('title','instruction')
    @classmethod
    def nonblank(cls,v):
        if v is not None and not v.strip(): raise ValueError('内容不能为空')
        return v.strip() if v is not None else v

class Version(BaseModel):
    model_config=ConfigDict(extra='forbid')
    expected_version: int = Field(ge=1)
