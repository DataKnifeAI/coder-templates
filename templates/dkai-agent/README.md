---
display_name: DKAI Agent
description: Cursor Cloud Agent self-hosted pool on Kubernetes — Arch worker, pool CLI, optional API key parameter
icon: /icon/k8s.svg
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor, cloud-agent]
---

# DKAI Agent

Fork of **DKAI Arch** (`dkai-arch`) with the same Arch Linux base, AppArmor sandbox bits, and persistent `/home/coder`, but **no Cursor Desktop button** in the Coder dashboard (agent/pool focus). Aimed at **[Self-Hosted Pool](https://cursor.com/docs/cloud-agent/self-hosted-pool)** workers: centrally managed machines that connect outbound to Cursor’s cloud and run tool calls in your environment.

## What you get

- **`agent` CLI** installed under `/home/coder/.local/bin` (and on `PATH`), same as DKAI Arch.
- **Workspace parameter `cursor_api_key`** (optional, masked in the UI): when set, Coder injects **`CURSOR_API_KEY`** into the workspace via `coder_env`. Leave empty and export it yourself if you prefer not to store the key on the workspace.
- **`start-cursor-pool-worker`** in `~/bin` and `/usr/local/bin`: runs `agent worker start --pool` with your workspace’s **idle-release timeout** (build parameter `cursor_pool_idle_timeout`, default 600 seconds). Honors:
  - **`CURSOR_API_KEY`** — from the parameter above, or a manual `export` ([service accounts](https://cursor.com/docs/account/enterprise/service-accounts)).
  - **`CURSOR_WORKER_DIR`** — git repo root for the worker (default `/home/coder/agent-workspace` when the template clones `cursor_worker_git_url`).
  - **`CURSOR_WORKER_LABELS_FILE`** — optional JSON/TOML labels ([labels](https://cursor.com/docs/cloud-agent/self-hosted-pool#labels)).
  - **`CURSOR_WORKER_MANAGEMENT_ADDR`** — e.g. `:8080` for `/metrics`, `/healthz`, `/readyz` on the worker.
- **Example labels file**: `~/.cursor-worker-labels.json.example` (copy and customize).

Workers only need **outbound HTTPS**; no inbound ports are required.

## Quick start (inside the workspace)

1. Enable **Allow Self-Hosted Agents** for your team and use a **service account** API key (see prerequisites in the [self-hosted pool docs](https://cursor.com/docs/cloud-agent/self-hosted-pool)).
2. The template clones **`cursor_worker_git_url`** into `/home/coder/<repo-name>/` (default **`agent-workspace`**). Or set **`CURSOR_WORKER_DIR`** to another repo root.
3. Set workspace parameter **`cursor_api_key`** (recommended): after the workspace is up, **`coder_script`** starts the pool worker in the background (logs: **`/tmp/cursor-pool-worker.log`**). Or leave it empty and configure manually:

   ```bash
   export CURSOR_API_KEY="your-service-account-api-key"
   start-cursor-pool-worker
   ```

4. Optionally set `CURSOR_WORKER_LABELS_FILE` / `CURSOR_WORKER_MANAGEMENT_ADDR` before the worker starts (or restart the workspace after changing them).

The idle timeout is **`cursor_pool_idle_timeout`** (seconds).

## Relationship to DKAI Arch

Same Kubernetes layout (Deployment + PVC, `truenas-csi-nfs`, pod anti-affinity) and startup behavior (pacman, `gh`/`glab`, Cursor sandbox `.deb` extract, `coder` CLI). Unlike **DKAI Arch**, this template does **not** include the `coder/cursor` registry module (no **Open in Cursor Desktop** app in Coder). Adds pool parameters, `coder_env` + **`coder_script`** to auto-start the pool worker when **`cursor_api_key`** is set, `start-cursor-pool-worker`, and related docs.

## Prerequisites

- **Cluster / namespace**: Same as other templates in this repo.
- **Cursor**: Team plan and admin-enabled self-hosted agents; see the official docs above.

## Debugging (Coder + kubectl)

**Coder “Started” only means the pod and `coder agent` are up.** A worker appears under **Cursor → Cloud Agents → Self-hosted** only after `agent worker start --pool` is running and connected. If workspace parameter **`cursor_api_key`** is set, a **`coder_script`** runs after the agent receives **`coder_env`** and **auto-starts** the pool worker (logs: **`/tmp/cursor-pool-worker.log`**, script log: **`/tmp/cursor-pool-autostart.log`**).

**Stuck at startup / “agent startup script exited with an error”:** The template uses **`startup_script_behavior = "blocking"`** so the main install finishes before **`coder_script`** runs (avoids the pool script timing out while `pacman` is still running). Inspect failures with:

```bash
./scripts/coder-workspace-debug.sh <workspace-name>
# or: coder show <ws> && coder logs <ws> | tail -200
```

### `coder` CLI

```bash
coder login <your-coder-url>   # if needed
coder show <workspace-name>    # e.g. copper-penguin-94 — check agent is connected / healthy
coder ssh <workspace-name> -- sh -c 'pgrep -af "agent worker|./coder agent"; test -n "$CURSOR_API_KEY" && echo CURSOR_API_KEY=set || echo CURSOR_API_KEY=missing'
coder ssh <workspace-name> -- sh -c 'tail -100 /tmp/cursor-pool-autostart.log /tmp/cursor-pool-worker.log 2>&1'
```

If **`CURSOR_API_KEY`** is missing in that SSH session, set the **`cursor_api_key`** workspace parameter or `export` it and run **`start-cursor-pool-worker`** manually from `/home/coder/agent-workspace` (or your **`CURSOR_WORKER_DIR`**).

### `kubectl` (correct context + namespace)

Workspace pods use labels such as `com.coder.workspace.name` and names `coder-<workspace-id>`. Replace **`<ns>`** with your template namespace (often `coder-workspaces`).

```bash
kubectl config use-context <cluster>
kubectl get pods -n <ns> -l com.coder.workspace.name=<workspace-name>
kubectl describe pod -n <ns> -l com.coder.workspace.name=<workspace-name>
kubectl logs -n <ns> -l com.coder.workspace.name=<workspace-name> -c dev --tail=200
```

Use **`kubectl logs`** for startup script output if the pool worker fails during boot.

## Related

- [Self-hosted pool](https://cursor.com/docs/cloud-agent/self-hosted-pool)
- [Kubernetes deployment (Helm / operator)](https://cursor.com/docs/cloud-agent/self-hosted-k8s)
- [Security & network](https://cursor.com/docs/cloud-agent/security-network)
