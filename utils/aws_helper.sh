#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# AWS Helpers: logging, prerequisites, unified ensures
# ---------------------------------------------

# ---------------- CONFIGURATION ----------------
LOG_FILE="${LOG_FILE:-./logs/aws_helper.log}"
STATE_FILE="${STATE_FILE:-./state.json}"
REGION="${REGION:-$(aws configure get region)}"
PROJECT_TAG="${PROJECT_TAG:-AutomationLab}"

mkdir -p "$(dirname "$LOG_FILE")"

# Ensure state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
fi

# ---------------- LOGGING ----------------
log() {
    local LEVEL="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] : $1" | tee -a "$LOG_FILE" >&2
}

error_exit() {
    log "$1" "ERROR"
    exit 1
}

# ---------------- PREREQUISITES ----------------
check_prerequisites() {
    command -v aws >/dev/null 2>&1 || { log "Installing AWS CLI..."; sudo apt-get update && sudo apt-get install -y awscli; }
    command -v jq >/dev/null 2>&1 || { log "Installing jq..."; sudo apt-get update && sudo apt-get install -y jq; }
    aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
}

# ---------------- STATE FILE HANDLING ----------------
load_state() {
    STATE=$(cat "$STATE_FILE")
}

save_state() {
    echo "$STATE" | jq '.' > "$STATE_FILE"
}

mark_done() {
    local key="$1"
    local value="$2"
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
}

is_done() {
    local key="$1"
    local exists
    exists=$(jq -r --arg k "$key" 'has($k) and .[$k] != null' "$STATE_FILE")
    [[ "$exists" == "true" ]]
}

get_resource() {
    local key="$1"
    jq -r --arg k "$key" '.[$k] // empty' "$STATE_FILE"
}


