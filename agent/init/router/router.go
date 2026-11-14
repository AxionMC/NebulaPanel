package router

import (
	v2 "github.com/NebulaPanel/nebulapanel/agent/app/api/v2"
	"github.com/NebulaPanel/nebulapanel/agent/app/service"
	"github.com/NebulaPanel/nebulapanel/agent/global"
	"github.com/NebulaPanel/nebulapanel/agent/i18n"
	"github.com/NebulaPanel/nebulapanel/agent/middleware"
	rou "github.com/NebulaPanel/nebulapanel/agent/router"
	"github.com/gin-gonic/gin"
)

var (
	Router *gin.Engine
)

func Routers() *gin.Engine {
	if err := service.ConfigurePanelMCPTasks(); err != nil {
		panic(err)
	}
	Router = gin.Default()
	Router.Use(i18n.UseI18n())
	Router.Use(middleware.MCPErrorMetadata())
	registerMCPRuntime(Router)

	PrivateGroup := Router.Group("/api/v2")
	if !global.IsMaster {
		PrivateGroup.Use(middleware.Certificate())
	}
	PrivateGroup.Use(middleware.OperationResolveMeta())
	PrivateGroup.Use(v2.PanelMCPTaskAccess())
	PrivateGroup.Use(v2.MCPBusinessDispatch())
	for _, router := range rou.RouterGroupApp {
		router.InitRouter(PrivateGroup)
	}
	PrivateGroup.GET("/health/check", v2.ApiGroupApp.BaseApi.CheckHealth)

	return Router
}

