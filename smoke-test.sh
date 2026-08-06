#!/usr/bin/env bash
# Assert the built image is actually usable before it is pushed.
#
# This exists because a green `docker build` does not mean a working image:
# an upstream can change a tarball's internal layout and `tar xz <name>` will
# extract nothing while the build still succeeds. That failure used to surface
# on the server at deploy time; now it surfaces here.
#
# Two levels of check:
#   BINS      — must be on PATH. Catches a tool that never got installed.
#   VERSIONED — must also *run* and report a version. Catches a tool that
#               installed but is broken: a native binding that resolved to the
#               wrong platform, a Python entry point whose imports fail, a
#               truncated download that is still executable.
#
# Presence alone is too weak for anything with a native or dynamic component,
# which is most of what this image adds.
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

# Everything this image deliberately installs. Excluded on purpose:
#   clawhub   — no version flag at all (`error: unknown option '--version'`)
#   nano-pdf  — prints usage instead of a version
#   uvx, and the base OS utilities — provided by Debian, not by us
VERSIONED="
gh yq yt-dlp jq
gog gws camsnap goplaces sonos spogo xurl
uv bun
claude gemini td mcporter
node chromium
ffmpeg exiftool pandoc tesseract
rg fd sqlite3
python3 pip
markitdown faker anydoc transcribe
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

# Flags are discovered rather than hardcoded: these tools come from Go, Rust,
# Node and Python ecosystems and do not agree on one. Anything that only emits
# usage text or rejects the flag is treated as "no version reported" and moves
# on to the next candidate; exhausting all four is a failure.
echo "==> version check (must actually execute)"
docker run --rm --entrypoint /bin/sh "$IMAGE" -c '
  fail=0
  for b in '"$(echo "$VERSIONED" | tr "\n" " ")"'; do
    got=""
    for flag in --version -version -V version -ver; do
      if out=$(timeout 20 "$b" "$flag" 2>&1); then
        case "$out" in
          Usage:*|usage:*|Syntax:*|*"unknown option"*|*"unrecognized"*|"") continue ;;
        esac
        # Drop log noise before picking the version line. markitdown emits an
        # onnxruntime warning on startup, and taking head -1 blindly accepted
        # that warning as the version — a pass that proved nothing.
        line=$(printf "%s\n" "$out" \
                 | grep -vE "^[0-9]{4}-[0-9]{2}-[0-9]{2}|\[W:|\[E:|WARNING|Warning:" \
                 | grep -vE "^[[:space:]]*$" \
                 | head -1)
        # A version string contains a digit. Anything else is banner text.
        case "$line" in
          *[0-9]*) got=$(printf "%s" "$line" | cut -c1-52); break ;;
        esac
      fi
    done
    if [ -n "$got" ]; then
      printf "  ok       %-11s %s\n" "$b" "$got"
    else
      printf "  BROKEN   %-11s (installed but will not report a version)\n" "$b"
      fail=1
    fi
  done
  exit $fail
'

echo "==> openclaw entrypoint responds"
docker run --rm --entrypoint node "$IMAGE" /app/openclaw.mjs --version

echo "==> chromium launches headless"
docker run --rm --entrypoint chromium "$IMAGE" \
  --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null

echo "==> smoke test passed"
