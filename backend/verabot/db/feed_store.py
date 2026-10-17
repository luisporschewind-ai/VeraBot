"""Tenant-scoped Feed SQL. Caller owns transactions; network never runs here."""
import json
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from .database import row, rows, now_iso

DEFAULT_PLAN = dict(enabled=False,bot_ids=[],topics=[],excluded_topics=[],use_memory=True,daily_limit=20,version=0)
SOURCE_FIELDS = ('id','name','url','kind','bot_id','enabled','last_success_at','next_fetch_at','last_error','failure_count')

def plan(c,user_id):
    p=row(c.execute('SELECT * FROM feed_plans WHERE user_id=?',(user_id,)).fetchone())
    if not p: return dict(DEFAULT_PLAN)
    return dict(enabled=bool(p['enabled']),bot_ids=json.loads(p['bot_ids']),topics=json.loads(p['topics']),
                excluded_topics=json.loads(p['excluded_topics']),use_memory=bool(p['use_memory']),daily_limit=20,version=p['version'])

def put_plan(c,user_id,p,expected):
    old=plan(c,user_id)
    if old['version']!=expected: return None
    c.execute('INSERT INTO feed_plans(user_id,enabled,bot_ids,topics,excluded_topics,use_memory,version) VALUES(?,?,?,?,?,?,?) '
              'ON CONFLICT(user_id) DO UPDATE SET enabled=excluded.enabled,bot_ids=excluded.bot_ids,topics=excluded.topics,'
              'excluded_topics=excluded.excluded_topics,use_memory=excluded.use_memory,version=excluded.version',
              (user_id,int(p['enabled']),json.dumps(p['bot_ids']),json.dumps(p['topics']),json.dumps(p['excluded_topics']),int(p['use_memory']),expected+1))
    # Any edit revokes in-flight snapshots, even if pause and resume happen during a fetch.
    c.execute('UPDATE feed_sources SET lease_token=NULL,lease_until=NULL WHERE user_id=?',(user_id,))
    return plan(c,user_id)

def bot(c,user_id,bot_id):
    return row(c.execute('SELECT id,name,memory_access FROM bots WHERE id=? AND user_id=?',(bot_id,user_id)).fetchone())

def public_source(s):
    result={k:s[k] for k in SOURCE_FIELDS}; result['enabled']=bool(result['enabled'])
    return result

def source(c,user_id,source_id):
    return row(c.execute('SELECT * FROM feed_sources WHERE user_id=? AND id=?',(user_id,source_id)).fetchone())

def sources(c,user_id):
    return [public_source(r) for r in rows(c.execute('SELECT * FROM feed_sources WHERE user_id=? ORDER BY id',(user_id,)).fetchall())]

class SourceLimitError(ValueError):
    pass

def add_source(c,user_id,p):
    found=c.execute('SELECT * FROM feed_sources WHERE user_id=? AND url=? AND COALESCE(bot_id,0)=?',
                    (user_id,p['url'],p.get('bot_id') or 0)).fetchone()
    if found: return public_source(dict(found))
    if c.execute('SELECT COUNT(*) FROM feed_sources WHERE user_id=?',(user_id,)).fetchone()[0]>=30:
        raise SourceLimitError('每个账号最多 30 个订阅来源')
    c.execute('INSERT OR IGNORE INTO feed_sources(user_id,name,url,kind,bot_id) VALUES(?,?,?,?,?)',
              (user_id,p['name'],p['url'],p['kind'],p.get('bot_id')))
    return public_source(dict(c.execute('SELECT * FROM feed_sources WHERE user_id=? AND url=? AND COALESCE(bot_id,0)=?',
                                       (user_id,p['url'],p.get('bot_id') or 0)).fetchone()))

def toggle_source(c,user_id,source_id,enabled):
    c.execute('UPDATE feed_sources SET enabled=?,revision=revision+1,lease_token=NULL,lease_until=NULL '
              'WHERE user_id=? AND id=?',(int(enabled),user_id,source_id))
    found=source(c,user_id,source_id)
    return public_source(found) if found else None

def refresh(c,user_id,now):
    if not plan(c,user_id)['enabled']: return False
    c.execute('UPDATE feed_sources SET next_fetch_at=? WHERE user_id=? AND enabled=1',(now,user_id))
    return True

def eligible(c,s,p):
    return p['enabled'] and s['enabled'] and (s['bot_id'] is None or (s['bot_id'] in p['bot_ids'] and bot(c,s['user_id'],s['bot_id']) is not None))

def claim(c,now,lease_seconds=300):
    # BEGIN IMMEDIATE at the caller serializes claims among processes.
    candidates=c.execute('SELECT s.* FROM feed_sources s JOIN feed_plans p ON p.user_id=s.user_id '
        'WHERE s.enabled=1 AND p.enabled=1 AND (s.next_fetch_at IS NULL OR s.next_fetch_at<=?) '
        'AND (s.lease_until IS NULL OR s.lease_until<=?) ORDER BY COALESCE(s.next_fetch_at,\'\'),s.id',(now,now))
    for candidate in candidates:
        s=dict(candidate)
        p=plan(c,s['user_id'])
        if not eligible(c,s,p): continue
        token=uuid4().hex
        until=(datetime.fromisoformat(now)+timedelta(seconds=lease_seconds)).isoformat()
        c.execute('UPDATE feed_sources SET lease_token=?,lease_until=? WHERE user_id=? AND id=?',(token,until,s['user_id'],s['id']))
        return dict(s,lease_token=token,lease_until=until,plan_version=p['version'])
    return None

def live_job(c,job,now):
    s=source(c,job['user_id'],job['id']); p=plan(c,job['user_id'])
    if not s or s['lease_token']!=job['lease_token'] or not s['lease_until'] or s['lease_until']<=now: return None
    if s['revision']!=job['revision'] or p['version']!=job['plan_version'] or not eligible(c,s,p): return None
    return s,p

def publication_allowance(c,source,p,now):
    """Daily ceiling per distinct eligible source URL; duplicate Bot subscriptions share it."""
    uid=source['user_id']
    enabled=rows(c.execute('SELECT * FROM feed_sources WHERE user_id=? AND enabled=1',(uid,)).fetchall())
    urls=sorted({s['url'] for s in enabled if eligible(c,s,p)})
    if not urls: return 0
    if len(urls)>20:
        # A deterministic daily rotating window lets every configured source take a turn.
        offset=(datetime.fromisoformat(now).date().toordinal()*20)%len(urls)
        selected={urls[(offset+i)%len(urls)] for i in range(20)}
        if source['url'] not in selected: return 0
    ceiling=max(1,20//len(urls))
    used=c.execute('SELECT COUNT(*) FROM feed_items i JOIN feed_sources s ON s.id=i.source_id AND s.user_id=i.user_id '
                   'WHERE i.user_id=? AND s.url=? AND substr(i.created_at,1,10)=?',
                   (uid,source['url'],now[:10])).fetchone()[0]
    return max(0,ceiling-used)

def stage_candidates(c,source,entries,now):
    """Keep at most 200 newest actual feed candidates, independently of published Feed items."""
    uid=source['user_id']; sid=source['id']
    for ordinal,entry in enumerate(entries[:200]):
        c.execute('INSERT INTO feed_pending_candidates(user_id,source_id,url,payload,published_at,fetched_at,ordinal) '
                  'VALUES(?,?,?,?,?,?,?) ON CONFLICT(user_id,source_id,url) DO UPDATE SET '
                  'payload=excluded.payload,published_at=excluded.published_at,fetched_at=excluded.fetched_at,ordinal=excluded.ordinal',
                  (uid,sid,entry['url'],json.dumps(entry,ensure_ascii=False),entry.get('published_at'),now,ordinal))
    c.execute('DELETE FROM feed_pending_candidates WHERE user_id=? AND source_id=? AND id NOT IN ('
              'SELECT id FROM feed_pending_candidates WHERE user_id=? AND source_id=? '
              'ORDER BY COALESCE(published_at,fetched_at) DESC,ordinal ASC,id DESC LIMIT 200)',(uid,sid,uid,sid))

def complete(c,job,entries,now,etag=None,modified=None):
    live=live_job(c,job,now)
    if not live: return 0
    s,p=live; uid=s['user_id']
    # Validators can advance only after fetched candidates are retained atomically.
    # A 304 has no new entries and drains this same durable queue under current fences.
    stage_candidates(c,s,entries,now)
    count=c.execute('SELECT COUNT(*) FROM feed_items WHERE user_id=? AND substr(created_at,1,10)=?',(uid,now[:10])).fetchone()[0]
    allowance=min(20-count,publication_allowance(c,s,p,now))
    pending=rows(c.execute('SELECT * FROM feed_pending_candidates WHERE user_id=? AND source_id=? '
                          'ORDER BY COALESCE(published_at,fetched_at) DESC,ordinal ASC,id DESC',(uid,s['id'])).fetchall())
    selected=[]
    for candidate in pending:
        entry=json.loads(candidate['payload'])
        if any(t.casefold() in (entry['title']+' '+entry['summary']).casefold() for t in p['excluded_topics']): continue
        existing=c.execute('SELECT id FROM feed_items WHERE user_id=? AND url=?',(uid,entry['url'])).fetchone()
        if existing:
            iid=existing[0]
            c.execute('INSERT OR IGNORE INTO feed_item_recommendations(user_id,item_id,source_id,bot_id,reason) VALUES(?,?,?,?,?)',
                      (uid,iid,s['id'],s['bot_id'],'来自你启用的订阅来源'))
            c.execute('DELETE FROM feed_pending_candidates WHERE user_id=? AND source_id=? AND id=?',(uid,s['id'],candidate['id']))
        elif len(selected)<allowance:
            selected.append((candidate,entry))
    # Select the newest first, then assign larger stable IDs to newer members.
    # Unknown dates fall back to fetch time plus original newest-first document order.
    for candidate,entry in reversed(selected):
        keys=('kind','title','url','author','published_at','summary','summary_basis','image_url','media_url','duration_seconds')
        iid=c.execute('INSERT INTO feed_items(user_id,source_id,created_at,'+','.join(keys)+') VALUES('+','.join('?'*13)+')',
                      (uid,s['id'],now,*(entry.get(k) for k in keys))).lastrowid
        c.execute('INSERT INTO feed_item_recommendations(user_id,item_id,source_id,bot_id,reason) VALUES(?,?,?,?,?)',
                  (uid,iid,s['id'],s['bot_id'],'来自你启用的订阅来源'))
        c.execute('DELETE FROM feed_pending_candidates WHERE user_id=? AND source_id=? AND id=?',(uid,s['id'],candidate['id']))
    next_at=(datetime.fromisoformat(now)+timedelta(hours=2)).isoformat()
    c.execute('UPDATE feed_sources SET last_success_at=?,next_fetch_at=?,failure_count=0,last_error=NULL,etag=?,modified=?,'
              'lease_token=NULL,lease_until=NULL WHERE user_id=? AND id=? AND lease_token=?',
              (now,next_at,etag or s['etag'],modified or s['modified'],uid,s['id'],job['lease_token']))
    return len(selected)

def fail(c,job,error,now):
    live=live_job(c,job,now)
    if not live: return
    s,_=live; failures=s['failure_count']+1
    next_at=(datetime.fromisoformat(now)+timedelta(seconds=min(86400,300*2**min(failures-1,9)))).isoformat()
    c.execute('UPDATE feed_sources SET failure_count=?,last_error=?,next_fetch_at=?,lease_token=NULL,lease_until=NULL '
              'WHERE user_id=? AND id=? AND lease_token=?',(failures,error[:200],next_at,s['user_id'],s['id'],job['lease_token']))

def memory_candidates(c,user_id,bots,now):
    enabled=c.execute('SELECT memory_enabled FROM users WHERE id=?',(user_id,)).fetchone()
    if not enabled or not enabled[0]: return []
    found={}
    for b in bots:
        if b['memory_access']=='none': continue
        scope="(scope='bot' AND bot_id=?)"
        if b['memory_access']=='bot_and_global': scope="(scope='global' OR (scope='bot' AND bot_id=?))"
        for r in rows(c.execute('SELECT id,content FROM memories WHERE user_id=? AND '+scope+
                 " AND status='active' AND sensitivity='normal' AND confirmed_at IS NOT NULL AND (expires_at IS NULL OR expires_at>?) "
                 'ORDER BY updated_at DESC LIMIT 100',(user_id,b['id'],now)).fetchall()): found[r['id']]=r
    return list(found.values())

def item(c,user_id,item_id):
    i=row(c.execute('SELECT i.*,s.name AS source_name,s.bot_id,b.name AS bot_name FROM feed_items i '
                   'JOIN feed_sources s ON s.id=i.source_id AND s.user_id=i.user_id '
                   'LEFT JOIN bots b ON b.id=s.bot_id AND b.user_id=i.user_id WHERE i.user_id=? AND i.id=?',(user_id,item_id)).fetchone())
    if not i: return None
    i.pop('user_id'); i['bot_id']=i['bot_id'] if i['bot_name'] is not None else None
    for key in ('read','saved','dismissed'): i[key]=bool(i[key])
    recs=rows(c.execute('SELECT r.bot_id,b.name AS bot_name,r.reason FROM feed_item_recommendations r '
                       'JOIN bots b ON b.id=r.bot_id AND b.user_id=r.user_id '
                       'WHERE r.user_id=? AND r.item_id=? ORDER BY r.source_id',(user_id,item_id)).fetchall())
    i['recommended_by']=list({r['bot_id']:r for r in recs}.values())
    i['recommendation_reason']='来自你启用的订阅来源'
    return i

def items(c,user_id,limit=20,cursor=None,kind=None,bot_id=None,saved_only=False):
    where=['i.user_id=?','i.dismissed=0']; params=[user_id]
    if cursor is not None: where.append('i.id<?'); params.append(cursor)
    if kind: where.append('i.kind=?'); params.append(kind)
    if saved_only: where.append('i.saved=1')
    else:
        where.append('EXISTS(SELECT 1 FROM feed_item_recommendations r JOIN feed_sources s ON s.id=r.source_id AND s.user_id=r.user_id '
                     'WHERE r.user_id=i.user_id AND r.item_id=i.id AND s.enabled=1 '
                     'AND (s.bot_id IS NULL OR EXISTS(SELECT 1 FROM bots b WHERE b.id=s.bot_id AND b.user_id=i.user_id)))')
    if bot_id is not None:
        where.append('EXISTS(SELECT 1 FROM feed_item_recommendations r JOIN bots b ON b.id=r.bot_id AND b.user_id=r.user_id '
                     'WHERE r.user_id=i.user_id AND r.item_id=i.id AND r.bot_id=?)'); params.append(bot_id)
    ids=[r[0] for r in c.execute('SELECT i.id FROM feed_items i WHERE '+' AND '.join(where)+' ORDER BY i.id DESC LIMIT ?',(*params,limit+1)).fetchall()]
    return dict(items=[item(c,user_id,iid) for iid in ids[:limit]],next_cursor=str(ids[limit-1]) if len(ids)>limit else None)

def state(c,user_id,item_id,fields):
    fields={k:int(v) for k,v in fields.items() if k in ('read','saved','dismissed') and v is not None}
    if fields:
        c.execute('UPDATE feed_items SET '+','.join(k+'=?' for k in fields)+' WHERE user_id=? AND id=?',(*fields.values(),user_id,item_id))
    return item(c,user_id,item_id)

def schema_ready(c):
    r=c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
    return r is not None and int(r[0])>=36
