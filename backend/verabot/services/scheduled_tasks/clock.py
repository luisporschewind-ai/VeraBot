from datetime import datetime, timezone

def now() -> datetime:
    return datetime.now(timezone.utc)

def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec='microseconds')

def parse(value: str) -> datetime:
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)
