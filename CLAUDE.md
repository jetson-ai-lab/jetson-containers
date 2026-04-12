# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

jetson-containers is a modular container build system for NVIDIA Jetson devices. It discovers packages under `packages/`, resolves their dependency graph, stitches their Dockerfiles into a single multi-stage build, and produces images pinned to a specific L4T/JetPack/CUDA target.

## Common commands

```bash
# Install: sets up venv, installs deps, symlinks CLI tools to /usr/local/bin
bash install.sh

# Build one or more packages (chains Dockerfiles in dependency order)
jetson-containers build <package> [<package2> ...]
# equivalent: ./build.sh <package> ...

# Run a compatible image (autotag picks local → registry → build)
jetson-containers run $(autotag <package>) [command]

# Lint/format (pre-commit runs Black + Flake8)
pre-commit install             # one-time
pre-commit run --all-files     # manual run
```

Override build targets without editing tracked files by copying `.env.default` → `.env` and setting `L4T_VERSION`, `CUDA_VERSION`, `LSB_RELEASE`, `CUDA_ARCH`, or local PyPI/APT mirror URLs. These flow into Docker `build_args` via `jetson_containers/l4t_version.py`.

## Pre-commit scope (important)

Pre-commit only lints three paths: `jetson_containers/*.py`, `packages/example/*.py`, and `test_precommit.py`. The rest of `packages/` is deliberately **not** linted — package code often mirrors upstream style and is left untouched. Do not "fix" formatting in other packages.

Black config: `line-length=88`, `skip-string-normalization=true` (single quotes allowed), `target-version=['py38']`. Pre-commit itself runs Black under Python 3.10.

## PR conventions

- **Target `dev`, not `master`.** The CI workflow `.github/workflows/pr-on-dev.yml` triggers on PRs to `dev` and builds changed packages on self-hosted Jetson runners (Orin + Thor).
- Each PR should touch only the packages it claims to change.
- Commit style from history: short, lowercase, imperative subject, no trailing period (e.g. `fix`, `bump llamacpp`, `vLLM Orin-specific FA3 patch`).

## Architecture

### Package resolution (4 forms, in priority order)

Every buildable unit lives under `packages/<category>/<name>/`. Metadata is read from whichever of these exists first:

1. **YAML header in `Dockerfile`** between `#---` markers at the top
2. **`config.yaml` / `config.yml`** — static metadata
3. **`config.json`** — meta-container (composition only, no Dockerfile)
4. **`config.py`** — executed at build time; returns a list of package dicts, enabling version variants (e.g. PyTorch's `config.py` emits `pytorch:2.8`, `pytorch:2.8-all`, `pytorch:2.8-builder`)

Key metadata fields: `name`, `alias`, `depends`, `requires` (version constraints on L4T/CUDA/Python), `test`, `build_args`, `dockerfile`.

### Build pipeline (core modules in `jetson_containers/`)

- **`packages.py`** — recursively scans `packages/`, runs `config.py` scripts, builds the dependency graph, filters by L4T compatibility, and installs a Python meta path finder so package code can `from packages.ml.pytorch.version import ...` at runtime.
- **`build.py`** — CLI entry point; argument parsing and dispatch.
- **`container.py`** — stitches multiple package Dockerfiles into one combined Dockerfile, invokes `docker build`, optionally runs per-package tests, optionally pushes.
- **`l4t_version.py`** — detects architecture (`tegra-aarch64`, `aarch64`, `x86_64`) and reads L4T/JetPack/CUDA/GPU-arch from `/etc/nv_tegra_release`. All version vars (`CUDA_VERSION`, `PYTORCH_VERSION`, …) originate here and flow into `build_args`.
- **`tag.py`, `docs.py`, `ci.py`, `network.py`, `webhook.py`, `logging.py`** — tagging conventions, auto-generated per-package docs, CI helpers, GitHub integration + build notifications, colored terminal output.

### Adding a new package

1. Create `packages/<category>/<name>/Dockerfile` with a `#---` YAML header (or `config.yaml` / `config.py`).
2. Declare `depends` on upstream packages (e.g. `pytorch`, `cuda`).
3. Optional: `test.py` or `test.sh` for post-build validation.
4. Build with `jetson-containers build <name>`.

### Upgrading a package version

Version definitions live in one of: `version.py` (canonical constant, e.g. `PYTORCH_VERSION = Version('2.8')`), a list of calls in `config.py` (add a new entry, **don't remove old ones** — historical versions support older JetPack targets), or `build_args` / Dockerfile `ARG`. After bumping, grep the package directory for the old version string to catch cascading refs in wheel URLs, download filenames, and `requires` constraints.

## Project-specific skills

Four workflow skills live in `.claude/skills/`:

- **`jetson-pr.md`** — full PR workflow (branch naming, PR template, `dev` targeting).
- **`upgrade-package.md`** — version-bump workflow (where versions are defined, what to preserve).
- **`new-package.md`** — step-by-step guide for scaffolding a new package (Dockerfile header, `config.py`, test file).
- **`triage-build-failure.md`** — how to diagnose and fix a failing `jetson-containers build` run (log reading, dependency tracing, layer cache busting).

Reach for these when the user asks to open a PR, upgrade a package, add a new package, or debug a build failure.
