#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./logs/create_sg.log"
mkdir -p ./logs
check_prerequisites

STATE_FILE="./state/state.json"

# ---------------- VALIDATE STATE ----------------
VPC_ID=$(jq -r '.vpc_id // empty' "$STATE_FILE")
if [[ -z "$VPC_ID" ]]; then
    log "[ERROR] VPC ID not found in state.json"
    exit 1
fi

# ---------------- SECURITY GROUP ----------------
log "Ensuring Security Group exists"

SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region "$REGION" 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for $PROJECT_TAG EC2 instances" \
        --vpc-id "$VPC_ID" \
        --query GroupId \
        --output text \
        --region "$REGION")

    # Allow SSH (example – adjust as needed)
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

# ---------------- SAVE TO STATE ----------------
tmp=$(mktemp)
jq --arg sg "$SG_ID" '.security_group_id = $sg' "$STATE_FILE" > "$tmp"
mv "$tmp" "$STATE_FILE"

# ---------------- INFO ----------------
log "Security group setup completed"
echo "Security Group ID: $SG_ID"
