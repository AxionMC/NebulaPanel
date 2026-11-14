//go:build amd64

package helper

import _ "embed"

//go:embed bin/NebulaPanel-kvm-amd64
var embeddedHelper []byte

func embeddedHelperBytes() ([]byte, bool) {
	return embeddedHelper, len(embeddedHelper) > 0
}

