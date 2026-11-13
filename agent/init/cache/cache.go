﻿package cache

import (
	"github.com/NebulaPanel/nebulapanel/agent/global"
	cachedb "github.com/NebulaPanel/nebulapanel/agent/init/cache/db"
)

func Init() {
	global.CACHE = cachedb.NewCacheDB()
}

