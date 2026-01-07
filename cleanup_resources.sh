#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIGURATION ----------------
LOG_FILE="cleanup_resources.log"
TAG_PROJECT="AutomationLab"
REGION=$(aws configure get region)

# ---------------- LOG FUNCTION ----------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}

# ---------------- PREREQUISITES ----------------
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

# ---------------- CLEANUP FUNCTIONS ----------------
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
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION" \
      --query 'TerminatingInstances[*].InstanceId' --output text >/dev/null
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
    log "EC2 instances terminated."
  else
    log "No EC2 instances found."
  fi
}

cleanup_key_pairs() {
  log "Searching for EC2 key pairs starting with 'automationlab-key'..."
  for KEY in $(aws ec2 describe-key-pairs --region "$REGION" \
               --query "KeyPairs[].KeyName" --output text); do
    if [[ "$KEY" == automationlab-key* ]]; then
      log "Deleting key pair: $KEY"
      aws ec2 delete-key-pair --key-name "$KEY" --region "$REGION" >/dev/null
      rm -f "${KEY}.pem" 2>/dev/null || true
    fi
  done
}

cleanup_s3_buckets() {
  log "Searching for S3 buckets with tag Project=$TAG_PROJECT..."
  BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

  for BUCKET in $BUCKETS; do
    TAG=$(aws s3api get-bucket-tagging \
      --bucket "$BUCKET" \
      --query "TagSet[?Key=='Project'].Value" \
      --output text 2>/dev/null || true)

    if [[ "$TAG" == "$TAG_PROJECT" ]]; then
      log "Cleaning S3 bucket: $BUCKET"

      # ---- Versions ----
      VERSIONS=$(aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --query 'Versions || []' \
        --output json)

      echo "$VERSIONS" | jq -c '.[]?' | while read -r OBJ; do
        aws s3api delete-object \
          --bucket "$BUCKET" \
          --key "$(echo "$OBJ" | jq -r '.Key')" \
          --version-id "$(echo "$OBJ" | jq -r '.VersionId')" >/dev/null
      done

      # ---- Delete Markers ----
      MARKERS=$(aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --query 'DeleteMarkers || []' \
        --output json)

      echo "$MARKERS" | jq -c '.[]?' | while read -r OBJ; do
        aws s3api delete-object \
          --bucket "$BUCKET" \
          --key "$(echo "$OBJ" | jq -r '.Key')" \
          --version-id "$(echo "$OBJ" | jq -r '.VersionId')" >/dev/null
      done

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
    log "Deleting security group: $SG_ID"
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
  done
}

cleanup_subnets() {
  log "Searching for subnets with tag Project=$TAG_PROJECT..."
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=tag:Project,Values=$TAG_PROJECT" \
    --query "Subnets[].SubnetId" \
    --output text)

  for SUBNET_ID in $SUBNET_IDS; do
    log "Deleting subnet: $SUBNET_ID"
    aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION"
  done
}

# ---------------- MAIN ----------------
log "Resource Cleanup Script Started"

check_prerequisites
cleanup_ec2_instances
cleanup_key_pairs
cleanup_s3_buckets
cleanup_security_groups
cleanup_subnets

log "Resource Cleanup Script Completed Successfully"
