"""日志脱敏（计划 §4.2）：任何日志记录里的令牌样式字符串替换为 <redacted>。

用 LogRecordFactory 在格式化前处理 msg + args，覆盖所有 logger / handler（含 uvicorn、httpx）。
httpx 日志级别保持 WARNING，不记录请求头。
"""
import logging
import re

PATTERN = re.compile(
    r"(Bearer\s+)\S+|\bgithub_pat_\w+|\bghp_\w+|\bgho_\w+|\blin_api_\w+",
    re.IGNORECASE,
)


def redact(text: str) -> str:
    return PATTERN.sub(lambda m: (m.group(1) or "") + "<redacted>", text)


_installed = False


def install() -> None:
    global _installed
    if _installed:
        return
    _installed = True
    previous = logging.getLogRecordFactory()

    def factory(*args, **kwargs):
        record = previous(*args, **kwargs)
        try:
            message = record.getMessage()
        except Exception:  # noqa: BLE001 - 格式化失败交给 logging 自己报
            return record
        cleaned = redact(message)
        if cleaned != message:
            record.msg, record.args = cleaned, None
        return record

    logging.setLogRecordFactory(factory)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
