#!/usr/bin/env bash
set -euo pipefail

# Configuration
source "./bootstrap.env"

#Logging
source "./bootstrap_helper.sh"

# Run all scripts in order
for SCRIPT in "$BOOTSTRAP_DIR"/*.sh; do
    [[ -f "$SCRIPT" ]] || continue
    log "[INFO] Running $SCRIPT..."
    chmod +x "$SCRIPT"
    bash "$SCRIPT"
done

log "Bucket for state and Dynamo Table for locks created successfully"


