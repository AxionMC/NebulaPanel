#!/usr/bin/env bash
#
# NebulaPanel 容器化部署修复（socket 互通 / docker CLI / 资源站 / GIN 模式）
#
# 修复以下 4 个已在现场观察到的问题：
#   1. core 连不上 agent：/etc/NebulaPanel/agent.sock 未共享
#   2. agent 内缺 docker CLI：Docker Compose command not found
#   3. 资源站 404：lang.tar.gz / GeoIP.mmdb / apps-assets 地址错误
#   4. Gin debug 模式：日志刷屏、性能损耗
#
# 用法：
#   sudo bash scripts/fix-container.sh
#
# 说明：会重建 agent 镜像（需拉取 docker-ce-cli，耗时约 1-3 分钟）。
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
DOCKER_DIR="${NP_HOME}/docker"
ETC_DIR="${NP_HOME}/etc"
COMPOSE="${DOCKER_DIR}/docker-compose.yml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){   printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){  printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
die(){ err "$*"; exit 1; }
sec(){ printf "\n${BLUE}===== %s =====${NC}\n" "$*"; }

[ "$(id -u)" -eq 0 ] || die "请用 root 运行"
[ -d "$DOCKER_DIR" ] || die "找不到 $DOCKER_DIR"
[ -f "$COMPOSE" ] || die "找不到 $COMPOSE"

cd "$DOCKER_DIR" || die "无法进入 $DOCKER_DIR"

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else die "未找到 docker compose"; fi

###############################################################################
sec "1. 创建 socket 共享目录"
###############################################################################
mkdir -p "$ETC_DIR"
chmod 700 "$ETC_DIR"
ok "已创建 $ETC_DIR（权限 700）"

###############################################################################
sec "2. 修补 docker-compose.yml"
###############################################################################
BACKUP="${COMPOSE}.bak.$(date +%s)"
cp -f "$COMPOSE" "$BACKUP"
info "备份：$BACKUP"

patch_compose() {
    local f="$1"

    # 2.1 补 /etc/NebulaPanel 共享挂载
    if ! grep -qF "/etc/NebulaPanel" "$f"; then
        info "补 /etc/NebulaPanel 共享挂载..."
        awk -v line="      - ${ETC_DIR}:/etc/NebulaPanel" '
            /^[[:space:]]*volumes:[[:space:]]*$/ { in_vol=1; done=0; print; next }
            in_vol && /^[[:space:]]*- / { print; next }
            in_vol && !/^[[:space:]]*- / { if (!done) { print line; done=1 } in_vol=0 }
            { print }
            END { if (in_vol && !done) print line }
        ' "$f" > "${f}.tmp" && mv -f "${f}.tmp" "$f"
        local cnt
        cnt="$(grep -cF "/etc/NebulaPanel" "$f" 2>/dev/null || echo 0)"
        ok "已写入 ${cnt} 处"
    else
        ok "已存在 /etc/NebulaPanel 挂载"
    fi

    # 2.2 补 GIN_MODE / TZ 环境变量
    if ! grep -q 'GIN_MODE' "$f"; then
        info "补 GIN_MODE / TZ 环境变量..."
        awk '
            { print }
            /^[[:space:]]*entrypoint:/ {
                print "    environment:"
                print "      - GIN_MODE=release"
                print "      - TZ=Asia/Shanghai"
            }
        ' "$f" > "${f}.tmp" && mv -f "${f}.tmp" "$f"
        ok "已写入 GIN_MODE=release / TZ=Asia/Shanghai"
    else
        ok "已存在 GIN_MODE 配置"
    fi
}

patch_compose "$COMPOSE"

echo ""
info "当前 compose 关键配置："
grep -nE 'entrypoint:|GIN_MODE|TZ=|/etc/NebulaPanel' "$COMPOSE" | sed 's/^/  /'

###############################################################################
sec "3. 重建 agent 镜像（安装 docker CLI）"
###############################################################################
AGENT_DF="${DOCKER_DIR}/Dockerfile.agent"

if [ -f "$AGENT_DF" ]; then
    if grep -q 'docker-ce-cli' "$AGENT_DF"; then
        ok "Dockerfile.agent 已含 docker-ce-cli"
    else
        info "重写 Dockerfile.agent（加入 docker CLI 与 compose 插件）..."
        cp -f "$AGENT_DF" "${AGENT_DF}.bak.$(date +%s)"
        cat > "$AGENT_DF" <<'EOF'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg tzdata \
        procps iproute2 \
        iptables nftables \
        tar gzip unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
         -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
         > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/NebulaPanel/conf /opt/NebulaPanel/db /opt/NebulaPanel/secret \
             /opt/NebulaPanel/logs /opt/NebulaPanel/backup /opt/NebulaPanel/geo \
             /opt/NebulaPanel/tmp /etc/NebulaPanel
WORKDIR /opt/NebulaPanel

COPY NebulaPanel-agent /usr/local/bin/NebulaPanel-agent
RUN chmod +x /usr/local/bin/NebulaPanel-agent

VOLUME /var/run/docker.sock

ENV GIN_MODE=release

ENTRYPOINT ["NebulaPanel-agent"]
EOF
        ok "Dockerfile.agent 已更新"
    fi
else
    warn "找不到 Dockerfile.agent，跳过"
fi

# core 也补 GIN_MODE
CORE_DF="${DOCKER_DIR}/Dockerfile.core"
if [ -f "$CORE_DF" ] && ! grep -q 'GIN_MODE' "$CORE_DF"; then
    info "为 Dockerfile.core 补 GIN_MODE=release..."
    cp -f "$CORE_DF" "${CORE_DF}.bak.$(date +%s)"
    python3 - "$CORE_DF" <<'PYEOF' 2>/dev/null || sed -i '/^ENTRYPOINT/i ENV GIN_MODE=release' "$CORE_DF"
import io, sys, re
p = sys.argv[1]
t = io.open(p, encoding="utf-8").read()
if "GIN_MODE" not in t:
    t = re.sub(r"(?m)^(ENTRYPOINT)", "ENV GIN_MODE=release\n\n\\1", t, count=1)
    io.open(p, "w", encoding="utf-8", newline="\n").write(t)
PYEOF
    ok "Dockerfile.core 已更新"
fi

###############################################################################
sec "4. 重建并启动"
###############################################################################
info "停止旧容器..."
${DC} down 2>&1 | sed 's/^/  /' || true

info "重建镜像（agent 需下载 docker-ce-cli，可能耗时 1-3 分钟）..."
if ! ${DC} build 2>&1 | tail -30 | sed 's/^/  /'; then
    warn "构建返回非 0，请检查上方输出"
fi

info "启动容器..."
${DC} up -d --force-recreate 2>&1 | sed 's/^/  /'

info "等待 15 秒..."
sleep 15

###############################################################################
sec "5. 验证"
###############################################################################
echo "--- 容器状态 ---"
${DC} ps 2>&1 | sed 's/^/  /'

echo ""
echo "--- socket 文件 ---"
if [ -S "${ETC_DIR}/agent.sock" ]; then
    ok "${ETC_DIR}/agent.sock 已创建（core 可与 agent 通信）"
    ls -l "${ETC_DIR}/agent.sock" | sed 's/^/  /'
else
    err "${ETC_DIR}/agent.sock 尚未创建"
    echo "  可能 agent 仍在启动，稍后再试；或查看下方 agent 日志"
fi

echo ""
echo "--- agent 内 docker CLI ---"
if docker exec nebulapanel-agent sh -c 'docker --version' 2>/dev/null | sed 's/^/  /'; then
    ok "agent 内 docker CLI 可用"
else
    err "agent 内 docker CLI 不可用"
fi

if docker exec nebulapanel-agent sh -c 'docker compose version' 2>/dev/null | sed 's/^/  /'; then
    ok "agent 内 docker compose 可用"
else
    err "agent 内 docker compose 不可用"
fi

echo ""
echo "--- core 日志（最后 15 行）---"
${DC} logs --tail=15 nebulapanel-core 2>&1 | sed 's/^/  /' | tee /tmp/np-core3.log

echo ""
echo "--- agent 日志（最后 20 行）---"
${DC} logs --tail=20 nebulapanel-agent 2>&1 | grep -vE 'GIN-debug' | sed 's/^/  /' | tee /tmp/np-agent3.log

###############################################################################
sec "6. 摘要"
###############################################################################
FAIL=0
grep -q 'unknown command "start"' /tmp/np-core3.log 2>/dev/null && { err "core 仍报 start 错误"; FAIL=1; }
grep -q 'panic:' /tmp/np-agent3.log 2>/dev/null && { err "agent 仍有 panic"; FAIL=1; }
grep -q 'Docker Compose command not found' /tmp/np-agent3.log 2>/dev/null && { err "agent 仍缺 compose"; FAIL=1; }
[ -S "${ETC_DIR}/agent.sock" ] || FAIL=1

if [ "$FAIL" -eq 0 ]; then
    ok "全部检查通过"
    PORT="$(grep -E '^ORIGINAL_PORT=' "${NP_HOME}/conf/npctl" 2>/dev/null | cut -d= -f2)"
    ENTR="$(grep -E '^ORIGINAL_ENTRANCE=' "${NP_HOME}/conf/npctl" 2>/dev/null | cut -d= -f2)"
    echo ""
    echo "  访问：http://$(hostname -I 2>/dev/null | awk '{print $1}'):${PORT:-8700}/${ENTR:-nebula}"
else
    warn "仍有问题，请把上方日志发出来"
fi
echo ""
