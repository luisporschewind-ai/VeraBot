"""Claim → fetch outside transaction → fenced atomic publish. Safe across restarts."""
import json
import subprocess
import sys
from ... import db
from ...db import feed_store as store
from ...db.database import now_iso

def collect_bounded(source):
    payload={key:source.get(key) for key in ('url','kind','etag','modified')}
    completed=subprocess.run([sys.executable,'-m','verabot.services.feed.collector'],
        input=json.dumps(payload),text=True,capture_output=True,timeout=40,check=False)
    if completed.returncode: raise ValueError('source collection failed')
    return json.loads(completed.stdout)

def process_one(collect=collect_bounded,clock=now_iso):
    with db.tx(immediate=True) as c: job=store.claim(c,clock(),lease_seconds=120)
    if not job: return False
    try:
        result=collect(job)
    except Exception as exc:
        with db.tx(immediate=True) as c: store.fail(c,job,'采集失败（'+type(exc).__name__+'）',clock())
    else:
        with db.tx(immediate=True) as c:
            store.complete(c,job,result['entries'],clock(),etag=result.get('etag'),modified=result.get('modified'))
    return True
