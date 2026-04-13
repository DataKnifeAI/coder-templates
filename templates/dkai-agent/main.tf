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

data "coder_parameter" "cli_config_disk_size" {
  name         = "cli_config_disk_size"
  display_name = "CLI config disk (kubectl, gh, glab, rancher)"
  description  = "Second persistent volume (NFS) for CLI credentials and configs. Symlinked: ~/.kube, ~/.config/gh, ~/.config/glab, ~/.rancher. Size in GB (can only be increased after creation)."
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
  description  = "After a Cloud Agent session ends, keep the worker connected this many seconds for follow-ups (see `agent worker start --help`). Used by ~/bin/start-cursor-worker (not team pool mode)."
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
  description  = "HTTPS URL cloned with: cd /home/coder && git clone <url> (repo appears as /home/coder/<name>, e.g. agent-workspace). Set empty to skip auto-clone."
  type         = "string"
  form_type    = "input"
  default      = "https://github.com/DataKnifeAI/agent-workspace.git"
  mutable      = true
  icon         = "/icon/github.svg"
}

data "coder_parameter" "cursor_api_key" {
  name         = "cursor_api_key"
  display_name = "Cursor API key"
  description  = "Optional. Your individual Cursor API key — sets CURSOR_API_KEY (coder_env) and auto-starts `agent worker start` (without --pool) when set. Create under Cursor Dashboard → Settings → Cursor Settings → API Keys. Usage is billed to your account; not team pool / service-account workers. Leave empty to export manually. Stored on the workspace; prefer org secret stores for production."
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
      apparmor bash binutils curl git kubectl nodejs zstd
    # Git 2.35+: "dubious ownership" when .git owner != invoking user (NFS root_squash → nobody, or root in a coder-owned tree).
    git config --system --add safe.directory '*' 2>/dev/null || true
    # Optional CLI downloads must not fail the whole startup (set -e): network blips, bad semver, etc.
    set +e
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
    # kubectl: installed from Arch extra (pacman above). Avoid dl.k8s.io curl — flaky behind some networks.
    # Rancher CLI (latest linux-amd64 .tar.gz from GitHub releases)
    if ! command -v rancher >/dev/null 2>&1; then
      python3 -c "import json,urllib.request;r=json.load(urllib.request.urlopen('https://api.github.com/repos/rancher/cli/releases/latest'));a=[x for x in r['assets'] if 'linux-amd64' in x['name'] and x['name'].endswith('.tar.gz')];print(a[0]['browser_download_url'] if a else '')" > /tmp/dkai-rancher-url 2>/dev/null || true
      read -r RANCHER_DL < /tmp/dkai-rancher-url || true
      if [ -n "$$RANCHER_DL" ] && curl -fsSL "$$RANCHER_DL" -o /tmp/rancher-cli.tgz; then
        mkdir -p /tmp/rancher-extract
        tar -xzf /tmp/rancher-cli.tgz -C /tmp/rancher-extract
        find /tmp/rancher-extract -name rancher -type f 2>/dev/null | head -n1 > /tmp/dkai-rancher-binpath
        read -r RBIN < /tmp/dkai-rancher-binpath
        if [ -n "$$RBIN" ]; then
          install -m 0755 "$$RBIN" /usr/local/bin/rancher
        fi
        rm -f /tmp/dkai-rancher-binpath
        rm -rf /tmp/rancher-cli.tgz /tmp/rancher-extract
      fi
    fi
    set -e
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
    # Second PVC (/mnt/coder-cli-config): persist kube + gh + glab + rancher configs (symlinks from ~).
    mkdir -p /mnt/coder-cli-config/kube /mnt/coder-cli-config/config/gh /mnt/coder-cli-config/config/glab /mnt/coder-cli-config/rancher
    chown -R coder:coder /mnt/coder-cli-config 2>/dev/null || true
    mkdir -p /home/coder/.config
    if [ -d /home/coder/.kube ] && [ ! -L /home/coder/.kube ]; then
      cp -a /home/coder/.kube/. /mnt/coder-cli-config/kube/ 2>/dev/null || true
      rm -rf /home/coder/.kube
    fi
    ln -sfn /mnt/coder-cli-config/kube /home/coder/.kube
    if [ -d /home/coder/.config/gh ] && [ ! -L /home/coder/.config/gh ]; then
      cp -a /home/coder/.config/gh/. /mnt/coder-cli-config/config/gh/ 2>/dev/null || true
      rm -rf /home/coder/.config/gh
    fi
    ln -sfn /mnt/coder-cli-config/config/gh /home/coder/.config/gh
    if [ -d /home/coder/.config/glab ] && [ ! -L /home/coder/.config/glab ]; then
      cp -a /home/coder/.config/glab/. /mnt/coder-cli-config/config/glab/ 2>/dev/null || true
      rm -rf /home/coder/.config/glab
    fi
    ln -sfn /mnt/coder-cli-config/config/glab /home/coder/.config/glab
    if [ -d /home/coder/.rancher ] && [ ! -L /home/coder/.rancher ]; then
      cp -a /home/coder/.rancher/. /mnt/coder-cli-config/rancher/ 2>/dev/null || true
      rm -rf /home/coder/.rancher
    fi
    ln -sfn /mnt/coder-cli-config/rancher /home/coder/.rancher
    chown -R coder:coder /mnt/coder-cli-config /home/coder/.kube /home/coder/.config /home/coder/.rancher 2>/dev/null || true
    # Default repo for Cloud Agent worker: clone under /home/coder/<repo-name> (not under ~/git).
    mkdir -p /home/coder
    chown coder:coder /home/coder 2>/dev/null || true
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
        chown -R coder:coder "/home/coder/$${WORKER_REPO_NAME}" 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" remote add origin "$${WORKER_GIT_URL}" 2>/dev/null || \
          git -C "/home/coder/$${WORKER_REPO_NAME}" remote set-url origin "$${WORKER_GIT_URL}"
      fi
      if [ -d "/home/coder/$${WORKER_REPO_NAME}/.git" ]; then
        git -C "/home/coder/$${WORKER_REPO_NAME}" remote set-url origin "$${WORKER_GIT_URL}" 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" pull --ff-only 2>/dev/null || \
          git -C "/home/coder/$${WORKER_REPO_NAME}" pull 2>/dev/null || true
        git -C "/home/coder/$${WORKER_REPO_NAME}" submodule update --init --recursive || true
      fi
      chown -R coder:coder "/home/coder/$${WORKER_REPO_NAME}" 2>/dev/null || true
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
    chown coder:coder /home/coder/bin/start-cursor-worker 2>/dev/null || true
    ln -sf /home/coder/bin/start-cursor-worker /usr/local/bin/start-cursor-worker 2>/dev/null || true
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
    if command -v kubectl >/dev/null 2>&1; then kubectl version --client=true 2>/dev/null | head -n1 || echo "  kubectl: installed"; else echo "  kubectl: not found"; fi
    if command -v rancher >/dev/null 2>&1; then rancher --version 2>/dev/null | head -n1 || echo "  rancher: installed"; else echo "  rancher: not found"; fi
    if command -v coder >/dev/null 2>&1; then coder version 2>/dev/null | head -n1; else echo "  coder: not found"; fi
    if command -v agent >/dev/null 2>&1; then
      echo -n "  cursor (agent): "
      agent --version 2>/dev/null || echo "(no version string)"
    else
      echo "  cursor (agent): not installed"
    fi
    echo ""
    echo "CLI configs persist on second PVC: /mnt/coder-cli-config (symlinks: ~/.kube ~/.config/gh ~/.config/glab ~/.rancher)"
    echo ""
    echo "=== Cursor Cloud Agent worker (individual API key; not team pool) ==="
    echo "  Docs: https://cursor.com/docs/cli/overview — API key: Dashboard → Cursor Settings → API Keys"
    echo "  Worker repo: cursor_worker_git_url clones to /home/coder/<repo>/, or set CURSOR_WORKER_DIR."
    echo "  Set CURSOR_API_KEY via workspace parameter cursor_api_key, or: export CURSOR_API_KEY=\"<key>\""
    echo "  Optional: export CURSOR_WORKER_LABELS_FILE=/home/coder/.cursor-worker-labels.json"
    echo "  Optional: export CURSOR_WORKER_MANAGEMENT_ADDR=:8080   # /metrics /healthz /readyz"
    echo "  Worker: auto-starts below when cursor_api_key is set; /tmp/cursor-worker.log contents follow"
    echo "  Or run manually: start-cursor-worker"
    echo "  (idle-release-timeout defaults from workspace parameter cursor_worker_idle_timeout)"
    echo ""
    echo "=== Other CLI (run as the workspace user) ==="
    echo "  GitHub:  gh auth login"
    echo "  GitLab:  glab auth login"
    echo "  Coder:   this workspace is linked; CLI elsewhere: coder login <your-coder-url>"
    echo ""
    # Cursor worker must run in this same script: a separate coder_script runs in parallel with startup_script and fails.
    # Do not use pkill -f '…agent worker…': that pattern appears in this script's argv and matches the startup shell (SIGTERM).
    if [ -n "$${CURSOR_API_KEY:-}" ] && [ -x /home/coder/bin/start-cursor-worker ]; then
      if [ -f /tmp/cursor-worker.pid ]; then
        read -r oldpid < /tmp/cursor-worker.pid 2>/dev/null || oldpid=
        [ -n "$$oldpid" ] && kill "$$oldpid" 2>/dev/null || true
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
      sleep 2
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

resource "kubernetes_persistent_volume_claim_v1" "cli_config" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-cli-config"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc-cli-config"
      "app.kubernetes.io/instance" = "coder-pvc-cli-${data.coder_workspace.me.id}"
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
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "truenas-csi-nfs"
    resources {
      requests = {
        storage = "${data.coder_parameter.cli_config_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.home,
    kubernetes_persistent_volume_claim_v1.cli_config,
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
            mount_path = "/mnt/coder-cli-config"
            name       = "cli-config"
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
          name = "cli-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.cli_config.metadata.0.name
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
