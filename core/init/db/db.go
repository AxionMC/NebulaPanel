﻿package db

import (
	"path"

	"github.com/NebulaPanel/nebulapanel/core/global"
	"github.com/NebulaPanel/nebulapanel/core/utils/common"
)

func Init() {
	global.DB = common.LoadDBConnByPath(path.Join(global.CONF.Base.InstallDir, "NebulaPanel/db/core.db"), "core")
	global.TaskDB = common.LoadDBConnByPath(path.Join(global.CONF.Base.InstallDir, "NebulaPanel/db/task.db"), "task")
	global.AgentDB = common.LoadDBConnByPath(path.Join(global.CONF.Base.InstallDir, "NebulaPanel/db/agent.db"), "agent")
	global.AlertDB = common.LoadDBConnByPath(path.Join(global.CONF.Base.InstallDir, "NebulaPanel/db/alert.db"), "alert")
}

