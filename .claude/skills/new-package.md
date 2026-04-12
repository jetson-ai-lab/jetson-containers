# Create a New jetson-containers Package

Help the user add a new package to this jetson-containers repository.

## What the user will provide

The user will tell you the package name. If they don't also tell you the category (e.g. `llm`, `ml`, `cv`, `speech`, `physicalAI`) and the upstream source (pip / git / tarball / prebuilt wheel URL), ask before proceeding.

## Directory layout

Every package lives at `packages/<category>/<name>/`. Look at an existing package in the same category for a working reference (e.g. `packages/ml/pytorch/` for a pip-based install with version variants, `packages/cv/opencv/` for a build-from-source package, `packages/llm/ollama/` for a simple upstream-binary package).

## Choosing a metadata form

Pick one, in order of increasing complexity:

1. **Dockerfile YAML header** — simplest. Put metadata between `#---` markers at the top of `Dockerfile`. Use when the package has a single version and no dynamic logic.
2. **`config.yaml`** — same as above but separate from the Dockerfile. Use when multiple Dockerfiles share one config.
3. **`config.json`** — meta-package. No Dockerfile; the package exists only to compose other packages via `depends`.
4. **`config.py`** — dynamic. Returns a list of package dicts at build time. Use when the package has multiple version variants (e.g. `pytorch:2.7`, `pytorch:2.8`) or aliases. Pair with a `version.py` that exports the canonical version constant.

## Required metadata fields

- `name` — short, lowercase, matches the directory name.
- `depends` — list of upstream packages this one is built on top of (e.g. `['pytorch', 'cuda']`). Grep `packages/` to confirm the exact names.
- `requires` — version constraints on L4T / CUDA / Python (e.g. `'>=36'` for JetPack 6+, `'cu128'` for CUDA 12.8). Leave empty if the package works across all supported targets.
- `test` — filename of the test script if one exists (`test.py` or `test.sh`).
- `build_args` — pass-through to `docker build --build-arg`. Use for version pins and upstream URLs.

Optional: `alias` (shorter names that resolve to this package), `dockerfile` (if named anything other than `Dockerfile`), `notes`.

## Step-by-step workflow

1. **Create the directory**: `packages/<category>/<name>/`.
2. **Write the Dockerfile** or config file. For pip-installable Python packages, the simplest Dockerfile is `FROM $BASE_IMAGE` + `RUN pip install <package>==<version>`.
3. **Declare `depends`** on upstream packages. If the package uses CUDA, depend on `cuda`. If it uses PyTorch, depend on `pytorch`.
4. **Set `requires`** only if there's a real constraint — don't invent one.
5. **Add `test.py` or `test.sh`** that imports the package and prints a version, or runs a minimal smoke test. Reference the `test` field in metadata.
6. **Build locally**: `jetson-containers build <name>`. Watch for upstream fetch failures, CUDA arch mismatches, and Python version issues.
7. **Once it builds**, show the user the final metadata and test output.

## Style notes

- Match the voice of neighboring packages in the same category — file layouts, comment density, and `build_args` naming conventions vary per upstream.
- Do not add the package to `packages/example/`. That directory is a reference shown by the pre-commit config and is scope-limited to linting examples.
- Do not modify unrelated packages (e.g. don't bump a sibling's version while adding yours).

## When to ask vs. proceed

- Ask for: category, upstream source, whether the package needs `cuda` as a direct dependency, and whether a `requires` constraint applies.
- Proceed silently on: directory creation, Dockerfile boilerplate, adding a minimal `test.py`, running the build.
