# Coder Templates

Custom [Coder](https://coder.com) workspace templates for DataKnife. Templates are written in Terraform and define the underlying infrastructure that Coder workspaces run on.

## Overview

This repository contains reusable Coder templates for provisioning development workspaces. Use these as starting points or import them directly into your Coder deployment.

## References

- **[Coder Registry](https://registry.coder.com)** — Explore official and community templates
- **[Kubernetes Template](https://registry.coder.com/templates/coder/kubernetes)** — Official Kubernetes (Deployment) template by Coder
- **[Coder Templates Docs](https://coder.com/docs/templates)** — Learn how to create and extend templates

## Getting Started

### Prerequisites

- [Coder](https://coder.com) deployment
- [Terraform](https://developer.hashicorp.com/terraform/intro) familiarity
- Access to your target infrastructure (Kubernetes, AWS, Docker, etc.)

### Using Templates

1. **From Coder UI**: Create a template → Import from registry or Git
2. **From CLI**: `coder templates create <name> --directory ./path/to/template`
3. **From Terraform**: Reference this repo as a module or copy the template files

### Key Concepts

- **Templates** = Terraform configs that provision workspace infrastructure
- **Parameters** = User-configurable options (CPU, memory, disk, etc.)
- **Resources** = The actual infrastructure (pods, VMs, volumes)

## Template Structure

```
coder-templates/
├── README.md
└── templates/
    └── <template-name>/
        ├── main.tf      # Terraform configuration
        ├── variables.tf  # Input variables
        └── README.md    # Template-specific docs
```

## Extending Templates

Common customizations:

- **Images** — Use custom Docker images with preinstalled tools
- **Parameters** — Add disk size, instance type, region options
- **IDEs** — Add JetBrains, RDP, or other IDE support
- **Persistence** — Configure volume mounts and backup behavior

See [Coder's extending templates guide](https://coder.com/docs/admin/templates/extending-templates) for details.

## CI/CD

GitHub Actions runs on every push and pull request:

- **Test** — `terraform init`, `terraform validate`, and `terraform fmt -check` for each template
- **Push to GitLab** — After tests pass on `main`, syncs to a GitLab mirror (optional)

### GitLab Mirror Setup

To enable pushing to GitLab after tests pass, add these repository secrets:

| Secret | Description |
|-------|-------------|
| `GITLAB_REPO_SSH_URL` | SSH URL (e.g. `git@gitlab.com:org/coder-templates.git`) |
| `GITLAB_SSH_KEY` | Private SSH key with write access to the GitLab repo |

Create a [GitLab Deploy Key](https://docs.gitlab.com/ee/user/project/deploy_keys/) or use a [Personal Access Token](https://docs.gitlab.com/ee/user/profile/personal_access_tokens/) with `write_repository` scope (as SSH key).

## Links

- [Coder Documentation](https://coder.com/docs)
- [Coder Registry](https://registry.coder.com)
- [Coder on GitHub](https://github.com/coder/coder)
