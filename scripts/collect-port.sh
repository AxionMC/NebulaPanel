#!/usr/bin/env bash
#
# NebulaPanel 端口问题一键取证
#
# 目的：一次性采集判断「端口为何不开放」所需的全部信息。
# 三种可能：
#   A. core 容器根本没起来（ENTRYPOINT / panic / 二进制是旧的）
#   B. core 起来了但监听在别的端口（配置来源不一致）
#   C. 监听正常但被防火墙 / 安全组拦截
#
# 用法：
#   sudo bash scripts/collect-port.sh
#
# 输出：直接复制终端全部内容发回即可
#

set -uo pipefail

NP_HOME="${NP_HOME:-/opt/NebulaPanel}"
DOCKER_DIR="${NP_HOME}/docker"

echo "================================================================"
echo " NebulaPanel 端口取证报告"
echo " 时间: $(date '+%F %T %Z')"
echo "================================================================"

###############################################################################
echo ""
echo "##### 1. 主机信息 #####"
uname -a
echo "--- 发行版 ---"
cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || true
echo "--- 本机 IP ---"
hostname -I 2>/dev/null || ip -4 addr show 2>/dev/null | grep inet || true

###############################################################################
echo ""
echo "##### 2. 安装目录结构 #####"
if [ -d "$NP_HOME" ]; then
    ls -la "$NP_HOME" 2>/dev/null
    echo "--- conf ---"
    ls -la "$NP_HOME/conf" 2>/dev/null
    echo "--- docker ---"
    ls -la "$NP_HOME/docker" 2>/dev/null
    echo "--- etc (socket 目录) ---"
    ls -la "$NP_HOME/etc" 2>/dev/null || echo "（不存在）"
else
    echo "!! $NP_HOME 不存在"
fi

###############################################################################
echo ""
echo "##### 3. 二进制版本与时间戳 #####"
for f in "$NP_HOME/docker/NebulaPanel-core" "$NP_HOME/docker/NebulaPanel-agent" \
         "$NP_HOME/.build/NebulaPanel-core" "$NP_HOME/.build/NebulaPanel-agent"; do
    if [ -f "$f" ]; then
        echo "  $f"
        ls -l --time-style=long-iso "$f" 2>/dev/null | awk '{print "    大小="$5"  时间="$6" "$7}'
        echo -n "    sha256(前16): "
        sha256sum "$f" 2>/dev/null | cut -c1-16
    fi
done

###############################################################################
echo ""
echo "##### 4. 配置内容 #####"
echo "--- conf/npctl 关键键值 ---"
if [ -f "$NP_HOME/conf/npctl" ]; then
    grep -E '^(BASE_DIR|ORIGINAL_PORT|ORIGINAL_ENTRANCE|ORIGINAL_VERSION|LANGUAGE)=' "$NP_HOME/conf/npctl" 2>/dev/null
else
    echo "!! conf/npctl 不存在"
fi

echo ""
echo "--- conf/app.yaml 全文 ---"
if [ -f "$NP_HOME/conf/app.yaml" ]; then
    cat "$NP_HOME/conf/app.yaml"
else
    echo "!! conf/app.yaml 不存在（core 会走 stable 分支读 ctl_conf）"
fi

###############################################################################
echo ""
echo "##### 5. compose 与 Dockerfile #####"
if [ -f "$DOCKER_DIR/docker-compose.yml" ]; then
    echo "--- docker-compose.yml ---"
    cat "$DOCKER_DIR/docker-compose.yml"
else
    echo "!! docker-compose.yml 不存在"
fi

echo ""
for df in Dockerfile.core Dockerfile.agent; do
    if [ -f "$DOCKER_DIR/$df" ]; then
        echo "--- $df 的 ENTRYPOINT / ENV ---"
        grep -E '^(ENTRYPOINT|ENV|CMD)' "$DOCKER_DIR/$df" 2>/dev/null
    fi
done

###############################################################################
echo ""
echo "##### 6. 容器状态 #####"
cd "$DOCKER_DIR" 2>/dev/null || { echo "!! 无法进入 $DOCKER_DIR"; exit 1; }

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else echo "!! 未找到 docker compose"; exit 1; fi

echo "--- docker compose ps -a ---"
${DC} ps -a 2>&1

echo ""
echo "--- 容器内实际运行的进程 ---"
for c in nebulapanel-core nebulapanel-agent; do
    echo "  [$c]"
    docker top "$c" 2>/dev/null | head -5 | sed 's/^/    /' || echo "    （容器未运行）"
done

###############################################################################
echo ""
echo "##### 7. core 日志（关键） #####"
echo "--- 是否出现 listen 记录 ---"
${DC} logs nebulapanel-core 2>&1 | grep -iE 'listen at|listen on' | tail -5 || echo "  （无 listen 记录！说明未成功监听）"

echo ""
echo "--- 启动错误 ---"
${DC} logs nebulapanel-core 2>&1 | grep -iE 'unknown command|panic|error|fatal|bind|address already in use|permission denied' | tail -15 || echo "  （无错误）"

echo ""
echo "--- 最后 30 行 ---"
${DC} logs --tail=30 nebulapanel-core 2>&1

###############################################################################
echo ""
echo "##### 8. 容器内配置读取验证 #####"
echo "--- core 容器内看到的配置 ---"
docker exec nebulapanel-core sh -c '
echo "[npctl 是否存在]"; ls -l /usr/local/bin/npctl 2>/dev/null || echo "  不存在"
echo "[npctl 的 ORIGINAL_PORT]"; grep -E "^ORIGINAL_PORT=" /usr/local/bin/npctl 2>/dev/null || echo "  读不到"
echo "[app.yaml 是否存在]"; ls -l /opt/NebulaPanel/conf/app.yaml 2>/dev/null || echo "  不存在"
echo "[app.yaml 的 mode 与 port]"; grep -E "^\s*(mode|port|bindAddress|entrance):" /opt/NebulaPanel/conf/app.yaml 2>/dev/null || echo "  读不到"
' 2>&1 | sed 's/^/  /' || echo "  !! 无法进入容器"

###############################################################################
echo ""
echo "##### 9. 宿主机监听端口 #####"
if command -v ss >/dev/null 2>&1; then
    echo "--- 全部 LISTEN ---"
    ss -ltnp 2>/dev/null
    echo ""
    echo "--- 8700 / 9999 专项 ---"
    ss -ltnp 2>/dev/null | grep -E ':(8700|9999)' || echo "  !! 8700 和 9999 都没有监听"
elif command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null
else
    echo "--- /proc/net/tcp ---"
    cat /proc/net/tcp 2>/dev/null | head -20
fi

###############################################################################
echo ""
echo "##### 10. 容器内监听验证 #####"
docker exec nebulapanel-core sh -c 'command -v ss >/dev/null && ss -ltn; command -v netstat >/dev/null && netstat -ltn' 2>/dev/null | sed 's/^/  /' || echo "  容器内无 ss/netstat"

###############################################################################
echo ""
echo "##### 11. 本机连通性 #####"
# 从 ctl_conf 读取实际配置端口，避免硬编码导致误判
CFG_PORT="$(grep -E '^ORIGINAL_PORT=' "$NP_HOME/conf/npctl" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"'\''[:space:]')"
APP_PORT="$(grep -E '^[[:space:]]*port:' "$NP_HOME/conf/app.yaml" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '"'\''[:space:]')"
echo "  配置端口：ctl_conf=${CFG_PORT:-无}  app.yaml=${APP_PORT:-无}"

PORTS_TO_TEST=""
for p in "${APP_PORT}" "${CFG_PORT}" 8700 9999; do
    [ -z "$p" ] && continue
    case " $PORTS_TO_TEST " in *" $p "*) continue ;; esac
    PORTS_TO_TEST="$PORTS_TO_TEST $p"
done

for p in $PORTS_TO_TEST; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:$p/" 2>/dev/null || echo "000")
    if [ "$CODE" = "000" ] || [ -z "$CODE" ]; then
        echo "  http://127.0.0.1:$p/  →  连接失败（该端口未监听或被拦）"
    else
        echo "  http://127.0.0.1:$p/  →  HTTP $CODE  ✅ 可达"
    fi
done

# 用安全入口再测一次（首页可能重定向）
if [ -n "${CFG_PORT:-}" ]; then
    ENT="$(grep -E '^ORIGINAL_ENTRANCE=' "$NP_HOME/conf/npctl" 2>/dev/null | cut -d= -f2 | tr -d '"'\''[:space:]')"
    if [ -n "${ENT:-}" ]; then
        CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:${CFG_PORT}/${ENT}" 2>/dev/null || echo "000")
        echo "  http://127.0.0.1:${CFG_PORT}/${ENT}  →  HTTP ${CODE:-000}"
    fi
fi

###############################################################################
echo ""
echo "##### 12. 防火墙 #####"
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "firewalld: 运行中"
    firewall-cmd --list-all 2>/dev/null | sed 's/^/  /'
elif command -v ufw >/dev/null 2>&1; then
    echo "ufw:"; ufw status 2>/dev/null | sed 's/^/  /'
else
    echo "firewalld / ufw 均未运行"
fi

echo ""
echo "--- iptables INPUT 链（前 15 条）---"
iptables -L INPUT -n -v 2>/dev/null | head -15 | sed 's/^/  /' || echo "  （无权限或未安装）"

echo ""
echo "--- Docker 相关 iptables 链 ---"
iptables -L DOCKER -n 2>/dev/null | head -10 | sed 's/^/  /' || echo "  （无 DOCKER 链）"

###############################################################################
echo ""
echo "================================================================"
echo " 取证结束"
echo ""
echo " 判读指引："
echo "   第7节无 listen 记录  → core 未启动（看第7节错误）"
echo "   第7节 listen 端口≠8700 → 配置来源不一致（对比第4、8节）"
echo "    listens 8700 但第11节 000 → 容器网络或防火墙"
echo "   第11节 200 但外网不通 → 云安全组未放行"
echo "================================================================"
