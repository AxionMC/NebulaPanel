#!/usr/bin/env bash
#
# NebulaPanel Linux 运维面板 - 交互式 Docker 一键安装脚本
# 基于 1Panel 源码重构，支持 Debian / Ubuntu / CentOS / Rocky / AlmaLinux
#
# 用法：
#   curl -fsSL https://resource.nebulapanel.pro/v2/quick_start.sh | bash
#   或者本地：bash install.sh
#

set -euo pipefail

###############################################################################
# 颜色输出
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

###############################################################################
# 读取用户输入（带默认值）
###############################################################################
read_input() {
    local prompt="$1" default="$2" var_name="$3"
    local input
    if [ -n "$default" ]; then
        printf "${BLUE}[?]${NC} %s ${YELLOW}[默认: ${default}]${NC}: " "$prompt"
    else
        printf "${BLUE}[?]${NC} %s: " "$prompt"
    fi
    read -r input || true
    input="${input:-$default}"
    if [ -z "$input" ]; then
        error "该项不能为空，请重新输入"
        read_input "$prompt" "$default" "$var_name"
        return
    fi
    eval "$var_name=\"\$input\""
}

###############################################################################
# 检查 root 权限
###############################################################################
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 权限运行安装脚本（sudo bash install.sh）"
        exit 1
    fi
}

###############################################################################
# 检测操作系统
###############################################################################
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        OS_VERSION_ID="$(rpm --eval %{dist} | tr -d '.')"
    else
        error "无法识别操作系统，仅支持 Debian/Ubuntu/CentOS/Rocky/AlmaLinux"
        exit 1
    fi

    case "$(uname -m)" in
        x86_64|amd64) NP_ARCH="amd64" ;;
        aarch64|arm64)  NP_ARCH="arm64" ;;
        *) error "不支持的架构：$(uname -m)，仅支持 amd64 / arm64"; exit 1 ;;
    esac

    info "检测到系统：${OS_ID} ${OS_VERSION_ID} 架构：${NP_ARCH}"
}

###############################################################################
# 安装系统依赖
###############################################################################
install_deps() {
    info "安装系统依赖（curl, ca-certificates, openssl, wget, tar, sudo）..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y curl ca-certificates openssl wget tar sudo gnupg >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        local pkg_mgr="yum"
        command -v dnf >/dev/null 2>&1 && pkg_mgr="dnf"
        ${pkg_mgr} install -y curl ca-certificates openssl wget tar sudo gnupg >/dev/null 2>&1 || true
    else
        warn "未找到 apt-get/yum/dnf，将跳过依赖安装，请自行保证 curl/openssl 可用"
    fi

    for cmd in curl openssl tar; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            error "缺少必要命令：${cmd}，请手动安装后重试"
            exit 1
        fi
    done
}

###############################################################################
# 检测 Docker，有则跳过安装，无则安装
###############################################################################
detect_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker 已安装，跳过 Docker 安装"
        docker --version
        return 0
    fi

    info "未检测到 Docker，开始安装 Docker..."
    install_docker
}

install_docker() {
    info "使用官方脚本安装 Docker（跨发行版自动适配）..."
    if ! command -v curl >/dev/null 2>&1; then
        error "缺少 curl 命令，无法安装 Docker"
        exit 1
    fi

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh

    systemctl enable --now docker 2>/dev/null || true

    if ! command -v docker >/dev/null 2>&1; then
        error "Docker 安装失败，请手动安装后重试"
        exit 1
    fi

    ok "Docker 安装完成：$(docker --version)"
}

###############################################################################
# 下载 NebulaPanel 二进制（用于构建 Docker 镜像）
###############################################################################
download_binaries() {
    info "下载 NebulaPanel 二进制文件（版本：${NP_VERSION}, 架构：${NP_ARCH}）..."

    mkdir -p "${NP_BUILD_DIR}"

    local core_url="${NP_BINARY_URL}/NebulaPanel-core-${NP_ARCH}"
    local agent_url="${NP_BINARY_URL}/NebulaPanel-agent-${NP_ARCH}"

    if ! curl -fsSL --connect-timeout 30 --max-time 300 -o "${NP_BUILD_DIR}/NebulaPanel-core" "${core_url}"; then
        error "下载 NebulaPanel-core 失败：${core_url}"
        exit 1
    fi
    chmod 755 "${NP_BUILD_DIR}/NebulaPanel-core"

    if ! curl -fsSL --connect-timeout 30 --max-time 300 -o "${NP_BUILD_DIR}/NebulaPanel-agent" "${agent_url}"; then
        error "下载 NebulaPanel-agent 失败：${agent_url}"
        exit 1
    fi
    chmod 755 "${NP_BUILD_DIR}/NebulaPanel-agent"

    ok "二进制文件下载完成"
}

###############################################################################
# 生成 Dockerfile（core）
###############################################################################
write_dockerfile_core() {
    cat > "${NP_DOCKER_DIR}/Dockerfile.core" <<EOF
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp}
WORKDIR /opt/NebulaPanel

COPY NebulaPanel-core /usr/local/bin/NebulaPanel-core
RUN chmod +x /usr/local/bin/NebulaPanel-core

EXPOSE 9999

ENTRYPOINT ["NebulaPanel-core", "start"]
EOF
}

###############################################################################
# 生成 Dockerfile（agent）
###############################################################################
write_dockerfile_agent() {
    cat > "${NP_DOCKER_DIR}/Dockerfile.agent" <<EOF
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp}
WORKDIR /opt/NebulaPanel

COPY NebulaPanel-agent /usr/local/bin/NebulaPanel-agent
RUN chmod +x /usr/local/bin/NebulaPanel-agent

VOLUME /var/run/docker.sock

ENTRYPOINT ["NebulaPanel-agent", "start"]
EOF
}

###############################################################################
# 生成 docker-compose.yml
###############################################################################
write_docker_compose() {
    cat > "${NP_DOCKER_DIR}/docker-compose.yml" <<EOF
version: "3.8"

services:
  nebulapanel-core:
    build:
      context: ${NP_BUILD_DIR}
      dockerfile: ${NP_DOCKER_DIR}/Dockerfile.core
    container_name: nebulapanel-core
    ports:
      - "${NP_PORT}:9999"
    volumes:
      - ${NP_CONF_DIR}:/opt/NebulaPanel/conf
      - ${NP_DB_DIR}:/opt/NebulaPanel/db
      - ${NP_SECRET_DIR}:/opt/NebulaPanel/secret
      - ${NP_LOG_DIR}:/opt/NebulaPanel/logs
      - ${NP_BACKUP_DIR}:/opt/NebulaPanel/backup
      - ${NP_GEO_DIR}:/opt/NebulaPanel/geo
      - ${NP_TMP_DIR}:/opt/NebulaPanel/tmp
    restart: always
    network_mode: host

  nebulapanel-agent:
    build:
      context: ${NP_BUILD_DIR}
      dockerfile: ${NP_DOCKER_DIR}/Dockerfile.agent
    container_name: nebulapanel-agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${NP_HOME}:/opt/NebulaPanel
    restart: always
    network_mode: host
EOF
}

###############################################################################
# 构建镜像并启动容器
###############################################################################
build_and_start() {
    info "构建 NebulaPanel Docker 镜像并启动服务..."

    mkdir -p "${NP_CONF_DIR}" "${NP_DB_DIR}" "${NP_SECRET_DIR}" \
             "${NP_LOG_DIR}" "${NP_BACKUP_DIR}" "${NP_GEO_DIR}" "${NP_TMP_DIR}" \
             "${NP_DOCKER_DIR}"

    # 拷贝二进制到构建上下文
    cp "${NP_BUILD_DIR}/NebulaPanel-core" "${NP_DOCKER_DIR}/NebulaPanel-core"
    cp "${NP_BUILD_DIR}/NebulaPanel-agent" "${NP_DOCKER_DIR}/NebulaPanel-agent"

    write_dockerfile_core
    write_dockerfile_agent
    write_docker_compose

    # 生成 conf/app.yaml（生产模式配置）
    cat > "${NP_CONF_DIR}/app.yaml" <<EOF
base:
  install_dir: ${NP_INSTALL_DIR}
  mode: stable
  is_demo: false
  is_offline: false
  is_enterprise: false
  port: ${NP_PORT}
  username: ${NP_USERNAME}
  password: ${NP_PASSWORD}
  version: ${NP_VERSION}

log:
  level: info
  time_zone: Asia/Shanghai
  log_name: NebulaPanel-Core
  log_suffix: .log
  max_backup: 10
EOF

    cd "${NP_DOCKER_DIR}"

    if command -v docker compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    else
        error "未找到 docker compose 插件，无法启动容器"
        exit 1
    fi

    ${DOCKER_COMPOSE} up -d --build

    ok "NebulaPanel 容器已启动"
}

###############################################################################
# 生成 npctl 管理 CLI
###############################################################################
generate_npctl() {
    info "生成 npctl 管理命令行..."

    cat > /usr/local/bin/npctl <<EOF
#!/usr/bin/env bash
set -euo pipefail
NP_PORT="${NP_PORT}"
NP_ENTRANCE="${NP_ENTRANCE}"
NP_HOME="${NP_HOME}"

cmd=\${1:-help}
case \$cmd in
    start)  docker compose -f "\${NP_HOME}/docker/docker-compose.yml" up -d ;;
    stop)   docker compose -f "\${NP_HOME}/docker/docker-compose.yml" stop ;;
    restart) docker compose -f "\${NP_HOME}/docker/docker-compose.yml" restart ;;
    status) docker compose -f "\${NP_HOME}/docker/docker-compose.yml" ps ;;
    user-info)
        echo "访问地址：http://\$(hostname -I | awk '{print \$1}'):\${NP_PORT}/\${NP_ENTRANCE}"
        echo "账号：${NP_USERNAME}"
        echo "密码：${NP_PASSWORD}"
        ;;
    *) echo "用法：npctl {start|stop|restart|status|user-info}" ;;
esac
EOF
    chmod 755 /usr/local/bin/npctl

    ok "npctl 已安装到 /usr/local/bin/npctl"
}

###############################################################################
# 安装后询问是否替换 Docker 镜像源
###############################################################################
ask_replace_mirror() {
    echo ""
    read -rp "安装完成后，是否替换 Docker 镜像源为 hub.002230.xyz:44300？[y/N]: " REPLY
    echo ""
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        info "跳过 Docker 镜像源替换"
        return 0
    fi

    info "配置 Docker 镜像源：hub.002230.xyz:44300..."

    mkdir -p /etc/docker

    if [ -f /etc/docker/daemon.json ]; then
        warn "/etc/docker/daemon.json 已存在，将覆盖 registry-mirrors 字段"
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s)
    fi

    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://hub.002230.xyz:44300"]
}
EOF

    systemctl daemon-reload
    systemctl restart docker

    ok "Docker 镜像源已替换为 https://hub.002230.xyz:44300，Docker 已重启"
}

###############################################################################
# 等待端口就绪并打印结果
###############################################################################
wait_and_print_result() {
    local waited=0
    while [ "${waited}" -lt 60 ]; do
        if command -v ss >/dev/null 2>&1; then
            ss -ltn | grep -q ":${NP_PORT} " && break
        elif command -v netstat >/dev/null 2>&1; then
            netstat -ltn | grep -q ":${NP_PORT} " && break
        fi
        sleep 2
        waited=$((waited + 2))
    done

    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"

    echo ""
    echo "========================================================================"
    ok "NebulaPanel Docker 部署完成！"
    echo ""
    echo "  访问地址：http://${local_ip}:${NP_PORT}/${NP_ENTRANCE}"
    echo "  管理账号：${NP_USERNAME}"
    echo "  管理密码：${NP_PASSWORD}"
    echo ""
    echo "  安装目录：${NP_HOME}"
    echo "  配置文件：${NP_CONF_DIR}/app.yaml"
    echo "  Docker 目录：${NP_DOCKER_DIR}"
    echo ""
    echo "  管理命令：npctl {start|stop|restart|status|user-info}"
    echo ""
    echo "  Docker 容器："
    echo "    docker compose -f ${NP_DOCKER_DIR}/docker-compose.yml ps"
    echo ""
    echo "========================================================================"
}

###############################################################################
# 交互式配置
###############################################################################
interactive_config() {
    echo ""
    echo "========================================================================"
    info "NebulaPanel 交互式安装配置"
    echo "========================================================================"
    echo ""

    # 版本
    read_input "请输入 NebulaPanel 版本" "v2.0.0" NP_VERSION

    # 安装目录
    read_input "请输入安装目录" "/opt" NP_INSTALL_DIR

    # 面板端口
    read_input "请输入面板访问端口" "9999" NP_PORT

    # 安全入口
    read_input "请输入安全入口路径（访问路径后缀）" "nebula" NP_ENTRANCE

    # 管理员账号
    read_input "请输入管理员账号" "admin" NP_USERNAME

    # 管理员密码
    read_input "请输入管理员密码" "admin123" NP_PASSWORD

    # 语言
    read_input "请输入界面语言（zh/en）" "zh" NP_LANGUAGE

    # 仓库地址
    read_input "请输入资源仓库地址" "https://resource.nebulapanel.pro/v2" NP_REPO_URL

    echo ""
    ok "配置读取完成，开始安装..."
    echo ""
}

###############################################################################
# 主流程
###############################################################################
main() {
    require_root
    detect_os
    interactive_config
    install_deps
    detect_docker

    # 根据用户配置构建下载地址
    NP_BINARY_URL="${NP_REPO_URL}/package/v2/${NP_VERSION}/linux"
    NP_HOME="${NP_INSTALL_DIR}/NebulaPanel"
    NP_CONF_DIR="${NP_HOME}/conf"
    NP_DB_DIR="${NP_HOME}/db"
    NP_SECRET_DIR="${NP_HOME}/secret"
    NP_LOG_DIR="${NP_HOME}/logs"
    NP_BACKUP_DIR="${NP_HOME}/backup"
    NP_GEO_DIR="${NP_HOME}/geo"
    NP_TMP_DIR="${NP_HOME}/tmp"
    NP_DOCKER_DIR="${NP_HOME}/docker"
    NP_BUILD_DIR="${NP_HOME}/.build"

    download_binaries
    build_and_start
    generate_npctl
    ask_replace_mirror
    wait_and_print_result
}

main "$@"
