"""Strict wire shapes shared by session API and deterministic rule restoration."""
from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field

RULE_VERSION = 'vera-tetris-2'
Action = Literal['start','pause','resume','moveLeft','moveRight','softDrop','rotateClockwise','hardDrop']
Phase = Literal['ready','running','clearing','paused','over']

class WireModel(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)

class Piece(WireModel):
    kind: int = Field(ge=1,le=7)
    rotation: int = Field(ge=0,le=3)
    x: int = Field(ge=-4,le=9)
    y: int = Field(ge=-4,le=19)

class Snapshot(WireModel):
    ruleVersion: Literal['vera-tetris-2']
    board: list[Annotated[int, Field(ge=0,le=7)]] = Field(min_length=200,max_length=200)
    active: Piece | None = None
    next: int = Field(ge=1,le=7)
    bag: list[Annotated[int, Field(ge=1,le=7)]] = Field(max_length=7)
    rngState: int = Field(ge=1,le=4294967295)
    score: int = Field(ge=0,le=10000000)
    lines: int = Field(ge=0,le=100000)
    lockedPieces: int = Field(ge=0)
    phase: Phase
    resumePhase: Literal['running','clearing'] | None = None
    logicalTimeMs: int = Field(ge=0,le=31536000000)
    stepRemainderMs: int = Field(ge=0,le=9)
    gravityRemainingMs: int = Field(ge=1,le=620)
    lockRemainingMs: int = Field(ge=0,le=500)
    lockResetCount: int = Field(ge=0,le=15)
    clearRemainingMs: int = Field(ge=0,le=180)
    pendingClearRows: list[Annotated[int, Field(ge=0,le=19)]] = Field(max_length=4)
    eventSequence: int = Field(ge=0,le=9000000000000000)
    endReason: Literal['topOut','blockedSpawn'] | None = None

class Step(WireModel):
    action: Action | None = None
    elapsed: int | None = Field(default=None,ge=1,le=31536000000)

UUID_PATTERN = r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
class HandoffRequest(WireModel):
    requestID: str = Field(pattern=UUID_PATTERN)
    clientID: str = Field(pattern=UUID_PATTERN)
    expectedVersion: int = Field(ge=0)
    expectedEpoch: int = Field(ge=0)
    botID: int = Field(ge=1)
    snapshot: Snapshot

class CommandRequest(WireModel):
    requestID: str = Field(pattern=UUID_PATTERN)
    clientID: str = Field(pattern=UUID_PATTERN)
    expectedVersion: int = Field(ge=1)
    expectedEpoch: int = Field(ge=1)
    command: Literal['handoff','pauseBot','resumeBot','reclaim','end','changeBot']
    botID: int | None = Field(default=None,ge=1)
    snapshot: Snapshot | None = None

FIXTURE_SHA256 = 'bd52a7eb5ed77ba516e6f53746fde5f619e6e2cc7e85d8668e81cede2c841ead'
