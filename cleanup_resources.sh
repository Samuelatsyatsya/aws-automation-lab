#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION

LOG_FILE="cleanup_resources.log"
TAG_PROJECT="AutomationLab"
REGION=$(aws configure get region)

# LOGGING FUNCTION

log() {
  # Logs messages with timestamp to terminal and log file (stderr-safe)
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}


# PREREQUISITES CHECK

check_prerequisites() {
  if ! command -v aws >/dev/null 2>&1; then
    log "ERROR: AWS CLI not installed."
    exit 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "ERROR: AWS credentials not configured or invalid."
    exit 1
  fi
}

# CLEANUP FUNCTIONS

cleanup_ec2_instances() {
  log "Searching for EC2 instances with tag Project=$TAG_PROJECT..."

  INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Project,Values=$TAG_PROJECT" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

  if [[ -n "$INSTANCE_IDS" ]]; then
    log "Terminating EC2 instances: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
    log "EC2 instances terminated."
  else
    log "No EC2 instances found to terminate."
  fi
}

cleanup_key_pairs() {
  log "Searching for EC2 key pairs with Project tag in name..."

  # Assumes key names start with "automationlab-key"
  for KEY in $(aws ec2 describe-key-pairs --region "$REGION" >/dev/null --query "KeyPairs[].KeyName" --output text); do
    if [[ "$KEY" == automationlab-key* ]]; then
      log "Deleting key pair: $KEY"
      aws ec2 delete-key-pair --key-name "$KEY" --region "$REGION"
      rm -f "${KEY}.pem" 2>/dev/null || true
    fi
  done
}

# cleanup_s3_buckets() {
#   log "Searching for S3 buckets with tag Project=$TAG_PROJECT..."

#   BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

#   for BUCKET in $BUCKETS; do
#     TAG=$(aws s3api get-bucket-tagging --bucket "$BUCKET" --query "TagSet[?Key=='Project'].Value" --output text 2>/dev/null || true)
#     if [[ "$TAG" == "$TAG_PROJECT" ]]; then
#       log "Deleting all objects in bucket: $BUCKET"
#       aws s3 rm "s3://$BUCKET" --recursive
#       log "Deleting bucket: $BUCKET"
#       aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
#     fi
#   done
# }

cleanup_s3_buckets() {
  # Install jq if not installed
  if ! command -v jq >/dev/null 2>&1; then
    log "jq not found. Installing jq..."
    sudo apt-get update && sudo apt-get install -y jq
  fi

  log "Searching for S3 buckets with tag Project=$TAG_PROJECT..."

  BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

  for BUCKET in $BUCKETS; do
    TAG=$(aws s3api get-bucket-tagging --bucket "$BUCKET" --query "TagSet[?Key=='Project'].Value" --output text 2>/dev/null || true)
    if [[ "$TAG" == "$TAG_PROJECT" ]]; then
      log "Deleting all objects (including all versions) in bucket: $BUCKET"

      # Delete all versions if versioning is enabled
      VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json)
      if [[ "$VERSIONS" != "[]" ]]; then
        for ROW in $(echo "$VERSIONS" | jq -c '.[]'); do
          KEY=$(echo "$ROW" | jq -r '.Key')
          VERSION_ID=$(echo "$ROW" | jq -r '.VersionId')
          aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION_ID"
        done
      fi

      # Delete all delete markers (also needed for versioned buckets)
      DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$BUCKET" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json)
      if [[ "$DELETE_MARKERS" != "[]" ]]; then
        for ROW in $(echo "$DELETE_MARKERS" | jq -c '.[]'); do
          KEY=$(echo "$ROW" | jq -r '.Key')
          VERSION_ID=$(echo "$ROW" | jq -r '.VersionId')
          aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION_ID"
        done
      fi

      log "Deleting bucket: $BUCKET"
      aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
    fi
  done
}


cleanup_security_groups() {
  log "Searching for security groups with tag Project=$TAG_PROJECT..."

  SG_IDS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=tag:Project,Values=$TAG_PROJECT" \
    --query "SecurityGroups[].GroupId" \
    --output text)

  for SG_ID in $SG_IDS; do
    # Skip default SG
    if [[ "$SG_ID" != "default" ]]; then
      log "Deleting security group: $SG_ID"
      aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
    fi
  done
}

# MAIN EXECUTION

log "Resource Cleanup Script Started"

check_prerequisites
cleanup_ec2_instances
cleanup_key_pairs
cleanup_s3_buckets
cleanup_security_groups

log "Resource Cleanup Script Completed"
