# Open issues on this repo

Use when the user asks to "open issues", "file issues", "create a batch of issues" on `jetson-ai-lab/jetson-containers`.

## Prefer the helper script over one-off `gh issue create` calls

Repeated `gh issue create` invocations are easy to get wrong (mismatched labels, inconsistent bodies, forgetting the Environment footer from `bug-report.yml`). Use `.claude/skills/cicd/scripts/open-issues.sh` with a manifest file:

```bash
.claude/skills/cicd/scripts/open-issues.sh <manifest.yaml>
```

The script reads a YAML manifest, validates each entry, runs `gh issue create`, and prints a summary of issue URLs. It also appends a standard **Environment** footer to each body so the repo's `bug-report.yml` conventions are respected.

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

Each `body_file` is a markdown file. The script prepends a brief header and appends the `environment_footer`. Labels must already exist in the repo (run `gh label list` to see available labels: `bug`, `enhancement`, `documentation`, `question`, etc.).

## When to open issues inline vs via script

- **1 issue** → inline `gh issue create --title ... --body-file ...` is fine.
- **≥ 3 issues** → use `.claude/skills/cicd/scripts/open-issues.sh`. Writing a manifest once is faster than remembering to set the label on each call, and the summary output is grep-able.

## Repo conventions (from `.github/ISSUE_TEMPLATE/`)

- `bug-report.yml` expects sections: **Bug**, **Environment**, **Additional**. Include them as markdown `###` headings.
- `feature-request.yml` expects: **Feature request** (or description), **Proposed**, **Additional**.
- Labels applied automatically by forms are `bug, triage` (bugs) / `enhancement, triage` (features). Via `gh issue create --label` we set only `bug` or `enhancement` — triage is a maintainer-added label.
- Cross-reference related issues and PRs with `jetson-ai-lab/jetson-containers#N`, not bare `#N` (the latter works in the same repo but is less portable).

## After creating issues

Always print the issue URLs so they're captured in the conversation / PR body.

## Related

- `.claude/skills/jetson-pr.md` — opens PRs after the issues are filed.
