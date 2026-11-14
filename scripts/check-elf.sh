#!/usr/bin/env bash
#
# 校验交叉编译产物确实是目标架构的 Linux ELF 可执行文件
#
# 用法：
#   bash scripts/check-elf.sh <二进制路径> <期望架构 amd64|arm64>
#
# 退出码：
#   0 = 校验通过
#   1 = 文件缺失 / 不是 ELF / 架构不符
#

set -uo pipefail

BIN="${1:-}"
WANT_ARCH="${2:-}"

if [ -z "${BIN}" ] || [ -z "${WANT_ARCH}" ]; then
    echo "用法: $0 <二进制路径> <amd64|arm64>" >&2
    exit 1
fi

if [ ! -f "${BIN}" ]; then
    echo "[FAIL] 文件不存在：${BIN}" >&2
    exit 1
fi

if [ ! -s "${BIN}" ]; then
    echo "[FAIL] 文件为空：${BIN}" >&2
    exit 1
fi

# 1. ELF 魔数（0x7F 'E' 'L' 'F'）
MAGIC="$(head -c 4 "${BIN}" | od -An -tx1 | tr -d ' \n')"
if [ "${MAGIC}" != "7f454c46" ]; then
    echo "[FAIL] 不是 ELF 文件（magic=${MAGIC}）：${BIN}" >&2
    exit 1
fi

# 2. ELF 头 e_machine（偏移 0x12，2 字节小端）
#    amd64 = 0x3E (62)   arm64 = 0xB7 (183)
MACHINE_HEX="$(dd if="${BIN}" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')"
case "${MACHINE_HEX}" in
    3e00) FOUND_ARCH="amd64" ;;
    b700) FOUND_ARCH="arm64" ;;
    0300) FOUND_ARCH="386" ;;
    2800) FOUND_ARCH="arm" ;;
    *)    FOUND_ARCH="unknown(${MACHINE_HEX})" ;;
esac

if [ "${FOUND_ARCH}" != "${WANT_ARCH}" ]; then
    echo "[FAIL] 架构不符：期望 ${WANT_ARCH}，实际 ${FOUND_ARCH} — ${BIN}" >&2
    exit 1
fi

# 3. 辅助信息（有 file 命令时打印，便于排查）
if command -v file >/dev/null 2>&1; then
    echo "[ OK ] $(file -b "${BIN}")  ← ${BIN}"
else
    echo "[ OK ] ${FOUND_ARCH} ELF  $(stat -c %s "${BIN}" 2>/dev/null || wc -c < "${BIN}") bytes  ← ${BIN}"
fi

exit 0
