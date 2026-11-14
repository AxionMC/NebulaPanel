package job

import (
	"github.com/NebulaPanel/nebulapanel/agent/app/service"
	"github.com/NebulaPanel/nebulapanel/agent/global"
)

type containerImageCheckUpdate struct{}

func NewContainerImageCheckUpdateJob() *containerImageCheckUpdate {
	return &containerImageCheckUpdate{}
}
func (j *containerImageCheckUpdate) Run() {
	status, err := service.GetContainerImageCheckUpdateStatus()
	if err != nil {
		global.LOG.Errorf("load container image update schedule: %v", err)
		return
	}
	if status.Enabled {
		if _, err := service.StartContainerImageCheckUpdate(); err != nil {
			global.LOG.Errorf("start container image update check: %v", err)
		}
	}
}

