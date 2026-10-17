"""Feed request validation; JSON responses include unknown fields as explicit null."""
from typing import Literal
from pydantic import BaseModel,ConfigDict,Field
Kind=Literal['news','post','video','audio']
class Input(BaseModel):
    model_config=ConfigDict(extra='forbid',str_strip_whitespace=True)
class PlanInput(Input):
    enabled:bool
    bot_ids:list[int]=Field(max_length=20)
    topics:list[str]=Field(max_length=30)
    excluded_topics:list[str]=Field(max_length=30)
    use_memory:bool
    expected_version:int=Field(ge=0)
class SuggestInput(Input):
    use_memory:bool=True
    bot_ids:list[int]=Field(default_factory=list,max_length=20)
    topics:list[str]=Field(default_factory=list,max_length=30)
class SourceInput(Input):
    name:str=Field(min_length=1,max_length=100)
    url:str=Field(min_length=1,max_length=2048)
    kind:Kind
    bot_id:int|None=Field(None,gt=0)
class SourcePatch(Input):
    enabled:bool
class StatePatch(Input):
    read:bool|None=None
    saved:bool|None=None
    dismissed:bool|None=None
