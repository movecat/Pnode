#!/bin/sh
set -eu

config_path_from_args() {
    previous=""
    for arg in "$@"; do
        if [ "$previous" = "--config" ] || [ "$previous" = "-c" ]; then
            printf '%s\n' "$arg"
            return 0
        fi

        case "$arg" in
            --config=*)
                printf '%s\n' "${arg#--config=}"
                return 0
                ;;
            -c=*)
                printf '%s\n' "${arg#-c=}"
                return 0
                ;;
        esac

        previous="$arg"
    done

    return 1
}

wants_help() {
    for arg in "$@"; do
        case "$arg" in
            help|--help|-h)
                return 0
                ;;
        esac
    done
    return 1
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

generate_config() {
    config_path="$1"

    if [ -z "${V2NODE_API_HOST:-}" ] || [ -z "${V2NODE_NODE_ID:-}" ] || [ -z "${V2NODE_API_KEY:-}" ]; then
        echo "v2node: config not found: ${config_path}" >&2
        echo "v2node: mount config.json to /etc/v2node/config.json or set V2NODE_API_HOST, V2NODE_NODE_ID and V2NODE_API_KEY." >&2
        exit 64
    fi

    if ! is_uint "$V2NODE_NODE_ID"; then
        echo "v2node: V2NODE_NODE_ID must be an unsigned integer." >&2
        exit 64
    fi

    timeout="${V2NODE_TIMEOUT:-15}"
    if ! is_uint "$timeout"; then
        echo "v2node: V2NODE_TIMEOUT must be an unsigned integer." >&2
        exit 64
    fi

    log_level="${V2NODE_LOG_LEVEL:-warning}"
    access_log="${V2NODE_ACCESS_LOG:-none}"
    api_host="$(json_escape "$V2NODE_API_HOST")"
    api_key="$(json_escape "$V2NODE_API_KEY")"
    log_level="$(json_escape "$log_level")"
    access_log="$(json_escape "$access_log")"

    mkdir -p "$(dirname "$config_path")"
    umask 077
    cat > "$config_path" <<EOF
{
    "Log": {
        "Level": "${log_level}",
        "Output": "",
        "Access": "${access_log}"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${V2NODE_NODE_ID},
            "ApiKey": "${api_key}",
            "Timeout": ${timeout}
        }
    ]
}
EOF

    echo "v2node: generated ${config_path} from environment variables." >&2
}

if [ "$#" -eq 0 ]; then
    set -- server
fi

if [ "${1#-}" != "$1" ]; then
    set -- server "$@"
fi

if [ "$1" = "server" ] && ! wants_help "$@"; then
    config_path="$(config_path_from_args "$@" || true)"
    if [ -z "$config_path" ]; then
        config_path="${V2NODE_CONFIG:-/etc/v2node/config.json}"
        set -- "$@" --config "$config_path"
    fi

    if [ ! -f "$config_path" ]; then
        generate_config "$config_path"
    fi
fi

exec /usr/local/bin/v2node "$@"
