"""Pure vera-tetris-2 engine. Integer milliseconds, xorshift32 and custom kicks.
No wall clock, database, random module, network, or LLM access.
"""
import copy
from dataclasses import dataclass
from pydantic import ValidationError
from .contracts import Snapshot, RULE_VERSION, Action
from typing import get_args

BASE = {1:((0,1),(1,1),(2,1),(3,1)),2:((0,0),(0,1),(1,1),(2,1)),
        3:((2,0),(0,1),(1,1),(2,1)),4:((1,0),(2,0),(1,1),(2,1)),
        5:((1,0),(2,0),(0,1),(1,1)),6:((1,0),(0,1),(1,1),(2,1)),
        7:((0,0),(1,0),(1,1),(2,1))}
KICKS=((0,0),(-1,0),(1,0),(-2,0),(2,0),(0,-1),(-1,-1),(1,-1),(0,-2))
class InvalidSnapshot(ValueError): pass
@dataclass
class GameState:
    state: dict

def interval(s): return max(130,620-(s['lines']//10)*55)
def cells(piece):
    if piece is None:return []
    points=BASE[piece['kind']]
    axis=3 if piece['kind']==1 else 2
    if piece['kind']!=4:
        for _ in range(piece['rotation']):points=tuple((axis-y,x) for x,y in points)
    return [(piece['x']+x,piece['y']+y) for x,y in points]
def fits(s,piece):
    return piece['y']>=-4 and all(0<=x<10 and y<20 and (y<0 or s['board'][10*y+x]==0) for x,y in cells(piece))
def grounded(s,piece):return not fits(s,{**piece,'y':piece['y']+1})
def full_rows(s):return [y for y in range(20) if all(s['board'][10*y:10*y+10])]

def restore(value):
    try:s=Snapshot.model_validate(value).model_dump(exclude_none=True)
    except (ValidationError,TypeError) as error:raise InvalidSnapshot(str(error)) from error
    if any(not 0<=v<=7 for v in s['board']) or any(not 1<=v<=7 for v in s['bag']) or len(set(s['bag']))!=len(s['bag']):
        raise InvalidSnapshot('invalid board or bag')
    if s['gravityRemainingMs']>interval(s):raise InvalidSnapshot('gravity timer outside level interval')
    if s['phase']=='paused':
        if s.get('resumePhase') not in ('running','clearing'):raise InvalidSnapshot('missing resume phase')
    elif 'resumePhase' in s:raise InvalidSnapshot('unexpected resume phase')
    clearing=s['phase']=='clearing' or s.get('resumePhase')=='clearing'
    if clearing:
        if s.get('active') is not None or not 1<=s['clearRemainingMs']<=180 or not 1<=len(s['pendingClearRows'])<=4 or s['pendingClearRows']!=full_rows(s):
            raise InvalidSnapshot('inconsistent clearing state')
    elif s['phase']!='over':
        if s['clearRemainingMs']!=0 or s['pendingClearRows'] or full_rows(s) or not s.get('active') or not fits(s,s['active']):
            raise InvalidSnapshot('inconsistent active state')
    return GameState(s)
def snapshot(game):return copy.deepcopy(game.state)
def _random(s):
    value=s['rngState']
    value^=(value<<13)&0xffffffff;value^=value>>17;value^=(value<<5)&0xffffffff
    s['rngState']=value
    return value
def _uniform(s,count):
    limit=2**32-(2**32%count)
    value=_random(s)
    while value>=limit:value=_random(s)
    return value%count
def _draw(s):
    if not s['bag']:
        s['bag']=list(range(1,8))
        for index in range(6,0,-1):
            other=_uniform(s,index+1);s['bag'][index],s['bag'][other]=s['bag'][other],s['bag'][index]
    return s['bag'].pop(0)
def _piece(kind):return dict(kind=kind,rotation=0,x=3,y=0)
def new(seed):
    if type(seed) is not int or not 0<=seed<=0xffffffff:raise ValueError('seed must be UInt32')
    s=dict(ruleVersion=RULE_VERSION,board=[0]*200,next=4,bag=[],rngState=seed or 0x6D2B79F5,score=0,lines=0,lockedPieces=0,phase='ready',logicalTimeMs=0,stepRemainderMs=0,gravityRemainingMs=620,lockRemainingMs=500,lockResetCount=0,clearRemainingMs=0,pendingClearRows=[],eventSequence=0)
    s['active']=_piece(_draw(s));s['next']=_draw(s)
    return restore(s)
def _emit(s,events,kind,count=0,hard=False):
    s['eventSequence']+=1
    events.append(dict(sequence=s['eventSequence'],kind=kind,count=count,fromHardDrop=hard))
def _end(s,events,reason):
    s.update(phase='over',endReason=reason);s.pop('resumePhase',None);_emit(s,events,'ended')
def _spawn(s,events):
    s['active']=_piece(s['next']);s['next']=_draw(s)
    s.update(phase='running',pendingClearRows=[],clearRemainingMs=0,lockRemainingMs=500,lockResetCount=0,gravityRemainingMs=interval(s))
    s.pop('resumePhase',None)
    _emit(s,events,'spawned')
    if not fits(s,s['active']):_end(s,events,'blockedSpawn')
def _clear(s,events,rows):
    count=len(rows)
    if not count:return
    s['board']=[0]*(count*10)+[s['board'][y*10+x] for y in range(20) if y not in rows for x in range(10)]
    s['lines']+=count;s['score']+=[0,100,300,500,800][count]
    _emit(s,events,'linesCleared',count)
def _lock(s,events,hard=False):
    occupied=cells(s['active'])
    if any(y<0 for x,y in occupied):_end(s,events,'topOut');return
    for x,y in occupied:s['board'][y*10+x]=s['active']['kind']
    s['lockedPieces']+=1;_emit(s,events,'locked',hard=hard)
    rows=full_rows(s)
    if rows:
        s.update(pendingClearRows=rows,clearRemainingMs=180,phase='clearing');s.pop('active',None);return
    _spawn(s,events)
def _reset(s,was_grounded):
    if was_grounded and s['lockResetCount']<15:s['lockResetCount']+=1;s['lockRemainingMs']=500

def apply(game,action):
    if action not in get_args(Action):raise ValueError('unknown action')
    s=game.state;events=[]
    if action=='pause' and s['phase'] in ('running','clearing'):
        s['resumePhase']=s['phase'];s['phase']='paused';_emit(s,events,'paused');return events
    if action=='resume' and s['phase']=='paused':
        s['phase']=s.pop('resumePhase');_emit(s,events,'resumed');return events
    if action=='start' and s['phase']=='ready':s['phase']='running';_emit(s,events,'resumed');return events
    if s['phase']!='running' or not s.get('active'):return events
    piece=copy.copy(s['active']);was_grounded=grounded(s,piece)
    if action in ('moveLeft','moveRight'):
        piece['x']+=-1 if action=='moveLeft' else 1
        if fits(s,piece):s['active']=piece;_reset(s,was_grounded);_emit(s,events,'moved')
    elif action=='rotateClockwise':
        if piece['kind']==4:return events
        piece['rotation']=(piece['rotation']+1)%4
        for dx,dy in KICKS:
            candidate={**piece,'x':piece['x']+dx,'y':piece['y']+dy}
            if fits(s,candidate):s['active']=candidate;_reset(s,was_grounded);_emit(s,events,'rotated');break
    elif action=='softDrop':
        piece['y']+=1
        if fits(s,piece):s['active']=piece;s['score']+=1;_emit(s,events,'moved')
    elif action=='hardDrop':
        distance=0
        while fits(s,{**piece,'y':piece['y']+1}):piece['y']+=1;distance+=1
        s['active']=piece;s['score']+=distance*2;_lock(s,events,hard=True)
    return events

def advance(game,milliseconds):
    if type(milliseconds) is not int or milliseconds<0:raise ValueError('elapsed must be nonnegative integer')
    s=game.state;events=[]
    if s['phase'] not in ('running','clearing') or milliseconds==0:return events
    s['stepRemainderMs']+=milliseconds
    while s['stepRemainderMs']>=10 and s['phase'] in ('running','clearing'):
        s['stepRemainderMs']-=10;s['logicalTimeMs']+=10
        if s['phase']=='clearing':
            s['clearRemainingMs']-=10
            if s['clearRemainingMs']<=0:_clear(s,events,s['pendingClearRows']);_spawn(s,events)
            continue
        was_grounded=grounded(s,s['active'])
        s['gravityRemainingMs']-=10
        if s['gravityRemainingMs']<=0:
            s['gravityRemainingMs']=interval(s)
            piece={**s['active'],'y':s['active']['y']+1}
            if fits(s,piece):s['active']=piece;_emit(s,events,'moved')
        if was_grounded and grounded(s,s['active']):
            s['lockRemainingMs']-=10
            if s['lockRemainingMs']<=0:_lock(s,events)
    if s['phase']=='over':s['stepRemainderMs']=0
    return events
