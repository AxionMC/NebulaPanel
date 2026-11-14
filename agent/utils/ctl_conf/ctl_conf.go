package ctl_conf

import (
	"fmt"
	"os"
	"strings"
)

const defaultFile = "/usr/local/bin/npctl"

func Load(key string) string {
	info, err := LoadFromFile(defaultFile, key)
	if err != nil {
		panic(err)
	}
	if len(info) == 0 || info == `""` {
		panic(fmt.Sprintf("error `%s` find in %s", key, defaultFile))
	}
	return info
}

func LoadWithoutPanic(key string) string {
	info, err := LoadFromFile(defaultFile, key)
	if err != nil {
		return ""
	}
	return info
}

func LoadFromFile(filePath, key string) (string, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", err
	}
	prefix := key + "="
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimRight(line, "\r")
		if strings.HasPrefix(line, prefix) {
			return normalizeValue(strings.TrimSpace(strings.TrimPrefix(line, prefix))), nil
		}
	}
	return "", fmt.Errorf("error `%s` find in %s", key, filePath)
}

// normalizeValue 去掉值两侧成对的引号。
// 兼容 `BASE_DIR="/opt"` 与 `BASE_DIR=/opt` 两种写法，
// 避免带引号的值被当成路径后导致目录拼接错误。
func normalizeValue(v string) string {
	if len(v) >= 2 {
		first, last := v[0], v[len(v)-1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			return v[1 : len(v)-1]
		}
	}
	return v
}

func UpdateInFile(filePath, key, value string) error {
	return rewriteFile(filePath, func(line string) (string, bool) {
		if strings.HasPrefix(line, key+"=") {
			return key + "=" + value, true
		}
		return line, true
	})
}

func RemoveValueFromFile(filePath, key, value string) error {
	target := key + "=" + value
	return rewriteFile(filePath, func(line string) (string, bool) {
		return line, line != target
	})
}

func rewriteFile(filePath string, rewrite func(string) (string, bool)) error {
	info, err := os.Stat(filePath)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}
	content := rewriteLines(string(data), rewrite)
	return os.WriteFile(filePath, []byte(content), info.Mode().Perm())
}

func rewriteLines(data string, rewrite func(string) (string, bool)) string {
	hasTrailingNewline := strings.HasSuffix(data, "\n")
	lines := strings.Split(strings.TrimSuffix(data, "\n"), "\n")
	rewritten := make([]string, 0, len(lines))
	for _, line := range lines {
		newLine, keep := rewrite(line)
		if keep {
			rewritten = append(rewritten, newLine)
		}
	}
	content := strings.Join(rewritten, "\n")
	if hasTrailingNewline {
		content += "\n"
	}
	return content
}

