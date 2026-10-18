#!/bin/bash
# ============================================================
# RSSHub + 自定义民航路由 —— 服务器一键部署
#
# 前置：把本仓库克隆到服务器任意位置
#   git clone https://github.com/Karen-Mok/rsshub-i2v.git /opt/rsshub-i2v
#   cd /opt/rsshub-i2v/server-deploy
#   sudo bash deploy.sh
#
# 可选参数：
#   --dir DIR         RSSHub 安装目录（默认 /opt/rsshub）
#   --port N          端口（默认 1200）
#   --commit HASH     指定 RSSHub 版本（默认用 routes/COMMIT 里的锚点）
#   --skip-node       已有 Node 22.22.2+ 时跳过安装
#   --no-systemd      不装 systemd，改用后台进程
#   --rebuild         强制重装依赖并重新构建（默认已构建则跳过，加快重跑）
#
# 本脚本内置了实际踩过的坑的防护，详见 README-服务器部署.md
# ============================================================
set -euo pipefail

# ---------- 默认值 ----------
INSTALL_DIR="/opt/rsshub"
PORT="1200"
COMMIT=""
SKIP_NODE=0
USE_SYSTEMD=1
FORCE_REBUILD=0
SERVICE_USER="rsshub"
NODE_VERSION="22.22.2"
PNPM_VERSION="10.34.5"
NPM_REGISTRY="https://registry.npmmirror.com"
RSSHUB_REPO="https://github.com/DIYgod/RSSHub.git"

# 所有 pnpm 命令都要带这个：
# 项目 package.json 锁定了 pnpm 版本，pnpm 默认每次启动都去解析/下载该版本，
# 不加此参数每条命令会卡约 300 秒
PNPM_FLAGS="--config.managePackageManagerVersions=false --config.updateNotifier=false"

# ---------- 输出 ----------
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_OFF='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_OFF=''
fi
log_info() { echo -e "${C_BLUE}[INFO]${C_OFF} $*"; }
log_ok()   { echo -e "${C_GREEN}[ OK ]${C_OFF} $*"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_OFF} $*"; }
log_err()  { echo -e "${C_RED}[FAIL]${C_OFF} $*"; }
step()     { echo ""; echo -e "${C_BLUE}── $* ──${C_OFF}"; }

# ---------- 参数 ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)         INSTALL_DIR="$2"; shift 2 ;;
        --port)        PORT="$2"; shift 2 ;;
        --commit)      COMMIT="$2"; shift 2 ;;
        --skip-node)   SKIP_NODE=1; shift ;;
        --no-systemd)  USE_SYSTEMD=0; shift ;;
        --rebuild)     FORCE_REBUILD=1; shift ;;
        -h|--help)     sed -n '2,22p' "$0"; exit 0 ;;
        *)             log_err "未知参数: $1"; exit 1 ;;
    esac
done

echo ""
echo "=========================================="
echo " RSSHub + 民航自定义路由 部署"
echo "=========================================="
echo " RSSHub 安装目录: $INSTALL_DIR"
echo " 端口:            $PORT"
echo ""

[ "$(id -u)" -eq 0 ] || { log_err "需要 root，请用 sudo bash $0"; exit 1; }
command -v git  >/dev/null 2>&1 || { log_err "缺少 git";  exit 1; }
command -v curl >/dev/null 2>&1 || { log_err "缺少 curl"; exit 1; }

# ---------- 0. 定位路由源 ----------
step "0. 定位自定义路由"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTES_SRC=""
ROUTES_MODE=""

# 优先：仓库内的 routes/ 目录（纯文本可 diff，git 不会产生 macOS ._ 文件）
if [ -d "$SCRIPT_DIR/../routes/lib/routes" ]; then
    ROUTES_SRC="$SCRIPT_DIR/../routes"
    ROUTES_MODE="dir"
    log_ok "使用仓库内路由目录: $(cd "$ROUTES_SRC" && pwd)"
# 兼容：旧版 tar.gz 包
elif [ -n "$(ls -t "$SCRIPT_DIR"/rsshub-routes-*.tar.gz 2>/dev/null | head -1)" ]; then
    ROUTES_SRC="$(ls -t "$SCRIPT_DIR"/rsshub-routes-*.tar.gz 2>/dev/null | head -1)"
    ROUTES_MODE="tarball"
    log_ok "使用路由包: $ROUTES_SRC"
else
    log_err "找不到自定义路由。"
    echo "  请 clone 整个仓库（含 routes/ 目录），不要只下载单个脚本："
    echo "    git clone https://github.com/Karen-Mok/rsshub-i2v.git /opt/rsshub-i2v"
    exit 1
fi

# 版本锚点：自定义路由与上游 RSSHub 强耦合，必须锁定同一 commit
if [ -z "$COMMIT" ] && [ -f "$ROUTES_SRC/COMMIT" ]; then
    COMMIT=$(tr -d '[:space:]' < "$ROUTES_SRC/COMMIT")
fi
[ -n "$COMMIT" ] && log_info "RSSHub 版本锚点: ${COMMIT:0:12}"

# ---------- 1. Node.js ----------
install_node() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64)   arch="x64" ;;
        aarch64|arm64)  arch="arm64" ;;
        *) log_err "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
    log_info "安装 Node.js v${NODE_VERSION} (${arch})..."
    local tb="node-v${NODE_VERSION}-linux-${arch}.tar.xz"
    cd /tmp
    curl -fsSL -m 300 -o "$tb" "https://registry.npmmirror.com/-/binary/node/v${NODE_VERSION}/${tb}" \
        || curl -fsSL -m 300 -O "https://nodejs.org/dist/v${NODE_VERSION}/${tb}"
    tar -xf "$tb" -C /opt && rm -f "$tb"
    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/node" /usr/local/bin/node
    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/npm"  /usr/local/bin/npm
    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/npx"  /usr/local/bin/npx
    export PATH="/opt/node-v${NODE_VERSION}-linux-${arch}/bin:$PATH"
    hash -r
    log_ok "Node $(node -v) 已安装"
}

# 语义化版本比较：不能只比主版本号
# 22.22.1 < 22.22.2，只比主版本会误判合格并跳过安装
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
node_satisfies() {
    local v="${1#v}"
    case "$v" in
        22.*)            ver_ge "$v" "22.22.2" ;;
        24.*)            ver_ge "$v" "24.15.0" ;;
        2[5-9].*|[3-9]*) return 0 ;;
        *)               return 1 ;;
    esac
}

step "1. Node.js"
if [ "$SKIP_NODE" -eq 1 ]; then
    command -v node >/dev/null 2>&1 || { log_err "未找到 node，去掉 --skip-node"; exit 1; }
    if node_satisfies "$(node -v)"; then
        log_ok "使用现有 Node $(node -v)"
    else
        log_err "RSSHub 要求 ^22.22.2 或 ^24.15.0，当前 $(node -v)"
        log_err "请去掉 --skip-node 自动安装，或先手动升级"
        exit 1
    fi
else
    if command -v node >/dev/null 2>&1 && node_satisfies "$(node -v)"; then
        log_ok "已有符合要求的 Node $(node -v)"
    else
        [ -n "$(command -v node || true)" ] && log_warn "现有 Node $(node -v) 不满足要求，安装 v${NODE_VERSION}"
        install_node
    fi
fi

# ---------- 2. pnpm ----------
step "2. pnpm"
npm install -g "pnpm@${PNPM_VERSION}" --registry="$NPM_REGISTRY" --no-audit --no-fund >/dev/null 2>&1
# 加固：确保 npm 全局 bin 在 PATH（--skip-node 时容易漏）
NPM_GLOBAL_BIN="$(npm prefix -g 2>/dev/null)/bin"
[ -d "$NPM_GLOBAL_BIN" ] && export PATH="$NPM_GLOBAL_BIN:$PATH"
command -v pnpm >/dev/null 2>&1 || { log_err "pnpm 安装失败"; exit 1; }
log_ok "pnpm $(pnpm $PNPM_FLAGS --version)"

# ---------- 3. RSSHub 源码 ----------
step "3. 拉取 RSSHub 源码"
if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "目录已存在，更新中..."
    cd "$INSTALL_DIR"
    git fetch --depth=1 origin master 2>/dev/null || true
else
    log_info "克隆 RSSHub（约 1~3 分钟）..."
    rm -rf "$INSTALL_DIR"
    git clone --depth=1 "$RSSHUB_REPO" "$INSTALL_DIR" || {
        log_warn "GitHub 直连失败，尝试镜像 ghfast.top..."
        git clone --depth=1 "https://ghfast.top/${RSSHUB_REPO}" "$INSTALL_DIR"
    }
    cd "$INSTALL_DIR"
fi

if [ -n "$COMMIT" ]; then
    log_info "锁定到版本锚点 ${COMMIT:0:12}..."
    git fetch origin "$COMMIT" 2>/dev/null \
        || git fetch --unshallow 2>/dev/null \
        || git fetch --depth=1000000 origin master 2>/dev/null \
        || true
    if git checkout -q "$COMMIT" 2>/dev/null; then
        log_ok "已锁定到 ${COMMIT:0:12}"
    else
        log_warn "无法 checkout 到 ${COMMIT:0:12}，使用当前 master"
        log_warn "若构建报错多为版本不匹配，可重跑：bash $0 --commit <本机 commit>"
    fi
fi

# ---------- 4. 应用自定义路由 ----------
step "4. 应用自定义路由"
if [ "$ROUTES_MODE" = "dir" ]; then
    cp -r "$ROUTES_SRC/." "$INSTALL_DIR/"
else
    TMP_X=$(mktemp -d)
    tar -xzf "$ROUTES_SRC" -C "$TMP_X"
    cp -r "$TMP_X/routes/." "$INSTALL_DIR/"
    rm -rf "$TMP_X"
fi

# 防御：清理 macOS AppleDouble 文件（._ 前缀，含二进制 \x00，会让 esbuild 崩）
# 用 routes/ 目录时不会有，保留以防手工拷文件混入
find "$INSTALL_DIR" \
    \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) \
    -not -path '*/node_modules/*' -exec rm -rf {} + 2>/dev/null || true

for ns in caac caacnews mct nia atmb ctaweb traveldaily; do
    [ -d "$INSTALL_DIR/lib/routes/$ns" ] && log_ok "新增 $ns"
done
[ -f "$INSTALL_DIR/lib/routes/bendibao/news.ts" ] && log_ok "修复 bendibao"
[ -f "$INSTALL_DIR/lib/routes/nbd/index.ts" ]    && log_ok "修复 nbd"

# ---------- 5. 依赖 ----------
step "5. 安装依赖"
cd "$INSTALL_DIR"
export PUPPETEER_SKIP_DOWNLOAD=true
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export CI=true

if [ -d node_modules ] && [ "$FORCE_REBUILD" -eq 0 ]; then
    log_ok "node_modules 已存在，跳过（--rebuild 强制重装）"
else
    log_info "安装中（约 3~15 分钟）..."
    pnpm $PNPM_FLAGS install --frozen-lockfile --registry="$NPM_REGISTRY"
    log_ok "依赖安装完成"
fi

# ---------- 6. 构建 ----------
step "6. 构建"
if [ -f dist/index.mjs ] && [ "$FORCE_REBUILD" -eq 0 ]; then
    log_ok "已构建过，跳过（--rebuild 强制重新构建）"
else
    # 构建前再兜底清一次 macOS 垃圾文件
    find "$INSTALL_DIR" \
        \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) \
        -not -path '*/node_modules/*' -exec rm -rf {} + 2>/dev/null || true

    log_info "构建中（约 1~2 分钟）..."
    if ! pnpm $PNPM_FLAGS build; then
        log_err "构建失败"
        echo ""
        echo "  ⚠️  后续步骤（.env / systemd / 启动）尚未执行。"
        echo "  排查后重跑本脚本；若构建已手工修好，跑："
        echo "     bash $SCRIPT_DIR/fix-build.sh --skip-build"
        echo "  常见原因见 README-服务器部署.md「故障排查」"
        exit 1
    fi
    log_ok "构建完成"
fi

# ---------- 7. 配置 ----------
step "7. 写入 .env"
cat > "$INSTALL_DIR/.env" <<EOF
PORT=$PORT
LISTEN_INADDR_ANY=1
CACHE_TYPE=memory
CACHE_EXPIRE=1800
MEMORY_MAX=512
LOGGER_LEVEL=info
NO_LOGFILES=false
SHOW_LOGGER_TIMESTAMP=true
REQUEST_TIMEOUT=30000
NO_RANDOM_UA=false
ALLOW_ORIGIN=*
EOF
log_ok ".env 已写入（端口 $PORT）"

id "$SERVICE_USER" >/dev/null 2>&1 || useradd -r -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || true
mkdir -p "$INSTALL_DIR/logs"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR" 2>/dev/null || true

# ---------- 8. 启动 ----------
step "8. 启动服务"
NODE_BIN=$(command -v node)
HAS_SYSTEMD=0
[ "$USE_SYSTEMD" -eq 1 ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && HAS_SYSTEMD=1

if [ "$HAS_SYSTEMD" -eq 1 ]; then
    cat > /etc/systemd/system/rsshub.service <<EOF
[Unit]
Description=RSSHub - RSS feed generator with custom CAAC routes
Documentation=https://docs.rsshub.app
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-http-header-size=32768
ExecStart=$NODE_BIN $INSTALL_DIR/dist/index.mjs
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=20
StandardOutput=append:$INSTALL_DIR/logs/systemd-stdout.log
StandardError=append:$INSTALL_DIR/logs/systemd-stderr.log
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable rsshub >/dev/null 2>&1 || true
    systemctl restart rsshub
    sleep 1
    systemctl is-active --quiet rsshub && log_ok "systemd 服务运行中" || {
        log_err "启动失败：journalctl -u rsshub -n 50 --no-pager"
        exit 1
    }
else
    log_warn "无 systemd，改用后台进程"
    pkill -f "$INSTALL_DIR/dist/index.mjs" 2>/dev/null || true
    sleep 1
    cd "$INSTALL_DIR"
    START="cd $INSTALL_DIR && NODE_ENV=production setsid nohup $NODE_BIN dist/index.mjs > logs/nohup.log 2>&1 &"
    runuser -u "$SERVICE_USER" -- bash -c "$START" 2>/dev/null || bash -c "$START"
    log_ok "后台进程已启动"
fi

# ---------- 9. 验证 ----------
step "9. 验证"
READY=0
for i in $(seq 1 40); do
    curl -fsS -m 3 -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null && { READY=1; break; }
    sleep 1
done

if [ "$READY" -ne 1 ]; then
    log_err "服务未就绪"
    [ "$HAS_SYSTEMD" -eq 1 ] && journalctl -u rsshub -n 20 --no-pager 2>/dev/null
    exit 1
fi
log_ok "服务已就绪: http://127.0.0.1:${PORT}"

# 验证阶段必须容错：
# set -e + pipefail 下，任一条路由 curl 失败会让 `n=$(curl|awk)` 返回非零，
# 导致脚本静默退出、后续路由全不测且无任何报错
set +e
check() {
    local name="$1" path="$2" code n
    code=$(curl -sS -m 45 -o /tmp/_rss_check.xml -w "%{http_code}" \
           "http://127.0.0.1:${PORT}${path}?limit=5" 2>/dev/null) || code="000"
    n=$(awk -v RS='<item>' 'END{print NR-1}' /tmp/_rss_check.xml 2>/dev/null) || n=0
    [ -z "$n" ] && n=0
    if [ "$code" = "200" ] && [ "$n" -gt 0 ] 2>/dev/null; then
        echo -e "  ${C_GREEN}✅${C_OFF} $name (${n} 条)"
    else
        echo -e "  ${C_YELLOW}⚠️${C_OFF}  $name  HTTP=${code} 条目=${n}"
    fi
}
check "民航局 /caac/xwzx/mhyw"   "/caac/xwzx/mhyw"
check "中国民航网 /caacnews/1/1" "/caacnews/1/1"
check "文旅部 /mct/whzx/whyw"    "/mct/whzx/whyw"
check "移民局 /nia/tzgg"         "/nia/tzgg"
check "空管局 /atmb"             "/atmb"
check "旅游研究院 /ctaweb"       "/ctaweb"
check "环球旅讯 /traveldaily"    "/traveldaily"
check "本地宝 /bendibao/news/bj" "/bendibao/news/bj"
check "每经 /nbd"                "/nbd"
set -e

echo ""
echo " 💡 HTTP=000 超时 / 5xx 路由报错 / 200但0条 = 上游站点结构变化"
echo "    大面积异常时先跑：bash $SCRIPT_DIR/diag.sh 判断是否出网问题"
echo ""
echo "=========================================="
echo " 部署完成  http://<服务器IP>:$PORT"
echo "=========================================="
echo " 目录: $INSTALL_DIR"
echo ""
echo " 运维：systemctl status|restart|stop rsshub"
echo "       journalctl -u rsshub -f"
echo ""
echo " ⚠️  放行端口："
echo "   firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload"
echo "   ufw allow ${PORT}/tcp"
echo ""
