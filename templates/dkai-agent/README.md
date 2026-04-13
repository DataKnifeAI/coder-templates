---
display_name: DKAI Agent
description: Cursor Cloud Agent worker on Kubernetes — Arch base, agent CLI, optional individual API key parameter
icon: /icon/k8s.svg
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor, cloud-agent]
---

# DKAI Agent

Fork of **DKAI Arch** (`dkai-arch`) with the same Arch Linux base, AppArmor sandbox bits, and persistent `/home/coder`, but **no Cursor Desktop button** in the Coder dashboard. This variant targets **[Cursor Cloud Agent](https://cursor.com/docs/cli/overview)** workers running in your cluster: the `agent` CLI connects outbound to Cursor using **your individual account API key** (not team pool mode — no `--pool`).

## What you get

- **`agent` CLI** installed under `/home/coder/.local/bin` (and on `PATH`), same as DKAI Arch.
- **`kubectl`** and **`rancher`** CLIs installed to `/usr/local/bin` on first boot (pinned by presence of the binary; delete the binary to force a reinstall on next start).
- **Second PVC** (`cli_config_disk_size`, default 5 GiB): mounted at **`/mnt/coder-cli-config`**. Startup symlinks **`~/.kube`**, **`~/.config/gh`**, **`~/.config/glab`**, and **`~/.rancher`** into that volume so credentials survive restarts independently of the home disk. Existing directories under home are copied into the volume once, then replaced by symlinks.
- **Workspace parameter `cursor_api_key`** (optional, masked in the UI): when set, Coder injects **`CURSOR_API_KEY`** into the workspace via `coder_env`. Use the API key from **Cursor Dashboard → Settings → Cursor Settings → API Keys** for the user who owns usage. Leave empty and export it yourself if you prefer not to store the key on the workspace.
- **`start-cursor-worker`** in `~/bin` and `/usr/local/bin`: runs `agent worker start` (without `--pool`) with your workspace’s **idle-release timeout** (build parameter `cursor_worker_idle_timeout`, default 600 seconds). Honors:
  - **`CURSOR_API_KEY`** — from the parameter above, or a manual `export`.
  - **`CURSOR_WORKER_DIR`** — git repo root for the worker (default `/home/coder/agent-workspace` when the template clones `cursor_worker_git_url`).
  - **`CURSOR_WORKER_LABELS_FILE`** — optional JSON/TOML labels for the worker.
  - **`CURSOR_WORKER_MANAGEMENT_ADDR`** — e.g. `:8080` for `/metrics`, `/healthz`, `/readyz` on the worker.
- **Example labels file**: `~/.cursor-worker-labels.json.example` (copy and customize).

Workers only need **outbound HTTPS**; no inbound ports are required.

## Quick start (inside the workspace)

1. Create an API key under **Cursor Settings → API Keys** (individual account; usage is billed to that account).
2. The template clones **`cursor_worker_git_url`** into `/home/coder/<repo-name>/` (default **`agent-workspace`**). Or set **`CURSOR_WORKER_DIR`** to another repo root.
3. Set workspace parameter **`cursor_api_key`** (recommended): after the workspace is up, the startup script starts the worker in the background (logs: **`/tmp/cursor-worker.log`**). Or leave it empty and configure manually:

   ```bash
   export CURSOR_API_KEY="your-api-key"
   start-cursor-worker
   ```

4. Optionally set `CURSOR_WORKER_LABELS_FILE` / `CURSOR_WORKER_MANAGEMENT_ADDR` before the worker starts (or restart the workspace after changing them).

The idle timeout is **`cursor_worker_idle_timeout`** (seconds).

## Relationship to DKAI Arch

Same Kubernetes layout (Deployment + **two** PVCs on `truenas-csi-nfs`, pod anti-affinity) and startup behavior (pacman, `gh`/`glab`, `kubectl`, `rancher`, Cursor sandbox `.deb` extract, `coder` CLI). Unlike **DKAI Arch**, this template does **not** include the `coder/cursor` registry module (no **Open in Cursor Desktop** app in Coder). Adds worker parameters, `coder_env` + end-of-startup autostart when **`cursor_api_key`** is set, `start-cursor-worker`, and related docs.

## Prerequisites

- **Cluster / namespace**: Same as other templates in this repo.
- **Cursor**: A user API key from the Cursor dashboard; this template does **not** use team self-hosted pool (`--pool`) or service-account-only flows.

## Debugging (Coder + kubectl)

**Coder “Started” only means the pod and `coder agent` are up.** The Cloud Agent worker is separate: it runs after the main install when **`cursor_api_key`** is set (logs: **`/tmp/cursor-worker.log`**).

**Stuck at startup / “agent startup script exited with an error”:** The template uses **`startup_script_behavior = "blocking"`** so the main install finishes before the worker autostart runs. Inspect failures with:

```bash
./scripts/coder-workspace-debug.sh <workspace-name>
# or: coder show <ws> && coder logs <ws> | tail -200
```

### `coder` CLI

```bash
coder login <your-coder-url>   # if needed
coder show <workspace-name>    # e.g. copper-penguin-94 — check agent is connected / healthy
coder ssh <workspace-name> -- sh -c 'pgrep -af "agent worker|./coder agent"; test -n "$CURSOR_API_KEY" && echo CURSOR_API_KEY=set || echo CURSOR_API_KEY=missing'
coder ssh <workspace-name> -- sh -c 'tail -100 /tmp/cursor-worker.log 2>&1'
```

If **`CURSOR_API_KEY`** is missing in that SSH session, set the **`cursor_api_key`** workspace parameter or `export` it and run **`start-cursor-worker`** manually from `/home/coder/agent-workspace` (or your **`CURSOR_WORKER_DIR`**).

### `kubectl` (correct context + namespace)

Workspace pods use labels such as `com.coder.workspace.name` and names `coder-<workspace-id>`. Replace **`<ns>`** with your template namespace (often `coder-workspaces`).

```bash
kubectl config use-context <cluster>
kubectl get pods -n <ns> -l com.coder.workspace.name=<workspace-name>
kubectl describe pod -n <ns> -l com.coder.workspace.name=<workspace-name>
kubectl logs -n <ns> -l com.coder.workspace.name=<workspace-name> -c dev --tail=200
```

Use **`kubectl logs`** for startup script output if the worker fails during boot.

## Related

- [Cursor CLI / Cloud Agent](https://cursor.com/docs/cli/overview)
