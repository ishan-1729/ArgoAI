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

load_brew_shellenv() {
    if command -v brew >/dev/null 2>&1; then
        eval "$(brew shellenv)"
        return 0
    fi

    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$brew_bin" ]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done

    return 1
}

ensure_homebrew() {
    if load_brew_shellenv; then
        return 0
    fi

    echo "[ArgoAI] Homebrew was not found. Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if ! load_brew_shellenv; then
        echo "[ArgoAI] Homebrew installed, but brew was not found on PATH."
        echo "[ArgoAI] Open a new Terminal window and run this launcher again."
        exit 1
    fi
}

ensure_brew_package() {
    local command_name="$1"
    local formula="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        echo "[ArgoAI] Found ${command_name}."
        return 0
    fi

    ensure_homebrew
    echo "[ArgoAI] Installing ${formula}..."
    brew install "$formula"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "[ArgoAI] Installed ${formula}, but ${command_name} is still not on PATH."
        echo "[ArgoAI] Open a new Terminal window and run this launcher again."
        exit 1
    fi
}

ensure_yarn() {
    if command -v yarn >/dev/null 2>&1; then
        echo "[ArgoAI] Found yarn."
        return 0
    fi

    ensure_brew_package node node
    echo "[ArgoAI] Installing yarn..."
    if ! npm install -g yarn; then
        ensure_homebrew
        brew install yarn
    fi

    if ! command -v yarn >/dev/null 2>&1; then
        echo "[ArgoAI] Yarn installation did not put yarn on PATH."
        exit 1
    fi
}

ensure_container_runtime() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo "[ArgoAI] Docker is running."
        return 0
    fi

    ensure_brew_package podman podman

    if ! podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
        echo "[ArgoAI] Initializing Podman machine..."
        podman machine init
    fi

    echo "[ArgoAI] Starting Podman machine if needed..."
    podman machine start >/dev/null 2>&1 || true

    if ! podman info >/dev/null 2>&1; then
        echo "[ArgoAI] Podman is installed but not running."
        echo "[ArgoAI] Try: podman machine start"
        exit 1
    fi
}

ensure_openshift_login() {
    if oc whoami >/dev/null 2>&1; then
        echo "[ArgoAI] OpenShift login found: $(oc whoami)"
        return 0
    fi

    echo "[ArgoAI] OpenShift CLI is installed, but you are not logged in."
    echo "[ArgoAI] Paste the full oc login command for your cluster, then press Enter."
    echo "[ArgoAI] Example: oc login https://api.example:6443 --username cluster-admin --password ..."
    read -r -p "> " OC_LOGIN_COMMAND

    if [ -z "$OC_LOGIN_COMMAND" ]; then
        echo "[ArgoAI] No login command provided."
        exit 1
    fi

    case "$OC_LOGIN_COMMAND" in
        oc\ login\ * )
            bash -lc "$OC_LOGIN_COMMAND"
            ;;
        * )
            echo "[ArgoAI] Expected a command starting with: oc login"
            exit 1
            ;;
    esac

    if ! oc whoami >/dev/null 2>&1; then
        echo "[ArgoAI] OpenShift login still failed."
        exit 1
    fi
}

ensure_brew_package git git
ensure_brew_package bash bash
ensure_brew_package go go
ensure_brew_package node node
ensure_brew_package uv uv
ensure_yarn
ensure_brew_package oc openshift-cli
ensure_container_runtime
ensure_openshift_login

echo

GITOPS_DIR="$SCRIPT_DIR/../gitops-console-plugin"
if [ ! -d "$GITOPS_DIR/.git" ]; then
    echo "[ArgoAI] Cloning Red Hat GitOps console plugin next to ArgoAI..."
    git clone https://github.com/redhat-developer/gitops-console-plugin.git "$GITOPS_DIR"
else
    echo "[ArgoAI] GitOps console plugin checkout found."
fi

echo
echo "[ArgoAI] Starting demo. Keep this window open; press Ctrl+C here to stop."
echo

OPEN_UI=true bash ./setup-demo.sh
