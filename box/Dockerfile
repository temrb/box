# syntax=docker/dockerfile:1
# Single Dockerfile with 3 targets: base, muse, opencode.
# Build with: docker build --file Dockerfile --target muse|opencode --pull ...
# Both tool images share base layers (Debian + common toolchain + box
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
    test -x /usr/local/bin/muse && test -f /usr/local/bin/muse && test ! -L /usr/local/bin/muse

RUN mkdir -p /workspace /persist/data/muse /persist/state/muse \
       /home/box/.config/muse /home/box/.cache /home/box/.local/bin \
    && ln -s /persist/data/muse /home/box/.muse \
    && touch /persist/data/muse/.volume-seed /persist/state/muse/.volume-seed \
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
ARG OPENCODE_NPM_INTEGRITY
ARG OPENCODE_NPM_INTEGRITY_LINUX_X64
ARG OPENCODE_NPM_INTEGRITY_LINUX_ARM64
# Toolchain pins from version-opencode.env (single source via lib/pins.sh):
# exact NodeSource package + fail-closed APT key fingerprint.
ARG NODE_VERSION
ARG NODESOURCE_FINGERPRINT

LABEL org.opencode.box.version=${OPENCODE_VERSION} \
      org.opencode.box.npm-integrity=${OPENCODE_NPM_INTEGRITY} \
      org.opencode.box.npm-integrity-linux-x64=${OPENCODE_NPM_INTEGRITY_LINUX_X64} \
      org.opencode.box.npm-integrity-linux-arm64=${OPENCODE_NPM_INTEGRITY_LINUX_ARM64} \
      org.box.tool=opencode

RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 via the upstream NodeSource repository (Debian trixie ships an
# older Node; OpenCode requires a current LTS). The APT key is vendored as
# keys/nodesource.asc (ASCII-armored, LF-only) and verified fail-closed by
# the NODESOURCE_FINGERPRINT pin from version-opencode.env (single source via
# lib/pins.sh; record live-key date in commit) before apt-get update. The key
# holds a primary + encryption subkey (2 `fpr:` lines); the build asserts the
# count and that the first (primary) fingerprint matches the pin. nodejs
# is pinned exact to ${NODE_VERSION} (amd64+arm64 verified same via
# binary-amd64/arm64 Packages on 2026-09-06).
# (Engine >= 25 + Linux-only requirement: see the base-stage note above.)
COPY keys/nodesource.asc /tmp/nodesource.asc
RUN set -euo pipefail; \
    test -n "${NODE_VERSION:-}" && test -n "${NODESOURCE_FINGERPRINT:-}"; \
    mkdir -p /etc/apt/keyrings; \
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg /tmp/nodesource.asc && rm /tmp/nodesource.asc; \
    fpr_count=$(gpg --show-keys --with-colons /etc/apt/keyrings/nodesource.gpg | grep -c '^fpr:'); test "$fpr_count" = 2; \
    fpr=$(gpg --show-keys --with-colons /etc/apt/keyrings/nodesource.gpg | awk -F: '/^fpr:/ {print $10; exit}'); test "$fpr" = "${NODESOURCE_FINGERPRINT}"; \
    NODE_MAJOR=${NODE_VERSION%%.*}; \
    case "$NODE_MAJOR" in ''|*[!0-9]*) echo 'Cannot derive NODE_MAJOR from NODE_VERSION' >&2; exit 1;; esac; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "nodejs=${NODE_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    node --version; npm --version

# OpenCode install per upstream docs (`npm i -g`), NOT the curl|bash install
# script (pipe-to-shell is explicitly rejected for image builds: it defeats
# fail-closed verification). npm fetches over TLS and verifies registry
# integrity on every tarball. All three `dist.integrity` pins from
# version-opencode.env (wrapper + both platform binaries, single source via
# lib/pins.sh) are enforced here in two layers (fail-closed): first pinned
# `npm view --json` + `jq -r` metadata asserts, then tarball-to-pin `sha512`
# verification of the actual packed bytes via `npm pack` (matching the Muse
# path's tarball-to-pin strength: `sha256sum --check`). Only then does
# `npm install -g` run; the platform-binary pins are additionally recorded in
# the image labels for audit and compared at run by box_assert_image. The
# final assert requires the
# installed CLI to report exactly the pinned version. npm's global prefix is
# distro-dependent (NodeSource uses /usr, not /usr/local) and its bin entry
# is a symlink, so the resolved real binary is copied to a regular file at
# the deterministic /usr/local/bin/opencode path (asserted -x + -f + not -L;
# the artifact is a self-contained native executable). Install scripts run as
# part of `npm install -g` (platform binaries need them); the build runs on
# an isolated network with no secrets, and the runtime container drops all
# capabilities with no-new-privileges under gVisor.
# npm cache mount (BuildKit): the 3 `npm pack` tarballs + `npm install -g`
# below re-download on every build without it. The mount persists across
# builds outside the image, so no `npm cache clean` is needed (cleaning here
# would wipe the persistent cache); the image stays small because the mount
# is never committed.
RUN --mount=type=cache,target=/root/.npm \
    set -euo pipefail; \
    test -n "${OPENCODE_VERSION:-}" && test -n "${OPENCODE_NPM_INTEGRITY:-}" && test -n "${OPENCODE_NPM_INTEGRITY_LINUX_X64:-}" && test -n "${OPENCODE_NPM_INTEGRITY_LINUX_ARM64:-}"; \
    case "$TARGETARCH" in \
      amd64|arm64) ;; \
      *) echo 'Only amd64 and arm64 are supported' >&2; exit 1;; \
    esac; \
    actual=$(npm view "opencode-ai@${OPENCODE_VERSION}" --json | jq -e -r 'if has("dist") and (.dist|has("integrity")) then .dist.integrity else error("missing dist.integrity") end'); \
    test "$actual" = "$OPENCODE_NPM_INTEGRITY"; \
    actual_x64=$(npm view "opencode-linux-x64@${OPENCODE_VERSION}" --json | jq -e -r 'if has("dist") and (.dist|has("integrity")) then .dist.integrity else error("missing dist.integrity") end'); \
    test "$actual_x64" = "$OPENCODE_NPM_INTEGRITY_LINUX_X64"; \
    actual_arm64=$(npm view "opencode-linux-arm64@${OPENCODE_VERSION}" --json | jq -e -r 'if has("dist") and (.dist|has("integrity")) then .dist.integrity else error("missing dist.integrity") end'); \
    test "$actual_arm64" = "$OPENCODE_NPM_INTEGRITY_LINUX_ARM64"; \
    pack_dir=$(mktemp -d); trap 'rm -rf "$pack_dir"' EXIT; \
    cd "$pack_dir" \
    && for spec in "opencode-ai@${OPENCODE_VERSION}:$OPENCODE_NPM_INTEGRITY" \
        "opencode-linux-x64@${OPENCODE_VERSION}:$OPENCODE_NPM_INTEGRITY_LINUX_X64" \
        "opencode-linux-arm64@${OPENCODE_VERSION}:$OPENCODE_NPM_INTEGRITY_LINUX_ARM64"; do \
      pkg=${spec%%:*}; want=${spec#*:}; \
      rm -f ./*.tgz; \
      tgz=$(npm pack "$pkg" --silent 2>/dev/null | tail -n 1); \
      test -n "$tgz" && test -f "$tgz" && test "${tgz%.tgz}" != "$tgz"; \
      test "$(ls -1 ./*.tgz | wc -l)" -eq 1; \
      got=$(node -e 'const crypto=require("crypto"),fs=require("fs");process.stdout.write("sha512-"+crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64"))' "$tgz"); \
      test "$got" = "$want"; \
    done \
    && cd / && rm -rf "$pack_dir"; trap - EXIT; \
    npm install -g --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}"; \
    installed_version=$(opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?' | head -n 1); \
    test "$installed_version" = "$OPENCODE_VERSION"; \
    npm_bin=$(command -v opencode); \
    test -n "$npm_bin"; \
    real_bin=$(readlink -e "$npm_bin"); \
    test -n "$real_bin" && test -x "$real_bin" && test -f "$real_bin" && test ! -L "$real_bin"; \
    install -m 0755 "$real_bin" /usr/local/bin/opencode; \
    test -x /usr/local/bin/opencode && test -f /usr/local/bin/opencode && test ! -L /usr/local/bin/opencode; \
    /usr/local/bin/opencode --version

RUN : "${HOST_UID:?Pass --build-arg HOST_UID=<host uid>}" "${HOST_GID:?Pass --build-arg HOST_GID=<host gid>}"; \
    test "$HOST_UID" -gt 0 && test "$HOST_GID" -gt 0 \
    && mkdir -p /workspace /persist/data/opencode /persist/state/opencode \
       /home/box/.config/opencode /home/box/.cache /home/box/.local/bin /home/box/.local/share \
    && ln -s /persist/data/opencode /home/box/.local/share/opencode \
    && touch /persist/data/opencode/.volume-seed /persist/state/opencode/.volume-seed \
    && chown -R "$HOST_UID:$HOST_GID" /workspace /persist /home/box

# Base ENV/USER/WORKDIR are inherited; this stage sets deltas only
# (XDG data/state split + auto-update opt-out). USER is re-asserted (not a
# delta) because the install steps above ran as 0:0.
ENV XDG_DATA_HOME=/persist/data/opencode \
    XDG_STATE_HOME=/persist/state/opencode \
    OPENCODE_DISABLE_AUTOUPDATE=1
USER ${HOST_UID}:${HOST_GID}
ENTRYPOINT ["/usr/local/bin/opencode"]
