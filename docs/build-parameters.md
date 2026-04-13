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
| DKAI Agent (`dkai-agent`) | Same CPU/memory/home disk as DKAI Arch, plus **cli_config_disk_size** (1–50 GiB, default 5, monotonic ↑) for a second PVC at `/mnt/coder-cli-config` (kubectl/gh/glab/rancher configs via symlinks); **cursor_worker_idle_timeout** (30–86400 s, default 600) for `start-cursor-worker`; optional **cursor_api_key** (masked; sets `CURSOR_API_KEY`). |
| kubernetes| See [templates/kubernetes/README.md](../templates/kubernetes/README.md)   |
