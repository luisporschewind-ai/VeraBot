#!/usr/bin/env python3
"""SQL 分层检查（SQL-LAYER-*）：SQL 只允许写在 verabot/db/ 里（*_store.py / repository.py / migrations/）。

静态扫描（AST，不导入、不连库）verabot/ 下 db/ 以外的模块：
  SQL-LAYER-01  不出现 .execute( / .executemany( / .executescript( 调用
  SQL-LAYER-02  不出现以 SQL 语句开头的字符串常量（SELECT / INSERT / UPDATE … SET / DELETE FROM / CREATE / DROP / ALTER / PRAGMA）
确实需要例外时把（相对 verabot/ 的路径, 函数名）加进 ALLOW，并在 PR 里说明原因。

PR #31 新模块（ENFORCE）里出现 SQL 会使检查失败。更早留在 db/ 以外的 SQL
（主要是 services/memory/、bots 路由、actions、mcp oauth）只打印为 known，不失败。
搬迁记录见 docs/testing/2026-10-14-known-issues.md。
用法：python scripts/test/sql_layer_check.py   （退出码 0 = ENFORCE 路径通过）
"""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "verabot"
EXEC = {"execute", "executemany", "executescript"}
SQL_START = re.compile(r"^\s*(SELECT\s|INSERT\s|UPDATE\s+\w+\s+SET\s|DELETE\s+FROM\s|CREATE\s|DROP\s|ALTER\s|PRAGMA\s)",
                       re.IGNORECASE)
# (相对 verabot/ 的路径, 函数名)；目前为空：ENFORCE 路径上不允许例外。
ALLOW: set[tuple[str, str]] = set()
# 相对 verabot/ 的路径。这些是 PR #31 新写出或改过、当时没有 SQL 的模块。
ENFORCE = (
    "services/chat_tasks/",
    "services/notify/",
    "services/owned_tasks/",
    "services/scheduled_tasks/",
    "agents/runtime.py",
    "agents/tool_router.py",
    "api/chat_task_schemas.py",
    "api/routers/chat.py",
    "api/routers/chat_tasks.py",
    "api/routers/conversation_activity.py",
    "api/routers/notifications.py",
    "api/routers/devices.py",
    "main.py",
)


def scan(path: Path):
    rel = path.relative_to(PKG).as_posix()
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found = []

    def visit(node, func):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            func = node.name
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in EXEC:
            found.append(("SQL-LAYER-01", rel, node.lineno, func, f".{node.func.attr}("))
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and SQL_START.match(node.value):
            found.append(("SQL-LAYER-02", rel, node.lineno, func, node.value.strip().splitlines()[0][:60]))
        if isinstance(node, ast.JoinedStr):
            head = node.values[0] if node.values else None
            if isinstance(head, ast.Constant) and isinstance(head.value, str) and SQL_START.match(head.value):
                found.append(("SQL-LAYER-02", rel, node.lineno, func, "f-string: " + head.value.strip()[:50]))
        for child in ast.iter_child_nodes(node):
            visit(child, func)

    visit(tree, "<module>")
    return [f for f in found if (f[1], f[3]) not in ALLOW]


def enforced(rel: str) -> bool:
    return any(rel == item or (item.endswith("/") and rel.startswith(item)) for item in ENFORCE)


def main() -> int:
    files = [p for p in sorted(PKG.rglob("*.py")) if p.relative_to(PKG).parts[0] != "db"]
    problems = [f for p in files for f in scan(p)]
    blocking = [f for f in problems if enforced(f[1])]
    known = [f for f in problems if not enforced(f[1])]
    db_files = sorted(p.relative_to(PKG).as_posix() for p in (PKG / "db").rglob("*.py"))
    ok1 = not any(f[0] == "SQL-LAYER-01" for f in blocking)
    ok2 = not any(f[0] == "SQL-LAYER-02" for f in blocking)
    for code, rel, line, func, what in known:
        print(f"    known {code} {rel}:{line} ({func}) {what}")
    for code, rel, line, func, what in blocking:
        print(f"    {code} {rel}:{line} ({func}) {what}")
    print(f"[{'PASS' if ok1 else 'FAIL'}] SQL-LAYER-01: PR #31 模块没有 execute 调用（扫描 {len(files)} 个模块）")
    print(f"[{'PASS' if ok2 else 'FAIL'}] SQL-LAYER-02: PR #31 模块没有 SQL 语句字符串")
    print(f"    db/ 模块 {len(db_files)} 个；ENFORCE 例外 {len(ALLOW)} 条；历史已知 {len(known)} 条")
    return 0 if ok1 and ok2 else 1


if __name__ == "__main__":
    sys.exit(main())
