"""Public group contracts. No user IDs, request hashes or database paths."""
from typing import Any, Literal, NotRequired, TypedDict

class GroupMember(TypedDict):
    id: int
    bot_id: int | None
    name: str
    color: str
    avatar: str
    detail: str
    appearance: dict[str, Any] | None
    available: bool

class Group(TypedDict):
    id: int
    name: str
    members: list[GroupMember]
    default_bot_id: int | None
    read_only: bool
    active_turn_id: int | None
    last_message: "GroupMessage | None"
    created_at: str
    updated_at: str

class GroupChatInput(TypedDict):
    client_request_id: str
    message: str
    mode: NotRequired[Literal['single', 'round']]
    target_bot_id: NotRequired[int | None]

class GroupMessage(TypedDict):
    id: int
    group_id: int
    turn_id: int
    member_id: int | None
    retry_of_message_id: int | None
    role: Literal['user', 'bot']
    content: str
    status: Literal['streaming', 'completed', 'failed', 'stopped', 'interrupted']
    sender_name: str | None
    sender_appearance: dict[str, Any] | None
    usage: dict[str, Any] | None
    created_at: str
    finished_at: str | None

class GroupTurn(TypedDict):
    id: int
    group_id: int
    client_request_id: str
    mode: Literal['single', 'round']
    status: Literal['running', 'completed', 'partial', 'stopped', 'failed', 'interrupted']
    cancel_requested: bool
    target_member_id: int | None
    retry_of_message_id: int | None
    user_message_id: int | None
    context_end_message_id: int | None
    created_at: str
    finished_at: str | None
    messages: list[GroupMessage]
