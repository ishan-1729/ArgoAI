#!/usr/bin/env bash

set -euo pipefail

PLUGIN_NAME="argocd-agent-plugin"

CONSOLE_IMAGE=${CONSOLE_IMAGE:="quay.io/openshift/origin-console:latest"}
CONSOLE_PORT=${CONSOLE_PORT:=9000}

echo "Starting OpenShift Console with ArgoAI plugin..."

BRIDGE_USER_AUTH="disabled"
BRIDGE_K8S_MODE="off-cluster"
BRIDGE_K8S_AUTH="bearer-token"
BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS=true
BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT=$(oc whoami --show-server)
set +e
BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.thanosPublicURL}' 2>/dev/null)
BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.alertmanagerPublicURL}' 2>/dev/null)
set -e
BRIDGE_K8S_AUTH_BEARER_TOKEN=$(oc whoami --show-token 2>/dev/null)
BRIDGE_USER_SETTINGS_LOCATION="localstorage"

detect_windows_podman_host() {
    if command -v ipconfig.exe >/dev/null 2>&1; then
        local gateway
        gateway="$(ipconfig.exe 2>/dev/null | tr -d '\r' | awk '/vEthernet \(WSL/{found=1} found && /IPv4 Address/{sub(/.*: /, ""); print; exit}')"
        if [ -n "$gateway" ]; then
            printf '%s\n' "$gateway"
            return 0
        fi
    fi

    if ! command -v wsl.exe >/dev/null 2>&1; then
        return 1
    fi

    local distro
    distro="$(timeout 5s wsl.exe -l -q 2>/dev/null | tr -d '\r\000' | grep '^podman-' | head -n 1 || true)"
    if [ -z "$distro" ]; then
        return 1
    fi

    local gateway
    gateway="$(timeout 5s wsl.exe -d "$distro" -- sh -lc "ip route | sed -n 's/default via \\([^ ]*\\).*/\\1/p' | head -n1" 2>/dev/null | tr -d '\r' | head -n 1 || true)"
    if [ -z "$gateway" ]; then
        return 1
    fi

    printf '%s\n' "$gateway"
}

PLUGIN_HOST="${CONSOLE_PLUGIN_HOST:-}"
if [ -z "$PLUGIN_HOST" ]; then
    if [ -x "$(command -v podman)" ]; then
        if [ "$(uname -s)" = "Linux" ]; then
            PLUGIN_HOST="localhost"
        else
            PLUGIN_HOST="$(detect_windows_podman_host || true)"
            PLUGIN_HOST="${PLUGIN_HOST:-host.containers.internal}"
        fi
    else
        PLUGIN_HOST="host.docker.internal"
    fi
fi

# Load the ArgoAI plugin. Optionally include a GitOps plugin when one is running.
AGENT_PLUGIN="${PLUGIN_NAME}=http://${PLUGIN_HOST}:9001"
BRIDGE_PLUGINS="${AGENT_PLUGIN}"
if [ "${ENABLE_GITOPS_PLUGIN:-false}" = "true" ]; then
    GITOPS_PLUGIN="gitops-plugin=http://${PLUGIN_HOST}:9002"
    BRIDGE_PLUGINS="${AGENT_PLUGIN},${GITOPS_PLUGIN}"
fi

echo "API Server: $BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT"
echo "Console Image: $CONSOLE_IMAGE"
echo "Console URL: http://localhost:${CONSOLE_PORT}"
echo "Plugin host from console container: ${PLUGIN_HOST}"
echo "ArgoAI plugin: http://${PLUGIN_HOST}:9001"
if [ "${ENABLE_GITOPS_PLUGIN:-false}" = "true" ]; then
    echo "GitOps plugin: http://${PLUGIN_HOST}:9002"
fi
echo ""
echo "NOTE: If the GitOps sidebar is needed, run gitops-console-plugin on port 9002 and set ENABLE_GITOPS_PLUGIN=true."
echo ""

BRIDGE_ENV_FILE=""
cleanup_bridge_env_file() {
    if [ -n "${BRIDGE_ENV_FILE:-}" ]; then
        rm -f "$BRIDGE_ENV_FILE"
    fi
}
trap cleanup_bridge_env_file EXIT

write_bridge_env_file() {
    BRIDGE_ENV_FILE="$(mktemp)"
    {
        printf 'BRIDGE_USER_AUTH=%s\n' "$BRIDGE_USER_AUTH"
        printf 'BRIDGE_K8S_MODE=%s\n' "$BRIDGE_K8S_MODE"
        printf 'BRIDGE_K8S_AUTH=%s\n' "$BRIDGE_K8S_AUTH"
        printf 'BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS=%s\n' "$BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS"
        printf 'BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT=%s\n' "$BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT"
        printf 'BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS=%s\n' "$BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS"
        printf 'BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER=%s\n' "$BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER"
        printf 'BRIDGE_K8S_AUTH_BEARER_TOKEN=%s\n' "$BRIDGE_K8S_AUTH_BEARER_TOKEN"
        printf 'BRIDGE_USER_SETTINGS_LOCATION=%s\n' "$BRIDGE_USER_SETTINGS_LOCATION"
        printf 'BRIDGE_PLUGINS=%s\n' "$BRIDGE_PLUGINS"
    } > "$BRIDGE_ENV_FILE"
}

if [ -x "$(command -v podman)" ]; then
    if [ "$(uname -s)" = "Linux" ]; then
        write_bridge_env_file
        podman run --platform linux/amd64 --pull always --rm --network=host \
            --env-file "$BRIDGE_ENV_FILE" \
            $CONSOLE_IMAGE
    else
        write_bridge_env_file
        podman run --platform linux/amd64 --pull always --rm -p "$CONSOLE_PORT":9000 \
            --env-file "$BRIDGE_ENV_FILE" \
            $CONSOLE_IMAGE
    fi
else
    write_bridge_env_file
    docker run --platform linux/amd64 --pull always --rm -p "$CONSOLE_PORT":9000 \
        --env-file "$BRIDGE_ENV_FILE" \
        $CONSOLE_IMAGE
fi
