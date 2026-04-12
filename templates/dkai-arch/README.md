---
display_name: DKAI Arch
description: Arch Linux Kubernetes workspace with Cursor IDE & CLI
icon: /icon/k8s.png
maintainer_github: coder
verified: false
tags: [kubernetes, container, archlinux, cursor]
---

# DKAI Arch

Same layout as **DKAI Dev** (`dkai-dev`) (CPU/memory/disk parameters, Cursor module, persistent `/home/coder`), but the workload uses the official **[`archlinux`](https://hub.docker.com/_/archlinux)** image and **pacman** for tooling (`apparmor`, `binutils` for `ar`, `zstd`, `nodejs`, `github-cli` (`gh`), `glab`). Cursor’s **`cursor-sandbox-apparmor`** `.deb` is unpacked with `ar` + `zstd` (not `dpkg`, which mishandles this package on Arch), then **`apparmor_parser -r`** is run so the profile loads even without systemd’s `apparmor.service` (the `.deb` postinst normally skips that in containers).

The Cursor module opens **`/home/coder/git`** (i.e. `~/git` for the `coder` user). That directory is created at startup if missing.

## Container user

The stock Arch image has no preconfigured workspace user. The pod runs as **root** so the startup script can run `pacman`, then creates **`coder` (UID 1000)** with passwordless `sudo` and `chown`s `/home/coder` for NFS-friendly ownership. The Coder agent and Cursor CLI run as **`coder`**.

First start may take longer while packages sync and install.

## Prerequisites

- **Cluster**: Existing Kubernetes namespace (same as other templates).
- **Authentication**: Same as **DKAI Dev** (`dkai-dev`) / `kubernetes` (`~/.kube/config` or in-cluster ServiceAccount).

## Architecture

- Kubernetes Deployment (ephemeral pod)
- PVC (persistent data under `/home/coder`)

Tools outside `/home/coder` are reset on rebuild unless baked into a custom image.

## Cursor Agent terminal sandbox / AppArmor

The script installs [Cursor’s `cursor-sandbox-apparmor` `.deb`](https://cursor.com/docs/agent/terminal) by extracting `data.tar.zst` to `/etc` (profile `cursor-sandbox-remote`, sysctl snippet for user namespaces), then runs **`apparmor_parser -r`** and **`sysctl -p`** when those paths exist. That matches what the Debian `postinst` would do only if **`systemctl is-active apparmor`**—which is usually false in containers—so Arch previously never loaded the profile.

The **node** must still enforce AppArmor and user namespaces as your CRI allows; some clusters cannot apply new sysctl or profiles inside pods.
