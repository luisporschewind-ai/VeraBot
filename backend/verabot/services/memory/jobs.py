"""memory_jobs 队列 + 进程内单 worker（M2，MEMORY_GROWTH §11.1）。

入队由 agents/runtime 在写库后调用（enqueue_summarize）；worker 在 FastAPI 启动时用
`asyncio.create_task` 拉起（main.py），关闭时取消。领取用 `UPDATE … WHERE status='pending'`
原子完成，单进程 uvicorn 足够；重启时 recover_running 把遗留的 running 退回 pending。
失败重试 ≤ MEMORY_JOBS_MAX_ATTEMPTS - 1 次，超过记 failed（error 只存短文案）。
"""
from __future__ import annotations

import asyncio
import logging

from ... import db
from ...core import config
from ...db import memory_job_store as store
from . import summarize

log = logging.getLogger("verabot.memory")

HANDLERS = {"summarize": summarize.run}
KINDS = ("summarize", "extract", "review")   # extract / review 是 M3 / M4 的占位（入队会 skipped）


def enqueue(user_id: int, bot_id: int | None, kind: str, after_message_id: int | None = None) -> bool:
    """幂等入队：同一 (user, bot, kind) 已有 pending/running 时忽略。"""
    if kind not in KINDS:
        raise ValueError(f"unknown job kind: {kind}")
    with db.tx() as c:
        return store.enqueue(c, user_id, bot_id, kind, after_message_id)


def enqueue_summarize(user_id: int, bot_id: int, after_message_id: int | None = None) -> bool:
    """一轮对话写库后调用；不阻塞 SSE，失败只记日志。"""
    try:
        return enqueue(user_id, bot_id, "summarize", after_message_id)
    except Exception as e:  # noqa: BLE001 — 入队失败不影响对话
        log.warning("enqueue summarize failed: user=%s bot=%s %s", user_id, bot_id, e)
        return False


async def _execute(job: dict) -> tuple[str, str | None]:
    handler = HANDLERS.get(job["kind"])
    if handler is None:
        return "skipped", "unsupported"
    try:
        return await handler(job)
    except asyncio.CancelledError:
        raise
    except Exception as e:  # noqa: BLE001 — 单条任务失败不影响 worker
        log.warning("memory job %s (%s) failed: %s", job["id"], job["kind"], e)
        return "failed", str(e)


def _claim() -> dict | None:
    with db.tx() as c:
        return store.claim_next(c)


def _finish(job: dict, status: str, error: str | None) -> None:
    retry = status == "failed" and job["attempts"] < config.MEMORY_JOBS_MAX_ATTEMPTS
    with db.tx() as c:
        store.finish(c, job["id"], "pending" if retry else status, error)
    if retry:
        log.info("memory job %s requeued (attempt %s)", job["id"], job["attempts"])


async def worker_loop():
    """常驻循环：每 MEMORY_JOBS_POLL_SECONDS 轮询一次；取消时把在跑的任务留给下次启动恢复。"""
    with db.tx() as c:
        n = store.recover_running(c)
    if n:
        log.info("memory jobs: recovered %s running job(s) → pending", n)
    while True:
        job = _claim()
        if job is None:
            await asyncio.sleep(config.MEMORY_JOBS_POLL_SECONDS)
            continue
        status, error = await _execute(job)
        _finish(job, status, error)
        if status == "failed":           # 失败后稍等，别在坏任务上打转
            await asyncio.sleep(config.MEMORY_JOBS_POLL_SECONDS)


def run_once() -> int:
    """测试 / 命令行用：同步处理完当前所有 pending（不等待轮询）。返回处理条数。"""
    n = 0
    while True:
        job = _claim()
        if job is None:
            return n
        status, error = asyncio.run(_execute(job))
        _finish(job, status, error)
        n += 1
