"""A separate process owns model work; HTTP only observes durable events."""
import asyncio
import json
import time
import uuid
import httpx
from dataclasses import fields
from ... import db
from ...db import chat_reply_store as store
from ...agents.runtime import run_chat
from ...tools.registry import TurnState

class Fenced(asyncio.CancelledError):pass

class Execution:
    def __init__(self,task):
        self.task=task;self.last_flush=time.monotonic();self.last_length=0;self.text='';self.traces=[];self.done=False
        self.checkpoint=store.decode_checkpoint(task.get('checkpoint_json'))
    def check(self,*,budget=True):
        with db.tx() as c:
            if not store.live(c,self.task):raise Fenced()
        bot=db.get_bot(self.task['user_id'],self.task['bot_id'])
        if not bot:raise Fenced()
        used,budget_limit=db.token_budget(self.task['user_id'])
        if budget and used>=budget_limit:raise store.ChatTaskError(429,'budget_exhausted','今日额度已用完')
        return bot
    def history_rows(self):
        with db.tx() as c:
            return store.history_rows(c,self.task)
    def bound_attachments(self):
        from ..attachments import repo
        return repo.for_messages(self.task['user_id'],[self.task['input_message_id']]).get(self.task['input_message_id'],[])
    def restore(self,messages,turn):
        cp=self.checkpoint
        if not cp:return messages,turn,[], '', {},0
        for key,value in cp.get('turn',{}).items():
            if key=='mcp_read_servers':value=set(value)
            elif key=='reminder_created':value={tuple(k):v for k,v in value}
            if hasattr(turn,key):setattr(turn,key,value)
        return cp['messages'],turn,cp.get('traces',[]),cp.get('answer',''),cp.get('usage',{}),cp.get('round',0)
    def checkpoint_save(self,messages,turn,traces,answer,usage,round_index,pending_calls=None):
        state={f.name:getattr(turn,f.name) for f in fields(turn) if f.name not in ('status_queue','parent_id','reminder_created')}
        state['mcp_read_servers']=list(state['mcp_read_servers'])
        state['reminder_created']=[[list(key),value] for key,value in turn.reminder_created.items()]
        cp={'messages':messages,'turn':state,'traces':traces,'answer':answer,'usage':usage,'round':round_index,'pending_calls':pending_calls or []}
        with db.tx(immediate=True) as c:
            if not store.live(c,self.task):raise Fenced()
            store.save_checkpoint(c,self.task,cp)
        self.checkpoint=cp
    def start_tool(self,tc):
        self.check()
        with db.tx(immediate=True) as c:return store.start_tool(c,self.task,tc)
    def complete_tool(self,tc,result):
        with db.tx(immediate=True) as c:
            if not store.complete_tool(c,self.task,tc,result):raise Fenced()
    def wait(self,result,answer,traces):
        state='awaiting_approval' if result.get('action_id') else 'awaiting_user'
        wait_id=f"action:{result['action_id']}" if result.get('action_id') else f"wait:{self.task['id']}:{self.task['version']}"
        text=answer.strip() or result.get('question') or result.get('message') or '请处理确认卡片后继续'
        with db.tx(immediate=True) as c:
            if not store.finish(c,self.task,state,text,traces,wait_id=wait_id):raise Fenced()
            if result.get('action_id'):
                store.bind_wait_action(c,self.task,result['action_id'])
        self.done=True
    def finish(self,answer,traces,error,rec_ids,*,user_text,bot,memory_tools):
        with db.tx(immediate=True) as c:
            if not store.live(c,self.task):raise Fenced()
            original_count=len(traces)
            def postprocess():
                if memory_tools:
                    from .. import memory
                    from ..memory import style
                    cue=style.match_style(user_text)
                    if cue:
                        proposal=memory.propose_style(self.task['user_id'],bot,cue,user_message_id=self.task['input_message_id'],connection=c)
                        if proposal and proposal.get('status')=='proposed':traces.append(style.trace_for(proposal))
                store.postprocess(c,self.task,rec_ids,memory_tools)
            ok,_=store.postprocess_safely(c,postprocess)
            if not ok:
                del traces[original_count:]
                import logging
                logging.getLogger(__name__).warning('chat postprocessing failed task=%s',self.task['id'])
            if not store.finish(c,self.task,'failed' if error else 'completed',answer,traces,error_code='chat_error' if error else None):raise Fenced()
            store.set_memory_ids(c,self.task,rec_ids)
        self.done=True
        return self.task['output_message_id']
    async def stream(self,messages,tools,tool_choice=None):
        from .. import llm
        for attempt in range(3):
            self.check()
            self.call_id=uuid.uuid4().hex
            with db.tx(immediate=True) as c:
                store.phase(c,self.task,'thinking')
                store.model_call(c,self.task,self.call_id,'running')
                store.event(c,self.task,'status',{'phase':'thinking','depth':0,'bot_name':db.get_bot(self.task['user_id'],self.task['bot_id']).get('name'),'tool':None,'parent_id':None})
            seen=False
            try:
                source=llm.stream_chat(messages,tools,tool_choice=tool_choice) if tool_choice else llm.stream_chat(messages,tools)
                async for kind,value in source:
                    seen=True
                    yield kind,value
                with db.tx(immediate=True) as c:store.model_call(c,self.task,self.call_id,'completed')
                return
            except (httpx.ConnectError,httpx.ConnectTimeout):
                with db.tx(immediate=True) as c:store.model_call(c,self.task,self.call_id,'connection_failed' if not seen else 'unknown')
                if seen or attempt==2:raise
                with db.tx(immediate=True) as c:store.phase(c,self.task,'retry_wait')
                await asyncio.sleep(.25*(attempt+1))
            except BaseException:
                with db.tx(immediate=True) as c:store.model_call(c,self.task,self.call_id,'unknown')
                raise
    def charge(self,usage):
        if usage:
            with db.tx(immediate=True) as c:store.charge_call(c,self.task,self.call_id,usage)
    def postprocess_allowed(self):
        with db.tx() as c:
            return store.postprocess_allowed(c,self.task)
    def consume(self,ev):
        if self.done:
            if ev["event"] in ("confirmation_required","done"):
                with db.tx(immediate=True) as c:store.event(c,self.task,ev["event"],ev["data"])
            return
        kind,data=ev['event'],ev['data']
        if kind=='delta':self.text+=data['text']
        if kind=='tool_result':self.traces.append(data)
        flush=kind!='delta' or len(self.text)-self.last_length>=256 or time.monotonic()-self.last_flush>=1
        if flush:
            with db.tx(immediate=True) as c:
                if not store.live(c,self.task):raise Fenced()
                if kind=='status':
                    phase='delegating' if data.get('depth',0)>0 else data['phase']
                    store.phase(c,self.task,phase)
                elif kind=='delta':
                    store.phase(c,self.task,"replying")
                elif kind=='tool_start':
                    store.phase(c,self.task,"tool")
                store.save_partial(c,self.task,self.text,self.traces)
                if kind!='delta':store.event(c,self.task,kind,data)
            self.last_flush=time.monotonic();self.last_length=len(self.text)

async def process_one(worker_id='chat-worker'):
    from . import approvals
    approvals.reconcile()
    with db.tx(immediate=True) as c:
        store.recover(c);task=store.claim_next(c,worker_id)
    if not task:return False
    execution=Execution(task)
    if execution.checkpoint:
        execution.text=execution.checkpoint.get('answer','');execution.traces=execution.checkpoint.get('traces',[])
    async def run():
        bot=execution.check()
        with db.tx() as c:text=store.input_content(c,task)
        async for ev in run_chat(task['user_id'],bot,text,durable=execution):execution.consume(ev)
    runner=asyncio.create_task(run())
    async def monitor():
        while not runner.done():
            await asyncio.sleep(.5)
            if execution.done:return
            with db.tx(immediate=True) as c:valid=store.heartbeat(c,task)
            if not valid:runner.cancel();return
            # Flush partials within one second even when provider stalls after a delta.
            if execution.text and time.monotonic()-execution.last_flush>=1 and not execution.done:
                with db.tx(immediate=True) as c:store.save_partial(c,task,execution.text,execution.traces)
                execution.last_flush=time.monotonic();execution.last_length=len(execution.text)
    heartbeat=asyncio.create_task(monitor())
    try:await runner
    except asyncio.CancelledError:
        # Expired/stopped/deleted work is never finalized by the old runtime's finally.
        with db.tx(immediate=True) as c:
            if store.live(c,task):store.finish(c,task,'interrupted',execution.text+'\n\n回复已中断',execution.traces,error_code='worker_interrupted')
    except Exception as exc:
        with db.tx(immediate=True) as c:store.finish(c,task,'failed',execution.text+'\n\n回复暂时无法完成',execution.traces,error_code=getattr(exc,'code','execution_failed'))
    finally:
        heartbeat.cancel();await asyncio.gather(heartbeat,return_exceptions=True)
    return True

async def loop():
    import os
    limit=max(1,int(os.getenv('VERABOT_CHAT_CONCURRENCY','4')))
    running=set()
    try:
        while True:
            finished={task for task in running if task.done()}
            if finished:
                await asyncio.gather(*finished,return_exceptions=True)
                running-=finished
            if len(running)<limit:running.add(asyncio.create_task(process_one(f'chat-worker-{os.getpid()}')))
            await asyncio.sleep(.5)
    finally:
        for task in running:task.cancel()
        await asyncio.gather(*running,return_exceptions=True)
