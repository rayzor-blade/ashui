#!/bin/sh
# Runs the counter and prints its checks; the frames land in $ASHUI_SNAPSHOT_DIR, or .ashui/snapshots.
#   apps/counter/run.sh           on Ash
#   apps/counter/run.sh rayzor    on Rayzor; needs BLINC_ABI, BLINC_CSS and RAYZOR_GPU, as tools/snapshot/run-rayzor.sh lists
set -e
here="$(cd "$(dirname "$0")" && pwd)"
case "${1:-ash}" in
ash) exec "$here/../../tools/snapshot/run.sh" "$here/Counter.hx" ;;
rayzor) exec "$here/../../tools/snapshot/run-rayzor.sh" "$here/Counter.hx" ;;
*) echo "usage: run.sh [ash|rayzor]" >&2; exit 2 ;;
esac
