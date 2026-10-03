"""兼容旧路径：附件表 DDL 已移到 db/migrations/v012_attachments.py。新代码请从那里导入。"""
from .migrations.v012_attachments import ATTACHMENT_SCHEMA, migrate_attachments  # noqa: F401
