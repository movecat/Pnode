#!/usr/bin/env bash
set -Eeuo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Override with V2NODE_IMAGE=... if you publish a custom image tag.
DEFAULT_IMAGE="${V2NODE_IMAGE:-ghcr.io/movecat/pnode:latest}"

INSTALL_DIR="/opt/v2node"
DATA_DIR="data"
IMAGE="$DEFAULT_IMAGE"
API_HOST=""
NODE_ID=""
API_KEY=""
LOG_LEVEL="warning"
ACCESS_LOG="none"
TIMEOUT="15"
TZ_VALUE="${TZ:-Asia/Shanghai}"
CONTAINER_NAME="v2node"
NETWORK_MODE="host"
FORCE="false"

usage() {
    cat <<EOF
Usage:
  bash install-docker.sh --api-host URL --node-id ID --api-key KEY [options]

Required:
  --api-host URL       V2board API host, for example https://example.com/
  --node-id ID         Node ID from the panel
  --api-key KEY        Node communication key from the panel

Options:
  --image IMAGE        Docker image to run (default: ${DEFAULT_IMAGE})
  --install-dir DIR    Install directory (default: ${INSTALL_DIR})
  --log-level LEVEL    Log level (default: ${LOG_LEVEL})
  --access-log VALUE   Access log path or none (default: ${ACCESS_LOG})
  --timeout SECONDS    Panel request timeout (default: ${TIMEOUT})
  --timezone TZ        Container timezone (default: ${TZ_VALUE})
  --container-name N   Container name (default: ${CONTAINER_NAME})
  --network-mode MODE  Docker network mode (default: ${NETWORK_MODE})
  --force              Continue even if native v2node files are detected
  -h, --help           Show this help

Example:
  bash install-docker.sh \\
    --image ghcr.io/movecat/pnode:latest \\
    --api-host https://example.com/ \\
    --node-id 1 \\
    --api-key replace-with-your-api-key
EOF
}

die() {
    echo -e "${red}错误:${plain} $*" >&2
    exit 1
}

info() {
    echo -e "${green}$*${plain}"
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "请使用 root 用户运行，例如: sudo bash install-docker.sh ..."
    fi
}

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

require_value() {
    local name="$1"
    local value="${2-}"
    [[ -n "$value" ]] || die "${name} 需要参数"
    printf '%s' "$value"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)
                API_HOST="$(require_value "$1" "${2-}")"; shift 2 ;;
            --node-id)
                NODE_ID="$(require_value "$1" "${2-}")"; shift 2 ;;
            --api-key)
                API_KEY="$(require_value "$1" "${2-}")"; shift 2 ;;
            --image)
                IMAGE="$(require_value "$1" "${2-}")"; shift 2 ;;
            --install-dir)
                INSTALL_DIR="$(require_value "$1" "${2-}")"; shift 2 ;;
            --log-level)
                LOG_LEVEL="$(require_value "$1" "${2-}")"; shift 2 ;;
            --access-log)
                ACCESS_LOG="$(require_value "$1" "${2-}")"; shift 2 ;;
            --timeout)
                TIMEOUT="$(require_value "$1" "${2-}")"; shift 2 ;;
            --timezone)
                TZ_VALUE="$(require_value "$1" "${2-}")"; shift 2 ;;
            --container-name)
                CONTAINER_NAME="$(require_value "$1" "${2-}")"; shift 2 ;;
            --network-mode)
                NETWORK_MODE="$(require_value "$1" "${2-}")"; shift 2 ;;
            --force)
                FORCE="true"; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                die "未知参数: $1" ;;
        esac
    done
}

validate_args() {
    [[ -n "$API_HOST" ]] || die "缺少 --api-host"
    [[ -n "$NODE_ID" ]] || die "缺少 --node-id"
    [[ -n "$API_KEY" ]] || die "缺少 --api-key"
    [[ -n "$IMAGE" ]] || die "缺少 --image"

    is_uint "$NODE_ID" || die "--node-id 必须是数字"
    is_uint "$TIMEOUT" || die "--timeout 必须是数字"
}

detect_native_install() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    if [[ -f /etc/systemd/system/v2node.service || -d /usr/local/v2node ]]; then
        die "检测到宿主机原生 v2node 安装。请先停止/卸载原生版本，或确认不会冲突后加 --force"
    fi
}

ensure_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        info "未检测到 Docker，开始安装 Docker..."
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com | sh
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://get.docker.com | sh
        else
            die "缺少 curl/wget，无法自动安装 Docker"
        fi
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker >/dev/null 2>&1 || true
    fi

    docker info >/dev/null 2>&1 || die "Docker daemon 未运行，请检查 Docker 安装状态"

    if ! docker compose version >/dev/null 2>&1; then
        die "未检测到 docker compose 插件。请安装 Docker Compose v2 后重试"
    fi
}

write_config() {
    local config_dir="${INSTALL_DIR}/${DATA_DIR}"
    local config_file="${config_dir}/config.json"

    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    local api_host api_key log_level access_log
    api_host="$(json_escape "$API_HOST")"
    api_key="$(json_escape "$API_KEY")"
    log_level="$(json_escape "$LOG_LEVEL")"
    access_log="$(json_escape "$ACCESS_LOG")"

    umask 077
    cat > "$config_file" <<EOF
{
    "Log": {
        "Level": "${log_level}",
        "Output": "",
        "Access": "${access_log}"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${NODE_ID},
            "ApiKey": "${api_key}",
            "Timeout": ${TIMEOUT}
        }
    ]
}
EOF

    chmod 600 "$config_file"
}

write_compose() {
    mkdir -p "$INSTALL_DIR"

    cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
services:
  v2node:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    network_mode: ${NETWORK_MODE}
    environment:
      TZ: ${TZ_VALUE}
    volumes:
      - ./${DATA_DIR}:/etc/v2node
EOF
}

start_service() {
    cd "$INSTALL_DIR"

    info "拉取镜像: ${IMAGE}"
    docker compose pull

    info "启动 v2node Docker 容器..."
    docker compose up -d

    info "安装完成"
    echo "安装目录: ${INSTALL_DIR}"
    echo "配置文件: ${INSTALL_DIR}/${DATA_DIR}/config.json"
    echo "查看日志: docker logs -f ${CONTAINER_NAME}"
}

main() {
    parse_args "$@"
    require_root
    validate_args
    detect_native_install
    ensure_docker
    write_config
    write_compose
    start_service
}

main "$@"
