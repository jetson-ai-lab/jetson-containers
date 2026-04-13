# Releasing `jetson-cli` / `jetson-containers` to PyPI

Both distributions ship the `jetson` console command from the same `jetson_cli/`
source tree. Publishing uses GitHub Actions + OIDC trusted publishing — no PyPI
API tokens are stored in repo secrets.

## Prerequisites (one-time)

### 1. Pending publishers on PyPI + Test-PyPI

For a brand-new distribution name, register a **pending publisher** on each
instance before the first upload (PyPI trusted-publisher docs:
<https://docs.pypi.org/trusted-publishers/adding-a-publisher/>).

Go to *Your account → Publishing → Add a pending publisher* on each instance
and add these four entries:

| Instance | Project | Owner | Repo | Workflow | Environment |
|---|---|---|---|---|---|
| test.pypi.org | `jetson-cli` | `jetson-ai-lab` | `jetson-containers` | `publish.yml` | `testpypi` |
| test.pypi.org | `jetson-containers` | `jetson-ai-lab` | `jetson-containers` | `publish.yml` | `testpypi` |
| pypi.org | `jetson-cli` | `jetson-ai-lab` | `jetson-containers` | `publish.yml` | `pypi` |
| pypi.org | `jetson-containers` | `jetson-ai-lab` | `jetson-containers` | `publish.yml` | `pypi` |

### 2. GitHub Environments

In repo Settings → Environments, create two environments: **`testpypi`** and
**`pypi`**. No secrets needed — only the environment names must match what
`.github/workflows/publish.yml` references (the OIDC token carries the
environment claim).

## Release flow

The workflow now runs three branch-driven channels plus a manual fallback. Let
`<base>` be the `version = "X.Y.Z"` line in `pyproject.toml` and `<N>` be
`${{ github.run_number }}` (monotonic per-workflow-per-repo).

| Trigger | Version | Test-PyPI | PyPI |
|---|---|---|---|
| `pull_request` (same-repo) | `<base>.dev<N>` | ✅ | ❌ |
| `push` → `dev` | `<base>.dev<N>` | ❌ | ✅ (dev stream) |
| `push` → `master` | `<base>` (stable) | ❌ | ✅ (stable) |
| `workflow_dispatch` → `testpypi` | `<base>.dev<N>` | ✅ | ❌ |
| `workflow_dispatch` → `pypi` | `<base>.dev<N>` | ❌ | ✅ |

### PR → Test-PyPI

Any same-repo PR automatically builds `<base>.dev<N>` wheels for both
distributions and uploads them to Test-PyPI. No action required — the build
surfaces in the PR's Checks tab.

Install-check from a clean venv:

```bash
uv venv /tmp/verify --seed
/tmp/verify/bin/pip install --index-url https://test.pypi.org/simple/ \
                           --extra-index-url https://pypi.org/simple/ \
                           jetson-cli==<base>.dev<N>
/tmp/verify/bin/jetson --version   # -> jetson <base>.dev<N>
```

(The `--extra-index-url` is needed because Test-PyPI lacks most dependencies.)

### Merge to `dev` → PyPI dev stream

Merging a PR into `dev` fires `publish.yml` → uploads `<base>.dev<N>` wheels to
**PyPI** (not Test-PyPI). Consumers pin the dev stream with:

```bash
pip install --pre 'jetson-cli>=<base>.dev0,<<base>'
```

Verify after ~3 minutes:

- <https://pypi.org/project/jetson-cli/#history>
- <https://pypi.org/project/jetson-containers/#history>

### Merge to `master` → PyPI stable

Merging `dev` into `master` fires `publish.yml` → uploads `<base>` (no suffix)
stable wheels to PyPI. This is the release event; there is no separate `git
tag` step. Tags can be created afterwards for git history but are not wired to
CI.

Verify:

- <https://pypi.org/project/jetson-cli/>
- <https://pypi.org/project/jetson-containers/>

### Manual fallback (`workflow_dispatch`)

```bash
gh workflow run publish.yml -f target=testpypi --ref <branch>
gh workflow run publish.yml -f target=pypi     --ref <branch>
```

Useful for producing a Test-PyPI build from a fork PR (see "Fork PRs" below)
or re-running after a transient failure.

## Version bumping

Canonical version: the `version = "X.Y.Z"` line in `pyproject.toml`.
`jetson_cli/__init__.py` currently hardcodes the same string so `pytest tests/`
runs without a mandatory editable install, so the repository has a **dual-source
setup** and both files must be kept in sync until we migrate to
`importlib.metadata`-based resolution.

```bash
# Bump both in one commit:
sed -i 's/^version = ".*"/version = "0.1.0"/' pyproject.toml
sed -i 's/^__version__ = ".*"/__version__ = "0.1.0"/' jetson_cli/__init__.py
git commit -am "chore: bump jetson-cli version to 0.1.0"
```

### Post-release version bump (required)

Immediately after `master` publishes `X.Y.Z` stable, open a PR to `dev`
bumping `<base>` to `X.Y.(Z+1)` (single `sed` commit as above). Without this
bump, subsequent `.dev<N>` builds from `dev` sort ≤ `X.Y.Z` per PEP 440 and
pip ignores them.

Merging the bump PR is safe: its own Test-PyPI build is just the first
`X.Y.(Z+1).dev<N>`.

## Matrix build explained

`publish.yml` runs the same build twice via `matrix.pkg: [jetson-cli, jetson-containers]`.
Two sequential regex-rewrite steps mutate `pyproject.toml` in-job (no commit)
before `python -m build`:

1. **Compute release version** — reads `<base>` from `pyproject.toml`, derives
   the channel version (`<base>` on `master`, else `<base>.dev<N>`), then
   rewrites the `version = "..."` line in `pyproject.toml` AND the
   `__version__ = "..."` line in `jetson_cli/__init__.py` so the wheel
   filename and `jetson --version` match.
2. **Rewrite name + readme** — swaps `name = "..."` to `${{ matrix.pkg }}` and
   `readme = "..."` to `packaging/README.${{ matrix.pkg }}.md`.

```python
text = re.sub(r'(?m)^name = ".*"',    f'name = "{pkg}"', text, count=1)
text = re.sub(r'(?m)^readme = ".*"',  f'readme = "packaging/README.{pkg}.md"',
              text, count=1)
```

The two built artifact sets are uploaded with distinct names (`dist-jetson-cli`,
`dist-jetson-containers`) and downloaded by name in the publish jobs so they
don't cross-contaminate.

## Fork PRs

Fork PRs run the **build** job (so the wheel metadata is validated) but
silently skip `publish-testpypi` because `id-token: write` — required for OIDC
trusted publishing — is not granted to workflows triggered from forks. The
Actions run shows the publish job as skipped, not failed.

To produce a Test-PyPI build that fork reviewers can install, use the manual
fallback from a same-repo branch tracking the fork PR, or push the fork's
commits to a same-repo branch and re-trigger via `workflow_dispatch`.

## Rollback

**Bad wheel uploaded.** PyPI versions are immutable — you cannot re-upload
`X.Y.Z`. Yank it from the PyPI project page (it stays resolvable by exact pin
but drops out of `pip install <name>` resolution), bump `<base>` to `X.Y.(Z+1)`
on `dev`, merge to `master`, and that push publishes the replacement.

**OIDC exchange failed.** `pypa/gh-action-pypi-publish` errors with "Trusted
publishing exchange failure" and uploads nothing. Fix the pending-publisher
config on PyPI, then re-run the failed job from the Actions UI. `skip-existing:
true` makes re-runs safe even if one of the two distributions uploaded and the
other didn't.

**Duplicate publish.** A second push to the same branch without a version bump
triggers the workflow again; `skip-existing: true` makes the upload a no-op on
both PyPI and Test-PyPI. No manual intervention needed.

**Full revert.** The `jetson_cli/` package and publish workflow are additive
to the repo. `git revert <commit-range>` removes them without touching
`jetson_containers/`, `packages/`, or `install.sh`.
