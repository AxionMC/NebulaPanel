﻿//go:build !xpack && !enterprise

package xpack

import (
	"github.com/NebulaPanel/nebulapanel/core/utils/xpack/helper"
	"github.com/gin-gonic/gin"
)

var AuthProvider = helper.NewIAuthProvider()

var MultiNodeProvider = helper.NewIMultiNodeProvider()

func IsMasterProductPro() bool {
	return false
}

func VMCountLimit(_ *gin.Context) int {
	return 1
}

