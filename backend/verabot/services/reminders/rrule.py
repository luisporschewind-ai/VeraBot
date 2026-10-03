"""RFC 5545 RRULE 子集。不支持的规则直接拒绝，下次时间只在服务端计算。"""
from __future__ import annotations

from datetime import datetime

from dateutil.rrule import rrulestr

_DAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
_DAY_SET = set(_DAYS)
_DAY_ZH = {"MO": "周一", "TU": "周二", "WE": "周三", "TH": "周四", "FR": "周五", "SA": "周六", "SU": "周日"}
_KEYS = ("FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "COUNT", "UNTIL")


class RRuleError(ValueError):
    pass


def _parts(rule: str) -> dict[str, str]:
    text = rule.strip()
    if text.upper().startswith("RRULE:"):
        text = text[6:]
    out: dict[str, str] = {}
    for piece in text.split(";"):
        if not piece or "=" not in piece:
            raise RRuleError("不支持的重复规则")
        key, value = piece.split("=", 1)
        key = key.strip().upper()
        value = value.strip()
        if key != "UNTIL":
            value = value.upper()
        if key not in _KEYS or not value or key in out:
            raise RRuleError("不支持的重复规则")
        out[key] = value
    return out


def normalize(rule: str | None) -> str | None:
    """校验并写成稳定字符串。空 / never / 永不 → None。"""
    if rule is None:
        return None
    text = rule.strip()
    if not text or text.lower() in {"none", "never", "永不"}:
        return None
    parts = _parts(text)
    freq = parts.get("FREQ")
    if freq not in {"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}:
        raise RRuleError("不支持的重复规则")
    if "COUNT" in parts and "UNTIL" in parts:
        raise RRuleError("不支持的重复规则")
    if "INTERVAL" in parts:
        if not parts["INTERVAL"].isdigit() or not 1 <= int(parts["INTERVAL"]) <= 99:
            raise RRuleError("不支持的重复规则")
    else:
        parts.pop("INTERVAL", None)
    if freq == "DAILY" and ("BYDAY" in parts or "BYMONTHDAY" in parts):
        raise RRuleError("不支持的重复规则")
    if freq == "WEEKLY":
        if "BYMONTHDAY" in parts:
            raise RRuleError("不支持的重复规则")
        if "BYDAY" in parts:
            days = [d.strip() for d in parts["BYDAY"].split(",") if d.strip()]
            if not days or any(d not in _DAY_SET for d in days) or len(days) != len(set(days)):
                raise RRuleError("不支持的重复规则")
            parts["BYDAY"] = ",".join(days)
    if freq == "MONTHLY":
        if "BYDAY" in parts:
            raise RRuleError("不支持的重复规则")
        if "BYMONTHDAY" in parts:
            if not parts["BYMONTHDAY"].isdigit() or not 1 <= int(parts["BYMONTHDAY"]) <= 31:
                raise RRuleError("不支持的重复规则")
    if freq == "YEARLY" and ("BYDAY" in parts or "BYMONTHDAY" in parts):
        raise RRuleError("不支持的重复规则")
    if "COUNT" in parts:
        if not parts["COUNT"].isdigit() or not 1 <= int(parts["COUNT"]) <= 500:
            raise RRuleError("不支持的重复规则")
    if "UNTIL" in parts:
        until = parts["UNTIL"]
        try:
            datetime.fromisoformat(until.replace("Z", "+00:00"))
        except ValueError:
            raise RRuleError("不支持的重复规则") from None
    ordered = [k for k in _KEYS if k in parts]
    return ";".join(f"{k}={parts[k]}" for k in ordered)


def from_preset(text: str | None, dtstart: datetime | None) -> str | None:
    """预设名（每天 / 工作日 / 每周 / 每月 / 每年）或 RRULE 文本。"""
    if text is None:
        return None
    raw = text.strip()
    key = raw.lower()
    if key in {"", "none", "never", "永不"}:
        return None
    if key in {"daily", "每天"}:
        return "FREQ=DAILY"
    if key in {"weekdays", "weekday", "工作日"}:
        return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    if key in {"yearly", "每年"}:
        return "FREQ=YEARLY"
    if key in {"weekly", "每周"}:
        if dtstart is None:
            raise RRuleError("设置每周重复需要先选择日期")
        return f"FREQ=WEEKLY;BYDAY={_DAYS[dtstart.weekday()]}"
    if key in {"monthly", "每月"}:
        if dtstart is None:
            raise RRuleError("设置每月重复需要先选择日期")
        return f"FREQ=MONTHLY;BYMONTHDAY={dtstart.day}"
    return normalize(raw)


def _parsed(rule: str) -> dict[str, str]:
    return dict(piece.split("=", 1) for piece in rule.split(";"))


def count_limit(rule: str | None) -> int | None:
    if not rule:
        return None
    raw = _parsed(rule).get("COUNT")
    return int(raw) if raw else None


def _naive_rule(rule: str, zone) -> str:
    """COUNT 由 occurrence_index 记账。带时区的 UNTIL 先换成同一时区的墙上时间，才能和朴素 dtstart 比较。"""
    parts: list[str] = []
    for piece in rule.split(";"):
        if piece.startswith("COUNT="):
            continue
        if piece.startswith("UNTIL=") and zone is not None:
            raw = piece.split("=", 1)[1]
            try:
                until = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            except ValueError:
                parts.append(piece)
                continue
            if until.tzinfo is not None:
                until = until.astimezone(zone).replace(tzinfo=None)
            parts.append("UNTIL=" + until.strftime("%Y%m%dT%H%M%S"))
            continue
        parts.append(piece)
    return ";".join(parts)


def _engine(rule: str, dtstart: datetime):
    """按墙上时间展开。夏令时切换后仍落在本地同一时刻，而不是固定加 24 小时。"""
    zone = dtstart.tzinfo
    if zone is None:
        naive = dtstart.replace(microsecond=0)
    else:
        naive = dtstart.astimezone(zone).replace(tzinfo=None, microsecond=0)
    return rrulestr("RRULE:" + _naive_rule(rule, zone), dtstart=naive), zone


def _attach(value: datetime | None, zone) -> datetime | None:
    if value is None or zone is None:
        return value
    return value.replace(tzinfo=zone)


def next_after(rule: str, dtstart: datetime, after: datetime) -> datetime | None:
    engine, zone = _engine(rule, dtstart)
    bound = after if zone is None else after.astimezone(zone).replace(tzinfo=None, microsecond=0)
    return _attach(engine.after(bound, inc=False), zone)


def between(rule: str, dtstart: datetime, start: datetime, end: datetime) -> list[datetime]:
    engine, zone = _engine(rule, dtstart)
    if zone is not None:
        start = start.astimezone(zone).replace(tzinfo=None, microsecond=0)
        end = end.astimezone(zone).replace(tzinfo=None, microsecond=0)
    return [_attach(item, zone) for item in engine.between(start, end, inc=True)]


def label(rule: str | None, due_local: datetime | None) -> str | None:
    if not rule:
        return None
    parts = _parsed(rule)
    interval = int(parts.get("INTERVAL", "1"))
    freq = parts.get("FREQ")
    if freq == "DAILY":
        base = "每天" if interval == 1 else f"每 {interval} 天"
    elif freq == "WEEKLY":
        days = parts.get("BYDAY", "")
        if days == "MO,TU,WE,TH,FR" and interval == 1:
            base = "工作日"
        elif days == "MO,TU,WE,TH,FR":
            base = f"每 {interval} 周的工作日"
        else:
            names = "".join(_DAY_ZH.get(d, d) for d in days.split(",") if d)
            base = (f"每{names}" if interval == 1 else f"每 {interval} 周{names}")
    elif freq == "MONTHLY":
        day = parts.get("BYMONTHDAY")
        base = f"每月 {day} 日" if day else "每月"
        if interval != 1:
            base = f"每 {interval} 个月" + (f" {day} 日" if day else "")
    else:
        base = "每年" if interval == 1 else f"每 {interval} 年"
    if "COUNT" in parts:
        base += f"，共 {parts['COUNT']} 次"
    if due_local is not None:
        base = f"{base} {due_local.strftime('%H:%M')}"
    return base


def simple_kind(rule: str | None) -> str | None:
    """每天 / 每周某天 / 工作日，且 INTERVAL=1、没有结束条件 → iOS 可用日历重复触发。"""
    if not rule:
        return None
    parts = _parsed(rule)
    if "COUNT" in parts or "UNTIL" in parts or int(parts.get("INTERVAL", "1")) != 1:
        return None
    freq = parts.get("FREQ")
    if freq == "DAILY" and "BYDAY" not in parts and "BYMONTHDAY" not in parts:
        return "daily"
    if freq == "WEEKLY":
        days = parts.get("BYDAY", "")
        if days == "MO,TU,WE,TH,FR":
            return "weekdays"
        if days in _DAY_SET:
            return "weekly"
    return None
