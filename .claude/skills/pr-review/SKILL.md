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

## Prerequisites (fail loud if missing)

- `gh auth status` — GitHub CLI authenticated with `repo` scope (needed for the
  `resolveReviewThread` GraphQL mutation).
- `SONAR_TOKEN` env var — see `.claude/skills/sonar-and-tests/SKILL.md` for how
  it's provisioned; project key is `jetson-ai-lab_jetson-containers`.
- Working tree: either clean (PR already open) or with the changes the user wants
  shipped. Do not auto-stash.

If anything is missing, stop and tell the user — do not silently skip a bot.

## Bot account reference

Filter comments by these exact logins:

| Bot | Login | Where comments live |
|---|---|---|
| Qodo Merge | `qodo-merge-pro[bot]` or `CodiumAI-Agent` | issue comments + review comments |
| Copilot PR review | `copilot-pull-request-reviewer[bot]` | review comments |
| SonarCloud | `sonarcloud[bot]` | status check + SonarCloud API |

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

# Qodo (both logins — bot was renamed in the past)
gh api "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.user.login=="qodo-merge-pro[bot]" or .user.login=="CodiumAI-Agent") | {id, body: .body[0:200]}'

# Copilot review comments
gh api "repos/$REPO/pulls/$PR/reviews" \
  --jq '.[] | select(.user.login=="copilot-pull-request-reviewer[bot]") | {id, state, submitted_at}'
gh api "repos/$REPO/pulls/$PR/comments" \
  --jq '.[] | select(.user.login=="copilot-pull-request-reviewer[bot]") | {id, path, line, body: .body[0:200]}'

# SonarCloud — check the status check first
gh pr checks $PR | grep -i sonar

# SonarCloud findings (requires SONAR_TOKEN)
curl -s -u "$SONAR_TOKEN:" \
  "https://sonarcloud.io/api/issues/search?componentKeys=jetson-ai-lab_jetson-containers&pullRequest=$PR&resolved=false" \
  | jq '.issues[] | {key, severity, component, line, message}'
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

## Phase 5 — reply and resolve every thread

Get every review thread and its id:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){
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
  }' -F owner=jetson-ai-lab -F repo=jetson-containers -F pr=$PR
```

Reply, then resolve:

```bash
# Inline review comment reply
gh api "repos/$REPO/pulls/$PR/comments/<comment_databaseId>/replies" \
  -f body='Fixed in <sha>. <1-line explanation>'

# OR top-level PR comment
gh pr comment $PR -b '<bot> pushback: <reason>'

# Resolve the thread
gh api graphql -f query='
  mutation($id:ID!){
    resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } }
  }' -f id=<thread_id>
```

For SonarCloud findings without a PR-thread (project-level issues), reply in a
single summary PR comment listing issue keys + dispositions, and mark the Sonar
issue resolved via `POST /api/issues/do_transition` (transition=`wontfix` for
pushback, `resolve` for fix) using `SONAR_TOKEN`.

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
# Every review thread resolved?
gh api graphql -f query='
  { repository(owner:"jetson-ai-lab",name:"jetson-containers"){
      pullRequest(number:'"$PR"'){
        reviewThreads(first:100){ nodes{ isResolved } } } } }' \
  | jq '.data.repository.pullRequest.reviewThreads.nodes | map(.isResolved) | all'
# -> true

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
