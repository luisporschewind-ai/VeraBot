"""Request-bound, single-worker sequential group execution."""
import asyncio
import anyio
import contextlib
import inspect
import json
import logging
import time
from .. import db
from ..db import group_store as store
from ..services import llm
from . import group_context

MEMBER_TIMEOUT=60.0
TURN_TIMEOUT=240.0
POLL_INTERVAL=0.05
_signals={}
log=logging.getLogger(__name__)

class Stopped(Exception): pass
class MemberGone(Exception): pass
class BudgetExhausted(Exception): pass

GROUP_NEXT_STEP = [{"type": "function", "function": {
    "name": "group_next_step",
    "description": ("提交唯一的群内协作动作；只允许在用户目标需要成员接力时调用。"
                    "kind=await_user 时必须提供非空 missing_information，并在正文写出真实追问。"),
    "parameters": {"type": "object", "additionalProperties": False, "required": ["kind"], "properties": {
        "kind": {"type": "string", "enum": ["completed", "consult", "handoff", "await_user"]},
        "target_member_id": {"type": ["integer", "null"]}, "goal": {"type": "string"},
        "result": {"type": "string"}, "context_message_ids": {"type": "array", "items": {"type": "integer"}},
        "attachment_ids": {"type": "array", "items": {"type": "string"}},
        "completion_criteria": {"type": "string"}, "issue_key": {"type": ["string", "null"]},
        "missing_information": {
            "type": "array", "items": {"type": "string"},
            "description": "await_user 时必填：还缺哪些信息的简短列表；其他 kind 可省略或为空。",
        },
    }},
}}]


async def run_step(step: dict, should_stop, *, user_id: int, group: dict, task: dict, member: dict,
                   save_snapshot=None) -> dict:
    """One step, with every provider attempt counted and accounted independently."""
    from ..services import group_actions
    from ..db import group_execution_store as execution_store
    content, usage, raw_action = "", None, None
    unknown, accounted = False, False
    managed = "lease_token" in step and "input_id" in step
    status, error = "completed", None
    async def next_event(generator):
        pending = asyncio.create_task(anext(generator))
        try:
            while not pending.done():
                if should_stop():
                    raise Stopped()
                await asyncio.wait({pending},timeout=POLL_INTERVAL)
            return pending.result()
        finally:
            if not pending.done():
                pending.cancel()
            with contextlib.suppress(asyncio.CancelledError, StopAsyncIteration, Exception):
                await pending
    try:
        remaining = max(0.001,(TURN_TIMEOUT*1000-int(step.get("elapsed_ms",0)))/1000)
        async with asyncio.timeout(min(MEMBER_TIMEOUT,remaining)):
            for attempt in range(2):
                if should_stop(): raise Stopped()
                check_budget(user_id)
                call_id = execution_store.begin_member_call(step["id"],step["lease_token"],step["version"]) if managed else None
                current_usage = None
                generator = llm.stream_chat(step["context"], GROUP_NEXT_STEP, tool_choice="auto", max_tokens=768)
                try:
                    while True:
                        try: kind,value = await next_event(generator)
                        except StopAsyncIteration: break
                        if kind == "delta":
                            content += value
                            if save_snapshot is not None:
                                saved = save_snapshot(content)
                                if inspect.isawaitable(saved): await saved
                        elif kind == "usage": current_usage = value
                        elif kind == "tool_calls":
                            if raw_action is not None or len(value)!=1 or value[0].get("name")!="group_next_step":
                                raise ValueError("invalid_action")
                            raw_action = json.loads(value[0].get("arguments") or "{}")
                finally:
                    with contextlib.suppress(Exception): await generator.aclose()
                    unknown = unknown or current_usage is None
                    if current_usage is not None:
                        usage = {key:int((usage or {}).get(key,0))+int(current_usage.get(key,0)) for key in ("prompt_tokens","completion_tokens","total_tokens")}
                    if call_id:
                        execution_store.record_call(call_id,user_id,group["id"],task["id"],step["id"],"group_chat",current_usage,current_usage is None)
                        accounted = True
                if content.strip() or raw_action is not None: break
                if attempt==1: raise ValueError("empty_response")
        try:
            action = group_actions.validate(user_id, group, task, step, raw_action)
        except ValueError as exc:
            # Streamed body already useful; do not mark the step failed for a soft tool-arg mistake.
            if content.strip():
                log.warning("group_next_step validation failed with non-empty content; coercing (%s)", exc)
                action = group_actions.coerce_from_content(user_id, group, task, step, raw_action, content)
            else:
                raise
    except Stopped:
        status,action="stopped",None
    except asyncio.CancelledError:
        status,action="interrupted",None
    except TimeoutError:
        status,action,error="failed",None,"member_timeout"
    except BudgetExhausted:
        status,action,error="failed",None,"daily_budget_exhausted"
    except execution_store.GroupExecutionError as exc:
        status,action,error="failed",None,exc.code
    except Exception as exc:
        status,action,error="failed",None,str(exc) if isinstance(exc,ValueError) else "member_failed"
    return {"content":content,"status":status,"action":action,"usage":usage,
            "usage_unknown":unknown,"usage_recorded":accounted,"error":error}

def signal_stop(user_id,group_id,turn_id):
    event=_signals.get((user_id,group_id,turn_id))
    if event: event.set()

def check_budget(user_id, pending=0):
    used,budget=db.token_budget(user_id)
    if used+pending>=budget: raise BudgetExhausted()

def interrupted(user_id,group_id,turn_id):
    turn=store.get_turn(user_id,group_id,turn_id)
    if turn['status']!='running': return
    for m in turn['messages']:
        if m['role']=='bot' and m['status']=='streaming':
            store.save_reply(user_id,m['id'],m['content'],'interrupted',m['usage'],finalize=True)
    store.finish_turn(user_id,group_id,turn_id,'interrupted')

async def run(user_id,group,turn):
    gid,tid=group['id'],turn['id']
    key=(user_id,gid,tid); signal=asyncio.Event(); _signals[key]=signal
    current=None; text=''; usage=None; final='completed'; finished_execution=False
    def event(name,**fields): return name,{'group_id':gid,'turn_id':tid,**fields}
    def cancelled():
        if signal.is_set() or store.get_turn(user_id,gid,tid)['cancel_requested']: raise Stopped()
    members=[m for m in group['members'] if m['available'] and
             (turn['mode']=='round' or m['id']==turn['target_member_id'])]
    def totals():
        messages=store.get_turn(user_id,gid,tid)['messages']
        known=[m['usage'] for m in messages if m['role']=='bot' and m['usage'] is not None]
        return {**{k:sum(int(u.get(k) or 0) for u in known) for k in ('prompt_tokens','completion_tokens','total_tokens')},
                'unknown_messages':sum(m['role']=='bot' and m['usage'] is None for m in messages)}
    try:
        question=store.get_message(user_id,gid,turn['user_message_id'])
        yield event('turn_start',user_message=question,speaker_member_ids=[m['id'] for m in members])
        async with asyncio.timeout(TURN_TIMEOUT):
            for member in members:
                cancelled()
                # Resolve again immediately before claiming a reply/model call.
                live=next((m for m in store.get_group(user_id,gid)['members'] if m['id']==member['id'] and m['available']),None)
                if not live:
                    final='partial'; continue
                current=store.start_reply(user_id,gid,tid,member['id']);text='';usage=None
                yield event('message_start',message=current)
                yield event('status',message_id=current['id'],member_id=member['id'],phase='thinking')
                status='completed'; error=None; last_saved=0; saved_at=time.monotonic()
                try:
                    async with asyncio.timeout(MEMBER_TIMEOUT):
                        for attempt in range(2):
                            cancelled(); check_budget(user_id,int((usage or {}).get('total_tokens') or 0))
                            previous_usage=dict(usage or {})
                            context=group_context.build(user_id,group,live,turn)
                            generator=llm.stream_chat(context,None,max_tokens=768)
                            pending=None
                            try:
                                while True:
                                    cancelled()
                                    if not db.get_bot(user_id,live['bot_id']): raise MemberGone()
                                    pending=asyncio.create_task(anext(generator))
                                    while not pending.done():
                                        await asyncio.wait({pending},timeout=POLL_INTERVAL)
                                        cancelled()
                                        if not db.get_bot(user_id,live['bot_id']): raise MemberGone()
                                    try: kind,value=pending.result()
                                    except StopAsyncIteration: break
                                    pending=None
                                    cancelled()
                                    if kind=='delta':
                                        text+=value
                                        if len(text)-last_saved>=256 or time.monotonic()-saved_at>=1:
                                            store.save_reply(user_id,current['id'],text,'streaming',usage,finalize=False)
                                            last_saved=len(text);saved_at=time.monotonic()
                                        yield event('delta',message_id=current['id'],member_id=member['id'],text=value)
                                    elif kind=='usage':
                                        # One usage report per provider attempt, aggregate empty retries.
                                        usage={k:int(previous_usage.get(k) or 0)+int(value.get(k) or 0)
                                               for k in ('prompt_tokens','completion_tokens','total_tokens')}
                                        store.save_reply(user_id,current['id'],text,'streaming',usage,finalize=False)
                                    elif kind=='tool_calls':
                                        raise llm.LLMError('Unexpected tool response')
                            finally:
                                # Starlette's disconnect CancelScope repeatedly cancels awaits.
                                # Shield only transport cleanup, never model generation.
                                with anyio.CancelScope(shield=True):
                                    if pending is not None:
                                        pending.cancel()
                                        with contextlib.suppress(asyncio.CancelledError,StopAsyncIteration): await pending
                                    await generator.aclose()
                            if text.strip(): break
                            if attempt==1: raise llm.LLMError('Empty response')
                except Stopped:
                    status='stopped';final='stopped'
                except MemberGone:
                    status='stopped';final='partial';error=('member_unavailable','这位伙伴已不可用，保留已有回应。')
                except BudgetExhausted:
                    status='failed';final='partial';error=('quota_exceeded','今日额度已用完，请稍后继续。')
                except TimeoutError:
                    status='failed';final='partial';error=('member_timeout','这位伙伴暂时没能完成回应，可以稍后重试。')
                except Exception:
                    log.exception('Group member failed group=%s turn=%s member=%s',gid,tid,member['id'])
                    status='failed';final='partial';error=('member_failed','这位伙伴暂时没能回应，可以稍后重试。')
                message=store.save_reply(user_id,current['id'],text,status,usage,finalize=True)
                current=None
                yield event('message_done',message=message)
                if error: yield event('error',code=error[0],message=error[1],message_id=message['id'])
                if final=='stopped' or (error and error[0]=='quota_exceeded'): break
        finished_execution=True
    except Stopped:
        final='stopped';finished_execution=True
    except TimeoutError:
        final='partial';finished_execution=True
        if current:
            message=store.save_reply(user_id,current['id'],text,'failed',usage,finalize=True);current=None
            yield event('message_done',message=message)
        yield event('error',code='turn_timeout',message='讨论时间已到，已保留完成的回应。')
    finally:
        # Cancellation/GeneratorExit cannot yield; persist partial text before releasing the lock.
        if current:
            store.save_reply(user_id,current['id'],text,'interrupted',usage,finalize=True)
        running=store.get_turn(user_id,gid,tid)
        if running['status']=='running':
            store.finish_turn(user_id,gid,tid,final if finished_execution else 'interrupted')
        _signals.pop(key,None)
    finished=store.get_turn(user_id,gid,tid)
    yield event('turn_done',status=finished['status'],usage=totals(),message_ids=[m['id'] for m in finished['messages']])
