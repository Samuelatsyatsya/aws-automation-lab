#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_all.log"

STATE_DIR="./state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/state.json"
[[ ! -f "$STATE_FILE" ]] && echo "{}" > "$STATE_FILE"

# LOAD ENV & HELPERS
if [[ -f "./config/aws_env.sh" ]]; then
    source ./config/aws_env.sh
else
    echo "ERROR: aws_env.sh not found"
    exit 1
fi

if [[ -f "./utils/aws_helper.sh" ]]; then
    source ./utils/aws_helper.sh
else
    echo "ERROR: aws_helper.sh not found"
    exit 1
fi

# STATE FUNCTIONS
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

# SCRIPT RUNNER
SCRIPT_DIR="./scripts"
SCRIPTS=(
    "create_subnet.sh"
    "create_security_group.sh"
    "create_s3_bucket.sh"
    "create_ec2.sh"
)

run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"

    if [[ ! -f "$script_path" ]]; then
        echo "ERROR: $script_path not found"
        exit 1
    fi

    if is_done "$script_name"; then
        echo "[INFO] Skipping $script_name (already completed)"
        return
    fi

    chmod +x "$script_path"
    echo "[INFO] Executing $script_path..."

    if ! bash "$script_path"; then
        echo "ERROR: $script_path failed. Aborting orchestration."
        exit 1
    fi

    echo "[INFO] $script_path completed successfully."
    mark_done "$script_name"
}

# MAIN
echo "[INFO] Automation Orchestrator Script Started"

for SCRIPT in "${SCRIPTS[@]}"; do
    run_script "$SCRIPT"
done

echo "[INFO] Automation Orchestrator Script Completed Successfully"
