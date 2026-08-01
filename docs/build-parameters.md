# Build Parameters

Templates prompt users for additional information when creating workspaces using **parameters**. Parameters let developers specify properties like CPU, memory, disk size, region, and more.

## Reference

For full documentation on Coder build parameters, see:

**[Build Parameters | Coder Docs](https://coder.com/docs/admin/templates/extending-templates/parameters)**

Topics covered include:

- **Types** — `string`, `bool`, `number`, `list(string)`
- **Options** — Limiting choices for string parameters
- **Required vs optional** — Using `default` for optional parameters
- **Mutability** — When users can change parameter values after creation
- **Ephemeral parameters** — Parameters only used at start/update/restart
- **Validation** — `min`/`max`, `monotonic` (increasing/decreasing), `regex`
- **Workspace presets** — Pre-configured parameter combinations

## Template Parameters

| Template   | Parameters                                                                 |
|-----------|----------------------------------------------------------------------------|
| DKAI DevPod (`dkai-dev`) | CPU (2/4 cores), Memory (4/8 GB), Home disk size (50–100 GB, monotonic ↑). Cursor IDE only (no subdomain). Startup installs Node.js, **Rust** (`rustc`/`cargo` via apt), `gh`, `glab`. |
| DKAI Arch (`dkai-arch`) | Same parameters as **DKAI DevPod** (`dkai-dev`). Arch Linux base image; Cursor IDE only (no subdomain). Startup installs **Rust** (`rust`/`gcc` via pacman) with Node.js, `gh`, `glab`. |
| DKAI Agent (`dkai-agent`) | Same CPU/memory/home disk as DKAI Arch, plus **tool_config_disk_size** (default 5 GiB, 1–50 GiB) for the shared **ReadWriteMany** tool-config PVC at `/mnt/coder-tool-config` (one per Coder owner: `coder-<owner-id>-tool-config`; plan-time cluster check creates if missing else attaches). **cursor_worker_idle_timeout** (30–86400 s, default 600) for `agent worker start --idle-release-timeout`; optional **cursor_api_key** (masked; `CURSOR_API_KEY` via `coder_env`). Includes **Rust** (`rustc`/`cargo` via pacman). |
| DKAI Hermes (`dkai-hermes`) | Same as **DKAI Agent** (tool PVC, gh/glab/kubectl/rancher, **Rust**), but **Hermes Agent controller only** — **[Enodios](https://github.com/DataKnifeAI/enodios) vLLM runs remotely** (not in workspace). Hermes config points at **vllm_base_url** (default `https://vllm.dataknife.net/v1`), **vllm_model** (`hermes3:8b`), optional **vllm_api_key**; optional **hermes_worker_git_url** for project code. |
| kubernetes| See [templates/kubernetes/README.md](../templates/kubernetes/README.md)   |

## Preinstalled dev toolchains

DKAI templates install popular language toolchains in the **`startup_script`** (not user-selectable build parameters). Versions follow the distro package manager (Arch **pacman** or Ubuntu **apt**) unless noted.

| Toolchain | DKAI DevPod (`dkai-dev`) | DKAI Arch / Agent / Hermes |
|-----------|--------------------------|----------------------------|
| **Node.js** | NodeSource 20.x if base image &lt; 20 | `nodejs` (pacman) |
| **pnpm** | `npm install -g pnpm` | `pnpm` (pacman) |
| **Python** | `python3`, `pip`, `venv` (apt) | `python` (pacman) |
| **uv** | [Astral install script](https://docs.astral.sh/uv/) → `/usr/local/bin` | `uv` (pacman) |
| **Go** | `golang-go` (apt) | `go` (pacman) |
| **Rust** | `rustc`, `cargo`, `build-essential` (apt) | `rust`, `gcc` (pacman) |
| **Java** | OpenJDK (`default-jdk`), Maven, Gradle (apt) | `jdk-openjdk`, `maven`, `gradle` (pacman) |
| **Ruby** | `ruby-full` (apt) | `ruby` (pacman) |
| **PHP** | `php-cli`, `php` (apt) | `php` (pacman) |
| **.NET** | `dotnet-sdk-8.0` (Microsoft apt feed) | `dotnet-sdk` (pacman) |
| **C/C++** | `build-essential` (`gcc`, etc.) | `gcc` (pacman) |

The **`kubernetes`** template installs **code-server** only; add languages via a custom container image or dotfiles (see [templates/kubernetes/README.md](../templates/kubernetes/README.md)).

Startup logs print a **=== Startup summary ===** block with detected versions for each toolchain.
