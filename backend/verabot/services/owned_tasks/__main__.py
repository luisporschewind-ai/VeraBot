import argparse,asyncio,uuid
from ... import db
from .worker import process_one
async def main(once=False):
 owner=uuid.uuid4().hex
 with db.tx() as c:
  if __import__('verabot.db.owned_task_store',fromlist=['schema_version']).schema_version(c)<29:raise RuntimeError('先由 API 在备份后的数据库应用迁移')
 if once:await process_one(owner);return
 while True:
  if not await process_one(owner):await asyncio.sleep(1)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--once',action='store_true');asyncio.run(main(p.parse_args().once))
