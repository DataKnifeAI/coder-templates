# Syncing Coder Workspace with Local Machine

This guide covers options for keeping files in sync between a Coder workspace and your local machine (e.g. Arch Linux desktop).

## Prerequisites

- **Coder CLI** installed on your local machine
- **SSH access** to workspaces enabled by your Coder admin
- **SSH config** set up: run `coder config-ssh` (or use Cursor's built-in Coder extension, which configures this automatically)

## Hostname Format

After `coder config-ssh`, workspaces appear in `~/.ssh/config` with hostnames like:

```
coder-vscode.<CODER_URL>--<owner>--<workspace>.<branch>
```

Example: `coder-vscode.coder.example.com--alice--myproject.main`

List your workspaces to find the exact name:

```bash
coder list
# WORKSPACE           TEMPLATE  STATUS   ...
# alice/myproject     dkai-dev  Started  ...
```

---

## Option 1: Manual rsync

**Use case:** One-time or on-demand sync.

**Requirements:** `rsync`, Coder CLI, SSH config.

### Pull from workspace (Coder → local)

```bash
# Replace HOST with your workspace SSH host (e.g. coder-vscode.coder.example.com--alice--myproject.main)
rsync -avz --progress "HOST:/home/coder/project/" ~/local-project/
```

### Push to workspace (local → Coder)

```bash
rsync -avz --progress ~/local-project/ "HOST:/home/coder/project/"
```

### Using coder ssh as transport

If SSH config isn't set up, use the `-e` flag:

```bash
# Pull
rsync -avz -e "coder ssh alice/myproject" --progress coder:~/project/ ~/local-project/

# Push
rsync -avz -e "coder ssh alice/myproject" --progress ~/local-project/ coder:~/project/
```

**Note:** The `coder:` user is implicit; paths are relative to `/home/coder/`.

### Useful rsync flags

| Flag | Description |
|------|-------------|
| `-a` | Archive mode (preserves permissions, timestamps, etc.) |
| `-v` | Verbose |
| `-z` | Compress during transfer |
| `--progress` | Show progress per file |
| `--delete` | Delete files in destination that don't exist in source (use with caution) |
| `--exclude 'node_modules'` | Exclude directories |

---

## Option 2: Cron (scheduled sync)

**Use case:** Periodic sync (e.g. every 5 minutes).

**Requirements:** `rsync`, Coder CLI, SSH config, `cron`.

### Create a sync script

```bash
#!/bin/bash
# ~/bin/coder-sync-pull.sh
HOST="coder-vscode.coder.example.com--alice--myproject.main"
REMOTE="/home/coder/project"
LOCAL="$HOME/coder-sync"

rsync -az --delete "$HOST:$REMOTE/" "$LOCAL/" 2>/dev/null || true
```

### Add to crontab

```bash
crontab -e
```

```
# Every 5 minutes: pull from Coder to ~/coder-sync
*/5 * * * * /home/myuser/bin/coder-sync-pull.sh
```

---

## Option 3: inotifywait (sync on file change)

**Use case:** Sync when files change locally (push to Coder on save).

**Requirements:** `rsync`, `inotify-tools`, Coder CLI, SSH config.

### Arch Linux

```bash
sudo pacman -S inotify-tools
```

### Watch local and push on change

```bash
#!/bin/bash
# ~/bin/coder-sync-watch.sh
HOST="coder-vscode.coder.example.com--alice--myproject.main"
LOCAL="$HOME/my-project"
REMOTE="/home/coder/project"

while inotifywait -r -e modify,create,delete,move "$LOCAL"; do
  rsync -az "$LOCAL/" "$HOST:$REMOTE/"
done
```

Run in background: `nohup ./coder-sync-watch.sh &`

### Watch remote (pull on change)

Requires `inotifywait` on the workspace. The DKAI template doesn't include it by default; you'd need to add it via a startup script or install manually.

---

## Option 4: lsyncd (daemon, batched sync)

**Use case:** Near real-time sync with batching (reduces rsync frequency).

**Requirements:** `lsyncd`, `rsync`, Coder CLI, SSH config.

### Arch Linux

```bash
sudo pacman -S lsyncd
```

### Configuration

Create `/etc/lsyncd/lsyncd.lua`:

```lua
settings {
  logfile = "/var/log/lsyncd.log",
  statusFile = "/var/log/lsyncd-status.log"
}

-- Coder workspace → local (pull)
sync {
  default.rsyncssh,
  source = "/home/coder/project",
  host = "coder-vscode.coder.example.com--alice--myproject.main",
  targetdir = "/home/myuser/coder-sync",
  rsync = { archive = true, compress = true }
}
```

**Note:** `lsyncd` runs as root by default. For user-owned sync, use a user systemd service or adjust paths.

### Start lsyncd

```bash
sudo systemctl enable lsyncd
sudo systemctl start lsyncd
```

---

## Option 5: Bidirectional sync (Unison / Syncthing)

**Use case:** Two-way sync when you edit on both local and remote.

### Unison

```bash
# Arch
sudo pacman -S unison
```

Unison config (`~/.unison/coder.prf`):

```
root = /home/myuser/local-project
root = ssh://coder-vscode.coder.example.com--alice--myproject.main//home/coder/project
```

Run: `unison coder`

### Syncthing

Runs on both machines; requires Syncthing installed in the workspace (e.g. via startup script or Docker). More setup but good for continuous two-way sync.

---

## Summary

| Option | Direction | Latency | Complexity |
|--------|-----------|---------|------------|
| Manual rsync | Either | On demand | Low |
| Cron | Either | Scheduled (e.g. 5 min) | Low |
| inotifywait | Push or pull | Near real-time | Medium |
| lsyncd | Unidirectional | Near real-time (batched) | Medium |
| Unison | Bidirectional | On demand | Medium |
| Syncthing | Bidirectional | Continuous | High |

---

## References

- [Coder SSH access](https://coder.com/docs/workspaces/ssh)
- [rsync man page](https://man.archlinux.org/man/rsync.1)
- [lsyncd](https://github.com/axkibe/lsyncd)
