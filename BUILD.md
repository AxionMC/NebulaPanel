# NebulaPanel 构建与部署指南

NebulaPanel 基于 1Panel 源码重构而成，采用 **Go (Gin) + Vue 3 + Element Plus** 技术栈。

- 后端：`core/`（面板核心）、`agent/`（节点代理）
- 前端：`frontend/`
- 安装脚本：`scripts/install.sh`
- 管理 CLI：`scripts/npctl`

## 一、前置条件

| 组件 | 版本要求 |
|------|----------|
| Go | 1.27.3+ |
| Node.js | 18+ / 20+ |
| pnpm / npm | 任意 |
| upx（可选）| 用于二进制压缩 |

## 二、获取源码

```bash
git clone https://github.com/NebulaPanel/nebulapanel.git
cd nebulapanel
```

## 三、前端构建

```bash
cd frontend
npm install   # 或 pnpm install
npm run build:pro   # 生产构建
```

构建产物会输出到 `frontend/dist`，并在打包后由后端通过 `embed` 内嵌进 `core/cmd/server/web/assets`。

## 四、后端构建（Linux）

在仓库根目录执行：

```bash
# 构建 NebulaPanel-core（面板核心）
cd core
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' \
  -o ../build/NebulaPanel-core ./cmd/server/main.go

# 构建 NebulaPanel-agent（节点代理）
cd ../agent
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' \
  -o ../build/NebulaPanel-agent ./cmd/server/main.go
```

或者直接使用 Makefile：

```bash
make build_all
```

构建产物位于 `build/` 目录：
- `build/NebulaPanel-core`
- `build/NebulaPanel-agent`

## 五、安装部署

### 方式一：一键安装脚本（推荐）

在目标 Linux 服务器上以 root 运行：

```bash
curl -fsSL https://resource.nebulapanel.pro/v2/quick_start.sh | bash
```

或本地运行：

```bash
sudo bash scripts/install.sh
```

安装脚本会完成以下工作：
1. 检测操作系统与架构（amd64 / arm64）
2. 安装系统依赖（curl, openssl, tar 等）
3. 下载 NebulaPanel-core / NebulaPanel-agent / npctl 二进制
4. 生成 `/usr/local/bin/npctl` 配置文件
5. 生成 `/opt/NebulaPanel/conf/app.yaml`
6. 创建 systemd 服务单元 `nebulapanel-core.service`、`nebulapanel-agent.service`
7. 启动服务并设置开机自启

安装完成后访问：`http://<服务器IP>:9999/nebula`

### 方式二：手动部署

```bash
# 1. 创建目录
sudo mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp}
sudo mkdir -p /usr/local/bin

# 2. 拷贝二进制
sudo cp build/NebulaPanel-core /usr/local/bin/
sudo cp build/NebulaPanel-agent /usr/local/bin/
sudo cp scripts/npctl /usr/local/bin/npctl
sudo chmod 755 /usr/local/bin/NebulaPanel-core /usr/local/bin/NebulaPanel-agent /usr/local/bin/npctl

# 3. 生成 npctl 配置（以端口 9999 为例）
cat > /usr/local/bin/npctl <<'EOF'
BASE_DIR="/opt"
ORIGINAL_PORT="9999"
ORIGINAL_VERSION="v2.0.0"
ORIGINAL_USERNAME="admin"
ORIGINAL_PASSWORD="admin123"
ORIGINAL_ENTRANCE="nebula"
LANGUAGE="zh"
CHANGE_USER_INFO=""
PANEL_EDITION="cn"
EOF

# 4. 生成 conf/app.yaml
cat > /opt/NebulaPanel/conf/app.yaml <<'EOF'
base:
  install_dir: /opt
  mode: stable
  is_demo: false
  is_offline: false
  is_enterprise: false
  port: 9999
  username: admin
  password: admin123
  version: v2.0.0

log:
  level: info
  time_zone: Asia/Shanghai
  log_name: NebulaPanel-Core
  log_suffix: .log
  max_backup: 10
EOF

# 5. 生成 systemd 单元并启动
sudo tee /etc/systemd/system/nebulapanel-core.service >/dev/null <<EOF
[Unit]
Description=NebulaPanel Core Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/NebulaPanel-core start
Restart=always
RestartSec=5
WorkingDirectory=/opt/NebulaPanel
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/nebulapanel-agent.service >/dev/null <<EOF
[Unit]
Description=NebulaPanel Agent Service
After=network.target nebulapanel-core.service

[Service]
Type=simple
ExecStart=/usr/local/bin/NebulaPanel-agent start
Restart=always
RestartSec=5
WorkingDirectory=/opt/NebulaPanel
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nebulapanel-core.service nebulapanel-agent.service
```

## 六、npctl 常用命令

```bash
# 查看服务状态
npctl status all

# 重启核心服务
npctl restart core

# 重启代理服务
npctl restart agent

# 修改面板端口
npctl update port 8080

# 修改管理员密码
npctl update password

# 修改管理员账号
npctl update username

# 查看访问信息（地址、账号、密码）
npctl user-info

# 重置安全入口
npctl reset entrance

# 查看版本
npctl version

# 查看帮助
npctl help
```

## 七、目录结构说明

```
/opt/NebulaPanel/
├── conf/
│   └── app.yaml          # 生产模式配置文件
├── db/                   # SQLite 数据库（core.db, task.db, agent.db, alert.db）
├── secret/               # TLS 证书与密钥（server.crt, server.key）
├── logs/                 # 运行日志
├── backup/               # 本地备份目录
├── geo/                  # GeoIP 数据库
└── tmp/                  # 升级/回滚临时目录
```

## 八、升级

```bash
npctl update version v2.x.x   # 升级到指定版本
```

升级过程会自动备份数据库，并在失败时支持 `npctl restore` 回滚。

## 九、卸载

```bash
sudo systemctl stop nebulapanel-core.service nebulapanel-agent.service
sudo systemctl disable nebulapanel-core.service nebulapanel-agent.service
sudo rm -rf /etc/systemd/system/nebulapanel-*.service
sudo rm -rf /usr/local/bin/NebulaPanel-core /usr/local/bin/NebulaPanel-agent /usr/local/bin/npctl
sudo rm -rf /opt/NebulaPanel
sudo systemctl daemon-reload
```

## 十、License

GNU General Public License v3.0
