#!/usr/bin/env python3
"""SQL 分层检查（SQL-LAYER-*）：SQL 只允许写在 verabot/db/ 里（*_store.py / repository.py / migrations/）。

静态扫描（AST，不导入、不连库）verabot/ 下 db/ 以外的模块：
  SQL-LAYER-01  不出现 .execute( / .executemany( / .executescript( 调用
  SQL-LAYER-02  不出现以 SQL 语句开头的字符串常量（SELECT / INSERT / UPDATE … SET / DELETE FROM / CREATE / DROP / ALTER / PRAGMA）
确实需要例外时把（相对 verabot/ 的路径, 函数名）加进 ALLOW，并在 PR 里说明原因。
用法：python scripts/test/sql_layer_check.py   （退出码 0 = 通过）
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
# (相对 verabot/ 的路径, 函数名)；目前为空：所有 SQL 都在 db/ 里。
ALLOW: set[tuple[str, str]] = set()


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


def main() -> int:
    files = [p for p in sorted(PKG.rglob("*.py")) if p.relative_to(PKG).parts[0] != "db"]
    problems = [f for p in files for f in scan(p)]
    db_files = sorted(p.relative_to(PKG).as_posix() for p in (PKG / "db").rglob("*.py"))
    ok1 = not any(f[0] == "SQL-LAYER-01" for f in problems)
    ok2 = not any(f[0] == "SQL-LAYER-02" for f in problems)
    for code, rel, line, func, what in problems:
        print(f"    {code} {rel}:{line} ({func}) {what}")
    print(f"[{'PASS' if ok1 else 'FAIL'}] SQL-LAYER-01: db/ 以外没有 execute 调用（扫描 {len(files)} 个模块）")
    print(f"[{'PASS' if ok2 else 'FAIL'}] SQL-LAYER-02: db/ 以外没有 SQL 语句字符串")
    print(f"    db/ 模块 {len(db_files)} 个；例外 {len(ALLOW)} 条")
    return 0 if ok1 and ok2 else 1


if __name__ == "__main__":
    sys.exit(main())
