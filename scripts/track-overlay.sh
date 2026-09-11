#!/usr/bin/env bash
# 把 deepseek-harness/ 里的 5 个本地 overlay 文件重新登记进本仓库 index。
#
# 背景：deepseek-harness/ 是上游 clone（自带 .git，约 190MB），本仓库整体忽略它；
# 只有下面 5 个文件属于我们自己的 overlay。嵌套 .git 会让 `git add -f` 静默失效，
# 所以这里用 hash-object + update-index 直接写 index（不改动嵌套仓库本身）。
# 用法：改完 overlay 后跑一次，然后正常 git commit。
set -euo pipefail
cd "$(dirname "$0")/.."
FILES=(
  deepseek-harness/.dockerignore
  deepseek-harness/.npmrc
  deepseek-harness/Dockerfile.orbstack
  deepseek-harness/orbstack-entrypoint.sh
  deepseek-harness/orbstack-relay.cjs
)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
  blob=$(git hash-object -w -- "$f")
  mode=$(test -x "$f" && echo 100755 || echo 100644)   # 只保留可执行位
  git update-index --add --cacheinfo "$mode,$blob,$f"
  echo "staged $f"
done
