"""python -m verabot.services.tetris_sessions [--once | --status].
Does not start API/chat workers, initialize a database, or require provider keys.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import time
from uuid import uuid4
from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parents[3]/'.env',override=False)
from ...core.config import DB_PATH
from ...db.database import tx
from ...db import tetris_session_store as store
from .contracts import RULE_VERSION,FIXTURE_SHA256
from .worker import Worker

def emit(value):print(json.dumps(value,separators=(',',':')),flush=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--once',action='store_true');mode.add_argument('--status',action='store_true')
    args=parser.parse_args()
    if not DB_PATH.is_file():
        emit(dict(schemaReady=False,workerReady=False,ruleVersion=RULE_VERSION,fixtureSHA256=FIXTURE_SHA256,error='database missing; apply reviewed migrations first'))
        return 1
    try:
        with tx() as c:
            status=store.capabilities(c,time.time())
            status['schemaReady']=True
            status['waiting']=c.execute("SELECT count(*) FROM tetris_sessions WHERE controller='bot' AND run_state IN ('running','reclaimPending')").fetchone()[0]
    except Exception:
        emit(dict(schemaReady=False,workerReady=False,ruleVersion=RULE_VERSION,fixtureSHA256=FIXTURE_SHA256,error='session schema unavailable'))
        return 1
    if args.status:emit(status);return 0
    subject=Worker(owner=f'{os.getpid()}:{uuid4()}')
    stopping=False
    def stop(signum,frame):
        nonlocal stopping
        stopping=True
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    emit(dict(event='tetris_worker_started',pid=os.getpid(),ruleVersion=RULE_VERSION,fixtureSHA256=FIXTURE_SHA256))
    exit_code=0
    try:
        while not stopping:
            start=time.monotonic();result=subject.tick()
            if result.published or result.errors or result.rejected:
                samples=sorted(result.latenessMs)
                emit(dict(event='tetris_tick',published=len(result.published),errors=result.errors,errorKinds=result.errorKinds,rejected=result.rejected,latenessMaxMs=round(max(samples,default=0),3),latenessMs=[round(value,3) for value in samples],planningQueue=len(subject.jobs)))
            if args.once:
                exit_code=int(result.errors>0);break
            # Scan more often than the 100ms logical batch so due times are
            # not quantized to a second 100ms wait after DB/API jitter.
            time.sleep(max(0,.02-(time.monotonic()-start)))
    finally:
        subject.close()
        emit(dict(event='tetris_worker_stopped',pid=os.getpid()))
    return exit_code

if __name__=='__main__':raise SystemExit(main())
