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

# Load BOTH the gitops plugin and the argoagent plugin
GITOPS_PLUGIN="gitops-plugin=http://host.containers.internal:9002"
AGENT_PLUGIN="${PLUGIN_NAME}=http://host.containers.internal:9001"

echo "API Server: $BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT"
echo "Console Image: $CONSOLE_IMAGE"
echo "Console URL: http://localhost:${CONSOLE_PORT}"
echo "ArgoAI plugin: http://localhost:9001"
echo ""
echo "NOTE: If GitOps sidebar is needed, also run the gitops-console-plugin on port 9002:"
echo "  cd ../gitops-console-plugin && yarn start --port 9002"
echo ""

if [ -x "$(command -v podman)" ]; then
    if [ "$(uname -s)" = "Linux" ]; then
        BRIDGE_PLUGINS="${AGENT_PLUGIN},${GITOPS_PLUGIN}"
        BRIDGE_PLUGINS="${BRIDGE_PLUGINS//host.containers.internal/localhost}"
        podman run --platform linux/amd64 --pull always --rm --network=host \
            --env-file <(set | grep BRIDGE) \
            $CONSOLE_IMAGE
    else
        BRIDGE_PLUGINS="${AGENT_PLUGIN},${GITOPS_PLUGIN}"
        podman run --platform linux/amd64 --pull always --rm -p "$CONSOLE_PORT":9000 \
            --env-file <(set | grep BRIDGE) \
            $CONSOLE_IMAGE
    fi
else
    BRIDGE_PLUGINS="${AGENT_PLUGIN//host.containers.internal/host.docker.internal},${GITOPS_PLUGIN//host.containers.internal/host.docker.internal}"
    docker run --platform linux/amd64 --pull always --rm -p "$CONSOLE_PORT":9000 \
        --env-file <(set | grep BRIDGE) \
        $CONSOLE_IMAGE
fi
