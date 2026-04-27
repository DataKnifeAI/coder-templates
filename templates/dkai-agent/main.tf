terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
  required_version = ">= 1.5.0"
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
  description  = "CPU limit for the workspace pod (Kubernetes limits.cpu; 2 or 4 cores)."
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
  description  = "Memory limit for the workspace pod in GiB (Kubernetes limits.memory as 4Gi or 8Gi)."
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
  description  = "Size of the home PVC for /home/coder in GiB (Kubernetes storage request N Gi). Range 50–100 GiB; can only be increased after creation."
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

data "coder_parameter" "tool_config_disk_size" {
  name         = "tool_config_disk_size"
  display_name = "Tool config disk (kube, gh, glab-cli, coder, rancher)"
  description  = "Size in GiB of the shared ReadWriteMany tool-config PVC at /mnt/coder-tool-config (default 5 GiB; range 1–50 GiB; monotonic increase). One PVC per Coder owner (coder-<owner-id>-tool-config); all your dkai-agent workspaces share it. Plan-time cluster check creates the PVC if missing, otherwise attaches to the existing claim."
  default      = "5"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = true
  validation {
    min       = 1
    max       = 50
    monotonic = "increasing"
  }
}

data "coder_parameter" "cursor_worker_idle_timeout" {
  name         = "cursor_worker_idle_timeout"
  display_name = "Cursor worker idle release (seconds)"
  description  = "Value passed to agent worker start --idle-release-timeout in /home/coder/bin/start-cursor-worker (seconds). See agent worker start --help. Not used for team pool mode."
  default      = "600"
  type         = "number"
  icon         = "/emojis/1f916.png"
  mutable      = true
  validation {
    min = 30
    max = 86400
  }
}

data "coder_parameter" "cursor_worker_git_url" {
  name         = "cursor_worker_git_url"
  display_name = "Cursor worker Git repo (HTTPS)"
  description  = "HTTPS URL for the Cursor worker checkout: cloned or updated under /home/coder/<repo>/ at startup (repo name = basename of the URL without .git). Clear to skip clone/pull and use /home/coder only."
  type         = "string"
  form_type    = "input"
  default      = "https://github.com/DataKnifeAI/agent-workspace.git"
  mutable      = true
  icon         = "/icon/github.svg"
}

data "coder_parameter" "cursor_api_key" {
  name         = "cursor_api_key"
  display_name = "Cursor API key"
  description  = "Optional. Your Cursor API key (Dashboard → Cursor Settings → API Keys). When set, Coder injects CURSOR_API_KEY via coder_env and the startup script auto-starts agent worker start (individual key, not --pool). Clear to set the key only inside the workspace. Usage bills to your Cursor account; treat like any workspace secret."
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

locals {
  # One ReadWriteMany tool-config PVC per Coder owner (not per workspace).
  tool_config_user_pvc_name = "coder-${data.coder_workspace_owner.me.id}-tool-config"
}

# Plan-time: shared PVC may already exist (another workspace created it). Avoid AlreadyExists on create.
# Probe with the same auth the kubernetes provider uses: in-cluster ServiceAccount + API when
# use_kubeconfig is false (kubectl is often not installed on the Coder pod).
data "external" "tool_shared_pvc_exists" {
  program = [
    "${path.module}/scripts/tool-shared-pvc-exists.sh",
    var.namespace,
    local.tool_config_user_pvc_name,
    var.use_kubeconfig ? "true" : "false",
    pathexpand("~/.kube/config"),
  ]
}

locals {
  tool_shared_pvc_exists = data.external.tool_shared_pvc_exists.result.exists == "true"
  # Import map: when the PVC already exists in the cluster, adopt it into this workspace's state so we
  # never flip count 1→0 (which would plan a destroy on the next apply after the creating workspace).
  tool_shared_pvc_import = local.tool_shared_pvc_exists ? { import = true } : {}
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  # Blocking: workspace is not ready until this script exits. Do not add a second run_on_start coder_script for
  # the Cursor worker — Coder runs multiple coder_scripts in parallel, which races and can SIGTERM scripts (see agent log).
  startup_script_behavior = "blocking"
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
      apparmor bash binutils curl git kubectl kubectx nano nodejs unzip zstd
    # Git 2.35+: "dubious ownership" when .git owner != invoking user (NFS root_squash → nobody, or root in a coder-owned tree).
    git config --system --add safe.directory '*' 2>/dev/null || true
    # Coder often sets GIT_ASKPASS for git; neutralize so gh/glab credential helpers can supply HTTPS tokens.
    printf '%s\n' \
      '# Managed by DKAI Agent template (see templates/dkai-agent/README.md).' \
      'export GIT_ASKPASS=true' \
      >/etc/profile.d/dkai-git-askpass.sh
    chmod 0644 /etc/profile.d/dkai-git-askpass.sh
    # Optional CLI downloads must not fail the whole startup (set -e): network blips, bad semver, etc.
    set +e
    # gh/glab: upstream binaries (Arch pkgs pull sudo). Each start: resolve latest stable from release APIs, reinstall if outdated.
    # Trim GitHub release tag with sed; avoid bash prefix-strip here; Terraform treats dollar-brace as template syntax in this block.
    # Avoid apostrophe in curl -w; avoid command-substitution open-paren on one line if the agent strips dollar signs.
    CFMT=%%{url_effective}
    curl -fsSIL -A "Mozilla/5.0" -o /dev/null -w "$${CFMT}" https://github.com/cli/cli/releases/latest 2>/dev/null > /tmp/dkai-gh-url || true
    read -r GH_URL < /tmp/dkai-gh-url || true
    GH_TAG=$${GH_URL##*/}
    T="$${GH_TAG}" python3 -c "import os; print(os.environ.get(\"T\",\"\").removeprefix(\"v\"))" 2>/dev/null > /tmp/dkai-gh-ver || true
    read -r GH_VERSION < /tmp/dkai-gh-ver || true
    [ -n "$${GH_VERSION}" ] || GH_VERSION=2.89.0
    printf "%s" "$${GH_VERSION}" | grep -qE '^[0-9]+\\.[0-9]+\\.[0-9]+$$' || GH_VERSION=2.89.0
    GH_CUR=
    if command -v gh >/dev/null 2>&1; then
      gh version 2>/dev/null | head -n1 | sed -E "s/^gh version ([0-9.]+).*/\\1/" > /tmp/dkai-gh-cur || true
      read -r GH_CUR < /tmp/dkai-gh-cur || true
    fi
    if [ "$${GH_CUR}" != "$${GH_VERSION}" ]; then
      if curl -fsSL "https://github.com/cli/cli/releases/download/v$${GH_VERSION}/gh_$${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tgz; then
        tar -xzf /tmp/gh.tgz -C /tmp
        install -m 0755 "/tmp/gh_$${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh
        rm -rf "/tmp/gh_$${GH_VERSION}_linux_amd64" /tmp/gh.tgz
      fi
    fi
    curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest" -o /tmp/dkai-glab-json 2>/dev/null || true
    python3 -c "import sys,json; t=json.load(sys.stdin)[\"tag_name\"]; print(t.removeprefix(\"v\"))" < /tmp/dkai-glab-json > /tmp/dkai-glab-ver 2>/dev/null || true
    read -r GLAB_VERSION < /tmp/dkai-glab-ver || true
    [ -n "$${GLAB_VERSION}" ] || GLAB_VERSION=1.92.0
    printf "%s" "$${GLAB_VERSION}" | grep -qE '^[0-9]+\\.[0-9]+\\.[0-9]+$$' || GLAB_VERSION=1.92.0
    GLAB_CUR=
    if command -v glab >/dev/null 2>&1; then
      glab version 2>/dev/null | head -n1 | sed -E "s/.*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/" > /tmp/dkai-glab-cur || true
      read -r GLAB_CUR < /tmp/dkai-glab-cur || true
    fi
    if [ "$${GLAB_CUR}" != "$${GLAB_VERSION}" ]; then
      if curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v$${GLAB_VERSION}/downloads/glab_$${GLAB_VERSION}_linux_amd64.tar.gz" -o /tmp/glab.tgz; then
        tar -xzf /tmp/glab.tgz -C /tmp
        install -m 0755 /tmp/bin/glab /usr/local/bin/glab
        rm -rf /tmp/bin /tmp/glab.tgz
      fi
    fi
    # kubectl: installed from Arch extra (pacman above). Avoid dl.k8s.io curl — flaky behind some networks.
    # kubectx Arch package installs kubectx + kubens (https://github.com/ahmetb/kubectx) — context/namespace switchers.
    # Rancher CLI: read Location from /releases/latest (no GitHub API — unauthenticated api.github.com is rate-limited in shared clusters).
    if ! command -v rancher >/dev/null 2>&1; then
      RANCHER_LOC=$(/usr/bin/curl -sI --no-styled-output -A "Mozilla/5.0" https://github.com/rancher/cli/releases/latest 2>/dev/null | grep -i '^[Ll]ocation:' | awk '{print $$2}' | tr -d '\r' | head -n1 || true)
      RANCHER_VER=$${RANCHER_LOC##*/}
      if [ -n "$${RANCHER_VER}" ] && /usr/bin/curl -fsSL "https://github.com/rancher/cli/releases/download/$${RANCHER_VER}/rancher-linux-amd64-$${RANCHER_VER}.tar.gz" -o /tmp/rancher-cli.tgz; then
        mkdir -p /tmp/rancher-extract
        tar -xzf /tmp/rancher-cli.tgz -C /tmp/rancher-extract
        find /tmp/rancher-extract -name rancher -type f 2>/dev/null | head -n1 > /tmp/dkai-rancher-binpath
        read -r RBIN < /tmp/dkai-rancher-binpath
        if [ -n "$${RBIN}" ]; then
          install -m 0755 "$${RBIN}" /usr/local/bin/rancher
        fi
        rm -f /tmp/dkai-rancher-binpath
        rm -rf /tmp/rancher-cli.tgz /tmp/rancher-extract
      fi
    fi
    # HashiCorp Terraform: zip from releases.hashicorp.com (Arch community/terraform pulls extra deps).
    TF_VERSION=1.13.5
    if command -v terraform >/dev/null 2>&1; then
      TF_CUR=$(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('terraform_version',''))" 2>/dev/null || true)
    else
      TF_CUR=
    fi
    if [ "$${TF_CUR}" != "$${TF_VERSION}" ]; then
      if curl -fsSL "https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip; then
        unzip -o -q /tmp/terraform.zip -d /tmp/terraform-extract
        install -m 0755 /tmp/terraform-extract/terraform /usr/local/bin/terraform
        rm -rf /tmp/terraform-extract /tmp/terraform.zip
      fi
    fi
    set -e
    if ! id -u coder >/dev/null 2>&1; then
      # PVC is usually mounted at /home/coder before this runs; -m would warn and skip skel.
      # Prefer UID 1000; if taken, fall back so startup does not abort under set -e.
      if [ -d /home/coder ]; then
        useradd --no-create-home -u 1000 -d /home/coder -s /bin/bash coder 2>/dev/null || \
        useradd --no-create-home -d /home/coder -s /bin/bash coder || true
      else
        useradd -m -u 1000 -s /bin/bash coder 2>/dev/null || \
        useradd -m -s /bin/bash coder || true
      fi
    fi
    # Only chown when the account exists; avoid invoking chown with a nonexistent user name.
    _chown_coder() { id -u coder >/dev/null 2>&1 && chown "$$@"; }
    # May fail on NFS (root_squash); home should already be UID/GID 1000 from storage.
    _chown_coder -R coder:coder /home/coder 2>/dev/null || true
    # Second PVC (/mnt/coder-tool-config): symlinks from /root and /home/coder (see below).
    mkdir -p /mnt/coder-tool-config/kube /mnt/coder-tool-config/config/gh /mnt/coder-tool-config/config/glab-cli /mnt/coder-tool-config/config/coderv2 /mnt/coder-tool-config/rancher
    # Coder CLI v2 uses ~/.config/coderv2 (--global-config / $CODER_CONFIG_DIR), not ~/.config/coder.
    if [ -d /mnt/coder-tool-config/config/coder ] && [ -z "$$(ls -A /mnt/coder-tool-config/config/coderv2 2>/dev/null)" ]; then
      cp -a /mnt/coder-tool-config/config/coder/. /mnt/coder-tool-config/config/coderv2/ 2>/dev/null || true
    fi
    if ! grep -q '[[:space:]]/mnt/coder-tool-config[[:space:]]' /proc/mounts 2>/dev/null; then
      echo "WARN: /mnt/coder-tool-config is not listed in /proc/mounts — tool PVC may not be mounted; configs might not persist." >&2
    fi
    mkdir -p /home/coder/.config
    # Merge then remove legacy /home/coder tool paths (older templates symlinked paths; we no longer link /home/coder to this PVC).
    if [ -d /home/coder/.kube ] && [ ! -L /home/coder/.kube ]; then
      cp -a /home/coder/.kube/. /mnt/coder-tool-config/kube/ 2>/dev/null || true
      rm -rf /home/coder/.kube
    elif [ -L /home/coder/.kube ]; then
      rm -f /home/coder/.kube
    fi
    if [ -d /home/coder/.config/gh ] && [ ! -L /home/coder/.config/gh ]; then
      cp -a /home/coder/.config/gh/. /mnt/coder-tool-config/config/gh/ 2>/dev/null || true
      rm -rf /home/coder/.config/gh
    elif [ -L /home/coder/.config/gh ]; then
      rm -f /home/coder/.config/gh
    fi
    if [ -d /home/coder/.config/glab-cli ] && [ ! -L /home/coder/.config/glab-cli ]; then
      cp -a /home/coder/.config/glab-cli/. /mnt/coder-tool-config/config/glab-cli/ 2>/dev/null || true
      rm -rf /home/coder/.config/glab-cli
    elif [ -L /home/coder/.config/glab-cli ]; then
      rm -f /home/coder/.config/glab-cli
    fi
    if [ -d /home/coder/.config/coderv2 ] && [ ! -L /home/coder/.config/coderv2 ]; then
      cp -a /home/coder/.config/coderv2/. /mnt/coder-tool-config/config/coderv2/ 2>/dev/null || true
      rm -rf /home/coder/.config/coderv2
    elif [ -L /home/coder/.config/coderv2 ]; then
      rm -f /home/coder/.config/coderv2
    fi
    if [ -d /home/coder/.config/coder ] && [ ! -L /home/coder/.config/coder ]; then
      cp -a /home/coder/.config/coder/. /mnt/coder-tool-config/config/coderv2/ 2>/dev/null || true
      rm -rf /home/coder/.config/coder
    elif [ -L /home/coder/.config/coder ]; then
      rm -f /home/coder/.config/coder
    fi
    if [ -d /home/coder/.rancher ] && [ ! -L /home/coder/.rancher ]; then
      cp -a /home/coder/.rancher/. /mnt/coder-tool-config/rancher/ 2>/dev/null || true
      rm -rf /home/coder/.rancher
    elif [ -L /home/coder/.rancher ]; then
      rm -f /home/coder/.rancher
    fi
    # Point root's config paths at the PVC (default interactive user in this pod).
    mkdir -p /root/.config
    if [ -d /root/.kube ] && [ ! -L /root/.kube ]; then
      cp -a /root/.kube/. /mnt/coder-tool-config/kube/ 2>/dev/null || true
      rm -rf /root/.kube
    fi
    ln -sfn /mnt/coder-tool-config/kube /root/.kube
    if [ -d /root/.config/gh ] && [ ! -L /root/.config/gh ]; then
      cp -a /root/.config/gh/. /mnt/coder-tool-config/config/gh/ 2>/dev/null || true
      rm -rf /root/.config/gh
    fi
    ln -sfn /mnt/coder-tool-config/config/gh /root/.config/gh
    # glab: XDG ~/.config/glab-cli (legacy under /home/coder merged above; PVC is source of truth)
    rm -f /root/.config/glab 2>/dev/null
    rm -rf /root/.config/glab /root/.config/glab-cli 2>/dev/null
    ln -sfn /mnt/coder-tool-config/config/glab-cli /root/.config/glab-cli
    if [ -d /root/.config/coderv2 ] && [ ! -L /root/.config/coderv2 ]; then
      cp -a /root/.config/coderv2/. /mnt/coder-tool-config/config/coderv2/ 2>/dev/null || true
      rm -rf /root/.config/coderv2
    fi
    if [ -d /root/.config/coder ] && [ ! -L /root/.config/coder ]; then
      cp -a /root/.config/coder/. /mnt/coder-tool-config/config/coderv2/ 2>/dev/null || true
      rm -rf /root/.config/coder
    fi
    ln -sfn /mnt/coder-tool-config/config/coderv2 /root/.config/coderv2
    if [ -d /root/.rancher ] && [ ! -L /root/.rancher ]; then
      cp -a /root/.rancher/. /mnt/coder-tool-config/rancher/ 2>/dev/null || true
      rm -rf /root/.rancher
    fi
    ln -sfn /mnt/coder-tool-config/rancher /root/.rancher
    # coder: same PVC paths (HOME=/home/coder — Cursor agent, kubectl, coder CLI, gh/glab, rancher).
    ln -sfn /mnt/coder-tool-config/kube /home/coder/.kube
    ln -sfn /mnt/coder-tool-config/config/gh /home/coder/.config/gh
    ln -sfn /mnt/coder-tool-config/config/glab-cli /home/coder/.config/glab-cli
    ln -sfn /mnt/coder-tool-config/config/coderv2 /home/coder/.config/coderv2
    ln -sfn /mnt/coder-tool-config/rancher /home/coder/.rancher
    # coder:coder on tool PVC so root and coder share files without root-only tokens (fixes glab/gh as coder).
    chown -R coder:coder /mnt/coder-tool-config/kube /mnt/coder-tool-config/rancher /mnt/coder-tool-config/config/coderv2 /mnt/coder-tool-config/config/gh /mnt/coder-tool-config/config/glab-cli 2>/dev/null || true
    if command -v git >/dev/null 2>&1; then
      if [ -x /usr/local/bin/gh ]; then
        git config --global credential.https://github.com.helper '!/usr/local/bin/gh auth git-credential'
      fi
      if [ -x /usr/local/bin/glab ]; then
        git config --global credential.https://gitlab.com.helper '!/usr/local/bin/glab auth git-credential'
      fi
      if id -u coder >/dev/null 2>&1; then
        if command -v runuser >/dev/null 2>&1; then
          [ -x /usr/local/bin/gh ] && runuser -u coder -- git config --global credential.https://github.com.helper '!/usr/local/bin/gh auth git-credential' || true
          [ -x /usr/local/bin/glab ] && runuser -u coder -- git config --global credential.https://gitlab.com.helper '!/usr/local/bin/glab auth git-credential' || true
        else
          [ -x /usr/local/bin/gh ] && su -s /bin/bash coder -c "git config --global credential.https://github.com.helper '!/usr/local/bin/gh auth git-credential'" || true
          [ -x /usr/local/bin/glab ] && su -s /bin/bash coder -c "git config --global credential.https://gitlab.com.helper '!/usr/local/bin/glab auth git-credential'" || true
        fi
      fi
    fi
    # Default repo for Cloud Agent worker: clone under /home/coder/<repo-name> (not under ~/git).
    mkdir -p /home/coder
    _chown_coder coder:coder /home/coder 2>/dev/null || true
    WORKER_GIT_URL="${trimspace(data.coder_parameter.cursor_worker_git_url.value)}"
    WORKER_REPO_NAME=
    if [ -n "$${WORKER_GIT_URL}" ]; then
      WORKER_REPO_NAME=`basename "$${WORKER_GIT_URL}" .git`
      if [ ! -d "/home/coder/$${WORKER_REPO_NAME}/.git" ]; then
        # git clone with no path: creates a subdir with .git inside it
        rm -rf "/home/coder/$${WORKER_REPO_NAME}"
        cd /home/coder
        git clone "$${WORKER_GIT_URL}"
      elif ! git -C "/home/coder/$${WORKER_REPO_NAME}" remote get-url origin >/dev/null 2>&1; then
        _chown_coder -R coder:coder "/home/coder/$${WORKER_REPO_NAME}" 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" remote add origin "$${WORKER_GIT_URL}" 2>/dev/null || \
          git -C "/home/coder/$${WORKER_REPO_NAME}" remote set-url origin "$${WORKER_GIT_URL}"
      fi
      if [ -d "/home/coder/$${WORKER_REPO_NAME}/.git" ]; then
        git -C "/home/coder/$${WORKER_REPO_NAME}" remote set-url origin "$${WORKER_GIT_URL}" 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" pull --ff-only 2>/dev/null || \
          git -C "/home/coder/$${WORKER_REPO_NAME}" pull 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" submodule update --init --recursive || true
      fi
      _chown_coder -R coder:coder "/home/coder/$${WORKER_REPO_NAME}" 2>/dev/null || true
    fi
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
      _chown_coder coder:coder /home/coder/.local 2>/dev/null || true
      curl -fsSL https://cursor.com/install | env HOME=/home/coder USER=coder LOGNAME=coder TAR_OPTIONS=--no-same-owner bash
      _chown_coder -R coder:coder /home/coder/.local /home/coder/.cursor 2>/dev/null || true
    fi
    # Cursor agent installs under HOME/.local/bin; terminals often start as root — symlink into PATH.
    if [ -e /home/coder/.local/bin/agent ]; then
      ln -sf /home/coder/.local/bin/agent /usr/local/bin/agent
    fi
    mkdir -p /home/coder/bin
    _chown_coder coder:coder /home/coder/bin 2>/dev/null || true
    cat > /home/coder/bin/start-cursor-worker <<'WORKERHELPER'
#!/usr/bin/env bash
set -euo pipefail
# Cursor Cloud Agent worker (individual API key; not team --pool). See: https://cursor.com/docs/cli/overview
# Do not use VAR:-default style expansion here: Terraform parses dollar-brace in startup_script and corrupts the helper (e.g. 332REPO_ROOT).
# With set -u, never expand optional env vars directly; use printenv into temp locals.
REPO_ROOT="/home/coder"
WORKER_CWD=$(printenv CURSOR_WORKER_DIR 2>/dev/null || true)
if [ -n "$WORKER_CWD" ]; then
  REPO_ROOT="$WORKER_CWD"
fi
cd "$REPO_ROOT" || { echo "Worker repo not found: $REPO_ROOT (clone a repo or set CURSOR_WORKER_DIR)" >&2; exit 1; }
API_KEY=$(printenv CURSOR_API_KEY 2>/dev/null || true)
if [ -z "$API_KEY" ]; then
  echo "Export CURSOR_API_KEY with your Cursor API key (Dashboard → Cursor Settings → API Keys), then re-run." >&2
  exit 1
fi
EXTRA=()
WORKER_MA=$(printenv CURSOR_WORKER_MANAGEMENT_ADDR 2>/dev/null || true)
WORKER_LF=$(printenv CURSOR_WORKER_LABELS_FILE 2>/dev/null || true)
[ -n "$WORKER_MA" ] && EXTRA+=(--management-addr "$WORKER_MA")
[ -n "$WORKER_LF" ] && EXTRA+=(--labels-file "$WORKER_LF")
exec agent worker start --idle-release-timeout __IDLE_SEC__ "$${EXTRA[@]}" "$@"
WORKERHELPER
    sed -i "s/__IDLE_SEC__/${data.coder_parameter.cursor_worker_idle_timeout.value}/" /home/coder/bin/start-cursor-worker
    if [ -n "$${WORKER_REPO_NAME}" ]; then
      sed -i "s|^REPO_ROOT=\"/home/coder\"|REPO_ROOT=\"/home/coder/$${WORKER_REPO_NAME}\"|" /home/coder/bin/start-cursor-worker
    fi
    chmod 0755 /home/coder/bin/start-cursor-worker 2>/dev/null || true
    # NFS / root_squash: chown may fail; 0755 still lets the coder user run the script as "other"
    _chown_coder coder:coder /home/coder/bin/start-cursor-worker 2>/dev/null || true
    ln -sf /home/coder/bin/start-cursor-worker /usr/local/bin/start-cursor-worker 2>/dev/null || true
    if [ ! -f /home/coder/.cursor-worker-labels.json.example ]; then
      printf "%s\n" \
        "{" \
        "  \"team\": \"your-team\"," \
        "  \"env\": \"coder-workspace\"," \
        "  \"capabilities\": [\"docker\"]" \
        "}" \
        > /home/coder/.cursor-worker-labels.json.example
      _chown_coder coder:coder /home/coder/.cursor-worker-labels.json.example 2>/dev/null || true
    fi
    if [ -f "$CURSOR_SANDBOX_PROFILE" ] && command -v apparmor_parser >/dev/null 2>&1; then
      apparmor_parser -r "$CURSOR_SANDBOX_PROFILE" 2>/dev/null || true
    fi
    # Add ~/.local/bin and ~/bin to PATH for coder user (.bashrc + .profile for login shells e.g. Cursor terminal)
    for f in /home/coder/.bashrc /home/coder/.profile; do
      [ -f "$f" ] || touch "$f"
      grep -qF ".local/bin" "$f" 2>/dev/null || printf "%s\n" "export PATH=\"\$HOME/.local/bin:\$HOME/bin:\$PATH\"" >> "$f"
      grep -qF "GIT_ASKPASS=true" "$f" 2>/dev/null || printf "%s\n" \
        "# DKAI: Coder may set GIT_ASKPASS; use gh/glab credential helpers for GitHub/GitLab HTTPS." \
        "export GIT_ASKPASS=true" >> "$f"
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
    if command -v kubectl >/dev/null 2>&1; then kubectl version --client=true 2>/dev/null | head -n1 || echo "  kubectl: installed"; else echo "  kubectl: not found"; fi
    if command -v kubectx >/dev/null 2>&1; then echo "  kubectx: installed"; else echo "  kubectx: not found"; fi
    if command -v kubens >/dev/null 2>&1; then echo "  kubens: installed"; else echo "  kubens: not found"; fi
    if command -v rancher >/dev/null 2>&1; then rancher --version 2>/dev/null | head -n1 || echo "  rancher: installed"; else echo "  rancher: not found"; fi
    if command -v terraform >/dev/null 2>&1; then terraform version 2>/dev/null | head -n1 || echo "  terraform: installed"; else echo "  terraform: not found"; fi
    if command -v coder >/dev/null 2>&1; then coder version 2>/dev/null | head -n1; else echo "  coder: not found"; fi
    if command -v agent >/dev/null 2>&1; then
      echo -n "  cursor (agent): "
      agent --version 2>/dev/null || echo "(no version string)"
    else
      echo "  cursor (agent): not installed"
    fi
    echo ""
    echo "Tool configs on second PVC: /mnt/coder-tool-config — /root and /home/coder symlink: .kube .config/{gh,glab-cli,coderv2} .rancher"
    echo ""
    echo "=== Cursor Cloud Agent worker (individual API key; not team pool) ==="
    echo "  Docs: https://cursor.com/docs/cli/overview — API key: Dashboard → Cursor Settings → API Keys"
    echo "  Worker repo: cursor_worker_git_url clones to /home/coder/<repo>/, or set CURSOR_WORKER_DIR."
    echo "  Set CURSOR_API_KEY via workspace parameter cursor_api_key, or: export CURSOR_API_KEY=\"<key>\""
    echo "  Optional: export CURSOR_WORKER_LABELS_FILE=/home/coder/.cursor-worker-labels.json"
    echo "  Optional: export CURSOR_WORKER_MANAGEMENT_ADDR=:8080   # /metrics /healthz /readyz"
    echo "  Worker: auto-starts below when cursor_api_key is set; log dumped after worker prints links (wait up to ~30s)"
    echo "  Or run manually: start-cursor-worker"
    echo "  (idle-release-timeout defaults from workspace parameter cursor_worker_idle_timeout)"
    echo ""
    echo "=== Other CLI (gh/glab auth is shared: /home/coder and /root use the same PVC paths) ==="
    echo "  GitHub:  gh auth login   # ok as coder or root; Cursor agent uses HOME=/home/coder"
    echo "  GitLab:  glab auth login"
    echo "  Coder:   this workspace is linked; CLI elsewhere: coder login <your-coder-url>"
    echo ""
    # Cursor worker must run in this same script: a separate coder_script runs in parallel with startup_script and fails.
    # Do not use pkill -f '…agent worker…': that pattern appears in this script's argv and matches the startup shell (SIGTERM).
    if [ -n "$${CURSOR_API_KEY:-}" ] && [ -x /home/coder/bin/start-cursor-worker ]; then
      if [ -f /tmp/cursor-worker.pid ]; then
        read -r oldpid < /tmp/cursor-worker.pid 2>/dev/null || oldpid=
        [ -n "$${oldpid}" ] && kill "$${oldpid}" 2>/dev/null || true
        rm -f /tmp/cursor-worker.pid
      fi
      sleep 1
      export HOME=/home/coder USER=coder LOGNAME=coder
      mkdir -p /home/coder
      if [ -n "$${WORKER_REPO_NAME}" ]; then
        cd "/home/coder/$${WORKER_REPO_NAME}" || cd /home/coder || true
      else
        cd /home/coder || true
      fi
      nohup /home/coder/bin/start-cursor-worker >>/tmp/cursor-worker.log 2>&1 & echo $$! >/tmp/cursor-worker.pid
      echo "cursor_worker: started in background (log: /tmp/cursor-worker.log, pid: /tmp/cursor-worker.pid)"
      # Wait until log has Cursor links (or cap ~30s) — 2s was too short for TLS/handshake.
      # Use brace expansion, not $(seq): some layers strip "$" from "$(..." and bash then sees "(seq..." → error near "(".
      for _attempt in {1..30}; do
        if [ -s /tmp/cursor-worker.log ] && grep -qE "Worker is now running|cursor\\.com/agents" /tmp/cursor-worker.log 2>/dev/null; then
          break
        fi
        sleep 1
      done
      if [ -f /tmp/cursor-worker.log ]; then
        echo ""
        cat /tmp/cursor-worker.log
      fi
    elif [ -z "$${CURSOR_API_KEY:-}" ]; then
      echo "cursor_worker: CURSOR_API_KEY not set; set workspace parameter cursor_api_key to auto-start worker"
    else
      echo "cursor_worker: helper missing at /home/coder/bin/start-cursor-worker"
    fi
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

# Inject worker API key when provided (avoid embedding secrets in startup_script).
# Agent applies coder_env before running startup_script; worker autostart runs at end of startup_script.
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

resource "kubernetes_persistent_volume_claim_v1" "tool_shared_user" {
  count = 1
  lifecycle {
    prevent_destroy = true
  }
  metadata {
    name      = local.tool_config_user_pvc_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc-tool-config-user"
      "app.kubernetes.io/instance" = "coder-pvc-tool-user-${data.coder_workspace_owner.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = true
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "truenas-csi-nfs"
    resources {
      requests = {
        storage = "${data.coder_parameter.tool_config_disk_size.value}Gi"
      }
    }
  }
}

# Adopt pre-existing shared tool PVC into state (second+ workspace, or re-apply after create). Skipped if already in state.
import {
  for_each = local.tool_shared_pvc_import
  to       = kubernetes_persistent_volume_claim_v1.tool_shared_user[0]
  id       = "${var.namespace}/${local.tool_config_user_pvc_name}"
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home,
    kubernetes_persistent_volume_claim_v1.tool_shared_user,
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
          volume_mount {
            mount_path = "/mnt/coder-tool-config"
            name       = "tool-config"
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
        volume {
          name = "tool-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.tool_shared_user[0].metadata[0].name
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
