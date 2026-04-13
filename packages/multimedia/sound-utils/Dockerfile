#---
# name: sound-utils
# group: multimedia
# depends: [cuda, python]
# requires: '>=38'
# test: [test.py]
# docs: docs.md
# notes: Sound utilities for working with audio. GPU torch install is vendored
#        from packages/ml/pytorch and packages/cuda/cudastack. See .assimilai.toml
#        for source tracking (https://assimilai.dev).
#---
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Versions — all ARG, overridable via --build-arg.
# cuDNN / NVPL / cuDSS / cuSPARSELt / cuTENSOR / NCCL: adapted from cudastack.
# torch / torchaudio: dissolved from packages/ml/pytorch.
ARG CUDNN_VERSION=9.20.0 \
    CUDNN_URL="https://developer.download.nvidia.com/compute/cudnn/9.20.0/local_installers/cudnn-local-repo-ubuntu2404-9.20.0_1.0-1_arm64.deb" \
    CUDNN_PACKAGES="libcudnn9-cuda-13 libcudnn9-dev-cuda-13" \
    NVPL_VERSION=25.11 \
    CUDSS_VERSION=0.7.1 \
    CUSPARSELT_VERSION=0.9.0 \
    CUTENSOR_VERSION=2.6.0 \
    NCCL_VERSION=2.28.7 \
    CUDA_VERSION_MAJOR=13 \
    CUDA_INSTALLED_VERSION=130 \
    CUDA_ARCH=aarch64 \
    DISTRO=ubuntu2404 \
    IS_SBSA=True \
    WGET_FLAGS="--quiet --tries=3 --timeout=60" \
    TORCH_VERSION=2.10.0 \
    TORCHAUDIO_VERSION=2.10.0

# Vendored cudastack install scripts (adapted from packages/cuda/cudastack/install/).
COPY cudastack_install_cudss.sh cudastack_install_cusparselt.sh \
     cudastack_install_cutensor.sh cudastack_install_nccl.sh \
     /tmp/cudastack/

# Single install+verify layer — per .claude/skills/standards/references/dockerfile.md
# "RUN layering": one RUN total when the verification is a trivial inline check.
# Per-source provenance lives in .assimilai.toml (source paths + sha256 + changes);
# each inline section below points at its manifest entry. The trailing metadata
# assertion is deliberately folded in here so the Dockerfile has a single RUN.
RUN set -eux; \
    # === cuDNN (adapted from packages/cuda/cudastack/install/install_cudnn.sh;
    # pinned 9.20.0 because upstream's 9.21.0 is a 404 on NVIDIA's CDN) ===
    cd /tmp && \
    wget --quiet --tries=3 --timeout=60 "${CUDNN_URL}" && \
    dpkg -i cudnn-local-repo-*.deb && \
    cp /var/cudnn-local-repo-*/cudnn-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true && \
    apt-get update && apt-get install -y --no-install-recommends ${CUDNN_PACKAGES} && \
    dpkg -P "cudnn-local-repo-ubuntu2404-${CUDNN_VERSION}" 2>/dev/null || true && \
    rm -rf /tmp/*.deb; \
    # === NVPL (adapted from install_nvpl.sh; torch's aarch64 wheels dlopen
    # libnvpl_lapack_lp64_gomp.so.0 at import time) ===
    cd /tmp && \
    wget --quiet --tries=3 --timeout=60 "https://developer.download.nvidia.com/compute/nvpl/${NVPL_VERSION}/local_installers/nvpl-local-repo-ubuntu2404-${NVPL_VERSION}_1.0-1_arm64.deb" && \
    dpkg -i nvpl-local-*.deb && \
    cp /var/nvpl-local-repo-*/nvpl-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true && \
    apt-get update && apt-get install -y --no-install-recommends nvpl && \
    rm -rf /tmp/*.deb; \
    # === cuDSS, cuSPARSELt, cuTENSOR, NCCL (adapted cudastack scripts;
    # see .assimilai.toml for per-script provenance) ===
    chmod +x /tmp/cudastack/*.sh && \
    /tmp/cudastack/cudastack_install_cudss.sh && \
    /tmp/cudastack/cudastack_install_cusparselt.sh && \
    /tmp/cudastack/cudastack_install_cutensor.sh && \
    /tmp/cudastack/cudastack_install_nccl.sh && \
    rm -rf /tmp/cudastack; \
    # === torch + torchaudio (dissolved from packages/ml/pytorch/install.sh and
    # torchaudio/install.sh — jetson-ai-lab SBSA/cu130 mirror wheels). NOTE:
    # torchaudio >=2.9 delegates .save() to torchcodec which needs FFmpeg >=7,
    # not available on Ubuntu 24.04 noble (ships FFmpeg 6). test.py soft-skips
    # that sub-test; soundfile.write() covers the same use case. ===
    uv pip install "torch==${TORCH_VERSION}" "torchaudio==${TORCHAUDIO_VERSION}"; \
    # === sound-utils' own audio stack (portaudio system headers +
    # python audio libs) ===
    apt-get update && apt-get install -y portaudio*-dev && \
    uv pip install soundfile sounddevice; \
    # === Cleanup ===
    rm -rf /var/lib/apt/lists/* && apt-get clean; \
    # === Verification: torch wheel carries CUDA metadata. Metadata only;
    # docker build isn't invoked with --gpus=all, so live torch.cuda.is_available()
    # belongs in test.py (runs with --gpus=all via container.py::test_container). ===
    python3 -c "import torch; \
assert torch.version.cuda is not None, 'Installed torch wheel does not include CUDA support'; \
print('torch', torch.__version__, 'built with CUDA', torch.version.cuda, 'cuDNN', torch.backends.cudnn.version()); \
print('Build-time check OK: torch imports and reports CUDA-enabled build metadata')"
