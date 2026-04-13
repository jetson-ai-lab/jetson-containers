# Open issues on this repo

Use when the user asks to "open issues", "file issues", "create a batch of issues" on `jetson-ai-lab/jetson-containers`.

## Prefer the helper script over one-off `gh issue create` calls

Repeated `gh issue create` invocations are easy to get wrong (mismatched labels, inconsistent bodies, forgetting the Environment footer from `bug-report.yml`). Use `.claude/skills/cicd/scripts/open-issues.sh` with a manifest file:

```bash
.claude/skills/cicd/scripts/open-issues.sh <manifest.yaml>
```

The script reads a YAML manifest, validates each entry, runs `gh issue create`, and prints a summary of issue URLs. If the manifest defines `defaults.environment_footer`, that block is appended to each body — useful for the repo's `bug-report.yml` Environment section. Bodies are passed through unchanged; the script does not rewrite or prepend to them.

## Manifest format

```yaml
defaults:
  repo: jetson-ai-lab/jetson-containers
  # Footer appended to every body; omit to skip.
  environment_footer: |
    ### Environment
    Jetson Thor, L4T detected R39.0.0, Ubuntu 24.04 noble, SBSA/aarch64,
    CUDA 13.0 (driver), Python 3.12.13.

issues:
  - title: "./build.sh fails on Python 3.12 ..."
    label: bug
    body_file: bodies/01-importlib-abc.md
  - title: "feature: batch verify script ..."
    label: enhancement
    body_file: bodies/02-batch-verify.md
```

Each `body_file` is a markdown file. The script appends the `environment_footer` (if set) but does not modify the body otherwise. Labels must already exist in the repo (run `gh label list` to see available labels: `bug`, `enhancement`, `documentation`, `question`, etc.).

## When to open issues inline vs via script

- **1 issue** → inline `gh issue create --title ... --body-file ...` is fine.
- **≥ 3 issues** → use `.claude/skills/cicd/scripts/open-issues.sh`. Writing a manifest once is faster than remembering to set the label on each call, and the summary output is grep-able.

## Related script: pulling PR review feedback

When the next step after opening issues is reviewing PR feedback (Qodo / Copilot / SonarCloud), use the companion helper:

```bash
.claude/skills/cicd/scripts/pull-pr-review.sh <pr-number> [--repo owner/repo] [--json]
```

It gathers status checks, review comments (with path:line), bot comments, unresolved review-thread IDs (so you can post replies and mark resolved via `gh api graphql`), and SonarCloud issues — all in one shot. Pass `--json` for machine-readable output.

## Repo conventions (from `.github/ISSUE_TEMPLATE/`)

- `bug-report.yml` expects sections: **Bug**, **Environment**, **Additional**. Include them as markdown `###` headings.
- `feature-request.yml` expects: **Feature request** (or description), **Proposed**, **Additional**.
- Labels applied automatically by forms are `bug, triage` (bugs) / `enhancement, triage` (features). Via `gh issue create --label` we set only `bug` or `enhancement` — triage is a maintainer-added label.
- Cross-reference related issues and PRs with `jetson-ai-lab/jetson-containers#N`, not bare `#N` (the latter works in the same repo but is less portable).

## After creating issues

Always print the issue URLs so they're captured in the conversation / PR body.

## Related

- `.claude/skills/jetson-pr.md` — opens PRs after the issues are filed.
