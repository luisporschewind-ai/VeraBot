"""Isolated fixtures; importing this module never uses the user's database."""
import os
import tempfile
from pathlib import Path
ROOT = Path(tempfile.mkdtemp(prefix='vb_library_'))
os.environ['VERABOT_DB'] = str(ROOT / 'test.db')
os.environ['VERABOT_DATA_DIR'] = str(ROOT)
os.environ.setdefault('DEEPSEEK_API_KEY', 'test-not-used')
from fastapi.testclient import TestClient
from verabot import db
from verabot.main import app
from verabot.services.attachments import repo

def setup():
    from verabot.services.attachments import files
    # Exercise the real parser in process; parser subprocess limits have existing coverage.
    files.process_file = files._process_file
    db.init_db()
    from verabot.api.routers import bots as bot_routes
    async def no_model(*args, **kwargs): return None
    bot_routes._generate_opening_background = no_model
    client = TestClient(app)
    suffix = os.urandom(4).hex()
    def account(name):
        result = client.post('/api/auth/register', json={'username': name+suffix, 'password':'pw123456'}).json()
        return {'Authorization':'Bearer '+result['token']}, result['user']['id']
    headers, uid = account('alice')
    other_headers, other_uid = account('bob')
    bots = [client.post('/api/bots', headers=headers, json={'name':n}).json()['id'] for n in ['Alpha','Beta']]
    return client, headers, uid, other_headers, other_uid, bots

def attached(uid, bot, text=b'library original'):
    att = repo.create_file(uid, bot, text, 'report.txt')
    mid = db.add_message(uid, bot, 'user', 'document')
    repo.attach(uid, bot, [att['id']], mid)
    return att['id'], mid
