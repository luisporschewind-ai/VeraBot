#!/usr/bin/env bash
# 打包后端交付件：dist/VeraBot-backend-v<版本>.zip
# 只包含 backend/ 下受控文件；排除 .venv、.env、数据库 / 日志 / JWT 密钥、缓存与测试结果。
# 用法：scripts/package_backend.sh          （版本号取自 backend/verabot/__init__.py）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' backend/verabot/__init__.py)"
NAME="VeraBot-backend-v$VERSION"
mkdir -p dist
OUT="dist/$NAME.zip"
rm -f "$OUT"
python3 - "$ROOT/backend" "$OUT" "$NAME" <<'PYEOF'
import os, sys, zipfile, fnmatch
src, out, top = sys.argv[1], sys.argv[2], sys.argv[3]
EXCL_DIRS = {".venv", "__pycache__", ".pytest_cache", ".ruff_cache", "results", "models"}
EXCL_FILES = [".env", "*.db", "*.db-*", "*.log", "*.pid", ".jwt_secret", ".DS_Store", "._*", "*.pyc"]
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dp, dns, fns in os.walk(src):
        dns[:] = sorted(d for d in dns if d not in EXCL_DIRS)
        for f in sorted(fns):
            if any(fnmatch.fnmatch(f, p) for p in EXCL_FILES):
                continue
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, src)
            zi = zipfile.ZipInfo.from_file(full, os.path.join(top, rel))
            zi.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as fh:
                z.writestr(zi, fh.read())   # ZipInfo.from_file 保留可执行权限 (start.sh / start.command)
            n += 1
print(f"[package] {n} 个文件 → {out}")
PYEOF
( cd dist && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" )
ls -l "$OUT"
