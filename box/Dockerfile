# syntax=docker/dockerfile:1
# Single Dockerfile with base + explicit muse, opencode, codex targets.
# Build only through make build-<stem>.
# All harness images share base layers (Debian + common toolchain + box
# user).
# All RUN steps use bash with pipefail (default /bin/sh is dash on
# trixie-slim, where `pipefail` is a no-op and find|head failures go silent).
# SHELL is per-stage (it cannot appear before the first FROM and resets on
# every FROM), so each target repeats the canonical SHELL below.
FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# No defaults (fail closed like the version ARGs): setup.sh and the Makefile
# thread --build-arg HOST_UID/HOST_GID from `id`; a bare `docker build`
# without them fails below with a clean message instead of baking 1000:1000.
ARG HOST_UID
ARG HOST_GID

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash build-essential ca-certificates curl fd-find findutils git grep \
    jq libcap2-bin procps ripgrep tree unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Base image pinned to manifest-list digest
# sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132
# pin-date: 2026-09-06 (Debian trixie-slim 2026-08-24); re-pin on every Debian point
# release and record the digest + date in the commit message.
# Requires Docker Engine >= 25 with bind-recursive support
# (see launcher mount flags) and Linux-only (macOS unsupported: runsc +
# UID/GID-matched rootful Engine are Linux-only).
# Clean-fail when HOST_* ARGs are missing (empty would otherwise report a
# confusing `integer expression expected` from test(1) below).
RUN : "${HOST_UID:?Pass --build-arg HOST_UID=<host uid>}" "${HOST_GID:?Pass --build-arg HOST_GID=<host gid>}"; \
    test "$HOST_UID" -gt 0 && test "$HOST_GID" -gt 0 \
    && (getent group "$HOST_GID" >/dev/null || groupadd --gid "$HOST_GID" box) \
    && ( ! getent passwd "$HOST_UID" >/dev/null || { echo 'UID already exists in base image; pick a base image without that UID' >&2; exit 1; }) \
    && useradd --uid "$HOST_UID" --gid "$HOST_GID" --create-home --shell /bin/bash box \
    && mkdir -p /workspace \
    && chown -R "$HOST_UID:$HOST_GID" /workspace /home/box

ENV XDG_CONFIG_HOME=/home/box/.config \
    XDG_CACHE_HOME=/home/box/.cache \
    HOME=/home/box \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/box/.local/bin \
    SHELL=/bin/bash
USER ${HOST_UID}:${HOST_GID}
WORKDIR /workspace

# --- Muse target ---
FROM base AS muse
# SHELL is per-stage: repeat in every target (see base).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0:0

ARG TARGETARCH
# HOST_* redeclared without defaults (global ARGs do not propagate into
# named stages without a per-stage declaration); same fail-closed rule.
ARG HOST_UID
ARG HOST_GID
# No defaults: require --build-arg (setup.sh threads pins from
# version-muse.env; bare `docker build` without args fails closed instead of
# baking a stale default).
ARG MUSE_VERSION
ARG MUSE_SHA256_AMD64
ARG MUSE_SHA256_ARM64

LABEL org.meta.muse.box.version=${MUSE_VERSION} \
      org.meta.muse.box.sha256-amd64=${MUSE_SHA256_AMD64} \
      org.meta.muse.box.sha256-arm64=${MUSE_SHA256_ARM64} \
      org.box.tool=muse

RUN apt-get update && apt-get install -y --no-install-recommends \
    bubblewrap libgcc-s1 libseccomp2 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Single documented HTTPS download (no fallback URL): any fallback host would
# need independent hash/signature pinning, otherwise it defeats fail-closed
# verification. Version + checksums pinned in version-muse.env; artifact URL
# follows the official channel manifest served by api.meta.ai (binaries are
# hosted on lookaside.facebook.com and are raw executables, not tarballs).
RUN set -euo pipefail; \
    test -n "${MUSE_VERSION:-}" && test -n "${MUSE_SHA256_AMD64:-}" && test -n "${MUSE_SHA256_ARM64:-}"; \
    case "$TARGETARCH" in \
      amd64) arch=x86; checksum="$MUSE_SHA256_AMD64";; \
      arm64) arch=aarch64; checksum="$MUSE_SHA256_ARM64";; \
      *) echo 'Only amd64 and arm64 are supported' >&2; exit 1;; \
    esac; \
    curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 600 \
      "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${MUSE_VERSION}&file=muse-${arch}-linux" \
      -o /tmp/muse; \
    printf '%s  %s\n' "$checksum" /tmp/muse | sha256sum --check -; \
    install -m 0755 /tmp/muse /usr/local/bin/muse; \
    rm /tmp/muse; \
    test -x /usr/local/bin/muse && test -f /usr/local/bin/muse && test ! -L /usr/local/bin/muse; \
    installed_version=$(/usr/local/bin/muse --version); \
    test "$installed_version" = "Muse Code ${MUSE_VERSION%%-*} ($MUSE_VERSION)"

RUN mkdir -p /workspace /persist/data/muse /persist/state/muse \
       /home/box/.config/muse /home/box/.cache /home/box/.local/bin \
    && ln -s /persist/data/muse /home/box/.muse \
    && touch /persist/data/muse/.volume-seed /persist/state/muse/.volume-seed \
    && chmod 700 /persist \
    && chown -R "$HOST_UID:$HOST_GID" /workspace /persist /home/box

# Base ENV/USER/WORKDIR are inherited; this stage sets deltas only
# (XDG data/state split + auto-update opt-out). USER is re-asserted (not a
# delta) because the install steps above ran as 0:0.
ENV XDG_DATA_HOME=/persist/data/muse \
    XDG_STATE_HOME=/persist/state/muse \
    MUSE_NO_AUTO_UPDATE=1
USER ${HOST_UID}:${HOST_GID}
ENTRYPOINT ["/usr/local/bin/muse"]

# --- OpenCode target ---
FROM base AS opencode
COPY harnesses/opencode/archive.py /tmp/box-opencode-archive.py
# SHELL is per-stage: repeat in every target (see base).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0:0

ARG TARGETARCH
# HOST_* redeclared without defaults (global ARGs do not propagate into
# named stages without a per-stage declaration); same fail-closed rule.
ARG HOST_UID
ARG HOST_GID
# No defaults: require --build-arg (setup.sh threads pins from
# version-opencode.env; bare `docker build` without args fails closed instead
# of baking a stale default).
ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_AMD64
ARG OPENCODE_SHA256_ARM64

LABEL org.opencode.box.version=${OPENCODE_VERSION} \
      org.opencode.box.sha256-amd64=${OPENCODE_SHA256_AMD64} \
      org.opencode.box.sha256-arm64=${OPENCODE_SHA256_ARM64} \
      org.box.tool=opencode

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Pinned standalone v2 binary (glibc): amd64 uses the x64-baseline archive,
# arm64 uses the arm64 archive. Both URLs + SHA256 are frozen in
# version-opencode.env; archive bytes are hash-checked before extraction,
# layout asserts exactly one executable `opencode`, and the installed version
# must read `opencode v<VER>` (v prefix + name).
RUN set -euo pipefail; \
    test -n "${OPENCODE_VERSION:-}" && test -n "${OPENCODE_SHA256_AMD64:-}" && test -n "${OPENCODE_SHA256_ARM64:-}"; \
    case "$TARGETARCH" in \
      amd64) platform=x64-baseline; checksum="$OPENCODE_SHA256_AMD64";; \
      arm64) platform=arm64; checksum="$OPENCODE_SHA256_ARM64";; \
      *) echo 'Only amd64 and arm64 are supported' >&2; exit 1;; \
    esac; \
    curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 600 \
      "https://opencode.ai/files/bin/${OPENCODE_VERSION}/opencode-linux-${platform}.tar.gz" \
      -o /tmp/opencode.tar.gz; \
    printf '%s  %s\n' "$checksum" /tmp/opencode.tar.gz | sha256sum --check -; \
    python3 /tmp/box-opencode-archive.py /tmp/opencode.tar.gz "$TARGETARCH"; \
    mkdir -p /tmp/extracted; tar -xzf /tmp/opencode.tar.gz -C /tmp/extracted; \
    test -f /tmp/extracted/opencode && test ! -L /tmp/extracted/opencode; \
    test -x /tmp/extracted/opencode; \
    install -m 0755 /tmp/extracted/opencode /usr/local/bin/opencode; \
    rm -rf /tmp/extracted /tmp/opencode.tar.gz /tmp/box-opencode-archive.py; \
    test -x /usr/local/bin/opencode && test ! -L /usr/local/bin/opencode; \
    installed_version=$(/usr/local/bin/opencode --version); \
    test "$installed_version" = "opencode v$OPENCODE_VERSION"

COPY --chmod=755 harnesses/opencode/entrypoint.sh /usr/local/bin/box-opencode

RUN : "${HOST_UID:?Pass --build-arg HOST_UID=<host uid>}" "${HOST_GID:?Pass --build-arg HOST_GID=<host gid>}"; \
    test "$HOST_UID" -gt 0 && test "$HOST_GID" -gt 0 \
    && mkdir -p /workspace /persist/config/opencode /persist/data/opencode /persist/state/opencode \
       /home/box/.config/opencode /home/box/.cache /home/box/.local/bin /home/box/.local/share \
    && ln -s /persist/data/opencode /home/box/.local/share/opencode \
    && touch /persist/data/opencode/.volume-seed /persist/state/opencode/.volume-seed \
    && chmod 700 /persist /persist/config /persist/config/opencode \
    && chown -R "$HOST_UID:$HOST_GID" /workspace /persist /home/box

# Base ENV/USER/WORKDIR are inherited; this stage sets deltas only
# (XDG data/state split + auto-update opt-out). USER is re-asserted (not a
# delta) because the install steps above ran as 0:0.
ENV XDG_CONFIG_HOME=/persist/config \
    XDG_DATA_HOME=/persist/data/opencode \
    XDG_STATE_HOME=/persist/state/opencode \
    OPENCODE_DISABLE_AUTOUPDATE=1
USER ${HOST_UID}:${HOST_GID}
ENTRYPOINT ["/usr/local/bin/box-opencode"]

# --- Codex target: complete release package, including required companions ---
FROM base AS codex
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER 0:0
ARG TARGETARCH
ARG HOST_UID
ARG HOST_GID
ARG CODEX_VERSION
ARG CODEX_SHA256_AMD64
ARG CODEX_SHA256_ARM64
LABEL org.openai.codex.box.version=${CODEX_VERSION} \
      org.openai.codex.box.sha256-amd64=${CODEX_SHA256_AMD64} \
      org.openai.codex.box.sha256-arm64=${CODEX_SHA256_ARM64} \
      org.box.tool=codex
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
RUN set -euo pipefail; \
    : "${CODEX_VERSION:?}" "${CODEX_SHA256_AMD64:?}" "${CODEX_SHA256_ARM64:?}"; \
    case "$TARGETARCH" in \
      amd64) arch=x86_64; checksum="$CODEX_SHA256_AMD64";; \
      arm64) arch=aarch64; checksum="$CODEX_SHA256_ARM64";; \
      *) echo 'Only amd64 and arm64 artifacts are available; native evidence required' >&2; exit 1;; \
    esac; \
    curl --fail --silent --show-error --proto '=https' --tlsv1.2 --location --retry 3 --connect-timeout 15 --max-time 600 \
      "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-package-${arch}-unknown-linux-musl.tar.gz" -o /tmp/codex.tar.gz; \
    printf '%s  %s\n' "$checksum" /tmp/codex.tar.gz | sha256sum --check -; \
    mkdir -p /opt/codex; tar -xzf /tmp/codex.tar.gz -C /opt/codex; rm /tmp/codex.tar.gz; \
    test -f /opt/codex/bin/codex && test ! -L /opt/codex/bin/codex; \
    test -x /opt/codex/bin/codex-code-mode-host && test -x /opt/codex/codex-resources/bwrap; \
    test -x /opt/codex/codex-path/rg && test -f /opt/codex/codex-package.json; \
    ln -s /opt/codex/bin/codex /usr/local/bin/codex; \
    installed_version=$(codex --version); test "$installed_version" = "codex-cli $CODEX_VERSION"
COPY harnesses/codex/policy/requirements.toml /etc/codex/requirements.toml
RUN chown 0:0 /etc/codex/requirements.toml && chmod 644 /etc/codex/requirements.toml \
    && mkdir -p /persist/state/codex /home/box/.codex /home/box/.cache \
    && touch /persist/state/codex/.volume-seed \
    && chmod 700 /persist \
    && chown -R "$HOST_UID:$HOST_GID" /persist /home/box
ENV CODEX_HOME=/home/box/.codex
USER ${HOST_UID}:${HOST_GID}
ENTRYPOINT ["/opt/codex/bin/codex"]
