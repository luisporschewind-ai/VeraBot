#!/usr/bin/env python3
"""Restricted Drift Bottle report handling.

Usage:
  uv run python scripts/drift_bottle_admin.py --db data/verabot.db --list
  uv run python scripts/drift_bottle_admin.py --db data/verabot.db --admin 1 \
      --report 7 --action hide --reason "包含联系方式"

The database path must be explicit (no implicit production path). The admin
account must be listed in VERABOT_DRIFT_BOTTLE_ADMINS. Actions: keep, hide,
restore. Every action is written to drift_bottle_moderation_actions.
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Bot 漂流瓶举报处理（受限管理员）")
    parser.add_argument("--db", required=True, help="显式 SQLite 数据库路径")
    parser.add_argument("--admin", type=int, help="管理员账号 ID（须在 VERABOT_DRIFT_BOTTLE_ADMINS 中）")
    parser.add_argument("--report", type=int, help="举报 ID")
    parser.add_argument("--action", choices=("keep", "hide", "restore"), help="处理动作")
    parser.add_argument("--reason", default="", help="处理说明")
    parser.add_argument("--list", action="store_true", help="列出待处理举报")
    args = parser.parse_args()

    path = Path(args.db).expanduser().resolve()
    if not path.is_file():
        print(f"数据库不存在：{path}", file=sys.stderr)
        return 2
    if path.name in ("", ":memory:"):
        print("必须指定明确的数据库文件", file=sys.stderr)
        return 2
    os.environ["VERABOT_DB"] = str(path)
    os.environ.setdefault("VERABOT_DATA_DIR", str(path.parent))
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

    from verabot.core.config import DRIFT_BOTTLE_ADMINS
    from verabot.services.drift_bottle import moderation
    from verabot.services.drift_bottle.contracts import BottleError

    if not DRIFT_BOTTLE_ADMINS:
        print("未配置 VERABOT_DRIFT_BOTTLE_ADMINS，管理员工具不可用", file=sys.stderr)
        return 3
    if args.admin is None or args.admin not in DRIFT_BOTTLE_ADMINS:
        print("管理员身份未授权", file=sys.stderr)
        return 3

    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    try:
        if args.list:
            rows = moderation.pending(connection)
            if not rows:
                print("没有待处理举报")
            for row in rows:
                body = (row["body"] or "").replace("\n", " ")[:80]
                print(f"#{row['id']}  投稿#{row['contribution_id']}  Bot:{row['bot_name']}  "
                      f"原因:{row['reason']}  正文:{body}")
            return 0
        if args.report is None or args.action is None:
            parser.error("处理举报需要 --report 和 --action")
        result = moderation.moderate(connection, args.admin, args.report, args.action,
                                     args.reason, __import__("time").time(),
                                     admins=DRIFT_BOTTLE_ADMINS)
        connection.commit()
        print(f"举报 #{result['report_id']} 已处理：{result['action']}；投稿状态 {result['contribution_state']}")
        return 0
    except BottleError as error:
        connection.rollback()
        print(f"{error.message} ({error.code})", file=sys.stderr)
        return 4
    except Exception as error:
        connection.rollback()
        print(f"处理失败：{error}", file=sys.stderr)
        return 5
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
