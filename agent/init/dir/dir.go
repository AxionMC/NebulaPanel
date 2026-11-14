package dir

import (
	"path"

	"github.com/NebulaPanel/nebulapanel/agent/global"
	"github.com/NebulaPanel/nebulapanel/agent/utils/files"
)

func Init() {
	fileOp := files.NewFileOp()
	baseDir := global.CONF.Base.InstallDir
	_, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/docker/compose/"))

	global.Dir.BaseDir, _ = fileOp.CreateDirWithPath(true, baseDir)
	global.Dir.DataDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel"))
	global.Dir.DbDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/db"))
	global.Dir.LogDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/log"))
	global.Dir.TaskDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/log/task"))
	global.Dir.TmpDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/tmp"))

	global.Dir.AppDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/apps"))
	global.Dir.ResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource"))
	global.Dir.IconCacheDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/icon"))
	global.Dir.AppResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/apps"))
	global.Dir.AppInstallDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/apps"))
	global.Dir.LocalAppResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/apps/local"))
	global.Dir.LocalAppInstallDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/apps/local"))
	global.Dir.RemoteAppResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/apps/remote"))
	global.Dir.CustomAppResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/apps/custom"))
	global.Dir.OfflineAppResourceDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/resource/offline"))
	global.Dir.RuntimeDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/runtime"))
	global.Dir.RecycleBinDir, _ = fileOp.CreateDirWithPath(true, "/.NebulaPanel_clash")
	global.Dir.SSLLogDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/log/ssl"))
	global.Dir.McpDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/mcp"))
	global.Dir.ConvertLogDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/log/convert"))
	global.Dir.FirewallDir, _ = fileOp.CreateDirWithPath(true, path.Join(baseDir, "NebulaPanel/firewall"))
}

