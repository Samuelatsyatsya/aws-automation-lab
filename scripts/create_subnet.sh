#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
LOG_FILE="./logs/create_sg.log"
STATE_FILE="./state/state.json"
mkdir -p ./logs ./state

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*" >> "$LOG_FILE"
}

check_prerequisites() {
    command -v aws >/dev/null 2>&1 || { echo "aws CLI not found"; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq not found"; exit 1; }
}

save_state() {
    local key="$1"
    local value="$2"
    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ---------------- START ----------------
log "Starting Security Group setup"
check_prerequisites

# ---------------- VPC ID ----------------
VPC_ID=$(jq -r '.vpc_id // empty' "$STATE_FILE")
if [[ -z "$VPC_ID" ]]; then
    log "[ERROR] VPC ID not found in state.json. Cannot create Security Group."
    exit 1
fi

# ---------------- SECURITY GROUP ----------------
SG_NAME="${SG_NAME:-automationlab-sg}"
PROJECT_TAG="${PROJECT_TAG:-automationlab}"

log "Checking if Security Group '$SG_NAME' exists in VPC $VPC_ID"

SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region "$REGION" 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    log "Creating Security Group: $SG_NAME"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for $PROJECT_TAG EC2 instances" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text \
        --region "$REGION")

    # Example: allow SSH
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$REGION"

    log "Created Security Group: $SG_ID"
else
    log "Security Group already exists: $SG_ID"
fi

# ---------------- SAVE STATE ----------------
save_state "security_group_id" "$SG_ID"

# ---------------- INFO ----------------
log "Security Group setup completed"
echo "Security Group ID: $SG_ID"
