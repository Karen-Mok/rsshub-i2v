#!/bin/bash
# ============================================================
# 导出本地自定义 RSSHub 路由（在 Mac 本机执行）
#
# 用途：把本机写好/修改过的路由打包，供远程 Linux 服务器部署使用
# 产出：rsshub-routes-<日期>.tar.gz + 版本锚点 COMMIT 文件
# ============================================================
set -euo pipefail

# 关键：禁止 macOS tar 生成 AppleDouble 元数据文件（._ 前缀）
# 这些文件含二进制内容，传到 Linux 后会被 esbuild 当源码扫描，
# 报 "Unexpected \x00" 导致构建直接失败
export COPYFILE_DISABLE=1

LOCAL_RSSHUB="${LOCAL_RSSHUB:-/Users/karenmok/WorkBuddy/2026-09-18-09-55-46/RSSHub}"
OUT_DIR="${OUT_DIR:-/Users/karenmok/WorkBuddy/2026-09-18-09-55-46/server-deploy}"
STAMP=$(date +%Y%m%d)

if [ ! -d "$LOCAL_RSSHUB" ]; then
    echo "❌ 找不到本地 RSSHub 目录: $LOCAL_RSSHUB"
    echo "   请用 LOCAL_RSSHUB=/path/to/RSSHub $0 指定"
    exit 1
fi

cd "$LOCAL_RSSHUB"

# 版本锚点：服务器上必须 checkout 到同一 commit，否则路由代码可能不兼容
COMMIT=$(git rev-parse HEAD)
echo "📌 本地 RSSHub commit: $COMMIT"

# ---- 需要迁移的文件清单 ----
# 7 个新增命名空间（各含 namespace.ts + 路由文件）
NEW_ROUTES=(
    "lib/routes/caac/namespace.ts"
    "lib/routes/caac/xwzx.ts"
    "lib/routes/caacnews/namespace.ts"
    "lib/routes/caacnews/index.ts"
    "lib/routes/mct/namespace.ts"
    "lib/routes/mct/index.ts"
    "lib/routes/nia/namespace.ts"
    "lib/routes/nia/index.ts"
    "lib/routes/atmb/namespace.ts"
    "lib/routes/atmb/index.ts"
    "lib/routes/ctaweb/namespace.ts"
    "lib/routes/ctaweb/index.ts"
    "lib/routes/traveldaily/namespace.ts"
    "lib/routes/traveldaily/index.ts"
)
# 2 个修改的内置路由
MODIFIED_ROUTES=(
    "lib/routes/bendibao/news.ts"
    "lib/routes/nbd/index.ts"
)
ALL_FILES=("${NEW_ROUTES[@]}" "${MODIFIED_ROUTES[@]}")

# ---- 校验文件都存在 ----
MISSING=0
for f in "${ALL_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "❌ 缺失文件: $f"
        MISSING=1
    fi
done
[ "$MISSING" -eq 1 ] && exit 1

# ---- 打包 ----
TMP=$(mktemp -d)
mkdir -p "$TMP/routes"

for f in "${ALL_FILES[@]}"; do
    mkdir -p "$TMP/routes/$(dirname "$f")"
    cp "$f" "$TMP/routes/$f"
done

echo "$COMMIT" > "$TMP/COMMIT"

cat > "$TMP/MANIFEST.txt" <<EOF
导出时间: $(date '+%Y-%m-%d %H:%M:%S')
RSSHub commit: $COMMIT
路由数量: 7 个新增命名空间 + 2 个修改的官方路由

新增命名空间（需整目录复制）:
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

# 兜底：清掉可能已混入的 macOS 垃圾文件
find "$TMP" \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) -exec rm -rf {} + 2>/dev/null || true

TARBALL="$OUT_DIR/rsshub-routes-$STAMP.tar.gz"
tar -czf "$TARBALL" \
    --exclude='._*' --exclude='.DS_Store' --exclude='__MACOSX' \
    -C "$TMP" routes COMMIT MANIFEST.txt
rm -rf "$TMP"

# 自检：包内不应有任何 ._ 文件
if tar -tzf "$TARBALL" | grep -q '/\._'; then
    echo "❌ 包内仍含 AppleDouble 文件，请检查本地目录"
    exit 1
fi

echo ""
echo "✅ 已导出: $TARBALL"
echo ""
echo "📦 包含 ${#ALL_FILES[@]} 个文件（新增 ${#NEW_ROUTES[@]} / 修改 ${#MODIFIED_ROUTES[@]}）"
echo "🔒 版本锚点 commit: $COMMIT"
echo ""
echo "下一步 —— 上传到服务器："
echo "  scp $TARBALL <user>@<server>:/tmp/"
echo "  scp $OUT_DIR/deploy.sh <user>@<server>:/tmp/"
echo ""
echo "然后在服务器上执行："
echo "  bash /tmp/deploy.sh"
