#!/bin/bash
# ============================================================
# RSSHub 远程 Linux 服务器一键部署脚本
#
# 功能：安装 Node/pnpm → 拉取 RSSHub → 应用自定义路由 → 构建
#      → 配置 systemd 服务 → 启动并验证
#
# 用法（需 root 或 sudo）：
#   sudo bash deploy.sh
#   sudo bash deploy.sh --dir /opt/rsshub --port 1200
#   sudo bash deploy.sh --routes /tmp/rsshub-routes-20260918.tar.gz
#   sudo bash deploy.sh --skip-node        # 已有 Node 22+ 时跳过安装
#
# 可选参数：
#   --dir DIR        安装目录（默认 /opt/rsshub）
#   --port N         监听端口（默认 1200）
#   --routes FILE    路由包路径（默认自动查找 /tmp/rsshub-routes-*.tar.gz）
#   --commit HASH    指定 RSSHub commit（默认用路由包内记录的版本）
#   --skip-node      跳过 Node 安装
#   --no-systemd     不装 systemd，改用 nohup 启动
# ============================================================
set -euo pipefail

# ---------- 默认值 ----------
INSTALL_DIR="/opt/rsshub"
PORT="1200"
ROUTES_TARBALL=""
COMMIT=""
SKIP_NODE=0
USE_SYSTEMD=1
SERVICE_USER="rsshub"
NODE_VERSION="22.22.2"
PNPM_VERSION="10.34.5"
NPM_REGISTRY="https://registry.npmmirror.com"

# ---------- 颜色输出 ----------
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_OFF='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_OFF=''
fi
log_info() { echo -e "${C_BLUE}[INFO]${C_OFF} $*"; }
log_ok()   { echo -e "${C_GREEN}[ OK ]${C_OFF} $*"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_OFF} $*"; }
log_err()  { echo -e "${C_RED}[FAIL]${C_OFF} $*"; }

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)        INSTALL_DIR="$2"; shift 2 ;;
        --port)       PORT="$2"; shift 2 ;;
        --routes)     ROUTES_TARBALL="$2"; shift 2 ;;
        --commit)     COMMIT="$2"; shift 2 ;;
        --skip-node)  SKIP_NODE=1; shift ;;
        --no-systemd) USE_SYSTEMD=0; shift ;;
        -h|--help)    sed -n '2,25p' "$0"; exit 0 ;;
        *)            log_err "未知参数: $1"; exit 1 ;;
    esac
done

# ---------- 前置检查 ----------
echo ""
echo "=========================================="
echo " RSSHub 服务器部署"
echo "=========================================="
echo " 安装目录: $INSTALL_DIR"
echo " 端口:     $PORT"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    log_err "需要 root 权限，请用 sudo bash $0 运行"
    exit 1
fi

command -v git >/dev/null 2>&1 || { log_err "缺少 git，请先安装: apt install -y git / yum install -y git"; exit 1; }
command -v curl >/dev/null 2>&1 || { log_err "缺少 curl，请先安装"; exit 1; }

# ---------- 1. Node.js ----------
install_node() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_err "不支持的架构: $(uname -m)"; exit 1 ;;
    esac

    log_info "安装 Node.js v${NODE_VERSION} (${arch})..."
    local tarball="node-v${NODE_VERSION}-linux-${arch}.tar.xz"
    local url="https://registry.npmmirror.com/-/binary/node/v${NODE_VERSION}/${tarball}"

    cd /tmp
    if ! curl -fsSL -m 300 -o "$tarball" "$url"; then
        log_warn "镜像下载失败，回退官方源"
        curl -fsSL -m 300 -O "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}"
    fi

    mkdir -p /opt
    tar -xf "$tarball" -C /opt
    rm -f "$tarball"

    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/node" /usr/local/bin/node
    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/npm"  /usr/local/bin/npm
    ln -sf "/opt/node-v${NODE_VERSION}-linux-${arch}/bin/npx"  /usr/local/bin/npx

    export PATH="/opt/node-v${NODE_VERSION}-linux-${arch}/bin:$PATH"
    log_ok "Node $(node -v) 已安装"
}

# 版本比较：$1 >= $2 ?
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# RSSHub package.json engines: ^22.22.2 || ^24.15.0
# 注意：不能只比较主版本号 —— 22.22.1 < 22.22.2 会导致构建告警甚至失败
node_satisfies() {
    local v="${1#v}"
    case "$v" in
        22.*)          ver_ge "$v" "22.22.2" ;;
        24.*)          ver_ge "$v" "24.15.0" ;;
        2[5-9].*|[3-9]*) return 0 ;;
        *)             return 1 ;;
    esac
}

if [ "$SKIP_NODE" -eq 1 ]; then
    log_info "跳过 Node 安装，检测现有版本..."
    if ! command -v node >/dev/null 2>&1; then
        log_err "未找到 node，去掉 --skip-node 重试"; exit 1
    fi
    if node_satisfies "$(node -v)"; then
        log_ok "使用现有 Node $(node -v)"
    else
        log_err "RSSHub 要求 Node ^22.22.2 或 ^24.15.0，当前 $(node -v)"
        log_err "请去掉 --skip-node 让脚本自动安装，或先手动升级 Node"
        exit 1
    fi
else
    if command -v node >/dev/null 2>&1 && node_satisfies "$(node -v)"; then
        log_ok "已存在符合要求的 Node $(node -v)，无需安装"
    else
        if command -v node >/dev/null 2>&1; then
            log_warn "现有 Node $(node -v) 不满足 ^22.22.2 / ^24.15.0，安装 v${NODE_VERSION}"
        fi
        install_node
    fi
fi

# ---------- 2. pnpm ----------
# 关键：必须用 --config.managePackageManagerVersions=false
# 否则 pnpm 每次启动都会去解析/下载 package.json 里锁定的版本，每条命令卡 ~300 秒
PNPM_FLAGS="--config.managePackageManagerVersions=false --config.updateNotifier=false"

log_info "安装 pnpm@${PNPM_VERSION}..."
npm install -g "pnpm@${PNPM_VERSION}" --registry="$NPM_REGISTRY" --no-audit --no-fund >/dev/null 2>&1

# 加固：确保 npm 全局 bin 目录在 PATH 中（跳过 Node 安装时容易漏掉）
NPM_GLOBAL_BIN="$(npm prefix -g 2>/dev/null)/bin"
[ -d "$NPM_GLOBAL_BIN" ] && export PATH="$NPM_GLOBAL_BIN:$PATH"

if ! command -v pnpm >/dev/null 2>&1; then
    log_err "pnpm 安装失败或未加入 PATH（npm 全局目录: $NPM_GLOBAL_BIN）"
    exit 1
fi
log_ok "pnpm $(pnpm $PNPM_FLAGS --version) 已安装"

# ---------- 3. 拉取 RSSHub ----------
if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "目录已存在，拉取最新代码..."
    cd "$INSTALL_DIR"
    git fetch --depth=1 origin master 2>/dev/null || true
else
    log_info "克隆 RSSHub 到 $INSTALL_DIR ..."
    rm -rf "$INSTALL_DIR"
    git clone --depth=1 https://github.com/DIYgod/RSSHub.git "$INSTALL_DIR" || {
        log_warn "GitHub 直连失败，尝试镜像 ghfast.top..."
        git clone --depth=1 https://ghfast.top/https://github.com/DIYgod/RSSHub.git "$INSTALL_DIR"
    }
    cd "$INSTALL_DIR"
fi

# ---------- 4. 应用自定义路由 ----------
if [ -z "$ROUTES_TARBALL" ]; then
    ROUTES_TARBALL=$(ls -t /tmp/rsshub-routes-*.tar.gz /root/rsshub-routes-*.tar.gz "$HOME"/rsshub-routes-*.tar.gz 2>/dev/null | head -1 || true)
fi

if [ -n "$ROUTES_TARBALL" ] && [ -f "$ROUTES_TARBALL" ]; then
    log_info "应用自定义路由: $ROUTES_TARBALL"

    TMP_EXTRACT=$(mktemp -d)
    tar -xzf "$ROUTES_TARBALL" -C "$TMP_EXTRACT"

    # 版本锚点：优先命令行指定，否则用包内记录
    if [ -z "$COMMIT" ] && [ -f "$TMP_EXTRACT/COMMIT" ]; then
        COMMIT=$(cat "$TMP_EXTRACT/COMMIT" | tr -d '[:space:]')
    fi

    if [ -n "$COMMIT" ]; then
        log_info "切换到匹配的 RSSHub 版本: ${COMMIT:0:12}"
        cd "$INSTALL_DIR"
        # 多数 Git 服务不允许直接 fetch 任意 sha，逐级回退
        git fetch origin "$COMMIT" 2>/dev/null \
            || git fetch --unshallow 2>/dev/null \
            || git fetch --depth=1000000 origin master 2>/dev/null \
            || true
        if git checkout -q "$COMMIT" 2>/dev/null; then
            log_ok "已锁定到 commit ${COMMIT:0:12}"
        else
            log_warn "无法 checkout 到 $COMMIT，继续使用当前 master"
            log_warn "若构建报错，多半是版本不匹配，可重跑：bash $0 --commit <本机 commit>"
        fi
    fi

    log_info "覆盖路由文件..."
    cp -r "$TMP_EXTRACT/routes/." "$INSTALL_DIR/"
    rm -rf "$TMP_EXTRACT"

    # 关键：清理 macOS 传输混入的 AppleDouble 元数据文件（._ 前缀）
    # 这些文件含二进制内容，Linux 上会被 esbuild 当源码扫描，报 "Unexpected \x00" 直接构建失败
    log_info "清理 macOS 元数据文件（._* / .DS_Store / __MACOSX）..."
    find "$INSTALL_DIR" \
        \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) \
        -not -path '*/node_modules/.pnpm/*' \
        -exec rm -rf {} + 2>/dev/null || true
    log_ok "已清理"

    echo "  --- 已应用的路由 ---"
    for ns in caac caacnews mct nia atmb ctaweb traveldaily; do
        [ -d "$INSTALL_DIR/lib/routes/$ns" ] && echo "  ✅ 新增 $ns"
    done
    [ -f "$INSTALL_DIR/lib/routes/bendibao/news.ts" ] && echo "  ✅ 修复 bendibao"
    [ -f "$INSTALL_DIR/lib/routes/nbd/index.ts" ]   && echo "  ✅ 修复 nbd"
else
    log_warn "未找到路由包，将部署纯净版 RSSHub（不含自定义路由）"
    log_warn "如需自定义路由：scp rsshub-routes-*.tar.gz 到本机后重跑本脚本，或用 --routes 指定"
fi

# ---------- 5. 安装依赖 ----------
cd "$INSTALL_DIR"
log_info "安装依赖（约 3~15 分钟，取决于服务器网速）..."
export PUPPETEER_SKIP_DOWNLOAD=true
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export CI=true

pnpm $PNPM_FLAGS install --frozen-lockfile --registry="$NPM_REGISTRY"
log_ok "依赖安装完成"

# ---------- 6. 构建 ----------
log_info "构建（含自定义路由）..."
# 构建前再兜底清理一次（防止期间有人手动拷文件带入 macOS 垃圾文件）
find "$INSTALL_DIR" \
    \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) \
    -not -path '*/node_modules/.pnpm/*' \
    -exec rm -rf {} + 2>/dev/null || true
pnpm $PNPM_FLAGS build
log_ok "构建完成"

# ---------- 7. 配置文件 ----------
log_info "写入 .env ..."
cat > "$INSTALL_DIR/.env" <<EOF
# ===== RSSHub 服务器配置 =====

# 服务端口
PORT=$PORT

# 监听地址（服务器上必须开，否则只监听 127.0.0.1，外部无法访问）
LISTEN_INADDR_ANY=1

# 缓存：单机用内存即可；长期运行建议换 redis（CACHE_TYPE=redis + REDIS_URL=redis://127.0.0.1:6379）
CACHE_TYPE=memory
CACHE_EXPIRE=1800
MEMORY_MAX=512

# 日志
LOGGER_LEVEL=info
NO_LOGFILES=false
SHOW_LOGGER_TIMESTAMP=true

# 网络请求
REQUEST_TIMEOUT=30000
NO_RANDOM_UA=false

# 跨域（浏览器插件 / 前端调用）
ALLOW_ORIGIN=*
EOF
log_ok ".env 已写入"

# ---------- 8. 创建运行用户 ----------
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin "$SERVICE_USER" 2>/dev/null || useradd -r -s /bin/false "$SERVICE_USER"
fi
mkdir -p "$INSTALL_DIR/logs"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# ---------- 9. 启动 ----------
NODE_BIN=$(command -v node)

if [ "$USE_SYSTEMD" -eq 1 ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    log_info "配置 systemd 服务..."
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

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rsshub >/dev/null 2>&1
    systemctl restart rsshub
    log_ok "systemd 服务已启用并启动"
    START_MODE="systemd"
else
    log_warn "未检测到 systemd，改用后台进程启动"
    cd "$INSTALL_DIR"
    START_CMD="cd $INSTALL_DIR && NODE_ENV=production setsid nohup $NODE_BIN dist/index.mjs > logs/nohup.log 2>&1 &"
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$SERVICE_USER" -- bash -c "$START_CMD"
    elif command -v su >/dev/null 2>&1; then
        su -s /bin/bash "$SERVICE_USER" -c "$START_CMD" 2>/dev/null || bash -c "$START_CMD"
    else
        log_warn "无 runuser/su，将以 root 运行（不推荐，建议装 systemd）"
        bash -c "$START_CMD"
    fi
    START_MODE="nohup"
fi

# ---------- 10. 验证 ----------
log_info "等待服务就绪..."
READY=0
for i in $(seq 1 40); do
    if curl -fsS -m 3 -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null; then
        READY=1
        break
    fi
    sleep 1
done

echo ""
echo "=========================================="
if [ "$READY" -eq 1 ]; then
    log_ok "RSSHub 已启动: http://127.0.0.1:${PORT}"
else
    log_err "启动超时，请查看日志排查"
    echo "  journalctl -u rsshub -n 50 --no-pager"
    echo "  tail -50 $INSTALL_DIR/logs/*.log"
    exit 1
fi
echo "=========================================="
echo ""

# 逐个验证自定义路由
log_info "验证自定义路由..."
# 注意：验证阶段必须容错。set -e + pipefail 下任一路由 curl 超时会让
# `n=$(curl | awk)` 赋值语句返回非零，导致脚本静默退出、后续路由全不测。
set +e
check() {
    local name="$1" path="$2" code n
    code=$(curl -sS -m 45 -o /tmp/_rss_check.xml -w "%{http_code}" \
           "http://127.0.0.1:${PORT}${path}?limit=5" 2>/dev/null) || code="000"
    n=$(awk -v RS='<item>' 'END{print NR-1}' /tmp/_rss_check.xml 2>/dev/null) || n=0
    [ -z "$n" ] && n=0
    if [ "$code" = "200" ] && [ "$n" -gt 0 ] 2>/dev/null; then
        echo "  ✅ $name  (${n} 条)"
    else
        echo "  ⚠️  $name  HTTP=${code} 条目=${n}  $path"
    fi
}

check "民航局 /caac/xwzx/mhyw"        "/caac/xwzx/mhyw"
check "中国民航网 /caacnews/1/1"       "/caacnews/1/1"
check "文旅部 /mct/whzx/whyw"          "/mct/whzx/whyw"
check "移民局 /nia/tzgg"               "/nia/tzgg"
check "空管局 /atmb"                   "/atmb"
check "旅游研究院 /ctaweb"             "/ctaweb"
check "环球旅讯 /traveldaily"          "/traveldaily"
check "本地宝 /bendibao/news/bj"       "/bendibao/news/bj"
check "每经 /nbd"                      "/nbd"
set -e

echo ""
echo " 💡 HTTP=000 表示超时（服务器到目标站点不通）；5xx 为路由报错；200 但 0 条为上游结构变化"
echo ""
echo "=========================================="
echo " 部署完成"
echo "=========================================="
echo " 安装目录: $INSTALL_DIR"
echo " 访问地址: http://<服务器IP>:$PORT"
echo " RSSHub commit: $(cd "$INSTALL_DIR" && git rev-parse --short HEAD)"
echo ""
if [ "$START_MODE" = "systemd" ]; then
    echo " 常用命令:"
    echo "   systemctl status rsshub        # 查看状态"
    echo "   systemctl restart rsshub       # 重启"
    echo "   systemctl stop rsshub          # 停止"
    echo "   journalctl -u rsshub -f        # 实时日志"
else
    echo " 常用命令:"
    echo "   tail -f $INSTALL_DIR/logs/nohup.log   # 日志"
    echo "   pkill -f 'dist/index.mjs'             # 停止"
fi
echo ""
echo " ⚠️  若服务器有防火墙，需放行端口:"
echo "   firewall-cmd --add-port=${PORT}/tcp --permanent && firewall-cmd --reload   # CentOS"
echo "   ufw allow ${PORT}/tcp                                                      # Ubuntu"
echo ""
echo " ⚠️  生产环境建议用 Nginx 反代 + HTTPS，不要直接暴露 1200 端口到公网"
echo ""
