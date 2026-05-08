# PROJECT CONTEXT: ArgoAI -- Multi-Agent Diagnostic System for ArgoCD

> This file is the single source of truth for all architectural decisions, design details,
> implementation plans, and domain knowledge for the project. Any LLM or developer starting
> a new coding session should read this file FIRST before writing any code.

---

## 1. Project Overview

- **Title:** ArgoAI

### Problem Statement

ArgoCD automates Kubernetes deployment synchronization via GitOps, but when applications
fail (Degraded, OutOfSync, Missing, Error states), developers must manually inspect pod logs,
K8s events, resource manifests, and configuration diffs to diagnose root causes. This is
time-consuming, error-prone, and requires deep K8s expertise.

### Solution

A two-service system (Go for K8s/API, Python for AI/agents) that sits alongside ArgoCD and provides:

1. **AI-Powered Fault Analysis** -- Router-based multi-agent diagnostic system with intelligent triage
2. **RAG Knowledge Base** -- Shared with OpenShift Lightspeed, containing KCS articles, CEE docs, FAQs
3. **BYOM (Bring Your Own Model)** -- Users provide their own LLM API key OR configure via K8s Secret
4. **OpenShift Console Plugin** -- ArgoAI UI integrated into the OpenShift console under the GitOps sidebar

### POC Scope (Current Implementation)

**In scope:**
- A2A-based agent routing with 5 specialist agents (Runtime, Config, Network, Storage, RBAC)
- All diagnosis goes through real LLM providers (Gemini, OpenAI, Anthropic, Groq, OpenRouter, Ollama)
- Shared RAG knowledge base (pre-built FAISS index from Lightspeed BYOK)
- Secure API key handling (K8s Secrets + BYOM fallback)
- Semantic caching for diagnosis results (15-min TTL)
- Intelligent log filtering before LLM context
- SSE streaming of reasoning steps
- Read-only cluster access (pod logs, events, resource manifests)
- App-scoped signal collection (events and pods filtered to the target ArgoCD app)
- Prometheus metrics and health checks
- Kubernetes deployment manifests (separate Go and Python pods)
- OpenShift Console dynamic plugin (ArgoAI under GitOps sidebar)
- Tool-call limit enforcement (default 3 calls, hard cap 5) via ADK tool callbacks
- Tool response truncation before results are fed back into the next LLM round
- LLM diagnosis timeout (configurable, default 90s)
- JSON response mode for Gemini only when tools are not attached

**Out of scope (post-POC):**
- Remediation / applying fixes (must go through Git, not direct cluster patches)
- Hybrid search (BM25 + dense vectors)
- CRDs (HealthAnalysis, AgentPolicy, etc.)
- ArgoCD UI extension (proxy extension approach)
- Alertmanager webhook trigger
- Automated failure detection (watcher)

---

## 2. System Architecture

### Two-Service Design

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                            │
│                                                                       │
│  ┌─────────────────────────────────┐                                 │
│  │  argocd-agent-go Pod (:8080)    │                                 │
│  │                                 │                                 │
│  │  External API:                  │                                 │
│  │    POST /api/v1/diagnose        │                                 │
│  │    GET  /api/v1/providers       │                                 │
│  │                                 │                                 │
│  │  Internal K8s API:              │                                 │
│  │    /internal/k8s/*              │                                 │
│  │    /internal/argocd/*           │                                 │
│  └────────────┬────────────────────┘                                 │
│               │ HTTP                                                  │
│  ┌────────────┴────────────────────┐                                 │
│  │  argocd-agent-python Pod (:8081)│                                 │
│  │                                 │                                 │
│  │  A2A Router → 5 Specialist      │                                 │
│  │  Agents (LLM-powered)          │                                 │
│  │                                 │                                 │
│  │  FAISS Index (mounted volume)   │                                 │
│  └─────────────────────────────────┘                                 │
│                                                                       │
│  ┌─────────────────────────────────┐                                 │
│  │  ArgoAI Console Plugin          │                                 │
│  │  (OpenShift dynamic plugin)     │                                 │
│  └─────────────────────────────────┘                                 │
└───────────────────────────────────────────────────────────────────────┘
```

### Why Two Services (Go + Python)?

| Concern | Language | Reason |
|---------|----------|--------|
| K8s API interactions | Go | `client-go` is the official, fully-typed K8s client |
| AI/Agent orchestration | Python | Google ADK, LiteLLM, sentence-transformers, FAISS |
| Security isolation | Go | Python pod has NO K8s RBAC. Prompt injection can't reach K8s API. |

---

## 3. Agent Architecture (A2A-Based Routing)

### Specialist Agents

| Agent | Description | Triggers |
|-------|-------------|----------|
| **Runtime Analyzer** | Pod crashes, OOM, image pulls, scheduling | `OOMKilled`, `CrashLoopBackOff`, `ImagePullBackOff`, `Degraded` health |
| **Config Analyzer** | ArgoCD sync, Git, Helm, Kustomize | `SyncError`, `ComparisonError`, `OutOfSync` |
| **Network Analyzer** | Connectivity, DNS, TLS, probes | `Unhealthy`, `connection refused`, `tls` |
| **Storage Analyzer** | PVC, volumes, StorageClass | `FailedMount`, `ProvisioningFailed`, `pvc` |
| **RBAC Analyzer** | Permissions, ServiceAccounts | `Forbidden`, `cannot get`, `unauthorized` |

### Routing Strategy

1. **Pod state matching (highest priority):** Match `stateReason`/`lastTerminatedReason` from pre-loaded pod statuses against AgentCard triggers. Pod states are always app-scoped.
2. **Event reason matching:** Match warning event reasons against AgentCard trigger lists.
3. **Keyword matching:** Search event messages and pod states for trigger keywords.
4. **Health/sync conditions:** Match ArgoCD health and sync status.
5. **Default:** Runtime Analyzer (general-purpose fallback).

Priority resolution when multiple agents match: `storage > rbac > network > config > runtime`

### Agent Prompt Design

All 5 agents follow the same prompt structure:
- **AVAILABLE TOOLS** -- Explicit whitelist to prevent hallucinated tool names
- **CONTEXT-FIRST RULE** -- Analyze pre-loaded data before calling tools
- **TOOL BUDGET** -- Maximum 3 tool calls per diagnosis
- **DIAGNOSTIC DECISION TREE** -- Migrated from the former rule-based engine
- **ANTI-HALLUCINATION RULES** -- Only report findings supported by evidence
- **OUTPUT FORMAT** -- Strict JSON, no markdown: `{"error": "...", "cause": "...", "fix": "..."}`

### Caching

| Cache | TTL | Purpose |
|-------|-----|---------|
| **Route Cache** | 20 min | Avoid repeated routing for same symptom pattern |
| **Diagnosis Cache** | 15 min | Avoid re-analyzing identical issues |

### Signal Pre-loading

The Go service collects signals upfront and sends them to the Python agent:
- ArgoCD Application health, sync, conditions
- Warning events (filtered to app-managed resources)
- Pod statuses with container state details (filtered to app-owned pods)
- Pre-loaded logs from first unhealthy pod (100 tail lines)
- ArgoCD source info (repoURL, targetRevision)

---

## 4. Tool System

### Two-Hop Architecture

```
LLM → ADK Agent → Python FunctionTool → HTTP POST → Go Internal API → K8s API
```

### Available Tools

| Tool | Go Endpoint | Purpose |
|------|-------------|---------|
| `get_events` | `POST /internal/k8s/events` | List K8s events (warnings prioritized) |
| `list_pods` | `POST /internal/k8s/pods` | List pods with status, restarts |
| `get_resource` | `POST /internal/k8s/resource` | Fetch any K8s resource manifest |
| `get_pod_logs` | `POST /internal/k8s/pod-logs` | Get filtered pod logs |
| `get_argocd_app` | `POST /internal/argocd/app` | Get ArgoCD Application health, sync, conditions |
| `get_argocd_diff` | `POST /internal/argocd/diff` | Get desired-vs-live diff |
| `rag_search` | (direct FAISS) | Search the knowledge base |

---

## 5. LLM Providers

| Provider | Default Model | Notes |
|----------|---------------|-------|
| `gemini` / `google` | `gemini-2.5-flash` | Native ADK support; JSON response mode only when tools are not attached |
| `openai` / `chatgpt` | `gpt-4o-mini` | Via LiteLLM |
| `anthropic` / `claude` | `claude-3-haiku-20240307` | Via LiteLLM |
| `groq` | `llama-3.1-8b-instant` | Via LiteLLM, free tier, weaker tool calling |
| `openrouter` | `openai/gpt-oss-20b:free` | Via LiteLLM/OpenRouter; paid models require account credits |
| `ollama` | `qwen3:32b` | Local, no API key needed |

All providers require an API key (via K8s Secret or BYOM request parameter) except `ollama`.

---

## 6. RAG Architecture

### Shared Knowledge Base with Lightspeed

The RAG uses a pre-built FAISS index from the OpenShift Lightspeed BYOK system.

**Quay Image:** `quay.io/devtools_gitops/argocd_lightspeed_byok:v0.0.4`

| Property | Value |
|----------|-------|
| Format | LlamaIndex + FAISS |
| Embedding Model | `sentence-transformers/all-mpnet-base-v2` (768 dimensions) |
| Total Documents | 4,801 chunks from 809 files |
| Vector Store | `faiss.IndexFlatIP` (inner product similarity) |
| Relevance Threshold | 0.65 (below this, inline help fallback is returned) |

RAG is controlled by the `ENABLE_RAG` environment variable (default: `true`). When RAG scores are low, the system returns curated inline help covering 13 common error types.

---

## 7. OpenShift Console Plugin (ArgoAI)

### Architecture

The ArgoAI UI is a standalone OpenShift Console dynamic plugin that adds an "ArgoAI" navigation item under the GitOps sidebar section.

| Component | Details |
|-----------|---------|
| Plugin name | `argocd-agent-plugin` |
| Display name | ArgoAI |
| Framework | React 17, TypeScript, PatternFly 6, Webpack 5 |
| Console SDK | `@openshift-console/dynamic-plugin-sdk` ^4.19.1 |
| Nav location | GitOps sidebar section, after Rollouts separator |

### UI Features

- **Application list** -- Table of ArgoCD Applications with health/sync status labels
- **Provider selector** -- Choose LLM provider (Gemini, OpenAI, Groq, Ollama, etc.)
- **API key input** -- BYOM mode for hosted providers
- **Diagnose button** -- Triggers SSE-streamed diagnosis
- **Live agent log** -- Real-time display of routing, tool calls, reasoning events
- **Diagnosis result** -- Structured display with Error, Root Cause, Confidence, Fix, Evidence

### Local Development

```bash
# Terminal 1: ArgoAI plugin (port 9001)
cd console-plugin && yarn start

# Terminal 2: GitOps plugin (port 9002, provides GitOps sidebar)
cd gitops-console-plugin && yarn start --port 9002

# Terminal 3: OpenShift console container (port 9000)
cd console-plugin && ./start-console.sh

# Terminal 4-5: Backend services
make run-go          # Go on :8080
make run-agent       # Python on :8081
```

Console available at `http://localhost:9000`.

---

## 8. Security

### API Key Handling

**Mode 1: Kubernetes Secret (Recommended)**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-agent-llm-keys
  namespace: argocd-agent
stringData:
  gemini-api-key: "your-key"
  openai-api-key: "your-key"
  openrouter-api-key: "your-key"
```

**Mode 2: BYOM (Per-request key)**
```json
{"appName": "my-app", "provider": "gemini", "apiKey": "user-key"}
```

### Key Lookup Order
1. Request body `apiKey` → BYOM mode
2. K8s Secret `argocd-agent-llm-keys` → Org-wide config
3. `ollama` provider → No key needed
4. Error if no key available

### Security Features
- Secret access restricted to `argocd-agent-go` ServiceAccount
- Python pod has NO K8s RBAC permissions
- Secret kind explicitly blocked in `get_resource` tool
- Keys never logged

---

## 9. Project Structure

```
argocd-agent/
│
│  ── Go Service (K8s + API) ──
├── cmd/server/main.go              # Go HTTP server entrypoint
├── internal/
│   ├── api/handler.go              # External API + signal collection + SSE proxy
│   ├── k8s/handler.go              # Internal K8s data endpoints
│   ├── health/health.go            # Liveness/readiness checks
│   ├── metrics/metrics.go          # Prometheus metrics
│   └── secrets/secrets.go          # K8s secret management
│
│  ── Python Agent Service ──
├── agent/
│   ├── main.py                     # FastAPI server (:8081)
│   ├── engine.py                   # Router, agents, cache, log filter, diagnosis runner
│   ├── metrics.py                  # Prometheus metrics
│   ├── agents/
│   │   ├── base.py                 # AgentCard and AgentSkill dataclasses
│   │   ├── router.py               # AgentCardRouter (heuristic routing)
│   │   ├── runtime_agent.py        # Runtime Analyzer
│   │   ├── config_agent.py         # Config Analyzer
│   │   ├── network_agent.py        # Network Analyzer
│   │   ├── storage_agent.py        # Storage Analyzer
│   │   └── rbac_agent.py           # RBAC Analyzer
│   ├── tools/
│   │   ├── k8s_tools.py            # K8s FunctionTools (7 tools)
│   │   └── rag_tools.py            # RAG search tool
│   ├── rag/
│   │   ├── retriever.py            # FAISS index loader + search
│   │   └── chunker.py              # Document chunker
│   └── tests/                      # Unit tests
│
│  ── Console Plugin (ArgoAI UI) ──
├── console-plugin/
│   ├── package.json                # Plugin metadata + dependencies
│   ├── console-extensions.json     # Nav item + page route
│   ├── plugin-metadata.ts          # Webpack module federation config
│   ├── webpack.config.ts           # Build config
│   ├── start-console.sh            # Local dev console runner
│   └── src/
│       ├── components/
│       │   ├── ArgoAgentPage.tsx    # Main page with app list
│       │   ├── DiagnosisPanel.tsx   # SSE streaming display
│       │   └── DiagnosisResult.tsx  # Structured diagnosis output
│       └── utils/
│           └── api.ts              # SSE client
│
│  ── Kubernetes Deployment ──
├── config/
│   ├── deploy/                     # Kustomize manifests
│   └── monitoring/                 # Grafana dashboard
│
│  ── Demo Scenarios ──
├── demo/                           # 7 failure scenarios for testing
│
│  ── Docker ──
├── Dockerfile.server               # Go service image
├── Dockerfile.agent                # Python service image
├── docker-compose.yml
├── Makefile
│
│  ── Documentation ──
├── AGENTS.md                       # Instructions for AI coding agents
├── PROJECT_CONTEXT.md              # This file
└── docs/
    └── OBSERVABILITY.md            # Metrics and monitoring guide
```

---

## 10. Running the POC

### Prerequisites

1. Docker installed
2. Access to a K8s/OpenShift cluster with ArgoCD
3. An LLM API key (Gemini, OpenAI, Anthropic, or Groq)

### Quick Start (Local)

```bash
# 1. Extract RAG data from the pre-built Quay image (one-time)
make extract-rag

# 2. Start Go service (Terminal 1)
make run-go

# 3. Start Python service (Terminal 2)
TRANSFORMERS_CACHE=/tmp/hf_cache RAG_INDEX_PATH=./rag_data/vector_db uv run python -m agent.main

# 4. Test diagnosis (BYOM mode)
curl -X POST http://localhost:8080/api/v1/diagnose \
  -H "Content-Type: application/json" \
  -d '{
    "appName": "my-broken-app",
    "appNamespace": "openshift-gitops",
    "provider": "gemini",
    "apiKey": "YOUR_GEMINI_API_KEY"
  }'
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GO_SERVICE_URL` | `http://localhost:8080` | Go service URL for Python service |
| `RAG_INDEX_PATH` | `/rag/vector_db` | Path to FAISS index |
| `ENABLE_RAG` | `true` | Enable/disable RAG tool |
| `DIAGNOSIS_TIMEOUT_SECONDS` | `90` | Max seconds for LLM diagnosis |
| `MAX_TOOL_CALLS` | `3` | Per-diagnosis tool-call budget, capped at 5 |
| `MAX_TOOL_RESPONSE_CHARS` | `1200` | Max chars returned from one tool result to the LLM |
| `LLM_MAX_OUTPUT_TOKENS` | `1024` | Max model output tokens per LLM round |
| `LLM_TEMPERATURE` | `0.2` | Model temperature for diagnosis runs |
| `GEMINI_THINKING_BUDGET` | `0` | Gemini 2.5 thinking budget; default off to preserve visible JSON output |
| `TRANSFORMERS_CACHE` | `/.cache` | HuggingFace model cache |

---

## 11. Test Scenarios

| # | Scenario | Root Cause | Expected Agent |
|---|----------|------------|----------------|
| 1 | OOMKilled | Memory limit too low | Runtime Analyzer |
| 2 | ImagePullBackOff | Wrong image tag | Runtime Analyzer |
| 3 | CrashLoopBackOff | Missing env var / app error | Runtime Analyzer |
| 4 | Missing ConfigMap | ConfigMap doesn't exist | Runtime Analyzer |
| 5 | OutOfSync | Git manifest changed | Config Analyzer |
| 6 | PVC Pending | StorageClass not found | Storage Analyzer |
| 7 | Probe failure | Container not listening | Network Analyzer |

Demo manifests in `demo/` directory.

---

## 12. Key Design Decisions

1. **All diagnosis goes through LLM** -- No deterministic/offline fallback. The project is an AI agent.
2. **Two-service split (Go + Python)** -- Security isolation + best-of-both-worlds.
3. **A2A-based routing** -- Agents expose capabilities via AgentCards; router uses heuristics.
4. **Shared RAG with Lightspeed** -- Same FAISS index, no duplicate infrastructure.
5. **Secure API keys** -- K8s Secrets preferred, BYOM as fallback.
6. **Semantic caching** -- Avoid redundant LLM calls for same issue type.
7. **Log filtering** -- Pre-process to extract errors, avoid context window bloat.
8. **App-scoped signals** -- Events and pods filtered to the target ArgoCD app's resources.
9. **Tool-call limits** -- ADK callbacks block expensive tool execution once the budget is exhausted (default 3, hard cap 5); oversized tool results are truncated before the next model round.
10. **JSON response mode** -- Gemini uses `response_mime_type: application/json` only for no-tool runs because Gemini rejects JSON MIME mode with function calling.
11. **Anti-hallucination prompts** -- Tool whitelist, evidence requirement, explicit "say you don't know" rules.
12. **Read-only POC** -- No remediation, only diagnosis and suggestions.
