#!/bin/bash
# ============================================================
# 同步本地自定义路由到本仓库的 routes/ 目录（Mac 本机执行）
#
# 工作流：
#   1) 在 ~/WorkBuddy/.../RSSHub 里改好路由并本地验证通过
#   2) 跑本脚本 → 同步到 ../routes/
#   3) git commit & push
#   4) 服务器：cd /opt/rsshub-i2v && git pull
#              cd server-deploy && sudo bash deploy.sh --rebuild
#
# 用法：
#   bash export-routes.sh                      # 同步到 ../routes/
#   bash export-routes.sh --out /path/to/dir   # 指定输出目录
#   bash export-routes.sh --tarball            # 额外生成 tar.gz 包
# ============================================================
set -euo pipefail

LOCAL_RSSHUB="${LOCAL_RSSHUB:-$HOME/WorkBuddy/2026-09-18-09-55-46/RSSHub}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../routes"
MAKE_TARBALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --out)      OUT_DIR="$2"; shift 2 ;;
        --tarball)  MAKE_TARBALL=1; shift ;;
        *)          echo "未知参数: $1"; exit 1 ;;
    esac
done

[ -d "$LOCAL_RSSHUB" ] || { echo "❌ 找不到本地 RSSHub: $LOCAL_RSSHUB"; echo "   用 LOCAL_RSSHUB=/path/to/RSSHub $0 指定"; exit 1; }

cd "$LOCAL_RSSHUB"
COMMIT=$(git rev-parse HEAD)
echo "📌 本地 RSSHub commit: $COMMIT"

# ---------- 文件清单 ----------
NEW_ROUTES=(
    "lib/routes/caac/namespace.ts"        "lib/routes/caac/xwzx.ts"
    "lib/routes/caacnews/namespace.ts"    "lib/routes/caacnews/index.ts"
    "lib/routes/mct/namespace.ts"         "lib/routes/mct/index.ts"
    "lib/routes/nia/namespace.ts"         "lib/routes/nia/index.ts"
    "lib/routes/atmb/namespace.ts"        "lib/routes/atmb/index.ts"
    "lib/routes/ctaweb/namespace.ts"      "lib/routes/ctaweb/index.ts"
    "lib/routes/traveldaily/namespace.ts" "lib/routes/traveldaily/index.ts"
)
MODIFIED_ROUTES=(
    "lib/routes/bendibao/news.ts"
    "lib/routes/nbd/index.ts"
)
ALL_FILES=("${NEW_ROUTES[@]}" "${MODIFIED_ROUTES[@]}")

# ---------- 校验 ----------
MISSING=0
for f in "${ALL_FILES[@]}"; do
    [ -f "$f" ] || { echo "❌ 缺失: $f"; MISSING=1; }
done
[ "$MISSING" -eq 1 ] && exit 1

# ---------- 同步 ----------
mkdir -p "$OUT_DIR"
for f in "${ALL_FILES[@]}"; do
    mkdir -p "$OUT_DIR/$(dirname "$f")"
    cp "$f" "$OUT_DIR/$f"
done

echo "$COMMIT" > "$OUT_DIR/COMMIT"

cat > "$OUT_DIR/MANIFEST.txt" <<EOF
同步时间: $(date '+%Y-%m-%d %H:%M:%S')
RSSHub commit: $COMMIT
路由数量: 7 个新增命名空间 + 2 个修改的官方路由

新增命名空间:
  caac          中国民用航空局     /caac/xwzx/:channel
  caacnews      中国民航网         /caacnews/:channel
  mct           文化和旅游部       /mct/:category
  nia           国家移民管理局     /nia/tzgg
  atmb          民航局空管局       /atmb
  ctaweb        中国旅游研究院     /ctaweb
  traveldaily   环球旅讯           /traveldaily/:channel

修改的官方路由:
  bendibao/news.ts   本地宝（修复失效选择器）
  nbd/index.ts       每日经济新闻（修复失效选择器）
EOF

# 防御：清掉可能混入的 macOS 垃圾文件（._ 前缀）
# 这些含二进制 \x00，Linux 上会被 esbuild 当源码扫描导致构建崩溃
find "$OUT_DIR" \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "✅ 已同步 ${#ALL_FILES[@]} 个文件到: $(cd "$OUT_DIR" && pwd)"
echo "🔒 版本锚点: $COMMIT"
echo ""

# ---------- 可选：额外打 tar.gz ----------
if [ "$MAKE_TARBALL" -eq 1 ]; then
    TB="$SCRIPT_DIR/rsshub-routes-$(date +%Y%m%d).tar.gz"
    tar -czf "$TB" -C "$OUT_DIR" .
    echo "📦 额外生成: $TB"
    echo ""
fi

# ---------- 提示 ----------
echo "下一步："
echo "  cd $(cd "$OUT_DIR/.." && pwd)"
echo "  git add -A && git commit -m '更新自定义路由 (RSSHub ${COMMIT:0:12})'"
echo "  git push"
echo ""
echo "服务器侧："
echo "  cd /opt/rsshub-i2v && git pull"
echo "  cd server-deploy && sudo bash deploy.sh --rebuild"
