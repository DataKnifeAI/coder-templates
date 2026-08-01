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
    # Node.js 20+ required for Cursor Server (Remote-SSH fallback when bundled node fails)
    NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0)
    if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 20 ] 2>/dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi
    # GitHub CLI (https://cli.github.com)
    if ! command -v gh >/dev/null 2>&1; then
      sudo mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      ARCH=$(dpkg --print-architecture)
      echo "deb [arch=$${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y gh
    fi
    # GitLab CLI (WakeMeOps apt; see GitLab docs installation_options.md — GitHub install.sh is 404)
    if ! command -v glab >/dev/null 2>&1; then
      curl -fsSL "https://raw.githubusercontent.com/upciti/wakemeops/main/assets/install_repository" | sudo bash
      sudo apt-get install -y glab
    fi
    # Popular dev languages (apt; idempotent — skip packages already installed)
    LANG_APT=
    command -v go >/dev/null 2>&1 || LANG_APT="$LANG_APT golang-go"
    if ! command -v python3 >/dev/null 2>&1; then
      LANG_APT="$LANG_APT python3 python3-pip python3-venv"
    elif ! command -v pip3 >/dev/null 2>&1; then
      LANG_APT="$LANG_APT python3-pip python3-venv"
    fi
    command -v javac >/dev/null 2>&1 || LANG_APT="$LANG_APT default-jdk"
    command -v mvn >/dev/null 2>&1 || LANG_APT="$LANG_APT maven"
    command -v gradle >/dev/null 2>&1 || LANG_APT="$LANG_APT gradle"
    command -v ruby >/dev/null 2>&1 || LANG_APT="$LANG_APT ruby-full"
    command -v php >/dev/null 2>&1 || LANG_APT="$LANG_APT php-cli php"
    command -v rustc >/dev/null 2>&1 || LANG_APT="$LANG_APT rustc cargo"
    command -v gcc >/dev/null 2>&1 || LANG_APT="$LANG_APT build-essential"
    if [ -n "$LANG_APT" ]; then
      sudo apt-get update
      # shellcheck disable=SC2086
      sudo apt-get install -y $LANG_APT
    fi
    # .NET SDK (Microsoft apt feed)
    if ! command -v dotnet >/dev/null 2>&1; then
      if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
        UBUNTU_VER=$(. /etc/os-release && echo "$VERSION_ID")
        curl -fsSL "https://packages.microsoft.com/config/ubuntu/$UBUNTU_VER/packages-microsoft-prod.deb" -o /tmp/packages-microsoft-prod.deb
        sudo dpkg -i /tmp/packages-microsoft-prod.deb
      fi
      sudo apt-get update
      sudo apt-get install -y dotnet-sdk-8.0
    fi
    # pnpm (Node package manager)
    if command -v npm >/dev/null 2>&1 && ! command -v pnpm >/dev/null 2>&1; then
      sudo npm install -g pnpm
    fi
    # uv (Python package manager)
    if ! command -v uv >/dev/null 2>&1; then
      curl -LsSf https://astral.sh/uv/install.sh | sudo env UV_INSTALL_DIR=/usr/local/bin sh
    fi
    sudo git config --system --add safe.directory '*' 2>/dev/null || true
    printf '%s\n' \
      '# Coder may set GIT_ASKPASS; use gh/glab credential helpers for HTTPS (see templates/dkai-dev/README.md).' \
      'export GIT_ASKPASS=true' \
      | sudo tee /etc/profile.d/dkai-git-askpass.sh >/dev/null
    sudo chmod 0644 /etc/profile.d/dkai-git-askpass.sh
    if command -v git >/dev/null 2>&1; then
      if [ -x /usr/bin/gh ]; then
        sudo git config --global credential.https://github.com.helper '!/usr/bin/gh auth git-credential'
      fi
      if [ -x /usr/bin/glab ]; then
        sudo git config --global credential.https://gitlab.com.helper '!/usr/bin/glab auth git-credential'
      fi
      if id -u coder >/dev/null 2>&1; then
        if [ -x /usr/bin/gh ]; then
          sudo -u coder git config --global credential.https://github.com.helper '!/usr/bin/gh auth git-credential' || true
        fi
        if [ -x /usr/bin/glab ]; then
          sudo -u coder git config --global credential.https://gitlab.com.helper '!/usr/bin/glab auth git-credential' || true
        fi
      fi
    fi
    # Cursor Agent terminal sandbox — cursor.com/docs/agent/terminal
    # postinst only runs apparmor_parser if systemd apparmor.service is active; force-load in containers.
    if ! dpkg -l cursor-sandbox-apparmor 2>/dev/null | grep -q '^ii'; then
      curl -fsSL https://downloads.cursor.com/lab/enterprise/cursor-sandbox-apparmor_0.6.0_all.deb -o /tmp/cursor-sandbox-apparmor.deb
      sudo apt-get install -y apparmor /tmp/cursor-sandbox-apparmor.deb || echo 'warning: cursor-sandbox-apparmor install failed (Agent terminal sandbox may not work)' >&2
    fi
    if [ -f /etc/apparmor.d/cursor-sandbox-remote ] && command -v apparmor_parser >/dev/null 2>&1; then
      sudo apparmor_parser -r /etc/apparmor.d/cursor-sandbox-remote 2>/dev/null || true
    fi
    if [ -f /etc/sysctl.d/50-cursor-remote-userns.conf ]; then
      sudo sysctl -p /etc/sysctl.d/50-cursor-remote-userns.conf 2>/dev/null || true
    fi
    # Coder CLI (install script from this deployment)
    if ! command -v coder >/dev/null 2>&1; then
      curl -fsSL https://coder.dataknife.net/install.sh | sudo sh -s --
    fi
    # Install Cursor CLI (https://cursor.com/cli) as coder user
    if [ ! -f /home/coder/.local/bin/agent ]; then
      sudo -u coder bash -c 'curl -fsSL https://cursor.com/install | bash'
    fi
    # Add ~/.local/bin to PATH for coder user (.bashrc + .profile for login shells e.g. Cursor terminal)
    CURSOR_PATH='export PATH="$HOME/.local/bin:$PATH"'
    for f in /home/coder/.bashrc /home/coder/.profile; do
      [ -f "$f" ] || touch "$f"
      grep -qF '.local/bin' "$f" 2>/dev/null || echo "$CURSOR_PATH" >> "$f"
      grep -qF 'GIT_ASKPASS=true' "$f" 2>/dev/null || printf '%s\n' \
        '# DKAI: Coder may set GIT_ASKPASS; use gh/glab credential helpers for GitHub/GitLab HTTPS.' \
        'export GIT_ASKPASS=true' >> "$f"
    done
    # Remove any leftover package.json from old workaround (breaks multiplex + code server)
    rm -f /home/coder/.cursor-server/package.json
    echo ''
    echo '=== Startup summary ==='
    echo ''
    echo 'git'
    git --version 2>/dev/null || echo '  (not found)'
    echo ''
    echo 'Node.js'
    node -v 2>/dev/null || echo '  (not found)'
    if command -v pnpm >/dev/null 2>&1; then pnpm -v 2>/dev/null | sed 's/^/  pnpm: v/'; else echo '  pnpm: (not found)'; fi
    echo ''
    echo 'Python'
    python3 --version 2>/dev/null || echo '  (not found)'
    if command -v uv >/dev/null 2>&1; then uv --version 2>/dev/null | head -n1; else echo '  uv: (not found)'; fi
    echo ''
    echo 'Go'
    go version 2>/dev/null || echo '  (not found)'
    echo ''
    echo 'Rust'
    rustc --version 2>/dev/null || echo '  rustc: (not found)'
    cargo --version 2>/dev/null || echo '  cargo: (not found)'
    echo ''
    echo 'Java'
    javac -version 2>&1 || echo '  javac: (not found)'
    if command -v mvn >/dev/null 2>&1; then mvn -version 2>/dev/null | head -n1; else echo '  maven: (not found)'; fi
    if command -v gradle >/dev/null 2>&1; then gradle --version 2>/dev/null | head -n1; else echo '  gradle: (not found)'; fi
    echo ''
    echo 'Ruby'
    ruby --version 2>/dev/null || echo '  (not found)'
    echo ''
    echo 'PHP'
    if command -v php >/dev/null 2>&1; then php --version 2>/dev/null | head -n1; else echo '  php: (not found)'; fi
    echo ''
    echo '.NET'
    dotnet --version 2>/dev/null || echo '  (not found)'
    echo ''
    echo 'C/C++'
    if command -v gcc >/dev/null 2>&1; then gcc --version 2>/dev/null | head -n1; else echo '  gcc: (not found)'; fi
    echo ''
    echo 'CLI tools'
    if command -v gh >/dev/null 2>&1; then gh version 2>/dev/null | head -n1; else echo '  gh: not found'; fi
    if command -v glab >/dev/null 2>&1; then glab version 2>/dev/null | head -n1; else echo '  glab: not found'; fi
    if command -v coder >/dev/null 2>&1; then coder version 2>/dev/null | head -n1; else echo '  coder: not found'; fi
    if [ -x /home/coder/.local/bin/agent ]; then
      echo -n '  cursor (agent): '
      /home/coder/.local/bin/agent --version 2>/dev/null || echo '(no version string)'
    else
      echo '  cursor (agent): not installed'
    fi
    echo ''
    echo '=== CLI login (run in a terminal as the workspace user) ==='
    echo '  GitHub:  gh auth login'
    echo '  GitLab:  glab auth login'
    echo '  Coder:   this workspace is already linked; for CLI outside Coder use: coder login <your-coder-url>'
    echo ''
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

# Cursor IDE - one-click button to launch Cursor Desktop
# https://registry.coder.com/modules/coder/cursor
module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/git"
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
        # No fs_group: kubelet would chown the volume, which breaks NFS. Ensure the
        # NFS export (or PV) is owned by UID 1000 to match run_as_user.
        security_context {
          run_as_user     = 1000
          run_as_non_root = true
        }

        container {
          name              = "dev"
          image             = "codercom/enterprise-base:ubuntu"
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
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
