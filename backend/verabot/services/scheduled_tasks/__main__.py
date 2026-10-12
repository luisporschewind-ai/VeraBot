"""Run a separately supervised scheduler/worker; --once supports operational scans."""
import argparse
import asyncio
import logging
import signal
from uuid import uuid4
from ... import db
from ...db import scheduled_task_store
from . import scheduler, worker

log=logging.getLogger('verabot.scheduled_tasks')

async def main(once=False):
    with db.tx() as c:
        if scheduled_task_store.schema_version(c)<23:
            raise RuntimeError('Start the API once to apply schema v23 before starting this worker')
    owner=uuid4().hex
    if once:
        scheduler.tick()
        await worker.process_one(owner)
        return
    stop=asyncio.Event()
    loop=asyncio.get_running_loop()
    for sig in (signal.SIGTERM,signal.SIGINT):
        loop.add_signal_handler(sig,stop.set)
    async def schedule_loop():
        while True:
            try:
                scheduler.tick()
                worker.recover_expired()
            except Exception:
                log.exception('scheduled scan failed')
            await asyncio.sleep(30)
    async def worker_loop():
        while True:
            try: did=await worker.process_one(owner)
            except asyncio.CancelledError: raise
            except Exception:
                log.exception('scheduled worker failed')
                did=False
            if not did: await asyncio.sleep(1)
    children=[asyncio.create_task(schedule_loop()),asyncio.create_task(worker_loop())]
    try:
        await stop.wait()
    finally:
        for task in children: task.cancel()
        await asyncio.gather(*children,return_exceptions=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once',action='store_true',help='scan once and execute at most one queued run')
    args=parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    from ...core import log_redact
    log_redact.install()
    asyncio.run(main(args.once))
