package kvm

import (
	"github.com/NebulaPanel/nebulapanel/agent/app/service"
	"github.com/NebulaPanel/nebulapanel/agent/global"
	vmHelper "github.com/NebulaPanel/nebulapanel/agent/utils/vm/helper"
)

func Init() {
	if helperPath, embedded, err := vmHelper.EnsureEmbeddedHelper(); err != nil {
		global.LOG.Warnf("sync embedded kvm helper failed, err: %v", err)
	} else if embedded {
		global.LOG.Infof("embedded kvm helper synced: %s", helperPath)
	}
	if err := service.NewIVMService().SyncResourcesOnStartup(); err != nil {
		global.LOG.Warnf("sync VM resources on startup failed, err: %v", err)
	}
}

