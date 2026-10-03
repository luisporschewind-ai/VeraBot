"""附件文件存储：薄接口 AttachmentStore + 本地磁盘实现 LocalStore。

- 根目录 ATTACHMENTS_DIR；路径 u<user_id>/<id 前 2 位>/att_<id>.<ext>（storage_key 是相对路径）。
- 目录 0700、文件 0600；写入 tmp/ → fsync → os.replace（原子），失败不留半个文件。
- 读取前 resolve()，必须仍在根目录内（防路径穿越）；storage_key 只由服务端生成。
- 以后换对象存储只需另写一个实现，表里的 storage_backend 区分。
"""
from __future__ import annotations

import os
import shutil
import uuid
from pathlib import Path
from typing import Protocol

from ...core.config import ATTACHMENTS_DIR


class AttachmentStore(Protocol):
    backend: str

    def put(self, key: str, data: bytes) -> None: ...
    def path(self, key: str) -> Path | None: ...
    def delete(self, key: str) -> None: ...
    def exists(self, key: str) -> bool: ...


class LocalStore:
    backend = "local"

    def __init__(self, root: Path):
        self.root = Path(root)

    # ---- 目录 ----
    def _ensure_dir(self, d: Path):
        d.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass

    @property
    def tmp_dir(self) -> Path:
        return self.root / "tmp"

    def ensure_root(self):
        self._ensure_dir(self.root)
        self._ensure_dir(self.tmp_dir)

    def clear_tmp(self):
        """启动时清空上传中途留下的临时文件。"""
        if self.tmp_dir.exists():
            shutil.rmtree(self.tmp_dir, ignore_errors=True)
        self.ensure_root()

    # ---- 路径安全 ----
    def resolve(self, key: str) -> Path | None:
        if not key or key.startswith("/") or "\\" in key or ".." in key.split("/"):
            return None
        root = self.root.resolve()
        p = (root / key).resolve()
        try:
            p.relative_to(root)
        except ValueError:
            return None
        if p == root or p.parent == root / "tmp" or root / "tmp" in p.parents:
            return None
        return p

    # ---- 接口 ----
    def put(self, key: str, data: bytes) -> None:
        dest = self.resolve(key)
        if dest is None:
            raise ValueError("bad storage key")
        self.ensure_root()
        self._ensure_dir(dest.parent)
        tmp = self.tmp_dir / f"{uuid.uuid4().hex}.part"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, dest)
        except BaseException:
            try:
                tmp.unlink()
            except OSError:
                pass
            raise

    def path(self, key: str) -> Path | None:
        p = self.resolve(key)
        return p if p is not None and p.is_file() else None

    def exists(self, key: str) -> bool:
        return self.path(key) is not None

    def delete(self, key: str) -> None:
        p = self.resolve(key)
        if p is None:
            return
        try:
            p.unlink()
        except FileNotFoundError:
            pass

    def iter_keys(self):
        """磁盘上所有附件文件（相对 key 与修改时间），对账用。跳过 tmp/。"""
        if not self.root.exists():
            return
        for p in self.root.rglob("att_*"):
            if not p.is_file() or self.tmp_dir in p.parents:
                continue
            yield p.relative_to(self.root).as_posix(), p.stat().st_mtime


_store: LocalStore | None = None


def get_store() -> LocalStore:
    """进程内单例。测试可通过 VERABOT_ATTACHMENTS_DIR / VERABOT_DATA_DIR 指到临时目录。"""
    global _store
    if _store is None:
        _store = LocalStore(ATTACHMENTS_DIR)
    return _store
