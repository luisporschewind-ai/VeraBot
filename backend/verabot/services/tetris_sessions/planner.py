"""Bounded legal-path search. Public information only; never calls a model."""
from collections import deque
from dataclasses import dataclass
import time
from . import rules

@dataclass(frozen=True)
class PlannerState:
    board:tuple
    current:tuple
    next:int
    lines:int
    gravityRemainingMs:int
    lockRemainingMs:int
    lockResetCount:int
    logicalTimeMs:int
    stepRemainderMs:int
    version:int
    controlEpoch:int
    nextInputTimeMs:int
    @classmethod
    def from_snapshot(cls,snapshot,version,epoch,earliest_action_ms=None):
        active=snapshot.get('active')
        if snapshot['phase']!='running' or active is None:raise ValueError('planner requires a running active piece')
        return cls(tuple(snapshot['board']),tuple(active[key] for key in ('kind','rotation','x','y')),snapshot['next'],snapshot['lines'],snapshot['gravityRemainingMs'],snapshot['lockRemainingMs'],snapshot['lockResetCount'],snapshot['logicalTimeMs'],snapshot['stepRemainderMs'],version,epoch,max(snapshot['logicalTimeMs'],earliest_action_ms or 0))

@dataclass(frozen=True)
class PlannedAction:
    action:str
    earliestLogicalTimeMs:int
@dataclass(frozen=True)
class Plan:
    version:int
    controlEpoch:int
    startLogicalTimeMs:int
    actions:tuple
    nodes:int
    budgetExhausted:bool

def _simulation(public):
    # Synthetic post-current sequence is irrelevant: only current placement and the
    # already-public next spawn are evaluated. Hidden session bag/RNG never arrive here.
    game=rules.new(1)
    game.state.update(board=list(public.board),active=dict(zip(('kind','rotation','x','y'),public.current)),next=public.next,lines=public.lines,gravityRemainingMs=public.gravityRemainingMs,lockRemainingMs=public.lockRemainingMs,lockResetCount=public.lockResetCount,logicalTimeMs=public.logicalTimeMs,stepRemainderMs=public.stepRemainderMs,phase='running')
    return rules.restore(game.state)
def _surface(board):
    heights=[];holes=0
    for x in range(10):
        occupied=False;height=0
        for y in range(20):
            if board[10*y+x]:occupied=True;height=max(height,20-y)
            elif occupied:holes+=1
        heights.append(height)
    return holes,sum(heights),sum(abs(a-b) for a,b in zip(heights,heights[1:]))
def _key(s):
    p=s['active']
    return (p['rotation'],p['x'],p['y'],s['gravityRemainingMs'],s['lockRemainingMs'],s['lockResetCount'])
def plan(public_state,max_nodes=2000,budget_ms=20,_clock=time.perf_counter):
    if not 1<=max_nodes<=2000 or not 0<budget_ms<=20:raise ValueError('planner budget outside limits')
    initial=_simulation(public_state)
    rules.advance(initial,public_state.nextInputTimeMs-public_state.logicalTimeMs)
    if initial.state['phase']!='running' or initial.state['lockedPieces']:
        return Plan(public_state.version,public_state.controlEpoch,public_state.logicalTimeMs,(),0,False)
    start=_clock();base_holes=_surface(initial.state['board'])[0]
    queue=deque([(initial,())]);visited={_key(initial.state)};nodes=0;exhausted=False
    best=None;best_actions=()
    while queue and nodes<max_nodes:
        # Always evaluate the initial immediate hard drop, even on an exhausted budget.
        if nodes and (_clock()-start)*1000>=budget_ms:exhausted=True;break
        game,path=queue.popleft();nodes+=1
        landing=rules.restore(rules.snapshot(game));piece_cells=rules.cells(game.state['active'])
        rules.apply(landing,'hardDrop')
        if landing.state['phase']=='clearing':rules.advance(landing,landing.state['clearRemainingMs'])
        holes,height,bump=_surface(landing.state['board'])
        quality=(landing.state['phase']=='over',holes-base_holes,height,bump,-(landing.state['lines']-initial.state['lines']),len(path)+1,min(x for x,y in piece_cells))
        if best is None or quality<best:
            best=quality;best_actions=path+(PlannedAction('hardDrop',game.state['logicalTimeMs']),)
        if (_clock()-start)*1000>=budget_ms:exhausted=True;break
        for action in ('moveLeft','moveRight','rotateClockwise','softDrop'):
            child=rules.restore(rules.snapshot(game))
            if not rules.apply(child,action):continue
            at=game.state['logicalTimeMs']
            rules.advance(child,40)
            if child.state['phase']!='running' or child.state['lockedPieces']!=initial.state['lockedPieces']:continue
            key=_key(child.state)
            if key in visited:continue
            visited.add(key);queue.append((child,path+(PlannedAction(action,at),)))
    return Plan(public_state.version,public_state.controlEpoch,public_state.logicalTimeMs,best_actions,nodes,exhausted or bool(queue and nodes>=max_nodes))
