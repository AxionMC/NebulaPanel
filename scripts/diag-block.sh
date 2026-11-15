#!/usr/bin/env bash
#
# NebulaPanel 端口外网不通 —— 定位被谁拦截
#
# 适用：本机 ss 能看到监听、ufw 已放行，但外网访问超时。
# 常见于同时装了宝塔面板（BT-Panel）的服务器：
#   宝塔会在 iptables 中插入自己的链（IN_BT / bt_ip_filter），
#   并接管 ufw，导致 ufw allow 的端口实际仍被 DROP。
#
# 用法：
#   sudo bash scripts/diag-block.sh
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
sec(){ printf "\n${BLUE}===== %s =====${NC}\n" "$*"; }

[ "$(id -u)" -eq 0 ] || { err "请用 root 运行"; exit 1; }

# 读取实际端口
PORT="$(grep -E '^ORIGINAL_PORT=' "$NP_HOME/conf/npctl" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"'\''[:space:]')"
PORT="${PORT:-7800}"

echo "================================================================"
echo " 端口外网不通定位    目标端口: $PORT"
echo "================================================================"

###############################################################################
sec "1. 本机监听确认"
if ss -ltn 2>/dev/null | grep -q ":$PORT "; then
    ok "本机已在 $PORT 监听"
    ss -ltnp 2>/dev/null | grep ":$PORT "
else
    err "本机未在 $PORT 监听，请先解决服务启动问题"
    exit 1
fi

echo ""
info "本机自测："
CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)
echo "  http://127.0.0.1:$PORT/  →  HTTP ${CODE:-000}"

###############################################################################
sec "2. ufw 规则"
if command -v ufw >/dev/null 2>&1; then
    ufw status 2>/dev/null | grep -E "^(Status|$PORT)" || warn "ufw 中未见 $PORT 规则"
else
    warn "未安装 ufw"
fi

###############################################################################
sec "3. iptables 拦截链分析"
info "INPUT 链策略与跳转："
iptables -L INPUT -n --line-numbers 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
info "检查宝塔相关链（IN_BT / bt_ip_filter）："
for chain in IN_BT IN_AN INPUT_BT bt_ip_filter; do
    if iptables -L "$chain" -n 2>/dev/null | head -3 | grep -q 'Chain'; then
        warn "发现链 $chain："
        iptables -L "$chain" -n --line-numbers 2>/dev/null | head -25 | sed 's/^/    /'
    fi
done

echo ""
info "综合规则中与 $PORT 相关的条目："
iptables-save 2>/dev/null | grep -E "$PORT" | sed 's/^/  /' || echo "  （iptables-save 中无该端口规则）"

echo ""
info "nftables 规则（若启用）："
if command -v nft >/dev/null 2>&1; then
    nft list ruleset 2>/dev/null | grep -E "dport $PORT|$PORT " | head -10 | sed 's/^/  /' || echo "  （无相关规则）"
else
    echo "  nft 未安装"
fi

###############################################################################
sec "4. 实测：临时放行测试"
echo "  下面会临时在 iptables INPUT 顶部插入 ACCEPT 规则，测试是否为防火墙拦截。"
echo "  测试完成后会自动删除，不影响现有配置。"
echo ""

read -rp "  是否执行临时放行测试？[y/N]: " REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    info "插入临时规则：iptables -I INPUT 1 -p tcp --dport $PORT -j ACCEPT"
    if iptables -I INPUT 1 -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
        ok "已插入，等待 2 秒后从外部测试"
        sleep 2
        echo ""
        echo "  请现在用浏览器或手机流量访问："
        echo "    http://<公网IP>:$PORT/nebula"
        echo ""
        read -rp "  能访问吗？(y=能，n=不能) [y/N]: " RES
        info "删除临时规则..."
        iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null && ok "已删除" || warn "删除失败，请手动检查"

        echo ""
        if [[ "$RES" =~ ^[Yy]$ ]]; then
            ok "确认：是 iptables 拦截导致的"
            echo ""
            echo "  永久放行方案（二选一）："
            echo "    A) 若用宝塔：面板 → 安全 → 放行端口 $PORT"
            echo "    B) 手工持久化："
            echo "         iptables -I INPUT 1 -p tcp --dport $PORT -j ACCEPT"
            echo "         apt install -y iptables-persistent && netfilter-persistent save"
        else
            warn "不是本机 iptables 的问题 → 大概率是云厂商安全组"
            echo ""
            echo "  请到云控制台（华为云/阿里云/AWS 等）的安全组/防火墙中"
            echo "  为入方向添加 TCP $PORT 放行规则。"
        fi
    else
        warn "插入规则失败，跳过测试"
    fi
else
    info "已跳过临时放行测试"
fi

###############################################################################
sec "5. 云安全组检查提示"
echo "  本机无法检测云安全组，请到控制台确认入方向规则包含："
echo "    协议: TCP    端口: $PORT    源: 0.0.0.0/0（或你的 IP）"
echo ""
echo "  已开放端口的机器通常 22/80/443 都在安全组白名单中，"
echo "  新端口 $PORT 需要单独添加。"

###############################################################################
sec "6. 结论"
echo ""
if cur_ip=$(hostname -I 2>/dev/null | awk '{print $1}'); then
    echo "  面板地址：http://${cur_ip}:${PORT}/nebula"
    echo "  （若上面这一步本机能通、外网不通，就是防火墙或安全组）"
fi
echo ""
