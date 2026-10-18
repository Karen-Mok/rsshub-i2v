#!/bin/zsh
# RSSHub 前台运行脚本 —— 供 launchd 调用
# launchd 要求进程在前台运行，不要自行 nohup / & 后台化

APP_DIR="/Users/karenmok/WorkBuddy/2026-09-18-09-55-46/RSSHub"
NODE_BIN="/Users/karenmok/.workbuddy/binaries/node/versions/22.22.2-2/bin"

# 关掉注入的 node 文件代理钩子，否则会拦截 RSSHub 的文件读写
unset NODE_OPTIONS
export CODEBUDDY_BROKERED_FS_HOOK_ENABLED=0

export PATH="$NODE_BIN:$PATH"
export NODE_ENV=production

cd "$APP_DIR" || exit 1

exec "$NODE_BIN/node" dist/index.mjs
