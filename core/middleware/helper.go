package middleware

import (
	"strings"

	"github.com/NebulaPanel/nebulapanel/core/utils/publicshare"
)

func ShouldProxyToAgent(reqPath string) bool {
	if strings.HasPrefix(reqPath, "/NebulaPanel/swagger") || !strings.HasPrefix(reqPath, "/api/v2") {
		return false
	}
	if strings.HasPrefix(reqPath, "/api/v2/core") && !strings.HasPrefix(reqPath, "/api/v2/core/xpack") {
		return false
	}
	return true
}

func IsPublicFileShareAPI(reqPath string) bool {
	return publicshare.IsAPI(reqPath)
}

