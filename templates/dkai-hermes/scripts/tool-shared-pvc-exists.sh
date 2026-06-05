#!/bin/sh
# Plan-time check: does coder-<owner-id>-tool-config PVC already exist?
# Args: $1=namespace $2=pvc_name $3=use_kubeconfig(true|false) $4=kubeconfig path
# Prints JSON: {"exists":"true"} or {"exists":"false"}
# Exit 1 if existence cannot be determined (avoid silent wrong branch → AlreadyExists).
set -eu
NS=$1
NAME=$2
USE_KUBECONFIG=$3
KUBECONFIG_PATH=$4

# 1) In-cluster Kubernetes API (matches provider when use_kubeconfig is false)
if [ -r /var/run/secrets/kubernetes.io/serviceaccount/token ] && [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "tool_shared_pvc_exists: in-cluster check needs curl in PATH" >&2
    exit 1
  fi
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  PORT=443
  [ -n "${KUBERNETES_SERVICE_PORT:-}" ] && PORT=${KUBERNETES_SERVICE_PORT}
  API="https://${KUBERNETES_SERVICE_HOST}:${PORT}"
  URL="${API}/api/v1/namespaces/${NS}/persistentvolumeclaims/${NAME}"
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$CA" -H "Authorization: Bearer $TOKEN" "$URL" || echo "000")
  case "$CODE" in
    200) echo '{"exists":"true"}'; exit 0 ;;
    404) echo '{"exists":"false"}'; exit 0 ;;
    000)
      echo "tool_shared_pvc_exists: curl failed calling Kubernetes API" >&2
      exit 1
      ;;
    *)
      echo "tool_shared_pvc_exists: unexpected HTTP ${CODE} from ${URL} (need get on persistentvolumeclaims)" >&2
      exit 1
      ;;
  esac
fi

# 2) Host kubeconfig / kubectl
if command -v kubectl >/dev/null 2>&1; then
  if [ "$USE_KUBECONFIG" = "true" ] && [ -f "$KUBECONFIG_PATH" ]; then
    export KUBECONFIG="$KUBECONFIG_PATH"
  fi
  if kubectl get pvc -n "$NS" "$NAME" >/dev/null 2>&1; then
    echo '{"exists":"true"}'
  else
    echo '{"exists":"false"}'
  fi
  exit 0
fi

echo "tool_shared_pvc_exists: need in-cluster ServiceAccount + curl, or kubectl in PATH" >&2
exit 1
