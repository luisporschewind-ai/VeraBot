"""Public typed contracts for durable group routing and execution."""
from typing import Any, Literal, NotRequired, TypedDict


class GroupInput(TypedDict):
    client_request_id: str
    message: str
    target_member_ids: list[int]
    everyone: bool
    reply_to_message_id: int | None
    attachment_ids: list[str]
    expected_task_id: int | None
    expected_version: int | None
    clarification_id: int | None


class RouteDecision(TypedDict):
    intent: Literal["respond", "clarify", "continue", "replace", "stop"]
    speaker_member_ids: list[int]
    goal: str
    missing_information: list[str]
    clarification_id: int | None
    usage: dict[str, Any] | None
    usage_unknown: bool


class GroupAction(TypedDict):
    kind: Literal["completed", "consult", "handoff", "await_user"]
    target_member_id: int | None
    goal: str
    result: str
    context_message_ids: list[int]
    attachment_ids: list[str]
    completion_criteria: str
    issue_key: str | None
    missing_information: list[str]


class GroupTask(TypedDict):
    id: int
    group_id: int
    goal: str
    state: Literal["queued", "running", "awaiting_user", "completed", "stopped", "failed", "interrupted"]
    version: int
    owner_member_id: int | None
    root_message_id: int | None
    created_at: str
    updated_at: str
    finished_at: str | None


class GroupStep(TypedDict):
    id: int
    task_id: int
    input_id: int
    kind: Literal["route", "member"]
    action_key: str | None
    version: int
    member_id: int | None
    status: Literal["queued", "running", "completed", "failed", "stopped", "interrupted", "awaiting_user"]
    input: dict[str, Any]
    result: NotRequired[dict[str, Any] | None]
    consult_return_step_id: int | None
    issue_key: str | None


class GroupClarification(TypedDict):
    id: int
    task_id: int
    group_id: int
    owner_member_id: int | None
    original_request: str
    missing_information: list[str]
    latest_question_message_id: int | None
    status: Literal["active", "awaiting_user", "resolved", "cancelled"]
    created_at: str
    updated_at: str


class GroupEvent(TypedDict):
    id: int
    task_id: int | None
    version: int
    kind: str
    payload: dict[str, Any]
    created_at: str
