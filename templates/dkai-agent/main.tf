terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
  default     = "coder-workspaces"
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB (can only be increased after creation)"
  default      = "50"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = true
  validation {
    min       = 50
    max       = 100
    monotonic = "increasing"
  }
}

data "coder_parameter" "cursor_pool_idle_timeout" {
  name         = "cursor_pool_idle_timeout"
  display_name = "Cursor pool idle release (seconds)"
  description  = "After a Cloud Agent session ends, keep the pool worker connected this many seconds for follow-ups (see Cursor self-hosted pool). Used by ~/bin/start-cursor-pool-worker."
  default      = "600"
  type         = "number"
  icon         = "/emojis/1f916.png"
  mutable      = true
  validation {
    min = 30
    max = 86400
  }
}

data "coder_parameter" "cursor_api_key" {
  name         = "cursor_api_key"
  display_name = "Cursor API key"
  description  = "Optional. Service account API key for Cursor Cloud Agent pool workers (sets CURSOR_API_KEY in the workspace). Leave empty to configure manually. Stored with the workspace; prefer org secret stores for production."
  type         = "string"
  form_type    = "input"
  default      = ""
  mutable      = true
  icon         = "/emojis/1f511.png"
  styling = jsonencode({
    mask_input = true
  })
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  display_apps {
    vscode = false
  }
  startup_script = <<-EOT
    set -e
    # Pod runs as root (see deployment); pacman installs tools, then UID 1000 under /home/coder.
    # Mask detect-old-perl-modules: that hook can invoke sudo on some K8s nodes; bash permission denied.
    mkdir -p /etc/pacman.d/hooks
    printf "%s\n" \
      "[Action]" \
      "Description = Skip old perl modules check (Coder/K8s)" \
      "When = PostTransaction" \
      "Exec = /usr/bin/true" \
      >/etc/pacman.d/hooks/detect-old-perl-modules.hook
    pacman -Sy --needed --noconfirm --disable-sandbox \
      apparmor bash binutils curl git nodejs zstd
    # gh/glab: upstream binaries (Arch pkgs pull sudo). Each start: resolve latest stable from release APIs, reinstall if outdated.
    # Trim GitHub release tag with sed; avoid bash prefix-strip here; Terraform treats dollar-brace as template syntax in this block.
    # Avoid apostrophe in curl -w; avoid command-substitution open-paren on one line if the agent strips dollar signs.
    CFMT=%%{url_effective}
    curl -fsSIL -A "Mozilla/5.0" -o /dev/null -w "$$CFMT" https://github.com/cli/cli/releases/latest 2>/dev/null > /tmp/dkai-gh-url || true
    read -r GH_URL < /tmp/dkai-gh-url || true
    GH_TAG=$${GH_URL##*/}
    T="$$GH_TAG" python3 -c "import os; print(os.environ.get(\"T\",\"\").removeprefix(\"v\"))" 2>/dev/null > /tmp/dkai-gh-ver || true
    read -r GH_VERSION < /tmp/dkai-gh-ver || true
    [ -n "$$GH_VERSION" ] || GH_VERSION=2.89.0
    printf "%s" "$$GH_VERSION" | grep -qE '^[0-9]+\\.[0-9]+\\.[0-9]+$$' || GH_VERSION=2.89.0
    GH_CUR=
    if command -v gh >/dev/null 2>&1; then
      gh version 2>/dev/null | head -n1 | sed -E "s/^gh version ([0-9.]+).*/\\1/" > /tmp/dkai-gh-cur || true
      read -r GH_CUR < /tmp/dkai-gh-cur || true
    fi
    if [ "$$GH_CUR" != "$$GH_VERSION" ]; then
      if curl -fsSL "https://github.com/cli/cli/releases/download/v$${GH_VERSION}/gh_$${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tgz; then
        tar -xzf /tmp/gh.tgz -C /tmp
        install -m 0755 "/tmp/gh_$${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh
        rm -rf "/tmp/gh_$${GH_VERSION}_linux_amd64" /tmp/gh.tgz
      fi
    fi
    curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest" -o /tmp/dkai-glab-json 2>/dev/null || true
    python3 -c "import sys,json; t=json.load(sys.stdin)[\"tag_name\"]; print(t.removeprefix(\"v\"))" < /tmp/dkai-glab-json > /tmp/dkai-glab-ver 2>/dev/null || true
    read -r GLAB_VERSION < /tmp/dkai-glab-ver || true
    [ -n "$$GLAB_VERSION" ] || GLAB_VERSION=1.92.0
    printf "%s" "$$GLAB_VERSION" | grep -qE '^[0-9]+\\.[0-9]+\\.[0-9]+$$' || GLAB_VERSION=1.92.0
    GLAB_CUR=
    if command -v glab >/dev/null 2>&1; then
      glab version 2>/dev/null | head -n1 | sed -E "s/.*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/" > /tmp/dkai-glab-cur || true
      read -r GLAB_CUR < /tmp/dkai-glab-cur || true
    fi
    if [ "$$GLAB_CUR" != "$$GLAB_VERSION" ]; then
      if curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v$${GLAB_VERSION}/downloads/glab_$${GLAB_VERSION}_linux_amd64.tar.gz" -o /tmp/glab.tgz; then
        tar -xzf /tmp/glab.tgz -C /tmp
        install -m 0755 /tmp/bin/glab /usr/local/bin/glab
        rm -rf /tmp/bin /tmp/glab.tgz
      fi
    fi
    if ! id -u coder >/dev/null 2>&1; then
      # PVC is usually mounted at /home/coder before this runs; -m would warn and skip skel.
      if [ -d /home/coder ]; then
        useradd --no-create-home -u 1000 -d /home/coder -s /bin/bash coder
      else
        useradd -m -u 1000 -s /bin/bash coder
      fi
    fi
    # May fail on NFS (root_squash); home should already be UID/GID 1000 from storage.
    chown -R coder:coder /home/coder 2>/dev/null || true
    # Default repo path for pool worker (see README); ensure it exists on fresh PVC.
    mkdir -p /home/coder/git
    chown coder:coder /home/coder/git 2>/dev/null || true
    # Cursor Agent terminal sandbox (AppArmor profile); extract .deb manually — pacman’s dpkg lacks zst.
    CURSOR_SANDBOX_DEB=/tmp/cursor-sandbox-apparmor.deb
    CURSOR_SANDBOX_PROFILE=/etc/apparmor.d/cursor-sandbox-remote
    if [ ! -f "$CURSOR_SANDBOX_PROFILE" ]; then
      curl -fsSL https://downloads.cursor.com/lab/enterprise/cursor-sandbox-apparmor_0.6.0_all.deb -o "$CURSOR_SANDBOX_DEB"
      mkdir -p /tmp/cursor-sandbox-apparmor-extract
      ( cd /tmp/cursor-sandbox-apparmor-extract && ar x "$CURSOR_SANDBOX_DEB" data.tar.zst && zstd -dc data.tar.zst | tar -x -C / )
      rm -rf /tmp/cursor-sandbox-apparmor-extract
    fi
    if [ -f /etc/sysctl.d/50-cursor-remote-userns.conf ]; then
      sysctl -p /etc/sysctl.d/50-cursor-remote-userns.conf 2>/dev/null || true
    fi
    if ! command -v coder >/dev/null 2>&1; then
      curl -fsSL https://coder.dataknife.net/install.sh | sh -s --
    fi
    if [ ! -f /home/coder/.local/bin/agent ]; then
      mkdir -p /home/coder/.local
      chown coder:coder /home/coder/.local 2>/dev/null || true
      curl -fsSL https://cursor.com/install | env HOME=/home/coder USER=coder LOGNAME=coder TAR_OPTIONS=--no-same-owner bash
      chown -R coder:coder /home/coder/.local /home/coder/.cursor 2>/dev/null || true
    fi
    # Cursor agent installs under HOME/.local/bin; terminals often start as root — symlink into PATH.
    if [ -e /home/coder/.local/bin/agent ]; then
      ln -sf /home/coder/.local/bin/agent /usr/local/bin/agent
    fi
    mkdir -p /home/coder/bin
    chown coder:coder /home/coder/bin 2>/dev/null || true
    cat > /home/coder/bin/start-cursor-pool-worker <<'POOLHELPER'
#!/usr/bin/env bash
set -euo pipefail
# Self-hosted Cloud Agent pool — https://cursor.com/docs/cloud-agent/self-hosted-pool
REPO_ROOT="$${CURSOR_WORKER_DIR:-/home/coder/git}"
cd "$$REPO_ROOT" || { echo "Worker repo not found: $$REPO_ROOT (clone a repo or set CURSOR_WORKER_DIR)" >&2; exit 1; }
if [ -z "$${CURSOR_API_KEY:-}" ]; then
  echo "Export CURSOR_API_KEY with your Cursor service account API key, then re-run." >&2
  echo "Docs: https://cursor.com/docs/account/enterprise/service-accounts" >&2
  exit 1
fi
EXTRA=()
[ -n "$${CURSOR_WORKER_MANAGEMENT_ADDR:-}" ] && EXTRA+=(--management-addr "$${CURSOR_WORKER_MANAGEMENT_ADDR}")
[ -n "$${CURSOR_WORKER_LABELS_FILE:-}" ] && EXTRA+=(--labels-file "$${CURSOR_WORKER_LABELS_FILE}")
exec agent worker start --pool --idle-release-timeout __IDLE_SEC__ "$${EXTRA[@]}" "$$@"
POOLHELPER
    sed -i "s/__IDLE_SEC__/${data.coder_parameter.cursor_pool_idle_timeout.value}/" /home/coder/bin/start-cursor-pool-worker
    chmod 0755 /home/coder/bin/start-cursor-pool-worker 2>/dev/null || true
    # NFS / root_squash: chown may fail; 0755 still lets the coder user run the script as "other"
    chown coder:coder /home/coder/bin/start-cursor-pool-worker 2>/dev/null || true
    ln -sf /home/coder/bin/start-cursor-pool-worker /usr/local/bin/start-cursor-pool-worker 2>/dev/null || true
    if [ ! -f /home/coder/.cursor-worker-labels.json.example ]; then
      printf "%s\n" \
        "{" \
        "  \"team\": \"your-team\"," \
        "  \"env\": \"coder-workspace\"," \
        "  \"capabilities\": [\"docker\"]" \
        "}" \
        > /home/coder/.cursor-worker-labels.json.example
      chown coder:coder /home/coder/.cursor-worker-labels.json.example 2>/dev/null || true
    fi
    if [ -f "$CURSOR_SANDBOX_PROFILE" ] && command -v apparmor_parser >/dev/null 2>&1; then
      apparmor_parser -r "$CURSOR_SANDBOX_PROFILE" 2>/dev/null || true
    fi
    # Add ~/.local/bin and ~/bin to PATH for coder user (.bashrc + .profile for login shells e.g. Cursor terminal)
    for f in /home/coder/.bashrc /home/coder/.profile; do
      [ -f "$f" ] || touch "$f"
      grep -qF ".local/bin" "$f" 2>/dev/null || printf "%s\n" "export PATH=\"\$HOME/.local/bin:\$HOME/bin:\$PATH\"" >> "$f"
    done
    rm -f /home/coder/.cursor-server/package.json
    echo ""
    echo "=== Startup summary ==="
    echo ""
    echo "git"
    git --version 2>/dev/null || echo "  (not found)"
    echo ""
    echo "Node.js"
    node -v 2>/dev/null || echo "  (not found)"
    echo ""
    echo "CLI tools"
    if command -v gh >/dev/null 2>&1; then gh version 2>/dev/null | head -n1; else echo "  gh: not found"; fi
    if command -v glab >/dev/null 2>&1; then glab version 2>/dev/null | head -n1; else echo "  glab: not found"; fi
    if command -v coder >/dev/null 2>&1; then coder version 2>/dev/null | head -n1; else echo "  coder: not found"; fi
    if command -v agent >/dev/null 2>&1; then
      echo -n "  cursor (agent): "
      agent --version 2>/dev/null || echo "(no version string)"
    else
      echo "  cursor (agent): not installed"
    fi
    echo ""
    echo "=== Cursor Cloud Agent (self-hosted pool) ==="
    echo "  Docs: https://cursor.com/docs/cloud-agent/self-hosted-pool"
    echo "  Prerequisites: team plan, self-hosted agents enabled, service account API key."
    echo "  Clone the repo the worker should serve under /home/coder/git (or set CURSOR_WORKER_DIR)."
    echo "  Set CURSOR_API_KEY via workspace parameter cursor_api_key, or: export CURSOR_API_KEY=\"<key>\""
    echo "  Optional: export CURSOR_WORKER_LABELS_FILE=/home/coder/.cursor-worker-labels.json"
    echo "  Optional: export CURSOR_WORKER_MANAGEMENT_ADDR=:8080   # /metrics /healthz /readyz"
    echo "  Run as coder:  start-cursor-pool-worker"
    echo "  (idle-release-timeout defaults from workspace parameter cursor_pool_idle_timeout)"
    echo ""
    echo "=== Other CLI (run as the workspace user) ==="
    echo "  GitHub:  gh auth login"
    echo "  GitLab:  glab auth login"
    echo "  Coder:   this workspace is linked; CLI elsewhere: coder login <your-coder-url>"
    echo ""
  EOT

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

# Inject pool worker API key when provided (avoid embedding secrets in startup_script).
resource "coder_env" "cursor_api_key" {
  count    = trimspace(data.coder_parameter.cursor_api_key.value) != "" ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "CURSOR_API_KEY"
  value    = data.coder_parameter.cursor_api_key.value
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace_owner.me.id
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "truenas-csi-nfs"
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home
  ]
  wait_for_rollout = false
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
        "app.kubernetes.io/part-of"  = "coder"
        "com.coder.resource"         = "true"
        "com.coder.workspace.id"     = data.coder_workspace.me.id
        "com.coder.workspace.name"   = data.coder_workspace.me.name
        "com.coder.user.id"          = data.coder_workspace_owner.me.id
        "com.coder.user.username"    = data.coder_workspace_owner.me.name
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
          "app.kubernetes.io/part-of"  = "coder"
          "com.coder.resource"         = "true"
          "com.coder.workspace.id"     = data.coder_workspace.me.id
          "com.coder.workspace.name"   = data.coder_workspace.me.name
          "com.coder.user.id"          = data.coder_workspace_owner.me.id
          "com.coder.user.username"    = data.coder_workspace_owner.me.name
        }
      }
      spec {
        # archlinux image has no UID-1000 workspace user; pod runs as root for pacman bootstrap.
        # NFS home volume: prefer UID/GID 1000 on the share; startup_script chowns when permitted.
        security_context {
          run_as_user     = 0
          run_as_non_root = false
        }

        container {
          name              = "dev"
          image             = "docker.io/archlinux:latest"
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "0"
          }
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata.0.name
            read_only  = false
          }
        }

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
