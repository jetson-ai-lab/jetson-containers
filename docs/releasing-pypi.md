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

### Test-PyPI (manual, any branch)

```bash
# From the Actions tab → "Publish to (Test-)PyPI" → Run workflow
#   branch: <your feature branch or dev>
#   target: testpypi
```

Or via CLI:

```bash
gh workflow run publish.yml -f target=testpypi --ref <branch>
```

Verify after ~3 minutes:

- <https://test.pypi.org/project/jetson-cli/>
- <https://test.pypi.org/project/jetson-containers/>

Install-check from a clean venv:

```bash
uv venv /tmp/verify --seed
/tmp/verify/bin/pip install --index-url https://test.pypi.org/simple/ \
                           --extra-index-url https://pypi.org/simple/ \
                           jetson-cli==0.0.1
/tmp/verify/bin/jetson --version   # -> jetson 0.0.1
```

(The `--extra-index-url` is needed because Test-PyPI lacks most dependencies.)

### Production PyPI (automatic, on tag)

```bash
# After dev → master promotion
git checkout master && git pull
git tag -a v0.1.0 -m "v0.1.0 — <summary>"
git push origin v0.1.0
```

The tag push fires `publish.yml` → builds both distributions with name-rewrite
→ uploads to PyPI. Verify:

- <https://pypi.org/project/jetson-cli/>
- <https://pypi.org/project/jetson-containers/>

## Version bumping

Single source of truth: the `version = "X.Y.Z"` line in `pyproject.toml`.
`jetson_cli/__init__.py` hardcodes the same string so `pytest tests/` runs
without a mandatory editable install — keep both in sync.

```bash
# Bump both in one commit:
sed -i 's/^version = ".*"/version = "0.1.0"/' pyproject.toml
sed -i 's/^__version__ = ".*"/__version__ = "0.1.0"/' jetson_cli/__init__.py
git commit -am "chore: bump jetson-cli version to 0.1.0"
```

## Matrix build explained

`publish.yml` runs the same build twice via `matrix.pkg: [jetson-cli, jetson-containers]`.
Before `python -m build`, a small inline Python snippet rewrites the `name`
and `readme` fields in `pyproject.toml`:

```python
text = re.sub(r'(?m)^name = ".*"',    f'name = "{pkg}"', text, count=1)
text = re.sub(r'(?m)^readme = ".*"',  f'readme = "packaging/README.{pkg}.md"',
              text, count=1)
```

The two built artifact sets are uploaded with distinct names (`dist-jetson-cli`,
`dist-jetson-containers`) and downloaded by name in the publish jobs so they
don't cross-contaminate.

## Rollback

**Bad wheel uploaded.** PyPI versions are immutable — you cannot re-upload
`0.1.0`. Yank it from the PyPI project page (it stays resolvable by exact pin
but drops out of `pip install <name>` resolution), then tag and push `0.1.1`.

**OIDC exchange failed.** `pypa/gh-action-pypi-publish` errors with "Trusted
publishing exchange failure" and uploads nothing. Fix the pending-publisher
config on PyPI, then re-run the failed job from the Actions UI. `skip-existing:
true` makes re-runs safe even if one of the two distributions uploaded and the
other didn't.

**Full revert.** The `jetson_cli/` package and publish workflow are additive
to the repo. `git revert <commit-range>` removes them without touching
`jetson_containers/`, `packages/`, or `install.sh`.
