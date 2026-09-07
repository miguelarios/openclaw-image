#!/bin/sh
rm -f /home/node/.openclaw/browser/*/user-data/Singleton* 2>/dev/null
# Reclaim regenerable space in the mounted home. Backgrounded so a large
# cache prune never delays gateway start; it logs to ~/.trash/prune.log.
( /usr/local/bin/prune-home.sh & ) 2>/dev/null
exec "$@"
