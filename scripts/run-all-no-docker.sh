#!/bin/bash
#
# ============================================================================
# 无 Docker 运行脚本 - 一键启动 clwork 本地开发环境
# ============================================================================
#
# ❗ 平台限制：本脚本仅支持 Linux！
#   macOS 用户请使用 scripts/dev-start.sh（Kuscia 通过 Docker 容器运行）。
#   原因：Kuscia 本地二进制依赖 containerd/runc/K3s 等 Linux 内核特性，
#         无法在 macOS 上运行；且脚本使用 ss 命令检测端口，macOS 没有该命令。
#
# 功能概述：
#   本脚本在本地直接启动 clwork 完整开发环境，不依赖 Docker 容器。
#   启动内容包括：
#     1. SecretFlow 本地可编辑安装（基于 conda 环境 sf310）
#     2. Kuscia Master 本地二进制（scripts/run_local_kuscia.sh）
#     3. Privahub 后端（Go 编译的 privahub 二进制）
#     4. Privahub 前端（privahub/web 本地源码 + Vite dev server）
#
# 用法：
#   bash scripts/run-all-no-docker.sh
#   bash scripts/run-all-no-docker.sh --stop
#   SUDO_PWD=your_password bash scripts/run-all-no-docker.sh
#
# 说明：
#   - 所有组件均使用 clwork 目录下的本地源码
#   - SecretFlow 使用 conda 环境 sf310 中的本地可编辑安装
#   - Kuscia 使用本地编译的 kuscia 二进制
#   - Privahub 后端使用本地 Go 编译的二进制
#   - Privahub 前端使用 privahub/web 本地源码
#
# 注意：
#   - Kuscia Master 需要监听 53 / 80 等特权端口，因此脚本内部使用 sudo
#   - 默认 sudo 密码为空，强烈建议通过 SUDO_PWD 环境变量覆盖
# ============================================================================

# Bash 严格模式
set -euo pipefail

# ------------------------------------------------------------------
# 全局路径与常量
# ------------------------------------------------------------------
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 从 .env 文件加载环境变量配置
DEV_START_ENV_FILE="${DEV_START_ENV_FILE:-$(dirname "${BASH_SOURCE[0]}")/.env}"
if [[ -f "$DEV_START_ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$DEV_START_ENV_FILE"
    set +a
fi

# 各子项目源码目录
readonly KUSCIA_DIR="$ROOT_DIR/kuscia"
readonly PRIVAHUB_DIR="$ROOT_DIR/privahub"
readonly SECRETFLOW_DIR="$ROOT_DIR/secretflow"

# LOG_DIR: 聚合日志目录；PID_DIR: 进程 ID 文件存放目录
readonly LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
readonly PID_DIR="$LOG_DIR/pids"

# KUSCIA_HOME: Kuscia 本地运行时的主目录
readonly KUSCIA_HOME="${KUSCIA_HOME:-$ROOT_DIR/.local-kuscia}"
export KUSCIA_HOME

# CONDA_ENV: SecretFlow 运行与构建使用的 conda 环境名称
CONDA_ENV="${CONDA_ENV:-sf310}"

# SUDO_PWD: 用于自动输入 sudo 密码
SUDO_PWD="${SUDO_PWD:-}"

# ------------------------------------------------------------------
# 颜色与日志
# ------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ------------------------------------------------------------------
# sudo 包装
# ------------------------------------------------------------------
run_sudo() {
    if [[ -n "${SUDO_PWD:-}" ]]; then
        echo "$SUDO_PWD" | sudo -S env PATH="$PATH" KUSCIA_HOME="$KUSCIA_HOME" "$@"
    elif sudo -n true 2>/dev/null; then
        sudo env PATH="$PATH" KUSCIA_HOME="$KUSCIA_HOME" "$@"
    else
        log_error "需要 sudo 权限但未设置 SUDO_PWD，且当前用户未配置免密 sudo"
        log_error "请设置环境变量：export SUDO_PWD=你的sudo密码"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 进程管理
# ------------------------------------------------------------------
is_process_alive() {
    local pid="$1"
    if [[ -n "$pid" ]]; then
        ps -p "$pid" >/dev/null 2>&1
    else
        return 1
    fi
}

stop_service_by_pidfile() {
    local pidfile="$1" name="$2"
    if [[ -f "$pidfile" ]]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_process_alive "$pid"; then
            log_info "停止已运行的 $name（pid $pid）..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            if is_process_alive "$pid"; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$pidfile"
    fi
}

# ------------------------------------------------------------------
# 端口检测
# ------------------------------------------------------------------
port_in_use() {
    local port="$1"
    ss -tln 2>/dev/null | grep -qE ":$port\\b"
}

wait_for_port() {
    local host="$1" port="$2" timeout_sec="${3:-60}" what="$4"
    log_info "等待 $what 就绪：$host:$port（最多 ${timeout_sec}s）..."
    local i
    for ((i = 0; i < timeout_sec; i++)); do
        if port_in_use "$port"; then
            log_info "$what 已就绪"
            return 0
        fi
        sleep 1
    done
    log_error "$what 在 $host:$port 上未就绪，请查看日志"
    return 1
}

# ------------------------------------------------------------------
# conda 环境管理
# ------------------------------------------------------------------
ensure_conda_env() {
    if [[ -n "${CONDA_PREFIX:-}" && "$(basename "$CONDA_PREFIX")" == "$CONDA_ENV" ]]; then
        return 0
    fi
    local conda_base
    conda_base="$(conda info --base 2>/dev/null)"
    if [[ -z "$conda_base" || ! -f "$conda_base/etc/profile.d/conda.sh" ]]; then
        log_error "未找到 conda，请先安装 Anaconda/Miniconda"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$conda_base/etc/profile.d/conda.sh"
    if ! conda env list | grep -qE "^$CONDA_ENV[[:space:]]"; then
        log_error "conda 环境 $CONDA_ENV 不存在，请先创建"
        exit 1
    fi
    conda activate "$CONDA_ENV"
}

# ------------------------------------------------------------------
# 依赖检查
# ------------------------------------------------------------------
check_dependencies() {
    log_step "检查系统依赖..."

    local cmd
    for cmd in node go gcc git openssl conda; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "未找到 $cmd，请先安装"
            exit 1
        fi
    done

    # Go 版本检测
    local go_version
    go_version=$(go version | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
    log_info "Go 版本：$go_version"

    # Node.js 版本检测
    local node_version
    node_version=$(node -v | sed 's/v//')
    if ! dpkg --compare-versions "$node_version" ge "18.0.0" 2>/dev/null; then
        log_warn "建议 Node.js 版本 >= 18.0.0，当前版本: $(node -v)"
    fi

    # 确保 conda 环境已激活
    ensure_conda_env
    log_info "当前 Python 环境：$CONDA_PREFIX ($(python --version))"

    if [[ -n "${SUDO_PWD:-}" ]]; then
        log_warn "当前通过 SUDO_PWD 传入 sudo 密码；请勿将密码提交到版本控制"
    fi
}

# ------------------------------------------------------------------
# 端口检查
# ------------------------------------------------------------------
check_ports() {
    log_step "检查关键端口占用情况..."
    local ports=(53 80 8080 8082 8083 8092 9001 8000)
    local occupied=()
    local port
    for port in "${ports[@]}"; do
        if port_in_use "$port"; then
            occupied+=("$port")
        fi
    done
    if (( ${#occupied[@]} > 0 )); then
        log_warn "以下端口已被占用：${occupied[*]}"
        log_warn "若启动失败，请先释放这些端口（尤其是 53 / 80 / 8083）"
    else
        log_info "关键端口空闲"
    fi
}

# ------------------------------------------------------------------
# SecretFlow 构建
# ------------------------------------------------------------------
build_secretflow() {
    log_step "安装本地 SecretFlow（$SECRETFLOW_DIR）..."
    ensure_conda_env
    cd "$SECRETFLOW_DIR"

    pip install -i https://mirrors.aliyun.com/pypi/simple/ --upgrade kuscia 2>&1 | tail -n 5
    pip install -e . 2>&1 | tail -n 10

    python - <<'PY'
from secretflow.component.core import Registry
d = Registry.get_definition_by_id('privacy/l_diversity:1.0.0')
assert d is not None, 'privacy/l_diversity:1.0.0 未注册'
print('SecretFlow 自检通过，已注册组件：privacy/l_diversity:1.0.0')
PY

    log_info "本地 SecretFlow 安装完成"
}

# ------------------------------------------------------------------
# Kuscia 构建
# ------------------------------------------------------------------
build_kuscia() {
    log_step "编译本地 Kuscia ..."
    cd "$KUSCIA_DIR"
    bash hack/build.sh -t kuscia
    log_info "Kuscia 编译完成：$KUSCIA_DIR/build/apps/kuscia/kuscia"
}

# ------------------------------------------------------------------
# Kuscia Master 启动与停止
# ------------------------------------------------------------------
start_kuscia_master() {
    log_step "启动 Kuscia Master（本地二进制模式）..."
    stop_kuscia_master

    mkdir -p "$KUSCIA_HOME"

    run_sudo DOMAIN_ID=kuscia-system bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" master \
        > "$LOG_DIR/kuscia-master.log" 2>&1 &

    sleep 2
    local kuscia_pid
    kuscia_pid="$(run_sudo cat "$KUSCIA_HOME/var/kuscia.pid" 2>/dev/null || true)"
    if [[ -n "$kuscia_pid" ]]; then
        echo "$kuscia_pid" > "$PID_DIR/kuscia-master.pid"
        log_info "Kuscia Master 已启动（pid $kuscia_pid）"
    else
        log_warn "未能从 $KUSCIA_HOME/var/kuscia.pid 读取 Kuscia PID"
    fi

    wait_for_port 127.0.0.1 8082 180 "Kuscia API HTTP"
    wait_for_port 127.0.0.1 8083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 80 180 "Kuscia Envoy 内部端口"
}

stop_kuscia_master() {
    log_info "停止 Kuscia Master ..."
    if [[ -f "$KUSCIA_HOME/var/kuscia.pid" ]]; then
        run_sudo bash "$KUSCIA_DIR/scripts/run_local_kuscia.sh" --stop || true

        local remaining
        remaining="$(pgrep -f "kuscia start -c" -u "$(id -u)" 2>/dev/null || true)"
        if [[ -n "$remaining" ]]; then
            log_warn "发现残留 Kuscia 进程，强制清理..."
            run_sudo kill -9 $remaining 2>/dev/null || true
        fi
    else
        log_info "未找到 $KUSCIA_HOME/var/kuscia.pid，跳过本地 Kuscia Master 停止"
    fi

    rm -f "$PID_DIR/kuscia-master.pid"
}

# ------------------------------------------------------------------
# Privahub 后端（Go）
# ------------------------------------------------------------------
build_privahub_backend() {
    log_step "编译 Privahub 后端（Go）..."
    cd "$PRIVAHUB_DIR"
    CGO_ENABLED=1 go build -o bin/privahub ./cmd/server
    if [[ ! -f "$PRIVAHUB_DIR/bin/privahub" ]]; then
        log_error "后端编译失败：未找到 bin/privahub"
        exit 1
    fi
    log_info "Privahub 后端编译完成"
}

start_privahub_backend() {
    log_step "启动 Privahub 后端..."
    stop_service_by_pidfile "$PID_DIR/privahub-backend.pid" "Privahub 后端"

    cd "$PRIVAHUB_DIR"

    # 非 Docker 本地模式下，config/privahub.yaml 已配置 Kuscia gRPC 端口 8083、notls
    nohup ./bin/privahub -config ./config/privahub.yaml > "$LOG_DIR/backend.log" 2>&1 &

    echo $! > "$PID_DIR/privahub-backend.pid"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
    log_info "Privahub 后端已启动"
}

# ------------------------------------------------------------------
# Privahub 前端
# ------------------------------------------------------------------
start_privahub_frontend() {
    log_step "启动 Privahub 前端..."
    stop_service_by_pidfile "$PID_DIR/privahub-frontend.pid" "Privahub 前端"

    cd "$PRIVAHUB_DIR/web"
    if [[ ! -d "node_modules" ]]; then
        log_info "首次运行，安装前端依赖..."
        corepack enable >/dev/null 2>&1 || true
        corepack pnpm install
    fi

    corepack enable >/dev/null 2>&1 || true
    nohup corepack pnpm --filter @secretpad/app dev > "$LOG_DIR/frontend.log" 2>&1 &
    echo $! > "$PID_DIR/privahub-frontend.pid"
    wait_for_port 127.0.0.1 8000 120 "前端开发服务器"
    log_info "Privahub 前端已启动"
}

# ------------------------------------------------------------------
# 服务停止与摘要
# ------------------------------------------------------------------
stop_all_services() {
    log_step "停止所有服务..."
    stop_service_by_pidfile "$PID_DIR/privahub-frontend.pid" "Privahub 前端"
    stop_service_by_pidfile "$PID_DIR/privahub-backend.pid" "Privahub 后端"
    stop_kuscia_master
    log_info "所有服务已停止"
}

print_summary() {
    local frontend_url="http://localhost:8000"
    local backend_health="http://localhost:8080/api/v1alpha1/healthz"
    local kuscia_api_http="http://localhost:8082"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  所有服务已启动（无 Docker 模式）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "🌐 前端开发服务器：${BLUE}${frontend_url}${NC}"
    echo -e "🔧 后端健康检查：${BLUE}${backend_health}${NC}"
    echo -e "⚙️  Kuscia API HTTP：${BLUE}${kuscia_api_http}${NC}"
    echo ""
    echo -e "👤 登录账号：${YELLOW}admin / 12345678${NC}"
    echo ""
    echo -e "📄 日志文件："
    echo -e "   Kuscia：$LOG_DIR/kuscia-master.log"
    echo -e "   后端：$LOG_DIR/backend.log"
    echo -e "   前端：$LOG_DIR/frontend.log"
    echo ""
    echo -e "🛑 停止服务：${YELLOW}bash scripts/run-all-no-docker.sh --stop${NC}"
    echo ""
}

# ------------------------------------------------------------------
# 主函数
# ------------------------------------------------------------------
main() {
    if [[ "${1:-}" == "--stop" ]]; then
        stop_all_services
        exit 0
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_error "本脚本 (run-all-no-docker.sh) 仅支持 Linux！"
        log_error "macOS 上 Kuscia 无法以本地二进制方式运行。"
        log_error "请使用 Docker 模式：bash scripts/dev-start.sh"
        exit 1
    fi

    check_dependencies

    mkdir -p "$LOG_DIR"
    mkdir -p "$PID_DIR"

    check_ports

    # 1. 本地 SecretFlow（conda 环境）
    build_secretflow

    # 2. 本地 Kuscia
    build_kuscia
    start_kuscia_master

    # 3. 本地 Privahub 后端（Go）
    build_privahub_backend
    start_privahub_backend

    # 4. 本地 Privahub 前端
    start_privahub_frontend

    print_summary
}

main "$@"
