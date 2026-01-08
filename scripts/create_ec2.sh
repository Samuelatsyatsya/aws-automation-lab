#!/usr/bin/env bash
set -euo pipefail

# ---------------- SETUP ----------------
LOG_FILE="./logs/create_ec2.log"
STATE_FILE="./state/state.json"
KEY_DIR="./keys"

mkdir -p ./logs "$KEY_DIR"

check_prerequisites

log "Starting EC2 instance setup"

# ---------------- AMI ----------------
AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameter.Value' \
    --output text \
    --region "$REGION")

# ---------------- SUBNET ----------------
SUBNET_ID=$(jq -r '.subnet_id // empty' "$STATE_FILE")

if [[ -z "$SUBNET_ID" ]]; then
    log "ERROR: subnet_id not found in state file"
    exit 1
fi

# ---------------- KEY PAIR ----------------
KEY_NAME="${KEY_NAME:-automationlab-key}"

if aws ec2 describe-key-pairs \
    --key-names "$KEY_NAME" \
    --region "$REGION" >/dev/null 2>&1; then
    log "EC2 KeyPair already exists: $KEY_NAME"
else
    log "Creating EC2 KeyPair: $KEY_NAME"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text \
        --region "$REGION" > "$KEY_DIR/${KEY_NAME}.pem"

    chmod 400 "$KEY_DIR/${KEY_NAME}.pem"
fi

# ---------------- EC2 INSTANCE ----------------
log "Launching EC2 instance"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "t3.micro" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$PROJECT_TAG}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$REGION")

# ---------------- SAVE STATE ----------------
tmp=$(mktemp)
jq --arg id "$INSTANCE_ID" '.ec2_instance_id=$id' "$STATE_FILE" > "$tmp"
mv "$tmp" "$STATE_FILE"

# ---------------- INFO ----------------
log "EC2 instance setup completed"
echo "Instance ID: $INSTANCE_ID"
