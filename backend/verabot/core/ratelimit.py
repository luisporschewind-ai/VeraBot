"""进程内限流（Rate limit）：滑动窗口计数。单机部署够用；多进程部署需要换成共享存储（见 AUTH_REFACTOR.md §7）。"""
import threading
import time
from collections import defaultdict, deque

_HITS: dict[str, deque] = defaultdict(deque)
_LOCK = threading.Lock()


def hit(key: str, limit: int, window_seconds: float) -> bool:
    """记一次并返回是否仍在限额内。超过限额时不记录这次。"""
    now = time.monotonic()
    with _LOCK:
        q = _HITS[key]
        while q and now - q[0] >= window_seconds:
            q.popleft()
        if len(q) >= limit:
            return False
        q.append(now)
        return True


def retry_after(key: str, window_seconds: float) -> int:
    with _LOCK:
        q = _HITS.get(key)
        if not q:
            return 0
        return max(1, int(window_seconds - (time.monotonic() - q[0])) + 1)


def reset():
    """测试用：清空所有计数。"""
    with _LOCK:
        _HITS.clear()


def count(key: str, window_seconds: float) -> int:
    """窗口内已记录的次数（不记新的一次）。"""
    now = time.monotonic()
    with _LOCK:
        q = _HITS.get(key)
        if not q:
            return 0
        while q and now - q[0] >= window_seconds:
            q.popleft()
        return len(q)
