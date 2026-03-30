---
display_name: Kubernetes (Arch, Cursor)
description: Kubernetes workspace on Arch Linux with Cursor IDE & CLI
icon: /icon/k8s.png
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor]
---

# Remote Development on Kubernetes (Arch Linux)

Same layout as **dkai-dev** (CPU/memory/disk parameters, Cursor module, persistent `/home/coder`), but the workload uses the official **[`archlinux`](https://hub.docker.com/_/archlinux)** image and **pacman** for tooling (`apparmor`, `dpkg`, `nodejs`, `github-cli` (`gh`), `glab`), plus Cursor’s **`cursor-sandbox-apparmor`** `.deb` for the Agent terminal sandbox.

The Cursor module opens **`/home/coder/git`** (i.e. `~/git` for the `coder` user). That directory is created at startup if missing.

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

## Cursor Agent terminal sandbox / AppArmor

The startup script installs **`apparmor`**, **`dpkg`** (to install the official Debian package on Arch), and Cursor’s **`cursor-sandbox-apparmor`** package from [Cursor’s docs](https://cursor.com/docs/agent/terminal) (same `.deb` as Debian/Ubuntu). That supplies the AppArmor profile needed for the Agent terminal sandbox on kernel 6.2+ when plain `apparmor` is not enough.

The **Kubernetes node** must still allow unprivileged user namespaces and AppArmor where your runtime applies them; container seccomp or missing `apparmor_parser` on the host can still block the sandbox. If problems remain, use Cursor’s sandbox settings or your cluster’s security profile.
