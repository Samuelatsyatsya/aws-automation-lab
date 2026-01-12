#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
: "${REGION:?REGION must be set (source env.sh)}"
: "${VPC_NAME:?VPC_NAME must be set}"
: "${SG_NAME:?SG_NAME must be set}"
: "${PROJECT_TAG:?PROJECT_TAG must be set}"

LOG_FILE="./logs/create_sg.log"
STATE_FILE="./state/state.json"
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"


#SOURCE HELPERS
source ./utils/aws_helper.sh


# START
log "Starting Security Group setup"

VPC_ID=$(get_state "vpc_id")
if [[ -z "$VPC_ID" ]]; then
    log "[ERROR] VPC ID not found. Please create VPC first."
    exit 1
fi

# CREATE IF NOT IN STATE 
SG_ID=$(get_state "security_group_id")

if [[ -n "$SG_ID" ]]; then
    log "Security Group already exists in state: $SG_ID"
else
    log "Creating Security Group: $SG_NAME"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for $PROJECT_TAG EC2 instances" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text \
        --region "$REGION")

    log "Adding ingress rules"
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$REGION"

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$REGION"

    set_state "security_group_id" "$SG_ID"
    log "Security Group $SG_ID created"
fi

# DONE
log "Security Group setup completed"
echo "Security Group ID: $SG_ID"
