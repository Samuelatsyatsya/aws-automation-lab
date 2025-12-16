#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION

LOG_FILE="create_security_group.log"
SG_NAME="automationlab-sg"
SG_DESCRIPTION="Security group for AutomationLab EC2 instances"
TAG_PROJECT="AutomationLab"
REGION=$(aws configure get region)


# LOGGING FUNCTION

log() {
  # Logs messages with timestamp to terminal and log file (stderr-safe)
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}


# PREREQUISITES CHECK
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
}

# SECURITY GROUP FUNCTIONS

create_security_group() {
  log "Creating security group: $SG_NAME"

  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "$SG_DESCRIPTION" \
    --region "$REGION" \
    --query GroupId \
    --output text)

  log "Security group created with ID: $SG_ID"
}

add_ingress_rules() {
  log "Adding inbound rules to security group"

  # Allow SSH (port 22)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" \
    --query 'SecurityGroupRules[0].SecurityGroupRuleId' \

  # Allow HTTP (port 80)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" \
    --query 'SecurityGroupRules[0].SecurityGroupRuleId' \

  log "Inbound rules added (SSH:22, HTTP:80)"
}

tag_security_group() {
  log "Tagging security group"

  aws ec2 create-tags \
    --resources "$SG_ID" \
    --tags Key=Project,Value="$TAG_PROJECT" \
    --region "$REGION"
}

display_security_group_info() {
  log "Security Group Details:"
  log "Security Group ID   : $SG_ID"
  log "Security Group Name : $SG_NAME"
  log "Region              : $REGION"
}

# MAIN EXECUTION

log "Security Group Automation Script Started"

check_prerequisites
create_security_group
add_ingress_rules
tag_security_group
display_security_group_info

log "Security Group Automation Script Completed"
