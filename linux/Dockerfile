# Kernel build image for rv32mbt (nommu RV32 Linux).
#
# Same pinned base as the main dev image; the kernel is built with
# clang/LLVM (make LLVM=-18) so no RISC-V GNU cross toolchain is
# needed. Kernel sources are fetched and sha256-verified by
# linux/build.sh, not baked into the image.
#
#   podman build -t rv32mbt-linux -f linux/Dockerfile linux
#   podman run --rm -v "$PWD:/work" rv32mbt-linux bash linux/build.sh
FROM docker.io/library/ubuntu:24.04@sha256:52df9b1ee71626e0088f7d400d5c6b5f7bb916f8f0c82b474289a4ece6cf3faf

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bc \
        bison \
        bzip2 \
        cmake \
        flex \
        make \
        perl \
        python3 \
        xz-utils \
        ca-certificates \
        curl \
        clang-18 \
        lld-18 \
        llvm-18 \
        llvm-18-dev \
        device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
