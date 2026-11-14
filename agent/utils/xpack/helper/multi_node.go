package helper

import (
	"crypto/tls"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/NebulaPanel/nebulapanel/agent/app/dto"
	"github.com/NebulaPanel/nebulapanel/agent/app/model"
	"github.com/NebulaPanel/nebulapanel/agent/buserr"
	"github.com/NebulaPanel/nebulapanel/agent/global"
	"github.com/NebulaPanel/nebulapanel/agent/utils/common"
	"github.com/NebulaPanel/nebulapanel/agent/utils/xpack/providers"
	"github.com/gin-gonic/gin"
)

type multiNodeHelper struct{}

func NewIMultiNodeProvider() providers.MultiNodeProvider {
	return &multiNodeHelper{}
}

func (m *multiNodeHelper) RemoveTamper(website string) {}

func (m *multiNodeHelper) StartClam(startClam *model.Clam, isUpdate bool) (int, error) {
	return 0, buserr.New("ErrXpackNotFound")
}

func (m *multiNodeHelper) LoadNodeInfo(isBase bool) (model.NodeInfo, error) {
	var info model.NodeInfo

	// ctl_conf（/usr/local/bin/npctl）是宿主机的键值配置，
	// 在容器化部署下可能不存在或未挂载。
	// 这里使用不带 panic 的读取 + 合理默认值，
	// 避免单机版因为缺少该文件而启动失败（crash-loop）。
	info.BaseDir = common.LoadParamsWithoutPanic("BASE_DIR")
	if len(info.BaseDir) == 0 {
		info.BaseDir = defaultBaseDir()
	}

	info.Version = common.LoadParamsWithoutPanic("ORIGINAL_VERSION")
	if len(info.Version) == 0 {
		info.Version = defaultVersion()
	}

	info.Scope = "master"
	global.IsMaster = true
	return info, nil
}

// defaultBaseDir 返回默认安装根目录。
// 优先级：环境变量 NP_BASE_DIR > /opt（与官方安装脚本一致）
func defaultBaseDir() string {
	if v := os.Getenv("NP_BASE_DIR"); len(v) > 0 {
		return v
	}
	if v := os.Getenv("BASE_DIR"); len(v) > 0 {
		return v
	}
	return "/opt"
}

// defaultVersion 返回默认版本号，与发布版本保持一致
func defaultVersion() string {
	if v := os.Getenv("NP_VERSION"); len(v) > 0 {
		return v
	}
	return "V1.0.0"
}

func (m *multiNodeHelper) GetImagePrefix() string {
	return ""
}

func (m *multiNodeHelper) IsUseCustomApp() bool {
	return false
}

func (m *multiNodeHelper) IsXpack() bool {
	return false
}

func (m *multiNodeHelper) LoadRequestTransport() *http.Transport {
	return &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		DialContext: (&net.Dialer{
			Timeout:   60 * time.Second,
			KeepAlive: 60 * time.Second,
		}).DialContext,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
		IdleConnTimeout:       15 * time.Second,
	}
}

func (m *multiNodeHelper) ValidateCertificate(c *gin.Context) bool {
	return true
}

func (m *multiNodeHelper) PushSSLToNode(websiteSSL *model.WebsiteSSL) error {
	return nil
}

func (m *multiNodeHelper) GetAgentInfo() (*dto.AgentInfo, error) {
	return nil, nil
}

func (m *multiNodeHelper) PushPHPExtensionsToNode(req dto.PHPExtensionsPush) error {
	return buserr.New("ErrXpackNotFound")
}

