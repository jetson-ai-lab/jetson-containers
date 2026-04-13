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

- User asks to cut a release (Test-PyPI or PyPI)
- User is troubleshooting the publish workflow
- User asks about trusted-publisher configuration

## One-time setup check (ask the user if first-time release)

Confirm the prerequisites are done before running any workflow:

1. **Four pending publishers registered** — table in `docs/releasing-pypi.md`. If Ori hasn't done this, he hits "Trusted publishing exchange failure" on the first run.
2. **Two GitHub Environments exist** — `testpypi` and `pypi` under repo Settings → Environments. No secrets inside.

If either is missing, STOP and tell Ori what to configure. Don't attempt to run the workflow.

## Release to Test-PyPI (always do this first for a new version)

```bash
# From current feature branch:
gh workflow run publish.yml -f target=testpypi --ref <branch>

# Watch progress:
gh run watch $(gh run list --workflow=publish.yml --limit=1 --json databaseId -q '.[0].databaseId')
```

Then verify project pages exist:

- <https://test.pypi.org/project/jetson-cli/>
- <https://test.pypi.org/project/jetson-containers/>

Install-check in a clean venv (from docs/releasing-pypi.md):

```bash
uv venv /tmp/verify --seed
/tmp/verify/bin/pip install --index-url https://test.pypi.org/simple/ \
                           --extra-index-url https://pypi.org/simple/ \
                           jetson-cli==<version>
/tmp/verify/bin/jetson --version
```

## Release to PyPI (tag-driven)

```bash
# After dev → master promotion:
git checkout master && git pull
git tag -a v0.1.0 -m "v0.1.0 — <one-line summary>"
git push origin v0.1.0
```

The tag push auto-fires `publish.yml`. Verify:

- <https://pypi.org/project/jetson-cli/>
- <https://pypi.org/project/jetson-containers/>

## Version-bump rules

Before tagging: bump BOTH sources in one commit.

```bash
sed -i 's/^version = ".*"/version = "0.1.0"/' pyproject.toml
sed -i 's/^__version__ = ".*"/__version__ = "0.1.0"/' jetson_cli/__init__.py
```

`tests/test_cli.py::test_version_constant` asserts the exact pinned value, so a
mismatch here fails CI before a bad release ships.

## Scope boundary (important)

The `jetson` CLI is **for Jetson device/package users**, not a meta-tool for this
repo. Do not propose `jetson build`, `jetson release`, `jetson doctor`, etc.
Repo-facing automation belongs in skills like this one, in `scripts/`, or in
GitHub Actions — not in the PyPI package.

## If something breaks

- **Bad wheel shipped to PyPI.** Immutable — yank via PyPI UI, bump to `0.1.1`.
- **OIDC exchange failed.** Pending publisher probably isn't configured. Fix PyPI config, re-run the failed job (`skip-existing: true` makes it idempotent).
- **One distribution uploaded, the other failed.** Same fix — re-run the failed job only; successful one is skipped.

## Follow-ups

Track in GitHub Issues on `jetson-ai-lab/jetson-containers`. If Issues are disabled, flag that to Ori and ask to enable them — do NOT park follow-ups in PR comments or an in-repo `FOLLOWUPS.md`.
