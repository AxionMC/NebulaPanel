#!/usr/bin/env bash
#
# NebulaPanel Linux 运维面板 - 交互式 Docker 一键安装脚本
# 基于 1Panel 源码重构，支持 Debian / Ubuntu / CentOS / Rocky / AlmaLinux
#
# 架构支持：仅 amd64（x86_64）
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/AxionMC/NebulaPanel/main/scripts/install.sh | bash
#   或者本地：sudo bash scripts/install.sh
#
# 说明：
#   - 全程交互式，可自定义安装目录、端口、安全入口、管理员账号与密码
#   - 面板版本固定为 V1.0.0，内置在线更新功能已移除
#   - 二进制从 https://resource.hongkongyun.top 获取
#     可用 NP_BINARY_BASE 环境变量覆盖：
#       NP_BINARY_BASE=https://your.cdn sudo -E bash scripts/install.sh
#   - 自动检测 Docker：已安装则跳过，未安装则自动安装
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

    # 本发布包仅提供 amd64（x86_64）二进制
    case "$(uname -m)" in
        x86_64|amd64)
            NP_ARCH="amd64"
            ;;
        aarch64|arm64)
            error "当前版本仅提供 amd64（x86_64）架构安装包，暂不支持 ARM64"
            error "如生产环境为 ARM 服务器，请从源码自行编译：bash scripts/build.sh --arch arm64"
            exit 1
            ;;
        *)
            error "不支持的架构：$(uname -m)，本发布包仅支持 amd64（x86_64）"
            exit 1
            ;;
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
        if command -v dnf >/dev/null 2>&1; then
            pkg_mgr="dnf"
        fi
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
# 下载 NebulaPanel 二进制
# 主源：NP_BINARY_BASE（自有资源站），文件名为 NebulaPanel-core-amd64 等
# 回退：本地 build/ 目录（源码构建产物）
###############################################################################
download_binaries() {
    info "下载 NebulaPanel 二进制（版本 ${NP_VERSION} / 架构 ${NP_ARCH}）..."
    info "资源站：${NP_BINARY_BASE}"

    mkdir -p "${NP_BUILD_DIR}"

    local core_dst="${NP_BUILD_DIR}/NebulaPanel-core"
    local agent_dst="${NP_BUILD_DIR}/NebulaPanel-agent"

    local ok_core=0
    local ok_agent=0

    # 依次尝试主域名与备用路径，兼容用户把文件放在根目录或 kvm/ 之类的子目录
    local candidates=(
        "${NP_BINARY_BASE}/NebulaPanel-core-${NP_ARCH}"
        "${NP_BINARY_BASE}/${NP_VERSION}/NebulaPanel-core-${NP_ARCH}"
        "${NP_BINARY_BASE}/linux/NebulaPanel-core-${NP_ARCH}"
    )

    for url in "${candidates[@]}"; do
        info "尝试下载 core：${url}"
        if curl -fSL --connect-timeout 20 --retry 2 --max-time 600 \
                --progress-bar -o "${core_dst}" "${url}" && [ -s "${core_dst}" ]; then
            ok_core=1
            break
        fi
        rm -f "${core_dst}"
    done

    local candidates_agent=(
        "${NP_BINARY_BASE}/NebulaPanel-agent-${NP_ARCH}"
        "${NP_BINARY_BASE}/${NP_VERSION}/NebulaPanel-agent-${NP_ARCH}"
        "${NP_BINARY_BASE}/linux/NebulaPanel-agent-${NP_ARCH}"
    )

    for url in "${candidates_agent[@]}"; do
        info "尝试下载 agent：${url}"
        if curl -fSL --connect-timeout 20 --retry 2 --max-time 600 \
                --progress-bar -o "${agent_dst}" "${url}" && [ -s "${agent_dst}" ]; then
            ok_agent=1
            break
        fi
        rm -f "${agent_dst}"
    done

    # 下载失败则回退到源码构建产物
    if [ "${ok_core}" -eq 0 ] || [ "${ok_agent}" -eq 0 ]; then
        warn "从资源站下载失败，尝试使用本地已构建的二进制"

        if [ "${ok_core}" -eq 0 ]; then
            for f in "${NP_SRC_DIR}/build/NebulaPanel-core-${NP_ARCH}" "${NP_SRC_DIR}/build/NebulaPanel-core"; do
                if [ -s "${f}" ]; then
                    cp -f "${f}" "${core_dst}"
                    ok_core=1
                    info "使用本地构建产物：${f}"
                    break
                fi
            done
        fi

        if [ "${ok_agent}" -eq 0 ]; then
            for f in "${NP_SRC_DIR}/build/NebulaPanel-agent-${NP_ARCH}" "${NP_SRC_DIR}/build/NebulaPanel-agent"; do
                if [ -s "${f}" ]; then
                    cp -f "${f}" "${agent_dst}"
                    ok_agent=1
                    info "使用本地构建产物：${f}"
                    break
                fi
            done
        fi
    fi

    if [ "${ok_core}" -eq 0 ] || [ "${ok_agent}" -eq 0 ]; then
        error "无法获取 NebulaPanel 二进制"
        error "  请确认资源站可访问：${NP_BINARY_BASE}/NebulaPanel-core-${NP_ARCH}"
        error "  或在源码目录执行 bash scripts/build.sh 后重试"
        exit 1
    fi

    # 基本校验：必须是 Linux ELF
    for f in "${core_dst}" "${agent_dst}"; do
        local magic
        magic=$(head -c 4 "${f}" | od -An -tx1 | tr -d ' \n')
        if [ "${magic}" != "7f454c46" ]; then
            error "$(basename "${f}") 不是有效的 Linux 可执行文件（magic=${magic}）"
            error "请检查资源站上的文件是否完整、是否为 amd64 Linux 版本"
            exit 1
        fi
    done

    chmod 755 "${core_dst}" "${agent_dst}"

    ok "二进制就绪：core $(du -h "${core_dst}" | cut -f1) / agent $(du -h "${agent_dst}" | cut -f1)"
}

###############################################################################
# 生成 Dockerfile（core）
###############################################################################
write_dockerfile_core() {
    cat > "${NP_DOCKER_DIR}/Dockerfile.core" <<'EOF'
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/NebulaPanel/conf /opt/NebulaPanel/db /opt/NebulaPanel/secret \
             /opt/NebulaPanel/logs /opt/NebulaPanel/backup /opt/NebulaPanel/geo \
             /opt/NebulaPanel/tmp
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
    cat > "${NP_DOCKER_DIR}/Dockerfile.agent" <<'EOF'
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/NebulaPanel/conf /opt/NebulaPanel/db /opt/NebulaPanel/secret \
             /opt/NebulaPanel/logs /opt/NebulaPanel/backup /opt/NebulaPanel/geo \
             /opt/NebulaPanel/tmp
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
services:
  nebulapanel-core:
    build:
      context: ${NP_DOCKER_DIR}
      dockerfile: ${NP_DOCKER_DIR}/Dockerfile.core
    container_name: nebulapanel-core
    # 使用 host 网络，面板直接监听 conn.port（默认 ${NP_PORT}），无需端口映射
    volumes:
      - ${NP_CONF_DIR}:/opt/NebulaPanel/conf
      - ${NP_DB_DIR}:/opt/NebulaPanel/db
      - ${NP_SECRET_DIR}:/opt/NebulaPanel/secret
      - ${NP_LOG_DIR}:/opt/NebulaPanel/logs
      - ${NP_BACKUP_DIR}:/opt/NebulaPanel/backup
      - ${NP_GEO_DIR}:/opt/NebulaPanel/geo
      - ${NP_TMP_DIR}:/opt/NebulaPanel/tmp
      # ctl_conf 配置文件：程序启动时读取 BASE_DIR / ORIGINAL_VERSION 等
      # 挂载为只读，容器内路径与上游约定一致
      - ${NP_CONF_DIR}/npctl:/usr/local/bin/npctl:ro
    restart: always
    network_mode: host

  nebulapanel-agent:
    build:
      context: ${NP_DOCKER_DIR}
      dockerfile: ${NP_DOCKER_DIR}/Dockerfile.agent
    container_name: nebulapanel-agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${NP_HOME}:/opt/NebulaPanel
      # 同上：agent 启动时 initBaseInfo() 会读该文件
      - ${NP_CONF_DIR}/npctl:/usr/local/bin/npctl:ro
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

    # 生成 conf/app.yaml（与 core/global/config.go 结构严格对应）
    cat > "${NP_CONF_DIR}/app.yaml" <<EOF
base:
  mode: stable
  username: ${NP_USERNAME}
  password: ${NP_PASSWORD}
  language: ${NP_LANGUAGE}
  is_demo: false
  is_offline: false
  is_enterprise: false
  version: ${NP_VERSION}
  install_dir: ${NP_INSTALL_DIR}

conn:
  port: ${NP_PORT}
  bindAddress: 0.0.0.0
  ipv6: disable
  ssl: disable
  entrance: ${NP_ENTRANCE}

log:
  level: info
  timeZone: Asia/Shanghai
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
# 生成 npctl
#
# 这一个文件身兼两职（与上游 1Panel 的 1pctl 设计一致）：
#   1. 宿主机上的管理 CLI（bash 脚本）
#   2. 程序读取的配置文件（顶部的 BASE_DIR= / ORIGINAL_PORT= 等键值行）
#      agent 启动时会读 /usr/local/bin/npctl 取 BASE_DIR 与 ORIGINAL_VERSION，
#      因此容器内也必须能看到这个文件（由 docker-compose 挂载）。
#
# 写入策略：
#   - 必写：${NP_CONF_DIR}/npctl（安装目录，永远可写），供 compose 挂载
#   - 尽力写：/usr/local/bin、/usr/bin（宿主机直接调用命令）
#   - 任一系统目录失败都不中断安装
###############################################################################
generate_npctl() {
    info "生成 npctl（管理命令 + 配置文件）..."

    local body
    body="$(cat <<EOF
#!/usr/bin/env bash
#
# NebulaPanel 管理命令行 (npctl)
# 顶部键值行同时作为程序配置文件，请勿删除或改动格式。

# 注意：值不加引号。程序侧按 key=value 直接取值，
# 带引号会被当成值的一部分，导致路径/端口异常。
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
)"

    # ---- 1. 写入安装目录（必需）----
    local primary="${NP_CONF_DIR}/npctl"
    if printf '%s\n' "${body}" > "${primary}" 2>/dev/null; then
        chmod 755 "${primary}" 2>/dev/null || true
        ok "配置文件已写入 ${primary}"
    else
        error "无法写入 ${primary}，安装无法继续"
        exit 1
    fi

    # ---- 2. 尽力写入系统目录，供宿主机直接调用 ----
    local system_path=""
    for dir in /usr/local/bin /usr/bin /bin; do
        [ -d "${dir}" ] || continue
        local target="${dir}/npctl"

        # immutable 预检
        if [ -e "${target}" ] && command -v lsattr >/dev/null 2>&1; then
            local attr
            attr="$(lsattr "${target}" 2>/dev/null | awk '{print $1}')"
            case "${attr}" in
                *i*)
                    warn "${target} 带 immutable 属性（chattr +i），跳过"
                    info "  如需修复：chattr -i ${target}"
                    continue
                    ;;
            esac
        fi

        if cp -f "${primary}" "${target}" 2>/dev/null; then
            chmod 755 "${target}" 2>/dev/null || true
            system_path="${target}"
            break
        fi
        warn "写入 ${target} 失败（目录不可写或文件被锁定），尝试下一个路径"
    done

    if [ -n "${system_path}" ]; then
        ok "管理命令已安装到 ${system_path}"
    else
        warn "未能把 npctl 安装到系统 PATH，面板运行不受影响"
        echo ""
        echo "  原因通常为以下之一："
        echo "    - /usr/local/bin/npctl 被 chattr +i 锁定 → chattr -i /usr/local/bin/npctl"
        echo "    - /usr/local/bin 或 /usr/bin 为只读挂载 → mount | grep usr"
        echo ""
        echo "  临时使用（无需安装）："
        echo "    ${primary} status"
        echo "    ${primary} user-info"
        echo ""
        echo "  或建立软链接（需目标可写）："
        echo "    ln -sf ${primary} /usr/local/bin/npctl"
        echo ""
    fi

    return 0
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
    local ready="no"
    while [ "${waited}" -lt 60 ]; do
        if command -v ss >/dev/null 2>&1; then
            if ss -ltn 2>/dev/null | grep -q ":${NP_PORT} "; then
                ready="yes"
                break
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -ltn 2>/dev/null | grep -q ":${NP_PORT} "; then
                ready="yes"
                break
            fi
        else
            # 无 ss/netstat 时直接跳过等待
            ready="unknown"
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done

    if [ "${ready}" = "no" ]; then
        warn "等待端口 ${NP_PORT} 超时，容器可能仍在启动，请稍后用 npctl status 检查"
    fi

    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
    if [ -z "${local_ip}" ]; then
        local_ip="127.0.0.1"
    fi

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
    if command -v npctl >/dev/null 2>&1; then
        echo "  管理命令：npctl {start|stop|restart|status|logs|user-info|version}"
    else
        echo "  管理命令（npctl 未安装到 PATH）："
        echo "    ${NP_HOME}/npctl.sh {start|stop|restart|status|logs|user-info|version}"
    fi
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

    # 版本已硬编码（内置在线更新已移除，后期按计划评估）
    NP_VERSION="V1.0.0"

    # 二进制资源站（可被环境变量 NP_BINARY_BASE 覆盖）
    # 服务器上传的两个文件：
    #   NebulaPanel-core-amd64
    #   NebulaPanel-agent-amd64
    NP_BINARY_BASE="${NP_BINARY_BASE:-https://resource.hongkongyun.top}"

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

    # 源码目录（脚本所在仓库根目录，用于回退本地构建产物）
    NP_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

    # 目录必须在写 npctl 之前建好
    mkdir -p "${NP_CONF_DIR}" "${NP_DB_DIR}" "${NP_SECRET_DIR}" \
             "${NP_LOG_DIR}" "${NP_BACKUP_DIR}" "${NP_GEO_DIR}" \
             "${NP_TMP_DIR}" "${NP_DOCKER_DIR}" "${NP_BUILD_DIR}"

    # 顺序要点：npctl 必须早于容器启动生成。
    # compose 会把它挂载到容器内 /usr/local/bin/npctl，
    # 若宿主机源文件不存在，Docker 会把它创建成空目录，导致 agent 读配置失败。
    generate_npctl
    download_binaries
    build_and_start
    ask_replace_mirror
    wait_and_print_result
}

main "$@"
