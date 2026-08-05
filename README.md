# openclaw-image

The OpenClaw gateway image for the homelab, built in CI and published to
`ghcr.io/miguelarios/openclaw`.

Consumed by [`miguelarios/homelab`](https://github.com/miguelarios/homelab),
which pins by digest.

## Why this exists

`Dockerfile.custom` used to live only on the Unraid host at `/mnt/user/appdata/openclaw/`,
untracked, and the image was built on the server. That meant the recipe for the
most complex container in the homelab existed on exactly one disk — and every
build tarred ~15 GB of runtime data (`config/` 7.6 G, `home/` 7.4 G, `ollama/`
262 M) into the build context, because there was no `.dockerignore`.

Here the build context is only what git tracks. The server just pulls.

## Tagging

The tag tracks the **upstream base image version** — whatever `ARG BASE_VERSION`
says. Rebuilds of the same base overwrite that tag.

That is safe because homelab pins the **digest**:

```yaml
image: ghcr.io/miguelarios/openclaw:2026.7.1@sha256:9f3c…
```

The tag stays readable, the digest makes the deploy reproducible, rollback is a
`git revert`, and Renovate on homelab opens the bump PR by itself when the digest
moves — it parses compose files and treats the image as an ordinary Docker
dependency, so no cross-repo token is involved.

Without the digest, compose compares the image *reference string* and would not
recreate the container at all when a new image exists behind an unchanged tag.

The build prints the exact line into the job summary.

## What is pinned, and what deliberately is not

**Pinned** — `ARG` + `# renovate:` comment, one grouped PR per week:
base image, `yq`, `yt-dlp`, `gog`, `gws`, `camsnap`, `goplaces`, `sonos`,
`spogo`, `xurl`. Combined cadence ~30–60 releases/yr.

**Floating** — unpinned, refreshed whenever that layer rebuilds: every npm CLI
(`claude-code`, `gemini-cli`, `todoist-cli`, `mcporter`, `clawhub`) and the
`uv pip` tools. Measured cadence made pinning impractical:

| package | releases / 12 mo |
|---|---|
| `@openai/codex` | 3666 |
| `@google/gemini-cli` | 629 |
| `@anthropic-ai/claude-code` | 316 |
| `@doist/todoist-cli` | 139 |

The base image ships ~104 stable releases a year, and a base bump rebuilds
everything below it, so these refresh roughly weekly for free.

### gws is on borrowed time

`gws` is being replaced by `gog`, but ~22 skills still shell out to `gws`
(`gws-gmail`, `gws-calendar`, `gws-drive`, `gws-sheets`, `gws-docs`,
`gws-slides`, `gws-people`, and the `recipe-*` family). Both ship until those
are migrated. Drop the `GWS_VERSION` ARG and its fetch line once they are.

## Layer order matters

Chromium is ~1.5 GB and sits above every pinned tool on purpose — anything
placed above it gets reinstalled whenever anything below it changes. The bands
are documented at the top of the Dockerfile; keep additions in the right one.

Caveat: a base-image bump invalidates everything regardless of ordering, since
`FROM` is layer zero. The ordering only buys cheap *tool* bumps.

## Building

Every push to `main` builds. Ad-hoc:

```bash
gh workflow run build.yml                              # cached
gh workflow run build.yml -f refresh_floating=true     # pull new claude-code/gemini/codex
gh workflow run build.yml -f no_cache=true             # from scratch
gh run watch
```

`refresh_floating` exists because Docker caches by instruction text: an unpinned
`npm install -g` layer will **not** pick up new versions on a cached rebuild.
The flag changes a build arg to force it.

## Smoke test

`smoke-test.sh` runs against the built image *before* it is pushed. It asserts
every expected binary resolves, that openclaw starts, and that Chromium launches
headless.

This replaces the feedback lost by not building on the server. A green
`docker build` does not mean a working image — and that is not hypothetical:
spogo renamed its release asset at v0.10.2
(`spogo_0.10.1_linux_amd64.tar.gz` → `spogo_0.10.3_spogo_linux_amd64_v1.tar.gz`),
which broke the string-templated fetch the old Dockerfile used. `fetch()` now
takes a full URL and locates the binary with `find`, so layout changes fail
loudly instead of yielding an image that looks fine and is missing a tool.
