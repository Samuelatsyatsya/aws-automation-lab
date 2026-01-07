#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
LOG_FILE="create_ec2.log"
KEY_NAME="automationlab-key-$(date +%s)"
INSTANCE_TYPE="t3.micro"
TAG_PROJECT="AutomationLab"
REGION="eu-central-1"

# ---------------- LOG FUNCTION ----------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}

# ---------------- CHECK PREREQUISITES ----------------
check_prerequisites() {
  if ! command -v aws >/dev/null 2>&1; then
    log "ERROR: AWS CLI not installed."
    exit 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "ERROR: AWS credentials not configured or invalid."
    exit 1
  fi

  log "AWS CLI and credentials verified."
}

# ---------------- GET LATEST AMI ----------------
get_latest_ami() {
  aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query Parameter.Value \
    --output text \
    --region "$REGION"
}

# ---------------- CREATE KEY PAIR ----------------
create_key_pair() {
  log "Creating EC2 key pair: $KEY_NAME"
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query KeyMaterial \
    --output text \
    --region "$REGION" > "${KEY_NAME}.pem"

  chmod 400 "${KEY_NAME}.pem"
  log "Key pair saved as ${KEY_NAME}.pem"
}

# ---------------- LAUNCH INSTANCE ----------------
launch_instance() {
  log "Launching EC2 instance..."

  # Get subnet ID (created via create_subnet.sh)
  SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Project,Values=$TAG_PROJECT" \
    --query 'Subnets[0].SubnetId' \
    --output text \
    --region "$REGION")

  # Launch instance and return Instance ID
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --count 1 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=$TAG_PROJECT}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$REGION")

  echo "$INSTANCE_ID"
}

# ---------------- PRINT INSTANCE INFO ----------------
print_instance_info() {
  log "Waiting for EC2 instance to enter running state..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region "$REGION")

  log "EC2 Instance created successfully."
  log "Instance ID : $INSTANCE_ID"
  log "Public IP   : $PUBLIC_IP"
}

# ---------------- MAIN ----------------
log "EC2 Automation Script Started"

check_prerequisites
AMI_ID=$(get_latest_ami)
create_key_pair
INSTANCE_ID=$(launch_instance)
print_instance_info

log "EC2 Automation Script Completed"
