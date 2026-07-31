---
display_name: DKAI DevPod
description: Cursor IDE on Kubernetes — Ubuntu base, 2/4 CPU, 4/8 GB RAM, persistent home
icon: /icon/k8s.svg
maintainer_github: coder
verified: true
tags: [kubernetes, container]
---

# DKAI DevPod

Kubernetes [Coder workspaces](https://coder.com/docs/workspaces) with Cursor Desktop integration (`coder/cursor` module) and an Ubuntu-based dev container.

**Startup installs** (idempotent): Node.js 20+, **pnpm**, **Python** (pip/venv) + **uv**, **Go**, **Rust**, **Java** (OpenJDK, Maven, Gradle), **Ruby**, **PHP**, **.NET SDK 8**, **C/C++** (`build-essential`), plus **gh**, **glab**, Cursor sandbox AppArmor, and Coder/Cursor CLI. See [docs/build-parameters.md](../../docs/build-parameters.md#preinstalled-dev-toolchains).

<!-- TODO: Add screenshot -->

## Prerequisites

### Infrastructure

**Cluster**: This template requires an existing Kubernetes cluster

**Container Image**: This template uses the [codercom/enterprise-base:ubuntu image](https://github.com/coder/enterprise-images/tree/main/images/base) with some dev tools preinstalled. To add additional tools, extend this image or build it yourself.

### Authentication

This template authenticates using a `~/.kube/config`, if present on the server, or via built-in authentication if the Coder provisioner is running on Kubernetes with an authorized ServiceAccount. To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Architecture

This template provisions the following resources:

- Kubernetes pod (ephemeral)
- Kubernetes persistent volume claim (persistent on `/home/coder`)

This means, when the workspace restarts, any tools or files outside of the home directory are not persisted. To pre-bake tools into the workspace (e.g. `python3`), modify the container image. Alternatively, individual developers can [personalize](https://coder.com/docs/dotfiles) their workspaces with dotfiles.

### Cursor Agent terminal sandbox

The startup script installs Cursor’s **`cursor-sandbox-apparmor`** package (see [Terminal / Sandbox](https://cursor.com/docs/agent/terminal)) and then runs **`apparmor_parser -r`** on `cursor-sandbox-remote` so the profile loads in containers where the package `postinst` skips loading (no active `apparmor.service`). The cluster node must still permit user namespaces and AppArmor as required by your runtime.

### Git, `gh` / `glab`, and Coder

Same defaults as **DKAI Arch**: **`GIT_ASKPASS=true`**, Git credential helpers for **github.com** / **gitlab.com** via **`gh`** / **`glab`**, and **`safe.directory *`**. Details: **[DKAI Agent — Git, gh / glab, and HOME](../dkai-agent/README.md#git-gh--glab-and-home)**.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
