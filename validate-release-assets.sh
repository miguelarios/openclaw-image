#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Load the Renovate-managed versions from the Dockerfile, then render the same
# asset manifest used by the image build. This catches upstream asset renames
# without downloading multi-megabyte archives or rebuilding the 4 GB image.
while IFS='=' read -r name value; do
  export "$name=$value"
done < <(grep -E '^ARG (YQ|YTDLP|GOGCLI|GWS|CAMSNAP|GOPLACES|SONOSCLI|SPOGO|XURL)_VERSION=' Dockerfile | sed 's/^ARG //')

source ./release-assets.sh

failed=0
while IFS='|' read -r _kind bin url; do
  printf 'checking %-9s %s\n' "$bin" "$url"
  if ! curl --fail --silent --show-error --location --head \
      --retry 2 --retry-all-errors "$url" >/dev/null; then
    failed=1
  fi
done < <(release_assets)

if (( failed )); then
  echo 'one or more pinned release assets are unavailable' >&2
  exit 1
fi

echo 'all pinned release assets are available'
