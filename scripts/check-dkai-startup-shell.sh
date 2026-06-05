#!/usr/bin/env bash
# Approximate Terraform-rendered startup_script and run bash -n.
# Committed main.tf uses $$ and $${ for escaping; Coder receives single $ and ${.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES=(
  dkai-arch
  dkai-agent
  dkai-hermes
)

for name in "${TEMPLATES[@]}"; do
  TF="$ROOT/templates/$name/main.tf"
  TMP="$(mktemp)"
  awk '
    /^  startup_script = <<-EOT$/ { p=1; next }
    /^  EOT$/ && p { exit }
    p { sub(/^    /, ""); print }
  ' "$TF" \
    | sed -e 's/\$\${/\${/g' \
          -e 's/%%{url_effective}/%{url_effective}/g' \
          -e 's/\$\$/\$/g' \
    | sed '/^%{if/,/^%{endif~}/d' \
    >"$TMP"

  bash -n "$TMP"
  echo "OK: rendered $name startup_script passes bash -n ($TMP)"
  rm -f "$TMP"
done
