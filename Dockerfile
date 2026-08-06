# syntax=docker/dockerfile:1
#
# OpenClaw gateway image.
#
# LAYER ORDER IS DELIBERATE: stable-and-huge first, volatile-and-pinned last.
# Chromium alone is ~1.5 GB, so anything placed above it gets reinstalled on
# every bump of anything below it. Keep new additions in the right band.
#
#   1. apt system packages      stable
#   2. GitHub CLI               stable
#   3. Playwright + Chromium    stable, ~1.5 GB  <-- never move below here
#   4. uv, bun                  stable
#   5. Python CLIs (floating)   refreshed on rebuild
#   6. npm CLIs (floating)      refreshed on rebuild
#   7. GitHub-release binaries  PINNED, Renovate-tracked  <-- cheap to rebuild
#
# Base image tags are bare (`2026.7.1`). The GitHub *release* tags carry a `v`
# prefix and a build suffix (`v2026.7.1-2`) — a DIFFERENT namespace. Renovate
# must use datasource=docker here, never github-releases.

# renovate: datasource=docker depName=ghcr.io/openclaw/openclaw
ARG BASE_VERSION=2026.7.1
FROM ghcr.io/openclaw/openclaw:${BASE_VERSION}

USER root

# Docker's default shell is `/bin/sh -c`, which on Debian is dash — and dash
# does not support `set -o pipefail`. That matters below: `curl -f … | tar xz`
# returns *tar's* exit status by default, so a 404 makes curl fail while tar
# succeeds on empty input and the build proceeds with a missing binary. This
# is the exact failure mode the smoke test exists to catch; pipefail stops it
# one step earlier.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]


# ── 1. System packages ───────────────────────────────────────────────
RUN apt-get update && apt-get upgrade -y \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    tree jq zip unzip \
    ripgrep fd-find \
    poppler-utils \
    tesseract-ocr \
    sqlite3 \
    file \
    dos2unix \
    iputils-ping \
    lsof \
    ffmpeg imagemagick libimage-exiftool-perl \
    pandoc \
    python3 \
    python3-pip \
    xvfb \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
  && ln -sf /usr/bin/python3 /usr/bin/python \
  && ln -sf /usr/bin/pip3 /usr/local/bin/pip


# ── 2. GitHub CLI ────────────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*


# ── 3. Playwright + Chromium (~1.5 GB — keep everything volatile BELOW) ──
# Chromium binaries → /opt/playwright (so the /home/node bind mount can't
# shadow them). Full playwright package → /opt/playwright-pkg, isolated from
# /app's npm tree to avoid peer-dep conflicts with OpenClaw's devDependencies.
RUN export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
  && mkdir -p /opt/playwright /opt/playwright-pkg \
  && node /app/node_modules/playwright-core/cli.js install --with-deps chromium \
  && ln -sf /opt/playwright/chromium-*/chrome-linux64/chrome /usr/local/bin/chromium \
  && PW_VERSION=$(node -p "require('/app/node_modules/playwright-core/package.json').version") \
  && cd /opt/playwright-pkg \
  && npm init -y >/dev/null \
  && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund --omit=dev "playwright@${PW_VERSION}" \
  && ln -sf /opt/playwright-pkg/node_modules/playwright /app/node_modules/playwright \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright


# ── 4. uv and bun ────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN curl -fsSL https://bun.sh/install | bash && mv /root/.bun /opt/bun
ENV PATH="/opt/bun/bin:$PATH"


# ── 5-6. Floating CLIs (deliberately unpinned) ───────────────────────
# These ship far too often to track: codex ~3600 releases/yr, gemini-cli ~630,
# claude-code ~316. Pinning them would mean a PR flood. They pick up whatever
# is current whenever this layer rebuilds — which happens on every base-image
# bump (~9/month), or on demand via the workflow's "refresh_floating" input.
#
# Docker caches by instruction text, so these layers will NOT refresh on a
# cached rebuild unless FLOATING_REFRESH changes. That is what the build arg
# is for; the workflow sets it to the run id when you ask for a refresh.
ARG FLOATING_REFRESH=0

RUN echo "refresh=${FLOATING_REFRESH}" >/dev/null \
  && uv pip install --system --break-system-packages nano-pdf

# npm globals install to the system prefix — this must stay ABOVE the
# NPM_CONFIG_PREFIX assignment further down, or they land in /home/node
# and get shadowed by the bind mount at runtime.
RUN echo "refresh=${FLOATING_REFRESH}" >/dev/null \
  && npm install -g \
    @anthropic-ai/claude-code \
    @google/gemini-cli \
    @doist/todoist-cli \
    mcporter \
    clawhub


# ── 7. Pinned release binaries (Renovate-tracked) ────────────────────
# Cheapest layer to rebuild, so it goes last. All of these publish
# goreleaser-style tarballs: <name>_<version-no-v>_linux_amd64.tar.gz

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.53.3
# renovate: datasource=github-releases depName=yt-dlp/yt-dlp versioning=loose
ARG YTDLP_VERSION=2026.07.04
# renovate: datasource=github-releases depName=openclaw/gogcli
ARG GOGCLI_VERSION=v0.34.1
# gws is being replaced by gog, but ~22 skills (gws-gmail, gws-calendar,
# gws-drive, gws-sheets, gws-docs, gws-slides, gws-people, and the recipe-*
# family) still shell out to `gws`. Both ship until those are migrated; drop
# this ARG and its fetch line below once they are.
# The musl build avoids the GLIBC 2.39 requirement of the default glibc build.
# renovate: datasource=github-releases depName=googleworkspace/cli
ARG GWS_VERSION=v0.22.5
# renovate: datasource=github-releases depName=steipete/camsnap
ARG CAMSNAP_VERSION=v0.3.0
# renovate: datasource=github-releases depName=openclaw/goplaces
ARG GOPLACES_VERSION=v0.4.4
# renovate: datasource=github-releases depName=steipete/sonoscli
ARG SONOSCLI_VERSION=v0.3.4
# renovate: datasource=github-releases depName=openclaw/spogo
ARG SPOGO_VERSION=v0.10.3
# renovate: datasource=github-releases depName=xdevplatform/xurl
ARG XURL_VERSION=v1.3.1

# fetch() takes a full URL because these projects do NOT share one asset
# convention, and the convention is not stable over time. spogo changed from
# `spogo_0.10.1_linux_amd64.tar.gz` to `spogo_0.10.3_spogo_linux_amd64_v1.tar.gz`
# at v0.10.2, which silently broke the previous string-templated version of this
# Dockerfile. Assume the next one will move too.
#
# Extraction goes via a temp dir + `find` rather than `tar xz <name>` because
# archive layouts differ: gogcli ships `gog` at the root, spogo ships `./spogo`.
# If the binary isn't in the tarball, this fails loudly instead of leaving a
# working-looking image with a missing tool.
RUN set -euo pipefail; \
    curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"; \
    curl -fsSL -o /usr/local/bin/yt-dlp \
      "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp"; \
    chmod +x /usr/local/bin/yq /usr/local/bin/yt-dlp; \
    fetch() { \
      local url="$1" bin="$2" tmp found; \
      tmp="$(mktemp -d)"; \
      curl -fsSL "$url" | tar xz -C "$tmp"; \
      found="$(find "$tmp" -type f -name "$bin" -print -quit)"; \
      if [ -z "$found" ]; then echo "fetch: '$bin' not found in $url" >&2; return 1; fi; \
      install -m 0755 "$found" "/usr/local/bin/$bin"; \
      rm -rf "$tmp"; \
    }; \
    fetch "https://github.com/openclaw/gogcli/releases/download/${GOGCLI_VERSION}/gogcli_${GOGCLI_VERSION#v}_linux_amd64.tar.gz"        gog;      \
    fetch "https://github.com/googleworkspace/cli/releases/download/${GWS_VERSION}/google-workspace-cli-x86_64-unknown-linux-musl.tar.gz" gws;    \
    fetch "https://github.com/steipete/camsnap/releases/download/${CAMSNAP_VERSION}/camsnap_${CAMSNAP_VERSION#v}_linux_amd64.tar.gz"    camsnap;  \
    fetch "https://github.com/openclaw/goplaces/releases/download/${GOPLACES_VERSION}/goplaces_${GOPLACES_VERSION#v}_linux_amd64.tar.gz" goplaces; \
    fetch "https://github.com/steipete/sonoscli/releases/download/${SONOSCLI_VERSION}/sonoscli_${SONOSCLI_VERSION#v}_linux_amd64.tar.gz" sonos;    \
    fetch "https://github.com/openclaw/spogo/releases/download/${SPOGO_VERSION}/spogo_${SPOGO_VERSION#v}_spogo_linux_amd64_v1.tar.gz"   spogo;    \
    fetch "https://github.com/xdevplatform/xurl/releases/download/${XURL_VERSION}/xurl_Linux_x86_64.tar.gz"                             xurl


# ── 8. Pinned Python / npm tools ─────────────────────────────────────
# These ship rarely enough to track, unlike the CLIs in band 6.

# renovate: datasource=pypi depName=markitdown
ARG MARKITDOWN_VERSION=0.1.7
# renovate: datasource=pypi depName=Faker
ARG FAKER_VERSION=40.36.0
# renovate: datasource=pypi depName=transcriber-cli
ARG TRANSCRIBER_CLI_VERSION=0.2.0
# renovate: datasource=npm depName=@firecrawl/anydoc
ARG ANYDOC_VERSION=0.1.6

# markitdown's format converters are optional extras — the bare package cannot
# read pdf/docx/pptx/xlsx at all. The document extras are selected explicitly
# rather than using [all], which additionally drags in the Azure Document
# Intelligence and OpenAI SDKs that nothing here uses.
RUN uv pip install --system --break-system-packages \
      "markitdown[pdf,docx,pptx,xlsx,xls,outlook]==${MARKITDOWN_VERSION}" \
      "Faker==${FAKER_VERSION}" \
      "transcriber-cli==${TRANSCRIBER_CLI_VERSION}"

# anydoc's Python wheel ships no console script — the CLI exists only in the
# npm package. Installs globally, so this must stay ABOVE the
# NPM_CONFIG_PREFIX assignment below.
RUN npm install -g "@firecrawl/anydoc@${ANYDOC_VERSION}"


# ── Runtime package-manager paths ────────────────────────────────────
# Must come AFTER the global npm install above.
#   npm → /home/node/.npm-global/   bun → /home/node/.bun/
#   pip → /home/node/.local/        uvx → /home/node/.cache/uv/
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV BUN_INSTALL=/home/node/.bun
ENV PATH="/home/node/.bun/bin:/home/node/.npm-global/bin:/home/node/.local/bin:/opt/bun/bin:$PATH"


# ── Startup cleanup (stale Chromium Singleton locks) ─────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

LABEL org.opencontainers.image.source=https://github.com/miguelarios/openclaw-image
LABEL org.opencontainers.image.description="OpenClaw gateway with CLI tooling, Playwright/Chromium, and media utilities"

USER node
