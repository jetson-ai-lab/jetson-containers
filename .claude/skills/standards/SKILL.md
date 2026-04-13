---
name: standards
description: Repo-wide authoring standards for Dockerfiles, shell scripts, and the patterns SonarCloud / Qodo / Copilot reviews check on PRs. Use when editing any package Dockerfile, vendored install script, or test script — and especially when responding to bot review feedback on an open PR.
---

# standards

Per-topic standards live in `references/`. Read the relevant one **before** editing a file the standard covers — these are mostly things that, if missed, will come back as bot review comments and force a force-push round.

## When to invoke

- Authoring or editing a package `Dockerfile` (any path under `packages/*/*/Dockerfile`).
- Authoring or editing bash scripts invoked from a Dockerfile (apt installers, vendored cudastack scripts, package `test.sh` files).
- Replying to or evaluating SonarCloud / Qodo / Copilot review comments on an open PR — these standards mirror the rules those bots check, so responding to a comment usually means citing the relevant reference here.

## References

- [`references/dockerfile.md`](references/dockerfile.md) — Dockerfile + bash-in-RUN + vendored-script standards. Codifies the lessons from PR #17 (Sonar `docker:S7031`, `shelldre:S7688`; Copilot `pip install` pin + build-time-GPU feedback).

## Adding a new reference

One reference per topic (`shell.md`, `python.md`, `packaging.md`, …). Keep `SKILL.md` short — it's a router, not the content. Each reference: 40–80 lines, with a "When this applies" lead and a "What not to do" closer, matching the voice of `.claude/skills/jetson-pr.md` and `.claude/skills/triage-build-failure.md`. Add a row to the **References** list above when you add a new file.
