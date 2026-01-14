#!/usr/bin/env bash
set -euo pipefail


#SOURCE HELPERS
source ./utils/aws_helper.sh

# Directories and files
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/run_all.log"


# Load environment and helper scripts
: "${AWS_ENV_FILE:=./config/aws_env.sh}"
: "${AWS_HELPER_FILE:=./utils/aws_helper.sh}"

[[ -f "$AWS_ENV_FILE" ]] && source "$AWS_ENV_FILE" || { echo "ERROR: $AWS_ENV_FILE not found"; exit 1; }
[[ -f "$AWS_HELPER_FILE" ]] && source "$AWS_HELPER_FILE" || { echo "ERROR: $AWS_HELPER_FILE not found"; exit 1; }

: "${STATE_HELPER:=./state/state_io.sh}"
: "${LOCK_HELPER:=./state/lock.sh}"

[[ -f "$STATE_HELPER" ]] && source "$STATE_HELPER" || { echo "ERROR: $STATE_HELPER not found"; exit 1; }
[[ -f "$LOCK_HELPER" ]] && source "$LOCK_HELPER" || { echo "ERROR: $LOCK_HELPER not found"; exit 1; }

# State tracking functions
is_done() {
    local key="$1"
    jq -e --arg k "$key" '.[$k] == true' "$STATE_FILE" >/dev/null 2>&1
}

mark_done() {
    local key="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg k "$key" '.[$k] = true' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Scripts to run
SCRIPT_DIR="./scripts"
SCRIPTS=(
    "create_subnet.sh"
    "create_security_group.sh"
    "create_s3_bucket.sh"
    "create_ec2.sh"
)

# Function to run each script
run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"

    [[ -f "$script_path" ]] || { log "ERROR: $script_path not found"; exit 1; }

    if is_done "$script_name"; then
        log "[INFO] Skipping $script_name (already completed)"
        return
    fi

    chmod +x "$script_path"
    log "[INFO] Executing $script_path..."

    if ! bash "$script_path"; then
        log "ERROR: $script_path failed. Aborting."
        exit 1
    fi

    log "[INFO] $script_path completed successfully."
    mark_done "$script_name"
}

# Main orchestration
log "[INFO] Automation Orchestrator Started"

# Acquire lock and download state
trap release_lock EXIT
acquire_lock
download_state

# Run scripts in order
for SCRIPT in "${SCRIPTS[@]}"; do
    run_script "$SCRIPT"
done

# Upload updated state
upload_state

echo "Automation Orchestrator Completed Successfully"
