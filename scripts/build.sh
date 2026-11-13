#!/usr/bin/env bash
#
# NebulaPanel 一键构建脚本（自举：自动安装 Go + Node.js）
#
# 用法：
#   sudo bash scripts/build.sh                    # 自动识别架构，构建前端 + core + agent
#   bash scripts/build.sh --arch arm64            # 指定目标架构
#   bash scripts/build.sh --skip-frontend         # 跳过前端（复用已有 core/cmd/server/web）
#   bash scripts/build.sh --diag                  # 只做环境诊断 + 打印真实编译错误
#   bash scripts/build.sh --mirror cn             # 强制使用国内镜像
#
# 产物：
#   build/NebulaPanel-core-<arch>
#   build/NebulaPanel-agent-<arch>
#   build/NebulaPanel-linux-<arch>.tar.gz
#   build/NebulaPanel-linux-<arch>.tar.gz.sha256
#
# 说明：
#   - 非 root 运行时会安装到 $HOME/.local，不污染系统目录
#   - 优先复用系统已有的 Go / Node，版本不足才自动下载
#   - 全程日志同时输出到终端与 build/build.log
#

set -uo pipefail

###############################################################################
# 可覆盖的版本与路径
###############################################################################
GO_VERSION="${GO_VERSION:-1.27.3}"
NODE_MAJOR="${NODE_MAJOR:-20}"
TARGET_ARCH="${TARGET_ARCH:-}"
MIRROR="${MIRROR:-auto}"          # auto | cn | global
SKIP_FRONTEND="${SKIP_FRONTEND:-0}"
SKIP_DEPS="${SKIP_DEPS:-0}"
DIAG_ONLY="${DIAG_ONLY:-0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
LOG_FILE="${BUILD_DIR}/build.log"

CORE_NAME="NebulaPanel-core"
AGENT_NAME="NebulaPanel-agent"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

die() { err "$*"; exit 1; }

###############################################################################
# 参数解析
###############################################################################
usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --arch)          TARGET_ARCH="${2:-}"; shift 2 ;;
        --arch=*)        TARGET_ARCH="${1#*=}"; shift ;;
        --skip-frontend) SKIP_FRONTEND=1; shift ;;
        --skip-deps)     SKIP_DEPS=1; shift ;;
        --diag)          DIAG_ONLY=1; shift ;;
        --mirror)        MIRROR="${2:-auto}"; shift 2 ;;
        --mirror=*)      MIRROR="${1#*=}"; shift ;;
        -h|--help)       usage ;;
        *)               die "未知参数：$1（用 --help 查看用法）" ;;
    esac
done

mkdir -p "${BUILD_DIR}"
: > "${LOG_FILE}"

# 所有输出同时写日志
exec > >(tee -a "${LOG_FILE}") 2>&1

###############################################################################
# 基础环境
###############################################################################
detect_arch() {
    if [ -n "${TARGET_ARCH}" ]; then
        case "${TARGET_ARCH}" in
            amd64|arm64) ;;
            *) die "不支持的架构：${TARGET_ARCH}（仅 amd64 / arm64）" ;;
        esac
        return
    fi
    case "$(uname -m)" in
        x86_64|amd64)  TARGET_ARCH="amd64" ;;
        aarch64|arm64) TARGET_ARCH="arm64" ;;
        *) die "不支持的机器架构：$(uname -m)" ;;
    esac
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VER="${VERSION_ID:-unknown}"
    else
        OS_ID="unknown"; OS_VER="unknown"
    fi
    case "${OS_ID}" in
        ubuntu|debian|raspbian|linuxmint) PKG="apt" ;;
        centos|rhel|rocky|almalinux|fedora|openeuler|anolis) PKG="yum" ;;
        opensuse*|sles) PKG="zypper" ;;
        alpine) PKG="apk" ;;
        *) PKG="unknown" ;;
    esac
}

SUDO=""
prepare_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
        INSTALL_PREFIX="/usr/local"
        return
    fi
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        INSTALL_PREFIX="/usr/local"
    else
        SUDO=""
        INSTALL_PREFIX="${HOME}/.local"
        warn "非 root 且无 sudo，工具链将安装到 ${INSTALL_PREFIX}"
    fi
}

install_base_deps() {
    [ "${SKIP_DEPS}" = "1" ] && { warn "已跳过系统依赖安装"; return; }
    log "安装基础依赖（curl / xz / tar / git / ca-certificates）..."

    case "${PKG}" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            ${SUDO} apt-get update -y >>"${LOG_FILE}" 2>&1 || true
            ${SUDO} apt-get install -y curl xz-utils tar git ca-certificates build-essential >>"${LOG_FILE}" 2>&1 || true
            ;;
        yum)
            local mgr="yum"
            command -v dnf >/dev/null 2>&1 && mgr="dnf"
            ${SUDO} ${mgr} install -y curl xz tar git ca-certificates gcc gcc-c++ make >>"${LOG_FILE}" 2>&1 || true
            ;;
        zypper)
            ${SUDO} zypper -n install curl xz tar git ca-certificates gcc gcc-c++ make >>"${LOG_FILE}" 2>&1 || true
            ;;
        apk)
            ${SUDO} apk add --no-cache curl xz tar git ca-certificates build-base >>"${LOG_FILE}" 2>&1 || true
            ;;
        *)
            warn "未识别的包管理器（${OS_ID}），跳过依赖安装"
            ;;
    esac

    for c in curl tar; do
        if ! command -v "${c}" >/dev/null 2>&1; then
            die "缺少必要命令：${c}"
        fi
    done
    ok "基础依赖就绪"
}

###############################################################################
# 镜像选择
###############################################################################
probe() {
    # probe <url> → 0 可达 / 1 不可达
    curl -fsSL --connect-timeout 5 --max-time 12 -o /dev/null "$1" >/dev/null 2>&1
}

choose_mirror() {
    if [ "${MIRROR}" != "auto" ]; then
        log "使用指定镜像模式：${MIRROR}"
        return
    fi
    log "探测网络环境（决定是否走国内镜像）..."
    if probe "https://go.dev/dl/"; then
        MIRROR="global"
    else
        MIRROR="cn"
    fi
    ok "网络模式：${MIRROR}"
}

###############################################################################
# Go 工具链
###############################################################################
go_ok() {
    local have
    command -v go >/dev/null 2>&1 || return 1
    have="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"
    [ -z "${have}" ] && return 1
    # 需要 >= GO_VERSION
    [ "$(printf '%s\n%s\n' "${GO_VERSION}" "${have}" | sort -V | head -n1)" = "${GO_VERSION}" ]
}

ensure_go() {
    if go_ok; then
        ok "Go 已满足要求：$(go version)"
        return
    fi

    log "安装 Go ${GO_VERSION} ..."
    local tarball="go${GO_VERSION}.linux-${HOST_ARCH}.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    local urls=()
    if [ "${MIRROR}" = "cn" ]; then
        urls+=("https://golang.google.cn/dl/${tarball}")
        urls+=("https://mirrors.aliyun.com/golang/${tarball}")
        urls+=("https://go.dev/dl/${tarball}")
    else
        urls+=("https://go.dev/dl/${tarball}")
        urls+=("https://golang.google.cn/dl/${tarball}")
    fi

    local got=""
    local u
    for u in "${urls[@]}"; do
        log "  尝试 ${u}"
        if curl -fL --connect-timeout 15 --retry 2 -o "${tmp}/${tarball}" "${u}"; then
            got="${tmp}/${tarball}"; break
        fi
    done
    [ -n "${got}" ] || die "Go 下载失败，可手动安装 Go ${GO_VERSION} 后重试"

    ${SUDO} rm -rf "${INSTALL_PREFIX}/go"
    ${SUDO} tar -C "${INSTALL_PREFIX}" -xzf "${got}"
    rm -rf "${tmp}"

    export GOROOT="${INSTALL_PREFIX}/go"
    export PATH="${GOROOT}/bin:${PATH}"

    if [ -n "${SUDO}" ]; then
        ${SUDO} ln -sf "${GOROOT}/bin/go"    "${INSTALL_PREFIX}/bin/go"
        ${SUDO} ln -sf "${GOROOT}/bin/gofmt" "${INSTALL_PREFIX}/bin/gofmt"
    fi

    go_ok || die "Go 安装后版本仍不满足（需要 >= ${GO_VERSION}）"
    ok "Go 已安装：$(go version)"
}

configure_go_env() {
    export GOOS="linux"
    export GOARCH="${TARGET_ARCH}"
    export CGO_ENABLED="0"
    export GOTOOLCHAIN="local"

    if [ "${MIRROR}" = "cn" ]; then
        export GOPROXY="https://goproxy.cn,direct"
    else
        export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
    fi
    export GOSUMDB="${GOSUMDB:-sum.golang.org}"
    export GOFLAGS=""
    log "go env：GOOS=${GOOS} GOARCH=${GOARCH} CGO=${CGO_ENABLED} GOPROXY=${GOPROXY}"
}

###############################################################################
# Node.js
###############################################################################
node_ok() {
    command -v node >/dev/null 2>&1 || return 1
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    [ "${major}" -ge "${NODE_MAJOR}" ] 2>/dev/null
}

ensure_node() {
    if node_ok; then
        ok "Node.js 已满足要求：$(node --version)"
        return
    fi

    log "安装 Node.js v${NODE_MAJOR}.x ..."
    local idx_urls=()
    if [ "${MIRROR}" = "cn" ]; then
        idx_urls+=("https://npmmirror.com/mirrors/node/latest-v${NODE_MAJOR}.x/SHASUMS256.txt")
        idx_urls+=("https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt")
    else
        idx_urls+=("https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt")
        idx_urls+=("https://npmmirror.com/mirrors/node/latest-v${NODE_MAJOR}.x/SHASUMS256.txt")
    fi

    local sums=""
    local u
    for u in "${idx_urls[@]}"; do
        if sums="$(curl -fsSL --connect-timeout 15 --max-time 60 "${u}" 2>/dev/null)"; then
            break
        fi
        sums=""
    done
    [ -n "${sums}" ] || die "无法获取 Node.js 版本清单"

    local file
    file="$(printf '%s\n' "${sums}" | awk '{print $2}' | grep -E "linux-${NODE_ARCH}\.tar\.xz$" | head -n1)"
    [ -n "${file}" ] || die "在版本清单中找不到 linux-${NODE_ARCH} 包"

    local base="${u%/*}"
    local tmp
    tmp="$(mktemp -d)"
    log "  下载 ${file}"
    curl -fL --connect-timeout 15 --retry 2 -o "${tmp}/node.tar.xz" "${base}/${file}" \
        || die "Node.js 下载失败"

    local dir="${INSTALL_PREFIX}/lib/nodejs"
    ${SUDO} mkdir -p "${dir}"
    ${SUDO} tar -C "${dir}" -xJf "${tmp}/node.tar.xz"
    # 顶层目录名就是去掉 .tar.xz 的文件名
    local extracted="${file%.tar.xz}"
    rm -rf "${tmp}"

    local nb="${dir}/${extracted}/bin"
    ${SUDO} mkdir -p "${INSTALL_PREFIX}/bin"
    for b in node npm npx corepack; do
        if [ -e "${nb}/${b}" ]; then
            ${SUDO} ln -sf "${nb}/${b}" "${INSTALL_PREFIX}/bin/${b}"
        fi
    done

    export PATH="${INSTALL_PREFIX}/bin:${PATH}"
    hash -r 2>/dev/null || true

    node_ok || die "Node.js 安装后仍不可用"
    ok "Node.js 已安装：$(node --version)"
}

###############################################################################
# 构建
###############################################################################
build_frontend() {
    local fe="${REPO_ROOT}/frontend"
    [ -d "${fe}" ] || die "找不到前端目录：${fe}"

    log "安装前端依赖..."
    cd "${fe}" || die "无法进入 ${fe}"

    local npm_args=("--no-audit" "--no-fund")
    if [ "${MIRROR}" = "cn" ]; then
        npm config set registry https://registry.npmmirror.com >/dev/null 2>&1 || true
        log "npm registry 切换到 npmmirror"
    fi

    if [ -f package-lock.json ]; then
        if ! npm ci "${npm_args[@]}"; then
            warn "npm ci 失败，回退 npm install --legacy-peer-deps"
            npm install "${npm_args[@]}" --legacy-peer-deps || die "前端依赖安装失败"
        fi
    else
        npm install "${npm_args[@]}" --legacy-peer-deps || die "前端依赖安装失败"
    fi
    ok "前端依赖安装完成"

    log "构建前端（vite build --mode production）..."
    npm run build:pro || die "前端构建失败"

    local web="${REPO_ROOT}/core/cmd/server/web"
    [ -f "${web}/index.html" ] || die "前端产物缺失：${web}/index.html"
    ok "前端构建完成 → ${web}"
    cd "${REPO_ROOT}" || die "无法返回仓库根目录"
}

tidy_agent() {
    log "校验 agent 模块依赖（go mod tidy）..."
    cd "${REPO_ROOT}/agent" || die "找不到 agent 目录"
    if go mod tidy; then
        ok "agent 依赖已就绪"
    else
        warn "go mod tidy 失败，尝试直接构建（-mod=mod 自动补齐）"
    fi
    cd "${REPO_ROOT}" || die "无法返回仓库根目录"
}

build_core() {
    log "编译 ${CORE_NAME}（linux/${TARGET_ARCH}）..."
    cd "${REPO_ROOT}/core" || die "找不到 core 目录"
    rm -f "${BUILD_DIR}/${CORE_NAME}-${TARGET_ARCH}"

    # 注意：不给 core 跑 go mod tidy —— core 内存在 //go:build xpack 的源文件
    # 引用了未随 OSS 源码发布的企业包，tidy 会因这些文件解析失败。
    # 用 -mod=mod 让 go 在构建时按当前构建约束自动补齐 go.sum。
    if go build -mod=mod -trimpath -ldflags '-s -w' \
        -o "${BUILD_DIR}/${CORE_NAME}-${TARGET_ARCH}" ./cmd/server/main.go; then
        ok "${CORE_NAME} 编译完成"
    else
        err "${CORE_NAME} 编译失败，下面是完整诊断信息："
        diag_core
        cd "${REPO_ROOT}" || true
        return 1
    fi
    cd "${REPO_ROOT}" || die "无法返回仓库根目录"
}

build_agent() {
    log "编译 ${AGENT_NAME}（linux/${TARGET_ARCH}）..."
    cd "${REPO_ROOT}/agent" || die "找不到 agent 目录"
    rm -f "${BUILD_DIR}/${AGENT_NAME}-${TARGET_ARCH}"

    # agent 依赖 vm helper 脚本（若存在）
    if [ -f utils/vm/helper/prepare.sh ]; then
        bash utils/vm/helper/prepare.sh >>"${LOG_FILE}" 2>&1 || warn "vm helper 准备脚本返回非 0，忽略"
    fi

    if go build -mod=mod -trimpath -ldflags '-s -w' \
        -o "${BUILD_DIR}/${AGENT_NAME}-${TARGET_ARCH}" ./cmd/server/main.go; then
        ok "${AGENT_NAME} 编译完成"
    else
        err "${AGENT_NAME} 编译失败，下面是完整诊断信息："
        diag_agent
        cd "${REPO_ROOT}" || true
        return 1
    fi
    cd "${REPO_ROOT}" || die "无法返回仓库根目录"
}

###############################################################################
# 诊断
###############################################################################
diag_core() {
    echo "----------------- core 诊断开始 -----------------"
    ( cd "${REPO_ROOT}/core" && {
        echo "\$ go version";        go version
        echo "\$ go env GOOS GOARCH CGO_ENABLED GOPROXY GOMOD GOWORK"
        go env GOOS GOARCH CGO_ENABLED GOPROXY GOMOD GOWORK
        echo
        echo "\$ head -10 go.mod";   head -10 go.mod
        echo
        echo "\$ ls cmd/server";     ls -la cmd/server
        echo "\$ ls cmd/server/cmd"; ls -la cmd/server/cmd
        echo "\$ ls cmd/server/docs"; ls -la cmd/server/docs
        echo "\$ ls cmd/server/web"; ls -la cmd/server/web | head -20
        echo
        echo "\$ go list ./cmd/server/cmd"; go list ./cmd/server/cmd 2>&1 | head -40
        echo "\$ go list ./cmd/server/docs"; go list ./cmd/server/docs 2>&1 | head -40
        echo
        echo "\$ go build ./cmd/server/main.go（完整输出）"
        go build -mod=mod -o /dev/null ./cmd/server/main.go 2>&1 | head -80
    } )
    echo "----------------- core 诊断结束 -----------------"
}

diag_agent() {
    echo "----------------- agent 诊断开始 -----------------"
    ( cd "${REPO_ROOT}/agent" && {
        echo "\$ go version";  go version
        echo "\$ head -12 go.mod"; head -12 go.mod
        echo "\$ grep lego go.mod go.sum"; grep -n lego go.mod go.sum || true
        echo "\$ go build ./cmd/server/main.go（完整输出）"
        go build -mod=mod -o /dev/null ./cmd/server/main.go 2>&1 | head -80
    } )
    echo "----------------- agent 诊断结束 -----------------"
}

###############################################################################
# 打包
###############################################################################
package_all() {
    log "打包产物..."
    cd "${BUILD_DIR}" || die "无法进入 build 目录"

    local core="${CORE_NAME}-${TARGET_ARCH}"
    local agent="${AGENT_NAME}-${TARGET_ARCH}"
    [ -f "${core}" ]  || die "缺少 ${core}"
    [ -f "${agent}" ] || die "缺少 ${agent}"

    chmod 755 "${core}" "${agent}"

    local tgz="NebulaPanel-linux-${TARGET_ARCH}.tar.gz"
    rm -f "${tgz}" "${tgz}.sha256"
    tar -czf "${tgz}" "${core}" "${agent}"
    sha256sum "${tgz}" > "${tgz}.sha256"

    ok "打包完成："
    ls -lh "${core}" "${agent}" "${tgz}" "${tgz}.sha256"
}

###############################################################################
# 主流程
###############################################################################
main() {
    detect_arch
    detect_os
    prepare_sudo

    case "$(uname -m)" in
        x86_64|amd64)  HOST_ARCH="amd64"; NODE_ARCH="x64" ;;
        aarch64|arm64) HOST_ARCH="arm64"; NODE_ARCH="arm64" ;;
        *) die "不支持的机器架构：$(uname -m)" ;;
    esac

    log "仓库根目录：${REPO_ROOT}"
    log "系统：${OS_ID} ${OS_VER} / 主机架构：${HOST_ARCH} / 目标架构：${TARGET_ARCH}"

    install_base_deps
    choose_mirror
    ensure_go
    configure_go_env

    if [ "${DIAG_ONLY}" = "1" ]; then
        warn "诊断模式：只打印环境与编译错误，不产出二进制"
        diag_core
        diag_agent
        echo
        echo "日志文件：${LOG_FILE}"
        exit 0
    fi

    if [ "${SKIP_FRONTEND}" != "1" ]; then
        ensure_node
        build_frontend
    else
        warn "已跳过前端构建，使用现有 core/cmd/server/web"
        [ -f "${REPO_ROOT}/core/cmd/server/web/index.html" ] \
            || warn "警告：core/cmd/server/web/index.html 不存在，core 的 go:embed 会失败"
    fi

    tidy_agent

    local failed=0
    build_core  || failed=1
    build_agent || failed=1

    if [ "${failed}" -ne 0 ]; then
        echo
        err "构建失败。完整日志：${LOG_FILE}"
        echo "把上面「诊断」段落发我，我按真实报错改。"
        exit 1
    fi

    package_all

    echo
    ok "全部完成！"
    echo "  二进制目录：${BUILD_DIR}"
    echo "  完整日志  ：${LOG_FILE}"
    echo
    echo "  部署到本机可直接执行："
    echo "    sudo bash scripts/install.sh"
}

main "$@"
