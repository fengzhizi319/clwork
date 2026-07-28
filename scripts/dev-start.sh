#!/bin/bash
#
# ============================================================================
# clwork 二次开发环境一键启动脚本（使用 Docker Kuscia + 自定义 SecretFlow 镜像）
# ============================================================================
#
# 支持平台:
#   - macOS ARM64 (Apple Silicon) — Kuscia 通过 Docker (colima) 运行
#   - Linux x86_64 / ARM64 — Kuscia 通过 Docker 运行
#
# 功能概述:
#   本脚本用于一键拉起完整的 clwork 二次开发环境,核心特点:
#   1. 检测 Go / Node.js / pnpm / Docker / conda 等运行时依赖
#   2. 基于 clwork/secretflow 本地源码构建自定义 SecretFlow 镜像
#   3. 部署 Kuscia Docker 环境(Master + alice + bob 三节点)
#   4. 将上述自定义镜像注册为 Kuscia AppImage,供任务调度使用
#   5. 编译并启动 privahub 后端服务(Go 二进制)
#   6. 启动 privahub 前端开发服务器(Vite dev server, privahub/web)
#
# 前置条件:
#   - clwork 已克隆到任意目录(脚本会自动推导根目录)
#   - 已创建 conda 环境 sf310(仅在构建 SecretFlow 镜像时需要)
#   - Docker 可用且当前用户有权限执行 docker 命令
#
# 用法:
#   bash scripts/dev-start.sh          # 完整启动
#   bash scripts/dev-start.sh --check  # 仅检查环境
#   bash scripts/dev-start.sh --help   # 显示帮助
#
# 停止服务:
#   bash scripts/dev-stop.sh
#   bash scripts/dev-stop.sh --kuscia  # 同时停止 Kuscia 容器
# ============================================================================

set -euo pipefail

# ------------------------------------------------------------------
# 全局路径与变量
# ------------------------------------------------------------------
SFWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 从 .env 文件加载环境变量配置
DEV_START_ENV_FILE="${DEV_START_ENV_FILE:-$(dirname "${BASH_SOURCE[0]}")/.env}"
if [[ -f "$DEV_START_ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$DEV_START_ENV_FILE"
    set +a
    echo "[INFO] 已加载环境变量配置:$DEV_START_ENV_FILE"
fi

# 各子项目路径
readonly PRIVAHUB_DIR="$SFWORK_ROOT/privahub"       # Privahub 前后端源码
readonly SECRETFLOW_DIR="$SFWORK_ROOT/secretflow"   # SecretFlow 源码
readonly KUSCIA_DIR="$SFWORK_ROOT/kuscia"           # Kuscia 源码

# 节点名称
export ALICE_NAME="${ALICE_NAME:-alice}"
export BOB_NAME="${BOB_NAME:-bob}"

# INSTALL_DIR: Kuscia 安装目录
if [[ -n "${INSTALL_DIR:-}" ]]; then
    export INSTALL_DIR
fi

# LOG_DIR: 聚合日志目录
LOG_DIR="${LOG_DIR:-$SFWORK_ROOT/logs}"

# PRIVACY_IMAGE: 自定义 SecretFlow 镜像 tag
PRIVACY_IMAGE="${PRIVACY_IMAGE:-secretflow/sf-privacy-dev:1.15.0.dev-privacy}"

# PRIVACY_DOCKERFILE: 自定义 SecretFlow 镜像 Dockerfile
PRIVACY_DOCKERFILE="${PRIVACY_DOCKERFILE:-Dockerfile}"

# KUSCIA_IMAGE: 自定义 Kuscia 镜像 tag(可选)
KUSCIA_IMAGE="${KUSCIA_IMAGE:-}"

# RESET_KUSCIA: 是否在启动前重置 Kuscia 容器
RESET_KUSCIA="${RESET_KUSCIA:-false}"

# CONDA_ENV: 构建 SecretFlow wheel 时使用的 conda 环境名称
CONDA_ENV="${CONDA_ENV:-sf310}"

# ------------------------------------------------------------------
# 颜色与日志系统
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
# 检查子项目是否已克隆
# ------------------------------------------------------------------
check_cloned_repositories() {
    local missing_dirs=()
    local dir
    for dir in "$PRIVAHUB_DIR" "$SECRETFLOW_DIR" "$KUSCIA_DIR"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    if [[ ! -d "$PRIVAHUB_DIR/web" ]]; then
        missing_dirs+=("$PRIVAHUB_DIR/web")
    fi
    if (( ${#missing_dirs[@]} > 0 )); then
        log_error "以下子项目目录不存在:"
        for dir in "${missing_dirs[@]}"; do
            log_error "  - $dir"
        done
        log_error "请先执行子项目克隆脚本:bash scripts/clone-repos.sh"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 工具函数库
# ------------------------------------------------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
    local os
    os="$(uname -s 2>/dev/null || echo unknown)"
    case "$os" in
        Linux*)     echo linux ;;
        Darwin*)    echo darwin ;;
        MINGW*|MSYS*|CYGWIN*) echo windows ;;
        *)          echo unknown ;;
    esac
}

is_linux() { [[ "$(detect_os)" == "linux" ]]; }
is_macos() { [[ "$(detect_os)" == "darwin" ]]; }
is_windows() { [[ "$(detect_os)" == "windows" ]]; }

version_ge() {
    local v1="$1" v2="$2"
    if command_exists sort && printf '%s\n%s\n' "$v2" "$v1" | sort -V -C 2>/dev/null; then
        return 0
    fi
    awk -v v1="$v1" -v v2="$v2" 'BEGIN {
        split(v1, a, "."); split(v2, b, ".");
        for (i = 1; i <= 4; i++) {
            if ((a[i] "" == "") && (b[i] "" == "")) exit 0;
            av = (a[i] "" == "") ? 0 : a[i] + 0;
            bv = (b[i] "" == "") ? 0 : b[i] + 0;
            if (av > bv) exit 0;
            if (av < bv) exit 1;
        }
        exit 0;
    }'
}

to_docker_path() {
    local path="$1"
    printf '%s' "$path" | tr '\\' '/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

to_posix_path() {
    local path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path" 2>/dev/null || to_docker_path "$path"
    elif command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$path" 2>/dev/null || to_docker_path "$path"
    else
        to_docker_path "$path"
    fi
}

get_node_version() { node -v 2>/dev/null | sed 's/^v//'; }
get_pnpm_version() { corepack pnpm -v 2>/dev/null || true; }
get_docker_version() { docker --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }
get_go_version() { go version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1; }

get_web_package_manager_pnpm_version() {
    local pkg_json="$PRIVAHUB_DIR/web/package.json"
    if [[ -f "$pkg_json" ]]; then
        grep -oE '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@[^"]+"' "$pkg_json" 2>/dev/null \
            | grep -oE 'pnpm@[0-9]+(\.[0-9]+)*' | head -1 | sed 's/pnpm@//'
    fi
}

# ------------------------------------------------------------------
# 环境检测
# ------------------------------------------------------------------
check_environment() {
    log_step "检查本地开发环境 ..."

    # Go 检测: Privahub 后端需要 Go 1.21+
    if command_exists go; then
        local go_ver
        go_ver="$(get_go_version)"
        if version_ge "$go_ver" "1.21"; then
            log_info "Go $go_ver 已满足要求"
        else
            log_error "当前 Go 版本为 $go_ver, Privahub 后端需要 Go >= 1.21"
            exit 1
        fi
    else
        log_error "需要 Go 1.21+, 请安装后重试"
        exit 1
    fi

    # Node.js 检测
    local node_ver
    node_ver="$(get_node_version)"
    local pkg_pnpm_ver
    pkg_pnpm_ver="$(get_web_package_manager_pnpm_version)"

    if ! command_exists node; then
        log_error "需要 Node.js,请安装后重试"
        exit 1
    fi

    if ! version_ge "$node_ver" "18"; then
        log_error "当前 Node.js 版本为 $node_ver, 前端需要 Node.js >= 18"
        exit 1
    fi

    # pnpm 11+ 需要 Node.js >= 22.13
    local pnpm_major
    pnpm_major="$(echo "$pkg_pnpm_ver" | cut -d. -f1)"
    if [[ -n "$pnpm_major" && "$pnpm_major" -ge 11 ]] && ! version_ge "$node_ver" "22.13.0"; then
        log_error "packageManager 指定 pnpm $pkg_pnpm_ver, 需要 Node.js >= 22.13"
        log_error "当前 Node.js 为 $node_ver, 请升级"
        exit 1
    fi
    log_info "Node.js $node_ver 已满足要求 (packageManager=pnpm@$pkg_pnpm_ver)"

    # pnpm/corepack 检测
    if command_exists corepack; then
        corepack enable >/dev/null 2>&1 || true
        local pnpm_ver
        pnpm_ver="$(get_pnpm_version)"
        log_info "pnpm $pnpm_ver (通过 corepack) 已就绪"
    else
        log_error "未找到 corepack,请升级 Node.js 到 16.10+ 或手动安装 pnpm"
        exit 1
    fi

    # Docker 检测
    if command_exists docker; then
        local docker_ver
        docker_ver="$(get_docker_version)"
        if version_ge "$docker_ver" "20.10.0"; then
            log_info "Docker $docker_ver 已满足要求"
        else
            log_error "需要 Docker 20.10+,当前版本 $docker_ver"
            exit 1
        fi
    else
        log_error "未找到 Docker,请手动安装 Docker >= 20.10"
        exit 1
    fi

    # macOS Docker 守护进程检测
    if is_macos; then
        if ! docker info >/dev/null 2>&1; then
            log_warn "Docker 守护进程未运行,尝试自动启动 colima ..."
            if command_exists colima; then
                colima start
                local wait_i
                for ((wait_i = 0; wait_i < 60; wait_i++)); do
                    if docker info >/dev/null 2>&1; then break; fi
                    sleep 1
                done
                if ! docker info >/dev/null 2>&1; then
                    log_error "colima 启动后 Docker 仍不可用"
                    exit 1
                fi
            else
                log_error "Docker 守护进程未运行,且未找到 colima"
                exit 1
            fi
        fi
    fi

    # conda 检测
    if command_exists conda; then
        if conda env list | grep -qE "^$CONDA_ENV[[:space:]]"; then
            log_info "Conda 环境 $CONDA_ENV 已存在"
        else
            log_error "Conda 环境 $CONDA_ENV 不存在,请先创建:conda create -n $CONDA_ENV python=3.10 -y"
            exit 1
        fi
    else
        log_error "未找到 conda,请先安装 Miniconda/Anaconda"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 端口检测
# ------------------------------------------------------------------
port_in_use() {
    local port="$1"
    if is_macos; then
        command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    elif is_windows; then
        if command -v lsof >/dev/null 2>&1; then
            lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
        elif command -v netstat >/dev/null 2>&1; then
            netstat -an 2>/dev/null | grep -qE "TCP[[:space:]]+[0-9.]+:${port}[[:space:]]+.*LISTENING"
        else
            return 1
        fi
    else
        if command -v ss >/dev/null 2>&1; then
            ss -tln 2>/dev/null | grep -qE ":$port($|[[:space:]])"
        else
            return 1
        fi
    fi
}

port_pid() {
    local port="$1"
    if is_macos; then
        command -v lsof >/dev/null 2>&1 && lsof -tiTCP:"$port" -sTCP:LISTEN | head -1
    else
        if command -v ss >/dev/null 2>&1; then
            ss -tlnp 2>/dev/null | grep -E ":$port($|[[:space:]])" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
        fi
    fi
}

read_pidfile() {
    local f="$1"
    if [[ -f "$f" ]]; then cat "$f"; fi
}

wait_for_port() {
    local host="$1" port="$2" timeout_sec="${3:-60}" what="$4"
    log_info "等待 $what 就绪:$host:$port(最多 ${timeout_sec}s)..."
    local i
    for ((i = 0; i < timeout_sec; i++)); do
        if port_in_use "$port"; then
            log_info "$what 已就绪"
            return 0
        fi
        sleep 1
    done
    log_error "$what 在 $host:$port 上未就绪,请查看日志"
    return 1
}

check_required_ports() {
    log_step "检查关键端口占用情况 ..."
    local backend_pid frontend_pid
    backend_pid="$(read_pidfile "$LOG_DIR/backend.pid")"
    frontend_pid="$(read_pidfile "$LOG_DIR/frontend.pid")"

    local kuscia_running=false
    if docker ps --filter "name=${USER}-kuscia-master" --format '{{.Names}}' | grep -q .; then
        kuscia_running=true
    fi

    local abort=false

    for p in 8080; do
        if port_in_use "$p"; then
            local pid
            pid="$(port_pid "$p")"
            if [ -n "$backend_pid" ] && [ "$pid" = "$backend_pid" ]; then
                log_info "端口 $p 已由当前后端进程占用"
            else
                log_error "端口 $p 被其他进程(pid ${pid:-unknown})占用"
                abort=true
            fi
        fi
    done

    if port_in_use 8000; then
        local pid
        pid="$(port_pid 8000)"
        if [ -n "$frontend_pid" ] && [ "$pid" = "$frontend_pid" ]; then
            log_info "端口 8000 已由当前前端进程占用"
        else
            log_error "端口 8000 被其他进程(pid ${pid:-unknown})占用"
            abort=true
        fi
    fi

    if [ "$kuscia_running" = false ]; then
        # center 模式端口: master(18080/18082/18083) + alice lite(28080~28083) + bob lite(38080~38083)
        for p in 18080 18082 18083 28080 28081 28082 28083 38080 38081 38082 38083; do
            if port_in_use "$p"; then
                log_error "端口 $p 已被占用,无法部署 Kuscia"
                abort=true
            fi
        done
    else
        log_info "Kuscia 已在运行,其端口占用符合预期"
    fi

    if [ "$abort" = true ]; then
        log_error "请先释放占用端口,或执行 bash scripts/dev-stop.sh 清理残留进程"
        exit 1
    fi
}

# ------------------------------------------------------------------
# 进程管理
# ------------------------------------------------------------------
is_process_alive() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    ps -p "$pid" >/dev/null 2>&1
}

stop_service_by_pidfile() {
    local pidfile="$1" name="$2"
    if [ -f "$pidfile" ]; then
        local pid
        pid="$(cat "$pidfile")"
        if is_process_alive "$pid"; then
            log_info "停止已运行的 $name(pid $pid)..."
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
# 自定义 SecretFlow 镜像构建
# ------------------------------------------------------------------
build_secretflow_image() {
    log_step "构建二次开发 SecretFlow 镜像:$PRIVACY_IMAGE ..."

    if docker image inspect "$PRIVACY_IMAGE" >/dev/null 2>&1; then
        log_info "镜像 $PRIVACY_IMAGE 已存在,跳过构建"
        return 0
    fi

    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        deactivate 2>/dev/null || true
        unset VIRTUAL_ENV
        PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '\.venv' | tr '\n' ':' | sed 's/:$//')"
        export PATH
    fi

    local conda_base
    conda_base="$(conda info --base)"
    # shellcheck source=/dev/null
    source "$conda_base/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"

    cd "$SECRETFLOW_DIR"
    rm -rf dist build

    log_info "构建 SecretFlow wheel ..."
    if ! python -c "import build" >/dev/null 2>&1; then
        log_error "当前 conda 环境缺少 python build 模块"
        log_error "请执行:pip install --upgrade build setuptools wheel"
        exit 1
    fi
    python -m build --wheel

    local wheels=("$SECRETFLOW_DIR"/dist/secretflow-*.whl)
    if [[ ! -f "${wheels[0]}" ]]; then
        log_error "未找到构建出的 wheel 文件"
        exit 1
    fi

    mkdir -p "$SECRETFLOW_DIR/docker/privacy-dev"
    rm -f "$SECRETFLOW_DIR/docker/privacy-dev"/secretflow-*.whl
    cp "${wheels[0]}" "$SECRETFLOW_DIR/docker/privacy-dev/"

    cd "$SECRETFLOW_DIR/docker/privacy-dev"
    log_info "构建 Docker 镜像(Dockerfile: $PRIVACY_DOCKERFILE)..."
    docker build . -f "$PRIVACY_DOCKERFILE" -t "$PRIVACY_IMAGE"

    log_info "镜像构建完成:$PRIVACY_IMAGE"
}

# ------------------------------------------------------------------
# Kuscia 部署
# ------------------------------------------------------------------
reset_kuscia() {
    log_step "重置 Kuscia 环境 ..."
    local containers=(
        "${USER}-kuscia-master"
        "${USER}-kuscia-lite-${ALICE_NAME}"
        "${USER}-kuscia-lite-${BOB_NAME}"
    )
    for ctr in "${containers[@]}"; do
        if docker ps -a --filter "name=^/${ctr}$" --format '{{.Names}}' | grep -q .; then
            log_info "删除现有 Kuscia 容器:$ctr"
            docker rm -f "$ctr" >/dev/null 2>&1 || true
        fi
    done

    local kuscia_install_dir="${INSTALL_DIR:-$HOME/kuscia}"
    if [ -d "$kuscia_install_dir" ]; then
        log_warn "删除 Kuscia 数据目录:$kuscia_install_dir"
        local docker_kuscia_install_dir
        docker_kuscia_install_dir="$(to_docker_path "$kuscia_install_dir")"
        if docker run --rm -v "$docker_kuscia_install_dir:/kuscia_tmp" busybox \
            sh -c 'find /kuscia_tmp -mindepth 1 -delete' >/dev/null 2>&1; then
            log_info "Kuscia 数据目录已清空"
        else
            if command -v sudo >/dev/null 2>&1; then
                if [[ -n "${SUDO_PWD:-}" ]]; then
                    echo "$SUDO_PWD" | sudo -S rm -rf "$kuscia_install_dir" >/dev/null 2>&1 || true
                else
                    sudo rm -rf "$kuscia_install_dir" >/dev/null 2>&1 || true
                fi
            else
                rm -rf "$kuscia_install_dir" >/dev/null 2>&1 || true
            fi
        fi
    fi
    log_info "Kuscia 环境已重置"
}

start_kuscia() {
    log_step "检查 Kuscia Docker 环境 ..."

    if docker ps --filter "name=${USER}-kuscia-master" --format '{{.Names}}' | grep -q .; then
        log_info "Kuscia master 已在运行,跳过部署"
    else
        log_info "正在部署 Kuscia(master + alice + bob)..."

        cd "$KUSCIA_DIR/scripts/deploy"
        export SECRETFLOW_IMAGE="$PRIVACY_IMAGE"
        if [[ -n "$KUSCIA_IMAGE" ]]; then
            export KUSCIA_IMAGE
            log_info "使用自定义 Kuscia 镜像:$KUSCIA_IMAGE"
        fi

        # 使用 kuscia 自带的 start_standalone.sh 部署中心化集群
        export ROOT="${INSTALL_DIR:-$HOME/kuscia}"
        bash start_standalone.sh center -P NOTLS
    fi

    wait_for_port 127.0.0.1 18083 180 "Kuscia API gRPC"
    wait_for_port 127.0.0.1 18080 180 "Kuscia 跨域网关端口"
}

# ------------------------------------------------------------------
# 镜像导入
# ------------------------------------------------------------------
import_custom_image_to_lite() {
    local node="$1"
    local ctr="${USER}-kuscia-lite-${node}"
    local image_short="${PRIVACY_IMAGE#docker.io/}"
    local image_name="${image_short%:*}"
    local image_tag="${image_short#*:}"

    local image_exists_in_kuscia
    image_exists_in_kuscia() {
        docker exec -i "${ctr}" kuscia image list 2>&1 \
            | grep -E "(${image_name}|docker\.io/${image_name})" \
            | grep -qF "${image_tag}"
    }

    if ! docker ps --filter "name=^/${ctr}$" --format '{{.Names}}' | grep -q .; then
        log_warn "Kuscia lite ${node} 未运行,跳过镜像导入"
        return 0
    fi

    if [ "$RESET_KUSCIA" != true ] && image_exists_in_kuscia; then
        log_info "自定义镜像已在 ${node} 节点存在,跳过导入"
        return 0
    fi

    log_step "导入自定义镜像到 Kuscia ${node} 节点 ..."
    docker save "${PRIVACY_IMAGE}" | docker exec -i "${ctr}" kuscia image load
    if image_exists_in_kuscia; then
        log_info "自定义镜像已成功导入 ${node} 节点"
    else
        log_error "自定义镜像导入 ${node} 节点失败"
        return 1
    fi
}

import_custom_image_to_kuscia() {
    log_step "检查并导入自定义 SecretFlow 镜像到 Kuscia ..."
    import_custom_image_to_lite "$ALICE_NAME"
    import_custom_image_to_lite "$BOB_NAME"
}

# ------------------------------------------------------------------
# Privahub 后端（Go）
# ------------------------------------------------------------------
build_backend() {
    log_step "编译 Privahub 后端(Go，需要 CGO 支持 SQLite)..."
    cd "$PRIVAHUB_DIR"
    CGO_ENABLED=1 go build -o bin/privahub ./cmd/server
    if [ ! -f "$PRIVAHUB_DIR/bin/privahub" ]; then
        log_error "后端编译失败:未找到 bin/privahub"
        exit 1
    fi
    log_info "后端编译完成"
}

start_backend() {
    log_step "启动 Privahub 后端 ..."
    local pidfile="$LOG_DIR/backend.pid"

    if [ -f "$pidfile" ] && is_process_alive "$(cat "$pidfile")"; then
        log_info "后端已在运行(pid $(cat "$pidfile"))"
        return 0
    fi
    stop_service_by_pidfile "$pidfile" "backend"

    cd "$PRIVAHUB_DIR"

    # Docker Kuscia 模式下使用 dev profile (api_port: 18083, gateway: 127.0.0.1:18080)
    export PRIVAHUB_PROFILE=dev

    nohup ./bin/privahub -config ./config/privahub.yaml > "$LOG_DIR/backend.log" 2>&1 &

    echo $! > "$pidfile"
    disown $! 2>/dev/null || true
    log_info "后端进程已启动,pid $!"
    wait_for_port 127.0.0.1 8080 120 "后端 HTTP"
}

# ------------------------------------------------------------------
# Privahub 前端
# ------------------------------------------------------------------
start_frontend() {
    log_step "启动 Privahub 前端 ..."
    local pidfile="$LOG_DIR/frontend.pid"

    if [ -f "$pidfile" ] && is_process_alive "$(cat "$pidfile")"; then
        log_info "前端已在运行(pid $(cat "$pidfile"))"
        return 0
    fi
    stop_service_by_pidfile "$pidfile" "frontend"

    cd "$PRIVAHUB_DIR/web"
    if [ ! -d "node_modules" ]; then
        log_info "首次运行,安装前端依赖 ..."
        corepack pnpm install
    fi

    nohup corepack pnpm --filter @secretpad/app dev > "$LOG_DIR/frontend.log" 2>&1 &
    echo $! > "$pidfile"
    disown $! 2>/dev/null || true
    log_info "前端进程已启动,pid $!"

    if ! wait_for_port 127.0.0.1 8000 180 "前端开发服务器"; then
        return 1
    fi

    # 等待 HTTP 200
    log_info "等待前端 HTTP 首页可访问 ..."
    local i
    for ((i = 0; i < 30; i++)); do
        if curl -fsS --max-time 2 "http://127.0.0.1:8000/" >/dev/null 2>&1; then
            log_info "前端 HTTP 首页已就绪"
            return 0
        fi
        sleep 1
    done
    log_error "前端 HTTP 首页在 127.0.0.1:8000 未就绪,请查看 $LOG_DIR/frontend.log"
    return 1
}

# ------------------------------------------------------------------
# 摘要
# ------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  clwork 二次开发环境已启动${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "🌐 前端开发服务器:${BLUE}http://localhost:8000${NC}"
    echo -e "🔧 后端健康检查:${BLUE}http://localhost:8080/api/v1alpha1/healthz${NC}"
    echo ""
    echo -e "🐳 自定义 SecretFlow 镜像:${YELLOW}$PRIVACY_IMAGE${NC}"
    echo -e "👤 登录账号:${YELLOW}admin / 12345678${NC}"
    echo ""
    echo -e "📄 日志文件:"
    echo -e "   后端:$LOG_DIR/backend.log"
    echo -e "   前端:$LOG_DIR/frontend.log"
    echo ""
    echo -e "🛑 停止服务:${YELLOW}bash scripts/dev-stop.sh${NC}"
    echo -e "🛑 同时停止 Kuscia:${YELLOW}bash scripts/dev-stop.sh --kuscia${NC}"
    echo ""
}

# ------------------------------------------------------------------
# Main entrypoint
# ------------------------------------------------------------------
main() {
    case "${1:-}" in
    --check | -c)
        check_cloned_repositories
        check_environment
        echo ""
        log_info "环境检查通过"
        exit 0
        ;;
    --reset-kuscia)
        RESET_KUSCIA=true
        shift
        ;;
    --help | -h)
        cat <<EOF
clwork 二次开发环境一键启动脚本

用法:
  bash scripts/dev-start.sh          完整启动
  bash scripts/dev-start.sh --check  仅检查环境
  bash scripts/dev-start.sh --reset-kuscia  重置 Kuscia 后完整启动
  bash scripts/dev-start.sh --help          显示本帮助

环境变量:
  PRIVACY_IMAGE        自定义 SecretFlow 镜像 tag
  KUSCIA_IMAGE         自定义 Kuscia 镜像 tag
  CONDA_ENV            构建 wheel 时使用的 conda 环境(默认:sf310)
  INSTALL_DIR          Kuscia 安装目录(默认:\$HOME/kuscia)
  LOG_DIR              日志与 PID 文件目录(默认:<clwork>/logs)

停止服务:
  bash scripts/dev-stop.sh
  bash scripts/dev-stop.sh --kuscia
EOF
        exit 0
        ;;
    esac

    check_cloned_repositories
    mkdir -p "$LOG_DIR"

    check_environment
    check_required_ports
    build_backend
    build_secretflow_image
    if [[ "$RESET_KUSCIA" == "true" ]]; then
        reset_kuscia
    fi
    start_kuscia
    import_custom_image_to_kuscia
    start_backend
    start_frontend
    print_summary
}

main "$@"
