#!/bin/bash
# 启动 DeepSeek Harness (dsh) Web UI（源码方式）
# 用法:
#   ./start-dsh.sh              前台启动并自动打开浏览器（默认 http://127.0.0.1:3080）
#   ./start-dsh.sh --no-open    只启动，不打开浏览器
#   ./start-dsh.sh --port 8080  指定端口
set -e
BASE="$(cd "$(dirname "$0")" && pwd)"
# 使用项目内自带完整头文件的 Node（原生模块编译/运行需要）
export PATH="$BASE/.toolchain/node-v22.23.2-darwin-arm64/bin:$PATH"
export COREPACK_NPM_REGISTRY="https://registry.npmmirror.com"
cd "$BASE/deepseek-harness"
exec pnpm dsh web "$@"
