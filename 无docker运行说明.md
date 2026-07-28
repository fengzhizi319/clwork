# 无 Docker 运行说明

本文档说明如何在不使用 Docker 的前提下，直接基于 `sfwork` 目录下的本地源码运行 Privahub 前端、Privahub 后端、Kuscia 以及 SecretFlow。该方式适用于本地二次开发和源码调试。

> **注意**：
> - 本方案不使用任何 Docker 镜像来运行 Kuscia / Privahub / SecretFlow。
> - SecretFlow 通过 conda 环境 `sf310` 以可编辑模式（`pip install -e .`）安装本地源码。
> - Kuscia 使用本地编译的 `kuscia` 二进制（`kuscia/scripts/run_local_kuscia.sh`）启动。
> - Privahub 后端使用 Go 源码本地编译启动（需要 CGO 支持 SQLite）。
> - Privahub 前端源码位于 `privahub/web/`，使用 pnpm workspace + Vite。
> - 实际执行隐私计算任务时，Kuscia 仍需要 AppImage 与容器运行时（containerd/runc/runp）；如需完全无容器运行任务，请参考 Kuscia `runp` 运行时文档额外配置。

## 目录

- [1. 环境准备](#1-环境准备)
- [2. 一键脚本](#2-一键脚本)
- [3. 手动启动步骤](#3-手动启动步骤)
- [4. 停止服务](#4-停止服务)
- [5. 常见问题排查](#5-常见问题排查)
- [6. 访问服务](#6-访问服务)

## 1. 环境准备

### 1.1 系统要求

| 组件 | 版本要求 | 说明 |
|------|---------|------|
| Go | 1.25+ | Privahub 后端编译与运行 |
| Node.js | >= 18（推荐 v22+） | Privahub 前端运行 |
| pnpm | 11.7.0 | 由 `privahub/web/package.json` 的 `packageManager` 管理 |
| gcc / g++ | 任意 | Kuscia / Privahub SQLite 驱动编译依赖 |
| git | 任意 | 版本管理 |
| openssl | 任意 | 证书生成（可选，开发模式 notls 不强制） |
| conda（Miniconda/Anaconda） | 任意 | 管理 SecretFlow Python 环境 `sf310` |
| sudo | 可用 | Kuscia Master 需要监听 53 / 80 等特权端口 |

**不需要 JDK、Maven 或 Docker。**

验证命令：

```bash
go version                    # go1.25+
node -v                       # v22+ 或 v18+
corepack pnpm -v              # 需先 corepack enable，版本应 >= 11.7.0
gcc --version
openssl version
conda info --base
conda env list | grep sf310   # 确认 sf310 环境存在
```

### 1.2 工作目录结构

确保你的工作目录结构如下：

```
/home/charles/code/sfwork/
├── kuscia/                         # Kuscia Go 源码
│   ├── scripts/run_local_kuscia.sh # 本地无 Docker 启动脚本
│   └── hack/build.sh               # Kuscia 编译脚本
├── secretflow/                     # SecretFlow Python 源码
│   └── pyproject.toml
├── privahub/                       # Privahub Go 后端 + React/Vite 前端
│   ├── cmd/server/                 # 主服务入口
│   ├── config/privahub.yaml       # 非 Docker 模式配置
│   ├── web/                        # 前端源码（pnpm workspace）
│   └── bin/privahub                # Go 构建产物
├── .local-kuscia/                  # Kuscia 本地运行时数据（自动创建）
├── logs/                           # 聚合日志目录
└── scripts/run-all-no-docker.sh    # 一键启动脚本
```

### 1.3 SecretFlow conda 环境

如果 `sf310` 环境不存在，可创建并安装基础依赖：

```bash
conda create -n sf310 python=3.10 -y
conda activate sf310
```

## 2. 一键脚本

项目提供了自动化脚本 `scripts/run-all-no-docker.sh`，启动顺序如下：

1. 检查系统依赖与 conda 环境
2. 在 `sf310` 环境中可编辑安装本地 SecretFlow
3. 编译本地 Kuscia 二进制
4. 启动本地 Kuscia Master（无 Docker）
5. 编译本地 Privahub 后端（Go，需要 CGO）
6. 启动 Privahub 后端
7. 启动 Privahub 前端

### 2.1 赋予脚本执行权限

```bash
chmod +x /home/charles/code/sfwork/scripts/run-all-no-docker.sh
```

### 2.2 启动所有服务

如果你的 sudo 密码不是默认的 `111111`，请通过环境变量传入：

```bash
# 默认 sudo 密码为 111111；建议自定义
export SUDO_PWD="111111"
export CONDA_ENV="sf310"

bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh
```

或合并为一行：

```bash
SUDO_PWD="111111" CONDA_ENV="sf310" bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh
```

### 2.3 停止所有服务

```bash
SUDO_PWD="111111" bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop
```

## 3. 手动启动步骤

如果你希望手动控制每个步骤，可按以下顺序执行。

### 3.1 安装本地 SecretFlow

```bash
cd /home/charles/code/sfwork/secretflow

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate sf310

# 安装 kuscia Python 包（SecretFlow Kuscia 入口需要）
pip install -i https://mirrors.aliyun.com/pypi/simple/ kuscia

# 可编辑安装本地 SecretFlow
pip install -e .

# 自检（以隐私计算组件 l_diversity 为例）
python - <<'PY'
from secretflow.component.core import Registry
d = Registry.get_definition_by_id('privacy/l_diversity:1.0.0')
assert d is not None, 'privacy/l_diversity:1.0.0 未注册'
print('SecretFlow 自检通过')
PY
```

### 3.2 编译 Kuscia

```bash
cd /home/charles/code/sfwork/kuscia
bash hack/build.sh -t kuscia

# 验证编译结果
ls -lh build/apps/kuscia/kuscia
./build/apps/kuscia/kuscia version
```

### 3.3 启动 Kuscia Master（本地二进制模式）

```bash
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
mkdir -p "$KUSCIA_HOME"

# 使用 sudo 启动，因为需要监听 53 / 80 端口
sudo bash /home/charles/code/sfwork/kuscia/scripts/run_local_kuscia.sh master
```

或使用脚本内部的 sudo 自动输入（已知密码时）：

```bash
echo "111111" | sudo -S bash /home/charles/code/sfwork/kuscia/scripts/run_local_kuscia.sh master
```

启动后会占用以下默认端口：

| 服务 | 端口 | 说明 |
|------|------|------|
| Kuscia API HTTP | 8082 | 外部 HTTP API |
| Kuscia API gRPC | 8083 | Privahub 后端连接端口 |
| Kuscia API HTTP Internal | 8092 | 内部 HTTP API |
| Envoy 内部端口 | 80 | 节点间通信 / Gateway |
| CoreDNS | 53 | 需要 root 权限 |

### 3.4 编译 Privahub 后端

```bash
cd /home/charles/code/sfwork/privahub

# 编译（CGO 必须启用，因为默认 SQLite 驱动为 mattn/go-sqlite3）
CGO_ENABLED=1 go build -o bin/privahub ./cmd/server

# 验证编译结果
ls -lh bin/privahub
./bin/privahub -version
```

构建成功后会在 `bin/` 目录下生成 `privahub` 可执行文件。

### 3.5 启动 Privahub 后端

非 Docker 本地模式下，`privahub/config/privahub.yaml` 已配置 Kuscia gRPC 端口为 `8083`、协议为 `notls`，直接启动即可：

```bash
cd /home/charles/code/sfwork/privahub

# 使用默认基础配置（非 Docker 模式）
./bin/privahub -config ./config/privahub.yaml
```

启动后占用端口：

| 服务 | 端口 | 说明 |
|------|------|------|
| Privahub 后端 HTTP | 8080 | 前端与外部 API |
| Privahub 内部 API | 9001 | 集群内部无认证接口 |
| gRPC（当前预留） | 9090 | 暂未连接外部服务 |

> 注意：`config/secretpad*.yaml` 文件名沿用历史 `secretpad` 命名，实际为 Privahub 后端配置。

### 3.6 启动 Privahub 前端

```bash
cd /home/charles/code/sfwork/privahub/web

# 启用 corepack 以使用项目指定的 pnpm 11.7.0
corepack enable

# 首次运行安装依赖
corepack pnpm install

# 启动开发服务器（Vite 默认监听 8000，代理 /api 到后端 8080）
corepack pnpm --filter @secretpad/app dev
```

## 4. 停止服务

### 4.1 使用一键脚本停止

```bash
SUDO_PWD="111111" bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop
```

### 4.2 手动停止服务

```bash
# 停止前端
kill $(lsof -t -i:8000) 2>/dev/null || true

# 停止后端
kill $(lsof -t -i:8080) 2>/dev/null || true
kill $(lsof -t -i:9001) 2>/dev/null || true

# 停止 Kuscia Master（通过自带脚本）
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
sudo bash /home/charles/code/sfwork/kuscia/scripts/run_local_kuscia.sh --stop

# 如仍有残留进程
sudo pkill -f "kuscia start -c"
```

### 4.3 清理数据（谨慎操作）

```bash
# 删除 Kuscia 本地运行时数据
rm -rf /home/charles/code/sfwork/.local-kuscia

# 删除日志与 PID
rm -rf /home/charles/code/sfwork/logs
```

## 5. 常见问题排查

### 5.1 conda 环境未找到

```bash
# 确认 conda 已初始化
conda info --base

# 激活环境
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate sf310

# 如环境不存在则创建
conda create -n sf310 python=3.10 -y
```

### 5.2 端口被占用

```bash
# 检查关键端口
for p in 53 80 8080 8082 8083 8092 9001 8000; do
  echo "Port $p:"
  sudo ss -tlnp | grep ":$p\b" || echo "  空闲"
done

# 释放被占用的端口（将 <port> 替换为实际端口）
sudo kill -9 $(lsof -t -i:<port>) 2>/dev/null || true
```

### 5.3 53 端口被 systemd-resolved 占用

```bash
# 检查
sudo ss -tlnp | grep ':53'

# 临时停止
sudo systemctl stop systemd-resolved

# 或修改 /etc/systemd/resolved.conf，注释掉 DNSStubListener=yes 后重启
sudo systemctl restart systemd-resolved
```

### 5.4 sudo 权限问题

```bash
# 测试 sudo 是否可用
sudo whoami

# 如不希望交互，可通过环境变量传入密码（已知密码时）
export SUDO_PWD="111111"
echo "$SUDO_PWD" | sudo -S whoami
```

### 5.5 Kuscia 启动失败

查看日志：

```bash
cat /home/charles/code/sfwork/.local-kuscia/var/logs/kuscia.log
cat /home/charles/code/sfwork/.local-kuscia/var/logs/kuscia_stdout.log
cat /home/charles/code/sfwork/logs/kuscia-master.log
```

常见原因：

- 端口冲突：53 / 80 / 8083 被占用
- 权限不足：未使用 sudo 或 sudo 密码错误
- K3s 初始化失败：检查 `.local-kuscia/var/logs/kuscia.log` 中的 k3s 相关错误

### 5.6 Privahub 后端连接 Kuscia 失败

确认配置文件：

```bash
cat /home/charles/code/sfwork/privahub/config/privahub.yaml
```

非 Docker 本地模式下关键字段应为：

```yaml
kuscia:
  api_address: "127.0.0.1"
  api_port: 8083
  protocol: "notls"
```

或使用环境变量覆盖（Viper 自动读取 `PRIVAHUB_*`）：

```bash
export PRIVAHUB_KUSCIA_API_ADDRESS=127.0.0.1
export PRIVAHUB_KUSCIA_API_PORT=8083
export PRIVAHUB_KUSCIA_PROTOCOL=notls
```

测试 Kuscia API：

```bash
# HTTP API 健康检查（未启用 TLS 时）
curl -v http://127.0.0.1:8082/healthz

# gRPC 端口监听
ss -tlnp | grep ':8083'
```

### 5.7 SecretFlow 组件未注册

如果后端提示找不到 `privacy/l_diversity` 等组件，请确认本地 SecretFlow 已正确安装：

```bash
conda activate sf310
python -c "from secretflow.component.core import Registry; \
           print(Registry.get_definition_by_id('privacy/l_diversity:1.0.0'))"
```

如未注册，重新执行：

```bash
cd /home/charles/code/sfwork/secretflow
pip install -e .
```

### 5.8 前端代理不到后端

前端 Vite 配置通过环境变量 `API_PROXY_URL` 指定后端地址，默认已经是 `http://127.0.0.1:8080`。

如需显式覆盖，启动前端时传入：

```bash
cd /home/charles/code/sfwork/privahub/web
API_PROXY_URL=http://127.0.0.1:8080 corepack pnpm --filter @secretpad/app dev
```

或在 `privahub/web/apps/secretpad/.env.local` 中写入：

```text
API_PROXY_URL=http://127.0.0.1:8080
```

## 6. 访问服务

服务启动成功后，可通过以下地址访问：

| 服务 | 地址 |
|------|------|
| Privahub 前端 | http://localhost:8000 |
| 后端健康检查 | http://localhost:8080/api/v1alpha1/healthz |
| 后端内部 API | http://localhost:9001 |
| Kuscia API HTTP | http://localhost:8082 |

登录账号：`admin` / `12345678`

---

**祝你开发愉快！** 🎉
