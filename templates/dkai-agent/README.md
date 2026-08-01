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
- **Dev toolchains** — same **pacman** language stack as **DKAI Arch** (Node.js, pnpm, Python, uv, Go, Rust, Java/Maven/Gradle, Ruby, PHP, .NET, gcc). See [docs/build-parameters.md](../../docs/build-parameters.md#preinstalled-dev-toolchains).
- **`kubectl`** from Arch **`extra/kubectl`** via the initial **`pacman`** install (`/usr/bin/kubectl`). **`kubectx`** and **`kubens`** from Arch **`extra/kubectx`** (same install; context / namespace helpers). **`rancher`** CLI is downloaded from GitHub releases to `/usr/local/bin` when missing.
- **`terraform`** installed to **`/usr/local/bin/terraform`** from [HashiCorp releases](https://releases.hashicorp.com/terraform/) (pinned version in startup script; upgraded when the pin changes). Uses **`unzip`** from **`pacman`** for the official Linux amd64 zip.
- **Tool config volume** — one **ReadWriteMany** PVC per **Coder user** at **`/mnt/coder-tool-config`** named **`coder-<owner-id>-tool-config`**. At **plan** time the template checks the cluster (in-cluster API or `kubectl`); if the PVC is missing Terraform **creates** it; if it already exists (another workspace or a prior apply), Terraform **imports** it into this workspace’s state so updates never **destroy** the claim. The PVC resource uses **`lifecycle { prevent_destroy = true }`** so Terraform will not delete it on workspace teardown (shared across your dkai-agent workspaces; remove from state manually if you must drop the claim). **`tool_config_disk_size`** sizes that shared volume. On each boot the startup script **`mkdir`**s layout there, **merges** legacy **`/home/coder`** paths into the PVC (including **`glab-cli`**), then **`ln -sfn`** the same paths for **both** **`/root`** and **`/home/coder`**: **`~/.kube`**, **`~/.config/gh`**, **`~/.config/glab-cli`**, **`~/.config/coderv2`**, **`~/.rancher`**. **Coder CLI** uses **`~/.config/coderv2`** (same as **`coder --global-config`** / default **`$CODER_CONFIG_DIR`**). The PVC dirs are **`chown`’d `coder:coder`** each boot so **`gh`**, **`glab`**, **`kubectl`**, **`coder`**, and **`rancher`** see the same files whether you use **`HOME=/home/coder`** or **`HOME=/root`** (root still reads/writes everything).
- **Workspace parameter `cursor_api_key`** (optional, masked in the UI): when set, Coder injects **`CURSOR_API_KEY`** into the workspace via `coder_env`. Use the API key from **Cursor Dashboard → Settings → Cursor Settings → API Keys** for the user who owns usage. Leave empty and export it yourself if you prefer not to store the key on the workspace.
- **`start-cursor-worker`** in `~/bin` and `/usr/local/bin`: runs `agent worker start` (without `--pool`) with your workspace’s **idle-release timeout** (build parameter `cursor_worker_idle_timeout`, default 600 seconds). Honors:
  - **`CURSOR_API_KEY`** — from the parameter above, or a manual `export`.
  - **`CURSOR_WORKER_DIR`** — git repo root for the worker (default `/home/coder/agent-workspace` when the template clones `cursor_worker_git_url`).
  - **`CURSOR_WORKER_LABELS_FILE`** — optional JSON/TOML labels for the worker.
  - **`CURSOR_WORKER_MANAGEMENT_ADDR`** — e.g. `:8080` for `/metrics`, `/healthz`, `/readyz` on the worker.
- **Example labels file**: `~/.cursor-worker-labels.json.example` (copy and customize).

Workers only need **outbound HTTPS**; no inbound ports are required.

## Coder CLI config

The **`coder`** binary stores global config under **`~/.config/coderv2`** (or **`$CODER_CONFIG_DIR`** if set). The tool PVC symlink **`/home/coder/.config/coderv2`** → **`/mnt/coder-tool-config/config/coderv2`**, so sessions and **`coder login`** persist like other tools. **`coder --global-config`** points at the same tree.

## Git, `gh` / `glab`, and `HOME`

**Why this matters:** Coder may set **`GIT_ASKPASS`** (and sometimes **`GIT_SSH_COMMAND`**) for Git. **`gh`** and **`glab`** store OAuth tokens under **`$HOME/.config/...`**. Cursor agents and some automation run with **`HOME=/home/coder`**, while operators often open an interactive **root** shell where **`HOME=/root`**. Without a shared config path, **`gh auth status`** can show “not logged in” in the agent while the same pod looks logged in as root, and **`git push`** over HTTPS to GitHub can fail with *could not read Username* / *No anonymous write access* even when **`gh`** is logged in.

**What this template does:**

- Symlinks **`~/.config/gh`**, **`~/.config/glab-cli`**, plus **`~/.kube`**, **`~/.config/coderv2`**, **`~/.rancher`** for **both** **`coder`** and **`root`** to the tool PVC. Dirs are owned **`coder:coder`** so tokens are not stuck as **`root`-only** (if **`glab auth status`** was empty as **`coder`** before, re-run **`glab auth login`** once after upgrading the template, or rely on the next workspace start after **`chown`**).
- Sets **`GIT_ASKPASS=true`** in **`/etc/profile.d/dkai-git-askpass.sh`** and appends it to **`/home/coder/.bashrc`** / **`.profile`** so Coder’s askpass does not block **`gh`** / **`glab`** credential helpers.
- Configures Git (for **root** and **`coder`**) with URL-scoped helpers: **`credential.https://github.com.helper`** → **`gh auth git-credential`**, **`credential.https://gitlab.com.helper`** → **`glab auth git-credential`**.

**Self‑hosted GitLab:** add another **`credential.<url>.helper`** for your host if needed.

**SSH remotes:** If **`GIT_SSH_COMMAND`** or Coder’s Git integration interferes with HTTPS, prefer **`git@github.com:org/repo.git`** when SSH keys are available in the workspace (avoids HTTPS + askpass entirely).

**Manual one‑off (any template without these defaults):** align **`HOME`** with where you ran **`gh auth login`**, or run:

`HOME=/root GIT_ASKPASS=true git -c credential.helper='!/usr/local/bin/gh auth git-credential' <git-subcommand>`

(adjust the **`gh`** path if installed elsewhere).

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

Same Kubernetes layout (Deployment + **two** PVCs on `truenas-csi-nfs`, pod anti-affinity) and startup behavior (pacman, `gh`/`glab`, `kubectl`, `rancher`, `terraform`, Cursor sandbox `.deb` extract, `coder` CLI). Unlike **DKAI Arch**, this template does **not** include the `coder/cursor` registry module (no **Open in Cursor Desktop** app in Coder). Adds worker parameters, `coder_env` + end-of-startup autostart when **`cursor_api_key`** is set, `start-cursor-worker`, and related docs.

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

**`kubectx`** / **`kubens`** are installed for interactive context and namespace switching (same `kubeconfig` as **`kubectl`**, including symlinks under **`/root/.kube`** on the tool PVC).

## Related

- [Cursor CLI / Cloud Agent](https://cursor.com/docs/cli/overview)
