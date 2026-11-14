package middleware

import (
	"github.com/NebulaPanel/nebulapanel/core/utils/mcpapi"
	"github.com/gin-gonic/gin"
)

func MCPDomainPolicy(c *gin.Context) bool {
	return c.Request.URL.Path == "/mcp" && c.GetBool("MCP_WEBSITE_PROXY") ||
		mcpapi.IsRequest(c.Request) && c.GetBool("MCP_API_AUTH")
}

