﻿package cmd

import (
	"fmt"
	"os"
	"path"
	"sort"
	"strings"

	"github.com/NebulaPanel/nebulapanel/core/global"
	"github.com/NebulaPanel/nebulapanel/core/i18n"
	cmdUtils "github.com/NebulaPanel/nebulapanel/core/utils/cmd"
	"github.com/NebulaPanel/nebulapanel/core/utils/common"
	"github.com/NebulaPanel/nebulapanel/core/utils/controller"
	"github.com/NebulaPanel/nebulapanel/core/utils/ctl_conf"
	"github.com/NebulaPanel/nebulapanel/core/utils/files"

	"github.com/spf13/cobra"
)

func init() {
	RootCmd.AddCommand(restoreCmd)
}

var restoreCmd = &cobra.Command{
	Use: "restore",
	RunE: func(cmd *cobra.Command, args []string) error {
		i18n.UseI18nForCmd(language)
		if !isRoot() {
			fmt.Println(i18n.GetMsgWithMapForCmd("SudoHelper", map[string]interface{}{"cmd": "sudo npctl restore"}))
			return nil
		}
		baseDir, err := ctl_conf.LoadFromFile("/usr/local/bin/npctl", "BASE_DIR")
		if err != nil {
			return fmt.Errorf("handle load `BASE_DIR` failed, err: %v", err)
		}
		upgradeDir := path.Join(baseDir, "NebulaPanel", "tmp", "upgrade")

		tmpPath, err := loadRestorePath(upgradeDir)
		if err != nil {
			return err
		}
		if tmpPath == "no such file" {
			fmt.Println(i18n.GetMsgByKeyForCmd("RestoreNoSuchFile"))
			return nil
		}
		tmpPath = path.Join(upgradeDir, tmpPath, "original")

		fmt.Println(i18n.GetMsgWithMapForCmd("RestoreStep1", map[string]interface{}{"name": tmpPath}))
		if err := files.CopyItem(false, true, path.Join(tmpPath, "NebulaPanel-agent"), "/usr/local/bin"); err != nil {
			return err
		}
		if err := files.CopyItem(false, true, path.Join(tmpPath, "NebulaPanel-core"), "/usr/local/bin"); err != nil {
			return err
		}
		if err := files.CopyItem(true, true, path.Join(tmpPath, "lang"), "/usr/local/bin"); err != nil {
			return err
		}
		if err := files.CopyItem(false, true, path.Join(tmpPath, "GeoIP.mmdb"), path.Join(baseDir, "NebulaPanel/geo")); err != nil {
			return err
		}
		_, _ = cmdUtils.NewCommandMgr().RunWithStdout("chmod", "755", "/usr/local/bin/NebulaPanel-agent", "/usr/local/bin/NebulaPanel-core")

		fmt.Println(i18n.GetMsgByKeyForCmd("RestoreStep2"))
		if err := files.CopyItem(false, true, path.Join(tmpPath, "npctl"), "/usr/local/bin"); err != nil {
			return err
		}
		_, _ = cmdUtils.NewCommandMgr().RunWithStdout("chmod", "755", "/usr/local/bin/npctl")
		_, _ = cmdUtils.NewCommandMgr().RunWithStdout("cp", "-r", path.Join(tmpPath, "lang"), "/usr/local/bin")
		geoPath := path.Join(global.CONF.Base.InstallDir, "NebulaPanel/geo")
		_ = os.MkdirAll(geoPath, os.ModePerm)
		_, _ = cmdUtils.NewCommandMgr().RunWithStdout("cp", path.Join(tmpPath, "GeoIP.mmdb"), geoPath+"/")

		fmt.Println(i18n.GetMsgByKeyForCmd("RestoreStep3"))
		svcBasePath, _ := controller.GetServicePath("")
		svcCoreName, _ := controller.LoadServiceName("NebulaPanel-core")
		selCoreName, _ := controller.SelectInitScript("NebulaPanel-core")
		scriptCoreName, _ := controller.GetScriptName("NebulaPanel-core")
		svcAgentName, _ := controller.LoadServiceName("NebulaPanel-agent")
		selAgentName, _ := controller.SelectInitScript("NebulaPanel-agent")
		scriptAgentName, _ := controller.GetScriptName("NebulaPanel-agent")
		if err := files.CopyItem(false, true, path.Join(tmpPath, svcCoreName), svcBasePath); err != nil {
			if err := files.CopyItem(false, true, path.Join(tmpPath, selCoreName), path.Join(svcBasePath, scriptCoreName)); err != nil {
				return err
			}
		}
		if err := files.CopyItem(false, true, path.Join(tmpPath, svcAgentName), svcBasePath); err != nil {
			if err := files.CopyItem(false, true, path.Join(tmpPath, selAgentName), path.Join(svcBasePath, scriptAgentName)); err != nil {
				return err
			}
		}
		fmt.Println(i18n.GetMsgByKeyForCmd("RestoreStep4"))
		if _, err := os.Stat(path.Join(tmpPath, "db")); err == nil {
			if err := os.Chmod(path.Join(tmpPath, "db"), 0700); err != nil {
				return err
			}
			dbPath := path.Join(baseDir, "NebulaPanel")
			targetDBDir := path.Join(dbPath, "db")
			if err := os.RemoveAll(targetDBDir); err != nil {
				global.LOG.Errorf("rollback NebulaPanel db cleanup failed, err: %v", err)
			}
			if err := files.CopyItem(true, true, path.Join(tmpPath, "db"), dbPath); err != nil {
				global.LOG.Errorf("rollback NebulaPanel db failed, err: %v", err)
			}
			if err := cleanOrphanSQLiteSidecars(targetDBDir); err != nil {
				global.LOG.Errorf("rollback NebulaPanel db sidecar cleanup failed, err: %v", err)
			}
		}

		fmt.Println(i18n.GetMsgByKeyForCmd("RestoreStep5"))
		version := loadRollbackVersion(tmpPath)
		fmt.Println(i18n.GetMsgWithMapForCmd("RestoreSuccessful", map[string]interface{}{"version": version}))

		controller.RestartPanel(true, true, true)
		return nil
	},
}

func loadRestorePath(upgradeDir string) (string, error) {
	if _, err := os.Stat(upgradeDir); err != nil && os.IsNotExist(err) {
		return "no such file", nil
	}
	files, err := os.ReadDir(upgradeDir)
	if err != nil {
		return "", err
	}
	var folders []string
	for _, file := range files {
		if file.IsDir() {
			folders = append(folders, file.Name())
		}
	}
	if len(folders) == 0 {
		return "no such file", nil
	}
	sort.Slice(folders, func(i, j int) bool {
		return common.ComparePanelVersion(folders[i], folders[j])
	})
	return folders[0], nil
}

func loadRollbackVersion(upgradeDir string) string {
	info, err := ctl_conf.LoadFromFile(path.Join(upgradeDir, "npctl"), "ORIGINAL_VERSION")
	if err != nil {
		return "-"
	}
	if len(info) == 0 || info == `""` {
		return "-"
	}
	return info
}

func cleanOrphanSQLiteSidecars(dbDir string) error {
	entries, err := os.ReadDir(dbDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		name := entry.Name()
		var mainDB string
		switch {
		case strings.HasSuffix(name, ".db-wal"):
			mainDB = strings.TrimSuffix(name, "-wal")
		case strings.HasSuffix(name, ".db-shm"):
			mainDB = strings.TrimSuffix(name, "-shm")
		default:
			continue
		}

		if _, statErr := os.Stat(path.Join(dbDir, mainDB)); statErr != nil {
			if !os.IsNotExist(statErr) {
				return statErr
			}
			if removeErr := os.Remove(path.Join(dbDir, name)); removeErr != nil && !os.IsNotExist(removeErr) {
				return removeErr
			}
		}
	}

	return nil
}

