#!/usr/bin/env bash
#
# NebulaPanel agent crash-loop 现场修复脚本
#
# 适用症状：
#   panic: open /usr/local/bin/npctl: no such file or directory
#   （agent 容器反复重启）
#
# 原因：
#   agent 启动时 initBaseInfo() 会读 /usr/local/bin/npctl 作为配置文件，
#   取其中的 BASE_DIR 与 ORIGINAL_VERSION。
#   该文件在宿主机创建失败（EPERM），且 compose 未挂载进容器，
#   于是 agent 读不到 → panic → 重启 → 再 panic。
#
# 本脚本做三件事（不重新下载、不重新构建镜像）：
#   1. 在 /opt/NebulaPanel/conf/npctl 生成配置文件（含键值行）
#   2. 给 docker-compose.yml 补上挂载卷
#   3. 重启容器并验证 agent 是否还 panic
#
# 用法：
#   sudo bash scripts/fix-agent.sh
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
CONF_DIR="${NP_HOME}/conf"
DOCKER_DIR="${NP_HOME}/docker"
COMPOSE="${DOCKER_DIR}/docker-compose.yml"
CTL_FILE="${CONF_DIR}/npctl"
APP_CONF="${CONF_DIR}/app.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
die(){ err "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行：sudo bash $0"

echo "========================================"
echo " NebulaPanel agent 修复"
echo "========================================"
echo ""

[ -d "$NP_HOME" ] || die "安装目录不存在：$NP_HOME"
[ -f "$COMPOSE" ] || die "未找到 $COMPOSE，请确认安装目录"

###############################################################################
# 1. 从 app.yaml 读取配置
###############################################################################
info "读取现有配置..."

NP_PORT="9999"; NP_ENTRANCE="nebula"; NP_USERNAME="admin"; NP_PASSWORD=""
NP_INSTALL_DIR="/opt"; NP_LANGUAGE="zh"; NP_VERSION="V1.0.0"

if [ -f "$APP_CONF" ]; then
    v() { grep -E "^\s*$1:" "$APP_CONF" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'; }
    P="$(v port)";       [ -n "$P" ] && NP_PORT="$P"
    E="$(v entrance)";   [ -n "$E" ] && NP_ENTRANCE="$E"
    U="$(v username)";   [ -n "$U" ] && NP_USERNAME="$U"
    W="$(v password)";   [ -n "$W" ] && NP_PASSWORD="$W"
    D="$(v install_dir)";[ -n "$D" ] && NP_INSTALL_DIR="$D"
    L="$(v language)";   [ -n "$L" ] && NP_LANGUAGE="$L"
    G="$(v version)";    [ -n "$G" ] && NP_VERSION="$G"
    ok "端口=$NP_PORT  入口=$NP_ENTRANCE  账号=$NP_USERNAME  安装目录=$NP_INSTALL_DIR"
else
    warn "$APP_CONF 不存在，使用默认值"
fi

# 若已从 /usr/local/bin/npctl 存在，优先取其中的 BASE_DIR
if [ -f /usr/local/bin/npctl ]; then
    EXISTING_BD="$(grep -E '^BASE_DIR=' /usr/local/bin/npctl 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'\''' | tr -d '[:space:]')"
    if [ -n "$EXISTING_BD" ]; then
        NP_INSTALL_DIR="$EXISTING_BD"
        info "使用现有 npctl 中的 BASE_DIR=$NP_INSTALL_DIR"
    fi
fi

###############################################################################
# 2. 生成配置文件
###############################################################################
info "生成 ${CTL_FILE} ..."
mkdir -p "$CONF_DIR"

cat > "$CTL_FILE" <<EOF
#!/usr/bin/env bash
#
# NebulaPanel 管理命令行 (npctl)
# 顶部键值行同时作为程序配置文件，请勿删除或改动格式。

BASE_DIR=${NP_INSTALL_DIR}
ORIGINAL_PORT=${NP_PORT}
ORIGINAL_VERSION=${NP_VERSION}
ORIGINAL_USERNAME=${NP_USERNAME}
ORIGINAL_PASSWORD=${NP_PASSWORD}
ORIGINAL_ENTRANCE=${NP_ENTRANCE}
LANGUAGE=${NP_LANGUAGE}
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
        echo "访问地址：http://\$(hostname -I | awk '{print \$1}'):${NP_PORT}/${NP_ENTRANCE}"
        echo "账号：${NP_USERNAME}"
        echo "密码：${NP_PASSWORD}"
        echo "版本：${NP_VERSION}"
        ;;
    version) echo "NebulaPanel ${NP_VERSION}" ;;
    *) echo "用法：npctl {start|stop|restart|status|logs|user-info|version}" ;;
esac
EOF
chmod 755 "$CTL_FILE"
ok "已写入 $CTL_FILE"

# 语法自检
bash -n "$CTL_FILE" && ok "语法检查通过" || die "生成的 npctl 语法有误"

# 尽力复制到系统 PATH
for d in /usr/local/bin /usr/bin /bin; do
    [ -d "$d" ] || continue
    t="$d/npctl"
    if cp -f "$CTL_FILE" "$t" 2>/dev/null; then
        chmod 755 "$t" 2>/dev/null
        ok "已安装命令：$t"
        break
    fi
done

###############################################################################
# 3. 修补 docker-compose.yml
###############################################################################
echo ""
info "检查 docker-compose.yml 挂载..."

MOUNT_LINE="      - ${CTL_FILE}:/usr/local/bin/npctl:ro"

# 备份
BACKUP="${COMPOSE}.bak.$(date +%s)"
cp -f "$COMPOSE" "$BACKUP"
info "已备份：$BACKUP"

if grep -qF "/usr/local/bin/npctl" "$COMPOSE"; then
    ok "已存在 npctl 挂载，无需修补"
else
    # 在每个 service 的 volumes 段落末尾插入一行挂载。
    # 注意 done 标记必须在遇到新的 volumes: 时重置，
    # 否则只会插入到第一个 service。
    awk -v line="$MOUNT_LINE" '
        /^[[:space:]]*volumes:[[:space:]]*$/ { in_vol=1; done=0; print; next }
        in_vol && /^[[:space:]]*- / { print; next }
        in_vol && !/^[[:space:]]*- / {
            if (!done) { print line; done=1 }
            in_vol=0
        }
        { print }
        END { if (in_vol && !done) print line }
    ' "$BACKUP" > "$COMPOSE"

    COUNT="$(grep -cF "/usr/local/bin/npctl" "$COMPOSE" 2>/dev/null || echo 0)"
    if [ "${COUNT:-0}" -ge 2 ]; then
        ok "已为 ${COUNT} 个容器添加挂载"
    else
        warn "自动修补只生效 ${COUNT} 处（期望 2），请手动检查 volumes"
        echo "  需要添加的行：$MOUNT_LINE"
    fi
fi

echo ""
echo "--- 修补后的 volumes 段 ---"
sed -n '/volumes:/,/^[^ ]/p' "$COMPOSE" | head -40 | sed 's/^/  /'

###############################################################################
# 4. 重启并验证
###############################################################################
echo ""
info "重启容器..."
cd "$DOCKER_DIR" || die "无法进入 $DOCKER_DIR"

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    die "未找到 docker compose"
fi

${DC} up -d 2>&1 | sed 's/^/  /'

echo ""
info "等待 8 秒让 agent 初始化..."
sleep 8

echo ""
echo "--- 容器状态 ---"
${DC} ps 2>&1 | sed 's/^/  /'

echo ""
echo "--- agent 最近日志（应无 panic） ---"
if ${DC} logs --tail=60 nebulapanel-agent 2>&1 | tee /tmp/np-agent.log | sed 's/^/  /'; then
    :
fi

echo ""
if grep -q "panic:" /tmp/np-agent.log 2>/dev/null; then
    err "agent 仍然 panic："
    grep -A5 "panic:" /tmp/np-agent.log | head -20 | sed 's/^/  /'
    echo ""
    echo "  请把以上内容发出来，需要进一步排查"
    exit 1
fi

RUNNING="$(${DC} ps --status running 2>/dev/null | grep -c nebulapanel-agent || echo 0)"
if [ "${RUNNING:-0}" -ge 1 ]; then
    ok "agent 已正常运行"
else
    warn "agent 未处于 running 状态，请检查上方日志"
fi

echo ""
echo "========================================"
ok "修复完成"
echo "========================================"
echo ""
echo "  访问地址：http://$(hostname -I 2>/dev/null | awk '{print $1}'):${NP_PORT}/${NP_ENTRANCE}"
echo "  账号：${NP_USERNAME}"
echo ""
echo "  管理命令：npctl status / npctl logs / npctl user-info"
echo ""
