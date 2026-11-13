﻿package service

import (
	"context"

	"github.com/NebulaPanel/nebulapanel/agent/constant"
	"github.com/NebulaPanel/nebulapanel/agent/global"
	"gorm.io/gorm"
)

func getTxAndContext() (tx *gorm.DB, ctx context.Context) {
	tx = global.DB.Begin()
	ctx = context.WithValue(context.Background(), constant.DB, tx)
	return
}

