#!/usr/bin/env bash
# Fetch a PR's review feedback in one shot: status checks, review comments
# (with path:line), issue comments (from bots like SonarCloud/Qodo/Copilot),
# and unresolved review-thread IDs (needed to post replies + mark resolved).
#
# Usage:
#   .claude/skills/cicd/scripts/pull-pr-review.sh <pr-number> [--repo owner/repo] [--json]
#
# Default repo comes from `gh repo view --json nameWithOwner`. Output is
# human-readable text unless --json is given, in which case a single JSON
# document is emitted with keys: pr, checks, issue_comments, review_comments,
# review_threads, sonarcloud_issues (if available).
#
# Requires: gh (authenticated), python3 (stdlib only), jq optional.

set -euo pipefail

pr=""
repo=""
json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  repo="$2"; shift 2 ;;
    --json)  json_mode=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *)
      if [[ -z "$pr" ]]; then pr="$1"; shift
      else echo "unexpected arg: $1" >&2; exit 2; fi ;;
  esac
done

if [[ -z "$pr" ]]; then
  echo "usage: $0 <pr-number> [--repo owner/repo] [--json]" >&2
  exit 2
fi

if [[ -z "$repo" ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Gather raw data with gh
gh pr view "$pr" --repo "$repo" \
  --json number,title,url,headRefName,state,comments,statusCheckRollup \
  > "$tmpdir/pr.json"

gh api "repos/$repo/pulls/$pr/comments" --paginate > "$tmpdir/review_comments.json"

# Review threads (for resolving): via GraphQL. Falls back to empty list on error.
gh api graphql -f query='
  query($owner:String!, $name:String!, $pr:Int!) {
    repository(owner:$owner, name:$name) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first:1) { nodes { databaseId author { login } } }
          }
        }
      }
    }
  }' \
  -F owner="${repo%%/*}" -F name="${repo##*/}" -F pr="$pr" \
  > "$tmpdir/threads.json" 2>/dev/null || echo '{}' > "$tmpdir/threads.json"

# SonarCloud PR issues (public endpoint; no auth)
curl -sSL --max-time 10 \
  "https://sonarcloud.io/api/issues/search?componentKeys=$(echo "$repo" | tr / _)&pullRequest=$pr&sinceLeakPeriod=true&ps=500" \
  > "$tmpdir/sonar.json" 2>/dev/null || echo '{}' > "$tmpdir/sonar.json"

python3 - "$tmpdir" "$json_mode" "$repo" "$pr" <<'PY'
import html, json, re, sys
from pathlib import Path

tmpdir, json_mode, repo, pr_num = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]

def strip(s):
    s = re.sub(r'<img[^>]*>', '', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = html.unescape(s)
    # collapse excessive blank lines
    s = re.sub(r'\n{3,}', '\n\n', s).strip()
    return s

def load(name, default):
    try:
        return json.loads((Path(tmpdir) / name).read_text())
    except Exception:
        return default

pr = load('pr.json', {})
review_comments = load('review_comments.json', [])
threads = (load('threads.json', {}).get('data') or {}) \
            .get('repository', {}).get('pullRequest', {}).get('reviewThreads', {}).get('nodes', [])
sonar_issues = load('sonar.json', {}).get('issues', [])

# Normalize data
checks = [
    {
        'name': c.get('name'),
        'status': c.get('status'),
        'conclusion': c.get('conclusion') or '',
    }
    for c in (pr.get('statusCheckRollup') or [])
]

issue_comments = [
    {
        'author': c['author']['login'],
        'created_at': c['createdAt'],
        'body': strip(c['body'])[:4000],
    }
    for c in (pr.get('comments') or [])
]

rc = []
for c in review_comments:
    rc.append({
        'id': c['id'],
        'author': c['user']['login'],
        'path': c['path'],
        'line': c.get('line') or c.get('original_line'),
        'body': strip(c['body']),
        'in_reply_to': c.get('in_reply_to_id'),
        'diff_hunk': c.get('diff_hunk'),
    })

# Match review comments to thread IDs (for resolving)
thread_index = {}
for t in threads:
    for cm in (t.get('comments', {}).get('nodes') or []):
        thread_index[cm['databaseId']] = {'thread_id': t['id'], 'resolved': t['isResolved'], 'path': t.get('path'), 'line': t.get('line')}
for c in rc:
    info = thread_index.get(c['id'])
    if info:
        c['thread_id'] = info['thread_id']
        c['resolved'] = info['resolved']

sonar_norm = [{
    'severity': i.get('severity'),
    'rule': i.get('rule'),
    'component': i.get('component','').split(':',1)[-1],
    'line': i.get('line'),
    'message': i.get('message'),
} for i in sonar_issues]

if json_mode:
    out = {
        'pr': {'number': int(pr_num), 'title': pr.get('title'), 'url': pr.get('url'), 'state': pr.get('state'), 'headRef': pr.get('headRefName')},
        'checks': checks,
        'issue_comments': issue_comments,
        'review_comments': rc,
        'review_threads': [{'id': t['id'], 'resolved': t['isResolved'], 'path': t.get('path'), 'line': t.get('line')} for t in threads],
        'sonarcloud_issues': sonar_norm,
    }
    print(json.dumps(out, indent=2))
    sys.exit(0)

# Human-readable output
print(f"PR #{pr_num}  {pr.get('title')}")
print(f"  state={pr.get('state')}  branch={pr.get('headRefName')}")
print(f"  {pr.get('url')}")
print()

if checks:
    print(f"Checks ({len(checks)}):")
    for c in checks:
        mark = '✓' if c['conclusion'] == 'SUCCESS' else ('—' if c['conclusion'] == 'SKIPPED' else ('✗' if c['conclusion'] else '…'))
        print(f"  {mark} {c['name']:40s} {c['status']:12s} {c['conclusion']}")
    print()

if issue_comments:
    print(f"Issue comments ({len(issue_comments)}):")
    for c in issue_comments:
        head = c['body'].split('\n',1)[0][:120]
        print(f"  [{c['author']}] {head}")
    print()

if rc:
    # Group by author
    by_author = {}
    for c in rc:
        by_author.setdefault(c['author'], []).append(c)
    print(f"Review comments ({len(rc)} across {len(by_author)} reviewer(s)):")
    for author, items in by_author.items():
        print(f"\n  [{author}] ({len(items)})")
        for c in items:
            tag = ''
            if 'resolved' in c:
                tag = '  [RESOLVED]' if c['resolved'] else '  [open]'
            print(f"  -- id={c['id']}{tag}  {c['path']}:{c['line']}")
            for ln in c['body'].splitlines()[:12]:
                print(f"       {ln}")
            if len(c['body'].splitlines()) > 12:
                print(f"       ... (+{len(c['body'].splitlines()) - 12} more lines)")
    print()

if sonar_norm:
    print(f"SonarCloud issues ({len(sonar_norm)}):")
    # Group identical rule:component:message
    from collections import Counter
    cnt = Counter((i['rule'], i['component']) for i in sonar_norm)
    for (rule, component), n in cnt.most_common():
        ex = next(i for i in sonar_norm if i['rule']==rule and i['component']==component)
        suffix = f" x{n}" if n > 1 else ""
        print(f"  [{ex['severity']}] {rule} in {component}{suffix}")
        print(f"       {ex['message']}")
    print()

# Tips for next actions
open_threads = [c for c in rc if not c.get('resolved', True) and not c.get('in_reply_to')]
if open_threads:
    print(f"Unresolved threads needing reply ({len(open_threads)}):")
    for c in open_threads:
        print(f"  reply: gh api --method POST repos/{repo}/pulls/{pr_num}/comments/{c['id']}/replies -f body=\"...\"")
        if c.get('thread_id'):
            print(f"  resolve: gh api graphql -f query='mutation {{resolveReviewThread(input:{{threadId:\"{c['thread_id']}\"}}) {{thread{{isResolved}}}}}}'")
    print()
PY
