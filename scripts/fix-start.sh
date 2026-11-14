#!/usr/bin/env bash
#
# NebulaPanel 容器启动与防火墙修复（无需重新编译二进制）
#
# 修复两个问题：
#   1. core 容器报 unknown command "start"
#      → Dockerfile 的 ENTRYPOINT 多了 start 参数
#   2. agent 报 unsupported firewall scope: ...:NEBULAPANEL_BASIC:input
#      → 二进制内的链名大小写比较 bug，需更换新二进制
#
# 用法：
#   sudo bash scripts/fix-start.sh          # 修复启动参数并重建容器
#
# 说明：本脚本不下载、不重编译，只修本地 Dockerfile 与 compose 后重建容器。
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
DOCKER_DIR="${NP_HOME}/docker"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
die(){ err "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行：sudo bash $0"
[ -d "$DOCKER_DIR" ] || die "找不到 $DOCKER_DIR，请确认安装目录"

echo "========================================"
echo " 修复 ENTRYPOINT 与容器启动"
echo "========================================"
echo ""

###############################################################################
# 1. 修正 Dockerfile 的 ENTRYPOINT
###############################################################################
fix_entrypoint() {
    local f="$1" name="$2"
    [ -f "$f" ] || { warn "$f 不存在，跳过"; return 1; }

    local before
    before="$(grep -E '^ENTRYPOINT' "$f" 2>/dev/null || echo '(无)')"
    echo "  $name 当前：$before"

    if ! grep -qE '"start"' "$f" 2>/dev/null; then
        ok "  $name 已无 start 参数，无需修改"
        return 0
    fi

    cp -f "$f" "${f}.bak.$(date +%s)"

    # 删掉 ENTRYPOINT 行上的 , "start"
    sed -i 's/\(ENTRYPOINT[^]]*\),[[:space:]]*"start"/\1/' "$f"

    local after
    after="$(grep -E '^ENTRYPOINT' "$f" 2>/dev/null || echo '(无)')"
    echo "  $name 修改后：$after"

    if grep -qE '"start"' "$f" 2>/dev/null; then
        err "  $name 修改失败"
        return 1
    fi
    ok "  $name 已修正"
    return 0
}

info "检查 Dockerfile..."
fix_entrypoint "${DOCKER_DIR}/Dockerfile.core"  "Dockerfile.core"  || true
fix_entrypoint "${DOCKER_DIR}/Dockerfile.agent" "Dockerfile.agent" || true

###############################################################################
# 2. 确保 npctl 挂载存在
###############################################################################
echo ""
info "检查 npctl 挂载..."

CTL_FILE="${NP_HOME}/conf/npctl"
COMPOSE="${DOCKER_DIR}/docker-compose.yml"

if [ ! -f "$CTL_FILE" ]; then
    warn "配置 ${CTL_FILE} 不存在，正在生成..."

    # 从 app.yaml 读配置
    P=9999; E=nebula; U=admin; W=""; D=/opt; L=zh; G=V1.0.0
    APP="${NP_HOME}/conf/app.yaml"
    if [ -f "$APP" ]; then
        v(){ grep -E "^\s*$1:" "$APP" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'; }
        t="$(v port)";       [ -n "$t" ] && P="$t"
        t="$(v entrance)";   [ -n "$t" ] && E="$t"
        t="$(v username)";   [ -n "$t" ] && U="$t"
        t="$(v password)";   [ -n "$t" ] && W="$t"
        t="$(v install_dir)";[ -n "$t" ] && D="$t"
        t="$(v language)";   [ -n "$t" ] && L="$t"
        t="$(v version)";    [ -n "$t" ] && G="$t"
    fi

    cat > "$CTL_FILE" <<EOF
#!/usr/bin/env bash
BASE_DIR=${D}
ORIGINAL_PORT=${P}
ORIGINAL_VERSION=${G}
ORIGINAL_USERNAME=${U}
ORIGINAL_PASSWORD=${W}
ORIGINAL_ENTRANCE=${E}
LANGUAGE=${L}
CHANGE_USER_INFO=
PANEL_EDITION=cn

set -euo pipefail
NP_HOME="${NP_HOME}"
NP_COMPOSE="\${NP_HOME}/docker/docker-compose.yml"
cmd=\${1:-help}
case \$cmd in
    start)   docker compose -f "\${NP_COMPOSE}" up -d ;;
    stop)    docker compose -f "\${NP_COMPOSE}" stop ;;
    restart) docker compose -f "\${NP_COMPOSE}" restart ;;
    status)  docker compose -f "\${NP_COMPOSE}" ps ;;
    logs)    docker compose -f "\${NP_COMPOSE}" logs -f --tail=200 ;;
    user-info)
        echo "访问地址：http://\$(hostname -I | awk '{print \$1}'):${P}/${E}"
        echo "账号：${U}"; echo "密码：${W}"; echo "版本：${G}" ;;
    version) echo "NebulaPanel ${G}" ;;
    *) echo "用法：npctl {start|stop|restart|status|logs|user-info|version}" ;;
esac
EOF
    chmod 755 "$CTL_FILE"
    ok "已生成 $CTL_FILE"
else
    ok "配置已存在：$CTL_FILE"
fi

# 补挂载
if grep -qF "/usr/local/bin/npctl" "$COMPOSE" 2>/dev/null; then
    ok "compose 已含 npctl 挂载"
else
    warn "compose 缺少 npctl 挂载，正在补..."
    BACKUP="${COMPOSE}.bak.$(date +%s)"
    cp -f "$COMPOSE" "$BACKUP"
    MOUNT="      - ${CTL_FILE}:/usr/local/bin/npctl:ro"
    awk -v line="$MOUNT" '
        /^[[:space:]]*volumes:[[:space:]]*$/ { in_vol=1; done=0; print; next }
        in_vol && /^[[:space:]]*- / { print; next }
        in_vol && !/^[[:space:]]*- / { if (!done) { print line; done=1 } in_vol=0 }
        { print }
        END { if (in_vol && !done) print line }
    ' "$BACKUP" > "$COMPOSE"

    CNT="$(grep -cF "/usr/local/bin/npctl" "$COMPOSE" 2>/dev/null || echo 0)"
    if [ "${CNT:-0}" -ge 2 ]; then
        ok "已为 ${CNT} 个容器添加挂载"
    else
        warn "只生效 ${CNT} 处，请手动补：$MOUNT"
    fi
fi

# 同步到系统 PATH
for d in /usr/local/bin /usr/bin; do
    [ -d "$d" ] || continue
    if cp -f "$CTL_FILE" "$d/npctl" 2>/dev/null; then
        chmod 755 "$d/npctl" 2>/dev/null
        ok "命令已安装：$d/npctl"
        break
    fi
done

###############################################################################
# 3. 重建并启动
###############################################################################
echo ""
info "重建容器..."

cd "$DOCKER_DIR" || die "无法进入 $DOCKER_DIR"

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    die "未找到 docker compose"
fi

# 强制重建，让新的 ENTRYPOINT 生效
${DC} up -d --force-recreate 2>&1 | sed 's/^/  /'

echo ""
info "等待 10 秒..."
sleep 10

echo ""
echo "--- 容器状态 ---"
${DC} ps 2>&1 | sed 's/^/  /'

echo ""
echo "--- core 日志（最后 30 行）---"
${DC} logs --tail=30 nebulapanel-core 2>&1 | sed 's/^/  /' | tee /tmp/np-core.log

echo ""
echo "--- agent 日志（最后 40 行）---"
${DC} logs --tail=40 nebulapanel-agent 2>&1 | sed 's/^/  /' | tee /tmp/np-agent2.log

echo ""
echo "========================================"
echo " 检查结果"
echo "========================================"

FAIL=0

if grep -q 'unknown command "start"' /tmp/np-core.log 2>/dev/null; then
    err "core 仍在报 unknown command start —— ENTRYPOINT 未生效，检查 Dockerfile"
    FAIL=1
else
    ok "core 无 start 参数错误"
fi

if grep -q 'unsupported firewall scope' /tmp/np-agent2.log 2>/dev/null; then
    warn "agent 仍有防火墙 scope 错误"
    echo "  这是二进制内部的大小写比较 bug，需要更换新二进制："
    echo "  从 GitHub Actions 下载 nebulapanel-linux-amd64，"
    echo "  替换资源站上的 NebulaPanel-agent-amd64 后重装。"
    echo "  该错误不影响面板主体功能，仅端口白名单迁移记录会跳过。"
else
    ok "agent 无防火墙 scope 错误"
fi

if grep -q "panic:" /tmp/np-agent2.log 2>/dev/null; then
    err "agent 仍有 panic"
    grep -A8 "panic:" /tmp/np-agent2.log | head -20 | sed 's/^/  /'
    FAIL=1
else
    ok "agent 无 panic"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    ok "修复完成，刷新页面访问面板"
else
    warn "仍有问题，请把上面日志发出来"
fi

echo ""
echo "  访问地址：http://$(hostname -I 2>/dev/null | awk '{print $1}'):$(grep -E '^ORIGINAL_PORT=' "$CTL_FILE" | cut -d= -f2)/$(grep -E '^ORIGINAL_ENTRANCE=' "$CTL_FILE" | cut -d= -f2)"
echo "  账号：$(grep -E '^ORIGINAL_USERNAME=' "$CTL_FILE" | cut -d= -f2)"
echo ""
