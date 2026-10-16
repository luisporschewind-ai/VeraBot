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


def item_row(c, user_id, item_id):
    return c.execute('SELECT * FROM library_items WHERE user_id=? AND id=?', (user_id, item_id)).fetchone()


def bot_ids_for_item(c, user_id, item_id):
    return [r[0] for r in c.execute(
        'SELECT bot_id FROM library_bot_links WHERE user_id=? AND item_id=? ORDER BY bot_id',
        (user_id, item_id))]


def sources_for_item(c, user_id, item_id):
    return c.execute(
        'SELECT * FROM library_sources WHERE user_id=? AND item_id=? ORDER BY created_at',
        (user_id, item_id))


def source_message_exists(c, kind, user_id, message_id):
    table = 'messages' if kind == 'private' else 'chat_group_messages'
    return c.execute(f'SELECT 1 FROM {table} WHERE user_id=? AND id=?', (user_id, message_id)).fetchone()


def clear_unlinked(c, user_id, item_id, bot_id):
    c.execute('DELETE FROM library_unlinked WHERE user_id=? AND item_id=? AND bot_id=?',
              (user_id, item_id, bot_id))


def try_link_bot(c, user_id, item_id, bot_id):
    return c.execute(
        'INSERT OR IGNORE INTO library_bot_links(user_id,item_id,bot_id,version) VALUES (?,?,?,?)',
        (user_id, item_id, bot_id, revision(c, user_id) + 1)).rowcount


def unlink_bot(c, user_id, item_id, bot_id):
    c.execute('DELETE FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',
              (user_id, item_id, bot_id))
    c.execute('INSERT OR IGNORE INTO library_unlinked VALUES (?,?,?)', (user_id, item_id, bot_id))


def soft_delete_item(c, user_id, item_id):
    c.execute('UPDATE library_items SET deleted=1 WHERE user_id=? AND id=?', (user_id, item_id))
    c.execute('DELETE FROM library_bot_links WHERE user_id=? AND item_id=?', (user_id, item_id))


def link_version(c, user_id, item_id, bot_id):
    row = c.execute(
        'SELECT version FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',
        (user_id, item_id, bot_id)).fetchone()
    return row[0] if row else None


def live_item_id_payloads(c, user_id):
    return c.execute(
        'SELECT id,payload FROM library_items WHERE user_id=? AND deleted=0 ORDER BY created_at DESC,id DESC',
        (user_id,)).fetchall()


def has_bot_link(c, user_id, item_id, bot_id):
    return bool(c.execute(
        'SELECT 1 FROM library_bot_links WHERE user_id=? AND item_id=? AND bot_id=?',
        (user_id, item_id, bot_id)).fetchone())


def bot_has_any_link(c, user_id, bot_id):
    return c.execute(
        'SELECT 1 FROM library_bot_links WHERE user_id=? AND bot_id=? LIMIT 1',
        (user_id, bot_id)).fetchone()


def changed_item_ids(c, user_id, after_revision, through_revision):
    return c.execute(
        'SELECT DISTINCT item_id FROM library_changes WHERE user_id=? AND id>? AND id<=?',
        (user_id, after_revision, through_revision)).fetchall()


def upload_key_item_id(c, user_id, request_key):
    return c.execute(
        'SELECT item_id FROM library_upload_keys WHERE user_id=? AND request_key=?',
        (user_id, request_key)).fetchone()


def insert_upload_key(c, user_id, request_key, item_id):
    c.execute('INSERT INTO library_upload_keys VALUES (?,?,?)', (user_id, request_key, item_id))


def item_payload_deleted(c, user_id, item_id):
    return c.execute(
        'SELECT payload,deleted FROM library_items WHERE id=? AND user_id=?',
        (item_id, user_id)).fetchone()


def sync_caption_to_item(c, user_id, item_id, caption, status):
    saved = c.execute(
        'SELECT payload FROM library_items WHERE id=? AND user_id=? AND deleted=0',
        (item_id, user_id)).fetchone()
    if saved:
        payload = json.loads(saved[0])
        payload.update(caption=caption, caption_status=status)
        c.execute('UPDATE library_items SET payload=? WHERE id=? AND user_id=?',
                  (json.dumps(payload), item_id, user_id))
        changed(c, user_id, item_id)
