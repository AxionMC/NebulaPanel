package global

import (
	"os"
	"strings"

	"github.com/NebulaPanel/nebulapanel/core/init/auth"
	"github.com/NebulaPanel/nebulapanel/core/init/session/psession"
	"github.com/go-playground/validator/v10"
	"github.com/nicksnyder/go-i18n/v2/i18n"
	"github.com/robfig/cron/v3"
	"github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"gorm.io/gorm"
)

var (
	DB      *gorm.DB
	AlertDB *gorm.DB
	TaskDB  *gorm.DB
	AgentDB *gorm.DB
	LOG     *logrus.Logger
	CONF    ServerConfig
	VALID   *validator.Validate
	SESSION *psession.PSession
	Viper   *viper.Viper

	I18n       *i18n.Localizer
	I18nForCmd *i18n.Localizer

	Cron *cron.Cron

	ScriptSyncJobID cron.EntryID

	IPTracker *auth.IPTracker
)

type DBOption func(*gorm.DB) *gorm.DB

// resourceURLOverride 允许通过环境变量覆盖资源站地址。
// 容器化部署时资源站可能与官方不同（语言包、GeoIP、应用图标等），
// 可用 NP_RESOURCE_URL 指向自有镜像：
//
//	environment:
//	  - NP_RESOURCE_URL=https://resource.example.com
//
// 留空则使用默认官方地址。
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
	if CONF.Base.Edition != "intl" {
		return "https://resource.fit2cloud.com/1Panel/package/v2"
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
	if CONF.Base.Edition != "intl" {
		return "https://resource.fit2cloud.com/1Panel/resource/v2"
	}
	return "https://resource.fit2cloud.com/1Panel/resource/v2/resource"
}
func AppRepoURL() string {
	if v := os.Getenv("NP_APP_REPO_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	if CONF.Base.IsEnterprise {
		return "https://apps-assets.fit2cloud.com"
	}
	if CONF.Base.Edition != "intl" {
		return "https://apps-assets.fit2cloud.com"
	}
	return "https://apps-assets.fit2cloud.com"
}

