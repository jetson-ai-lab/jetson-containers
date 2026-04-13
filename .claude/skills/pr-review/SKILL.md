---
name: pr-review
description: End-to-end PR bot-review triage for jetson-ai-lab/jetson-containers. Use when the user says "review my PR", "triage bot comments", "handle Qodo/Copilot/Sonar feedback", or invokes `/pr-review`. Branches+pushes if needed, opens the PR, waits for Qodo + Copilot + SonarCloud, then enters plan mode to fix/pushback/defer each finding and files follow-up issues.
---

# pr-review

Closes the loop on PR bot feedback so comments don't stagnate and out-of-scope
findings don't get lost. Drives Qodo Merge, GitHub Copilot PR review, and
SonarCloud from "PR open" → "every thread resolved, every deferral in Issues".

## When to invoke

- User says "review my PR" / "go through the bot comments" / "/pr-review".
- User just pushed changes and wants the bot feedback triaged end-to-end.
- Existing PR has unresolved Qodo/Copilot/Sonar threads the user wants cleaned up.

## Prerequisites

**Required:**

- `gh auth status` — GitHub CLI authenticated with `repo` scope (needed for the
  `resolveReviewThread` GraphQL mutation). If missing, stop and tell the user.

**Optional (degrades gracefully):**

- `SONAR_TOKEN` env var — only needed to query SonarCloud's API directly or to
  transition Sonar issues (`do_transition`). If unset, fall back to reading
  `sonarqubecloud[bot]`'s PR summary comment + the `SonarCloud Code Analysis`
  status check; skip the API-only steps and say so in the final report.
  See `.claude/skills/sonar-and-tests/SKILL.md`; project key is
  `jetson-ai-lab_jetson-containers`.

**Working tree:** either clean (PR already open) or holding the changes the user
wants shipped. Do not auto-stash.

## Bot account reference

Filter comments by these exact logins (verified on this repo):

| Bot | Login | Where comments live |
|---|---|---|
| Qodo Merge | `qodo-code-review[bot]` (historically also `qodo-merge-pro[bot]` / `CodiumAI-Agent`) | issue comments **and** inline review comments |
| Copilot PR review | `copilot-pull-request-reviewer[bot]` (author field may appear as `Copilot`) | review comments + review-summary body |
| SonarCloud | `sonarqubecloud[bot]` (historically `sonarcloud[bot]`) | status check + single PR summary comment |

## Phase 1 — branch + PR (skip if a PR for this branch already exists)

Detect state:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
gh pr view --json number,state,headRefName 2>/dev/null
```

If a PR already exists and is open, record `PR=$(gh pr view --json number -q .number)` and skip to Phase 2.

Otherwise defer to the **`jetson-pr`** skill for branch naming, commit style, and
PR body template — do not duplicate it here. The short version:

- If on `dev`/`master` or a protected branch: `git checkout -b <slug>` off `dev`.
- Commit staged work (lowercase imperative subject, no period, no `--no-verify`).
- `git push -u origin HEAD`
- `gh pr create --base dev --title '...' --body '...'`
- `PR=$(gh pr view --json number -q .number)`

## Phase 2 — wait for bots

The 5-minute floor is required: Qodo/Copilot/Sonar don't all post simultaneously.

```bash
# Minimum wait: 5 min. Use the harness sleep / ScheduleWakeup — do not tight-poll.
sleep 300
```

Then check each bot. Re-check every ~2 min up to a 10-minute ceiling:

```bash
REPO=jetson-ai-lab/jetson-containers

# Shared login filter — covers historical renames
QODO='.user.login=="qodo-code-review[bot]" or .user.login=="qodo-merge-pro[bot]" or .user.login=="CodiumAI-Agent"'
COPILOT='.user.login=="copilot-pull-request-reviewer[bot]" or .user.login=="Copilot"'
SONAR='.user.login=="sonarqubecloud[bot]" or .user.login=="sonarcloud[bot]"'

# Qodo — posts BOTH issue-level and inline review comments
gh api "repos/$REPO/issues/$PR/comments" \
  --jq ".[] | select($QODO) | {id, body: .body[0:200]}"
gh api "repos/$REPO/pulls/$PR/comments" \
  --jq ".[] | select($QODO) | {id, path, line, body: .body[0:200]}"

# Copilot — summary review body + inline review comments
gh api "repos/$REPO/pulls/$PR/reviews" \
  --jq ".[] | select($COPILOT) | {id, state, submitted_at}"
gh api "repos/$REPO/pulls/$PR/comments" \
  --jq ".[] | select($COPILOT) | {id, path, line, body: .body[0:200]}"

# SonarCloud — status check + single summary issue comment
gh pr checks $PR | grep -i sonar
gh api "repos/$REPO/issues/$PR/comments" \
  --jq ".[] | select($SONAR) | {id, body: .body[0:500]}"

# SonarCloud API — only if SONAR_TOKEN is set (otherwise the bot comment above is enough)
if [ -n "$SONAR_TOKEN" ]; then
  curl -s -u "$SONAR_TOKEN:" \
    "https://sonarcloud.io/api/issues/search?componentKeys=jetson-ai-lab_jetson-containers&pullRequest=$PR&resolved=false" \
    | jq '.issues[] | {key, severity, component, line, message}'
fi
```

Move on once the 5-minute floor passed AND at least one signal per bot has
arrived (or the 10-minute ceiling hit — note missing bots in the final report).

## Phase 3 — triage in plan mode

Enter plan mode. Build one table per bot:

| comment_id / issue_key | path:line | severity | summary | action |
|---|---|---|---|---|
| … | … | … | … | fix / pushback / defer |

Action buckets:

- **fix** — bot is right, change fits this PR's scope. Edit the code.
- **pushback** — bot is wrong (false positive, upstream constraint, repo style).
  Reply must cite the constraint (file:line or upstream link), not just "won't fix".
- **defer** — valid but out-of-scope for this PR. Route to a follow-up issue.

Do not call `ExitPlanMode` until every finding is assigned a bucket.

## Phase 4 — apply fixes

- Batch edits into one commit per logical group, not per comment.
- Use the `jetson-pr` commit style. Reference comment ids in the body, e.g.
  `addresses qodo #<id>, sonar python:S5754`.
- `git push`

## Phase 5 — reply and resolve

**What can be "resolved" vs just "replied":**

- **Review threads** (inline code comments on a PR) — have a `thread_id` and
  are resolvable via the `resolveReviewThread` GraphQL mutation.
- **Issue comments** (top-level PR conversation: Qodo summary, Copilot summary,
  SonarCloud summary comment) — are **not** resolvable. Reply with a new issue
  comment to close the loop; they collapse naturally once acknowledged.

**Scope of resolution:** only auto-reply/resolve threads whose root comment
author is in the bot-login table above. If a thread is authored by a human
reviewer, stop and ask the user — do not auto-resolve human feedback.

### Fetch every review thread (paginated)

```bash
cursor=
all_threads='[]'
while :; do
  args=(-F owner=jetson-ai-lab -F repo=jetson-containers -F pr="$PR")
  [ -n "$cursor" ] && args+=(-F cursor="$cursor")

  resp=$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          reviewThreads(first:100, after:$cursor){
            pageInfo{ hasNextPage endCursor }
            nodes{
              id
              isResolved
              comments(first:1){
                nodes{ databaseId author{login} path body }
              }
            }
          }
        }
      }
    }' "${args[@]}")

  all_threads=$(jq -s '.[0] + .[1]' \
    <(printf '%s' "$all_threads") \
    <(printf '%s' "$resp" | jq '.data.repository.pullRequest.reviewThreads.nodes'))

  [ "$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')" = "true" ] || break
  cursor=$(printf '%s' "$resp" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
done

# Keep only bot-authored, unresolved threads
BOT_RE='^(qodo-code-review\[bot\]|qodo-merge-pro\[bot\]|CodiumAI-Agent|copilot-pull-request-reviewer\[bot\]|Copilot|sonarqubecloud\[bot\]|sonarcloud\[bot\])$'
printf '%s' "$all_threads" \
  | jq --arg re "$BOT_RE" '
      map(select(.isResolved == false
                 and (.comments.nodes[0].author.login | test($re))))'
```

### Reply, then resolve

```bash
# Inline review comment reply — path is PR-scoped per GitHub REST docs:
# POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies
gh api "repos/$REPO/pulls/$PR/comments/<comment_databaseId>/replies" \
  -f body='Fixed in <sha>. <1-line explanation>'

# Top-level PR issue-comment reply (Qodo/Copilot/Sonar summary comments)
gh pr comment $PR -b '<bot> summary: fixed <N>, pushed back <N>, deferred <N>. <links>'

# Resolve the review thread (inline only — not for issue comments)
gh api graphql -f query='
  mutation($id:ID!){
    resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } }
  }' -f id=<thread_id>
```

### SonarCloud specifics

SonarCloud findings do not live on review threads. Two cases:

- **Quality Gate passed, 0 new issues** — nothing to resolve; note in final report.
- **Findings present** — reply with a single top-level PR comment listing issue
  keys + disposition (fixed/pushback/defer). If `SONAR_TOKEN` is set, also
  `POST /api/issues/do_transition` (transition=`wontfix` for pushback,
  `resolve` for fix). Without `SONAR_TOKEN`, leave the Sonar-side state alone
  and rely on the next scan (after the fix commit) to clear the issue.

## Phase 6 — follow-up issues for deferred items

For every row bucketed as **defer**:

```bash
gh issue create --repo jetson-ai-lab/jetson-containers \
  --title '<verb> <scope>: <short summary>' \
  --label 'follow-up,bot-review' \
  --body "$(cat <<EOF
Deferred from #$PR.

**Source:** <Qodo|Copilot|SonarCloud> — <comment URL or issue key>
**Path:** \`<file>:<line>\`
**Finding:** <bot's summary>
**Why deferred:** <scope / risk / dependency>
**Suggested package/owner:** <package path or maintainer>
EOF
)"
```

Reply on the original thread with the new issue URL, then resolve the thread.

If Issues are disabled on the repo (same caveat as `release-jetson-cli`), stop
and tell the maintainer to enable them. Do NOT dump follow-ups into PR comments
or a markdown file in the repo.

## Verification

After the skill completes:

```bash
# Every bot-authored review thread resolved? (reuses the paginated fetch + BOT_RE
# filter from Phase 5 — then assert all remaining unresolved threads are human)
printf '%s' "$all_threads" \
  | jq --arg re "$BOT_RE" '
      [ .[] | select(.comments.nodes[0].author.login | test($re)) | .isResolved ]
      | all'
# -> true  (any remaining unresolved threads belong to human reviewers and are out of scope)

# Deferred items filed?
gh issue list --repo jetson-ai-lab/jetson-containers \
  --label follow-up --search "PR #$PR in:body" --state open
```

Report back to the user: count fixed / count pushed-back / count deferred (with
issue links), and the PR's current CI + SonarCloud gate state.

## Scope note

This skill is for **triage**, not merge. It does not approve, merge, or
force-push. If CI is red after fixes, hand off — don't retry in a loop.

## See also

- `.claude/skills/jetson-pr.md` — branch/commit/PR-body conventions.
- `.claude/skills/sonar-and-tests/SKILL.md` — `SONAR_TOKEN` setup + Sonar project key.
- `.claude/skills/release-jetson-cli/SKILL.md` — follow-up-issue policy this skill inherits.
