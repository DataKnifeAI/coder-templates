#!/usr/bin/env bash
# Debug a Coder workspace (stuck startup, agent health, recent logs).
# Usage: ./scripts/coder-workspace-debug.sh <workspace-name>
# Requires: coder CLI logged in (`coder login`), optional kubectl for the cluster that hosts workspaces.
set -euo pipefail
WS="${1:?usage: $0 <workspace-name> (e.g. copper-penguin-94)}"

echo "=== coder whoami ==="
coder whoami 2>&1 || true

echo ""
echo "=== coder show $WS ==="
coder show "$WS" 2>&1 || exit 1

echo ""
echo "=== coder logs $WS (last 120 lines) ==="
coder logs "$WS" 2>&1 | tail -120

echo ""
echo "=== grep: error / exit / failed / Script ==="
coder logs "$WS" 2>&1 | rg -i 'error|exit|failed|startup script|coder_script' | tail -40 || true

echo ""
echo "=== optional: kubectl (set KUBE_NS e.g. coder-workspaces, use cluster with workspace pods) ==="
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info &>/dev/null; then
  NS="${KUBE_NS:-coder-workspaces}"
  kubectl get pods -n "$NS" -l "com.coder.workspace.name=$WS" -o wide 2>&1 || echo "(no pods or wrong namespace/context)"
else
  echo "kubectl not configured; skip. To debug pods: kubectl logs -n <ns> deploy/coder-<workspace-id> -c dev"
fi

echo ""
echo "Done. If agent shows 'startup script exited with an error', read full log: coder logs -f $WS"
