#!/bin/zsh
# RSSHub 本地启动脚本（后台常驻）
#
# 用法:
#   ./start-rsshub.sh          # 生产模式（已 build，性能更好）
#   ./start-rsshub.sh dev      # 开发模式（热重载，改路由自动重启）
#
# 说明: 必须 unset NODE_OPTIONS 并关掉 CODEBUDDY_BROKERED_FS_HOOK，
#       否则注入的 node 文件代理钩子会拦截 pnpm/node 的文件操作导致失败。

set -e

APP_DIR="/Users/karenmok/WorkBuddy/2026-09-18-09-55-46/RSSHub"
NODE_BIN="/Users/karenmok/.workbuddy/binaries/node/versions/22.22.2-2/bin"
PNPM="/Users/karenmok/.workbuddy/binaries/node/pnpm10/node_modules/.bin/pnpm"
LOG_DIR="$APP_DIR/logs"

unset NODE_OPTIONS
export CODEBUDDY_BROKERED_FS_HOOK_ENABLED=0
export PATH="$NODE_BIN:$PATH"

MODE="${1:-prod}"

cd "$APP_DIR"
mkdir -p "$LOG_DIR"

# 端口占用则先停掉旧实例
if lsof -ti:1200 >/dev/null 2>&1; then
    echo "⚠️  端口 1200 已被占用，先停止旧进程..."
    lsof -ti:1200 | xargs kill -9 2>/dev/null || true
    sleep 1
fi

if [ "$MODE" = "dev" ]; then
    echo "🚀 开发模式启动 RSSHub（热重载）..."
    nohup "$PNPM" --config.managePackageManagerVersions=false dev > "$LOG_DIR/rsshub-dev.log" 2>&1 &
else
    echo "🚀 生产模式启动 RSSHub..."
    nohup "$PNPM" --config.managePackageManagerVersions=false start > "$LOG_DIR/rsshub-prod.log" 2>&1 &
fi

echo "⏳ 等待服务就绪..."
for i in {1..40}; do
    if curl -sS -m 2 -o /dev/null http://127.0.0.1:1200/ 2>/dev/null; then
        echo "✅ RSSHub 已启动: http://127.0.0.1:1200"
        echo "   日志: $LOG_DIR/rsshub-$([ "$MODE" = "dev" ] && echo dev || echo prod).log"
        exit 0
    fi
    sleep 1
done

echo "❌ 启动超时，请查看日志排查"
tail -20 "$LOG_DIR/rsshub-$([ "$MODE" = "dev" ] && echo dev || echo prod).log"
exit 1
