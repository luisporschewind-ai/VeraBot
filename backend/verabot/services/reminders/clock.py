"""可替换的时钟。测试用 set_now 固定时间；调度器与状态机都读 now()。"""
from datetime import datetime, timezone

_override: datetime | None = None


def now() -> datetime:
    if _override is not None:
        return _override
    return datetime.now(timezone.utc)


def set_now(value: datetime | None) -> None:
    """value 为 None 时恢复真实时钟。传入的时间会换成 UTC。"""
    global _override
    if value is None:
        _override = None
        return
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    _override = value.astimezone(timezone.utc)


def iso_utc(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat(timespec="seconds")


def iso_local(value: datetime) -> str:
    return value.isoformat(timespec="minutes")
