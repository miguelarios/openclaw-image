#!/usr/bin/env bash
# Shared release-asset manifest for the Docker build and PR validation.
# Version variables come from Dockerfile ARG declarations.

release_assets() {
  cat <<EOF
raw|yq|https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64
raw|yt-dlp|https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp
tar|gog|https://github.com/openclaw/gogcli/releases/download/${GOGCLI_VERSION}/gogcli_${GOGCLI_VERSION#v}_linux_amd64.tar.gz
tar|camsnap|https://github.com/steipete/camsnap/releases/download/${CAMSNAP_VERSION}/camsnap_${CAMSNAP_VERSION#v}_linux_amd64.tar.gz
tar|goplaces|https://github.com/openclaw/goplaces/releases/download/${GOPLACES_VERSION}/goplaces_${GOPLACES_VERSION#v}_linux_amd64.tar.gz
tar|sonos|https://github.com/steipete/sonoscli/releases/download/${SONOSCLI_VERSION}/sonoscli_${SONOSCLI_VERSION#v}_linux_amd64.tar.gz
tar|spogo|https://github.com/openclaw/spogo/releases/download/${SPOGO_VERSION}/spogo_${SPOGO_VERSION#v}_linux_amd64.tar.gz
tar|xurl|https://github.com/xdevplatform/xurl/releases/download/${XURL_VERSION}/xurl_Linux_x86_64.tar.gz
zip|duckdb|https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip
EOF
}
