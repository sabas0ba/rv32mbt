# Development / CI image for rv32mbt.
#
# Provides the MoonBit toolchain (native + js backends) and clang-18 +
# lld-18 for building the riscv-tests harness (tests/build_tests.sh).
# The repository is expected to be bind-mounted at /work:
#
#   podman build -t rv32mbt-dev .
#   podman run --rm -v "$PWD:/work" rv32mbt-dev moon check
#
# Version pinning:
#   - Base image is pinned by digest (ubuntu:24.04).
#   - MoonBit is pinned via MOON_VERSION (see docs/toolchain.md).
#   - apt package versions are determined by the base image snapshot at
#     build time; the versions actually used are recorded in
#     docs/toolchain.md.
FROM docker.io/library/ubuntu:24.04@sha256:52df9b1ee71626e0088f7d400d5c6b5f7bb916f8f0c82b474289a4ece6cf3faf

# MoonBit toolchain pinning: cli.moonbitlang.com serves only "latest"
# (versioned URLs return 403), so the tarballs are verified against
# sha256 digests and the installed version string is asserted. If
# upstream publishes a new build, the digest check fails the build and
# the pins below must be updated together (see docs/toolchain.md).
# moon 0.1.20260713 (75c7e1f) / moonc v0.10.4+2cc641edf
ARG MOON_VERSION=0.1.20260713
ARG MOONBIT_SHA256=31b7fc5cc78657964a6d545792ecd7fb8eed51b97c7431a17458b58734303381
ARG CORE_SHA256=03ad55b99f3e431f3cb81b4e2bb28bb98173304e4a1b18a891ea027cabba5d1c

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        python3 \
        clang-18 \
        lld-18 \
        device-tree-compiler \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/clang-18 /usr/local/bin/clang \
    && ln -s /usr/bin/clang-18 /usr/local/bin/cc \
    && ln -s /usr/bin/ld.lld-18 /usr/local/bin/ld.lld \
    && ln -s /usr/bin/ar /usr/local/bin/ar \
    && ln -s /usr/bin/ranlib /usr/local/bin/ranlib

# MOON_HOME outside $HOME so the toolchain is usable regardless of the
# invoking user. Steps mirror install/unix.sh, plus digest verification.
ENV MOON_HOME=/opt/moon
ENV PATH=/opt/moon/bin:$PATH
# `sha256sum -c` reports a mismatch without saying what it got, which
# leaves whoever hits an upstream rotation with nothing to act on.
# Report both digests and point at the update procedure, so the fix is
# to paste the printed value into the ARGs above.
RUN set -e; \
    verify() { \
      got=$(sha256sum "$2" | cut -d' ' -f1); \
      [ "$1" = "$got" ] && return 0; \
      echo "ERROR: $2 does not match its pinned digest." >&2; \
      echo "  expected: $1" >&2; \
      echo "  actual:   $got" >&2; \
      echo "cli.moonbitlang.com serves only 'latest', so upstream has published a" >&2; \
      echo "new build. Update MOON_VERSION/MOONBIT_SHA256/CORE_SHA256 in this" >&2; \
      echo "Dockerfile and the version table in docs/toolchain.md together; see" >&2; \
      echo "'Updating a pinned version' there." >&2; \
      exit 1; \
    }; \
    curl -fsSL -o /tmp/moonbit.tar.gz https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz \
    && verify "$MOONBIT_SHA256" /tmp/moonbit.tar.gz \
    && mkdir -p /opt/moon \
    && tar xf /tmp/moonbit.tar.gz -C /opt/moon \
    && rm /tmp/moonbit.tar.gz \
    && chmod +x /opt/moon/bin/* /opt/moon/bin/internal/tcc \
    && ln -sfn moon /opt/moon/bin/moonx \
    && { moon version | grep -F "$MOON_VERSION" \
         || { echo "ERROR: expected moon $MOON_VERSION, got: $(moon version)" >&2; \
              echo "Update MOON_VERSION in this Dockerfile and docs/toolchain.md." >&2; \
              exit 1; }; } \
    && curl -fsSL -o /tmp/core.tar.gz https://cli.moonbitlang.com/cores/core-latest.tar.gz \
    && verify "$CORE_SHA256" /tmp/core.tar.gz \
    && mkdir -p /opt/moon/lib \
    && tar xf /tmp/core.tar.gz -C /opt/moon/lib \
    && rm /tmp/core.tar.gz \
    && moon -C /opt/moon/lib/core bundle --warn-list -a --all \
    && moon -C /opt/moon/lib/core bundle --warn-list -a --target wasm-gc --quiet \
    && moon version --all

WORKDIR /work
