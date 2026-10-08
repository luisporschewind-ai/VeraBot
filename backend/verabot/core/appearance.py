"""Versioned appearance document. Geometry and runtime state are never stored here."""
import json
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class AppearanceModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AppearanceColor(AppearanceModel):
    space: Literal["srgb", "display-p3"]
    red: float = Field(strict=True, ge=0, le=1, allow_inf_nan=False)
    green: float = Field(strict=True, ge=0, le=1, allow_inf_nan=False)
    blue: float = Field(strict=True, ge=0, le=1, allow_inf_nan=False)


class AppearancePalette(AppearanceModel):
    body: AppearanceColor
    eyes: AppearanceColor


class AppearanceParameters(AppearanceModel):
    roundness: float = Field(strict=True, ge=0, le=1, allow_inf_nan=False)


class AppearanceV1(AppearanceModel):
    schema_version: int = Field(strict=True, ge=1, le=1)
    template_id: str = Field(strict=True, pattern=r"^[a-z][a-z0-9-]{0,63}$", max_length=64)
    template_version: int = Field(strict=True, ge=1, le=2147483647)
    palette: AppearancePalette
    parameters: AppearanceParameters

    @model_validator(mode="after")
    def bounded_document(self):
        if len(json.dumps(self.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":")).encode("utf-8")) > 4096:
            raise ValueError("外观配置超过 4096 字节")
        return self


def validate_appearance(value: dict) -> dict:
    return AppearanceV1.model_validate(value).model_dump(mode="json")
