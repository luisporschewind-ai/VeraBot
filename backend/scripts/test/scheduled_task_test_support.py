import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

TMP = tempfile.mkdtemp(prefix='vb_tasks_')
os.environ['VERABOT_DB'] = str(Path(TMP) / 'test.db')
os.environ['VERABOT_DATA_DIR'] = TMP
os.environ['VERABOT_SCHEDULER'] = '0'
os.environ['VERABOT_MEMORY_JOBS'] = '0'
os.environ.setdefault('DEEPSEEK_API_KEY', 'offline-not-used')
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verabot import db
NOW = datetime(2026, 10, 11, 1, 0, tzinfo=timezone.utc)

class DBTest(unittest.TestCase):
    def setUp(self):
        Path(os.environ['VERABOT_DB']).unlink(missing_ok=True)
        db.init_db()
        with db.tx() as c:
            for uid in (1, 2):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)", (uid, f'user{uid}', 'test', NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)", (uid,uid,f'bot{uid}',NOW.isoformat(),'["get_weather","list_reminders"]'))
    def payload(self, **kwargs):
        return dict(bot_id=1,title='日报',instruction='写一份简短总结',start_at='2026-10-11T09:01:00+08:00',timezone='Asia/Shanghai',repeat='daily', **kwargs)
