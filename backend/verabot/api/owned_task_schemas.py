from pydantic import BaseModel,ConfigDict,Field,field_validator
class CreateOwnedTask(BaseModel):
 model_config=ConfigDict(extra='forbid')
 bot_id:int|None=Field(default=None,gt=0)
 goal:str=Field(min_length=1,max_length=8000)
 completion_criteria:str=Field(min_length=1,max_length=1000)
 token_limit:int=Field(default=20000,gt=0,le=200000)
 @field_validator('goal','completion_criteria')
 @classmethod
 def nonblank(cls,v):
  if not v.strip():raise ValueError('内容不能为空')
  return v.strip()
class Control(BaseModel):
 model_config=ConfigDict(extra='forbid')
 expected_version:int=Field(ge=1)
 bot_id:int|None=Field(default=None,gt=0)
class Input(Control):
 message:str=Field(min_length=1,max_length=8000)
 @field_validator('message')
 @classmethod
 def nonblank(cls,v):
  if not v.strip():raise ValueError('回答不能为空')
  return v.strip()
