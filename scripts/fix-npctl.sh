#!/usr/bin/env bash
#
# NebulaPanel npctl 安装诊断与修复工具
#
# 用途：当 install.sh 在生成 /usr/local/bin/npctl 时报
#       "Operation not permitted" 时，用本脚本定位并修复
#
# 用法：
#   sudo bash scripts/fix-npctl.sh            # 诊断 + 自动修复
#   sudo bash scripts/fix-npctl.sh --diag     # 只诊断，不改动
#
# 参数来源：从 /opt/NebulaPanel/conf/app.yaml 读取端口 / 入口 / 账号
#

set -uo pipefail

NP_HOME="/opt/NebulaPanel"
CONF="${NP_HOME}/conf/app.yaml"
DIAG_ONLY=0
[ "${1:-}" = "--diag" ] && DIAG_ONLY=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

###############################################################################
# 1. 诊断
###############################################################################
echo "========================================"
echo " npctl 安装环境诊断"
echo "========================================"
echo ""

info "当前用户：$(id -un 2>/dev/null || echo unknown)  UID=$(id -u 2>/dev/null || echo ?)"

echo ""
echo "--- 目标路径状态 ---"
for d in /usr/local/bin /usr/bin; do
    if [ -d "$d" ]; then
        printf "  %-16s 存在  权限=%s  可写=%s\n" \
            "$d" "$(stat -c '%a %U:%G' "$d" 2>/dev/null || echo '?')" \
            "$([ -w "$d" ] && echo 是 || echo 否)"
    else
        printf "  %-16s 不存在\n" "$d"
    fi
done

echo ""
echo "--- 已存在的 npctl ---"
if [ -e /usr/local/bin/npctl ]; then
    ls -l /usr/local/bin/npctl 2>/dev/null
    if command -v lsattr >/dev/null 2>&1; then
        ATTR="$(lsattr /usr/local/bin/npctl 2>/dev/null | awk '{print $1}')"
        echo "  lsattr: ${ATTR:-（无法读取）}"
        case "$ATTR" in
            *i*) warn "检测到 immutable 属性（chattr +i）—— 这就是 EPERM 的直接原因" ;;
        esac
    fi
else
    echo "  /usr/local/bin/npctl 不存在"
fi

echo ""
echo "--- 挂载与安全模块 ---"
if command -v mountpoint >/dev/null 2>&1; then
    for m in /usr /usr/local /usr/local/bin; do
        if mountpoint -q "$m" 2>/dev/null; then
            echo "  $m 是独立挂载点："
            mount | grep " $m " | sed 's/^/    /'
            mount | grep " $m " | grep -q '\bro\b' && warn "    $m 为只读挂载"
        fi
    done
    echo "  （以上无输出表示 /usr/local/bin 未独立挂载）"
fi
if command -v getenforce >/dev/null 2>&1; then
    echo "  SELinux: $(getenforce 2>/dev/null)"
fi
if [ -d /sys/fs/apparmor ]; then
    echo "  AppArmor: 已启用"
fi

echo ""
echo "--- 文件系统类型 ---"
df -T /usr/local/bin 2>/dev/null | tail -n +1 | sed 's/^/  /'

###############################################################################
# 2. 读取面板配置
###############################################################################
echo ""
echo "========================================"
echo " 面板配置读取"
echo "========================================"

NP_PORT="9999"; NP_ENTRANCE="nebula"; NP_USERNAME="admin"; NP_PASSWORD=""

if [ -f "$CONF" ]; then
    v() { grep -E "^\s*$1:" "$CONF" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'; }
    P="$(v port)";        [ -n "$P" ] && NP_PORT="$P"
    E="$(v entrance)";    [ -n "$E" ] && NP_ENTRANCE="$E"
    U="$(v username)";    [ -n "$U" ] && NP_USERNAME="$U"
    W="$(v password)";    [ -n "$W" ] && NP_PASSWORD="$W"
    ok "已从 $CONF 读取配置"
    echo "  端口=$NP_PORT  入口=$NP_ENTRANCE  账号=$NP_USERNAME"
else
    warn "$CONF 不存在，使用默认值（端口 9999 / 入口 nebula / 账号 admin）"
    echo "  若面板已部署但此文件缺失，请确认安装目录是否被自定义"
fi

if [ "$DIAG_ONLY" = "1" ]; then
    echo ""
    info "诊断模式结束（未做任何改动）"
    exit 0
fi

###############################################################################
# 3. 修复
###############################################################################
echo ""
echo "========================================"
echo " 修复 npctl"
echo "========================================"

# 3.1 尝试解除 immutable
if [ -e /usr/local/bin/npctl ] && command -v lsattr >/dev/null 2>&1; then
    ATTR="$(lsattr /usr/local/bin/npctl 2>/dev/null | awk '{print $1}')"
    if [ "${ATTR#*i}" != "$ATTR" ]; then
        info "尝试解除 immutable：chattr -i /usr/local/bin/npctl"
        if chattr -i /usr/local/bin/npctl 2>/dev/null; then
            ok "immutable 已解除"
        else
            warn "chattr -i 失败，可能需要更高权限或文件系统不支持"
        fi
    fi
fi

# 3.2 生成脚本内容
build_body() {
cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
NP_PORT="${NP_PORT}"
NP_ENTRANCE="${NP_ENTRANCE}"
NP_HOME="${NP_HOME}"
NP_VERSION="V1.0.0"

cmd=\${1:-help}
case \$cmd in
    start)   docker compose -f "\${NP_HOME}/docker/docker-compose.yml" up -d ;;
    stop)    docker compose -f "\${NP_HOME}/docker/docker-compose.yml" stop ;;
    restart) docker compose -f "\${NP_HOME}/docker/docker-compose.yml" restart ;;
    status)  docker compose -f "\${NP_HOME}/docker/docker-compose.yml" ps ;;
    logs)    docker compose -f "\${NP_HOME}/docker/docker-compose.yml" logs -f --tail=200 ;;
    user-info)
        echo "访问地址：http://\$(hostname -I | awk '{print \$1}'):\${NP_PORT}/\${NP_ENTRANCE}"
        echo "账号：${NP_USERNAME}"
        echo "密码：${NP_PASSWORD}"
        echo "版本：\${NP_VERSION}"
        ;;
    version) echo "NebulaPanel \${NP_VERSION}" ;;
    *) echo "用法：npctl {start|stop|restart|status|logs|user-info|version}" ;;
esac
EOF
}

# 3.3 按优先级尝试安装
install_to() {
    local dir="$1" target tmp
    [ -d "$dir" ] || return 1
    target="${dir}/npctl"
    tmp="${target}.tmp.$$"
    if build_body > "$tmp" 2>/dev/null; then
        chmod 755 "$tmp" 2>/dev/null
        if mv -f "$tmp" "$target" 2>/dev/null; then
            ok "已安装到 ${target}"
            return 0
        fi
        rm -f "$tmp" 2>/dev/null
    fi
    return 1
}

INSTALLED=""
for d in /usr/local/bin /usr/bin /bin; do
    if install_to "$d"; then
        INSTALLED="${d}/npctl"
        break
    fi
done

# 3.4 兜底：安装目录
if [ -z "$INSTALLED" ]; then
    warn "系统目录均不可写，改为安装到 ${NP_HOME}/npctl.sh"
    if build_body > "${NP_HOME}/npctl.sh" 2>/dev/null; then
        chmod 755 "${NP_HOME}/npctl.sh"
        INSTALLED="${NP_HOME}/npctl.sh"
        ok "已安装到 ${INSTALLED}"
        echo ""
        echo "  加入 PATH（写入 /etc/profile.d）："
        echo "    echo 'export PATH=\"\$PATH:${NP_HOME}\"' > /etc/profile.d/nebulapanel.sh"
        echo "    source /etc/profile.d/nebulapanel.sh"
        echo "    alias npctl='${NP_HOME}/npctl.sh'"
    else
        err "全部路径写入失败，请检查文件系统状态"
        exit 1
    fi
fi

###############################################################################
# 4. 验证
###############################################################################
echo ""
echo "========================================"
echo " 验证"
echo "========================================"

if bash -n "$INSTALLED" 2>/dev/null; then
    ok "语法检查通过"
else
    err "语法检查失败"
    exit 1
fi

echo ""
info "执行 npctl status："
echo "---------------------------------------"
bash "$INSTALLED" status 2>&1 | sed 's/^/  /' || warn "status 返回非 0（容器可能未运行）"

echo ""
info "访问信息："
echo "---------------------------------------"
bash "$INSTALLED" user-info 2>&1 | sed 's/^/  /'

echo ""
echo "========================================"
ok "完成"
echo "========================================"
