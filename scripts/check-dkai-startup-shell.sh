#!/usr/bin/env bash
# Approximate Terraform-rendered startup_script and run bash -n.
# Committed main.tf uses $$ and $${ for escaping; Coder receives single $ and ${.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/templates/dkai-arch/main.tf"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

awk '
  /^  startup_script = <<-EOT$/ { p=1; next }
  /^  EOT$/ && p { exit }
  p { sub(/^    /, ""); print }
' "$TF" \
  | sed -e 's/\$\${/\${/g' \
        -e 's/%%{url_effective}/%{url_effective}/g' \
        -e 's/\$\$/\$/g' \
  >"$TMP"

bash -n "$TMP"
echo "OK: rendered dkai-arch startup_script passes bash -n ($TMP)"
