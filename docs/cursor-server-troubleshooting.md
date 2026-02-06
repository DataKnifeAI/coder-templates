# Cursor + Coder Workspace — Troubleshooting

## "Cursor Desktop must be installed first"

This error appears when you click **Open in Cursor** in the Coder dashboard but don't have Cursor Desktop installed on your **local machine** (the computer you're using to access Coder).

**Fix:** Install Cursor on your local machine:

- **macOS/Linux:** [https://cursor.com](https://cursor.com) → Download
- **Windows:** [https://cursor.com](https://cursor.com) → Download

The "Open in Cursor" button uses a `cursor://` URL that your OS hands off to the Cursor app. If Cursor isn't installed, the handler isn't registered and you get this message.

---

## "Code server did not start successfully"

When connecting Cursor IDE to a Coder workspace via SSH, you may see:

```
Error installing server: Couldn't install Cursor Server, install script returned non-zero exit status: Code server did not start successfully
```

## Root Cause

Cursor IDE installs a **Cursor Server** on the remote workspace when you connect. Common failure reasons:

### 1. Missing Node.js (most likely)

The `codercom/enterprise-base:ubuntu` image does **not** include Node.js. Cursor Server's bundled Node can fail with "cannot execute: required file not found" on minimal containers. The [Anysphere Remote-SSH extension v0.0.30+](https://forum.cursor.com/t/cannot-ssh-into-remote-server-in-cursor-works-in-vs-code/89655) falls back to **system Node.js 20+** when the bundled Node fails — but the base image has no Node.

**Fix:** The DKAI template installs Node.js 20 in the startup script so Cursor Server can use it.

### 2. Network access (outbound)

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

### 5. Do not add `~/.cursor-server/package.json` with `"type":"module"`

Adding `{"type":"module"}` to `~/.cursor-server/package.json` to fix `SyntaxError: Unexpected token 'export'` causes worse failures:

- **Multiplex server** fails: `ReferenceError: exports is not defined in ES module scope` (it uses CommonJS)
- **Code server** fails: `ERR_MODULE_NOT_FOUND: Cannot find package 'cookie'` (ESM resolution breaks bundled deps)

If you added this workaround, remove it:

```bash
rm -f /home/coder/.cursor-server/package.json
```

Then try connecting again. If you still see the original `export` error, it may be a Cursor version bug — try updating Cursor IDE or report to [Cursor forum](https://forum.cursor.com).

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
