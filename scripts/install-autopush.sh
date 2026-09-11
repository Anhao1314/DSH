#!/usr/bin/env bash
# 安装「提交即推送」钩子：每次 git commit 之后自动把当前分支推到 origin。
#
# 目的：让 GitHub 上的仓库始终跟得上本地（用户要求「保持实时推送」）。
# 行为：钩子在 commit 成功后同步执行 `git push origin HEAD:<branch>`；
#       推送失败（断网 / 无权限）只写日志，**不会**让这次提交失败。
#
# 用法：
#   ./scripts/install-autopush.sh            # 安装 / 更新钩子
#   ./scripts/install-autopush.sh --status   # 查看钩子状态与最近推送日志
#   ./scripts/install-autopush.sh --remove   # 卸载钩子
#
# 日志：/tmp/dsh-autopush.log
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK=".git/hooks/post-commit"
LOG=/tmp/dsh-autopush.log

case "${1:-install}" in
  --status)
    if [ -x "$HOOK" ]; then echo "钩子已安装：$HOOK"; else echo "钩子未安装"; fi
    if [ -f "$LOG" ]; then echo "--- 最近 5 条推送日志 ---"; tail -5 "$LOG"; else echo "（还没有推送日志）"; fi
    ;;
  --remove)
    rm -f "$HOOK"
    echo "已卸载 $HOOK"
    ;;
  *)
    cat > "$HOOK" <<'HOOKBODY'
#!/bin/sh
# 由 scripts/install-autopush.sh 生成：提交后把 HEAD 推到 origin（失败只记日志，不阻塞提交）。
LOG=/tmp/dsh-autopush.log
branch=$(git symbolic-ref --short -q HEAD || true)
[ -z "$branch" ] && exit 0            # detached HEAD：不推
printf '[%s] push %s -> origin/%s\n' "$(date '+%F %T')" "$(git rev-parse --short HEAD)" "$branch" >> "$LOG"
if git push origin "HEAD:$branch" >> "$LOG" 2>&1; then
  printf '         ok\n' >> "$LOG"
else
  printf '         failed（可手动 git push 重试）\n' >> "$LOG"
fi
exit 0
HOOKBODY
    chmod +x "$HOOK"
    echo "已安装 $HOOK"
    echo "以后每次 git commit 都会自动推送到 origin；日志见 $LOG"
    ;;
esac
