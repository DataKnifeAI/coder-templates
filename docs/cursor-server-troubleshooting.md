# Cursor Server Not Starting — Troubleshooting

When connecting Cursor IDE to a Coder workspace via SSH, you may see:

```
Error installing server: Couldn't install Cursor Server, install script returned non-zero exit status: Code server did not start successfully
```

## Root Cause

Cursor IDE installs a **Cursor Server** on the remote workspace when you connect. Common failure reasons:

### 1. Missing Node.js (most likely)

The `codercom/enterprise-base:ubuntu` image does **not** include Node.js. Cursor Server's bundled Node can fail with "cannot execute: required file not found" on minimal containers. The [Anysphere Remote-SSH extension v0.0.30+](https://forum.cursor.com/t/cannot-ssh-into-remote-server-in-cursor-works-in-vs-code/89655) falls back to **system Node.js 20+** when the bundled Node fails — but the base image has no Node.

**Fix:** The DKAI template installs Node.js 20 in the startup script so Cursor Server can use it.

### 2. Network access

The workspace must reach `cursor.blob.core.windows.net` to download the server. If the cluster has network policies or no outbound internet:

```bash
# From workspace terminal (coder ssh or web terminal)
curl -I https://cursor.blob.core.windows.net
```

### 3. Disk space

Ensure `/home/coder` and `/tmp` have space. Cursor Server writes to `~/.cursor-server/`.

```bash
df -h /home/coder /tmp
```

### 4. Architecture mismatch

Verify the image matches Cursor's expected arch:

```bash
uname -a
# Should be x86_64 or aarch64
```

## Verify from workspace

SSH into the workspace and run:

```bash
# Check Node.js (required for Cursor Server fallback)
node --version   # Should be v20+

# Check Cursor Server install
ls -la ~/.cursor-server/bin/

# Test bundled Node (if present)
~/.cursor-server/bin/*/node -e 'console.log("ok")' 2>/dev/null || echo "Bundled node failed - system node used"
```

## References

- [Cursor Remote SSH — NixOS fix (Node fallback)](https://forum.cursor.com/t/cannot-ssh-into-remote-server-in-cursor-works-in-vs-code/89655)
- [Cursor + Coder](https://coder.com/docs/user-guides/workspace-access/cursor)
- [Coder enterprise-base image](https://github.com/coder/images/tree/main/images/base)
