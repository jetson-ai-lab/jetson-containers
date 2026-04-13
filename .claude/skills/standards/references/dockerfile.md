# Dockerfile + bash-script standards

Apply when authoring or editing a package `Dockerfile` (`packages/*/*/Dockerfile`) or any bash script invoked from one (`*.sh` under the same package directory). These rules map to the SonarCloud + review-bot findings we got hit with on PR #17 — landing them right the first time avoids a force-push round.

## RUN layering (`docker:S7031`)

Merge consecutive `RUN`s that form **one logical install unit** — an `apt-get update && apt-get install -y X Y && apt-get clean && rm -rf /var/lib/apt/lists/*` is one layer; a `pip install a b c` is one layer. Splitting them across separate `RUN`s inflates the image and may leave apt metadata stale across the gap.

**Don't merge** when each `RUN` represents a distinct provenance or cache concern that you deliberately want tracked independently — e.g. in the assimilai pattern (`packages/multimedia/sound-utils/Dockerfile`), each vendored-from-upstream install gets its own `RUN` so it matches a `[[sources.files]]` entry in `.assimilai.toml`. When you do keep them separate, put a one-line comment on the `RUN` naming the intent ("vendored from cudastack/install_cudss.sh — kept as its own layer for assimilai provenance"), so the next Sonar flag has a clean reply.

**Always** end apt-install steps with `apt-get clean && rm -rf /var/lib/apt/lists/*` *in the same `RUN`* that populated them. Cleanup in a later layer doesn't reclaim the space.

## Bash in `RUN` + invoked scripts (`shelldre:S7688`)

- Use `[[ ... ]]`, **not** `[ ... ]`. It's word-splitting-safe, supports `==` / `=~`, and chains with `&&` / `||` without subshells. Drop to `[ ... ]` only when the shebang is `#!/bin/sh` (POSIX-only).
- `set -euo pipefail` at the top of every non-trivial bash script (including ones invoked from `RUN`).
- `$(...)`, not backticks.

## Version pins

Every external version referenced in the Dockerfile (cuDNN, NCCL, torch, torchaudio, CUDNN_PACKAGES, DISTRO, …) goes behind an `ARG NAME=X.Y.Z` with a concrete default. Overridable at build time via `--build-arg`. Never `pip install <pkg>` unpinned — the index can update under you and silently regress the image.

## Build-time vs runtime checks

`docker build` is **not** invoked with `--gpus=all` in this repo. A `RUN` step that calls `torch.cuda.is_available()` will be flaky on builders without `default-runtime: nvidia` set in the daemon. Put **metadata** checks at build time:

```dockerfile
RUN python3 -c "import torch; assert torch.version.cuda is not None"
```

…and **live-GPU** checks in `test.py` / `test.sh`. `container.py::test_container` runs tests under `docker run --gpus=all`, so that's where a `torch.cuda.is_available()` + tensor-op check belongs.

## Exceptions: verbatim vendored code

If a file in a package directory is a verbatim copy from elsewhere in the repo or from a public upstream, and its SHA256 is pinned in a manifest (`.assimilai.toml`), **do not "fix" lint findings on it**. Modifying verbatim copies breaks the provenance contract the manifest encodes.

Instead: file an upstream issue against the canonical source, reference the Sonar rule + finding count, and push back in review. Concrete example: PR #17 vendored `packages/cuda/cudastack/install/*.sh` into `packages/multimedia/sound-utils/`. The 14 `shelldre:S7688` findings on those copies were tracked as jetson-ai-lab/jetson-containers#19 and the threads were left open (not "fixed" downstream).

## Replying to bot flags on intentional patterns

When SonarCloud / Qodo / Copilot flag something you're keeping as-is on purpose, the reply should:

1. **Name the pattern** (e.g. "assimilai vendored", "per-concern RUN layering", "ARG-driven pin overridable via --build-arg").
2. **Point at the override mechanism** that makes it reasonable (`--build-arg X=...`, `.assimilai.toml`, test.py for live checks, …).
3. **Link any follow-up issue** that tracks the broader concern (#18 for `.env`-driven version pins, #19 for cudastack shell-style cleanup, etc.).

Resolve the thread only when a fix actually landed. Leave it open if you pushed back — let the maintainer close it when they agree.

## What not to do

- Don't silence Sonar / bot warnings by deleting comments or adding `// NOSONAR` blanket suppressions. If a finding doesn't apply, the right answer is a substantive PR reply (above), not suppression.
- Don't fix lint on verbatim vendored files — see the exception rule above.
- Don't merge a `RUN` that intentionally encodes provenance (assimilai per-source layer) just to silence `docker:S7031`. Comment the intent; reply on the thread.
- Don't put live-GPU checks (`torch.cuda.is_available()`, GPU tensor ops) in a Dockerfile `RUN`. Put them in `test.py` / `test.sh`.
