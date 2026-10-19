"""Transactional Tetris storage. Caller owns BEGIN IMMEDIATE/commit/rollback.
No model calls or planning inside a transaction; all user reads are scoped.
"""
import hashlib
import json
from uuid import uuid4
from pydantic import ValidationError
from ..services.tetris_sessions import rules
from ..services.tetris_sessions.contracts import CommandRequest,HandoffRequest,RULE_VERSION,FIXTURE_SHA256

MAX_SESSIONS=4
class SessionError(ValueError):
    def __init__(self,status,detail):self.status=status;self.detail=detail;super().__init__(detail)
def _json(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def _hash(value):return hashlib.sha256(_json(value).encode()).hexdigest()
def _validate(model,body):
    try:
        if len(_json(body).encode())>65536:raise SessionError(413,'request exceeds 64KiB')
        return model.model_validate(body).model_dump(exclude_none=True)
    except ValidationError as error:raise SessionError(422,'invalid session request') from error
def _restore(snapshot):
    try:return rules.restore(snapshot)
    except rules.InvalidSnapshot as error:raise SessionError(422,'invalid Tetris snapshot') from error
def _row(c,user_id,sid):
    row=c.execute('SELECT * FROM tetris_sessions WHERE id=? AND user_id=?',(sid,user_id)).fetchone()
    if row is None:raise SessionError(404,'session not found')
    return dict(row)
def _view(row):
    snapshot=json.loads(row['snapshot_json'])
    public_state='over' if row['run_state']=='ended' else ('paused' if snapshot['phase']=='paused' else 'running')
    return dict(id=row['id'],originClientID=row['origin_client_id'],botID=row['bot_id'],controller=row['controller'],runState=public_state,version=row['version'],controlEpoch=row['control_epoch'],latestSnapshot=snapshot,contribution=dict(playerScore=row['player_score'],playerLines=row['player_lines'],botScore=row['bot_score'],botLines=row['bot_lines']),updatedAt=row['updated_at'],pendingOperation=row['pending_request_id'],events=[],eventCursor=snapshot['eventSequence'],snapshotFallback=True)
def get_session(c,user_id,session_id,after_event_sequence=None):
    result=_view(_row(c,user_id,session_id))
    if after_event_sequence is not None:
        events=c.execute('SELECT payload_json FROM tetris_events WHERE session_id=? AND event_sequence>? ORDER BY event_sequence LIMIT 101',(session_id,after_event_sequence)).fetchall()
        if len(events)<=100:
            result['events']=[json.loads(event[0]) for event in events]
            result['snapshotFallback']=False
    return result
def get_current(c,user_id):
    row=c.execute("SELECT id FROM tetris_sessions WHERE user_id=? AND controller='bot' AND run_state!='ended' ORDER BY updated_at DESC LIMIT 1",(user_id,)).fetchone()
    return get_session(c,user_id,row['id']) if row else None
def get_operation(c,user_id,request_id):
    row=c.execute('SELECT result_json FROM tetris_operations WHERE user_id=? AND request_id=?',(user_id,request_id)).fetchone()
    if row is None:raise SessionError(404,'operation not found')
    return json.loads(row['result_json'])
def _retry(c,user_id,request_id,digest):
    row=c.execute('SELECT payload_hash,result_json FROM tetris_operations WHERE user_id=? AND request_id=?',(user_id,request_id)).fetchone()
    if row is None:return None
    if row['payload_hash']!=digest:raise SessionError(409,'requestID reused with another payload')
    return json.loads(row['result_json'])
def heartbeat(c,owner,now):
    c.execute('INSERT INTO tetris_workers(owner,heartbeat,rule_version,fixture_sha256) VALUES(?,?,?,?) ON CONFLICT(owner) DO UPDATE SET heartbeat=excluded.heartbeat,rule_version=excluded.rule_version,fixture_sha256=excluded.fixture_sha256',(owner,now,RULE_VERSION,FIXTURE_SHA256))
def capabilities(c,now):
    ready=c.execute('SELECT 1 FROM tetris_workers WHERE heartbeat>=? AND rule_version=? AND fixture_sha256=? LIMIT 1',(now-10,RULE_VERSION,FIXTURE_SHA256)).fetchone() is not None
    active=c.execute("SELECT count(*) FROM tetris_sessions WHERE controller='bot' AND run_state!='ended'").fetchone()[0]
    return dict(available=ready and active<MAX_SESSIONS,workerReady=ready,active=active,capacity=MAX_SESSIONS,ruleVersion=RULE_VERSION,fixtureSHA256=FIXTURE_SHA256)
def _admit(c,now):
    if not capabilities(c,now)['available']:raise SessionError(503,'Tetris worker unavailable or at capacity')
def _bot(c,user_id,bot_id):
    if c.execute('SELECT 1 FROM bots WHERE id=? AND user_id=?',(bot_id,user_id)).fetchone() is None:raise SessionError(404,'bot not found')
def _one_round(c,user_id,exclude=None):
    if c.execute("SELECT 1 FROM tetris_sessions WHERE user_id=? AND controller='bot' AND run_state!='ended' AND id!=?",(user_id,exclude or '')).fetchone():raise SessionError(409,'another Bot round is active')
def _normalize(game):
    if game.state['phase']=='over':raise SessionError(422,'cannot hand off an ended board')
    events=[]
    if game.state['phase']=='ready':events=rules.apply(game,'start')
    if game.state['phase']=='paused':events=rules.apply(game,'resume')
    return events

def create_handoff(c,user_id,body,now):
    body=_validate(HandoffRequest,body);digest=_hash(dict(path='create',body=body))
    retry=_retry(c,user_id,body['requestID'],digest)
    if retry is not None:return retry
    if body['expectedVersion']!=0 or body['expectedEpoch']!=0:raise SessionError(409,'initial version must be zero')
    _bot(c,user_id,body['botID']);_one_round(c,user_id);_admit(c,now)
    game=_restore(body['snapshot']);events=_normalize(game);snapshot=rules.snapshot(game)
    sid=str(uuid4())
    c.execute('''INSERT INTO tetris_sessions(id,user_id,bot_id,origin_client_id,controller,run_state,version,control_epoch,snapshot_json,pending_clear_controller,player_score,player_lines,bot_score,bot_lines,next_due,updated_at)
      VALUES(?,?,?,?,'bot','running',1,1,?,?,?,?,0,0,?,?)''',(sid,user_id,body['botID'],body['clientID'],_json(snapshot),'player' if snapshot['phase']=='clearing' else None,snapshot['score'],snapshot['lines'],now,now))
    _events(c,sid,events,snapshot,'player')
    result=dict(requestID=body['requestID'],status='committed',session=get_session(c,user_id,sid))
    c.execute('INSERT INTO tetris_operations VALUES(?,?,?,?,?,?)',(user_id,body['requestID'],sid,digest,_json(result),'committed'))
    return result

def apply_command(c,user_id,session_id,body,now):
    body=_validate(CommandRequest,body);digest=_hash(dict(path=session_id,body=body))
    retry=_retry(c,user_id,body['requestID'],digest)
    if retry is not None:return retry
    row=_row(c,user_id,session_id)
    if row['origin_client_id']!=body['clientID']:raise SessionError(403,'original client required')
    if row['version']!=body['expectedVersion'] or row['control_epoch']!=body['expectedEpoch']:raise SessionError(409,'session changed')
    if row['run_state']=='ended':raise SessionError(409,'round ended')
    if row['pending_request_id']:raise SessionError(409,'control transition pending')
    command=body['command'];game=_restore(json.loads(row['snapshot_json']));events=[];pending=None
    if command=='handoff':
        if row['controller']!='player' or 'snapshot' not in body or 'botID' not in body:raise SessionError(409,'player snapshot and Bot required')
        _bot(c,user_id,body['botID']);_one_round(c,user_id,session_id);_admit(c,now)
        game=_restore(body['snapshot'])
        old=json.loads(row['snapshot_json'])
        if any(game.state[key]<old[key] for key in ('score','lines','eventSequence','logicalTimeMs')):raise SessionError(409,'stale player snapshot')
        row['player_score']+=game.state['score']-old['score'];row['player_lines']+=game.state['lines']-old['lines']
        events=_normalize(game);row.update(controller='bot',run_state='running',control_epoch=row['control_epoch']+1,bot_id=body['botID'],pending_clear_controller='player' if game.state['phase']=='clearing' else None)
    elif command=='reclaim':
        if row['controller']!='bot':raise SessionError(409,'already controlled by player')
        row['run_state']='reclaimPending';pending=body['requestID']
    elif command in ('pauseBot','resumeBot','changeBot'):
        if row['controller']!='bot':raise SessionError(409,'Bot does not control this round')
        if command=='resumeBot':
            _admit(c,now) if not capabilities(c,now)['workerReady'] else None
            events=rules.apply(game,'resume');row['run_state']='running'
        else:
            if command=='changeBot':
                if 'botID' not in body:raise SessionError(422,'botID required')
                _bot(c,user_id,body['botID']);row['bot_id']=body['botID'];row['control_epoch']+=1
            events=rules.apply(game,'pause');row['run_state']='paused'
    elif command=='end':
        events=rules.apply(game,'pause');row['run_state']='ended';row['ended_at']=now;row['control_epoch']+=1
    snapshot=rules.snapshot(game)
    c.execute('''UPDATE tetris_sessions SET bot_id=?,controller=?,run_state=?,version=version+1,control_epoch=?,snapshot_json=?,pending_request_id=?,pending_clear_controller=?,player_score=?,player_lines=?,lease_owner=NULL,lease_token=NULL,lease_expires=NULL,next_due=?,updated_at=?,ended_at=? WHERE id=? AND user_id=?''',(row['bot_id'],row['controller'],row['run_state'],row['control_epoch'],_json(snapshot),pending,row['pending_clear_controller'],row['player_score'],row['player_lines'],now,now,row.get('ended_at'),session_id,user_id))
    _events(c,session_id,events,snapshot,row['controller'])
    status='pending' if pending else 'committed'
    result=dict(requestID=body['requestID'],status=status,session=get_session(c,user_id,session_id))
    c.execute('INSERT INTO tetris_operations VALUES(?,?,?,?,?,?)',(user_id,body['requestID'],session_id,digest,_json(result),status))
    return result

def _events(c,sid,events,snapshot,controller):
    for event in events:
        c.execute('INSERT INTO tetris_events VALUES(?,?,?,?,?,?)',(sid,event['sequence'],event.get('logicalTimeMs',snapshot['logicalTimeMs']),event['kind'],event.get('controller',controller),_json(event)))
def claim(c,owner,now,lease_seconds=10):
    row=c.execute("SELECT * FROM tetris_sessions WHERE controller='bot' AND run_state IN ('running','reclaimPending') AND next_due<=? AND (lease_expires IS NULL OR lease_expires<=?) ORDER BY next_due,id LIMIT 1",(now,now)).fetchone()
    if row is None:return None
    token=str(uuid4());sid=row['id']
    changed=c.execute('UPDATE tetris_sessions SET lease_owner=?,lease_token=?,lease_expires=? WHERE id=? AND (lease_expires IS NULL OR lease_expires<=?)',(owner,token,now+lease_seconds,sid,now)).rowcount
    if not changed:return None
    return _lease(dict(c.execute('SELECT * FROM tetris_sessions WHERE id=?',(sid,)).fetchone()))
def _lease(row):
    return dict(id=row['id'],userID=row['user_id'],version=row['version'],controlEpoch=row['control_epoch'],leaseToken=row['lease_token'],leaseExpires=row['lease_expires'],runState=row['run_state'],snapshot=json.loads(row['snapshot_json']),nextDue=row['next_due'])
def leased(c,owner,now):
    return [_lease(dict(row)) for row in c.execute("SELECT * FROM tetris_sessions WHERE lease_owner=? AND lease_expires>? AND controller='bot' AND run_state IN ('running','reclaimPending') AND next_due<=? ORDER BY next_due,id",(owner,now,now))]
def renew(c,session_id,owner,token,now):
    return c.execute('UPDATE tetris_sessions SET lease_expires=? WHERE id=? AND lease_owner=? AND lease_token=? AND lease_expires>?',(now+10,session_id,owner,token,now)).rowcount==1

def commit_batch(c,session_id,expected_version,epoch,lease_token,snapshot,events,now,transition_only=False):
    raw=c.execute('SELECT * FROM tetris_sessions WHERE id=?',(session_id,)).fetchone()
    if raw is None:return False
    row=dict(raw)
    if row['version']!=expected_version or row['control_epoch']!=epoch or row['lease_token']!=lease_token or row['lease_expires'] is None or row['lease_expires']<=now:return False
    if row['run_state']=='reclaimPending' and not transition_only:return False
    if row['controller']!='bot' or row['run_state'] not in ('running','reclaimPending'):return False
    game=_restore(snapshot);snapshot=rules.snapshot(game);old=json.loads(row['snapshot_json'])
    if any(snapshot[key]<old[key] for key in ('score','lines','eventSequence','logicalTimeMs')):return False
    if [event['sequence'] for event in events]!=list(range(old['eventSequence']+1,snapshot['eventSequence']+1)):return False
    delta_score=snapshot['score']-old['score'];delta_lines=snapshot['lines']-old['lines']
    pending=row['pending_clear_controller'];player_clear_score=player_clear_lines=0
    tagged=[]
    for event in events:
        actor=pending if event['kind']=='linesCleared' and pending else 'bot'
        if event['kind']=='linesCleared' and actor=='player':
            player_clear_lines+=event['count'];player_clear_score+=[0,100,300,500,800][event['count']]
        tagged.append({**event,'controller':actor})
        if event['kind']=='locked':pending='bot'
        if event['kind'] in ('spawned','linesCleared'):pending=None
    if player_clear_score>delta_score or player_clear_lines>delta_lines:return False
    row['player_score']+=player_clear_score;row['player_lines']+=player_clear_lines
    row['bot_score']+=delta_score-player_clear_score;row['bot_lines']+=delta_lines-player_clear_lines
    returned=row['run_state']=='reclaimPending' and snapshot['phase']=='paused' and snapshot.get('resumePhase')!='clearing'
    ended=snapshot['phase']=='over'
    if returned:row['controller']='player';row['control_epoch']+=1;row['run_state']='paused'
    if ended:row['run_state']='ended';row['ended_at']=now
    invalidate=returned or ended
    c.execute('''UPDATE tetris_sessions SET controller=?,run_state=?,version=version+1,control_epoch=?,snapshot_json=?,pending_clear_controller=?,player_score=?,player_lines=?,bot_score=?,bot_lines=?,lease_owner=CASE WHEN ? THEN NULL ELSE lease_owner END,lease_token=CASE WHEN ? THEN NULL ELSE lease_token END,lease_expires=CASE WHEN ? THEN NULL ELSE lease_expires END,next_due=?,updated_at=?,ended_at=?,pending_request_id=CASE WHEN ? THEN NULL ELSE pending_request_id END WHERE id=?''',(row['controller'],row['run_state'],row['control_epoch'],_json(snapshot),pending if snapshot['phase']=='clearing' or snapshot.get('resumePhase')=='clearing' else None,row['player_score'],row['player_lines'],row['bot_score'],row['bot_lines'],invalidate,invalidate,invalidate,(row['next_due']+.1 if 0<=now-row['next_due']<.1 else now+.1),now,row.get('ended_at'),invalidate,session_id))
    _events(c,session_id,tagged,snapshot,'bot')
    if invalidate and row['pending_request_id']:
        result=dict(requestID=row['pending_request_id'],status='committed',session=get_session(c,row['user_id'],session_id))
        c.execute("UPDATE tetris_operations SET result_json=?,status='committed' WHERE user_id=? AND request_id=?",(_json(result),row['user_id'],row['pending_request_id']))
    return True
