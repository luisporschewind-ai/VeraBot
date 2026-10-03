"""进行中的 SSE 连接。调度器产生通知时，如果该用户正在对话，就推一条 notification 事件。"""
from __future__ import annotations

import asyncio
from collections import defaultdict

_subs: dict[int, set[asyncio.Queue]] = defaultdict(set)


def subscribe(user_id: int) -> asyncio.Queue:
    queue: asyncio.Queue = asyncio.Queue()
    _subs[user_id].add(queue)
    return queue


def unsubscribe(user_id: int, queue: asyncio.Queue) -> None:
    _subs.get(user_id, set()).discard(queue)


def publish(user_id: int, payload: dict) -> None:
    for queue in list(_subs.get(user_id, ())):
        try:
            queue.put_nowait(payload)
        except asyncio.QueueFull:
            pass


def drain(queue: asyncio.Queue) -> list[dict]:
    found = []
    while True:
        try:
            found.append(queue.get_nowait())
        except asyncio.QueueEmpty:
            return found
