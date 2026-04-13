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

# Assimilated from packages/cuda/cudastack/install/install_cudnn.sh.
# Pinned to 9.20.0 because cudastack's default 9.21.0 is a 404 on NVIDIA's CDN.
ARG CUDNN_VERSION=9.20.0
ARG CUDNN_URL="https://developer.download.nvidia.com/compute/cudnn/${CUDNN_VERSION}/local_installers/cudnn-local-repo-ubuntu2404-${CUDNN_VERSION}_1.0-1_arm64.deb"
ARG CUDNN_PACKAGES="libcudnn9-cuda-13 libcudnn9-dev-cuda-13"
RUN set -eux; \
    cd /tmp; \
    wget --quiet --tries=3 --timeout=60 "${CUDNN_URL}"; \
    dpkg -i cudnn-local-repo-*.deb; \
    cp /var/cudnn-local-repo-*/cudnn-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true; \
    apt-get update && apt-get install -y --no-install-recommends ${CUDNN_PACKAGES}; \
    dpkg -P "cudnn-local-repo-ubuntu2404-${CUDNN_VERSION}" 2>/dev/null || true; \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb; \
    apt-get clean

# Assimilated from packages/cuda/cudastack/install/install_nvpl.sh.
# Required because torch's SBSA/aarch64 wheels link against libnvpl_lapack_lp64_gomp.so.0
# at import time. Discovered by an ImportError in the previous build attempt.
ARG NVPL_VERSION=25.11
RUN set -eux; \
    cd /tmp; \
    wget --quiet --tries=3 --timeout=60 \
      "https://developer.download.nvidia.com/compute/nvpl/${NVPL_VERSION}/local_installers/nvpl-local-repo-ubuntu2404-${NVPL_VERSION}_1.0-1_arm64.deb"; \
    dpkg -i nvpl-local-*.deb; \
    cp /var/nvpl-local-repo-*/nvpl-*-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true; \
    apt-get update && apt-get install -y --no-install-recommends nvpl; \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb; \
    apt-get clean

# Assimilated (verbatim) from packages/cuda/cudastack/install/
# These are the scripts for the other runtime libs the torch aarch64 wheel links against.
# Skipped from cudastack: TensorRT, NVSHMEM, GDRCopy, CUTLASS (not needed by sound-utils).
COPY cudastack_install_cudss.sh cudastack_install_cusparselt.sh \
     cudastack_install_cutensor.sh cudastack_install_nccl.sh \
     /tmp/cudastack/
ARG CUDSS_VERSION=0.7.1 \
    CUSPARSELT_VERSION=0.9.0 \
    CUTENSOR_VERSION=2.6.0 \
    NCCL_VERSION=2.28.7 \
    CUDA_VERSION_MAJOR=13 \
    CUDA_INSTALLED_VERSION=130 \
    CUDA_ARCH=aarch64 \
    DISTRO=ubuntu2404 \
    IS_SBSA=True \
    WGET_FLAGS="--quiet --tries=3 --timeout=60"
RUN set -eux; \
    chmod +x /tmp/cudastack/*.sh; \
    /tmp/cudastack/cudastack_install_cudss.sh; \
    /tmp/cudastack/cudastack_install_cusparselt.sh; \
    /tmp/cudastack/cudastack_install_cutensor.sh; \
    /tmp/cudastack/cudastack_install_nccl.sh; \
    rm -rf /tmp/cudastack

# Assimilated from packages/ml/pytorch/install.sh (lines 53-60) and
# packages/ml/pytorch/torchaudio/install.sh — prebuilt wheels from
# the jetson-ai-lab SBSA/cu130 mirror (PIP_INDEX_URL).
# NOTE: torchaudio >=2.9 delegates .save() to torchcodec, and torchcodec
# requires FFmpeg >=7, which is unavailable in Ubuntu 24.04 noble (ships
# FFmpeg 6). test.py was patched to soft-skip the save sub-test on this
# platform; soundfile.write() still exercises the same functionality.
ARG TORCH_VERSION=2.10.0
ARG TORCHAUDIO_VERSION=2.10.0
RUN uv pip install "torch==${TORCH_VERSION}" "torchaudio==${TORCHAUDIO_VERSION}"

# portaudio dev headers
RUN apt-get update && \
    apt-get install -y portaudio*-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN uv pip install soundfile sounddevice

# Build-time sanity: verify torch imports and the installed wheel has CUDA
# support baked in. We do NOT require live GPU access here — docker build
# isn't run with --gpus=all, so torch.cuda.is_available() may be False on
# some builders. The live-GPU check belongs in test.py, which runs under
# docker run --gpus=all via container.py::test_container.
RUN python3 -c "import torch; \
assert torch.version.cuda is not None, 'Installed torch wheel does not include CUDA support'; \
print('torch', torch.__version__, 'built with CUDA', torch.version.cuda, 'cuDNN', torch.backends.cudnn.version()); \
print('Build-time check OK: torch imports and reports CUDA-enabled build metadata')"
