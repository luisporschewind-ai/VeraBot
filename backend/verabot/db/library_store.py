"""Independent, account-scoped library metadata; caller owns transactions."""
import json
from .database import now_iso

def revision(c, user_id):
    return c.execute('SELECT COALESCE(MAX(id),0) FROM library_changes WHERE user_id=?', (user_id,)).fetchone()[0]

def changed(c, user_id, item_id):
    rev = c.execute('INSERT INTO library_changes(user_id,item_id) VALUES (?,?)', (user_id,item_id)).lastrowid
    c.execute('UPDATE library_items SET revision=? WHERE id=? AND user_id=?', (rev,item_id,user_id))
    return rev

def ingest(c, row, source_kind, source_id, bot_id, explicit=False):
    row = dict(row); uid = row['user_id']; aid = row['id']
    existing = c.execute('SELECT deleted FROM library_items WHERE id=? AND user_id=?', (aid,uid)).fetchone()
    if existing and existing[0]: return aid
    inserted = c.execute('INSERT OR IGNORE INTO library_items(id,user_id,payload,created_at) VALUES (?,?,?,?)',
        (aid,uid,json.dumps(row),row['created_at'])).rowcount
    name = None
    if bot_id is not None:
        bot = c.execute('SELECT name FROM bots WHERE id=? AND user_id=?',(bot_id,uid)).fetchone()
        name = bot[0] if bot else '已删除的 Bot'
    elif source_kind == 'group':
        group = c.execute('SELECT name FROM chat_groups WHERE id=? AND user_id=?',(source_id,uid)).fetchone()
        name = group[0] if group else '群聊'
    source_key = f'{source_kind}:{source_id}:{row.get("message_id") or 0}'
    added = c.execute('INSERT OR IGNORE INTO library_sources(item_id,user_id,source_key,kind,source_id,bot_id,display_name,message_id,created_at) VALUES (?,?,?,?,?,?,?,?,?)',
        (aid,uid,source_key,source_kind,source_id,bot_id,name or '直接上传',row.get('message_id'),row['created_at'])).rowcount
    linked = 0
    if bot_id is not None:
        blocked = c.execute('SELECT 1 FROM library_unlinked WHERE user_id=? AND item_id=? AND bot_id=?',(uid,aid,bot_id)).fetchone()
        if explicit or not blocked:
            if explicit: c.execute('DELETE FROM library_unlinked WHERE user_id=? AND item_id=? AND bot_id=?',(uid,aid,bot_id))
            linked = c.execute('INSERT OR IGNORE INTO library_bot_links(user_id,item_id,bot_id,version) VALUES (?,?,?,?)',(uid,aid,bot_id,revision(c,uid)+1)).rowcount
    if inserted or added or linked: changed(c,uid,aid)
    return aid

def live_resource_keys(c):
    keys = set()
    for row in c.execute('SELECT payload FROM library_items WHERE deleted=0'):
        item = json.loads(row[0])
        keys.update(item.get(k) for k in ('storage_key','thumb_key','text_key') if item.get(k))
        key = item.get('storage_key','')
        if key.endswith('.gif'): keys.add(key[:-4]+'_still.jpg')
    return keys
