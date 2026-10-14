from ... import db
from ...db import chat_reply_store as store
from ..attachments import repo as attachments

def submit(uid,bid,payload):
    # Replay first: attachments may already be bound and budget may have changed.
    with db.tx() as c:old=store.receipt(c,uid,bid,payload['client_request_id'])
    if not old:
        used,budget=db.token_budget(uid)
        if used>=budget:raise store.ChatTaskError(429,'budget_exhausted','今日额度已用完')
        attachments.check_pending(uid,bid,payload.get('attachment_ids',[]))
    with db.tx(immediate=True) as c:return store.accept(c,uid,bid,payload)
