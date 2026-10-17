"""Run independently: python -m verabot.services.feed [--once]. Never migrates a DB."""
from ...core.envfile import load_env_file
load_env_file()
import argparse
import logging
import signal
import threading
from ... import db
from ...db import feed_store
from .worker import process_one

def main(once=False):
    with db.tx() as c:
        if not feed_store.schema_ready(c): raise RuntimeError('Feed requires reviewed schema v36; worker will not migrate the database')
    if once: return process_one()
    stop=threading.Event()
    for sig in (signal.SIGINT,signal.SIGTERM): signal.signal(sig,lambda *_:stop.set())
    while not stop.is_set():
        try: did=process_one()
        except Exception:
            logging.getLogger('verabot.feed').exception('Feed worker iteration failed')
            did=False
        if not did: stop.wait(2)

if __name__=='__main__':
    args=argparse.ArgumentParser(description=__doc__)
    args.add_argument('--once',action='store_true')
    main(args.parse_args().once)
