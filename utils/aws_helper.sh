#!/usr/bin/env bash
set -euo pipefail

# Configuration
LOG_FILE="${LOG_FILE:-./logs/aws_helper.log}"

source ./config/aws_env.sh

mkdir -p "$(dirname "$LOG_FILE")"

# Ensure state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
fi

error_exit() {
    log "$1" "ERROR"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    command -v aws >/dev/null 2>&1 || { log "Installing AWS CLI..."; sudo apt-get update && sudo apt-get install -y awscli; }
    command -v jq >/dev/null 2>&1 || { log "Installing jq..."; sudo apt-get update && sudo apt-get install -y jq; }
    aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
}

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*" | tee -a "$LOG_FILE"
}

# State helpers
get_state() {
    jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}

set_state() {
    local tmp
    tmp=$(mktemp)
    jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Delete state key
delete_state_key() {
    jq "del(.$1)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
}

# Delete resource if tracked in state
delete_if_tracked() {
    local key="$1"
    local label="$2"
    local delete_cmd_template="$3"

    local resource_id
    resource_id=$(get_state "$key")

    if [[ -z "$resource_id" ]]; then
        log "No $label found in state"
        return
    fi

    log "Deleting $label: $resource_id"

    local delete_cmd="${delete_cmd_template//__ID__/$resource_id}"

    eval "$delete_cmd"
    delete_state_key "$key"
}

#bash plan
bash_plan() {
    local resource_type="$1"
    local description="$2"
    local cmd="${3:-}"

    if [[ "${BASH_PLAN:-false}" == "true" ]]; then
        log "[BASH PLAN] Create $resource_type: $description"
    else
        # Execute the command if provided
        if [[ -n "$cmd" ]]; then
            eval "$cmd"
        fi
    fi
}