package viper

import (
	"bytes"
	"fmt"
	"os"
	"path"

	"github.com/NebulaPanel/nebulapanel/core/cmd/server/conf"
	"github.com/NebulaPanel/nebulapanel/core/global"
	"github.com/NebulaPanel/nebulapanel/core/utils/ctl_conf"
	"github.com/fsnotify/fsnotify"
	"github.com/spf13/viper"
	"gopkg.in/yaml.v3"
)

func Init() {
	baseDir := "/opt"
	port := "9999"
	mode := ""
	version := "v2.0.0"
	username, password, entrance, language, edition := "", "", "", "zh", ""
	v := viper.NewWithOptions()
	v.SetConfigType("yaml")

	config := global.ServerConfig{}
	if err := yaml.Unmarshal(conf.AppYaml, &config); err != nil {
		panic(err)
	}
	if config.Base.Mode != "" {
		mode = config.Base.Mode
	}

	// 运行模式以运行时配置为准：
	// conf.AppYaml 是编译期嵌入的默认配置（mode: dev），
	// 容器化部署时会在 /opt/NebulaPanel/conf/app.yaml 写入 mode: stable。
	// 因此这里优先读运行时文件的 mode，读不到才回退编译期默认值。
	// 否则永远走 dev 分支，ctl_conf 中的 ORIGINAL_PORT 等一概不生效。
	appConfPath := path.Join("/opt/NebulaPanel/conf", "app.yaml")
	if data, rerr := os.ReadFile(appConfPath); rerr == nil {
		runtimeConf := global.ServerConfig{}
		if yerr := yaml.Unmarshal(data, &runtimeConf); yerr == nil && runtimeConf.Base.Mode != "" {
			mode = runtimeConf.Base.Mode
		}
	}

	_, err := os.Stat(appConfPath)
	if mode == "dev" && err == nil {
		v.SetConfigName("app")
		v.AddConfigPath(path.Join("/opt/NebulaPanel/conf"))
		if err := v.ReadInConfig(); err != nil {
			panic(fmt.Errorf("fatal error config file: %s", err))
		}
	} else {
		// stable 模式（容器化部署）下，配置来自宿主机的 ctl_conf。
		// 该文件是 /usr/local/bin/npctl，由安装脚本生成并挂载进容器。
		// 若缺失或未挂载，不能让进程直接 panic —— 使用可解释的默认值回退，
		// 否则容器会陷入 crash-loop。
		baseDir = loadOr("BASE_DIR", baseDir)
		port = loadOr("ORIGINAL_PORT", port)
		version = loadOr("ORIGINAL_VERSION", version)
		username = loadOr("ORIGINAL_USERNAME", username)
		password = loadOr("ORIGINAL_PASSWORD", password)
		entrance = loadOr("ORIGINAL_ENTRANCE", entrance)
		language = loadOr("LANGUAGE", language)
		edition = ctl_conf.LoadWithoutPanic("PANEL_EDITION")

		reader := bytes.NewReader(conf.AppYaml)
		if err := v.ReadConfig(reader); err != nil {
			panic(fmt.Errorf("fatal error config file: %s", err))
		}
	}
	v.OnConfigChange(func(e fsnotify.Event) {
		if err := v.Unmarshal(&global.CONF); err != nil {
			panic(err)
		}
	})
	serverConfig := global.ServerConfig{}
	if err := v.Unmarshal(&serverConfig); err != nil {
		panic(err)
	}
	_, err = os.Stat(appConfPath)
	if mode == "dev" && err == nil {
		if serverConfig.Base.InstallDir != "" {
			baseDir = serverConfig.Base.InstallDir
		}
		if serverConfig.Conn.Port != "" {
			port = serverConfig.Conn.Port
		}
		if serverConfig.Base.Version != "" {
			version = serverConfig.Base.Version
		}
		if serverConfig.Base.Username != "" {
			username = serverConfig.Base.Username
		}
		if serverConfig.Base.Password != "" {
			password = serverConfig.Base.Password
		}
		if serverConfig.Conn.Entrance != "" {
			entrance = serverConfig.Conn.Entrance
		}
	}

	global.CONF = serverConfig
	global.CONF.Base.InstallDir = baseDir
	global.CONF.Base.IsDemo = v.GetBool("base.is_demo")
	global.CONF.Base.IsOffline = v.GetBool("base.is_offline")
	if edition == "intl" {
		global.CONF.Base.Edition = "intl"
	} else {
		global.CONF.Base.Edition = "cn"
	}
	global.CONF.Base.Version = version
	global.CONF.Base.Username = username
	global.CONF.Base.Password = password
	global.CONF.Base.Language = language
	global.CONF.Base.ChangeUserInfo = loadChangeInfo()
	global.CONF.Conn.Entrance = entrance
	global.CONF.Conn.Port = port
	global.Viper = v
}

func loadChangeInfo() string {
	return ctl_conf.LoadWithoutPanic("CHANGE_USER_INFO")
}

// loadOr 依次尝试：ctl_conf 键值 → 同名环境变量 → 默认值。
// 用于容器化部署下 ctl_conf 缺失时不中断启动。
//
// 环境变量名与键名一致（如 ORIGINAL_PORT），
// 便于在 docker-compose 的 environment 段直接覆盖端口等配置：
//
//	environment:
//	  - ORIGINAL_PORT=8700
func loadOr(key, fallback string) string {
	if v := ctl_conf.LoadWithoutPanic(key); len(v) > 0 {
		return v
	}
	if v := os.Getenv(key); len(v) > 0 {
		return v
	}
	return fallback
}

