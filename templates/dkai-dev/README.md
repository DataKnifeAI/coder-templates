---
display_name: Kubernetes (Deployment)
description: Provision Kubernetes Deployments as Coder workspaces
icon: /icon/k8s.png
maintainer_github: coder
verified: true
tags: [kubernetes, container]
---

# Remote Development on Kubernetes Pods

Provision Kubernetes Pods as [Coder workspaces](https://coder.com/docs/workspaces) with this example template.

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

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
