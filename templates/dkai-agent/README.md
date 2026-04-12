---
display_name: DKAI Agent
description: Cursor Cloud Agent self-hosted pool on Kubernetes — Arch worker, pool CLI, optional API key parameter
icon: /icon/k8s.svg
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor, cloud-agent]
---

# DKAI Agent

Fork of **DKAI Arch** (`dkai-arch`) with the same Arch Linux base, Cursor IDE module, AppArmor sandbox bits, and persistent `/home/coder`. This variant is aimed at **[Self-Hosted Pool](https://cursor.com/docs/cloud-agent/self-hosted-pool)** workers: centrally managed machines that connect outbound to Cursor’s cloud and run tool calls in your environment.

## What you get

- **`agent` CLI** installed under `/home/coder/.local/bin` (and on `PATH`), same as DKAI Arch.
- **Workspace parameter `cursor_api_key`** (optional, masked in the UI): when set, Coder injects **`CURSOR_API_KEY`** into the workspace via `coder_env`. Leave empty and export it yourself if you prefer not to store the key on the workspace.
- **`start-cursor-pool-worker`** in `~/bin` and `/usr/local/bin`: runs `agent worker start --pool` with your workspace’s **idle-release timeout** (build parameter `cursor_pool_idle_timeout`, default 600 seconds). Honors:
  - **`CURSOR_API_KEY`** — from the parameter above, or a manual `export` ([service accounts](https://cursor.com/docs/account/enterprise/service-accounts)).
  - **`CURSOR_WORKER_DIR`** — git repo root for the worker (default `/home/coder/git`).
  - **`CURSOR_WORKER_LABELS_FILE`** — optional JSON/TOML labels ([labels](https://cursor.com/docs/cloud-agent/self-hosted-pool#labels)).
  - **`CURSOR_WORKER_MANAGEMENT_ADDR`** — e.g. `:8080` for `/metrics`, `/healthz`, `/readyz` on the worker.
- **Example labels file**: `~/.cursor-worker-labels.json.example` (copy and customize).

Workers only need **outbound HTTPS**; no inbound ports are required.

## Quick start (inside the workspace)

1. Enable **Allow Self-Hosted Agents** for your team and use a **service account** API key (see prerequisites in the [self-hosted pool docs](https://cursor.com/docs/cloud-agent/self-hosted-pool)).
2. Clone the repository the worker should serve into `/home/coder/git` (or set `CURSOR_WORKER_DIR`).
3. As user **`coder`**, either set **`cursor_api_key`** on the workspace (recommended for convenience) or:

   ```bash
   export CURSOR_API_KEY="your-service-account-api-key"
   ```

4. Optionally: `export CURSOR_WORKER_LABELS_FILE=$HOME/.cursor-worker-labels.json`, then run **`start-cursor-pool-worker`**.

The idle timeout is configurable as **`cursor_pool_idle_timeout`** (seconds).

## Relationship to DKAI Arch

Same Kubernetes layout (Deployment + PVC, `truenas-csi-nfs`, pod anti-affinity) and startup behavior (pacman, `gh`/`glab`, Cursor sandbox `.deb` extract, `coder` CLI). This template adds pool parameters, optional `coder_env` for the API key, the helper script, and related docs.

## Prerequisites

- **Cluster / namespace**: Same as other templates in this repo.
- **Cursor**: Team plan and admin-enabled self-hosted agents; see the official docs above.

## Related

- [Self-hosted pool](https://cursor.com/docs/cloud-agent/self-hosted-pool)
- [Kubernetes deployment (Helm / operator)](https://cursor.com/docs/cloud-agent/self-hosted-k8s)
- [Security & network](https://cursor.com/docs/cloud-agent/security-network)
