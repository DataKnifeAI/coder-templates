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
| DKAI Dev (`dkai-dev`) | CPU (2/4 cores), Memory (4/8 GB), Home disk size (50–100 GB, monotonic ↑). Cursor IDE only (no subdomain). |
| DKAI Arch (`dkai-arch`) | Same parameters as **DKAI Dev** (`dkai-dev`). Arch Linux base image; Cursor IDE only (no subdomain). |
| DKAI Agent (`dkai-agent`) | Same as DKAI Arch, plus **cursor_pool_idle_timeout** (30–86400 s, default 600) for `agent worker start --pool` via `start-cursor-pool-worker`, and optional **cursor_api_key** (masked string; sets `CURSOR_API_KEY` via `coder_env` when non-empty). |
| kubernetes| See [templates/kubernetes/README.md](../templates/kubernetes/README.md)   |
