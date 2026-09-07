#!/bin/sh
# prune-home.sh — reclaim regenerable space in the bind-mounted $HOME at
# container start. Runs from entrypoint.sh as the node user.
#
# The home directory is a persistent volume, so caches and staged deletions
# outlive the image. This is an explicit allowlist: only the paths named
# below are touched, nothing is globbed from $HOME itself, and auth or state
# directories (.claude*, .codex, .config, .openclaw, .npm-global, backup
# tarballs) are deliberately absent. Every removal is appended to
# $HOME/.trash/prune.log.
#
# Knobs (environment):
#   PRUNE_HOME=0            skip entirely
#   PRUNE_TRASH_DAYS=7      ~/.trash entries older than this are deleted
#   PRUNE_TMP_DAYS=14       ~/tmp entries older than this are deleted
#   PRUNE_NPX_DAYS=30       ~/.npm/_npx entries older than this are deleted
set -u

[ "${PRUNE_HOME:-1}" = "0" ] && exit 0
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || exit 0

TRASH="$HOME/.trash"
LOG="$TRASH/prune.log"
mkdir -p "$TRASH"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }

# Remove top-level entries of $1 whose mtime is older than $2 days.
prune_dir() {
  dir="$1"; days="$2"
  [ -d "$dir" ] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -mtime +"$days" -print 2>/dev/null |
  while IFS= read -r entry; do
    [ "$entry" = "$LOG" ] && continue
    size=$(du -sh "$entry" 2>/dev/null | cut -f1)
    if rm -rf -- "$entry"; then
      log "rm  $entry ($size, >${days}d)"
    else
      log "ERR could not remove $entry"
    fi
  done
}

log "--- prune start ---"

prune_dir "$TRASH"          "${PRUNE_TRASH_DAYS:-7}"
prune_dir "$HOME/tmp"       "${PRUNE_TMP_DAYS:-14}"
prune_dir "$HOME/.npm/_npx" "${PRUNE_NPX_DAYS:-30}"

# Package-manager caches. Each tool owns its own store and knows what is
# safe to drop; none of these hold credentials.
if command -v npm >/dev/null 2>&1; then
  npm cache clean --force >/dev/null 2>&1 && log "npm cache clean" || log "ERR npm cache clean"
fi
if command -v uv >/dev/null 2>&1; then
  uv cache prune --quiet >/dev/null 2>&1 && log "uv cache prune" || log "ERR uv cache prune"
fi
if command -v pnpm >/dev/null 2>&1; then
  pnpm store prune >/dev/null 2>&1 && log "pnpm store prune" || log "ERR pnpm store prune"
fi

log "--- prune done ---"
exit 0
