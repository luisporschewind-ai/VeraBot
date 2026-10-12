"""查询参数与公开链接检查；本机 HTTP 客户端只访问固定搜索服务。"""
import ipaddress
import re
from urllib.parse import urlsplit

_LOCAL_SUFFIXES = (".localhost", ".local", ".internal", ".lan", ".home", ".test", ".invalid")


def public_url(value: str) -> str | None:
    if not isinstance(value, str) or len(value) > 2048 or re.search(r"[\s\\\x00-\x1f\x7f]", value):
        return None
    try:
        parsed = urlsplit(value)
        host = (parsed.hostname or "").rstrip(".").lower()
        if parsed.scheme != "https" or parsed.username is not None or parsed.password is not None:
            return None
        if parsed.port not in (None, 443) or not host or "%" in host:
            return None
        try:
            address = ipaddress.ip_address(host)
            if not address.is_global:
                return None
        except ValueError:
            if "." not in host or host.endswith(_LOCAL_SUFFIXES) or host == "localhost":
                return None
            ascii_host = host.encode("idna").decode("ascii")
            if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", ascii_host):
                return None
            # Reject noncanonical numeric IP forms interpreted specially by HTTP stacks.
            if all(re.fullmatch(r"(?:\d+|0x[0-9a-f]+)", part) for part in ascii_host.split(".")):
                return None
    except (ValueError, UnicodeError):
        return None
    return value


def validate_search(query, topic, time_range, domains, refresh) -> tuple[str, list[str]]:
    if not isinstance(query, str) or not 1 <= len(query.strip()) <= 400:
        raise ValueError("查询内容需要 1–400 字")
    if topic not in ("general", "news") or time_range not in ("", "day", "week", "month", "year"):
        raise ValueError("查询分类或时间范围无效")
    if not isinstance(refresh, bool):
        raise ValueError("refresh 必须为布尔值")
    if domains is None:
        domains = []
    if not isinstance(domains, list) or len(domains) > 5:
        raise ValueError("最多指定 5 个域名")
    clean = []
    for domain in domains:
        if not isinstance(domain, str) or re.search(r"[/\\:?#@\s]", domain) or not public_url("https://" + domain):
            raise ValueError("请使用公开网站的域名")
        clean.append(domain.encode("idna").decode("ascii").lower().rstrip("."))
    return query.strip(), sorted(set(clean))
