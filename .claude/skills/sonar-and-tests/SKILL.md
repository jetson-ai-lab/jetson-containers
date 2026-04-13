---
name: sonar-and-tests
description: Wire SonarCloud checks locally and add the pytest+coverage job to CI. Use when the user says "wire sonar", "set up sonar locally", "add pytest to CI", "test coverage job", or asks about SonarCloud for jetson-containers.
---

# sonar-and-tests

Closes the gap where SonarCloud findings (permission placement, reraise rules,
SHA pinning) only surface AFTER push, and where `tests/test_cli.py` has no CI
job running it. Adapted from `~/git/culture`'s CI patterns.

## When to invoke

- User asks to add local SonarCloud pre-check capability
- User wants a pytest job added to `pr-on-dev.yml`
- User asks about coverage reports or quality gates for `jetson_cli/`
- PR feedback from SonarCloud is arriving late and creating round-trips

## Two deliverables

This skill produces two repo changes. Make both in one PR.

### 1. Update the existing `sonar-project.properties` at the repo root

The file already exists. Preserve unrelated entries; only merge the keys
below. Expected end state (diff against current content — new lines starred):

```properties
sonar.projectKey=jetson-ai-lab_jetson-containers
sonar.organization=jetson-ai-lab
sonar.sources=jetson_containers,jetson_cli,packages,scripts   # *** add jetson_cli
sonar.tests=tests,test_suite
sonar.python.version=3.10,3.11,3.12
sonar.python.coverage.reportPaths=coverage.xml                # *** add
sonar.exclusions=**/Dockerfile*,**/*.patch,logs/**,data/**,deprecated/**,venv/**,**/__pycache__/**,docs/**,.github/**
sonar.sourceEncoding=UTF-8
sonar.qualitygate.wait=true                                   # *** add (optional — blocks PR merge until gate passes)
```

Do NOT replace the file. Do NOT invent new exclusions (the existing set is
tuned for this repo). Only add the three keys above.

### 2. New job block appended to `.github/workflows/pr-on-dev.yml`

```yaml
  tests-jetson-cli:
    name: Run jetson_cli tests + coverage
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.0
        with:
          fetch-depth: 0  # SonarCloud needs history
      - uses: actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065  # v5.6.0
        with:
          python-version: "3.11"
      - name: Install uv
        run: curl -LsSf https://astral.sh/uv/install.sh | sh
      - name: Install project + test deps
        run: |
          uv venv .venv
          uv pip install -e ".[test]" pytest-cov pytest-xdist
      - name: Run pytest with coverage
        run: |
          .venv/bin/pytest tests/ -n auto \
            --cov=jetson_cli \
            --cov-report=xml:coverage.xml \
            --cov-report=term \
            -v
      - name: SonarCloud scan
        if: always()
        uses: SonarSource/sonarcloud-github-action@master  # pin to SHA before merge
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

Notes on the job:

- **Runs on `ubuntu-latest`**, NOT the self-hosted Jetson runners used by
  `build` — pytest/coverage don't need a device.
- **`fetch-depth: 0`** required by SonarCloud for new-code detection.
- **SonarCloud action left `@master` in this template** — pin to the current
  SHA before merging (matching the SHA-pinning convention from
  `publish.yml`). Fetch with: `gh api repos/SonarSource/sonarcloud-github-action/branches/master --jq .commit.sha`.
- **`SONAR_TOKEN`** must be added as a GitHub repo secret. Generate one at
  <https://sonarcloud.io/account/security> with "Execute Analysis" scope.

## Local pre-push usage

The user's global `sonarclaude` skill (`~/.claude/skills/sonarclaude/`) can
query SonarCloud's API for results on a PR *before* pushing — use it to check
recent findings on a branch. Combined with this CI job, the round-trip cost of
SonarCloud feedback drops from "push → wait for comment" to "push once, see
gate result immediately, or query from local".

## Verification

After adding both files + the SONAR_TOKEN secret:

```bash
# Locally, before pushing:
uv pip install -e ".[test]" pytest-cov
pytest tests/ --cov=jetson_cli --cov-report=term
# Expect: all 4 tests pass, coverage ~100% of the stub

# After pushing to a PR branch:
gh pr checks <pr-number>   # pytest job should be green
# Then SonarCloud quality gate appears as a status check
```

## Scope note

This skill adds a CI-only quality job. It does NOT touch the build-matrix
workflows (`pr-on-dev.yml`'s self-hosted `build` job, `sweep-build-matrix.yml`,
etc.) — those remain for the container packages. The existing
`sonar-project.properties` already scopes SonarCloud to the Python code via
`sonar.sources` / `sonar.exclusions`; this skill just extends `sources` to
include `jetson_cli`.

## Follow-ups

Track in GitHub Issues on `jetson-ai-lab/jetson-containers`.
