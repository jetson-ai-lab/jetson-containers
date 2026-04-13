# Dockerfile + bash-script standards

Apply when authoring or editing a package `Dockerfile` (`packages/*/*/Dockerfile`) or any bash script invoked from one (`*.sh` under the same package directory). These rules map to the SonarCloud + review-bot findings we got hit with on PR #17 — landing them right the first time avoids a force-push round.

## RUN layering (`docker:S7031`)

**Target: one `RUN` per Dockerfile.** Merge aggressively. Sonar flags every consecutive-RUN pair, your image's layer count inflates with each RUN, and the Docker cache gets thinner the more you split. Docker layer boundaries are not the right place to record where code came from — provenance lives in `.assimilai.toml` (source paths, sha256, `changes` notes); layer boundaries are just a cache-and-size knob. Don't conflate the two.

**How to merge cleanly:**
- Concatenate install steps with `\` + `;` (or `&&` where you want short-circuit-on-fail) under a single `RUN set -eux; ...`.
- Use `# === <section-name> ===` comments *inside* the `RUN` to mark each logical section, and point each section at its `[[sources.files]]` entry in `.assimilai.toml` so the next reader can still trace provenance.
- **Fold the build-time verification (e.g. `python3 -c "import X; assert ..."`) in as the trailing section of the same RUN** when it's a simple inline check. A failed assertion still fails the RUN and fails the build — same behavior as a separate layer, one fewer flag. Only keep verification as its own `RUN` when it needs a distinct `COPY`, a different source tree, or `ARG`s the install layer doesn't already have.

**Always** end apt-install steps with `apt-get clean && rm -rf /var/lib/apt/lists/*` *in the same `RUN`* that populated `/var/lib/apt/lists/`. Cleanup in a later layer doesn't reclaim the space.

**Concrete exemplar:** `packages/multimedia/sound-utils/Dockerfile` is a **single `RUN`** — cuDNN + NVPL + cuDSS + cuSPARSELt + cuTENSOR + NCCL + torch + portaudio + soundfile/sounddevice + a trailing `torch.version.cuda is not None` verification — with per-source `# === section ===` comments pointing at `.assimilai.toml`. Zero `docker:S7031` flags, full provenance preserved.

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

## Vendored / assimilated code (`status: verbatim` vs `adapted`)

Vendored files (a copy of code from elsewhere in the repo or a public upstream, tracked in a `.assimilai.toml` manifest) have two valid statuses:

- **`verbatim`** — exact byte-for-byte copy. SHA256 in the manifest matches the upstream's hash. Use only when you literally must not change the file (signed sources, regulatory constraints, an active upstream sync window).
- **`adapted`** — copy with documented local changes. Manifest carries `sha256` (this repo's copy), `upstream_sha256` (the source's hash at the time of vendor), and a `changes` field describing the diff.

When SonarCloud / Qodo / Copilot flag a finding on a vendored file, **default to fixing it locally and promoting `verbatim` → `adapted`** rather than carrying the noise indefinitely. We control this repo; `verbatim` is a contract about provenance, not a moratorium on improvements. The fix needs to be:

1. Mechanical and well-understood (e.g. `[ → [[`, deleting a stray semicolon). Behavioral changes get a separate review.
2. Recorded in the manifest's `changes` field with the rule that drove it (e.g. `Sonar shelldre:S7688`).
3. Tracked upstream too, so the canonical source eventually catches up. File an issue against the upstream package and link it from `changes`.

Concrete example from PR #17: the four `cudastack_install_*.sh` scripts started as `verbatim` copies and tripped 14 `shelldre:S7688` findings. They were promoted to `adapted` with the `[ → [[` change applied locally; the upstream cleanup is tracked at jetson-ai-lab/jetson-containers#19 so the next sync doesn't lose the fix.

Use `verbatim` (and push back on lint findings) only when the bar above can't be met — and even then, the fallback is `sonar.exclusions` in `sonar-project.properties` so the dashboard isn't permanently noisy.

## Replying to bot flags on intentional patterns

When SonarCloud / Qodo / Copilot flag something you're keeping as-is on purpose, the reply should:

1. **Name the pattern** (e.g. "assimilai vendored", "per-concern RUN layering", "ARG-driven pin overridable via --build-arg").
2. **Point at the override mechanism** that makes it reasonable (`--build-arg X=...`, `.assimilai.toml`, test.py for live checks, …).
3. **Link any follow-up issue** that tracks the broader concern (#18 for `.env`-driven version pins, #19 for cudastack shell-style cleanup, etc.).

Resolve the thread only when a fix actually landed. Leave it open if you pushed back — let the maintainer close it when they agree.

## What not to do

- Don't silence Sonar / bot warnings by deleting comments or adding `// NOSONAR` blanket suppressions. If a finding doesn't apply, the right answer is a substantive PR reply (above), not suppression.
- Don't push back on a Sonar finding in vendored code with "it's verbatim" if the fix is mechanical. Promote to `adapted`, record the `changes`, file the upstream issue. Reserve `verbatim` for cases where local fixes really aren't an option.
- Don't split installs into many small `RUN`s "for provenance". Merge into one install RUN; record provenance in `.assimilai.toml`; mark each section inline with `# === ... ===` comments. One install RUN + one verification RUN is the target shape.
- Don't put live-GPU checks (`torch.cuda.is_available()`, GPU tensor ops) in a Dockerfile `RUN`. Put them in `test.py` / `test.sh`.
