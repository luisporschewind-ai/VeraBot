"""Library lifetime and access rules. Account ownership is distinct from Bot access."""
import json
from .. import db
from ..db import library_store as sql
from .attachments import repo

class LibraryError(Exception):
    def __init__(self,status,message,code='library_error'):
        self.status,self.message,self.code=status,message,code
        super().__init__(message)

def ingest_attachment(c, *, user_id, attachment_id, source_kind, source_id, bot_id, explicit=False):
    row = c.execute('SELECT * FROM attachments WHERE id=? AND user_id=? AND status=\'attached\'',(attachment_id,user_id)).fetchone()
    if not row: raise LibraryError(404,'资料不存在')
    return sql.ingest(c, row, source_kind, source_id, bot_id, explicit)

def raw_item(c,user_id,item_id,include_deleted=False):
    row = c.execute('SELECT * FROM library_items WHERE user_id=? AND id=?',(user_id,item_id)).fetchone()
    if not row or (row['deleted'] and not include_deleted): raise LibraryError(404,'资料不存在','library_not_found')
    return dict(row)

def get_item(user_id,item_id):
    with db.tx() as c:
        row = raw_item(c,user_id,item_id)
        data = json.loads(row['payload'])
        links = [r[0] for r in c.execute('SELECT bot_id FROM library_bot_links WHERE user_id=? AND item_id=? ORDER BY bot_id',(user_id,item_id))]
        sources = []
        for source in c.execute('SELECT * FROM library_sources WHERE user_id=? AND item_id=? ORDER BY created_at',(user_id,item_id)):
            s=dict(source); table='messages' if s['kind']=='private' else 'chat_group_messages'
            s['message_available'] = bool(s['message_id'] and s['kind']!='upload' and c.execute(f'SELECT 1 FROM {table} WHERE user_id=? AND id=?',(user_id,s['message_id'])).fetchone())
            sources.append(s)
    return dict(id=item_id,kind=data['kind'],name=data.get('filename') or '图片',mime=data['mime'],bytes=data['bytes'],
        sha256=data['sha256'],resource_version=data['sha256'],created_at=row['created_at'],revision=row['revision'],
        availability='available' if repo.get_store().exists(data['storage_key']) else 'missing',text_status=data.get('text_status'),
        bot_ids=links,sources=sources)

def link_bot(user_id,item_id,bot_id):
    with db.tx(immediate=True) as c:
        raw_item(c,user_id,item_id)
        if not c.execute('SELECT 1 FROM bots WHERE id=? AND user_id=?',(bot_id,user_id)).fetchone(): raise LibraryError(404,'Bot 不存在')
        c.execute('DELETE FROM library_unlinked WHERE user_id=? AND item_id=? AND bot_id=?',(user_id,item_id,bot_id))
        if c.execute('INSERT OR IGNORE INTO library_bot_links(user_id,item_id,bot_id,version) VALUES (?,?,?,?)',(user_id,item_id,bot_id,sql.revision(c,user_id)+1)).rowcount:
            sql.changed(c,user_id,item_id)

def unlink_bot(user_id,item_id,bot_id):
    with db.tx(immediate=True) as c:
        raw_item(c,user_id,item_id)
        c.execute('DELETE FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',(user_id,item_id,bot_id))
        c.execute('INSERT OR IGNORE INTO library_unlinked VALUES (?,?,?)',(user_id,item_id,bot_id))
        sql.changed(c,user_id,item_id)

def delete_item(user_id,item_id):
    with db.tx(immediate=True) as c:
        row=raw_item(c,user_id,item_id,include_deleted=True)
        if row['deleted']: return
        c.execute('UPDATE library_items SET deleted=1 WHERE user_id=? AND id=?',(user_id,item_id))
        c.execute('DELETE FROM library_bot_links WHERE user_id=? AND item_id=?',(user_id,item_id))
        sql.changed(c,user_id,item_id)
        data=json.loads(row['payload'])
    repo.delete_files(repo.file_keys(data))

def authorize_bot(user_id,bot_id,item_id):
    with db.tx() as c:
        raw_item(c,user_id,item_id)
        row=c.execute('SELECT version FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',(user_id,item_id,bot_id)).fetchone()
        if not row: raise LibraryError(404,'资料不存在','library_not_found')
        return row[0]

def catalog(user_id, *, kind=None, bot_id=None, q='', cursor=None, limit=50):
    import base64
    query=(kind,bot_id,q,limit)
    with db.tx() as c:
        rev=sql.revision(c,user_id); offset=0
        if cursor:
            try:
                saved=json.loads(base64.urlsafe_b64decode(cursor))
                if saved['u']!=user_id or saved['q']!=list(query): raise ValueError()
                offset=int(saved['o'])
                if saved['r']!=rev: raise LibraryError(409,'资料已更新，请重新同步','library_revision_changed')
            except LibraryError: raise
            except Exception: raise LibraryError(400,'无效分页游标','library_invalid_cursor')
        rows=c.execute('SELECT id,payload FROM library_items WHERE user_id=? AND deleted=0 ORDER BY created_at DESC,id DESC',(user_id,)).fetchall()
        selected=[]
        for row in rows:
            data=json.loads(row['payload'])
            if kind and data['kind']!=kind: continue
            if bot_id is not None and not c.execute('SELECT 1 FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',(user_id,row['id'],bot_id)).fetchone(): continue
            if q:
                text=data.get('filename','') or ''
                path=repo.get_store().path(data.get('text_key')) if data.get('text_key') else None
                if path: text+='\n'+path.read_text(encoding='utf-8',errors='replace')
                text+='\n'+(data.get('caption') or '')
                if q.casefold() not in text.casefold(): continue
            selected.append(row['id'])
        ids=selected[offset:offset+limit]
        next_cursor=base64.urlsafe_b64encode(json.dumps(dict(u=user_id,r=rev,o=offset+limit,q=query)).encode()).decode() if offset+limit<len(selected) else None
    items=[get_item(user_id,aid) for aid in ids]
    with db.tx() as c:
        if sql.revision(c,user_id)!=rev: raise LibraryError(409,'资料已更新，请重新同步','library_revision_changed')
    return dict(items=items,next_cursor=next_cursor,snapshot_revision=rev)

def changes(user_id,after_revision):
    with db.tx() as c:
        revision=sql.revision(c,user_id)
        rows=c.execute('SELECT DISTINCT item_id FROM library_changes WHERE user_id=? AND id>? AND id<=?',(user_id,after_revision,revision)).fetchall()
        live=[]; removed=[]
        for row in rows:
            item=raw_item(c,user_id,row[0],True)
            (removed if item['deleted'] else live).append(row[0])
    result=dict(upserts=[get_item(user_id,aid) for aid in live],removed_ids=removed,next_cursor=None,through_revision=revision)
    with db.tx() as c:
        if sql.revision(c,user_id)!=revision: raise LibraryError(409,'资料已更新，请重新同步','library_revision_changed')
    return result

def upload(user_id,data,filename,mime,request_key,bot_id=None):
    if not request_key or len(request_key)>200: raise LibraryError(400,'缺少有效上传请求标识')
    if bot_id is not None and not db.get_bot(user_id,bot_id): raise LibraryError(404,'Bot 不存在')
    with db.tx() as c:
        previous=c.execute('SELECT item_id FROM library_upload_keys WHERE user_id=? AND request_key=?',(user_id,request_key)).fetchone()
    if previous: return get_item(user_id,previous[0])
    att=repo.create(user_id,None,data) if mime.startswith('image/') else repo.create_file(user_id,None,data,filename)
    try:
        with db.tx(immediate=True) as c:
            previous=c.execute('SELECT item_id FROM library_upload_keys WHERE user_id=? AND request_key=?',(user_id,request_key)).fetchone()
            if previous: aid=previous[0]
            else:
                aid=att['id']
                c.execute("UPDATE attachments SET status='attached',expires_at=NULL WHERE id=? AND user_id=?",(aid,user_id))
                ingest_attachment(c,user_id=user_id,attachment_id=aid,source_kind='upload',source_id=None,bot_id=bot_id,explicit=True)
                c.execute('INSERT INTO library_upload_keys VALUES (?,?,?)',(user_id,request_key,aid))
        if aid!=att['id']: repo.delete_pending(user_id,att['id'])
    except Exception:
        if repo.get(user_id,att['id']) and repo.get(user_id,att['id'])['status']=='pending': repo.delete_pending(user_id,att['id'])
        raise
    return get_item(user_id,aid)

def content_row(user_id,item_id):
    with db.tx() as c: return json.loads(raw_item(c,user_id,item_id)['payload'])

def assert_authorization(user_id,bot_id,item_id,version):
    if authorize_bot(user_id,bot_id,item_id)!=version: raise LibraryError(404,'资料访问权限已变更')

def bot_can_read(user_id,bot_id,item_id):
    try: authorize_bot(user_id,bot_id,item_id);return True
    except LibraryError: return False
