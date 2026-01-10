
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup_resources.log"

STATE_FILE="./state/state.json"
: "${STATE_FILE:=${STATE_FILE:-./state/state.json}}"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
fi

# Load helpers
if [[ -f "./utils/aws_helper.sh" ]]; then
    source ./utils/aws_helper.sh
else
    echo "ERROR: aws_helper.sh not found"
    exit 1
fi

log "Resource Cleanup Script Started"
check_prerequisites
cleanup_all_resources
log "Resource Cleanup Script Completed Successfully"


