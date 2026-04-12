# Triage a jetson-containers Build Failure

Help the user diagnose why a `jetson-containers build` run failed — either locally or in the `pr-on-dev.yml` CI on self-hosted Orin / Thor runners — and propose a fix.

## What the user will provide

Usually just the package name and a vague "it's failing". Ask for the runner (Orin / Thor / local) and the JetPack/CUDA target if not specified. If the user pastes a log snippet or links to a GitHub Actions run, read that first.

## Where logs live

Local builds write to `logs/<date>/<package>/`. See `docs/how-to-use-logs.md` for the layout — do not duplicate that guidance here; read it if you need a refresher on directory structure or retention.

CI logs come from the GitHub Actions run. Use `gh run view <run-id> --log-failed` to get only the failing step.

## Classify the failure

Grep the log for the first occurrence of `ERROR`, `error:`, `failed to solve`, or a non-zero exit. The failure is almost always one of these:

1. **Upstream fetch 404 / checksum mismatch** — wheel, tarball, or git tag moved or was deleted. Check the Dockerfile `ARG` for the URL or version and compare to the upstream (PyPI / GitHub releases / NVIDIA). Fix: update the URL or version.

2. **CUDA arch mismatch** — build succeeds on Orin but fails on Thor (or vice versa), or emits `no kernel image is available for execution`. `jetson_containers/l4t_version.py` owns the `CUDA_ARCH` / `GPU_ARCHS` vars. Fix: widen the arch list in the Dockerfile or add a runner-specific build arg.

3. **Python version mismatch** — `No matching distribution found` on a wheel that's only built for one Python version. Fix: pin a compatible version in `config.py`, or add a build step that compiles from source.

4. **`requires` constraint too tight / too loose** — package builds on an unsupported target because the `requires` field doesn't exclude it, or is skipped on a supported target because it over-constrains. Fix: edit `requires` in the metadata; see neighboring packages for the constraint DSL.

5. **Dependency version conflict** — pip resolver error showing two packages demanding incompatible versions of a shared dep. Fix: pin the conflicting dep in *this* package's Dockerfile, or bump the upstream package that's lagging.

6. **Disk / runner environment** — "no space left on device", "permission denied" on `/home/jetson/actions-runner/_work/...`. These are runner-side, not a package bug. Flag to the user; don't try to fix in-repo.

## What to do

1. Identify which class the failure falls into (above).
2. Locate the exact file to change: usually the package's `Dockerfile`, `config.py`, or `version.py`. Grep the package directory for the failing version string or URL.
3. Propose the minimal fix. Show the diff before applying.
4. If the fix is a version bump, follow `.claude/skills/upgrade-package.md` for the proper procedure (don't delete old version entries — they support older JetPack targets).
5. Rebuild locally on the same arch that failed, if possible. If the failure is Thor-only and the user is on Orin, say so and let them trigger CI.

## What not to do

- Do not bump unrelated package versions "while you're in there".
- Do not silence warnings by adding try/except or `|| true` to Dockerfile `RUN` lines.
- Do not modify `.github/workflows/pr-on-dev.yml` to skip the failing package — that hides the bug.
- Do not touch `jetson_containers/l4t_version.py` unless the root cause is genuinely a missing L4T version entry (rare; usually a new JetPack release).
