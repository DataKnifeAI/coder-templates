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
| DKAI DevPod (`dkai-dev`) | CPU (2/4 cores), Memory (4/8 GB), Home disk size (50–100 GB, monotonic ↑). Cursor IDE only (no subdomain). |
| DKAI Arch (`dkai-arch`) | Same parameters as **DKAI DevPod** (`dkai-dev`). Arch Linux base image; Cursor IDE only (no subdomain). |
| DKAI Agent (`dkai-agent`) | Same CPU/memory/home disk as DKAI Arch, plus **tool_config_volume_mode** (**dedicated** default vs **shared_pool**): **tool_config_disk_size** (default 5 GiB, 1–50 GiB) for the second PVC at `/mnt/coder-tool-config` — **dedicated** = one **ReadWriteOnce** PVC per workspace; **shared_pool** = one **ReadWriteMany** PVC per Coder **owner** (`coder-<owner-id>-tool-config`); **cursor_worker_idle_timeout** (30–86400 s, default 600) for `agent worker start --idle-release-timeout`; optional **cursor_api_key** (masked; `CURSOR_API_KEY` via `coder_env`). |
| kubernetes| See [templates/kubernetes/README.md](../templates/kubernetes/README.md)   |
