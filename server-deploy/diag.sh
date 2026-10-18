#!/bin/bash
# ============================================================
# RSSHub 出网连通性诊断（服务器上执行）
#
# 用途：当自定义路由大面积超时（HTTP=000）时，
#      判断到底是「服务器到目标站点不通」还是「路由代码问题」
#
# 用法：
#   bash diag.sh                    # 完整诊断
#   bash diag.sh --dir /data/rsshub # 指定安装目录
#   bash diag.sh --skip-routes      # 只测出网，不测 RSSHub 路由
# ============================================================
set -uo pipefail   # 注意：诊断脚本全程容错，不用 -e

INSTALL_DIR="/opt/rsshub"
SKIP_ROUTES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)          INSTALL_DIR="$2"; shift 2 ;;
        --skip-routes)  SKIP_ROUTES=1; shift ;;
        *)              echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -t 1 ]; then
    C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_BLUE='\033[0;34m'; C_OFF='\033[0m'
else
    C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''; C_OFF=''
fi

PORT=$(grep -E '^PORT=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
PORT="${PORT:-1200}"

echo ""
echo "=========================================="
echo " RSSHub 出网连通性诊断"
echo "=========================================="

# ---------- 1. 服务器位置 ----------
echo ""
echo -e "${C_BLUE}[1] 服务器出口位置${C_OFF}"
PUB_IP=$(curl -sS -m 8 https://api.ipify.org 2>/dev/null || curl -sS -m 8 https://ifconfig.me 2>/dev/null || echo "未知")
echo "    公网 IP: ${PUB_IP}"
GEO=$(curl -sS -m 10 "https://ipapi.co/${PUB_IP}/json/" 2>/dev/null)
if [ -n "$GEO" ]; then
    COUNTRY=$(echo "$GEO" | grep -o '"country_name" *: *"[^"]*"' | cut -d'"' -f4)
    CITY=$(echo "$GEO" | grep -o '"city" *: *"[^"]*"' | cut -d'"' -f4)
    echo "    地理位置: ${COUNTRY} ${CITY}"
    case "$COUNTRY" in
        *China*|*中国*) echo -e "    ${C_GREEN}境内服务器 → 访问国内站点应正常${C_OFF}" ;;
        *) echo -e "    ${C_YELLOW}境外服务器 → 访问国内政府站点可能慢/被拦截，这是超时主因${C_OFF}" ;;
    esac
fi

# ---------- 2. 目标站点连通性 ----------
echo ""
echo -e "${C_BLUE}[2] RSSHub 路由的目标站点连通性${C_OFF}"
printf "    %-26s %-8s %-10s %s\n" "站点" "HTTP" "耗时" "状态"
echo "    ------------------------------------------------------------"

# 站点 -> 对应路由
TARGETS=(
    "https://www.caac.gov.cn|民航局 /caac"
    "http://www.caacnews.com.cn|中国民航网 /caacnews"
    "https://www.mct.gov.cn|文旅部 /mct"
    "https://www.nia.gov.cn|移民局 /nia"
    "http://www.atmb.net.cn|空管局 /atmb"
    "http://www.ctaweb.org.cn|旅游研究院 /ctaweb"
    "https://www.traveldaily.cn|环球旅讯 /traveldaily"
    "http://bj.bendibao.com|本地宝 /bendibao"
    "https://www.nbd.com.cn|每经 /nbd"
)

SLOW=0
for entry in "${TARGETS[@]}"; do
    url="${entry%%|*}"
    label="${entry##*|}"
    # 超时 20s（境外访问国内站点可能偏慢，10s 容易误判）
    # 关键：把 curl 的 stderr 留到文件，失败时打印具体原因，
    # 否则 "000" 无法区分 DNS 失败 / 连接被重置 / 真超时
    rm -f /tmp/_diag_err
    result=$(curl -sS -m 20 -o /dev/null -L \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36" \
        -w "%{http_code}|%{time_total}" "$url" 2>/tmp/_diag_err) || result="000|0"
    code="${result%%|*}"
    t="${result##*|}"

    case "$code" in
        200|301|302) status="${C_GREEN}通${C_OFF}";;
        000)
            SLOW=$((SLOW+1))
            errmsg=$(tr -d '\n' < /tmp/_diag_err 2>/dev/null | sed 's/.*curl: *//' | cut -c1-45)
            # 按 curl 错误码给出可读原因
            case "$errmsg" in
                "(6)"*)  reason="DNS解析失败" ;;
                "(7)"*)  reason="连接被拒(站点/网络封锁)" ;;
                "(28)"*) reason="超时(太慢或丢包)" ;;
                "(35)"*) reason="TLS握手失败" ;;
                "(51)"*) reason="证书校验失败" ;;
                *)       reason="连接失败" ;;
            esac
            status="${C_RED}${reason}${C_OFF}"
            ;;
        403|429)     status="${C_YELLOW}被拦截${C_OFF}"; SLOW=$((SLOW+1));;
        *)           status="${C_YELLOW}异常${C_OFF}"; SLOW=$((SLOW+1));;
    esac
    printf "    %-26s %-8s %-10s %b\n" "$label" "$code" "${t}s" "$status"
done

# ---------- 3. RSSHub 路由实测 ----------
if [ "$SKIP_ROUTES" -eq 0 ]; then
    echo ""
    echo -e "${C_BLUE}[3] RSSHub 路由实测（RSSHub 端口 ${PORT}）${C_OFF}"
    if ! curl -fsS -m 5 -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null; then
        echo -e "    ${C_RED}RSSHub 服务未运行，跳过路由测试${C_OFF}"
        echo "    启动: systemctl restart rsshub"
    else
        printf "    %-30s %-8s %-8s %s\n" "路由" "HTTP" "条目" "状态"
        echo "    --------------------------------------------------------------"
        ROUTES=(
            "/caac/xwzx/mhyw|民航局"
            "/caacnews/1/1|中国民航网"
            "/mct/whzx/whyw|文旅部"
            "/nia/tzgg|移民局"
            "/atmb|空管局"
            "/ctaweb|旅游研究院"
            "/traveldaily|环球旅讯"
            "/bendibao/news/bj|本地宝"
            "/nbd|每经"
        )
        for entry in "${ROUTES[@]}"; do
            path="${entry%%|*}"
            label="${entry##*|}"
            code=$(curl -sS -m 45 -o /tmp/_diag.xml -w "%{http_code}" \
                   "http://127.0.0.1:${PORT}${path}?limit=5" 2>/dev/null) || code="000"
            n=$(awk -v RS='<item>' 'END{print NR-1}' /tmp/_diag.xml 2>/dev/null) || n=0
            [ -z "$n" ] && n=0
            if [ "$code" = "200" ] && [ "$n" -gt 0 ] 2>/dev/null; then
                st="${C_GREEN}正常${C_OFF}"
            elif [ "$code" = "000" ]; then
                st="${C_RED}超时${C_OFF}"
            else
                st="${C_YELLOW}异常${C_OFF}"
            fi
            printf "    %-30s %-8s %-8s %b\n" "$label" "$code" "$n" "$st"
        done
    fi
fi

# ---------- 4. 结论与建议 ----------
echo ""
echo "=========================================="
echo " 结论"
echo "=========================================="

if [ "$SLOW" -eq 0 ]; then
    echo -e "${C_GREEN}所有目标站点可达。${C_OFF}"
    echo "若路由仍返回 0 条，多半是上游站点结构变化，需更新路由选择器。"
else
    echo -e "${C_YELLOW}有 ${SLOW} 个目标站点不可达或被拦截。${C_OFF}"
    echo ""
    echo "这是「服务器出网」问题，不是路由代码问题——改代码无解。可选方案："
    echo ""
    echo "  方案 A（推荐，最彻底）：换用境内服务器部署"
    echo "    民航类数据源几乎都在国内，境内服务器延迟低、不会被拦。"
    echo ""
    echo "  方案 B：只给不通的站点配代理（需自备可用代理）"
    echo "    在 $INSTALL_DIR/.env 追加："
    echo "      PROXY_URI=http://<代理地址>:<端口>"
    echo "      PROXY_URL_REGEX=^(?!.*atmb\\\\.net\\\\.cn).*\$   # 注意：这是「排除」写法"
    echo ""
    echo "    更简单——只代理特定域名，把正则写成匹配该域名："
    echo "      PROXY_URL_REGEX=atmb\\\\.net\\\\.cn"
    echo "    然后: systemctl restart rsshub"
    echo ""
    echo "  方案 C：放弃该源"
    echo "    若该源优先级不高（如空管局为 P1），直接从订阅列表去掉即可。"
    echo ""
    echo "  如何判断是哪种："
    echo "    (6) DNS解析失败     → 换 DNS（如 8.8.8.8 / 223.5.5.5）"
    echo "    (7) 连接被拒        → 站点对境外 IP 封锁，只能换境内服务器或走代理"
    echo "    (28) 超时           → 网络慢，可调大 REQUEST_TIMEOUT 或走代理"
    echo "    (35) TLS握手失败    → 站点可能只支持 http，检查路由里的协议"
fi
echo ""
