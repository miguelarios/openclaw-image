#!/usr/bin/env bash
# Assert the built image is actually usable before it is pushed.
#
# This exists because a green `docker build` does not mean a working image:
# an upstream can change a tarball's internal layout and `tar xz <name>` will
# extract nothing while the build still succeeds. That failure used to surface
# on the server at deploy time; now it surfaces here.
#
# Every binary below was verified present in the running container before this
# list was written. If one goes MISSING, the build genuinely regressed.
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"

BINS="
node openclaw
gh yq yt-dlp jq
gog gws camsnap goplaces sonos spogo xurl
uv uvx bun
claude gemini td mcporter clawhub
chromium
ffmpeg convert exiftool pandoc tesseract pdftotext
rg fd sqlite3 file dos2unix tree zip unzip lsof ping
python3 python pip nano-pdf transcribe
markitdown faker anydoc
"

echo "==> binary presence check: $IMAGE"
docker run --rm --entrypoint /bin/sh "$IMAGE" -c '
  fail=0
  for b in '"$(echo "$BINS" | tr "\n" " ")"'; do
    if command -v "$b" >/dev/null 2>&1; then
      printf "  ok       %s\n" "$b"
    else
      printf "  MISSING  %s\n" "$b"
      fail=1
    fi
  done
  exit $fail
'

echo "==> pinned tool versions"
docker run --rm --entrypoint /bin/sh "$IMAGE" -c '
  yq --version
  gog --version 2>/dev/null || true
  yt-dlp --version
'

echo "==> openclaw entrypoint responds"
docker run --rm --entrypoint node "$IMAGE" /app/openclaw.mjs --version

echo "==> chromium launches headless"
docker run --rm --entrypoint chromium "$IMAGE" \
  --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null

echo "==> smoke test passed"
