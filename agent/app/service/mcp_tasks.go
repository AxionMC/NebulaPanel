package service

import (
	"github.com/NebulaPanel/nebulapanel/agent/constant"
	"github.com/NebulaPanel/nebulapanel/agent/utils/taskscope"
)

func ConfigurePanelMCPTasks() error {
	return taskscope.Configure(taskscope.Rule{Scope: constant.TaskScopePanelMCP, Restricted: true, ExternalExecutor: true})
}

