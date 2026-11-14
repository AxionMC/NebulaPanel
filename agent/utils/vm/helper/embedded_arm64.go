//go:build arm64

package helper

import "embed"

// 说明见 embedded_amd64.go：用 all:bin 目录嵌入，允许 bin/ 内暂时没有真实二进制。
//
//go:embed all:bin
var embeddedBin embed.FS

const helperFileName = "bin/NebulaPanel-kvm-arm64"

func embeddedHelperBytes() ([]byte, bool) {
	data, err := embeddedBin.ReadFile(helperFileName)
	if err != nil || len(data) == 0 {
		return nil, false
	}
	return data, true
}
