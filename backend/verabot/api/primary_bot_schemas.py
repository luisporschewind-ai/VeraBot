from pydantic import BaseModel, ConfigDict, Field, StrictBool, model_validator
class PrimaryBotPatch(BaseModel):
 model_config=ConfigDict(extra='forbid')
 primary_bot_id:int|None=Field(default=None,gt=0)
 active_enabled:StrictBool|None=None
 daily_token_limit:int|None=Field(default=None,gt=0,le=200000)
 expected_version:int=Field(ge=1)
 @model_validator(mode='after')
 def no_null_settings(self):
  if any(k in self.model_fields_set and getattr(self,k) is None for k in ('active_enabled','daily_token_limit')):
   raise ValueError('设置不能为空')
  return self
