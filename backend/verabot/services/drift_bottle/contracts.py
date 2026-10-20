"""Strict Drift Bottle request/response contracts.

Only whitelisted public fields are modelled. Author account IDs, bot IDs used
for ownership, personas and private turns never appear in public contribution
DTOs. Text limits count Unicode code points, matching Swift `unicodeScalars`.
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

MAX_PUBLIC_LENGTH = 1000
OPENING_MAX_LENGTH = 120
CHAT_MAX_LENGTH = 300
MEMORY_TITLE_MAX = 80
MEMORY_SUMMARY_MAX = 500
MEMORY_NOTE_MAX = 200
MAX_CONTRIBUTIONS = 50
HOLD_SECONDS = 86400
PAGE_SIZE = 20
RATE_PUBLISH = 5
RATE_DRAW = 10
RATE_GENERATE = 10
GENERATION_WINDOW_SECONDS = 120

Authorship = Literal["owner", "coauthored", "bot_draft"]
ContributionState = Literal["visible", "withdrawn", "hidden"]
DisplayState = Literal["visible", "withdrawn", "hidden", "reported", "blocked"]
EndReason = Literal["returned", "released", "expired"]


class BottleError(ValueError):
    """Business error mapped to HTTP by the router. Never carries another user's data."""

    def __init__(self, status: int, code: str, message: str, *, retry_after: int | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retry_after = retry_after


def _nonblank(value: str) -> str:
    if not value.strip():
        raise ValueError("内容不能为空")
    return value


def _public_text(value: str) -> str:
    _nonblank(value)
    if len(value) > MAX_PUBLIC_LENGTH:
        raise ValueError(f"内容不能超过 {MAX_PUBLIC_LENGTH} 个字符")
    return value


def _request_id(value: str) -> str:
    value = value.strip()
    if not 8 <= len(value) <= 128:
        raise ValueError("请求 ID 长度需在 8–128 之间")
    return value


class _Request(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=False)


class ContributionInput(_Request):
    body: str
    authorship: Authorship

    @field_validator("body")
    @classmethod
    def _body(cls, value: str) -> str:
        return _public_text(value)


class CreateBottleRequest(_Request):
    request_id: str
    bot_id: int = Field(gt=0)
    body: str
    authorship: Authorship

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)

    @field_validator("body")
    @classmethod
    def _body(cls, value: str) -> str:
        return _public_text(value)


class DrawRequest(_Request):
    request_id: str
    bot_id: int = Field(gt=0)

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)


class ReleaseRequest(_Request):
    request_id: str
    lease_token: str = Field(min_length=8, max_length=128)
    expected_version: int = Field(ge=0)
    contribution: ContributionInput | None = None

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)


class TurnRequest(_Request):
    request_id: str
    kind: Literal["opening", "chat", "draft"]
    text: str = Field(default="", max_length=CHAT_MAX_LENGTH)
    quiet: bool = False

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)

    @model_validator(mode="after")
    def _kind(self):
        if self.kind == "chat":
            _nonblank(self.text)
            if len(self.text) > CHAT_MAX_LENGTH:
                raise ValueError(f"消息不能超过 {CHAT_MAX_LENGTH} 个字符")
        return self


class DraftSuggestionRequest(_Request):
    request_id: str
    bot_id: int = Field(gt=0)
    body: str = ""

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)

    @field_validator("body")
    @classmethod
    def _body(cls, value: str) -> str:
        if len(value) > MAX_PUBLIC_LENGTH:
            raise ValueError(f"内容不能超过 {MAX_PUBLIC_LENGTH} 个字符")
        return value


class MemoryRequest(_Request):
    request_id: str

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)


class MemoryPatch(_Request):
    title: str | None = Field(default=None, max_length=MEMORY_TITLE_MAX)
    summary: str | None = Field(default=None, max_length=MEMORY_SUMMARY_MAX)
    owner_note: str | None = Field(default=None, max_length=MEMORY_NOTE_MAX)
    expected_version: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def _one(self):
        if self.title is None and self.summary is None and self.owner_note is None:
            raise ValueError("没有要修改的内容")
        for value in (self.title, self.summary):
            if value is not None:
                _nonblank(value)
        return self


class WithdrawRequest(_Request):
    request_id: str

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)


class ReportRequest(_Request):
    request_id: str
    contribution_id: int = Field(gt=0)
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)

    @field_validator("reason")
    @classmethod
    def _reason(cls, value: str) -> str:
        return _nonblank(value)


class BlockRequest(_Request):
    request_id: str
    contribution_id: int = Field(gt=0)

    @field_validator("request_id")
    @classmethod
    def _rid(cls, value: str) -> str:
        return _request_id(value)


# ---------------------------------------------------------------------------
# Shared response DTOs (public field whitelists; never serialise database rows)
# ---------------------------------------------------------------------------


class PublicContribution(BaseModel):
    id: int
    bottle_id: int
    sequence: int
    kind: Literal["origin", "message"]
    body: str
    state: ContributionState
    display_state: DisplayState
    bot_name: str
    bot_avatar: str
    bot_color: str
    authorship: Authorship
    created_at: float
    is_mine: bool = False
    can_withdraw: bool = False
    can_report: bool = False


class DriftTurn(BaseModel):
    id: int
    role: Literal["user", "bot", "system"]
    kind: Literal["opening", "chat", "draft", "quiet"]
    content: str
    created_at: float


class MemoryCard(BaseModel):
    id: int
    encounter_id: int
    record_id: str
    title: str
    summary: str
    owner_note: str
    edited: bool
    generated_by: Literal["fact", "bot"]
    source_turn_ids: list[int]
    version: int
    created_at: float
    updated_at: float


class EncounterDetail(BaseModel):
    id: int
    bottle_id: int
    bot_id: int | None
    bot_name: str
    bot_avatar: str
    bot_color: str
    bot_deleted: bool
    started_at: float
    expires_at: float
    ended_at: float | None
    end_reason: EndReason | None
    version: int
    bottle_version: int
    lease_token: str
    read_limit: int
    quiet: bool
    remaining_seconds: int
    is_expired: bool
    can_publish: bool
    contributions: list[PublicContribution]
    next_cursor: str | None
    turns: list[DriftTurn]
    memory: MemoryCard | None = None


class ReleaseDetail(BaseModel):
    bottle_id: int
    state: Literal["active", "archived", "empty"]
    public_count: int
    created_at: float
    bot_id: int | None
    bot_name: str
    bot_avatar: str
    bot_color: str
    contributions: list[PublicContribution]


class RecordSummary(BaseModel):
    id: str
    kind: Literal["encounter", "release"]
    title: str
    subtitle: str
    bot_id: int | None
    bot_name: str
    bot_avatar: str
    bot_color: str
    created_at: float
    completed_at: float | None
    has_memory: bool
    contribution_count: int


class RecordDetail(BaseModel):
    id: str
    kind: Literal["encounter", "release"]
    title: str
    subtitle: str
    created_at: float
    completed_at: float | None
    encounter: EncounterDetail | None = None
    release: ReleaseDetail | None = None
    contributions: list[PublicContribution]
    turns: list[DriftTurn]
    memory: MemoryCard | None = None


class Limits(BaseModel):
    max_contributions_per_bottle: int = MAX_CONTRIBUTIONS
    hold_seconds: int = HOLD_SECONDS
    public_length_min: int = 1
    public_length_max: int = MAX_PUBLIC_LENGTH
    opening_max_length: int = OPENING_MAX_LENGTH
    chat_max_length: int = CHAT_MAX_LENGTH
    publish_per_minute: int = RATE_PUBLISH
    draw_per_minute: int = RATE_DRAW
    generate_per_minute: int = RATE_GENERATE


class BottleState(BaseModel):
    server_time: float
    current: EncounterDetail | None
    limits: Limits = Limits()
    has_active_encounter: bool


class OperationInfo(BaseModel):
    request_id: str
    status: Literal["pending", "committed", "failed"]
    kind: str
    error_code: str | None = None
    error_message: str | None = None
    retryable: bool = False


class OperationEnvelope(BaseModel):
    operation: OperationInfo
    result: dict | None = None


class CreateBottleResponse(BaseModel):
    operation: OperationInfo
    record: RecordSummary


class DrawResponse(BaseModel):
    operation: OperationInfo
    encounter: EncounterDetail | None


class ReleaseResponse(BaseModel):
    operation: OperationInfo
    record: RecordDetail


class TurnResponse(BaseModel):
    operation: OperationInfo
    encounter: EncounterDetail
    turn: DriftTurn | None = None
    draft: str | None = None


class DraftSuggestionResponse(BaseModel):
    operation: OperationInfo
    draft: str
    authorship: Authorship = "bot_draft"


class MemoryResponse(BaseModel):
    operation: OperationInfo
    memory: MemoryCard


class WithdrawResponse(BaseModel):
    operation: OperationInfo
    contribution: PublicContribution


class ReportInfo(BaseModel):
    id: int
    contribution_id: int
    state: Literal["pending", "kept", "hidden", "restored"]
    created_at: float


class ReportResponse(BaseModel):
    operation: OperationInfo
    report: ReportInfo


class BlockResponse(BaseModel):
    operation: OperationInfo
    blocked: bool


class RecordList(BaseModel):
    records: list[RecordSummary]
    next_cursor: str | None = None


class StateResponse(BottleState):
    pass
