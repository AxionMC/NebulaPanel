#!/usr/bin/env bash
#
# 下载 NebulaPanel KVM 辅助二进制到 agent/utils/vm/helper/bin/
#
# 说明：
#   - 这两个文件体积较大、按架构分发，不纳入版本库
#   - 缺失时 agent 依然可以编译（embed 使用 all:bin 目录形式），
#     仅 KVM 功能在运行期提示「NebulaPanel-kvm 不存在」
#   - 下载源可用环境变量覆盖：
#       NP_KVM_BASE_URL=https://your.mirror/kvm
#
# 用法：
#   bash agent/utils/vm/helper/prepare.sh            # 下载缺失的架构
#   SKIP_KVM_HELPER=1 bash .../prepare.sh            # 完全跳过（CI 快构建）
#

set -uo pipefail

helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${helper_dir}/bin"
mkdir -p "${bin_dir}"

# 默认下载源（可在 CI/本地通过环境变量覆盖为自有 OSS）
BASE_URL="${NP_KVM_BASE_URL:-https://resource.nebulapanel.pro/kvm}"

if [ "${SKIP_KVM_HELPER:-0}" = "1" ]; then
    echo "[prepare] SKIP_KVM_HELPER=1，跳过 KVM 辅助二进制下载"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[prepare] 警告：未找到 curl，跳过 KVM 辅助二进制下载（不影响编译）" >&2
    exit 0
fi

DOWNLOADED=0
SKIPPED=0
FAILED=0

for arch in amd64 arm64; do
    target="${bin_dir}/NebulaPanel-kvm-${arch}"

    if [ -s "${target}" ]; then
        echo "[prepare] 已存在：NebulaPanel-kvm-${arch}（$(wc -c < "${target}") 字节），跳过"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    url="${BASE_URL}/NebulaPanel-kvm-${arch}"
    echo "[prepare] 下载 ${url}"
    tmp="${target}.download"

    if curl --fail --location --retry 2 --connect-timeout 15 --max-time 300 \
            --silent --show-error "${url}" --output "${tmp}" 2>/dev/null \
       && [ -s "${tmp}" ]; then
        chmod 755 "${tmp}"
        mv "${tmp}" "${target}"
        echo "[prepare] 完成：NebulaPanel-kvm-${arch}（$(wc -c < "${target}") 字节）"
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        rm -f "${tmp}"
        echo "[prepare] 警告：下载失败 ${url}" >&2
        echo "[prepare]        编译不受影响，仅 KVM 功能不可用" >&2
        FAILED=$((FAILED + 1))
    fi
done

echo "[prepare] 结果：新下载 ${DOWNLOADED}，已存在 ${SKIPPED}，失败 ${FAILED}"

# 下载失败不视为构建失败 —— embed 已改为可选的目录形式
exit 0
