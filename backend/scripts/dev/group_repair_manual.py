#!/usr/bin/env python3
"""Run repaired group chat against an isolated local copy, with the configured real provider."""
import argparse
import asyncio
import os
from pathlib import Path
import shutil
import sqlite3
import sys

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-dir',required=True)
parser.add_argument('--source-data',required=True)
parser.add_argument('--port',type=int,default=8094)
args=parser.parse_args()
source=Path(args.source_data).resolve()
data=Path(args.data_dir).resolve()
if data == source or source in data.parents:
    parser.error('the manual data directory must be separate from the source database')
data.mkdir(parents=True,exist_ok=True)
destination=data/'verabot.db'
if not destination.exists():
    with sqlite3.connect('file:'+str(source/'verabot.db')+'?mode=ro',uri=True) as original:
        with sqlite3.connect(destination) as replica:original.backup(replica)
    if (source/'attachments').exists():shutil.copytree(source/'attachments',data/'attachments',dirs_exist_ok=True)
    if (source/'.jwt_secret').exists():shutil.copy2(source/'.jwt_secret',data/'.jwt_secret')
os.environ['VERABOT_DB']=str(destination)
os.environ['VERABOT_DATA_DIR']=str(data)
os.environ['VERABOT_ATTACHMENTS_DIR']=str(data/'attachments')
os.environ['VERABOT_MEMORY_JOBS']='0'
os.environ['VERABOT_MEMORY_VECTOR']='0'
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot.main import app
from verabot.services.reminders import scheduler
from verabot.core.config import DEEPSEEK_API_KEY
import uvicorn

async def idle_reminders():
    await asyncio.Event().wait()
# Background reminder side effects are irrelevant to the user's group-chat acceptance.
scheduler.loop=idle_reminders
print(f'Group repair manual server http://127.0.0.1:{args.port}; isolated database; provider configured={bool(DEEPSEEK_API_KEY)}',flush=True)
uvicorn.run(app,host='127.0.0.1',port=args.port,log_level='warning')
