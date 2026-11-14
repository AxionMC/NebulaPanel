#!/usr/bin/env bash
#
# 检查仓库内文本文件是否带 UTF-8 BOM（EF BB BF）
#
# 为什么需要：
#   - go.mod 带 BOM → go: errors parsing go.mod: go.mod:1: unexpected input character '\ufeff'
#   - package.json 带 BOM → vite/rolldown 报 [JSON_PARSE] expected value at line 1 column 1
#   - *.sh 带 BOM → Linux 报 bad interpreter: /usr/bin/env bash^M
#
# 用法：
#   bash scripts/check-bom.sh          # 检查，发现问题退出码 1
#   bash scripts/check-bom.sh --fix    # 就地剥离 BOM
#
# 实现说明：用单次 grep -P 扫描全部目标文件，避免逐文件 spawn 进程。
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# 目标文件：按扩展名/文件名筛选
# 注意：末尾的 "$@" 必须传下去，调用方会用它追加 -print0
collect_files() {
    find . -type f \
        -not -path './.git/*' \
        -not -path '*/node_modules/*' \
        -not -path './build/*' \
        -not -path '*/dist/*' \
        -not -path './.history/*' \
        \( -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
           -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' -o -name '*.json' \
           -o -name '*.yml' -o -name '*.yaml' -o -name '*.scss' -o -name '*.css' \
           -o -name '*.less' -o -name '*.md' -o -name '*.mod' -o -name '*.sum' \
           -o -name '*.sh' -o -name '*.bash' -o -name '*.html' -o -name '*.htm' \
           -o -name '*.properties' -o -name '*.toml' -o -name '*.ini' -o -name '*.conf' \
           -o -name '*.txt' -o -name '*.proto' \
           -o -name 'go.mod' -o -name 'go.sum' -o -name 'Makefile' -o -name 'VERSION' \
           -o -name 'Dockerfile' -o -name '.gitignore' -o -name '.gitattributes' \
           -o -name '.dockerignore' \) \
        "$@"
}

# 单次 grep 找出带 BOM 的文件；grep -l 带 -P 用 PCRE 匹配字节序列
scan_bom_files() {
    collect_files -print0 \
        | xargs -0 -r grep -lP '^\xEF\xBB\xBF' -- 2>/dev/null
}

# 兜底：grep 不支持 -P 时，退回逐文件判断（较慢但可用）
scan_bom_files_awk() {
    collect_files -print0 | while IFS= read -r -d '' f; do
        if [ "$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
            echo "$f"
        fi
    done
}

# 探测 grep 是否支持 -P（PCRE）
if printf '\xEF\xBB\xBF' | grep -qP '^\xEF\xBB\xBF' 2>/dev/null; then
    FILES="$(scan_bom_files)"
else
    echo "（当前 grep 不支持 -P，改用逐文件扫描，速度较慢）"
    FILES="$(scan_bom_files_awk)"
fi

if [ -z "${FILES}" ]; then
    echo "OK 未发现带 BOM 的文本文件"
    exit 0
fi

if [ "${FIX}" = "0" ]; then
    echo "发现以下文件带 UTF-8 BOM："
    printf '%s\n' "${FILES}" | sed 's/^/  /'
    echo ""
    echo "修复：bash scripts/check-bom.sh --fix"
    exit 1
fi

FIXED=0
FAIL=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if tail -c +4 "$f" > "$f.__nobom" 2>/dev/null && mv "$f.__nobom" "$f"; then
        FIXED=$((FIXED + 1))
        echo "  已剥离: $f"
    else
        rm -f "$f.__nobom" 2>/dev/null
        echo "  剥离失败: $f" >&2
        FAIL=$((FAIL + 1))
    fi
done <<< "${FILES}"

echo ""
echo "已剥离 ${FIXED} 个，失败 ${FAIL} 个"
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
