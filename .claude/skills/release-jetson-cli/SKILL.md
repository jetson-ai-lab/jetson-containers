---
name: release-jetson-cli
description: Publish the `jetson-cli` and `jetson-containers` PyPI distributions. Use when the user says "release jetson-cli", "publish to pypi", "cut a jetson release", or asks about PyPI trusted publishing for this repo.
---

# release-jetson-cli

End-to-end release workflow for the two PyPI distributions that both ship the
`jetson` console command from `jetson_cli/`. The full playbook lives in
[docs/releasing-pypi.md](../../../docs/releasing-pypi.md) — this skill just
tells you which branch to use and in what order.

## When to invoke

- User asks to cut a release (Test-PyPI, PyPI dev stream, or PyPI stable)
- User asks about the PR → Test-PyPI auto-publish or the dev-stream channel
- User is troubleshooting the publish workflow
- User asks about trusted-publisher configuration

## One-time setup check (ask the user if first-time release)

Confirm the prerequisites are done before running any workflow:

1. **Four pending publishers registered** — table in `docs/releasing-pypi.md`. If the repo admin hasn't done this, the workflow fails with "Trusted publishing exchange failure" on the first run.
2. **Two GitHub Environments exist** — `testpypi` and `pypi` under repo Settings → Environments. No secrets inside.

If either is missing, STOP and tell the user (or maintainer) what to configure. Don't attempt to run the workflow.

## Channels (branch-driven)

`<base>` = `version = "X.Y.Z"` in `pyproject.toml`. `<N>` = `github.run_number`.

| Event | Version | Where |
|---|---|---|
| Same-repo PR | `<base>.dev<N>` | Test-PyPI (auto) |
| Merge to `dev` | `<base>.dev<N>` | PyPI (dev stream, auto) |
| Merge to `master` | `<base>` | PyPI (stable, auto) |
| `workflow_dispatch` → `testpypi` | `<base>.dev<N>` | Test-PyPI (manual) |
| `workflow_dispatch` → `pypi` | `<base>.dev<N>` | PyPI (manual) |

Fork PRs build but skip publish (OIDC token not granted to fork-triggered
runs). For a fork-reviewer install, fall back to `workflow_dispatch`.

### PR → Test-PyPI

Nothing to do — push the PR and the publish step runs automatically. Verify
the version appears at `https://test.pypi.org/project/jetson-cli/<base>.dev<N>/`.

Install-check (clean venv):

```bash
uv venv /tmp/verify --seed
/tmp/verify/bin/pip install --index-url https://test.pypi.org/simple/ \
                           --extra-index-url https://pypi.org/simple/ \
                           jetson-cli==<base>.dev<N>
/tmp/verify/bin/jetson --version   # -> jetson <base>.dev<N>
```

### Dev stream (merge to `dev`)

Merging to `dev` publishes `<base>.dev<N>` to **PyPI** (not Test-PyPI).
Consumers pin with `pip install --pre 'jetson-cli>=<base>.dev0,<<base>'`.

### Stable (merge to `master`)

Merging to `master` publishes `<base>` (no suffix) stable to PyPI. No tag
step. Verify at `https://pypi.org/project/jetson-cli/`.

### Manual fallback

```bash
# Test-PyPI
gh workflow run publish.yml -f target=testpypi --ref <branch>
gh run watch $(gh run list --workflow=publish.yml --limit=1 --json databaseId -q '.[0].databaseId')

# PyPI (publishes as <base>.dev<N> — dispatch never produces a stable wheel)
gh workflow run publish.yml -f target=pypi --ref <branch>
gh run watch $(gh run list --workflow=publish.yml --limit=1 --json databaseId -q '.[0].databaseId')
```

## Version-bump rules

Bump BOTH sources in one commit — they are enforced in sync by
`tests/test_cli.py::test_version_constant`:

```bash
sed -i 's/^version = ".*"/version = "0.1.0"/' pyproject.toml
sed -i 's/^__version__ = ".*"/__version__ = "0.1.0"/' jetson_cli/__init__.py
```

### Post-release bump (required)

After `master` publishes `X.Y.Z`, open a PR to `dev` bumping both files to
`X.Y.(Z+1)` with the same `sed` one-liner. Without this, subsequent
`.dev<N>` builds from `dev` sort ≤ `X.Y.Z` per PEP 440 and pip ignores them.
See `docs/releasing-pypi.md` for the full rationale.

## Scope boundary (important)

The `jetson` CLI is **for Jetson device/package users**, not a meta-tool for this
repo. Do not propose `jetson build`, `jetson release`, `jetson doctor`, etc.
Repo-facing automation belongs in skills like this one, in `scripts/`, or in
GitHub Actions — not in the PyPI package.

## If something breaks

- **Bad wheel shipped to PyPI.** Immutable — yank via PyPI UI, bump `<base>` to the next patch on `dev`, merge to `master`; that push publishes the replacement.
- **OIDC exchange failed.** Pending publisher probably isn't configured. Fix PyPI config, re-run the failed job (`skip-existing: true` makes it idempotent).
- **One distribution uploaded, the other failed.** Same fix — re-run the failed job only; successful one is skipped.
- **Fork PR publish skipped.** Expected. Use `workflow_dispatch` from a same-repo branch for a fork-reviewer build.

## Follow-ups

Track in GitHub Issues on `jetson-ai-lab/jetson-containers`. If Issues are disabled, flag that to the maintainer and ask them to enable — do NOT park follow-ups in PR comments or an in-repo `FOLLOWUPS.md`.
