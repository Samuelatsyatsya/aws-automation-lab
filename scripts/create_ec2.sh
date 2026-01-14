#!/usr/bin/env bash
set -euo pipefail

# Files and directories
LOG_FILE="./logs/create_ec2.log"
STATE_FILE="./state/state.json"
KEY_DIR="./keys"

mkdir -p ./logs "$KEY_DIR"

# Load helper scripts
source ./utils/aws_helper.sh
check_prerequisites

log "Starting EC2 instance setup"

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query 'Parameter.Value' \
    --output text \
    --region "$REGION")

# Read subnet ID from state
SUBNET_ID=$(jq -r '.subnet_id // empty' "$STATE_FILE")

if [[ -z "$SUBNET_ID" ]]; then
    log "ERROR: subnet_id not found in state file"
    exit 1
fi

# Set or create key pair
KEY_NAME="${KEY_NAME:-automationlab-key}"

if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
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

# Launch EC2 instance
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

# Save instance ID to state
set_state "ec2_instance_id" "$INSTANCE_ID"

# Output info
log "EC2 instance setup completed"
echo "Instance ID: $INSTANCE_ID"
