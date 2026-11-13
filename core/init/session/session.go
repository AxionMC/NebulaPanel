﻿package session

import (
	"github.com/NebulaPanel/nebulapanel/core/global"
	"github.com/NebulaPanel/nebulapanel/core/init/session/psession"
)

func Init() {
	global.SESSION = psession.NewPSession("")
	global.LOG.Info("init in-memory session successfully")
}

