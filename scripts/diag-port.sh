#!/usr/bin/env bash
#
# NebulaPanel 端口监听诊断
#
# 解决「容器没对外开端口」的排查：
#   1. host 网络模式下 docker ps 的 PORTS 列为空是正常的，需另验监听
#   2. core 在 stable 模式下从 ctl_conf(/usr/local/bin/npctl) 读 ORIGINAL_PORT，
#      不读 app.yaml，因此 port 配错或 npctl 未挂载都会导致异常
#
# 用法：
#   sudo bash scripts/diag-port.sh
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
DOCKER_DIR="${NP_HOME}/docker"
CTL_FILE="${NP_HOME}/conf/npctl"
APP_CONF="${NP_HOME}/conf/app.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
sec(){ printf "\n${BLUE}===== %s =====${NC}\n" "$*"; }

[ "$(id -u)" -eq 0 ] || { err "请用 root 运行"; exit 1; }

###############################################################################
sec "1. 配置文件"
###############################################################################
if [ -f "$CTL_FILE" ]; then
    ok "存在 $CTL_FILE"
    echo "  关键键值："
    grep -E '^(BASE_DIR|ORIGINAL_PORT|ORIGINAL_ENTRANCE|ORIGINAL_VERSION)=' "$CTL_FILE" | sed 's/^/    /'
    PORT_FROM_CTL="$(grep -E '^ORIGINAL_PORT=' "$CTL_FILE" | head -1 | cut -d= -f2 | tr -d '"'\''[:space:]')"
    echo "  解析端口：${PORT_FROM_CTL:-（空）}"
else
    err "缺少 $CTL_FILE —— core 在 stable 模式下会 panic 或使用错误端口"
    PORT_FROM_CTL=""
fi

echo ""
if [ -f "$APP_CONF" ]; then
    echo "  $APP_CONF 的 mode 与 port："
    grep -E '^\s*(mode|port|entrance):' "$APP_CONF" | sed 's/^/    /'
    MODE="$(grep -E '^\s*mode:' "$APP_CONF" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"'\''[:space:]')"
    echo "  解析 mode：${MODE:-（空）}"
    if [ "$MODE" = "stable" ]; then
        warn "  mode=stable → 端口取自 ctl_conf 的 ORIGINAL_PORT，不读本文件的 port"
    elif [ "$MODE" = "dev" ]; then
        info "  mode=dev → 端口取自本文件的 conn.port"
    fi
else
    err "缺少 $APP_CONF"
fi

###############################################################################
sec "2. 容器状态"
###############################################################################
cd "$DOCKER_DIR" 2>/dev/null || { err "找不到 $DOCKER_DIR"; exit 1; }

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else err "未找到 docker compose"; exit 1; fi

$DC ps 2>&1 | sed 's/^/  /'

echo ""
echo "  说明：network_mode: host 下 PORTS 列显示为空是正常的，"
echo "        容器直接占用宿主机端口，不经端口映射。"

###############################################################################
sec "3. core 是否成功监听"
###############################################################################
CORE_LOG="$($DC logs --tail=60 nebulapanel-core 2>&1)"

echo "  core 日志中的 listen 记录："
echo "$CORE_LOG" | grep -iE 'listen at|listen on' | tail -5 | sed 's/^/    /' || echo "    （无）"

echo ""
echo "  core 启动错误（如有）："
echo "$CORE_LOG" | grep -iE 'unknown command|panic|error.*bind|address already in use|permission denied' | tail -8 | sed 's/^/    /' || echo "    （无）"

if echo "$CORE_LOG" | grep -q 'unknown command "start"'; then
    err "  core 仍在报 unknown command start —— 镜像未重建，需 docker compose build"
fi

###############################################################################
sec "4. 宿主机监听端口"
###############################################################################
if command -v ss >/dev/null 2>&1; then
    echo "  所有 LISTEN 端口（含 NebulaPanel 相关）："
    ss -ltnp 2>/dev/null | grep -E ":(8700|9999|8080)" | sed 's/^/    /' || echo "    （未找到 8700/9999/8080 监听）"
    echo ""
    echo "  全部监听端口："
    ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | sort -u | sed 's/^/    /'
elif command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null | grep -E ":(8700|9999)" | sed 's/^/    /' || echo "    （未找到监听）"
else
    warn "  没有 ss 或 netstat，改用 /proc 检查"
    awk 'NR>1{split($2,a,":"); if(a[4]=="0A") print strtonum("0x" a[2])}' /proc/net/tcp 2>/dev/null | sort -u | sed 's/^/    端口 /' || true
fi

###############################################################################
sec "5. 容器内部监听（排除 host 网络的影响）"
###############################################################################
if docker ps --format '{{.Names}}' | grep -q '^nebulapanel-core$'; then
    echo "  容器内 ss/netstat："
    docker exec nebulapanel-core sh -c 'command -v ss >/dev/null && ss -ltn || (command -v netstat >/dev/null && netstat -ltn) || echo "容器内无 ss/netstat"' 2>/dev/null | sed 's/^/    /' || warn "  无法进入容器"
    echo ""
    echo "  容器内进程："
    docker exec nebulapanel-core sh -c 'ps aux 2>/dev/null || ps -ef 2>/dev/null' 2>/dev/null | head -10 | sed 's/^/    /' || warn "  无法读取进程"
else
    err "  nebulapanel-core 容器未运行"
fi

###############################################################################
sec "6. 本机连通性测试"
###############################################################################
TRY_PORT="${PORT_FROM_CTL:-8700}"
echo "  尝试本机访问 127.0.0.1:${TRY_PORT}"
if command -v curl >/dev/null 2>&1; then
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "http://127.0.0.1:${TRY_PORT}/" 2>/dev/null || echo 000)"
    if [ "$CODE" != "000" ]; then
        ok "  本机可达，HTTP 状态码 $CODE"
    else
        err "  本机不可达（连接失败）"
    fi
else
    warn "  无 curl，跳过"
fi

###############################################################################
sec "7. 防火墙"
###############################################################################
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "  firewalld 运行中"
    firewall-cmd --list-ports 2>/dev/null | sed 's/^/    已开放端口: /'
    firewall-cmd --list-services 2>/dev/null | sed 's/^/    已开放服务: /'
    if ! firewall-cmd --list-ports 2>/dev/null | grep -qw "${TRY_PORT}/tcp"; then
        warn "  ${TRY_PORT}/tcp 未在 firewalld 开放"
        echo "    放行命令：firewall-cmd --permanent --add-port=${TRY_PORT}/tcp && firewall-cmd --reload"
    fi
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "  ufw 运行中"
    ufw status 2>/dev/null | head -20 | sed 's/^/    /'
    if ! ufw status 2>/dev/null | grep -q "^${TRY_PORT}"; then
        warn "  ${TRY_PORT} 未在 ufw 放行"
        echo "    放行命令：ufw allow ${TRY_PORT}/tcp"
    fi
else
    echo "  firewalld / ufw 均未启用"
    if command -v iptables >/dev/null 2>&1; then
        echo "  iptables INPUT 链策略："
        iptables -L INPUT -n 2>/dev/null | head -5 | sed 's/^/    /'
    fi
fi

echo ""
echo "  云服务器还需检查安全组是否放行 ${TRY_PORT} 端口"

###############################################################################
sec "8. 结论与建议"
###############################################################################
echo ""
if echo "$CORE_LOG" | grep -q 'unknown command "start"'; then
    echo "  ▶ 首要问题：core 未启动成功（ENTRYPOINT 带 start）"
    echo "    修复：cd $DOCKER_DIR && docker compose down && docker compose build && docker compose up -d"
elif ! docker ps --format '{{.Names}}' | grep -q '^nebulapanel-core$'; then
    echo "  ▶ 首要问题：core 容器未运行"
    echo "    查看日志：docker compose logs --tail=80 nebulapanel-core"
elif [ -z "${PORT_FROM_CTL:-}" ]; then
    echo "  ▶ 首要问题：ctl_conf 缺少 ORIGINAL_PORT"
    echo "    修复：重新执行 install.sh 或手工在 $CTL_FILE 补上 ORIGINAL_PORT=8700"
else
    echo "  ▶ core 已在 ${TRY_PORT} 监听"
    echo "    若外网仍打不开，依次检查："
    echo "      1. 云厂商安全组是否放行 ${TRY_PORT}"
    echo "      2. 本机防火墙（上方第 7 节输出）"
    echo "      3. 安全入口路径是否正确：http://IP:${TRY_PORT}/<entrance>"
fi
echo ""
