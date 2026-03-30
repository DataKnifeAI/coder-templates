---
display_name: Kubernetes (Arch, Cursor)
description: Kubernetes workspace on Arch Linux with Cursor IDE & CLI
icon: ../../../site/static/icon/k8s.png
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor]
---

# Remote Development on Kubernetes (Arch Linux)

Same layout as **dkai-dev** (CPU/memory/disk parameters, Cursor module, persistent `/home/coder`), but the workload uses the official **[`archlinux`](https://hub.docker.com/_/archlinux)** image and **pacman** for tooling (`nodejs`, `github-cli` (`gh`), `glab`).

## Container user

The stock Arch image has no preconfigured workspace user. The pod runs as **root** so the startup script can run `pacman`, then creates **`coder` (UID 1000)** with passwordless `sudo` and `chown`s `/home/coder` for NFS-friendly ownership. The Coder agent and Cursor CLI run as **`coder`**.

First start may take longer while packages sync and install.

## Prerequisites

- **Cluster**: Existing Kubernetes namespace (same as other templates).
- **Authentication**: Same as `dkai-dev` / `kubernetes` (`~/.kube/config` or in-cluster ServiceAccount).

## Architecture

- Kubernetes Deployment (ephemeral pod)
- PVC (persistent data under `/home/coder`)

Tools outside `/home/coder` are reset on rebuild unless baked into a custom image.
