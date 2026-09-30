#!/usr/bin/env bash
# 停止 ./start.sh --detach 启动的后台服务
cd "$(dirname "$0")"
if [ -f data/server.pid ] && kill "$(cat data/server.pid)" 2>/dev/null; then
  echo "[VeraBot] 已停止 PID $(cat data/server.pid)"; rm -f data/server.pid
else
  echo "[VeraBot] 没有找到运行中的后台服务（data/server.pid）"
fi
