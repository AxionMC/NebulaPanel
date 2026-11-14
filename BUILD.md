# NebulaPanel 构建与部署指南

NebulaPanel 基于 1Panel 源码重构而成，采用 **Go (Gin) + Vue 3 + Element Plus** 技术栈。

- 版本：**V1.0.0**
- 后端：`core/`（面板核心）、`agent/`（节点代理）
- 前端：`frontend/`
- 安装脚本：`scripts/install.sh`（全程交互式 Docker 部署）
- 管理 CLI：`scripts/npctl`
- 自动构建：`.github/workflows/build.yml`

> 说明：面板内置的在线更新（升级）功能已在 V1.0.0 中移除，后期按计划评估是否重新加入。当前版本更新方式为重新拉取源码/镜像后重新安装。

## 一、前置条件

| 组件 | 版本要求 |
|------|----------|
| Go | 1.27.3+ |
| Node.js | 18+ / 20+ |
| pnpm / npm | 任意 |
| Docker | 20.10+（仅部署需要） |
| upx（可选）| 用于二进制压缩 |

## 二、获取源码

```bash
git clone https://github.com/AxionMC/NebulaPanel.git
cd NebulaPanel
```

## 三、前端构建

```bash
cd frontend
npm install   # 或 pnpm install
npm run build:pro   # 生产构建
```

构建产物直接输出到 `core/cmd/server/web`（见 `frontend/vite.config.ts` 的 `build.outDir`），随后由后端通过 `embed` 内嵌进 `NebulaPanel-core`。

## 四、后端构建（Linux）

### 方式一：一键构建脚本（推荐，自动装 Go + Node）

```bash
sudo bash scripts/build.sh
```

脚本会自动完成：识别发行版与架构 → 安装基础依赖 → 缺失时下载 Go 1.27.3 与 Node.js 20（可走国内镜像）→ 构建前端 → 编译 core 与 agent → 打包成 `build/NebulaPanel-linux-<arch>.tar.gz` 并生成 sha256。

常用参数：

| 参数 | 作用 |
|------|------|
| `--arch arm64` | 交叉编译到指定架构（默认取本机架构） |
| `--skip-frontend` | 跳过前端，复用已有 `core/cmd/server/web` |
| `--skip-deps` | 跳过系统依赖安装 |
| `--mirror cn` | 强制使用国内镜像（goproxy.cn / npmmirror） |
| `--diag` | 只打印环境和真实编译错误，不产出二进制 |

产物与日志：

```
build/NebulaPanel-core-<arch>
build/NebulaPanel-agent-<arch>
build/NebulaPanel-linux-<arch>.tar.gz
build/NebulaPanel-linux-<arch>.tar.gz.sha256
build/build.log
```

编译失败时脚本会自动打印诊断段（`go version`、`go env`、目录清单、`go build` 完整输出），把这一段贴出来即可定位问题。

### 方式二：手动编译

在仓库根目录执行：

```bash
# 构建 NebulaPanel-core（面板核心）
cd core
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' \
  -o ../build/NebulaPanel-core ./cmd/server/main.go

# 构建 NebulaPanel-agent（节点代理）
cd ../agent
go mod tidy   # lego 模块已替换为 github.com/AxionMC/lego，首次构建需校验哈希
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

ARM64 构建只需把 `GOARCH=amd64` 换成 `GOARCH=arm64`。

## 五、GitHub Actions 自动构建

仓库已内置 `.github/workflows/build.yml`，触发条件：

| 触发方式 | 说明 |
|----------|------|
| push 到 `main` | 构建前端 + 后端 amd64/arm64，产物作为 Artifact 保留 7 天 |
| push tag `v*` / `V*` | 额外构建 Docker 镜像推送 GHCR，并自动发布 GitHub Release |
| Pull Request | 仅构建校验，不发布 |
| 手动 workflow_dispatch | 可指定版本号，构建并发布镜像 |

产物命名：

- `NebulaPanel-linux-amd64.tar.gz`
- `NebulaPanel-linux-arm64.tar.gz`

每个压缩包内含 `NebulaPanel-core-<arch>` 与 `NebulaPanel-agent-<arch>`，并附带 `.sha256` 校验文件。

发布新版本只需：

```bash
git tag V1.0.0
git push origin V1.0.0
```

## 六、安装部署

### 方式一：一键安装脚本（推荐）

> **架构说明**：当前发布包仅提供 **amd64（x86_64）**。在 ARM64 机器上运行安装脚本会被明确拒绝并提示从源码编译。

在目标 Linux 服务器上以 root 运行：

```bash
git clone https://github.com/AxionMC/NebulaPanel.git
cd NebulaPanel
sudo bash scripts/install.sh
```

或从资源站直接获取：

```bash
curl -fsSL https://resource.hongkongyun.top/install.sh -o install.sh
sudo bash install.sh
```

脚本为**全程交互式**，依次询问：

1. 安装目录（默认 `/opt`）
2. 面板访问端口（默认 `9999`）
3. 安全入口路径（默认 `nebula`）
4. 管理员账号（默认 `admin`）
5. 管理员密码（默认 `admin123`）
6. 界面语言（默认 `zh`）

版本固定为 `V1.0.0`，二进制从资源站 `https://resource.hongkongyun.top` 获取：

| 文件 | 说明 |
|------|------|
| `NebulaPanel-core-amd64` | 面板核心服务 |
| `NebulaPanel-agent-amd64` | 节点代理服务 |

下载地址可用环境变量覆盖：

```bash
NP_BINARY_BASE=https://your.cdn.example.com sudo -E bash scripts/install.sh
```

资源站不可达时会回退使用本地 `build/` 下的构建产物；两者都拿不到则中止并给出明确提示。下载完成后会校验 ELF magic，防止拿到 HTML 错误页之类的假文件。

脚本其余工作：

1. 检测操作系统，架构仅允许 amd64（ARM64 直接拒绝）
2. 安装系统依赖（curl, openssl, tar 等）
3. 检测 Docker：已安装则跳过，未安装则自动安装
4. 生成 `Dockerfile.core`、`Dockerfile.agent`、`docker-compose.yml`
5. 生成 `/opt/NebulaPanel/conf/app.yaml`
6. 构建镜像并 `docker compose up -d`
7. 生成 `/usr/local/bin/npctl` 管理命令
8. 交互式询问是否替换 Docker 镜像源为 `hub.002230.xyz:44300`

安装完成后访问：`http://<服务器IP>:<端口>/<安全入口>`

### 资源站介绍页

仓库根目录的 `index.html` 是资源站的介绍页，可直接与两个二进制、`install.sh` 一起放到 Web 根目录：

```
网站根目录/
├── index.html                 # 介绍页
├── install.sh                 # 安装脚本
├── NebulaPanel-core-amd64     # 核心服务
└── NebulaPanel-agent-amd64    # 节点代理
```

介绍页中的下载链接指向 `/NebulaPanel-core-amd64` 等相对路径，与本目录结构一致，无需改动。

### 方式二：手动 Docker 部署

```bash
# 1. 创建目录
sudo mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp,docker}

# 2. 放置二进制到构建上下文
sudo cp build/NebulaPanel-core build/NebulaPanel-agent /opt/NebulaPanel/docker/
```

`/opt/NebulaPanel/docker/Dockerfile.core`：

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp}
WORKDIR /opt/NebulaPanel
COPY NebulaPanel-core /usr/local/bin/NebulaPanel-core
RUN chmod +x /usr/local/bin/NebulaPanel-core
EXPOSE 9999
ENTRYPOINT ["NebulaPanel-core", "start"]
```

`/opt/NebulaPanel/docker/Dockerfile.agent`：

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/NebulaPanel/{conf,db,secret,logs,backup,geo,tmp}
WORKDIR /opt/NebulaPanel
COPY NebulaPanel-agent /usr/local/bin/NebulaPanel-agent
RUN chmod +x /usr/local/bin/NebulaPanel-agent
ENTRYPOINT ["NebulaPanel-agent", "start"]
```

`/opt/NebulaPanel/docker/docker-compose.yml`：

```yaml
services:
  nebulapanel-core:
    build:
      context: /opt/NebulaPanel/docker
      dockerfile: /opt/NebulaPanel/docker/Dockerfile.core
    container_name: nebulapanel-core
    ports:
      - "9999:9999"
    volumes:
      - /opt/NebulaPanel/conf:/opt/NebulaPanel/conf
      - /opt/NebulaPanel/db:/opt/NebulaPanel/db
      - /opt/NebulaPanel/secret:/opt/NebulaPanel/secret
      - /opt/NebulaPanel/logs:/opt/NebulaPanel/logs
      - /opt/NebulaPanel/backup:/opt/NebulaPanel/backup
      - /opt/NebulaPanel/geo:/opt/NebulaPanel/geo
      - /opt/NebulaPanel/tmp:/opt/NebulaPanel/tmp
    restart: always
    network_mode: host

  nebulapanel-agent:
    build:
      context: /opt/NebulaPanel/docker
      dockerfile: /opt/NebulaPanel/docker/Dockerfile.agent
    container_name: nebulapanel-agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/NebulaPanel:/opt/NebulaPanel
    restart: always
    network_mode: host
```

启动：

```bash
cd /opt/NebulaPanel/docker
docker compose up -d --build
```

### 方式三：GHCR 镜像部署

```bash
docker pull ghcr.io/axionmc/nebulapanel:V1.0.0
docker run -d --name nebulapanel-core \
  --network host --restart always \
  -v /opt/NebulaPanel:/opt/NebulaPanel \
  ghcr.io/axionmc/nebulapanel:V1.0.0
```

## 七、npctl 常用命令

```bash
# 查看服务状态
npctl status

# 启动 / 停止 / 重启
npctl start
npctl stop
npctl restart

# 查看实时日志
npctl logs

# 查看访问信息（地址、账号、密码、版本）
npctl user-info

# 查看版本
npctl version
```

源码目录下的完整版 `scripts/npctl` 还支持 systemd 模式的 `update port`、`update password`、`reset entrance`、`reset mfa` 等高级操作。

## 八、目录结构说明

```
/opt/NebulaPanel/
├── conf/
│   └── app.yaml          # 生产模式配置文件
├── db/                   # SQLite 数据库（core.db, task.db, agent.db, alert.db）
├── secret/               # TLS 证书与密钥（server.crt, server.key）
├── logs/                 # 运行日志
├── backup/               # 本地备份目录
├── geo/                  # GeoIP 数据库
├── docker/               # Dockerfile 与 docker-compose.yml
├── tmp/                  # 临时目录
└── .build/               # 安装期二进制缓存
```

## 九、版本更新

内置在线更新已移除。更新方式：

```bash
cd NebulaPanel
git pull
git checkout V1.0.0        # 或目标版本 tag
sudo bash scripts/install.sh   # 重新执行安装，会复用已有配置目录
```

数据库与配置位于 `/opt/NebulaPanel`，重新安装不会清空。

## 十、卸载

```bash
cd /opt/NebulaPanel/docker
docker compose down
docker rmi nebulapanel-core nebulapanel-agent 2>/dev/null || true
sudo rm -rf /opt/NebulaPanel /usr/local/bin/npctl
```

## 十一、License

Apache License 2.0
