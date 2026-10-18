#!/bin/bash
# ============================================================
# 修复已部署 RSSHub 的构建失败（服务器上执行）
#
# 适用场景：
#   build 报  ERROR: Unexpected "\x00"  /  ._index.ts  /  ._xxx.ts
#   原因：macOS 传输时混入的 AppleDouble 元数据文件（._ 前缀），
#        在 Linux 上被 esbuild 当成源码扫描，二进制内容导致解析崩溃。
#
# 用法：
#   sudo bash fix-build.sh                    # 清理 + 重建 + 确保服务运行 + 验证
#   sudo bash fix-build.sh --dir /data/rsshub # 指定安装目录
#   sudo bash fix-build.sh --port 8080        # 指定端口（.env 不存在时才生效）
#   sudo bash fix-build.sh --upgrade-node     # 同时把 Node 升到 22.22.2
#   sudo bash fix-build.sh --dry-run          # 只列出将被删除的文件，不实际删除
#   sudo bash fix-build.sh --skip-build       # 已构建成功时跳过重建，只补服务并启动
#
# 说明：若上次 deploy.sh 在 build 阶段中断，.env / systemd 服务都还没建，
#      本脚本会自动补齐并启动，无需重跑整个 deploy.sh。
# ============================================================
set -euo pipefail

INSTALL_DIR="/opt/rsshub"
PORT_OPT="1200"
UPGRADE_NODE=0
DRY_RUN=0
SKIP_BUILD=0
NODE_VERSION="22.22.2"
PNPM_FLAGS="--config.managePackageManagerVersions=false --config.updateNotifier=false"

if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_OFF='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_OFF=''
fi
log_info() { echo -e "${C_BLUE}[INFO]${C_OFF} $*"; }
log_ok()   { echo -e "${C_GREEN}[ OK ]${C_OFF} $*"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_OFF} $*"; }
log_err()  { echo -e "${C_RED}[FAIL]${C_OFF} $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)           INSTALL_DIR="$2"; shift 2 ;;
        --port)          PORT_OPT="$2"; shift 2 ;;
        --upgrade-node)  UPGRADE_NODE=1; shift ;;
        --dry-run)       DRY_RUN=1; shift ;;
        --skip-build)    SKIP_BUILD=1; shift ;;
        -h|--help)       sed -n '2,16p' "$0"; exit 0 ;;
        *)               log_err "未知参数: $1"; exit 1 ;;
    esac
done

[ -d "$INSTALL_DIR" ] || { log_err "目录不存在: $INSTALL_DIR"; exit 1; }

echo ""
echo "=========================================="
echo " RSSHub 构建修复"
echo " 目录: $INSTALL_DIR"
echo "=========================================="
echo ""

# ---------- 1. 扫描 macOS 垃圾文件 ----------
log_info "扫描 macOS 元数据文件（._* / .DS_Store）..."

# 只匹配 ._ 前缀的隐藏文件与 .DS_Store，不做任何宽泛删除
JUNK_LIST=$(find "$INSTALL_DIR" \
    \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) \
    -not -path '*/node_modules/.pnpm/*' 2>/dev/null || true)

JUNK_COUNT=$(echo "$JUNK_LIST" | grep -c . || true)

if [ "${JUNK_COUNT:-0}" -eq 0 ]; then
    log_ok "未发现 ._ / .DS_Store 文件"
else
    log_warn "发现 ${JUNK_COUNT} 个 macOS 元数据文件，前 20 个："
    echo "$JUNK_LIST" | head -20 | sed 's/^/    /'
    echo ""

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "--dry-run 模式，不删除。去掉该参数以实际清理。"
        exit 0
    fi

    log_info "清理中（这些是 macOS 的元数据，删除不影响任何源码）..."
    # 逐个精确删除，避免误伤
    echo "$JUNK_LIST" | while read -r f; do
        [ -n "$f" ] && rm -rf -- "$f"
    done
    log_ok "已清理 ${JUNK_COUNT} 个文件"
fi

# ---------- 2. 校验自定义路由文件确实还在 ----------
log_info "校验自定义路由文件完整性..."
MISSING=0
for f in \
    lib/routes/caac/xwzx.ts lib/routes/caac/namespace.ts \
    lib/routes/caacnews/index.ts lib/routes/caacnews/namespace.ts \
    lib/routes/mct/index.ts lib/routes/mct/namespace.ts \
    lib/routes/nia/index.ts lib/routes/nia/namespace.ts \
    lib/routes/atmb/index.ts lib/routes/atmb/namespace.ts \
    lib/routes/ctaweb/index.ts lib/routes/ctaweb/namespace.ts \
    lib/routes/traveldaily/index.ts lib/routes/traveldaily/namespace.ts \
    lib/routes/bendibao/news.ts lib/routes/nbd/index.ts ; do
    if [ ! -f "$INSTALL_DIR/$f" ]; then
        log_err "缺失: $f"
        MISSING=1
    fi
done
if [ "$MISSING" -eq 1 ]; then
    log_err "自定义路由不完整，请重新执行：bash deploy.sh --routes /tmp/rsshub-routes-*.tar.gz"
    exit 1
fi
log_ok "16 个自定义路由文件齐全"

# ---------- 3. Node 版本（可选升级） ----------
CUR_NODE=$(node -v 2>/dev/null || echo "none")
log_info "当前 Node: $CUR_NODE  （RSSHub 要求 ^22.22.2 或 ^24.15.0）"

ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

NODE_OK=0
case "$CUR_NODE" in
    v22.*) ver_ge "${CUR_NODE#v}" "22.22.2" && NODE_OK=1 ;;
    v24.*) ver_ge "${CUR_NODE#v}" "24.15.0" && NODE_OK=1 ;;
    v2[5-9].*|v[3-9]*) NODE_OK=1 ;;
esac

if [ "$NODE_OK" -eq 0 ]; then
    if [ "$UPGRADE_NODE" -eq 1 ]; then
        log_info "升级 Node 到 v${NODE_VERSION} ..."
        arch=$(uname -m); case "$arch" in x86_64|amd64) a="x64";; aarch64|arm64) a="arm64";; *) log_err "不支持架构 $arch"; exit 1;; esac
        tb="node-v${NODE_VERSION}-linux-${a}.tar.xz"
        cd /tmp
        curl -fsSL -m 300 -o "$tb" "https://registry.npmmirror.com/-/binary/node/v${NODE_VERSION}/${tb}" \
            || curl -fsSL -m 300 -O "https://nodejs.org/dist/v${NODE_VERSION}/${tb}"
        tar -xf "$tb" -C /opt && rm -f "$tb"
        ln -sf "/opt/node-v${NODE_VERSION}-linux-${a}/bin/node" /usr/local/bin/node
        ln -sf "/opt/node-v${NODE_VERSION}-linux-${a}/bin/npm"  /usr/local/bin/npm
        ln -sf "/opt/node-v${NODE_VERSION}-linux-${a}/bin/npx"  /usr/local/bin/npx
        export PATH="/opt/node-v${NODE_VERSION}-linux-${a}/bin:$PATH"
        hash -r
        log_ok "Node 已升级: $(node -v)"

        # Node 换了主目录，pnpm 需重装到新 prefix
        log_info "重装 pnpm 到新 Node 环境..."
        npm install -g "pnpm@10.34.5" --registry=https://registry.npmmirror.com --no-audit --no-fund >/dev/null 2>&1
        NPM_BIN="$(npm prefix -g)/bin"; export PATH="$NPM_BIN:$PATH"; hash -r
        log_ok "pnpm $(pnpm $PNPM_FLAGS --version)"
    else
        log_warn "Node 版本不满足要求（当前 $CUR_NODE）"
        log_warn "目前只是 WARN，通常仍能构建成功；若仍失败请加 --upgrade-node"
    fi
else
    log_ok "Node 版本符合要求"
fi

# ---------- 4. 重新构建 ----------
cd "$INSTALL_DIR"
if [ "$SKIP_BUILD" -eq 1 ]; then
    log_info "--skip-build：跳过构建"
    if [ ! -f "$INSTALL_DIR/dist/index.mjs" ]; then
        log_err "dist/index.mjs 不存在，不能跳过构建，请去掉 --skip-build"
        exit 1
    fi
else
    log_info "重新构建（服务器约 1~2 分钟）..."
    export PUPPETEER_SKIP_DOWNLOAD=true
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export CI=true
    pnpm $PNPM_FLAGS build
    log_ok "构建完成"
fi

# ---------- 5. 确保 .env / 运行用户 / 服务存在并启动 ----------
# 说明：上次 deploy.sh 在 build 阶段失败中断，第 7~10 步（.env、用户、systemd、启动）
#      根本没执行，所以这里要补齐，而不只是重启。

# 5.1 .env
if [ ! -f "$INSTALL_DIR/.env" ]; then
    log_info ".env 不存在，创建（端口 $PORT_OPT）..."
    cat > "$INSTALL_DIR/.env" <<EOF
PORT=$PORT_OPT
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
    log_ok ".env 已创建"
else
    log_ok ".env 已存在"
fi
PORT=$(grep -E '^PORT=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "$PORT_OPT")
PORT="${PORT:-$PORT_OPT}"

# 5.2 运行用户
SVC_USER="rsshub"
if [ "$(id -u)" -eq 0 ] && ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin "$SVC_USER" 2>/dev/null \
        || useradd -r -s /bin/false "$SVC_USER" 2>/dev/null \
        || SVC_USER="root"
fi
mkdir -p "$INSTALL_DIR/logs"
[ "$(id -u)" -eq 0 ] && chown -R "$SVC_USER":"$SVC_USER" "$INSTALL_DIR" 2>/dev/null || true

# 5.3 启动服务
NODE_BIN=$(command -v node)
HAS_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    HAS_SYSTEMD=1
fi

if [ "$HAS_SYSTEMD" -eq 1 ]; then
    if ! systemctl list-unit-files 2>/dev/null | grep -q '^rsshub.service'; then
        log_info "创建 systemd 服务..."
        cat > /etc/systemd/system/rsshub.service <<EOF
[Unit]
Description=RSSHub - RSS feed generator with custom CAAC routes
Documentation=https://docs.rsshub.app
After=network.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
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
    fi
    systemctl restart rsshub
    sleep 1
    if systemctl is-active --quiet rsshub; then
        log_ok "systemd 服务运行中"
    else
        log_err "systemd 启动失败，日志：journalctl -u rsshub -n 50 --no-pager"
        systemctl status rsshub --no-pager 2>/dev/null | head -15
    fi
else
    log_warn "未检测到 systemd，改用后台进程启动"
    pkill -f "$INSTALL_DIR/dist/index.mjs" 2>/dev/null || true
    sleep 1
    cd "$INSTALL_DIR"
    START_CMD="cd $INSTALL_DIR && NODE_ENV=production setsid nohup $NODE_BIN dist/index.mjs > logs/nohup.log 2>&1 &"
    if command -v runuser >/dev/null 2>&1 && [ "$SVC_USER" != "root" ]; then
        runuser -u "$SVC_USER" -- bash -c "$START_CMD"
    else
        bash -c "$START_CMD"
    fi
    log_ok "后台进程已启动"
fi

# ---------- 6. 验证 ----------

log_info "等待服务就绪（端口 $PORT）..."
READY=0
for i in $(seq 1 40); do
    curl -fsS -m 3 -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null && { READY=1; break; }
    sleep 1
done

echo ""
if [ "$READY" -ne 1 ]; then
    log_err "服务未就绪，开始诊断..."
    echo ""

    if [ "$HAS_SYSTEMD" -eq 1 ]; then
        echo "--- systemctl status ---"
        systemctl status rsshub --no-pager 2>/dev/null | head -12
        echo ""
        echo "--- journalctl 最近 30 行 ---"
        journalctl -u rsshub -n 30 --no-pager 2>/dev/null
    else
        echo "--- nohup.log 最近 30 行 ---"
        tail -30 "$INSTALL_DIR/logs/nohup.log" 2>/dev/null
    fi

    echo ""
    echo "--- 直接前台启动看实时报错（8 秒后强制退出）---"
    cd "$INSTALL_DIR"
    NODE_ENV=production timeout 8 "$NODE_BIN" dist/index.mjs 2>&1 | head -25

    echo ""
    log_err "仍未就绪。常见原因："
    echo "    1) 端口 $PORT 被占用：ss -lntp | grep $PORT"
    echo "    2) dist/index.mjs 缺失：ls -la $INSTALL_DIR/dist/index.mjs"
    echo "    3) .env 配置错误：cat $INSTALL_DIR/.env"
    exit 1
fi
log_ok "服务已就绪: http://127.0.0.1:${PORT}"

log_info "验证自定义路由..."
# 关键：验证阶段必须容错。set -e + pipefail 下，任一路由 curl 超时/5xx
# 会让 `n=$(curl | awk)` 的赋值语句返回非零，导致脚本静默退出、后续路由全不测。
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
        # 000 = 超时/连不上；5xx = 路由内部报错；200 但 0 条 = 上游站点结构变化
        echo -e "  ${C_YELLOW}⚠️${C_OFF}  $name  HTTP=${code} 条目=${n}"
    fi
}
check "民航局 /caac/xwzx/mhyw"  "/caac/xwzx/mhyw"
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
log_ok "修复完成"
echo ""
echo " 💡 说明：HTTP=000 表示超时（服务器到目标站点不通或太慢）"
echo "    HTTP=5xx 表示路由内部报错；HTTP=200 但 0 条表示上游站点结构变化"
echo "    若大面积超时且服务器在海外，跑 diag.sh 检查出网连通性"
echo ""
