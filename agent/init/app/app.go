package app

import (
	"github.com/NebulaPanel/nebulapanel/agent/utils/docker"
)

func Init() {
	go func() {
		_ = docker.CreateDefaultDockerNetwork()
	}()
}

