#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIGURATION ----------------
LOG_FILE="run_all.log"

# Include the subnet creation script first
SCRIPTS=("create_subnet.sh" "create_security_group.sh" "create_s3_bucket.sh" "create_ec2.sh")

# ---------------- LOGGING FUNCTION ----------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}

# ---------------- MAIN EXECUTION ----------------
log "Automation Orchestrator Script Started"

for SCRIPT in "${SCRIPTS[@]}"; do
  if [[ -f "$SCRIPT" ]]; then
    # Make the script executable if it isn’t already
    if [[ ! -x "$SCRIPT" ]]; then
      chmod +x "$SCRIPT"
      log "Set executable permission for $SCRIPT"
    fi

    log "Executing $SCRIPT..."
    
    # Run the script and capture errors
    if ! ./"$SCRIPT"; then
      log "ERROR: $SCRIPT failed. Aborting orchestration."
      exit 1
    fi

    log "$SCRIPT completed successfully."
  else
    log "ERROR: $SCRIPT not found"
    exit 1
  fi
done

log "Automation Orchestrator Script Completed Successfully"
