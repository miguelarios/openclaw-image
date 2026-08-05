#!/bin/sh
rm -f /home/node/.openclaw/browser/*/user-data/Singleton* 2>/dev/null
exec "$@"
