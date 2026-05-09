# ArgoAI

ArgoAI is an OpenShift console plugin and API service that diagnoses broken ArgoCD/OpenShift workloads with LLM providers, Kubernetes tool calls, and an optional RAG knowledge base.

## What You Need

- An OpenShift or ROSA cluster with `cluster-admin` access.
- `oc` logged into that cluster.
- Git, Go, Python/uv, Node.js, Yarn, and Docker or Podman.
- A Gemini and/or OpenRouter API key for live LLM tests.

Do not commit API keys, cluster passwords, kubeconfigs, or generated runtime logs.

## Windows

Recommended: run the project commands from Git Bash, WSL, or another Bash-compatible shell. PowerShell is fine for `oc login` and checks, but `setup-demo.sh` expects Bash.

1. Install prerequisites:

   - Git for Windows
   - Go
   - Node.js LTS
   - Yarn: `npm install -g yarn`
   - uv: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
   - Podman Desktop or Docker Desktop
   - OpenShift CLI (`oc`)

2. Start your container runtime:

   ```powershell
   podman machine init
   podman machine start
   ```

   Skip this if Docker Desktop is already running.

3. Clone and enter the repo:

   ```powershell
   git clone https://github.com/ishan-1729/ArgoAI.git
   git clone https://github.com/redhat-developer/gitops-console-plugin.git
   cd ArgoAI
   ```

4. Log into OpenShift:

   ```powershell
   oc login <cluster-api-url>
   oc whoami
   ```

5. Run the setup script from Bash:

   ```bash
   bash ./setup-demo.sh
   ```

6. Open the UI:

   ```text
   http://localhost:9000/argoai
   ```

## macOS

1. Install prerequisites:

   ```bash
   brew install git go node uv podman openshift-cli
   npm install -g yarn
   ```

   You can use Docker Desktop instead of Podman if preferred.

2. Start your container runtime:

   ```bash
   podman machine init
   podman machine start
   ```

   Skip this if Docker Desktop is already running.

3. Clone and enter the repo:

   ```bash
   git clone https://github.com/ishan-1729/ArgoAI.git
   git clone https://github.com/redhat-developer/gitops-console-plugin.git
   cd ArgoAI
   ```

4. Log into OpenShift:

   ```bash
   oc login <cluster-api-url>
   oc whoami
   ```

5. Run the setup script:

   ```bash
   bash ./setup-demo.sh
   ```

6. Open the UI:

   ```text
   http://localhost:9000/argoai
   ```

## What Setup Does

`setup-demo.sh` verifies the cluster login, installs/checks OpenShift GitOps, deploys seven intentionally broken demo apps, creates ArgoCD Application CRs, starts the Go service, starts the Python agent, starts the console plugins, and opens the local console stack on `localhost:9000`.

For the richer GitOps navigation, clone `https://github.com/redhat-developer/gitops-console-plugin` next to the `ArgoAI` folder before running setup. The setup script auto-detects either `../gitops-console-plugin` or `./gitops-console-plugin`, starts it on port `9002`, and launches the console with `ENABLE_GITOPS_PLUGIN=true`. If your checkout is somewhere else, set `GITOPS_CONSOLE_PLUGIN_DIR=/path/to/gitops-console-plugin`.

By default, the demo ArgoCD Applications point at `https://github.com/tzprograms/ArgoAI` with paths under `demo/`. For a fork, set `ARGOAI_DEMO_REPO_URL`, `ARGOAI_DEMO_TARGET_REVISION`, and optionally `ARGOAI_DEMO_PATH_PREFIX` before running `setup-demo.sh`.

## Demo Scenarios

Non-image-pull scenarios use public Red Hat registry images so Docker Hub rate limits do not mask the intended failure mode.

| App | Failure Mode | Expected Agent |
|-----|--------------|----------------|
| `demo-oomkilled` | Allocates 256MB with a 64Mi limit, producing OOMKilled or CrashLoopBackOff | Runtime Analyzer |
| `demo-imagepull` | Nonexistent image tag, producing ImagePullBackOff | Runtime Analyzer |
| `demo-crashloop` | App exits with code 1 after a simulated DB connection failure | Runtime Analyzer |
| `demo-missing-config` | References a nonexistent ConfigMap, producing CreateContainerConfigError | Config Analyzer |
| `demo-network-issue` | Probe targets an unused port, producing readiness/liveness failures | Network Analyzer |
| `demo-storage-issue` | PVC references a nonexistent StorageClass, leaving the pod Pending | Storage Analyzer |
| `demo-rbac-issue` | Restricted ServiceAccount tries to list Secrets, producing Forbidden logs and CrashLoopBackOff | RBAC Analyzer |

## Verify It Works

Health checks:

```bash
curl http://localhost:8080/api/v1/health
curl http://localhost:8081/health
```

Demo workloads:

```bash
oc get applications -n openshift-gitops
oc get pods -n default | grep demo
```

Optional live RAG and tool-call check:

```bash
export OPENROUTER_API_KEY="<openrouter-key>"
export GEMINI_API_KEY="<gemini-key>"
export GOOGLE_API_KEY="$GEMINI_API_KEY"
export RAG_INDEX_PATH="./rag_data/vector_db"
export GO_SERVICE_URL="http://localhost:8080"

uv run python scripts/live_rag_tool_provider_check.py
```

The final summary should show:

```json
{
  "all_ok": true,
  "rag_ok": true,
  "cluster_tool_ok": true,
  "provider_ok": {
    "gemini": true,
    "openrouter": true
  }
}
```

## Stopping

Keep the setup terminal open while demoing. Press `Ctrl+C` in that terminal to stop the Go service, Python agent, plugin server, and console container.
