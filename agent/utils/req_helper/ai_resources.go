package req_helper

import (
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/NebulaPanel/nebulapanel/agent/constant"
	"github.com/NebulaPanel/nebulapanel/agent/global"
)

func LoadAIResource(directory, localVersion string) ([]byte, string, error) {
	baseURL := fmt.Sprintf("%s/%s", global.ResourceURL(), directory)
	versionURL := fmt.Sprintf("%s/version.txt?t=%d", baseURL, time.Now().UnixNano())
	_, versionData, err := HandleRequest(versionURL, http.MethodGet, constant.TimeOut20s)
	if err != nil {
		return nil, "", fmt.Errorf("load %s version failed: %w", directory, err)
	}
	version := strings.TrimSpace(string(versionData))
	if version == "" {
		return nil, "", errors.New("remote resource version is empty")
	}
	if version == strings.TrimSpace(localVersion) {
		return nil, version, nil
	}
	_, data, err := HandleRequest(baseURL+"/data.yaml?version="+url.QueryEscape(version), http.MethodGet, constant.TimeOut20s)
	if err != nil {
		return nil, "", fmt.Errorf("load %s data.yaml failed: %w", directory, err)
	}
	return data, version, nil
}

