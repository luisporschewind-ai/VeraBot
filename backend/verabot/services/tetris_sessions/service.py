"""Short transactional session operations; independent worker does all simulation."""
import time
from ...db.database import tx
from ...db import tetris_session_store as store

def create(user_id,body):
    with tx(immediate=True) as c:return store.create_handoff(c,user_id,body,time.time())
def command(user_id,session_id,body):
    with tx(immediate=True) as c:return store.apply_command(c,user_id,session_id,body,time.time())
def get(user_id,session_id,after_event_sequence=None):
    with tx() as c:
        if not c.in_transaction:c.execute('BEGIN')
        return store.get_session(c,user_id,session_id,after_event_sequence)
def operation(user_id,request_id):
    with tx() as c:return store.get_operation(c,user_id,request_id)
def capabilities():
    with tx() as c:return store.capabilities(c,time.time())

def current(user_id):
    with tx() as c:
        if not c.in_transaction:c.execute('BEGIN')
        return dict(session=store.get_current(c,user_id))
