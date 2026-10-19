"""Independent, bounded worker. Durable CAS is the only publication point.
Every computation is tentative; API control changes reject the entire old batch.
"""
from collections import deque
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
import time
from uuid import uuid4
from ...db.database import tx
from ...db import tetris_session_store as store
from . import planner,rules

@dataclass(frozen=True)
class TickResult:
    published:tuple
    errors:int
    rejected:int
    latenessMs:tuple
    errorKinds:tuple=()

class Worker:
    def __init__(self,transaction=tx,owner=None,executor=None,clock=time.time):
        self.transaction=transaction;self.owner=owner or str(uuid4());self.clock=clock
        self.executor=executor or ProcessPoolExecutor(max_workers=2)
        self.owns_executor=executor is None
        self.jobs={};self.plans={};self.needs={};self.last_action={};self.last_scheduled={};self.counter=0;self.closed=False
    def close(self):
        if self.closed:return
        self.closed=True
        for future,_ in self.jobs.values():future.cancel()
        if self.owns_executor:self.executor.shutdown(wait=True,cancel_futures=True)
        with self.transaction(immediate=True) as c:
            c.execute('UPDATE tetris_sessions SET lease_owner=NULL,lease_token=NULL,lease_expires=NULL WHERE lease_owner=?',(self.owner,))
            c.execute('DELETE FROM tetris_workers WHERE owner=?',(self.owner,))
    @staticmethod
    def _tag(events,game):
        return [{**event,'logicalTimeMs':game.state['logicalTimeMs']} for event in events]
    def _ready_plan(self,lease):
        sid=lease['id'];job=self.jobs.get(sid)
        if job and job[0].done():
            future,identity=self.jobs.pop(sid)
            try:result=future.result()
            except Exception:result=None
            if result and identity==(lease['version'],lease['controlEpoch'],lease['leaseToken']) and result.startLogicalTimeMs==lease['snapshot']['logicalTimeMs']:
                self.plans[sid]=dict(actions=deque(result.actions),version=lease['version'],epoch=lease['controlEpoch'],token=lease['leaseToken'])
        cached=self.plans.get(sid)
        if cached and (cached['version'],cached['epoch'],cached['token'])!=(lease['version'],lease['controlEpoch'],lease['leaseToken']):
            self.plans.pop(sid,None);cached=None
        return cached
    def _transition(self,game):
        events=[]
        if game.state['phase']=='paused' and game.state.get('resumePhase')=='clearing':events+=self._tag(rules.apply(game,'resume'),game)
        for _ in range(10):
            if game.state['phase']!='clearing':break
            events+=self._tag(rules.advance(game,10),game)
        if game.state['phase'] not in ('clearing','over'):events+=self._tag(rules.apply(game,'pause'),game)
        return events
    def _ordinary(self,lease,game,cached):
        events=[];sid=lease['id']
        for _ in range(10):
            if game.state['phase']=='over':break
            actions=cached['actions'] if cached else ()
            if actions and game.state['phase']=='running' and actions[0].earliestLogicalTimeMs<=game.state['logicalTimeMs']:
                action=actions.popleft()
                if game.state['logicalTimeMs']-self.last_action.get(sid,-1000000)>=40:
                    emitted=rules.apply(game,action.action)
                    if emitted:
                        self.last_action[sid]=game.state['logicalTimeMs']
                        events+=self._tag(emitted,game)
                    else:actions.clear()
                else:actions.clear()
            events+=self._tag(rules.advance(game,10),game)
            if any(event['kind']=='locked' for event in events) and cached:cached['actions'].clear()
        return events
    @staticmethod
    def _error(stage,error):
        return f"{stage}:{type(error).__name__}:{str(error)[:160]}"
    def _submit(self):
        # Only two outstanding jobs, including obsolete jobs still executing. No
        # unbounded executor queue; least recently scheduled round goes first.
        errors=[]
        for sid in sorted(self.needs,key=lambda key:self.last_scheduled.get(key,-1)):
            if len(self.jobs)>=2:break
            if sid in self.jobs:continue
            lease=self.needs[sid]
            public=planner.PlannerState.from_snapshot(lease['snapshot'],lease['version'],lease['controlEpoch'],self.last_action.get(sid,-40)+40)
            try:future=self.executor.submit(planner.plan,public)
            except Exception as error:
                errors.append(self._error('planning',error))
                continue
            self.jobs[sid]=(future,(lease['version'],lease['controlEpoch'],lease['leaseToken']))
            self.counter+=1;self.last_scheduled[sid]=self.counter
            self.needs.pop(sid,None)
        return errors
    def tick(self,now=None):
        if self.closed:raise RuntimeError('worker closed')
        current=(lambda:now) if now is not None else self.clock
        published=[];errors=0;rejected=0;late=[];error_kinds=[]
        try:
            with self.transaction(immediate=True) as c:
                timestamp=current();store.heartbeat(c,self.owner,timestamp)
                c.execute("DELETE FROM tetris_sessions WHERE run_state='ended' AND ended_at<?",(timestamp-7*86400,))
                leases=store.leased(c,self.owner,timestamp)
                while len(leases)<store.MAX_SESSIONS:
                    lease=store.claim(c,self.owner,timestamp)
                    if lease is None:break
                    leases.append(lease)
                owned={row[0] for row in c.execute("SELECT id FROM tetris_sessions WHERE lease_owner=? AND lease_expires>? AND controller='bot' AND run_state IN ('running','reclaimPending')",(self.owner,timestamp))}
        except Exception as error:return TickResult((),1,0,(),(self._error("claim",error),))
        for mapping in (self.plans,self.needs,self.last_action,self.last_scheduled):
            for sid in list(mapping):
                if sid not in owned:mapping.pop(sid,None)
        for sid,(future,identity) in list(self.jobs.items()):
            if sid not in owned and (future.done() or future.cancel()):self.jobs.pop(sid,None)
        for lease in leases:
            sid=lease['id']
            stage='restore'
            try:
                cached=self._ready_plan(lease)
                game=rules.restore(lease['snapshot']);transition=lease['runState']=='reclaimPending'
                stage='simulate'
                if transition:
                    self.plans.pop(sid,None);self.needs.pop(sid,None)
                    job=self.jobs.get(sid)
                    if job and job[0].cancel():self.jobs.pop(sid,None)
                    events=self._transition(game)
                else:events=self._ordinary(lease,game,cached)
                snapshot=rules.snapshot(game)
                stage='commit'
                with self.transaction(immediate=True) as c:
                    timestamp=current()
                    committed=store.commit_batch(c,sid,lease['version'],lease['controlEpoch'],lease['leaseToken'],snapshot,events,timestamp,transition_only=transition)
                    if committed and not transition:store.renew(c,sid,self.owner,lease['leaseToken'],timestamp)
                # Context manager commit has completed; a failed commit cannot publish.
                if not committed:
                    rejected+=1;self.plans.pop(sid,None);self.needs.pop(sid,None);continue
                published.append((sid,lease['version']+1));late.append(max(0,(timestamp-lease['nextDue'])*1000))
                if cached:cached['version']=lease['version']+1
                if not transition and snapshot['phase']=='running' and (not cached or not cached['actions']):
                    self.needs[sid]={**lease,'version':lease['version']+1,'snapshot':snapshot}
            except Exception as error:
                error_kinds.append(self._error(stage,error))
                errors+=1;self.plans.pop(sid,None);self.needs.pop(sid,None)
        planning_errors=self._submit();errors+=len(planning_errors);error_kinds.extend(planning_errors)
        return TickResult(tuple(published),errors,rejected,tuple(late),tuple(error_kinds))
