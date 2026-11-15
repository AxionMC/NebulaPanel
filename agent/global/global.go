package global

import (
	"context"
	"os"
	"strings"
	"sync"

	badger_db "github.com/NebulaPanel/nebulapanel/agent/init/cache/db"
	"github.com/go-playground/validator/v10"
	"github.com/nicksnyder/go-i18n/v2/i18n"
	"github.com/robfig/cron/v3"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"gorm.io/gorm"
)

var (
	DB           *gorm.DB
	MonitorDB    *gorm.DB
	GPUMonitorDB *gorm.DB
	TaskDB       *gorm.DB
	CoreDB       *gorm.DB
	AlertDB      *gorm.DB

	LOG   *logrus.Logger
	CONF  ServerConfig
	VALID *validator.Validate
	CACHE *badger_db.Cache
	Viper *viper.Viper

	Dir SystemDir

	Cron             *cron.Cron
	MonitorCronID    cron.EntryID
	GPUMonitorCronID cron.EntryID

	CleanupVLLMMonitor func(uint) error

	IsMaster bool

	I18n *i18n.Localizer

	AlertBaseJobID     cron.EntryID
	AlertResourceJobID cron.EntryID

	TaskCtxMap = make(map[string]context.CancelFunc)
	taskCtxMu  sync.RWMutex
)

func RegisterTaskCancel(taskID string, cancel context.CancelFunc) {
	taskCtxMu.Lock()
	defer taskCtxMu.Unlock()
	TaskCtxMap[taskID] = cancel
}

func LoadTaskCancel(taskID string) (context.CancelFunc, bool) {
	taskCtxMu.RLock()
	defer taskCtxMu.RUnlock()
	cancel, ok := TaskCtxMap[taskID]
	return cancel, ok
}

func RemoveTaskCancel(taskID string) {
	taskCtxMu.Lock()
	defer taskCtxMu.Unlock()
	delete(TaskCtxMap, taskID)
}

// 资源站地址支持环境变量覆盖，便于容器化部署指向自有镜像：
//
//	environment:
//	  - NP_RESOURCE_URL=https://resource.example.com
//	  - NP_APP_REPO_URL=https://apps.example.com
//
// 未设置时回退到官方地址。
func resourceURLOverride() string {
	return strings.TrimRight(os.Getenv("NP_RESOURCE_URL"), "/")
}

func RepoURL() string {
	if v := resourceURLOverride(); v != "" {
		return v + "/package/v2"
	}
	if CONF.Base.IsEnterprise {
		return "https://resource.fit2cloud.com/1Panel/package/enterprise"
	}
	return "https://resource.fit2cloud.com/1Panel/package/v2"
}
func ResourceURL() string {
	if v := resourceURLOverride(); v != "" {
		return v + "/resource/v2"
	}
	if CONF.Base.IsEnterprise {
		return "https://resource.fit2cloud.com/1Panel/resource/v2"
	}
	return "https://resource.fit2cloud.com/1Panel/resource/v2"
}
func AppRepoURL() string {
	if v := os.Getenv("NP_APP_REPO_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	return "https://apps-assets.fit2cloud.com"
}

