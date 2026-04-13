#!/usr/bin/env bash
# Bulk-open GitHub issues from a YAML manifest.
#
# Usage: scripts/open_issues.sh <manifest.yaml>
# Requires: gh (authenticated), python3 with PyYAML.
#
# Manifest format (see .claude/skills/open-issue.md):
#   defaults:
#     repo: owner/repo
#     environment_footer: |
#       ### Environment
#       ...
#   issues:
#     - title: "..."
#       label: bug            # or enhancement, documentation, etc.
#       body_file: path.md    # relative to the manifest's directory

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <manifest.yaml>" >&2
  exit 2
fi

manifest="$1"
if [[ ! -f "$manifest" ]]; then
  echo "error: manifest not found: $manifest" >&2
  exit 2
fi

command -v gh >/dev/null || { echo "error: gh not installed" >&2; exit 2; }
command -v python3 >/dev/null || { echo "error: python3 not installed" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "error: python3 PyYAML not installed (pip install pyyaml)" >&2; exit 2; }

manifest_dir=$(dirname "$(readlink -f "$manifest")")

# Emit one tab-separated record per issue: title \t label \t body_path
# and a final 'FOOTER:' line (possibly empty) with the footer text base64-encoded.
parsed=$(python3 - "$manifest" "$manifest_dir" <<'PY'
import base64, os, sys, yaml
path, root = sys.argv[1], sys.argv[2]
with open(path) as f:
    doc = yaml.safe_load(f)
defaults = doc.get('defaults') or {}
repo = defaults.get('repo')
if not repo:
    sys.exit("manifest missing defaults.repo")
footer = defaults.get('environment_footer', '') or ''
issues = doc.get('issues') or []
if not issues:
    sys.exit("manifest has no issues")
print(f"REPO\t{repo}")
print(f"FOOTER\t{base64.b64encode(footer.encode()).decode()}")
for i, it in enumerate(issues, 1):
    title = it.get('title')
    label = it.get('label', '')
    body_file = it.get('body_file')
    if not title or not body_file:
        sys.exit(f"issue {i} missing title or body_file")
    body_path = os.path.join(root, body_file)
    if not os.path.isfile(body_path):
        sys.exit(f"issue {i}: body file not found: {body_path}")
    print(f"ISSUE\t{title}\t{label}\t{body_path}")
PY
)

repo=$(grep -m1 '^REPO\b' <<<"$parsed" | cut -f2-)
footer_b64=$(grep -m1 '^FOOTER\b' <<<"$parsed" | cut -f2-)
footer=$(printf '%s' "$footer_b64" | base64 -d)

mapfile -t rows < <(grep '^ISSUE\b' <<<"$parsed")
count=${#rows[@]}

echo "opening $count issue(s) on $repo..."
urls=()
idx=0
for row in "${rows[@]}"; do
  idx=$((idx+1))
  IFS=$'\t' read -r _ title label body_path <<<"$row"
  tmp_body=$(mktemp)
  cat "$body_path" > "$tmp_body"
  if [[ -n "$footer" ]]; then
    printf '\n%s\n' "$footer" >> "$tmp_body"
  fi
  echo "-> [$idx/$count] $title"
  if [[ -n "$label" ]]; then
    url=$(gh issue create --repo "$repo" --title "$title" --label "$label" --body-file "$tmp_body" | tail -1)
  else
    url=$(gh issue create --repo "$repo" --title "$title" --body-file "$tmp_body" | tail -1)
  fi
  urls+=("$url")
  rm -f "$tmp_body"
done

echo
echo "Created $count issue(s):"
for u in "${urls[@]}"; do
  echo "  $u"
done
