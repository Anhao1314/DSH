#!/bin/bash
# 停止监听 3080 端口的 dsh web 服务（如改过端口请把 PORT 改成对应值）
PORT="${1:-3080}"
PIDS="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null)"
if [ -n "$PIDS" ]; then
  kill $PIDS 2>/dev/null && echo "已停止端口 $PORT 上的进程: $PIDS"
else
  echo "端口 $PORT 上没有在运行的 dsh 服务"
fi
