"""memory_jobs：入队 + 进程内单 worker。

启动时把 running 退回 pending。领取用「UPDATE … WHERE status='pending'」保证一次只有一个 worker 拿到。
失败最多再试 2 次（共 3 次领取）。日志不写记忆或消息正文。
"""
from __future__ import annotations

import asyncio
import logging

from ... import db
from ...core import config
from ...db import memory_job_store as store
from . import summarize

log = logging.getLogger("verabot.memory.jobs")
POLL_SECONDS = 1.0
# 这些失败可以重试；策略拦截 / 预算跳过不重试
_RETRYABLE = {"llm_error", "invalid_json", "empty_summary"}


def enabled() -> bool:
    return config.MEMORY_JOBS


def enqueue(user_id: int, bot_id: int, *, kind: str = "summarize", after_message_id: int | None = None) -> int:
    with db.tx() as c:
        return store.enqueue(c, user_id=user_id, bot_id=bot_id, kind=kind, after_message_id=after_message_id)


def recover() -> int:
    with db.tx() as c:
        n = store.recover_running(c)
    if n:
        log.info("memory jobs recovered running→pending: %s", n)
    return n


def skip_pending_summaries(user_id: int, bot_id: int) -> int:
    """清空对话后，还没开始的摘要任务不再跑。"""
    with db.tx() as c:
        return store.skip_pending(c, user_id, bot_id, "summarize", "conversation_cleared")


def _apply(job: dict, status: str, error: str | None) -> str:
    with db.tx() as c:
        if status == "failed" and error in _RETRYABLE and int(job["attempts"]) < config.MEMORY_JOB_MAX_ATTEMPTS:
            store.requeue(c, job["id"], error or "error")
            return "pending"
        store.finish(c, job["id"], status if status != "failed" else "failed", error)
    return status


async def process_one() -> bool:
    """领取并处理一条 pending。没有任务时返回 False。"""
    with db.tx() as c:
        job = store.claim_next(c)
    if not job:
        return False
    kind = job["kind"]
    try:
        if kind == "summarize":
            status, error = await summarize.run(job)
        else:
            # extract / review 属于 M3+，M2 不执行
            status, error = "skipped", "unsupported"
    except Exception:
        log.info("memory job crashed: id=%s kind=%s", job["id"], kind)
        status, error = "failed", "crash"
    final = _apply(job, status, error)
    log.info("memory job done: id=%s kind=%s status=%s error=%s attempts=%s",
             job["id"], kind, final, error, job["attempts"])
    return True


async def loop() -> None:
    """单 worker。取消时退出。启动先恢复 running。"""
    recover()
    while True:
        try:
            did = await process_one()
        except asyncio.CancelledError:
            raise
        except Exception:
            log.info("memory job worker iteration failed")
            did = False
        if not did:
            await asyncio.sleep(POLL_SECONDS)
