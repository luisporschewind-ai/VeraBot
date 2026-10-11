#!/usr/bin/env python3
"""G3 local HTTP/Simulator demo. Temporary data; deterministic provider only."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port', type=int, default=8093)
parser.add_argument('--data-dir', default=None)
parser.add_argument('--delay', type=float, default=0.18, help='Seconds per delta (0.05-2), for UI stop acceptance')
args = parser.parse_args()
if not 0.05 <= args.delay <= 2:
    parser.error("--delay must be between 0.05 and 2")
data = Path(args.data_dir or tempfile.mkdtemp(prefix='vb_group_g3_')).resolve()
data.mkdir(parents=True, exist_ok=True)
os.environ['VERABOT_DB'] = str(data / 'demo.db')
os.environ['VERABOT_DATA_DIR'] = str(data)
os.environ['VERABOT_MEMORY_JOBS'] = '0'
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from fastapi.testclient import TestClient
from verabot import db
from verabot.main import app
from verabot.services import llm
import uvicorn

db.init_db()
client = TestClient(app)
credentials = {'username': 'group-demo', 'password': 'group-demo-123'}
auth = client.post('/api/auth/register', json=credentials)
if auth.status_code != 200:
    auth = client.post('/api/auth/login', json=credentials)
auth.raise_for_status()
headers = {'Authorization': 'Bearer ' + auth.json()['token']}
bots = client.get('/api/bots', headers=headers).json()['bots']
if not bots:
    for name, persona in [('A', '善于提出方案'), ('B', '善于提出不同观点'), ('C', '善于总结')]:
        client.post('/api/bots', headers=headers, json={'name': name, 'persona': persona}).raise_for_status()
failed = set()

async def simulated_provider(messages, tools, **kwargs):
    # Never delegates to the original provider, regardless of server configuration.
    identity = json.loads(messages[1]['content'])['current']
    name = identity['name']
    question = next((json.loads(m['content'])['text'] for m in reversed(messages[2:])
                     if json.loads(m['content'])['source']['role'] == 'user'), '')
    key = (name, question)
    with (data / 'provider-calls.jsonl').open('a') as f:
        f.write(json.dumps({'name': name, 'messages': messages, 'tools': tools,
                            'max_tokens': kwargs.get('max_tokens')}, ensure_ascii=False) + '\n')
    if '[fail-once]' in question and name == 'B' and key not in failed:
        failed.add(key)
        raise llm.LLMError('G3 deterministic failure')
    answer = f'【模拟回复】我是 {name}。我已阅读本群可见的讨论。这个测试用于检查流式消息、顺序发言和停止操作。'
    for start in range(0, len(answer), 3):
        await asyncio.sleep(args.delay)
        yield 'delta', answer[start:start+3]
    yield 'usage', {'prompt_tokens': 2, 'completion_tokens': 3, 'total_tokens': 5}
    yield 'finish', 'stop'

llm.stream_chat = simulated_provider
print(f'G3 demo: http://127.0.0.1:{args.port}; data={data}; login=group-demo / group-demo-123', flush=True)
uvicorn.run(app, host='127.0.0.1', port=args.port, log_level='warning')
