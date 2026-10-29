#!/bin/bash
# Apply the current time-based policy using official Apple Shortcuts CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=scripts/profile.sh
source "$ROOT/profile.sh"

clock="$(/bin/date +%H%M)"
limit="$(set_profile "$clock")" || { echo "Invalid local clock: $clock" >&2; exit 2; }
case "$limit" in
    80) name="白天充电上限80" ;;
    100) name="晚间充电上限100" ;;
    *) echo "Unexpected limit: $limit" >&2; exit 2 ;;
esac

# Note: a successful CLI exit does NOT independently verify the battery's
# actual charge-limit setting. The user must check System Settings > Battery.
echo "$(/bin/date '+%Y-%m-%d %H:%M:%S %z') Applying ${limit}% via ${name}"
if /usr/bin/shortcuts run "$name"; then
    echo "Shortcut command returned success (battery state not independently verified)."
else
    rc=$?
    echo "ERROR: shortcuts run $name exited with $rc" >&2
    exit "$rc"
fi
