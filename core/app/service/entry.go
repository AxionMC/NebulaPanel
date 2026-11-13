﻿package service

import "github.com/NebulaPanel/nebulapanel/core/app/repo"

var (
	commandRepo    = repo.NewICommandRepo()
	settingRepo    = repo.NewISettingRepo()
	backupRepo     = repo.NewIBackupRepo()
	logRepo        = repo.NewILogRepo()
	groupRepo      = repo.NewIGroupRepo()
	upgradeLogRepo = repo.NewIUpgradeLogRepo()

	agentRepo  = repo.NewIAgentRepo()
	scriptRepo = repo.NewIScriptRepo()
)

