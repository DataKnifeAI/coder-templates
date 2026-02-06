# Coder Templates

Custom [Coder](https://coder.com) workspace templates for DataKnife. Templates are written in Terraform and define the underlying infrastructure that Coder workspaces run on.

## Overview

This repository contains reusable Coder templates for provisioning development workspaces. Use these as starting points or import them directly into your Coder deployment.

## Templates

| Template      | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| **kubernetes** | Kubernetes Deployments with code-server — base template for K8s workspaces |
| **dkai-dev**   | Kubernetes workspaces with Cursor IDE & CLI — 2/4 CPU, 4/8 GB RAM, 50–100 GB disk (no subdomain required) |

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

### Local Validation

Validate templates locally before pushing:

```bash
make test
```

| Target      | Description                                      |
|-------------|--------------------------------------------------|
| `make test` | Init, validate, and format-check all templates   |
| `make fmt`  | Format Terraform files                           |
| `make clean`| Remove `.terraform` and lock files                |
| `make debug`| Run tests with verbose Terraform output (`V=1`)  |

### Key Concepts

- **Templates** = Terraform configs that provision workspace infrastructure
- **Parameters** = User-configurable options (CPU, memory, disk, etc.)
- **Resources** = The actual infrastructure (pods, VMs, volumes)

## Template Structure

```
coder-templates/
├── README.md
├── Makefile           # Local validation (make test)
├── docs/
│   └── build-parameters.md
└── templates/
    ├── kubernetes/
    │   ├── main.tf
    │   └── README.md
    └── dkai-dev/
        ├── main.tf
        └── README.md
```

## Extending Templates

Common customizations:

- **Images** — Use custom Docker images with preinstalled tools
- **Parameters** — Add disk size, instance type, region options
- **IDEs** — Add JetBrains, RDP, Cursor, or other IDE support
- **Persistence** — Configure volume mounts and backup behavior

See [Coder's extending templates guide](https://coder.com/docs/admin/templates/extending-templates) for details.

- **[Build Parameters](docs/build-parameters.md)** — Reference for template parameters (types, validation, mutability)
- **[Wildcard Subdomain](docs/wildcard-subdomain.md)** — Why workspaces need it, how to check via CLI
- **[Cursor Server Troubleshooting](docs/cursor-server-troubleshooting.md)** — Fix "Code server did not start successfully"
- **[Workspace Sync](docs/workspace-sync.md)** — rsync, cron, inotifywait, lsyncd, Unison options for syncing Coder ↔ local

## CI/CD

GitHub Actions runs on every push and pull request:

- **Test** — `terraform init`, `terraform validate`, and `terraform fmt -check` for each template
- **Push to GitLab** — After tests pass on `main`, syncs to a GitLab mirror (optional)

### GitLab Mirror Setup (GitHub Actions)

To enable pushing to GitLab after tests pass, add this repository secret (same as [freya](https://github.com/DataKnifeAI/freya)):

| Secret | Description |
|-------|-------------|
| `GITLAB_TOKEN` | GitLab [Personal Access Token](https://docs.gitlab.com/ee/user/profile/personal_access_tokens/) or [Project Access Token](https://docs.gitlab.com/ee/user/project/settings/project_access_tokens.html) with `write_repository` scope |

Mirror URL: `https://gitlab.com/dk-raas/dkai/devops/coder-templates`

### GitLab CI (Push to Coder)

The GitLab pipeline tests templates and pushes updates to Coder when changes land on `main`. Configure these CI/CD variables (Settings > CI/CD > Variables):

| Variable | Type | Description |
|----------|------|-------------|
| `CODER_URL` | Variable | Coder instance URL (e.g. `https://coder.dataknife.net`) |
| `CODER_SESSION_TOKEN` | Masked | Long-lived token: `coder token create --lifetime 8760h --name "GitLab CI"` |

## Links

- [Coder Documentation](https://coder.com/docs)
- [Coder Registry](https://registry.coder.com)
- [Coder on GitHub](https://github.com/coder/coder)
