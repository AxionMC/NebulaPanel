//go:build amd64

package helper

import "embed"

// 使用目录通配形式嵌入：bin/ 目录只要存在（哪怕只有一个占位文件）就能通过编译。
// 真实的 NebulaPanel-kvm-amd64 由 prepare.sh 在构建前下载放入 bin/。
// 未放入时 ReadFile 返回错误，embeddedHelperBytes 返回 ok=false，
// 上层 EnsureEmbeddedHelper 会跳过释放，KVM 功能在运行期提示“NebulaPanel-kvm 不存在”。
//
//go:embed all:bin
var embeddedBin embed.FS

const helperFileName = "bin/NebulaPanel-kvm-amd64"

func embeddedHelperBytes() ([]byte, bool) {
	data, err := embeddedBin.ReadFile(helperFileName)
	if err != nil || len(data) == 0 {
		return nil, false
	}
	return data, true
}
