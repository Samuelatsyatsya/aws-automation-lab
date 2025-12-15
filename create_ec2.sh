#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION

LOG_FILE="create_ec2.log"
KEY_NAME="automationlab-key-$(date +%s)"
INSTANCE_TYPE="t3.micro"         # Free-tier
TAG_PROJECT="AutomationLab"

# LOGGING FUNCTION

log() {
  # Logs messages with timestamp to both terminal and log file
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE"
}


check_prerequisites() {
  # Ensure AWS CLI is installed
  if ! command -v aws >/dev/null 2>&1; then
    log "ERROR: AWS CLI not installed."
    exit 1
  fi

  # Ensure AWS credentials are valid
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "ERROR: AWS credentials not configured or invalid."
    exit 1
  fi

  log "AWS CLI and credentials verified."
}

get_latest_ami() {
  # Fetch the latest Amazon Linux 2 AMI (region-independent)
  aws ssm get-parameter \
    --name /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query Parameter.Value \
    --output text
}

create_key_pair() {
  # Create an EC2 key pair and save private key locally
  log "Creating EC2 key pair: $KEY_NAME"

  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query KeyMaterial \
    --output text > "${KEY_NAME}.pem"

  chmod 400 "${KEY_NAME}.pem"
  log "Key pair saved as ${KEY_NAME}.pem"
}

launch_instance() {
  # Launch EC2 instance using the AMI and key pair
  log "Launching EC2 instance..."

  aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --count 1 \
    --region "eu-central-1" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Project,Value=$TAG_PROJECT}]" \
    --query 'Instances[0].InstanceId' \
    --output text
}

print_instance_info() {
  # Wait for instance to be running and fetch public IP
  log "Waiting for EC2 instance to enter running state..."

  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

  log "EC2 Instance created successfully."
  log "Instance ID : $INSTANCE_ID"
  log "Public IP  : $PUBLIC_IP"
}

# ---------------- MAIN EXECUTION ----------------

log "EC2 Automation Script Started"

check_prerequisites
AMI_ID=$(get_latest_ami)

create_key_pair
INSTANCE_ID=$(launch_instance)

print_instance_info

log "EC2 Automation Script Completed"
