#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

on_exit() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo
        echo "[ArgoAI] Startup failed. Fix the message above and run this file again."
        read -r -p "Press Enter to close this window..." || true
    fi
}
trap on_exit EXIT

echo "[ArgoAI] macOS launcher"
echo

if ! command -v git >/dev/null 2>&1; then
    echo "[ArgoAI] Git is required. Install it with: brew install git"
    exit 1
fi

if ! command -v oc >/dev/null 2>&1; then
    echo "[ArgoAI] OpenShift CLI (oc) is required. Install it with: brew install openshift-cli"
    exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
    echo "[ArgoAI] You are not logged into OpenShift."
    echo "[ArgoAI] Run: oc login <cluster-api-url>"
    exit 1
fi

GITOPS_DIR="$SCRIPT_DIR/../gitops-console-plugin"
if [ ! -d "$GITOPS_DIR/.git" ]; then
    echo "[ArgoAI] Cloning Red Hat GitOps console plugin next to ArgoAI..."
    git clone https://github.com/redhat-developer/gitops-console-plugin.git "$GITOPS_DIR"
else
    echo "[ArgoAI] GitOps console plugin checkout found."
fi

if command -v podman >/dev/null 2>&1; then
    echo "[ArgoAI] Starting Podman machine if needed..."
    podman machine start >/dev/null 2>&1 || true
fi

echo
echo "[ArgoAI] Starting demo. Keep this window open; press Ctrl+C here to stop."
echo

OPEN_UI=true bash ./setup-demo.sh
