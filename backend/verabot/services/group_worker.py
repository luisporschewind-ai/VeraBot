"""Single-process durable worker for group routing, clarification, and member steps."""
import asyncio
from datetime import datetime, timedelta, timezone
import logging
import time
import uuid

from ..db import group_execution_store as store
from ..db import group_store
from ..agents import group_context, group_runtime
from . import group_actions, group_routing

log = logging.getLogger(__name__)
_process_lock = asyncio.Lock()
_cancel_events: dict[int, asyncio.Event] = {}
LEASE_SECONDS = 90
LEASE_RENEW_SECONDS = 15


def request_cancel(task_id: int) -> None:
    event = _cancel_events.get(task_id)
    if event:
        event.set()


def _utc_after(seconds: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat(timespec="seconds")


async def _renew(step, stop):
    while not stop.is_set():
        await asyncio.sleep(LEASE_RENEW_SECONDS)
        if not store.renew_lease(step["id"], step["lease_token"], step["version"], _utc_after(LEASE_SECONDS)):
            return


async def process_one(worker_id: str) -> bool:
    """Process at most one queued step; caller may safely poll again."""
    async with _process_lock:
        step = store.claim_next(worker_id, datetime.now(timezone.utc).isoformat(timespec="seconds"))
        if step is None:
            return False
        task, clarification, history, fairness = store.routing_context(step["user_id"], step["group_id"], step["task_id"])
        cancel = _cancel_events.setdefault(task["id"], asyncio.Event())
        started = time.monotonic()
        heartbeat_stop = asyncio.Event()
        heartbeat = asyncio.create_task(_renew(step, heartbeat_stop))
        try:
            if step["kind"] == "route":
                group = group_store.get_group(step["user_id"], step["group_id"])
                call_id=f"group-route:{uuid.uuid4()}"
                decision = None
                routing_request={**step["input"],"_routing_call":{"id":call_id,"task_id":task["id"],"step_id":step["id"]}}
                routing = asyncio.create_task(group_routing.resolve(step["user_id"],group,routing_request,task,history,clarification,fairness))
                try:
                    while not routing.done():
                        if cancel.is_set() or not store.is_current(step["id"],step["lease_token"],step["version"]):
                            routing.cancel()
                            try: await routing
                            except asyncio.CancelledError: pass
                            store.interrupt_step(step["id"],step["lease_token"],stopped=True)
                            return True
                        await asyncio.wait({routing},timeout=0.05)
                    decision = routing.result()
                finally:
                    if not routing.done():
                        routing.cancel()
                        try: await routing
                        except asyncio.CancelledError: pass
                    if decision and (decision.get("usage") is not None or decision.get("usage_unknown")):
                        store.record_call(call_id,step["user_id"],step["group_id"],task["id"],step["id"],"group_routing",decision.get("usage"),decision.get("usage_unknown",False))
                decision["usage_recorded"]=True
                if cancel.is_set() or not store.is_current(step["id"], step["lease_token"], step["version"]):
                    store.interrupt_step(step["id"], step["lease_token"], stopped=True)
                else:
                    store.apply_route(step["id"], step["lease_token"], step["version"], decision)
                return True

            group = group_store.get_group(step["user_id"], step["group_id"])
            member = next((m for m in group["members"] if m["id"] == step["member_id"] and m["available"]), None)
            if member is None:
                store.commit_step(step["id"], step["lease_token"], step["version"],
                                  {"content": "", "status": "failed", "error": "member_unavailable", "usage_unknown": True})
                return True
            step["context"] = group_context.build_execution(step["user_id"], step["group_id"], task, step,
                                                              remaining_calls=max(0, 6 - int(step.get("call_count", 0))))
            last_check = 0.0
            def should_stop():
                nonlocal last_check
                if cancel.is_set():
                    return True
                current = time.monotonic()
                if current - last_check >= 1.0:
                    last_check = current
                    return not store.is_current(step["id"], step["lease_token"], step["version"])
                return False
            last_saved = 0
            last_saved_at = time.monotonic()
            def save_snapshot(content):
                nonlocal last_saved, last_saved_at
                now = time.monotonic()
                if len(content) - last_saved >= 256 or (content and now - last_saved_at >= 1):
                    if store.save_snapshot(step["id"], step["lease_token"], step["version"], content):
                        last_saved, last_saved_at = len(content), now
            try:
                result = await group_runtime.run_step(step, should_stop, user_id=step["user_id"], group=group,
                                                      task=task, member=member, save_snapshot=save_snapshot)
            except asyncio.CancelledError:
                store.interrupt_step(step["id"], step["lease_token"], stopped=cancel.is_set())
                raise
            result["elapsed_ms"] = int((time.monotonic() - started) * 1000)
            if result.get("status") == "completed" and result.get("action") is not None:
                if result["action"].get("kind") == "completed" and not result["action"].get("result"):
                    result["action"]["result"] = result.get("content", "")
                result["next_steps"] = group_actions.next_steps(task, step, result["action"])
            if result.get("status") == "interrupted":
                store.interrupt_step(step["id"],step["lease_token"],result=result)
            elif result.get("status") == "stopped" or should_stop():
                store.interrupt_step(step["id"], step["lease_token"], stopped=True, result=result)
            else:
                store.commit_step(step["id"], step["lease_token"], step["version"], result)
            return True
        except asyncio.CancelledError:
            if store.is_current(step["id"], step["lease_token"], step["version"]):
                store.interrupt_step(step["id"], step["lease_token"], stopped=cancel.is_set())
            raise
        except Exception as exc:
            log.warning("group worker step failed id=%s reason=%s", step["id"], type(exc).__name__)
            if step["kind"] == "member":
                store.commit_step(step["id"], step["lease_token"], step["version"],
                                  {"content": "", "status": "failed", "error": "step_failed", "usage_unknown": True})
            else:
                if isinstance(exc,group_runtime.BudgetExhausted):
                    store.commit_step(step["id"],step["lease_token"],step["version"],{"status":"failed","error":"daily_budget_exhausted"})
                    return True
                store.apply_route(step["id"], step["lease_token"], step["version"], {
                    "intent": "clarify", "speaker_member_ids": [], "goal": task.get("goal", ""),
                    "missing_information": ["用户希望完成的事情"], "usage": None, "usage_unknown": True,
                })
            return True
        finally:
            heartbeat_stop.set()
            heartbeat.cancel()
            try:
                await heartbeat
            except asyncio.CancelledError:
                pass
            _cancel_events.pop(task["id"], None)


async def loop(worker_id: str) -> None:
    while True:
        try:
            if not await process_one(worker_id):
                await asyncio.sleep(0.25)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("group worker recovered after an unexpected step failure")
            store.recover_interrupted(datetime.now(timezone.utc).isoformat(timespec="seconds"))
            await asyncio.sleep(0.25)
