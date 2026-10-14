from pydantic import BaseModel,Field
from .schemas import ChatIn

class ChatInput(ChatIn):
    client_request_id:str=Field(min_length=1,max_length=128)
    expected_generation:int=Field(ge=1)
class StopInput(BaseModel):
    expected_version:int=Field(ge=1)
    control_request_id:str=Field(min_length=1,max_length=128)
class AnswerInput(BaseModel):
    expected_version:int=Field(ge=1)
    client_request_id:str=Field(min_length=1,max_length=128)
    wait_id:str=Field(min_length=1,max_length=128)
    message:str=Field(min_length=1,max_length=4000)
class MessageRead(BaseModel):
    message_id:int=Field(gt=0)
    publication_revision:int=Field(gt=0)
class ReadInput(BaseModel):
    generation:int=Field(ge=1)
    messages:list[MessageRead]=Field(max_length=100)
