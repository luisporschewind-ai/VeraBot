"""Correct checksums for existing TXT bytes converted by the old shared-key parser.

Only metadata changes: preserve the existing server file and record the former digest.
New uploads have separate original/extraction keys and never enter this repair.
"""
import hashlib
import json

def migrate(c,ver):
    if ver>=34: return
    from ...services.attachments.store import get_store
    from ..library_store import changed
    for row in c.execute('SELECT id,user_id,payload FROM library_items WHERE deleted=0').fetchall():
        item_id, user_id, payload_raw = row
        payload=json.loads(payload_raw)
        if payload.get('kind')!='file' or payload.get('extension')!='txt' or payload.get('storage_key')!=payload.get('text_key'): continue
        path=get_store().path(payload['storage_key'])
        if path is None: continue
        digest=hashlib.sha256()
        with path.open('rb') as source:
            for block in iter(lambda:source.read(1024*1024),b''): digest.update(block)
        size=path.stat().st_size;checksum=digest.hexdigest()
        if size==payload['bytes'] and checksum==payload['sha256']: continue
        payload.update(previous_original_sha256=payload['sha256'],previous_original_bytes=payload['bytes'],original_status='legacy_converted_text',bytes=size,sha256=checksum,text_bytes=0)
        c.execute('UPDATE library_items SET payload=? WHERE id=? AND user_id=?',(json.dumps(payload),item_id,user_id))
        c.execute('UPDATE attachments SET bytes=?,sha256=?,text_bytes=0 WHERE id=? AND user_id=?',(size,checksum,item_id,user_id))
        changed(c,user_id,item_id)
