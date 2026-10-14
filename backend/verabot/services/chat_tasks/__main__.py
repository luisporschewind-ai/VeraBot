import argparse
import asyncio
from ... import db
from .worker import process_one,loop
parser=argparse.ArgumentParser(description='Detached private chat worker (same persistent VERABOT_DB as API)')
parser.add_argument('--once',action='store_true')
args=parser.parse_args()
db.init_db()
asyncio.run(process_one() if args.once else loop())
