---
display_name: DKAI Hermes
description: Hermes Agent controller on Kubernetes — remote Enodios vLLM at vllm.dataknife.net
icon: /icon/k8s.svg
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, hermes, enodios, vllm, remote-llm]
---

# DKAI Hermes

**Hermes Agent controller** on Kubernetes, wired to **remote [Enodios](https://github.com/DataKnifeAI/enodios) vLLM** at **`https://vllm.dataknife.net/v1`**.

**Enodios does not run in this workspace.** Enodios is the remote inference stack (vLLM on GPU / DataKnife-hosted). This pod installs **Hermes only** and connects outbound over HTTPS. No `enodios install`, no local vLLM, no GPU required in the workspace.

```
You ──► Hermes Agent (this Coder workspace — tools, files, terminal)
              │
              │  OpenAI-compatible API
              ▼
         Remote Enodios vLLM (vllm.dataknife.net — outside workspace)
```

## What runs where

| Component | Location | In workspace? |
|-----------|----------|---------------|
| **Enodios / vLLM** | GPU host or `vllm.dataknife.net` | **No** |
| **Hermes Agent** | Coder workspace pod | **Yes** |
| **Your code** | Optional git clone under `/home/coder/<repo>/` | **Yes** |

## What you get

- **`hermes` CLI** — agent with tools; config on tool PVC at `~/.hermes`.
- **Remote vLLM parameters** — Hermes `custom_providers` block (Enodios layout) rewritten each start:
  - **`vllm_base_url`** — default `https://vllm.dataknife.net/v1`
  - **`vllm_model`** — default `hermes3:8b`
  - **`vllm_api_key`** — optional, for authenticated endpoints
- **`hermes_worker_git_url`** — optional project repo (default `agent-workspace`); not Enodios itself.
- **`start-hermes-chat`** — `hermes chat` from cloned repo or `/home/coder`.
- **Startup probe** — `GET <base-url>/models` reachability check.

## Quick start

1. Ensure remote Enodios vLLM is up at `vllm.dataknife.net` (or your `vllm_base_url`).
2. Create workspace; confirm startup shows **vLLM reachability: ok**.
3. Chat:

   ```bash
   start-hermes-chat
   ```

## Parameters

| Parameter | Default | Notes |
|-----------|---------|-------|
| `vllm_base_url` | `https://vllm.dataknife.net/v1` | Remote Enodios endpoint (reachable from pods) |
| `vllm_model` | `hermes3:8b` | Must match remote `/v1/models` |
| `vllm_api_key` | (empty) | If remote vLLM requires auth |
| `hermes_worker_git_url` | `agent-workspace` repo | Your project code — not Enodios |

## Operating Enodios (remote)

Enodios is managed on the inference side. See **[Enodios docs](https://dataknifeai.github.io/enodios/)** for GPU host setup (`enodios install`, `enodios start --lan`, etc.). Controllers (this template) only need Hermes pointed at the remote URL.

## Relationship to DKAI Agent

Same Kubernetes layout and CLI tooling (`gh`, `glab`, `kubectl`, `rancher`). Replaces Cursor Cloud Agent with **Hermes → remote Enodios vLLM**.

Git / `gh` / `glab` shared paths: **[DKAI Agent README](../dkai-agent/README.md#git-gh--glab-and-home)**.

## Debugging

```bash
coder ssh <workspace> -- sh -c 'cat /mnt/coder-tool-config/hermes/config.yaml'
coder ssh <workspace> -- sh -c 'curl -fsS "https://vllm.dataknife.net/v1/models" | head -c 500'
```

## Related

- [Enodios](https://github.com/DataKnifeAI/enodios) · [Docs](https://dataknifeai.github.io/enodios/) (remote inference stack)
- [Hermes Agent](https://hermes-agent.nousresearch.com/)
