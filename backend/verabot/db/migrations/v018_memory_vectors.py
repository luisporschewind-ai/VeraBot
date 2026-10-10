"""v17 → v18：M5 本地记忆向量缓存。"""


def migrate(c, ver: int) -> None:
    c.execute("""CREATE TABLE IF NOT EXISTS memory_vectors (
        memory_id INTEGER PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        model TEXT NOT NULL,
        dim INTEGER NOT NULL CHECK(dim > 0),
        content_hash TEXT NOT NULL,
        vector BLOB NOT NULL CHECK(length(vector) = dim * 4),
        updated_at TEXT NOT NULL
    )""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_mem_vectors_user_model ON memory_vectors(user_id, model)")
